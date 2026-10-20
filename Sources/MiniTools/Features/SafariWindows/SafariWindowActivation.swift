import ApplicationServices
import Foundation

/// Synchronous AX work runs on the activation worker, never the main actor.
/// Clock, waiting and AX operations are injected so tests never touch Safari.
struct SafariWindowActivation {
    let isMinimized: () -> Bool?
    let restore: () -> AXError
    let raise: () -> AXError
    let isFrontmost: () -> Bool
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var pause: () -> Void = { Thread.sleep(forTimeInterval: 0.05) }
    var checkCancellation: () throws -> Void = { try Task.checkCancellation() }

    func run() throws {
        try checkCancellation()
        let deadline = now() + 3
        if isMinimized() == true {
            let result = restore()
            guard result == .success || result == .cannotComplete else {
                throw failure("无法恢复已最小化的 Safari 窗口", result)
            }
            // Unminimize is asynchronous; do not raise during the Dock transition.
            while isMinimized() != false {
                try checkCancellation()
                guard now() < deadline else {
                    throw MiniToolsError.processingFailed("Safari 窗口恢复尚未完成，请稍后重试")
                }
                pause()
            }
        }

        for _ in 0..<3 {
            try checkCancellation()
            guard now() < deadline else { break }
            let result = raise()
            if result == .success { return }
            guard result == .cannotComplete else {
                throw failure("无法将 Safari 窗口置于前台", result)
            }
            // CannotComplete may be a reply timeout after the action already succeeded.
            // Require the target's actual restored/focused state before accepting it.
            let observationDeadline = min(deadline, now() + 0.2)
            repeat {
                try checkCancellation()
                if isMinimized() == false && isFrontmost() { return }
                if now() >= observationDeadline { break }
                pause()
            } while true
        }
        throw failure("无法将 Safari 窗口置于前台", .cannotComplete)
    }

    static func activateAll<T>(_ targets: [T], activate: (T) throws -> Void) throws {
        var failures: [String] = []
        for target in targets {
            try Task.checkCancellation()
            do { try activate(target) }
            catch is CancellationError { throw CancellationError() }
            catch { failures.append(error.localizedDescription) }
        }
        guard !failures.isEmpty else { return }
        throw MiniToolsError.processingFailed(
            "\(targets.count - failures.count)/\(targets.count) 个 Safari 窗口已打开；\(failures.count) 个失败：\(failures[0])"
        )
    }

    private func failure(_ message: String, _ status: AXError) -> MiniToolsError {
        .processingFailed("\(message)（错误码 \(status.rawValue)）")
    }
}
