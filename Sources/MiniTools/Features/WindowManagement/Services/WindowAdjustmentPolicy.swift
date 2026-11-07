import Foundation

/// Explicit evidence-based exceptions; all other applications retain the baseline.
enum WindowAdjustmentPolicy: String {
    case baseline
    case compatible

    static let defaultBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.finder", "com.openai.codex",
        "com.openai.chat", "com.tencent.qq", "com.electron.lark", "com.apple.Notes"
    ]

    static func resolve(bundleIdentifier: String?,
                        compatibleApplications: Set<String> = defaultBundleIdentifiers) -> Self {
        guard let bundleIdentifier, compatibleApplications.contains(bundleIdentifier) else { return .baseline }
        return .compatible
    }
}

struct WindowFramePlacement {
    enum Anchor { case leading, center, trailing }
    let horizontal: Anchor
    let vertical: Anchor
    let visible: CGRect
    private let relativePosition: CGPoint?

    init(target: CGRect, visible: CGRect) {
        self.visible = visible
        relativePosition = nil
        func anchor(_ start: CGFloat, _ end: CGFloat, _ low: CGFloat, _ high: CGFloat) -> Anchor {
            if abs(start - low) <= 1, abs(end - high) <= 1 { return .center }
            if abs(start - low) <= 1 { return .leading }
            if abs(end - high) <= 1 { return .trailing }
            return .center
        }
        horizontal = anchor(target.minX, target.maxX, visible.minX, visible.maxX)
        vertical = anchor(target.minY, target.maxY, visible.minY, visible.maxY)
    }

    /// Keep a free-form cross-screen target's relative position if size is constrained.
    init(relativeTarget target: CGRect, visible: CGRect) {
        self.visible = visible
        horizontal = .center
        vertical = .center
        relativePosition = CGPoint(
            x: visible.width > target.width ? min(1, max(0, (target.minX - visible.minX) / (visible.width - target.width))) : 0.5,
            y: visible.height > target.height ? min(1, max(0, (target.minY - visible.minY) / (visible.height - target.height))) : 0.5
        )
    }

    func origin(for size: CGSize) -> CGPoint {
        if let relativePosition {
            return CGPoint(x: visible.minX + relativePosition.x * max(0, visible.width - size.width),
                           y: visible.minY + relativePosition.y * max(0, visible.height - size.height))
        }
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
