import AppKit
import ApplicationServices
import Foundation

struct SafariAXWindowRecord: Equatable {
    let id: String
    let windowTitle: String
    let tabTitle: String
    let wasActiveWindow: Bool
}

enum SafariWindowService {
    private static let safariBundleIdentifier = "com.apple.Safari"
    private static var windowNumberAttribute: CFString { "AXWindowNumber" as CFString }
    private static var menuItemCommandCharacterAttribute: CFString {
        "AXMenuItemCmdChar" as CFString
    }
    private static var menuItemCommandModifiersAttribute: CFString {
        "AXMenuItemCmdModifiers" as CFString
    }
    private static let pathCache = SafariWindowPathCache()
    private static let menuItemRole = "AXMenuItem"

    static func fetchWindows() throws -> [SafariWindowItem] {
        try ResponsivenessMetrics.measure("SafariWindowScan") { try readWindows() }
    }

    private static func readWindows() throws -> [SafariWindowItem] {
        try AccessibilityAuthorization.requirePermission()
        let (application, axApplication) = try safariApplication()
        let budget = SafariWindowScanBudget()
        try budget.check()
        let windows = try ResponsivenessMetrics.measure("SafariEnumerateWindows") { try accessibilityWindows(of: axApplication) }
        let focusedWindow = AccessibilityClient.element(
            from: axApplication,
            attribute: kAXFocusedWindowAttribute as CFString
        )

        let pid = processIdentity(for: application)
        let cachedPaths = pathCache.snapshot(for: pid)
        var updatedPaths: [String: SafariWindowPathCache.Entry] = [:]
        var nodeReads = 0
        var completed = false
        defer {
            // Preserve successful lookups even if a later window exceeds the budget.
            // A complete scan also prunes paths for closed windows.
            pathCache.replace(completed ? updatedPaths : cachedPaths.merging(updatedPaths) { _, new in new }, for: pid)
            ResponsivenessMetrics.count("SafariAXNodes", nodeReads)
        }
        var records: [SafariAXWindowRecord] = []
        for window in windows {
            try budget.check()
            let attributes = try readAttributes(window, names: [
                kAXTitleAttribute, kAXIdentifierAttribute, kAXMainAttribute, "AXWindowNumber"
            ])
            guard let identifier = windowIdentifier(attributes: attributes, processIdentity: pid) else { continue }
            let windowTitle = attributes[kAXTitleAttribute] as? String ?? ""
            let cachedPath = cachedPaths[identifier].flatMap { $0.title == windowTitle ? $0.path : nil }
            let webArea = try ResponsivenessMetrics.measure("SafariWebAreaLookup") {
                try SafariWebAreaLocator.locate(
                root: window, cachedPath: cachedPath,
                read: { element in
                    nodeReads += 1
                    let values = try readAttributes(element, names: [
                        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute
                    ])
                    return SafariTreeNode(role: values[kAXRoleAttribute] as? String,
                        title: values[kAXTitleAttribute] as? String,
                        description: values[kAXDescriptionAttribute] as? String,
                        children: values[kAXChildrenAttribute] as? [AXUIElement] ?? [])
                }, check: budget.check)
            }
            if let webArea { updatedPaths[identifier] = .init(title: windowTitle, path: webArea.path) }
            let accessibilityIdentifier = attributes[kAXIdentifierAttribute] as? String ?? ""
            guard webArea != nil || accessibilityIdentifier.contains("SafariWindow") else { continue }
            records.append(SafariAXWindowRecord(
                id: identifier, windowTitle: attributes[kAXTitleAttribute] as? String ?? "",
                tabTitle: webArea?.title ?? "",
                wasActiveWindow: AccessibilityClient.elementsAreEqual(window, focusedWindow)
                    || (attributes[kAXMainAttribute] as? NSNumber)?.boolValue == true))
        }
        try budget.check()
        completed = true

        _ = application // Keep the running application alive while reading its AX hierarchy.
        return ResponsivenessMetrics.measure("SafariBuildList") { makeWindowItems(from: records) }
    }

    static func activateWindow(id: String) throws {
        try activateWindows(ids: [id])
    }

    static func activateWindows(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try AccessibilityAuthorization.requirePermission()
        let (application, axApplication) = try safariApplication()
        let windows = try accessibilityWindows(of: axApplication)
        let identifiedWindows = windows.compactMap { window in
            windowIdentifier(for: window, processIdentity: processIdentity(for: application)).map { (id: $0, window: window) }
        }
        let targets = ids.compactMap { id in
            identifiedWindows.first(where: { $0.id == id })?.window
        }
        guard !targets.isEmpty else {
            throw MiniToolsError.processingFailed("Safari 窗口已关闭，请重新打开窗口列表")
        }

        _ = application.activate(options: [])
        for target in targets.reversed() {
            try restoreAndRaise(target)
        }
    }

    static func createWindow() throws {
        try AccessibilityAuthorization.requirePermission()

        guard let application = runningSafariApplication() else {
            guard
                let safariURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: safariBundleIdentifier
                ),
                NSWorkspace.shared.open(safariURL)
            else {
                throw MiniToolsError.processingFailed("无法启动 Safari")
            }
            return
        }

        let axApplication = AccessibilityClient.application(
            for: application.processIdentifier
        )
        guard
            let menuBar = AccessibilityClient.element(
                from: axApplication,
                attribute: kAXMenuBarAttribute as CFString
            ),
            let newWindowItem = newWindowMenuItem(in: menuBar)
        else {
            throw MiniToolsError.processingFailed("无法找到 Safari 的“新建窗口”命令")
        }

        let result = AccessibilityClient.perform(
            kAXPressAction as CFString,
            on: newWindowItem
        )
        guard result == .success else {
            throw MiniToolsError.processingFailed(
                "无法新建 Safari 窗口（错误码 \(result.rawValue)）"
            )
        }
        _ = application.activate(options: [])
    }

    private static func restoreAndRaise(_ target: AXUIElement) throws {
        if AccessibilityClient.boolean(
            from: target,
            attribute: kAXMinimizedAttribute as CFString
        ) == true {
            let unminimizeResult = AccessibilityClient.setValue(
                kCFBooleanFalse,
                on: target,
                attribute: kAXMinimizedAttribute as CFString
            )
            guard unminimizeResult == .success else {
                throw MiniToolsError.processingFailed("无法恢复已最小化的 Safari 窗口")
            }
        }

        let raiseResult = AccessibilityClient.perform(kAXRaiseAction as CFString, on: target)
        guard raiseResult == .success else {
            throw MiniToolsError.processingFailed(
                "无法将 Safari 窗口置于前台（错误码 \(raiseResult.rawValue)）"
            )
        }
    }

    static func makeWindowItems(from records: [SafariAXWindowRecord]) -> [SafariWindowItem] {
        records
            .map { record in
                let groupName = tabGroupName(
                    windowTitle: record.windowTitle,
                    tabTitle: record.tabTitle
                )
                return SafariWindowItem(
                    id: record.id,
                    title: groupName ?? displayTitle(
                        windowTitle: record.windowTitle,
                        tabTitle: record.tabTitle
                    ),
                    wasActiveWindow: record.wasActiveWindow,
                    hasTabGroup: groupName != nil
                )
            }
            .sorted { lhs, rhs in
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
            }
    }

    static func displayTitle(windowTitle: String, tabTitle: String) -> String {
        let cleanWindowTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTabTitle = tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTabTitle.isEmpty else {
            return cleanWindowTitle.isEmpty ? "未命名 Safari 窗口" : cleanWindowTitle
        }

        if let groupName = tabGroupName(windowTitle: cleanWindowTitle, tabTitle: cleanTabTitle) {
            return groupName
        }
        return cleanTabTitle
    }

    static func tabGroupName(windowTitle: String, tabTitle: String) -> String? {
        let cleanWindowTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTabTitle = tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTabTitle.isEmpty else { return nil }

        let suffix = " — \(cleanTabTitle)"
        guard cleanWindowTitle.hasSuffix(suffix) else { return nil }
        let groupName = String(cleanWindowTitle.dropLast(suffix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return groupName.isEmpty ? nil : groupName
    }

    private static func safariApplication() throws -> (NSRunningApplication, AXUIElement) {
        guard let application = runningSafariApplication() else {
            throw MiniToolsError.processingFailed("Safari 未运行")
        }
        return (
            application,
            AccessibilityClient.application(for: application.processIdentifier, timeout: 0.15)
        )
    }

    private static func runningSafariApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: safariBundleIdentifier
        ).first
    }

    private static func newWindowMenuItem(in menuBar: AXUIElement) -> AXUIElement? {
        var queue = AccessibilityClient.elements(
            from: menuBar,
            attribute: kAXChildrenAttribute as CFString
        )
        var cursor = 0
        var inspectedElementCount = 0

        while cursor < queue.count, inspectedElementCount < 500 {
            let element = queue[cursor]
            cursor += 1
            inspectedElementCount += 1

            let role = AccessibilityClient.string(
                from: element,
                attribute: kAXRoleAttribute as CFString
            )
            let commandCharacter = AccessibilityClient.string(
                from: element,
                attribute: menuItemCommandCharacterAttribute
            )
            let commandModifiers = AccessibilityClient.integer(
                from: element,
                attribute: menuItemCommandModifiersAttribute
            )
            if role == menuItemRole,
               commandCharacter?.caseInsensitiveCompare("n") == .orderedSame,
               commandModifiers == 0,
               AccessibilityClient.boolean(
                   from: element,
                   attribute: kAXEnabledAttribute as CFString
               ) != false {
                return element
            }

            queue.append(contentsOf: AccessibilityClient.elements(
                from: element,
                attribute: kAXChildrenAttribute as CFString
            ))
        }
        return nil
    }

    private static func accessibilityWindows(of application: AXUIElement) throws -> [AXUIElement] {
        let result = AccessibilityClient.copyValue(
            from: application,
            attribute: kAXWindowsAttribute as CFString
        )
        guard result.status == .success, let windows = result.value as? [AXUIElement] else {
            throw MiniToolsError.processingFailed(
                "无法读取 Safari 窗口（错误码 \(result.status.rawValue)）"
            )
        }
        return windows
    }

    static func currentProcessIdentity() -> String? {
        runningSafariApplication().map(processIdentity)
    }

    private static func processIdentity(for application: NSRunningApplication) -> String {
        "\(application.processIdentifier):\(application.launchDate?.timeIntervalSince1970 ?? 0)"
    }

    private static func windowIdentifier(for window: AXUIElement, processIdentity: String) -> String? {
        guard let attributes = try? readAttributes(window, names: [kAXIdentifierAttribute, "AXWindowNumber"]) else { return nil }
        return windowIdentifier(attributes: attributes, processIdentity: processIdentity)
    }

    private static func windowIdentifier(attributes: [String: Any], processIdentity: String) -> String? {
        if let identifier = attributes[kAXIdentifierAttribute] as? String, !identifier.isEmpty {
            return "process:\(processIdentity):identifier:\(identifier)"
        }
        if let number = attributes["AXWindowNumber"] as? Int {
            return "process:\(processIdentity):window-number:\(number)"
        }
        return nil
    }

    private static func readAttributes(_ element: AXUIElement, names: [String]) throws -> [String: Any] {
        // Set a per-element timeout; the scan budget is a separate, cooperative whole-walk limit.
        AXUIElementSetMessagingTimeout(element, 0.15)
        var output: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &output)
        guard status == .success, let values = output as? [Any] else {
            throw MiniToolsError.processingFailed("无法读取 Safari 窗口（错误码 \(status.rawValue)），请重新打开刷新")
        }
        return Dictionary(uniqueKeysWithValues: zip(names, values))
    }
}
