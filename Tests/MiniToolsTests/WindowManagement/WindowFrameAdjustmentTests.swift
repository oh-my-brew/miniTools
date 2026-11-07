import CoreGraphics
import Foundation
import XCTest
@testable import MiniTools

final class WindowFrameAdjustmentTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)

    // No AX, applications, filesystem, or real waiting. These exercise the
    // convergence engine using only an in-memory window and virtual time.
    private func adjust(_ initial: CGRect, to target: CGRect, acceptsWrites: Bool = true) throws
        -> (WindowFrameAdjustment.Result, [String]) {
        var frame = initial
        var writes: [String] = []
        var clock: TimeInterval = 0
        let result = try WindowFrameAdjustment.run(
            initial: initial, target: target, visible: screen,
            read: { frame },
            position: { point in
                writes.append("position")
                if acceptsWrites { frame.origin = point }
            },
            size: { size in
                writes.append("size")
                if acceptsWrites {
                    // Model an application that clips growth at the screen edge.
                    frame.size = CGSize(width: min(size.width, self.screen.maxX - frame.minX),
                                        height: min(size.height, self.screen.maxY - frame.minY))
                }
            },
            check: {},
            trace: WindowAdjustmentTrace(command: "test", requestedAt: ProcessInfo.processInfo.systemUptime),
            uptime: { clock }, wait: { clock += 0.012 }
        )
        return (result, writes)
    }

    func testNormalResizeCompletesWithoutCompensation() throws {
        let target = CGRect(x: 0, y: 0, width: 600, height: 900)
        let (result, writes) = try adjust(screen, to: target)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.frame, target)
        XCTAssertEqual(writes, ["size"])
    }

    func testGrowthFromBottomRightMovesBeforeResizing() throws {
        let (result, writes) = try adjust(CGRect(x: 600, y: 450, width: 600, height: 450), to: screen)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.frame, screen)
        XCTAssertEqual(writes, ["position", "size"])
    }

    func testMixedTransitionShrinksBeforeMovingAndGrowing() throws {
        let initial = CGRect(x: 0, y: 450, width: 1200, height: 450)
        let target = CGRect(x: 600, y: 0, width: 600, height: 900)
        let (result, writes) = try adjust(initial, to: target)
        XCTAssertEqual(result.outcome, .applied)
        XCTAssertEqual(result.frame, target)
        XCTAssertEqual(writes, ["size", "position", "size"])
    }

    func testRepeatedRejectedWritesReportNoProgress() throws {
        let target = CGRect(x: 0, y: 0, width: 600, height: 900)
        let (result, writes) = try adjust(screen, to: target, acceptsWrites: false)
        XCTAssertEqual(result.outcome, .noProgress)
        XCTAssertEqual(result.frame, screen)
        XCTAssertEqual(writes.count, 2)
    }

    func testSupersededRequestCannotWrite() {
        XCTAssertThrowsError(try WindowFrameAdjustment.run(
            initial: screen, target: CGRect(x: 0, y: 0, width: 600, height: 900), visible: screen,
            read: { XCTFail("Obsolete request must not read"); return self.screen },
            position: { _ in XCTFail("Obsolete request must not move") },
            size: { _ in XCTFail("Obsolete request must not resize") },
            check: { throw CancellationError() },
            trace: WindowAdjustmentTrace(command: "test", requestedAt: ProcessInfo.processInfo.systemUptime)
        )) { XCTAssertTrue($0 is CancellationError) }
    }
}
