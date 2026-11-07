import CoreGraphics
import Foundation
import XCTest
@testable import MiniTools

final class WindowCompatibilityTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)

    /// An asynchronous app: a new AX request cancels the old pending change.
    /// Time advances only via the injected wait closure, never real sleeping.
    private final class Window {
        var frame: CGRect
        var clock: TimeInterval = 0
        var pending: CGRect?
        var due: TimeInterval = 0
        var minimum: CGSize
        var writes = 0
        var delay: TimeInterval = 0.25
        init(_ frame: CGRect, minimum: CGSize = .zero) {
            self.frame = frame; self.minimum = minimum
        }
        func read() -> CGRect {
            if let pending, clock >= due { frame = pending; self.pending = nil }
            return frame
        }
        func position(_ point: CGPoint) {
            let current = read()
            pending = CGRect(x: max(0, min(point.x, 1200 - current.width)),
                             y: max(0, min(point.y, 900 - current.height)),
                             width: current.width, height: current.height)
            due = clock + delay; writes += 1
        }
        func size(_ size: CGSize) {
            let current = read()
            pending = CGRect(origin: current.origin,
                size: CGSize(width: max(minimum.width, min(size.width, 1200 - current.minX)),
                             height: max(minimum.height, min(size.height, 900 - current.minY))))
            due = clock + delay; writes += 1
        }
    }

    private func adjust(_ window: Window, target: CGRect,
                        policy: WindowAdjustmentPolicy = .compatible,
                        check: () throws -> Void = {}) throws -> WindowFrameAdjustment.Result {
        try WindowFrameAdjustment.run(
            target: target, read: { window.read() },
            position: { window.position($0) }, size: { window.size($0) },
            check: check, trace: trace(), policy: policy, initial: window.frame,
            placement: WindowFramePlacement(target: target, visible: screen),
            uptime: { window.clock }, wait: { window.clock += 0.012 }
        )
    }

    func testOnlyExplicitApplicationsUseCompatibility() {
        for app in ["com.apple.Safari", "com.apple.finder", "com.openai.codex", "com.openai.chat",
                    "com.tencent.qq", "com.electron.lark"] {
            XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: app), .compatible)
        }
        for app in [nil, "com.sublimetext.4", "com.tencent.xinWeChat", "com.apple.Numbers", "unknown"] {
            XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: app), .baseline)
        }
    }

    func testBothRightWidthsCompleteDespiteCancellingAXRequests() throws {
        for y in [CGFloat(0), CGFloat(450)] {
            let half = CGRect(x: 600, y: y, width: 600, height: 450)
            let third = CGRect(x: 800, y: y, width: 400, height: 450)
            for (initial, target) in [(half, third), (third, half)] {
                let window = Window(initial)
                let result = try adjust(window, target: target)
                XCTAssertEqual(result.outcome, .applied)
                XCTAssertEqual(result.frame, target)
                XCTAssertLessThan(window.clock, 2)
            }
        }
    }

    func testMovingReleasesTemporaryGrowthRestriction() throws {
        let window = Window(CGRect(x: 600, y: 450, width: 600, height: 450))
        let result = try adjust(window, target: screen)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.frame, screen)
        XCTAssertEqual(window.writes, 3) // refused growth, move, successful growth
    }

    func testMinimumHeightStillAnchorsAtBottom() throws {
        let window = Window(screen, minimum: CGSize(width: 0, height: 600))
        let result = try adjust(window, target: CGRect(x: 0, y: 450, width: 600, height: 450))
        XCTAssertEqual(result.outcome, .adjustedToObservedSize)
        XCTAssertEqual(result.frame, CGRect(x: 0, y: 300, width: 600, height: 600))
    }

    func testQQMinimumWidthAndHeightStillAnchorBottomRight() throws {
        let window = Window(screen, minimum: CGSize(width: 820, height: 580))
        let result = try adjust(window, target: CGRect(x: 800, y: 450, width: 400, height: 450))
        XCTAssertEqual(result.outcome, .adjustedToObservedSize)
        XCTAssertEqual(result.frame, CGRect(x: 380, y: 320, width: 820, height: 580))
    }

    func testNormalPolicyDoesNotAdvanceVirtualTime() throws {
        let window = Window(screen)
        _ = try adjust(window, target: CGRect(x: 600, y: 450, width: 600, height: 450), policy: .baseline)
        XCTAssertEqual(window.clock, 0)
        XCTAssertEqual(window.writes, 3)
    }

    func testCancellationDuringObservationPreventsNextWrite() {
        let window = Window(screen)
        XCTAssertThrowsError(try adjust(window, target: CGRect(x: 600, y: 450, width: 600, height: 450),
                                       check: { if window.clock > 0.05 { throw CancellationError() } })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(window.writes, 1)
    }

    func testAnimationStateRestoredAfterCancellation() {
        var enabled = true
        var writes: [Bool] = []
        XCTAssertThrowsError(try WindowAnimationScope.run(
            assistiveTechnologyEnabled: false, read: { enabled },
            write: { enabled = $0; writes.append($0); return 0 }, trace: trace(),
            body: { suppressed -> Void in
                XCTAssertTrue(suppressed)
                throw CancellationError()
            }
        ))
        XCTAssertTrue(enabled)
        XCTAssertEqual(writes, [false, true])
    }

    func testAnimationScopePreservesUnsupportedDisabledAndAssistiveStates() {
        for original in [Optional<Bool>.none, false, true] {
            for assistive in [false, true] {
                if original == true && !assistive { continue }
                WindowAnimationScope.run(assistiveTechnologyEnabled: assistive, read: { original },
                    write: { _ in XCTFail("Must not alter state"); return 0 }, trace: trace()) {
                        XCTAssertFalse($0)
                    }
            }
        }
    }

    func testTimedOutAnimationSetterStillAttemptsRestoration() {
        var writes: [Bool] = []
        WindowAnimationScope.run(assistiveTechnologyEnabled: false, read: { true },
            write: { writes.append($0); return -25204 }, trace: trace()) { XCTAssertFalse($0) }
        XCTAssertEqual(writes, [false, true])
    }

    private func trace() -> WindowAdjustmentTrace {
        WindowAdjustmentTrace(command: "test", requestedAt: ProcessInfo.processInfo.systemUptime)
    }
}
