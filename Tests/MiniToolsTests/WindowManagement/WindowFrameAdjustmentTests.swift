import CoreGraphics
import Foundation
import XCTest
@testable import MiniTools

final class WindowFrameAdjustmentTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)

    // In-memory windows only. No AX, applications, log files, or real waiting.
    private func adjust(_ initial: CGRect, to target: CGRect,
                        minimum: CGSize = .zero, acceptsWrites: Bool = true) throws
        -> (WindowFrameAdjustment.Result, [String]) {
        var frame = initial
        var steps: [String] = []
        let result = try WindowFrameAdjustment.run(
            target: target,
            read: { steps.append("read"); return frame },
            position: { point in
                steps.append("position")
                if acceptsWrites {
                    // Model edge clamping while the old size is still present.
                    frame.origin = CGPoint(x: min(point.x, self.screen.maxX - frame.width),
                                           y: min(point.y, self.screen.maxY - frame.height))
                }
            },
            size: { size in
                steps.append("size")
                if acceptsWrites {
                    frame.size = CGSize(width: max(minimum.width, size.width),
                                        height: max(minimum.height, size.height))
                }
            },
            check: {}, trace: trace()
        )
        return (result, steps)
    }

    func testFinalPositionRestoresBottomRightAfterShrinking() throws {
        let target = CGRect(x: 600, y: 450, width: 600, height: 450)
        let (result, steps) = try adjust(screen, to: target)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.frame, target)
        XCTAssertEqual(steps, ["position", "size", "position", "read"])
    }

    func testMinimumHeightNeverBlocksBottomPositionWrite() throws {
        let target = CGRect(x: 0, y: 450, width: 600, height: 450)
        let (result, steps) = try adjust(screen, to: target, minimum: CGSize(width: 0, height: 520))
        XCTAssertEqual(result.outcome, .mismatchObserved)
        XCTAssertEqual(result.frame.minY, 380)
        XCTAssertEqual(result.frame.maxY, screen.maxY)
        XCTAssertEqual(steps, ["position", "size", "position", "read"])
    }

    func testBothRightWidthTransitionsUseTheSameBaseline() throws {
        for y in [CGFloat(0), CGFloat(450)] {
            let half = CGRect(x: 600, y: y, width: 600, height: 450)
            let third = CGRect(x: 800, y: y, width: 400, height: 450)
            for (initial, target) in [(half, third), (third, half)] {
                let (result, steps) = try adjust(initial, to: target)
                XCTAssertEqual(result.outcome, .applied)
                XCTAssertEqual(result.frame, target)
                XCTAssertEqual(steps, ["position", "size", "position", "read"])
            }
        }
    }

    func testMismatchIsRecordedWithoutThrowingOrRetrying() throws {
        let target = CGRect(x: 0, y: 0, width: 600, height: 900)
        let (result, steps) = try adjust(screen, to: target, acceptsWrites: false)
        XCTAssertEqual(result.outcome, .mismatchObserved)
        XCTAssertEqual(result.frame, screen)
        XCTAssertEqual(steps, ["position", "size", "position", "read"])
    }

    func testSupersessionAfterFirstWritePreventsLaterWrites() {
        var superseded = false
        var steps: [String] = []
        XCTAssertThrowsError(try WindowFrameAdjustment.run(
            target: screen,
            read: { XCTFail("Superseded request must not observe"); return self.screen },
            position: { _ in steps.append("position"); superseded = true },
            size: { _ in XCTFail("Superseded request must not resize") },
            check: { if superseded { throw CancellationError() } }, trace: trace()
        )) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(steps, ["position"])
    }

    func testAXWriteErrorStillPropagates() {
        enum WriteError: Error { case rejected }
        XCTAssertThrowsError(try WindowFrameAdjustment.run(
            target: screen,
            read: { XCTFail("Failed request must not observe"); return self.screen },
            position: { _ in throw WriteError.rejected },
            size: { _ in XCTFail("Failed request must stop") },
            check: {}, trace: trace()
        )) { XCTAssertTrue($0 is WriteError) }
    }

    private func trace() -> WindowAdjustmentTrace {
        WindowAdjustmentTrace(command: "test", requestedAt: ProcessInfo.processInfo.systemUptime)
    }
}
