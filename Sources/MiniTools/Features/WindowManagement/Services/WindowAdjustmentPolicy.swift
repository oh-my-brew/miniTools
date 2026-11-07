import Foundation

/// Explicit evidence-based exceptions; all other applications retain the baseline.
enum WindowAdjustmentPolicy: String {
    case baseline
    case compatible

    static func resolve(bundleIdentifier: String?) -> Self {
        switch bundleIdentifier {
        case "com.apple.Safari", "com.apple.finder", "com.openai.codex",
             "com.openai.chat", "com.tencent.qq", "com.electron.lark": .compatible
        default: .baseline
        }
    }
}

struct WindowFramePlacement {
    enum Anchor { case leading, center, trailing }
    let horizontal: Anchor
    let vertical: Anchor
    let visible: CGRect

    init(target: CGRect, visible: CGRect) {
        self.visible = visible
        func anchor(_ start: CGFloat, _ end: CGFloat, _ low: CGFloat, _ high: CGFloat) -> Anchor {
            if abs(start - low) <= 1, abs(end - high) <= 1 { return .center }
            if abs(start - low) <= 1 { return .leading }
            if abs(end - high) <= 1 { return .trailing }
            return .center
        }
        horizontal = anchor(target.minX, target.maxX, visible.minX, visible.maxX)
        vertical = anchor(target.minY, target.maxY, visible.minY, visible.maxY)
    }

    func origin(for size: CGSize) -> CGPoint {
        func coordinate(_ anchor: Anchor, _ extent: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            let proposed: CGFloat
            switch anchor {
            case .leading: proposed = low
            case .center: proposed = (low + high - extent) / 2
            case .trailing: proposed = high - extent
            }
            return max(low, min(proposed, max(low, high - extent)))
        }
        return CGPoint(x: coordinate(horizontal, size.width, visible.minX, visible.maxX),
                       y: coordinate(vertical, size.height, visible.minY, visible.maxY))
    }
}

/// Optional, undocumented AX attribute. Failure is non-fatal. Never enable an
/// initially disabled/unsupported state, and always restore a changed state.
enum WindowAnimationScope {
    static func run<T>(
        assistiveTechnologyEnabled: Bool,
        read: () -> Bool?,
        write: (Bool) -> Int32,
        trace: WindowAdjustmentTrace,
        body: (Bool) throws -> T
    ) rethrows -> T {
        let original = read()
        trace.event(original == true ? "enhancedUIEnabled" : original == false
                    ? "enhancedUIDisabled" : "enhancedUIUnavailable")
        guard original == true, !assistiveTechnologyEnabled else {
            if assistiveTechnologyEnabled { trace.event("preservedForAssistiveTechnology") }
            return try body(false)
        }
        let status = write(false)
        trace.event("disableEnhancedUI", axStatus: status)
        // A failed or timed-out setter may still have changed state. Attempt
        // restoration even on that path, including cancellation and AX errors.
        defer { trace.event("restoreEnhancedUI", axStatus: write(true)) }
        return try body(status == 0 && read() == false)
    }
}
