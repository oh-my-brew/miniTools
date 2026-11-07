import Carbon
import CoreGraphics
import XCTest
@testable import MiniTools

final class ComposedWindowLayoutTests: XCTestCase {
    func testSizeCatalogUsesShortAndLongPressTargets() throws {
        let full = try XCTUnwrap(
            ComposedWindowControlCatalog.sizeTarget(for: .fullOrHalfHeight, press: .short)
        )
        let upperHalf = try XCTUnwrap(
            ComposedWindowControlCatalog.sizeTarget(for: .fullOrHalfHeight, press: .long)
        )
        let halfWidth = try XCTUnwrap(
            ComposedWindowControlCatalog.sizeTarget(
                for: .halfOrThirdFullHeight,
                press: .short
            )
        )
        let thirdWidth = try XCTUnwrap(
            ComposedWindowControlCatalog.sizeTarget(
                for: .halfOrThirdFullHeight,
                press: .long
            )
        )

        XCTAssertEqual(full.frame, UnitWindowFrame(0, 0, 1, 1))
        XCTAssertEqual(upperHalf.frame, UnitWindowFrame(0, 0, 1, 0.5))
        XCTAssertEqual(halfWidth.frame, UnitWindowFrame(0.25, 0, 0.5, 1))
        XCTAssertEqual(thirdWidth.frame, UnitWindowFrame(1.0 / 3.0, 0, 1.0 / 3.0, 1))
    }

    func testEachCornerAlignsCorrespondingPointsAndPreservesArbitrarySize() {
        let visible = CGRect(x: -1440, y: 40, width: 1440, height: 900)
        let current = CGRect(x: -1100, y: 200, width: 713, height: 627)
        let expected: [(ComposedWindowPlacement, CGPoint)] = [
            (.upperLeft, CGPoint(x: -1440, y: 40)),
            (.lowerLeft, CGPoint(x: -1440, y: 313)),
            (.upperRight, CGPoint(x: -713, y: 40)),
            (.lowerRight, CGPoint(x: -713, y: 313))
        ]
        for (placement, origin) in expected {
            let target = WindowGeometry.composedPlacementTarget(currentFrame: current, visibleFrame: visible, placement: placement)
            XCTAssertEqual(target.frame, CGRect(origin: origin, size: current.size))
        }
    }

    func testRepeatedCornerPlacementDoesNotCycle() {
        let visible = CGRect(x: 0, y: -900, width: 1200, height: 860)
        for placement in corners {
            let first = WindowGeometry.composedPlacementTarget(
                currentFrame: CGRect(x: 150, y: -700, width: 600, height: 430), visibleFrame: visible, placement: placement)
            let second = WindowGeometry.composedPlacementTarget(currentFrame: first.frame, visibleFrame: visible, placement: placement)
            XCTAssertEqual(second, first)
        }
    }

    func testFullWidthAndFullHeightRequireNoSizeClassification() {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 900)
        for size in [visible.size, CGSize(width: 1200, height: 450), CGSize(width: 800, height: 900)] {
            let current = CGRect(origin: CGPoint(x: 333, y: 222), size: size)
            for placement in corners {
                let frame = WindowGeometry.composedPlacementTarget(currentFrame: current, visibleFrame: visible, placement: placement).frame
                XCTAssertEqual(frame.size, size)
                switch placement {
                case .upperLeft: XCTAssertEqual(frame.origin, visible.origin)
                case .lowerLeft: XCTAssertEqual(frame.minX, visible.minX); XCTAssertEqual(frame.maxY, visible.maxY)
                case .upperRight: XCTAssertEqual(frame.maxX, visible.maxX); XCTAssertEqual(frame.minY, visible.minY)
                case .lowerRight: XCTAssertEqual(frame.maxX, visible.maxX); XCTAssertEqual(frame.maxY, visible.maxY)
                case .center: XCTFail("Unexpected center")
                }
            }
        }
    }

    func testOversizedWindowPreservesSizeAndRequestedCorner() {
        let visible = CGRect(x: 0, y: 20, width: 1200, height: 900)
        let frame = WindowGeometry.composedPlacementTarget(
            currentFrame: CGRect(x: 0, y: 0, width: 1400, height: 1000), visibleFrame: visible, placement: .lowerRight).frame
        XCTAssertEqual(frame, CGRect(x: -200, y: -80, width: 1400, height: 1000))
    }

    func testCenterPreservesSizeIncludingFullWidthHalfHeight() {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 900)
        let frame = WindowGeometry.composedPlacementTarget(
            currentFrame: CGRect(x: 0, y: 0, width: 1200, height: 450), visibleFrame: visible, placement: .center).frame
        XCTAssertEqual(frame, CGRect(x: 100, y: 245, width: 1200, height: 450))
    }

    func testCompatiblePlacementRetainsExplicitAnchorWhenActualSizeDiffers() {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let placement = WindowFramePlacement(composed: .lowerRight, visible: visible)
        // A full-screen target has ambiguous geometric anchors. The selected
        // lower-right anchor must survive an application's actual size limits.
        XCTAssertEqual(placement.origin(for: visible.size), .zero)
        XCTAssertEqual(placement.origin(for: CGSize(width: 800, height: 700)), CGPoint(x: 400, y: 200))
        XCTAssertEqual(placement.origin(for: CGSize(width: 1300, height: 1000)), CGPoint(x: -100, y: -100))
    }

    func testEveryCornerUsesPositionOnlyForBothAdjustmentPolicies() throws {
        let visible = CGRect(x: -1200, y: 20, width: 1200, height: 900)
        for policy in [WindowAdjustmentPolicy.baseline, .compatible] {
            for placement in corners {
                var actual = CGRect(x: -900, y: 100, width: 713, height: 627)
                let target = WindowGeometry.composedPlacementTarget(currentFrame: actual, visibleFrame: visible, placement: placement).frame
                var clock = 0.0
                let result = try WindowFrameAdjustment.run(
                    target: target, read: { actual }, position: { actual.origin = $0 },
                    size: { _ in XCTFail("Corner placement must preserve actual size") }, check: {},
                    trace: WindowAdjustmentTrace(command: "corner", requestedAt: 0),
                    policy: policy, initial: actual, allowsResize: false,
                    placement: WindowFramePlacement(composed: placement, visible: visible),
                    uptime: { clock }, wait: { clock += 0.012 }
                )
                XCTAssertEqual(result.outcome, .applied)
                XCTAssertEqual(actual, target)
            }
        }
    }

    @MainActor
    func testCornerKeysAndExistingCustomHLBindingsArePreserved() throws {
        let suite = "ComposedCornerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let customH = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | optionKey))
        let customL = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(cmdKey | optionKey))
        defaults.set(try JSONEncoder().encode(["leadingPlacement": customH, "trailingPlacement": customL]),
                     forKey: "composedWindowControlShortcuts")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.composedWindowControlShortcut(for: .lowerLeftPlacement), customH)
        XCTAssertEqual(settings.composedWindowControlShortcut(for: .lowerRightPlacement), customL)
        let keys: [(ComposedWindowControlID, Int)] = [(.upperLeftPlacement, kVK_ANSI_U), (.lowerLeftPlacement, kVK_ANSI_J),
                                                     (.upperRightPlacement, kVK_ANSI_I), (.lowerRightPlacement, kVK_ANSI_K)]
        for (id, code) in keys {
            XCTAssertEqual(ComposedWindowControlCatalog.defaultShortcuts[id]?.keyCode, UInt32(code))
            XCTAssertEqual(ComposedWindowControlCatalog.defaultShortcuts[id]?.carbonModifiers, KeyboardShortcut.panelDefault.carbonModifiers)
        }
    }

    private var corners: [ComposedWindowPlacement] { [.upperLeft, .lowerLeft, .upperRight, .lowerRight] }
}
