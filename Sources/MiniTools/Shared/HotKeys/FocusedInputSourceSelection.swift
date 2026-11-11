import Carbon
import Darwin
import Foundation

@MainActor
enum FocusedInputSourceSelection {
    enum Delivery {
        case replied
        case awaitingReply
        case unavailable
        case failed
    }

    enum Route: Equatable {
        case focusedApplication
        case focusedApplicationAwaitingReply
        case local

        var description: String {
            switch self {
            case .focusedApplication: "前台应用切换请求已响应"
            case .focusedApplicationAwaitingReply: "前台应用切换请求已发送，响应超时"
            case .local: "本机输入源 API"
            }
        }
    }

    enum Failure: Error, Equatable {
        case unavailableSource
        case focusChanged
        case cancelled
        case deliveryFailed
        case localSelectionFailed

        var message: String {
            switch self {
            case .unavailableSource: "原输入法已不可用，请先手动选择一种输入法"
            case .focusChanged: "切换期间键盘焦点已改变，已停止后续切换"
            case .cancelled: "输入法切换请求已取消"
            case .deliveryFailed: "前台输入法切换请求发送失败"
            case .localSelectionFailed: "切换输入法失败，请检查输入法是否已启用"
            }
        }
    }

    static func select(
        currentProcess: pid_t,
        focusedProcess: () -> pid_t?,
        isCurrent: () -> Bool,
        deliver: (pid_t) -> Delivery,
        selectLocally: () -> Bool
    ) -> Result<Route, Failure> {
        guard isCurrent() else { return .failure(.cancelled) }
        let focused = focusedProcess()
        if let focused, focused > 0, focused != currentProcess {
            guard isCurrent() else { return .failure(.cancelled) }
            guard focusedProcess() == focused else { return .failure(.focusChanged) }
            guard isCurrent() else { return .failure(.cancelled) }
            let delivery = deliver(focused)
            guard isCurrent() else { return .failure(.cancelled) }
            guard focusedProcess() == focused else { return .failure(.focusChanged) }
            switch delivery {
            case .replied:
                return .success(.focusedApplication)
            case .awaitingReply:
                // A delivered request may still execute after the reply timeout.
                // Sending another selection would race with that request.
                return .success(.focusedApplicationAwaitingReply)
            case .failed:
                return .failure(.deliveryFailed)
            case .unavailable:
                break
            }
        }
        guard isCurrent() else { return .failure(.cancelled) }
        guard focusedProcess() == focused else { return .failure(.focusChanged) }
        guard isCurrent() else { return .failure(.cancelled) }
        return selectLocally() ? .success(.local) : .failure(.localSelectionFailed)
    }
}

/// Ask the keyboard-focus process to update its own text input context.
/// The private TSM protocol is optional; unavailable capability uses TIS.
@MainActor
enum FocusedInputSourceTransport {
    private typealias RemotePort = @convention(c) (
        CFAllocator?, CFString, CFIndex
    ) -> Unmanaged<CFMessagePort>?
    private typealias FlattenSource = @convention(c) (
        TISInputSource, UnsafeMutablePointer<Unmanaged<CFDictionary>?>
    ) -> Bool
    private typealias TypingFocus = @convention(c) () -> pid_t

    private static let remotePort: RemotePort? = symbol("CFMessagePortCreatePerProcessRemote")
    private static let flattenSource: FlattenSource? = symbol("_CreateFlattenedInputSource")
    private static let typingFocus: TypingFocus? = symbol("SLPSGetTypingFocusProcess")

    static func focusedProcessIdentifier() -> pid_t? {
        if let process = typingFocus?(), process > 0 { return process }
        return AccessibilityClient.systemFocusedProcessIdentifier(timeout: 0.025)
    }

    static func send(
        _ source: TISInputSource, to process: pid_t
    ) -> FocusedInputSourceSelection.Delivery {
        guard let remotePort, let flattenSource else { return .unavailable }
        var reference: Unmanaged<CFDictionary>?
        let flattened = flattenSource(source, &reference)
        let properties = reference?.takeRetainedValue()
        guard flattened, let properties,
              let data = try? PropertyListSerialization.data(
                  fromPropertyList: ["tsmInputSourceSelectedInpSrcKey": properties],
                  format: .xml, options: 0
              ),
              let port = remotePort(
                  nil, "com.apple.tsm.portname" as CFString, CFIndex(process)
              )?.takeRetainedValue() else { return .unavailable }
        defer { CFMessagePortInvalidate(port) }

        // The reply run loop can reenter the main actor. The caller checks
        // cancellation and focus again after both bounded waits.
        let status = CFMessagePortSendRequest(
            port, 7, data as CFData, 0.05, 0.05,
            CFRunLoopMode.defaultMode.rawValue, nil
        )
        return delivery(for: status)
    }

    static func delivery(for status: Int32) -> FocusedInputSourceSelection.Delivery {
        switch status {
        case kCFMessagePortSuccess: return .replied
        case kCFMessagePortReceiveTimeout: return .awaitingReply
        default: return .failed
        }
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(address, to: T.self)
    }
}
