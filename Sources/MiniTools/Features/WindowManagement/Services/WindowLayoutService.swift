import AppKit
import ApplicationServices
import Foundation

/// 一次窗口操作命中的循环候选。
struct WindowActionOutcome: Equatable, Sendable {
    let candidateIndex: Int
    let didReachTarget: Bool
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
        let bundleIdentifier: String?
    }

    private enum Action: Sendable {
        case layout(WindowLayoutCommand)
        case center
        case nextScreen

        var id: WindowControlID {
            switch self {
            case .layout(let command): command.id
            case .center: .centerWindow
            case .nextScreen: .moveWindowToNextScreen
            }
        }
    }

    /// Invalidation is independent of the AX worker, including during a blocked
    /// AX call. An obsolete operation cannot issue its next write.
    private final class RequestGate: @unchecked Sendable {
        private let lock = NSLock()
        private var generation: UInt64 = 0

        func issue() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            generation &+= 1
            return generation
        }

        func isCurrent(_ ticket: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return generation == ticket
        }

        func check(_ ticket: UInt64) throws {
            if !isCurrent(ticket) { throw CancellationError() }
        }

        func cancel(_ ticket: UInt64) {
            lock.lock()
            defer { lock.unlock() }
            if generation == ticket { generation &+= 1 }
        }
    }

    private final class Worker: @unchecked Sendable {
        let queue = DispatchQueue(label: "com.omzcj.minitools.window-adjustment", qos: .userInitiated)
        // All AX elements and intent state are confined to queue.
        struct Intent {
            let window: AXUIElement
            let command: WindowControlID
            let target: CGRect
            let visible: CGRect
            let processID: pid_t
        }
        var intent: Intent?
        private let observationQueue = DispatchQueue(label: "com.omzcj.minitools.window-observation", qos: .utility)

        // Only reads cross to this queue; it never issues window/animation writes.
        // All trace data are value snapshots, not the mutable worker trace.
        private struct Observation: @unchecked Sendable {
            let window: AXUIElement
            let windowID: CGWindowID?
            let processID: pid_t
            let ticket: UInt64
            let requestedAt: TimeInterval
            let record: WindowAdjustmentTrace.Record
            let readAccessibility: Bool
        }

        private func scheduleObservations(_ observation: Observation) {
            for milliseconds in [250, 750] {
                observationQueue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                    guard gate.isCurrent(observation.ticket) else { return }
                    let server = observation.windowID.flatMap {
                        WindowServerWindowInspector.frame(windowID: $0, processIdentifier: observation.processID)
                    }
                    let ax = observation.readAccessibility ? try? readFrame(of: observation.window) : nil
                    guard gate.isCurrent(observation.ticket) else { return }
                    WindowAdjustmentTrace.appendObservation(
                        from: observation.record, phase: "after\(milliseconds)ms",
                        elapsedMS: (ProcessInfo.processInfo.systemUptime - observation.requestedAt) * 1000,
                        accessibility: ax, windowServer: server
                    )
                }
            }
        }

        func execute(
            _ action: Action,
            frontmost: pid_t?,
            geometries: [WindowLayoutScreenGeometry],
            ticket: UInt64,
            requestedAt: TimeInterval,
            assistiveTechnologyEnabled: Bool
        ) throws -> WindowActionOutcome {
            let trace = WindowAdjustmentTrace(command: action.id.rawValue, requestedAt: requestedAt)
            var lastFrame: CGRect?
            defer {
                // Only a superseded pending intention can drive the next cycle.
                // Completed, failed or manually restarted operations use actual geometry.
                if gate.isCurrent(ticket) { intent = nil }
            }
            do {
                // Count successive cycle presses even when their intermediate
                // writes are superseded, without re-querying AX for every queued press.
                if !gate.isCurrent(ticket), let pending = intent,
                   pending.processID == frontmost,
                   case .layout(let command) = action, command.id == pending.command {
                    let targets = command.frames.map { WindowGeometry.targetFrame(for: $0, in: pending.visible) }
                    if let next = WindowGeometry.nextTarget(currentFrame: pending.target, candidates: targets) {
                        intent = Intent(window: pending.window, command: pending.command, target: next,
                                        visible: pending.visible, processID: pending.processID)
                        trace.plan(initial: pending.target, target: next, visible: pending.visible)
                        trace.event("coalescedPendingIntent")
                        throw CancellationError()
                    }
                }
                trace.event("resolveApplication")
                let application = try activeApplication(frontmostProcessIdentifier: frontmost)
                trace.identify(processID: application.processIdentifier, application: application.bundleIdentifier,
                               windowID: nil, frameSource: "unresolved")
                trace.event("resolveWindow")
                let window = try focusedWindow(for: application)
                AXUIElementSetMessagingTimeout(window, 0.25)
                try ensureWindowCanBeAdjusted(window)
                trace.event("readInitialFrame")
                let axFrame = try readFrame(of: window)
                let windowID = WindowServerWindowInspector.matchingWindowID(
                    processIdentifier: application.processIdentifier, accessibilityFrame: axFrame,
                    diagnostic: { trace.event($0, frame: $1) }
                )
                trace.identify(processID: application.processIdentifier,
                               application: application.bundleIdentifier, windowID: windowID,
                               frameSource: windowID == nil ? "accessibilityOnly" : "windowServer")
                func read() throws -> CGRect {
                    let value: CGRect
                    if let windowID {
                        guard let observed = WindowServerWindowInspector.frame(
                            windowID: windowID, processIdentifier: application.processIdentifier
                        ) else { throw WindowLayoutError.unreadableWindowFrame }
                        value = observed
                    } else {
                        value = try readFrame(of: window)
                    }
                    lastFrame = value
                    return value
                }
                trace.event("initialAccessibilityFrame", frame: axFrame)
                let policy = WindowAdjustmentPolicy.resolve(bundleIdentifier: application.bundleIdentifier)
                trace.event(policy.rawValue)
                let current = try read()
                let visible = WindowGeometry.screenGeometry(for: current, geometries: geometries).visibleFrame
                var target: CGRect
                var candidateIndex = 0
                var destination = visible
                switch action {
                case .layout(let command):
                    let targets = command.frames.map { WindowGeometry.targetFrame(for: $0, in: visible) }
                    let cycleFrame: CGRect
                    if let intent, CFEqual(intent.window, window), intent.command == action.id,
                       intent.visible == visible {
                        cycleFrame = intent.target
                    } else {
                        cycleFrame = current
                    }
                    guard let next = WindowGeometry.nextTarget(currentFrame: cycleFrame, candidates: targets) else {
                        throw WindowLayoutError.unreadableWindowFrame
                    }
                    target = next
                    candidateIndex = targets.firstIndex(of: next) ?? 0
                case .center:
                    target = WindowGeometry.centeredFrame(current, in: visible)
                case .nextScreen:
                    guard geometries.count > 1 else { throw WindowLayoutError.notEnoughScreens }
                    let index = WindowGeometry.screenIndex(containing: current.center, geometries: geometries)
                    destination = geometries[(index + 1) % geometries.count].visibleFrame
                    // Cross-screen size semantics intentionally remain unchanged.
                    target = WindowGeometry.frameByMoving(current, from: visible, to: destination)
                }
                intent = Intent(window: window, command: action.id, target: target, visible: visible,
                                processID: application.processIdentifier)
                trace.plan(initial: current, target: target, visible: destination)
                trace.event("resolved", frame: current)
                try gate.check(ticket)
                let adjust: (Bool) throws -> WindowFrameAdjustment.Result = { suppressed in
                    try WindowFrameAdjustment.run(
                        target: target,
                        read: read,
                        position: { point in
                            try gate.check(ticket)
                            trace.event("writePositionRequested")
                            let status = try setPosition(point, of: window)
                            trace.event("writePosition", axStatus: status.rawValue)
                            try gate.check(ticket)
                        },
                        size: { size in
                            try gate.check(ticket)
                            trace.event("writeSizeRequested")
                            let status = try setSize(size, of: window)
                            trace.event("writeSize", axStatus: status.rawValue)
                            try gate.check(ticket)
                        },
                        check: { try gate.check(ticket) }, trace: trace,
                        policy: policy, initial: current,
                        placement: { if case .nextScreen = action { return nil }
                                     return WindowFramePlacement(target: target, visible: destination) }(),
                        authoritativeRead: windowID != nil, animationsSuppressed: suppressed
                    )
                }
                let result: WindowFrameAdjustment.Result
                if policy == .compatible {
                    let appElement = AccessibilityClient.application(for: application.processIdentifier, timeout: 0.25)
                    let attribute = "AXEnhancedUserInterface" as CFString
                    result = try WindowAnimationScope.run(
                        assistiveTechnologyEnabled: assistiveTechnologyEnabled,
                        read: { AccessibilityClient.boolean(from: appElement, attribute: attribute) },
                        write: { AccessibilityClient.setValue($0 ? kCFBooleanTrue! : kCFBooleanFalse!,
                                                             on: appElement, attribute: attribute).rawValue },
                        trace: trace, body: adjust
                    )
                } else {
                    result = try adjust(false)
                }
                try gate.check(ticket)
                lastFrame = result.frame
                trace.finish(result.outcome.rawValue, frame: result.frame)
                scheduleObservations(Observation(window: window, windowID: windowID,
                    processID: application.processIdentifier, ticket: ticket,
                    requestedAt: requestedAt, record: trace.snapshot(),
                    readAccessibility: policy == .compatible || windowID == nil))
                return WindowActionOutcome(candidateIndex: candidateIndex,
                                           didReachTarget: result.outcome == .applied)
            } catch is CancellationError {
                trace.finish("superseded", frame: lastFrame)
                throw CancellationError()
            } catch {
                switch error {
                case WindowLayoutError.cannotResizeWindow(let status):
                    trace.event("axFailure", axStatus: status.rawValue)
                case WindowLayoutError.invalidAccessibilityWindowState:
                    trace.event("invalidAccessibilityWindowState")
                case WindowLayoutError.noFocusedWindow:
                    trace.event("noFocusedWindow")
                case WindowLayoutError.unreadableWindowFrame:
                    trace.event("unreadableWindowFrame")
                case WindowLayoutError.fullScreenWindow:
                    trace.event("fullScreenWindow")
                default:
                    trace.event("resolutionFailed")
                }
                trace.finish("failed", frame: lastFrame)
                throw error
            }
        }
    }

    private static let gate = RequestGate()
    private static let worker = Worker()

    @MainActor
    static func applyLayout(_ command: WindowLayoutCommand) async throws -> WindowActionOutcome {
        try await submit(.layout(command))
    }

    @MainActor
    static func moveFocusedWindowToNextScreen() async throws -> WindowActionOutcome {
        try await submit(.nextScreen)
    }

    @MainActor
    static func centerFocusedWindow() async throws -> WindowActionOutcome {
        try await submit(.center)
    }

    @MainActor
    private static func submit(_ action: Action) async throws -> WindowActionOutcome {
        try AccessibilityAuthorization.requirePermission()
        let ticket = gate.issue()
        let requestedAt = ProcessInfo.processInfo.systemUptime
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let geometries = WindowGeometry.screenGeometries()
        let assistiveTechnologyEnabled = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                worker.queue.async {
                    do {
                        continuation.resume(returning: try worker.execute(
                            action, frontmost: frontmost, geometries: geometries,
                            ticket: ticket, requestedAt: requestedAt,
                            assistiveTechnologyEnabled: assistiveTechnologyEnabled
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            gate.cancel(ticket)
        }
    }

    private static func activeApplication(frontmostProcessIdentifier: pid_t?) throws -> TargetApplication {
        let focusedProcessIdentifier = AccessibilityClient.systemFocusedProcessIdentifier(timeout: 0.25)
        let processIdentifiers = WindowTargetResolver.candidateProcessIdentifiers(
            accessibilityFocusedProcessIdentifier: focusedProcessIdentifier,
            frontmostProcessIdentifier: frontmostProcessIdentifier,
            currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        for processIdentifier in processIdentifiers {
            guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { continue }
            let target = TargetApplication(processIdentifier: processIdentifier,
                                           name: application.localizedName ?? "当前应用",
                                           bundleIdentifier: application.bundleIdentifier)
            if processIdentifier == focusedProcessIdentifier,
               processIdentifier != frontmostProcessIdentifier,
               !hasAccessibleWindow(for: target) { continue }
            return target
        }
        throw WindowLayoutError.noActiveApplication
    }

    private static func hasAccessibleWindow(for target: TargetApplication) -> Bool {
        let application = AccessibilityClient.application(for: target.processIdentifier, timeout: 0.25)
        return windowCandidates(from: application).contains {
            $0.role == kAXWindowRole as String
        }
    }

    private static func focusedWindow(for target: TargetApplication) throws -> AXUIElement {
        let application = AccessibilityClient.application(for: target.processIdentifier, timeout: 0.25)
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
        var candidates: [(element: AXUIElement, role: String?)] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            guard let element = AccessibilityClient.element(from: application, attribute: attribute as CFString) else { continue }
            let role = AccessibilityClient.string(from: element, attribute: kAXRoleAttribute as CFString)
            candidates.append((element, role))
            if role == kAXWindowRole as String { return candidates }
        }
        for element in AccessibilityClient.elements(from: application, attribute: kAXWindowsAttribute as CFString) {
            let role = AccessibilityClient.string(from: element, attribute: kAXRoleAttribute as CFString)
            candidates.append((element, role))
            if role == kAXWindowRole as String { break }
        }
        return candidates
    }

    private static func ensureWindowCanBeAdjusted(_ window: AXUIElement) throws {
        if AccessibilityClient.boolean(from: window, attribute: "AXFullScreen" as CFString) == true {
            throw WindowLayoutError.fullScreenWindow
        }
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

    private static func setPosition(_ point: CGPoint, of window: AXUIElement) throws -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { throw WindowLayoutError.unreadableWindowFrame }
        return try set(value, attribute: kAXPositionAttribute as CFString, on: window)
    }

    private static func setSize(_ size: CGSize, of window: AXUIElement) throws -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw WindowLayoutError.unreadableWindowFrame }
        return try set(value, attribute: kAXSizeAttribute as CFString, on: window)
    }

    private static func set(_ value: CFTypeRef, attribute: CFString, on window: AXUIElement) throws -> AXError {
        let result = AccessibilityClient.setValue(value, on: window, attribute: attribute)
        // Keep real AX failures visible; a frame mismatch alone is diagnostic.
        guard result == .success else {
            throw WindowLayoutError.cannotResizeWindow(result)
        }
        return result
    }
}
