import Foundation

/// The common baseline for every application. Calls run consecutively on the
/// serial AX worker: no polling, intermediate frames, or corrective writes.
enum WindowFrameAdjustment {
    enum Outcome: String {
        case applied
        // This is an immediate observation, not proof of a permanent constraint.
        case mismatchObserved
    }

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
        trace: WindowAdjustmentTrace
    ) throws -> Result {
        trace.event("baselinePositionSizePosition")
        try check()
        try position(target.origin)
        try check()
        try size(target.size)
        try check()
        try position(target.origin)
        try check()

        // Read only after all writes. A mismatch is diagnostic information and
        // must never gate movement, initiate retries, or cause a failure toast.
        let actual = try read()
        try check()
        trace.event("sampledImmediately", frame: actual)
        return Result(frame: actual, outcome:
            WindowGeometry.frameFollowUp(actualFrame: actual, targetFrame: target) == .complete
                ? .applied : .mismatchObserved)
    }
}
