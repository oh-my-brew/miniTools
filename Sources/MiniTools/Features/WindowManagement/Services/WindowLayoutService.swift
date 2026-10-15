import AppKit
import ApplicationServices
import Foundation

/// 一次窗口操作命中的循环候选。
struct WindowActionOutcome: Equatable, Sendable {
    let candidateIndex: Int
}

enum WindowLayoutError: LocalizedError {
    case noActiveApplication
    case noFocusedWindow
    case invalidAccessibilityWindowState(String)
    case fullScreenWindow
    case unreadableWindowFrame
    case cannotResizeWindow(AXError)
    case notEnoughScreens
    case cannotReadPointerPosition
    case cannotMovePointer(CGError)

    var errorDescription: String? {
        switch self {
        case .noActiveApplication:
            return "当前没有可调整的活动应用"
        case .noFocusedWindow:
            return "当前应用没有可调整的活动窗口"
        case let .invalidAccessibilityWindowState(applicationName):
            return "\(applicationName) 的辅助功能窗口状态异常，请重启该应用后再试"
        case .fullScreenWindow:
            return "请先退出 macOS 全屏模式再调整窗口"
        case .unreadableWindowFrame:
            return "无法读取当前窗口的位置或尺寸"
        case let .cannotResizeWindow(error):
            return "当前窗口不允许调整（错误码 \(error.rawValue)）"
        case .notEnoughScreens:
            return "当前只检测到一块显示器"
        case .cannotReadPointerPosition:
            return "无法读取当前鼠标位置"
        case let .cannotMovePointer(error):
            return "无法移动鼠标（错误码 \(error.rawValue)）"
        }
    }
}

enum WindowLayoutService {
    private struct TargetApplication: Sendable {
        let processIdentifier: pid_t
        let name: String
    }

    static func applyLayout(_ command: WindowLayoutCommand) async throws -> WindowActionOutcome {
        try AccessibilityAuthorization.requirePermission()
        let application = try await activeApplication()
        let geometries = await WindowGeometry.screenGeometries()

        return try await Task.detached(priority: .userInitiated) {
            let window = try focusedWindow(for: application)
            try ensureWindowCanBeAdjusted(window)

            let currentFrame = try frame(of: window, for: application)
            let visibleFrame = WindowGeometry.screenGeometry(
                for: currentFrame,
                geometries: geometries
            ).visibleFrame
            let targets = command.frames.map {
                WindowGeometry.targetFrame(for: $0, in: visibleFrame)
            }
            guard let target = WindowGeometry.nextTarget(
                currentFrame: currentFrame,
                candidates: targets
            ) else {
                throw WindowLayoutError.unreadableWindowFrame
            }
            try setFrame(
                target,
                of: window,
                visibleFrame: visibleFrame,
                processIdentifier: application.processIdentifier
            )
            return WindowActionOutcome(candidateIndex: targets.firstIndex(of: target) ?? 0)
        }.value
    }

    static func applyComposedSize(_ target: ComposedWindowSizeTarget) async throws {
        try AccessibilityAuthorization.requirePermission()
        let application = try await activeApplication()
        let geometries = await WindowGeometry.screenGeometries()

        try await Task.detached(priority: .userInitiated) {
            let window = try focusedWindow(for: application)
            try ensureWindowCanBeAdjusted(window)

            let currentFrame = try frame(of: window, for: application)
            let visibleFrame = WindowGeometry.screenGeometry(
                for: currentFrame,
                geometries: geometries
            ).visibleFrame
            try setFrame(
                WindowGeometry.targetFrame(for: target.frame, in: visibleFrame),
                of: window,
                visibleFrame: visibleFrame,
                processIdentifier: application.processIdentifier
            )
        }.value
    }

    static func applyComposedPlacement(
        _ placement: ComposedWindowPlacement
    ) async throws -> ComposedWindowPlacementTarget? {
        try AccessibilityAuthorization.requirePermission()
        let application = try await activeApplication()
        let geometries = await WindowGeometry.screenGeometries()

        return try await Task.detached(priority: .userInitiated) {
            let window = try focusedWindow(for: application)
            try ensureWindowCanBeAdjusted(window)

            let currentFrame = try frame(of: window, for: application)
            let visibleFrame = WindowGeometry.screenGeometry(
                for: currentFrame,
                geometries: geometries
            ).visibleFrame
            guard let target = WindowGeometry.composedPlacementTarget(
                currentFrame: currentFrame,
                visibleFrame: visibleFrame,
                placement: placement
            ) else {
                return nil
            }
            try correctPositionUntilStable(
                initialFrame: currentFrame,
                targetFrame: target.frame,
                window: window,
                processIdentifier: application.processIdentifier
            )
            return target
        }.value
    }

    static func moveFocusedWindowToNextScreen() async throws -> WindowActionOutcome {
        try AccessibilityAuthorization.requirePermission()
        let application = try await activeApplication()
        let geometries = await WindowGeometry.screenGeometries()

        return try await Task.detached(priority: .userInitiated) {
            let window = try focusedWindow(for: application)
            try ensureWindowCanBeAdjusted(window)

            let currentFrame = try frame(of: window, for: application)
            guard geometries.count > 1 else { throw WindowLayoutError.notEnoughScreens }
            let currentIndex = WindowGeometry.screenIndex(
                containing: currentFrame.center,
                geometries: geometries
            )
            let nextIndex = (currentIndex + 1) % geometries.count
            let destination = geometries[nextIndex]
            let target = WindowGeometry.frameByMoving(
                currentFrame,
                from: geometries[currentIndex].visibleFrame,
                to: destination.visibleFrame
            )
            try setFrame(
                target,
                of: window,
                visibleFrame: destination.visibleFrame,
                processIdentifier: application.processIdentifier
            )
            return WindowActionOutcome(candidateIndex: 0)
        }.value
    }

    static func centerFocusedWindow() async throws -> WindowActionOutcome {
        try AccessibilityAuthorization.requirePermission()
        let application = try await activeApplication()
        let geometries = await WindowGeometry.screenGeometries()

        return try await Task.detached(priority: .userInitiated) {
            let window = try focusedWindow(for: application)
            try ensureWindowCanBeAdjusted(window)

            let currentFrame = try frame(of: window, for: application)
            let visibleFrame = WindowGeometry.screenGeometry(
                for: currentFrame,
                geometries: geometries
            ).visibleFrame
            try setFrame(
                WindowGeometry.centeredFrame(currentFrame, in: visibleFrame),
                of: window,
                visibleFrame: visibleFrame,
                processIdentifier: application.processIdentifier
            )
            return WindowActionOutcome(candidateIndex: 0)
        }.value
    }

    @MainActor
    private static func activeApplication() throws -> TargetApplication {
        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        let focusedProcessIdentifier = AccessibilityClient.systemFocusedProcessIdentifier()
        let processIdentifiers = WindowTargetResolver.candidateProcessIdentifiers(
            accessibilityFocusedProcessIdentifier: focusedProcessIdentifier,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )

        for processIdentifier in processIdentifiers {
            guard let application = NSRunningApplication(
                processIdentifier: processIdentifier
            ) else {
                continue
            }
            let target = TargetApplication(
                processIdentifier: processIdentifier,
                name: application.localizedName ?? "当前应用"
            )

            // A non-activating panel can own the system keyboard focus while a
            // different application remains frontmost. Prefer it only when its
            // AX tree exposes a real window; otherwise preserve the established
            // frontmost-application behavior.
            if processIdentifier == focusedProcessIdentifier,
               processIdentifier != frontmostProcessIdentifier,
               !hasAccessibleWindow(for: target) {
                continue
            }
            return target
        }
        throw WindowLayoutError.noActiveApplication
    }

    private static func hasAccessibleWindow(for target: TargetApplication) -> Bool {
        let application = AccessibilityClient.application(for: target.processIdentifier)
        return windowCandidates(from: application).contains {
            $0.role == kAXWindowRole as String
        }
    }

    private static func focusedWindow(for target: TargetApplication) throws -> AXUIElement {
        let application = AccessibilityClient.application(for: target.processIdentifier)
        let initialCandidates = windowCandidates(from: application)
        if let window = initialCandidates.first(where: {
            $0.role == kAXWindowRole as String
        })?.element {
            return window
        }

        let hasVisibleWindow = WindowServerWindowInspector.hasVisibleWindow(
            processIdentifier: target.processIdentifier
        )
        guard hasVisibleWindow else { throw WindowLayoutError.noFocusedWindow }

        // A foreground transition can briefly expose the application before its
        // focused window. Retry once before classifying the AX tree as stale.
        Thread.sleep(forTimeInterval: 0.04)
        let retryCandidates = windowCandidates(from: application)
        if let window = retryCandidates.first(where: {
            $0.role == kAXWindowRole as String
        })?.element {
            return window
        }

        let candidateRoles = (initialCandidates + retryCandidates).compactMap(\.role)
        if WindowAccessibilityHealth.isInvalid(
            candidateRoles: candidateRoles,
            hasVisibleWindow: true
        ) {
            throw WindowLayoutError.invalidAccessibilityWindowState(target.name)
        }
        throw WindowLayoutError.noFocusedWindow
    }

    private static func windowCandidates(
        from application: AXUIElement
    ) -> [(element: AXUIElement, role: String?)] {
        let directCandidates = [
            AccessibilityClient.element(
                from: application,
                attribute: kAXFocusedWindowAttribute as CFString
            ),
            AccessibilityClient.element(
                from: application,
                attribute: kAXMainWindowAttribute as CFString
            )
        ].compactMap { $0 }
        let candidates = directCandidates + AccessibilityClient.elements(
            from: application,
            attribute: kAXWindowsAttribute as CFString
        )
        let candidatesWithRoles = candidates.map { element in
            (
                element: element,
                role: AccessibilityClient.string(
                    from: element,
                    attribute: kAXRoleAttribute as CFString
                )
            )
        }
        return candidatesWithRoles
    }

    private static func ensureWindowCanBeAdjusted(_ window: AXUIElement) throws {
        if AccessibilityClient.boolean(from: window, attribute: "AXFullScreen" as CFString) == true {
            throw WindowLayoutError.fullScreenWindow
        }
    }

    private static func frame(
        of window: AXUIElement,
        for application: TargetApplication
    ) throws -> CGRect {
        let accessibilityFrame: CGRect
        do {
            accessibilityFrame = try readFrame(of: window)
        } catch WindowLayoutError.unreadableWindowFrame {
            Thread.sleep(forTimeInterval: 0.04)
            if let recoveredFrame = try? readFrame(of: window) {
                accessibilityFrame = recoveredFrame
            } else {
                if WindowServerWindowInspector.hasVisibleWindow(
                    processIdentifier: application.processIdentifier
                ) {
                    throw WindowLayoutError.invalidAccessibilityWindowState(application.name)
                }
                throw WindowLayoutError.unreadableWindowFrame
            }
        }

        // Some applications report the last requested AX frame instead of the
        // actual constrained frame. WindowServer is the source of truth for
        // deciding which layout candidate should be selected next.
        return WindowServerWindowInspector.frontmostVisibleWindowFrame(
            processIdentifier: application.processIdentifier
        ) ?? accessibilityFrame
    }

    private static func readFrame(of window: AXUIElement) throws -> CGRect {
        let positionResult = AccessibilityClient.copyValue(
            from: window,
            attribute: kAXPositionAttribute as CFString
        )
        let sizeResult = AccessibilityClient.copyValue(
            from: window,
            attribute: kAXSizeAttribute as CFString
        )
        guard
            positionResult.status == .success,
            sizeResult.status == .success,
            let positionValue = positionResult.value,
            let sizeValue = sizeResult.value,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            throw WindowLayoutError.unreadableWindowFrame
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
            AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
        else {
            throw WindowLayoutError.unreadableWindowFrame
        }
        return CGRect(origin: position, size: size)
    }

    private static func setFrame(
        _ frame: CGRect,
        of window: AXUIElement,
        visibleFrame: CGRect,
        processIdentifier: pid_t
    ) throws {
        let initialFrame = WindowServerWindowInspector.frontmostVisibleWindowFrame(
            processIdentifier: processIdentifier
        ) ?? (try? readFrame(of: window))
        guard let initialFrame else { throw WindowLayoutError.unreadableWindowFrame }

        let mutationOrder = WindowGeometry.frameMutationOrder(
            currentFrame: initialFrame,
            targetFrame: frame,
            visibleFrame: visibleFrame
        )
        let resizedFrame: CGRect
        switch mutationOrder {
        case .positionThenSize:
            let positionedFrame = try correctPositionUntilStable(
                initialFrame: initialFrame,
                targetFrame: frame,
                window: window,
                processIdentifier: processIdentifier
            )
            resizedFrame = try resizeUntilAccepted(
                initialFrame: positionedFrame,
                targetFrame: frame,
                window: window,
                processIdentifier: processIdentifier
            )
        case .sizeThenPosition:
            resizedFrame = try resizeUntilAccepted(
                initialFrame: initialFrame,
                targetFrame: frame,
                window: window,
                processIdentifier: processIdentifier
            )
        }

        // A delayed resize can still shift the origin, so verify placement at
        // the end regardless of the selected mutation order.
        try correctPositionUntilStable(
            initialFrame: resizedFrame,
            targetFrame: frame,
            window: window,
            processIdentifier: processIdentifier
        )
    }

    private static func setPosition(
        _ point: CGPoint,
        of window: AXUIElement
    ) throws {
        var position = point
        guard let value = AXValueCreate(.cgPoint, &position) else {
            throw WindowLayoutError.unreadableWindowFrame
        }
        try set(value, attribute: kAXPositionAttribute as CFString, on: window)
    }

    private static func waitForFrameToSettle(
        initialFrame: CGRect?,
        targetFrame: CGRect,
        window: AXUIElement,
        processIdentifier: pid_t
    ) -> CGRect? {
        guard let initialFrame else {
            Thread.sleep(forTimeInterval: 0.2)
            return currentFrame(of: window, processIdentifier: processIdentifier)
        }

        var tracker = WindowFrameSettlementTracker(
            initialFrame: initialFrame,
            targetFrame: targetFrame
        )
        var latestFrame = initialFrame
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8

        repeat {
            Thread.sleep(forTimeInterval: 0.025)
            guard let frame = currentFrame(
                of: window,
                processIdentifier: processIdentifier
            ) else {
                continue
            }
            latestFrame = frame
            if tracker.record(frame) {
                return frame
            }
        } while ProcessInfo.processInfo.systemUptime < deadline

        return latestFrame
    }

    @discardableResult
    private static func correctPositionUntilStable(
        initialFrame: CGRect,
        targetFrame: CGRect,
        window: AXUIElement,
        processIdentifier: pid_t
    ) throws -> CGRect {
        var actualFrame = initialFrame

        // A resize can arrive in separate width and height phases. Even after
        // the size appears stable, Safari may apply one final origin change.
        // Verify the WindowServer frame after each correction so one shortcut
        // invocation converges on the requested position.
        for _ in 0..<3 {
            guard let correctedPosition = WindowGeometry.correctedOriginAfterApplyingFrame(
                actualFrame: actualFrame,
                targetFrame: targetFrame
            ) else {
                return actualFrame
            }
            try setPosition(correctedPosition, of: window)
            Thread.sleep(forTimeInterval: 0.08)
            guard let refreshedFrame = currentFrame(
                of: window,
                processIdentifier: processIdentifier
            ) else {
                return actualFrame
            }
            actualFrame = refreshedFrame
        }
        return actualFrame
    }

    private static func resizeUntilAccepted(
        initialFrame: CGRect,
        targetFrame: CGRect,
        window: AXUIElement,
        processIdentifier: pid_t
    ) throws -> CGRect {
        guard let correctedSize = WindowGeometry.correctedSizeAfterApplyingFrame(
            actualFrame: initialFrame,
            targetFrame: targetFrame
        ) else {
            return initialFrame
        }
        try setSize(correctedSize, of: window)

        let settledFrame = waitForFrameToSettle(
            initialFrame: initialFrame,
            targetFrame: targetFrame,
            window: window,
            processIdentifier: processIdentifier
        ) ?? initialFrame
        return try retrySizeUntilAccepted(
            initialFrame: settledFrame,
            targetFrame: targetFrame,
            window: window,
            processIdentifier: processIdentifier
        )
    }

    private static func retrySizeUntilAccepted(
        initialFrame: CGRect,
        targetFrame: CGRect,
        window: AXUIElement,
        processIdentifier: pid_t
    ) throws -> CGRect {
        var actualFrame = initialFrame

        // Safari can acknowledge an AXSize write before both dimensions reach
        // their final values. Retry the requested size within this invocation;
        // bounded retries also avoid hanging on applications with hard minimums.
        for _ in 0..<2 {
            guard let correctedSize = WindowGeometry.correctedSizeAfterApplyingFrame(
                actualFrame: actualFrame,
                targetFrame: targetFrame
            ) else {
                return actualFrame
            }
            try setSize(correctedSize, of: window)
            Thread.sleep(forTimeInterval: 0.12)
            guard let refreshedFrame = currentFrame(
                of: window,
                processIdentifier: processIdentifier
            ) else {
                return actualFrame
            }
            actualFrame = refreshedFrame
        }
        return actualFrame
    }

    private static func setSize(
        _ size: CGSize,
        of window: AXUIElement
    ) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw WindowLayoutError.unreadableWindowFrame
        }
        try set(value, attribute: kAXSizeAttribute as CFString, on: window)
    }

    private static func currentFrame(
        of window: AXUIElement,
        processIdentifier: pid_t
    ) -> CGRect? {
        WindowServerWindowInspector.frontmostVisibleWindowFrame(
            processIdentifier: processIdentifier
        ) ?? (try? readFrame(of: window))
    }

    private static func set(
        _ value: CFTypeRef,
        attribute: CFString,
        on window: AXUIElement
    ) throws {
        let result = AccessibilityClient.setValue(value, on: window, attribute: attribute)
        guard result == .success else {
            throw WindowLayoutError.cannotResizeWindow(result)
        }
    }
}
