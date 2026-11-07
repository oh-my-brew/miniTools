import Foundation

/// Runs only on the dedicated serial AX worker. No application-specific delays.
enum WindowFrameAdjustment {
    enum Outcome: String {
        case applied
        case noProgress
        case timedOut
    }

    struct Result {
        let frame: CGRect
        let outcome: Outcome
    }

    static func run(
        initial: CGRect,
        target: CGRect,
        visible: CGRect,
        read: () throws -> CGRect,
        position: (CGPoint) throws -> Void,
        size: (CGSize) throws -> Void,
        check: () throws -> Void,
        trace: WindowAdjustmentTrace,
        uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wait: () -> Void = { Thread.sleep(forTimeInterval: 0.012) }
    ) throws -> Result {
        let deadline = uptime() + 0.9
        var actual = initial
        var previousAttempt: CGRect?

        func pause() throws {
            try check()
            // This is a dedicated queue, not the main thread or the cooperative pool.
            wait()
            try check()
        }

        func observeDependency(_ ready: (CGRect) -> Bool) throws -> Bool {
            let phaseDeadline = min(deadline, uptime() + 0.18)
            repeat {
                try check()
                actual = try read()
                if ready(actual) { return true }
                if uptime() >= phaseDeadline { return false }
                try pause()
            } while true
        }

        func moveThenResize() throws {
            if WindowGeometry.correctedOriginAfterApplyingFrame(actualFrame: actual, targetFrame: target) != nil {
                try check()
                try position(target.origin)
                // Growing before this move is visible would clip the new size.
                guard try observeDependency({
                    WindowGeometry.correctedOriginAfterApplyingFrame(actualFrame: $0, targetFrame: target) == nil
                }) else { return }
            }
            if WindowGeometry.correctedSizeAfterApplyingFrame(actualFrame: actual, targetFrame: target) != nil {
                try check()
                try size(target.size)
            }
        }

        for attempt in 0..<3 {
            try check()
            if WindowGeometry.frameFollowUp(actualFrame: actual, targetFrame: target) == .complete {
                return Result(frame: actual, outcome: .applied)
            }
            if uptime() >= deadline { break }
            trace.event(attempt == 0 ? "apply" : "compensate", frame: actual)
            let permitted = visible.insetBy(dx: -1, dy: -1)
            let targetAtCurrentOrigin = CGRect(origin: actual.origin, size: target.size)
            let currentAtTargetOrigin = CGRect(origin: target.origin, size: actual.size)
            let changesSize = WindowGeometry.correctedSizeAfterApplyingFrame(actualFrame: actual, targetFrame: target) != nil
            let changesPosition = WindowGeometry.correctedOriginAfterApplyingFrame(actualFrame: actual, targetFrame: target) != nil

            if changesSize, changesPosition,
               !permitted.contains(targetAtCurrentOrigin), !permitted.contains(currentAtTargetOrigin) {
                // Neither direct ordering fits. Shrink only necessary dimensions,
                // move that safe rectangle, then grow to the final dimensions.
                trace.event("bridge")
                let bridge = CGSize(width: min(actual.width, target.width), height: min(actual.height, target.height))
                try check()
                try size(bridge)
                if try observeDependency({ $0.width <= bridge.width + 8 && $0.height <= bridge.height + 8 }) {
                    try moveThenResize()
                }
            } else if WindowGeometry.frameMutationOrder(currentFrame: actual, targetFrame: target, visibleFrame: visible) == .positionThenSize {
                trace.event("positionThenSize")
                try moveThenResize()
            } else {
                trace.event("sizeThenPosition")
                if changesSize {
                    try check()
                    try size(target.size)
                }
                // Only wait between writes when moving the old size would cross
                // the screen edge. Ordinary applications keep the immediate path.
                let mayMove: Bool
                if changesSize, changesPosition, !permitted.contains(currentAtTargetOrigin) {
                    mayMove = try observeDependency({
                        permitted.contains(CGRect(origin: target.origin, size: $0.size))
                    })
                } else {
                    mayMove = true
                }
                if mayMove, changesPosition {
                    try check()
                    try position(target.origin)
                }
            }

            var tracker = WindowFrameSettlementTracker(initialFrame: actual, targetFrame: target, requiredStableSamples: 3)
            var last = actual
            var changedAt = uptime()
            let writtenAt = changedAt
            // Observe while the application progresses; don't overwrite an
            // in-flight resize merely because a fixed fast-path timer expired.
            repeat {
                try check()
                actual = try read()
                let now = uptime()
                if !WindowGeometry.framesAreClose(actual, last, tolerance: 1) {
                    changedAt = now
                    trace.event("observed", frame: actual)
                }
                if WindowGeometry.frameFollowUp(actualFrame: actual, targetFrame: target) == .complete {
                    trace.event("reached", frame: actual)
                    return Result(frame: actual, outcome: .applied)
                }
                let settled = tracker.record(actual)
                if now - writtenAt >= 0.12, now - changedAt >= 0.06,
                   settled || now - changedAt >= 0.12 {
                    break
                }
                last = actual
                if now >= deadline { break }
                try pause()
            } while true

            // Repeatedly stable at the same wrong result is not proof of an app
            // minimum size. Record "noProgress", stop writing, and don't count success.
            if let previousAttempt,
               WindowGeometry.framesAreClose(previousAttempt, actual, tolerance: 1) {
                return Result(frame: actual, outcome: .noProgress)
            }
            previousAttempt = actual
        }
        try check()
        actual = try read()
        return Result(frame: actual, outcome:
            WindowGeometry.frameFollowUp(actualFrame: actual, targetFrame: target) == .complete ? .applied : .timedOut)
    }
}
