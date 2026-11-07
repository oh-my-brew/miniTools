import Foundation

/// Only the explicit compatible policy observes asynchronous dependencies.
enum WindowFrameAdjustment {
    enum Outcome: String { case applied, adjustedToObservedSize, mismatchObserved }
    struct Result {
        let frame: CGRect
        let outcome: Outcome
    }

    static func run(
        target: CGRect,
        read: () throws -> CGRect,
        position: (CGPoint) throws -> Void,
        size: (CGSize) throws -> Void,
        check: () throws -> Void,
        trace: WindowAdjustmentTrace,
        policy: WindowAdjustmentPolicy = .baseline,
        initial: CGRect? = nil,
        placement: WindowFramePlacement? = nil,
        authoritativeRead: Bool = true,
        animationsSuppressed: Bool = false,
        uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wait: () -> Void = { Thread.sleep(forTimeInterval: 0.012) }
    ) throws -> Result {
        guard policy == .compatible, let initial else {
            trace.event("baselinePositionSizePosition")
            try check(); try position(target.origin)
            try check(); try size(target.size)
            try check(); try position(target.origin)
            try check()
            let actual = try read()
            try check()
            trace.event("sampledImmediately", frame: actual)
            return Result(frame: actual, outcome: matches(actual, target) ? .applied : .mismatchObserved)
        }

        trace.event("compatibleAdjustment")
        let deadline = uptime() + 2
        var actual = initial
        let quietPeriod: TimeInterval = animationsSuppressed ? 0.04 : 0.10
        let unchangedGrace: TimeInterval = animationsSuppressed ? 0.06 : 0.35

        func observe(_ ready: (CGRect) -> Bool) throws {
            let started = uptime()
            var changed = started
            var previous = actual
            var hasChanged = false
            repeat {
                try check()
                actual = try read()
                let now = uptime()
                if !WindowGeometry.framesAreClose(actual, previous, tolerance: 1) {
                    changed = now
                    hasChanged = true
                    trace.event("observed", frame: actual)
                }
                if ready(actual), authoritativeRead || now - changed >= quietPeriod { return }
                // An unchanged size can be a minimum OR temporary edge clipping.
                // Moving and then retrying below distinguishes those cases.
                if now - changed >= quietPeriod,
                   (hasChanged || now - started >= unchangedGrace) { return }
                if now >= deadline { trace.event("observationBudgetReached"); return }
                previous = actual
                try check()
                wait()
            } while true
        }

        func resizeIfNeeded() throws {
            guard uptime() < deadline,
                  WindowGeometry.correctedSizeAfterApplyingFrame(actualFrame: actual, targetFrame: target) != nil
            else { return }
            trace.event("compatibleSize")
            try check(); try size(target.size)
            try observe { WindowGeometry.correctedSizeAfterApplyingFrame(actualFrame: $0, targetFrame: target) == nil }
        }

        func move(to origin: CGPoint) throws -> Bool {
            let desired = CGRect(origin: origin, size: actual.size)
            guard uptime() < deadline,
                  WindowGeometry.correctedOriginAfterApplyingFrame(actualFrame: actual, targetFrame: desired,
                                                                   tolerance: 1) != nil else { return false }
            trace.event("compatiblePosition", frame: desired)
            try check(); try position(origin)
            try observe { WindowGeometry.correctedOriginAfterApplyingFrame(actualFrame: $0, targetFrame: desired,
                                                                           tolerance: 1) == nil }
            return true
        }

        // Shrink first when necessary. A refusal at the old origin is not cached
        // as a minimum: reserve room, move, then retry the requested size once.
        try resizeIfNeeded()
        let reserved = CGSize(width: max(actual.width, target.width), height: max(actual.height, target.height))
        let moved = try move(to: placement?.origin(for: reserved) ?? target.origin)
        if moved { try resizeIfNeeded() }

        // Only anchor after the visible size is observed; never skip movement
        // because an application's minimum exceeds a half/third target.
        _ = try move(to: placement?.origin(for: actual.size) ?? target.origin)
        try check()
        actual = try read()
        try check()
        let effective = CGRect(origin: placement?.origin(for: actual.size) ?? target.origin, size: actual.size)
        trace.event("effectiveTarget", frame: effective)
        if matches(actual, target) { return Result(frame: actual, outcome: .applied) }
        if placement != nil, matches(actual, effective) {
            return Result(frame: actual, outcome: .adjustedToObservedSize)
        }
        return Result(frame: actual, outcome: .mismatchObserved)
    }

    private static func matches(_ actual: CGRect, _ target: CGRect) -> Bool {
        WindowGeometry.frameFollowUp(actualFrame: actual, targetFrame: target) == .complete
    }
}
