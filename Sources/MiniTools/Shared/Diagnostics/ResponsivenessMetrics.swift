import Foundation
import os

/// Instruments intervals contain fixed stage names, elapsed time and counts only.
/// Never pass clipboard content, window titles, URLs, paths or application identities here.
enum ResponsivenessMetrics {
    private static let signposter = OSSignposter(subsystem: "com.omzcj.minitools", category: "Responsiveness")

    static func measure<T>(_ stage: StaticString, _ operation: () throws -> T) rethrows -> T {
        let interval = signposter.beginInterval(stage)
        defer { signposter.endInterval(stage, interval) }
        return try operation()
    }

    static func event(_ stage: StaticString, since start: ContinuousClock.Instant) {
        let elapsed = start.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        signposter.emitEvent(stage, "elapsed_ms=\(milliseconds)")
    }

    static func count(_ stage: StaticString, _ value: Int) {
        signposter.emitEvent(stage, "count=\(value)")
    }
}
