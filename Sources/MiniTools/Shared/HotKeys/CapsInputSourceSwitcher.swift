import Carbon
import Foundation

@MainActor
final class CapsInputSourceSwitcher {
    struct Client {
        var currentIdentifier: () -> String?
        var asciiIdentifier: () -> String?
        var select: (
            String, () -> Bool
        ) -> Result<FocusedInputSourceSelection.Route, FocusedInputSourceSelection.Failure>
    }

    struct Request: Equatable {
        let previousIdentifier: String
        let targetIdentifier: String
        let route: FocusedInputSourceSelection.Route

        var pendingStatus: String {
            "\(route.description)；正在确认目标输入源 \(targetIdentifier)"
        }

        func confirmationStatus(observed: String?) -> String {
            guard let observed else {
                return "\(route.description)；无法读取当前输入源"
            }
            if observed == targetIdentifier {
                return "已确认目标输入源 \(targetIdentifier)（\(route.description)）；中文输入就绪仍无法确认"
            }
            if observed == previousIdentifier {
                return "目标为 \(targetIdentifier)，当前仍是 \(observed)（\(route.description)）"
            }
            return "目标为 \(targetIdentifier)，当前为其他输入源 \(observed)（\(route.description)）"
        }
    }

    enum Failure: Error, Equatable {
        case unreadable
        case noPreviousSource
        case busy
        case selection(FocusedInputSourceSelection.Failure)

        var message: String {
            switch self {
            case .unreadable: "无法读取当前输入法"
            case .noPreviousSource: "请先手动切换到另一种输入法，再单按 Caps Lock"
            case .busy: "上一次输入法切换请求仍在处理"
            case let .selection(failure): failure.message
            }
        }
    }

    private static let previousIDKey = "capsLockPreviousInputSourceID"
    private let defaults: UserDefaults
    private let client: Client
    private var generation: UInt64 = 0
    private var isSelecting = false

    init(defaults: UserDefaults = .standard, client: Client? = nil) {
        self.defaults = defaults
        self.client = client ?? Self.systemClient
    }

    func currentIdentifier() -> String? {
        client.currentIdentifier()
    }

    func rememberCurrent() {
        guard let current = client.currentIdentifier(),
              let ascii = client.asciiIdentifier(), current != ascii else { return }
        defaults.set(current, forKey: Self.previousIDKey)
    }

    func cancel() {
        generation &+= 1
    }

    func toggle() -> Result<Request, Failure> {
        guard !isSelecting else { return .failure(.busy) }
        guard let current = client.currentIdentifier(),
              let ascii = client.asciiIdentifier() else { return .failure(.unreadable) }
        guard let target = CapsInputSourceChoice.target(
            current: current, ascii: ascii,
            previous: defaults.string(forKey: Self.previousIDKey)
        ) else { return .failure(.noPreviousSource) }

        generation &+= 1
        let ticket = generation
        isSelecting = true
        defer { isSelecting = false }
        let result = client.select(target, { self.generation == ticket })
        guard generation == ticket else { return .failure(.selection(.cancelled)) }
        switch result {
        case let .success(route):
            if target == ascii {
                defaults.set(current, forKey: Self.previousIDKey)
            }
            return .success(Request(
                previousIdentifier: current, targetIdentifier: target, route: route
            ))
        case let .failure(failure):
            return .failure(.selection(failure))
        }
    }

    private static var systemClient: Client {
        Client(
            currentIdentifier: {
                identifier(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
            },
            asciiIdentifier: {
                identifier(of: TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue())
            },
            select: { target, isCurrent in
                let sources = TISCreateInputSourceList(nil, false).takeRetainedValue()
                let candidates = (0..<CFArrayGetCount(sources)).compactMap { index -> TISInputSource? in
                    guard let pointer = CFArrayGetValueAtIndex(sources, index) else { return nil }
                    return Unmanaged<TISInputSource>.fromOpaque(pointer).takeUnretainedValue()
                }
                guard let source = candidates.first(where: { identifier(of: $0) == target }) else {
                    return .failure(.unavailableSource)
                }
                return FocusedInputSourceSelection.select(
                    currentProcess: ProcessInfo.processInfo.processIdentifier,
                    focusedProcess: FocusedInputSourceTransport.focusedProcessIdentifier,
                    isCurrent: isCurrent,
                    deliver: { FocusedInputSourceTransport.send(source, to: $0) },
                    selectLocally: { TISSelectInputSource(source) == noErr }
                )
            }
        )
    }

    private static func identifier(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
