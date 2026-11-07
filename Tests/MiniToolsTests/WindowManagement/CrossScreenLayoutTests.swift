import CoreGraphics
import Foundation
import XCTest
@testable import MiniTools

final class CrossScreenLayoutTests: XCTestCase {
    private let small = CGRect(x: -1200, y: 100, width: 1200, height: 800)
    private let large = CGRect(x: 0, y: 40, width: 1920, height: 1200)

    func testUpperHalfScalesInBothDirections() {
        let topSmall = CGRect(x: -1200, y: 100, width: 1200, height: 400)
        let topLarge = CGRect(x: 0, y: 40, width: 1920, height: 600)
        XCTAssertEqual(WindowGeometry.frameByScaling(topSmall, from: small, to: large), topLarge)
        XCTAssertEqual(WindowGeometry.frameByScaling(topLarge, from: large, to: small), topSmall)
    }

    func testRightLowerQuarterRetainsBothAnchors() {
        let quarter = CGRect(x: -600, y: 500, width: 600, height: 400)
        XCTAssertEqual(WindowGeometry.frameByScaling(quarter, from: small, to: large),
                       CGRect(x: 960, y: 640, width: 960, height: 600))
    }

    func testFreeFormWindowRoundTripHasOnlyRoundingError() {
        let frame = CGRect(x: -1037, y: 243, width: 537, height: 359)
        let moved = WindowGeometry.frameByScaling(frame, from: small, to: large)
        let back = WindowGeometry.frameByScaling(moved, from: large, to: small)
        XCTAssertTrue(WindowGeometry.framesAreClose(frame, back, tolerance: 1))
    }

    func testOversizedAndOffScreenFrameFitsDestination() {
        let oversized = CGRect(x: -1400, y: -100, width: 1600, height: 1200)
        XCTAssertEqual(WindowGeometry.frameByScaling(oversized, from: small, to: large), large)
        let offscreen = CGRect(x: -200, y: 800, width: 600, height: 400)
        XCTAssertEqual(WindowGeometry.frameByScaling(offscreen, from: small, to: large),
                       CGRect(x: 960, y: 640, width: 960, height: 600))
    }

    func testAbsoluteModeStillClampsButDoesNotScaleBackUp() {
        let topLarge = CGRect(x: 0, y: 40, width: 1920, height: 600)
        let moved = WindowGeometry.frameByMoving(topLarge, from: large, to: small)
        XCTAssertEqual(moved.size, CGSize(width: 1200, height: 600))
        XCTAssertEqual(WindowGeometry.frameByMoving(moved, from: small, to: large).size, moved.size)
    }

    func testMinimumSizeKeepsBottomRightAndFreeFormPlacement() {
        let target = CGRect(x: 960, y: 640, width: 960, height: 600)
        let placement = WindowFramePlacement(relativeTarget: target, visible: large)
        XCTAssertEqual(placement.origin(for: CGSize(width: 1100, height: 800)), CGPoint(x: 820, y: 440))
        let free = WindowFramePlacement(relativeTarget: CGRect(x: 240, y: 190, width: 960, height: 600), visible: large)
        XCTAssertEqual(free.origin(for: CGSize(width: 1120, height: 800)), CGPoint(x: 200, y: 140))
        XCTAssertEqual(placement.origin(for: CGSize(width: 2500, height: 1600)), large.origin)
    }

    func testDiagnosticsRetainSourceDestinationModeAndActualFrame() throws {
        let trace = WindowAdjustmentTrace(command: "moveWindowToNextScreen",
                                          requestedAt: ProcessInfo.processInfo.systemUptime)
        trace.crossScreen(source: small, mode: "proportional")
        trace.plan(initial: small, target: large, visible: large)
        trace.event("effectiveTarget", frame: CGRect(x: 0, y: 40, width: 1000, height: 600))
        let record = try JSONDecoder().decode(WindowAdjustmentTrace.Record.self,
                                             from: JSONEncoder().encode(trace.snapshot()))
        XCTAssertEqual(record.sourceVisible, [-1200, 100, 1200, 800])
        XCTAssertEqual(record.visible, [0, 40, 1920, 1200])
        XCTAssertEqual(record.crossScreenMode, "proportional")
        XCTAssertEqual(record.events.last?.frame, [0, 40, 1000, 600])
    }

    @MainActor
    func testSettingDefaultsOffAndPersistsBothStates() throws {
        let suite = "CrossScreenLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.crossScreenPreservesLayout)
        settings.updateCrossScreenPreservesLayout(true)
        XCTAssertTrue(AppSettings(defaults: defaults).crossScreenPreservesLayout)
        settings.updateCrossScreenPreservesLayout(false)
        XCTAssertFalse(AppSettings(defaults: defaults).crossScreenPreservesLayout)
    }
}
