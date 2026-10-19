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

    func testFullSizeIgnoresEveryPlacementCommand() {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 900)

        for placement in [
            ComposedWindowPlacement.leading,
            .trailing,
            .center
        ] {
            XCTAssertNil(WindowGeometry.composedPlacementTarget(
                currentFrame: visible,
                visibleFrame: visible,
                placement: placement
            ))
        }
    }

    func testFullWidthHalfHeightUsesTopAndBottomWithoutCenter() throws {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 900)
        let current = CGRect(x: 100, y: 245, width: 1200, height: 450)

        let top = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .leading
        ))
        let bottom = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .trailing
        ))

        XCTAssertEqual(top.frame, CGRect(x: 100, y: 20, width: 1200, height: 450))
        XCTAssertEqual(bottom.frame, CGRect(x: 100, y: 470, width: 1200, height: 450))
        XCTAssertNil(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .center
        ))
    }

    func testHalfHeightLeadingAndTrailingCommandsCycleWithinTheirOwnSide() throws {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 900)
        let centered = CGRect(x: 400, y: 245, width: 600, height: 450)

        let leftTop = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: centered,
            visibleFrame: visible,
            placement: .leading
        ))
        let leftBottom = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: leftTop.frame,
            visibleFrame: visible,
            placement: .leading
        ))
        let rightTop = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: leftBottom.frame,
            visibleFrame: visible,
            placement: .trailing
        ))
        let rightBottom = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: rightTop.frame,
            visibleFrame: visible,
            placement: .trailing
        ))

        XCTAssertEqual(leftTop.frame.origin, CGPoint(x: 100, y: 20))
        XCTAssertEqual(leftBottom.frame.origin, CGPoint(x: 100, y: 470))
        XCTAssertEqual(rightTop.frame.origin, CGPoint(x: 700, y: 20))
        XCTAssertEqual(rightBottom.frame.origin, CGPoint(x: 700, y: 470))
    }

    func testFullHeightPresetUsesLeftRightAndCenterPositions() throws {
        let visible = CGRect(x: 100, y: 20, width: 1200, height: 900)
        let current = CGRect(x: 300, y: 20, width: 800, height: 900)

        let left = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .leading
        ))
        let right = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .trailing
        ))
        let center = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: left.frame,
            visibleFrame: visible,
            placement: .center
        ))

        XCTAssertEqual(left.frame, CGRect(x: 100, y: 20, width: 800, height: 900))
        XCTAssertEqual(right.frame, CGRect(x: 500, y: 20, width: 800, height: 900))
        XCTAssertEqual(center.frame, current)
    }

    func testStronglyConstrainedHalfSizeStillUsesCornerPlacement() throws {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let constrained = CGRect(x: 250, y: 180, width: 850, height: 560)

        let left = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: constrained,
            visibleFrame: visible,
            placement: .leading
        ))
        let right = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: constrained,
            visibleFrame: visible,
            placement: .trailing
        ))

        XCTAssertEqual(left.frame.origin, CGPoint(x: 0, y: 25))
        XCTAssertEqual(right.frame.origin, CGPoint(x: 590, y: 25))
    }

    func testLargeArbitraryWindowIsNotTreatedAsFullSize() throws {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let current = CGRect(x: 140, y: 110, width: 1240, height: 740)

        let left = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .leading
        ))

        XCTAssertEqual(left.frame.origin, CGPoint(x: 0, y: 93))
    }

    func testClearlyUnknownSizeStillUsesGenericPlacement() throws {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let current = CGRect(x: 260, y: 180, width: 710, height: 700)

        let left = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .leading
        ))

        XCTAssertEqual(left.frame, CGRect(x: 0, y: 113, width: 710, height: 700))
    }

    func testUnknownSizePreservesSizeAndUsesGenericPlacement() throws {
        let visible = CGRect(x: 0, y: 20, width: 1200, height: 900)
        let current = CGRect(x: 260, y: 180, width: 710, height: 620)

        let left = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .leading
        ))
        let right = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .trailing
        ))
        let center = try XCTUnwrap(WindowGeometry.composedPlacementTarget(
            currentFrame: current,
            visibleFrame: visible,
            placement: .center
        ))

        XCTAssertEqual(left.frame, CGRect(x: 0, y: 160, width: 710, height: 620))
        XCTAssertEqual(right.frame, CGRect(x: 490, y: 160, width: 710, height: 620))
        XCTAssertEqual(center.frame, CGRect(x: 245, y: 160, width: 710, height: 620))
    }
}

@MainActor
final class HotKeyLongPressRecognizerTests: XCTestCase {
    func testReleaseBeforeThresholdTriggersOnlyShortPress() async {
        var shortPresses = 0
        var longPresses = 0
        let recognizer = HotKeyLongPressRecognizer(
            threshold: .seconds(1),
            onShortPress: { shortPresses += 1 },
            onLongPress: { longPresses += 1 }
        )

        recognizer.press()
        recognizer.press()
        try? await Task.sleep(for: .milliseconds(5))
        recognizer.release()
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(shortPresses, 1)
        XCTAssertEqual(longPresses, 0)
    }

    func testHoldingPastThresholdTriggersLongPressOnlyOnce() async {
        var shortPresses = 0
        var longPresses = 0
        let longPressTriggered = expectation(description: "long press triggered")
        let recognizer = HotKeyLongPressRecognizer(
            threshold: .milliseconds(20),
            onShortPress: { shortPresses += 1 },
            onLongPress: {
                longPresses += 1
                longPressTriggered.fulfill()
            }
        )

        recognizer.press()
        recognizer.press()
        await fulfillment(of: [longPressTriggered], timeout: 1)
        recognizer.release()

        XCTAssertEqual(shortPresses, 0)
        XCTAssertEqual(longPresses, 1)
    }

    func testCancellationDoesNotEmitAnAction() async {
        var actionCount = 0
        let recognizer = HotKeyLongPressRecognizer(
            threshold: .milliseconds(20),
            onShortPress: { actionCount += 1 },
            onLongPress: { actionCount += 1 }
        )

        recognizer.press()
        recognizer.cancel()
        recognizer.release()
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(actionCount, 0)
    }

    func testUpdatingThresholdCancelsPendingPressAndUsesNewThreshold() async {
        var shortPresses = 0
        var longPresses = 0
        let longPressTriggered = expectation(description: "updated long press triggered")
        let recognizer = HotKeyLongPressRecognizer(
            threshold: .milliseconds(100),
            onShortPress: { shortPresses += 1 },
            onLongPress: {
                longPresses += 1
                longPressTriggered.fulfill()
            }
        )

        recognizer.press()
        try? await Task.sleep(for: .milliseconds(5))
        recognizer.updateThreshold(.milliseconds(20))
        recognizer.press()
        await fulfillment(of: [longPressTriggered], timeout: 1)
        recognizer.release()

        XCTAssertEqual(shortPresses, 0)
        XCTAssertEqual(longPresses, 1)
    }
}
