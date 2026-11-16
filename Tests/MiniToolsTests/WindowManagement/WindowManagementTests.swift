import CoreGraphics
import XCTest
@testable import MiniTools

final class WindowManagementTests: XCTestCase {
    func testWindowTargetPrefersAccessibilityFocusBeforeFrontmostApplication() {
        XCTAssertEqual(
            WindowTargetResolver.candidateProcessIdentifiers(
                accessibilityFocusedProcessIdentifier: 42,
                frontmostProcessIdentifier: 84,
                currentProcessIdentifier: 21
            ),
            [42, 84]
        )
    }

    func testWindowTargetDeduplicatesAndExcludesMiniTools() {
        XCTAssertEqual(
            WindowTargetResolver.candidateProcessIdentifiers(
                accessibilityFocusedProcessIdentifier: 42,
                frontmostProcessIdentifier: 42,
                currentProcessIdentifier: 21
            ),
            [42]
        )
        XCTAssertEqual(
            WindowTargetResolver.candidateProcessIdentifiers(
                accessibilityFocusedProcessIdentifier: 21,
                frontmostProcessIdentifier: 84,
                currentProcessIdentifier: 21
            ),
            [84]
        )
    }

    func testDetectsVisibleApplicationWithNoAXWindowRoleAsInvalid() {
        XCTAssertTrue(
            WindowAccessibilityHealth.isInvalid(
                candidateRoles: [kAXApplicationRole as String],
                hasVisibleWindow: true
            )
        )
        XCTAssertFalse(
            WindowAccessibilityHealth.isInvalid(
                candidateRoles: [kAXWindowRole as String],
                hasVisibleWindow: true
            )
        )
        XCTAssertFalse(
            WindowAccessibilityHealth.isInvalid(
                candidateRoles: [],
                hasVisibleWindow: false
            )
        )
    }

    func testInvalidAccessibilityStateExplainsHowToRecover() {
        XCTAssertEqual(
            WindowLayoutError.invalidAccessibilityWindowState("Sublime Text")
                .localizedDescription,
            "Sublime Text 的辅助功能窗口状态异常，请重启该应用后再试"
        )
    }

    @MainActor
    func testSharinganUsesCircularShadowAndClippedArtwork() throws {
        let view = SharinganCursorHighlightView(
            style: .sharinganThreeTomoe,
            frame: CGRect(origin: .zero, size: SharinganCursorHighlightView.canvasSize)
        )

        view.startAnimation()

        let eye = try XCTUnwrap(view.layer?.sublayers?.first(where: { $0.cornerRadius > 0 }))
        XCTAssertEqual(eye.bounds.width, SharinganCursorHighlightView.eyeDiameter)
        XCTAssertNotNil(eye.shadowPath)

        let clip = try XCTUnwrap(eye.sublayers?.first)
        XCTAssertTrue(clip.masksToBounds)
        XCTAssertEqual(clip.cornerRadius, SharinganCursorHighlightView.eyeDiameter / 2)
        XCTAssertNotNil(clip.sublayers?.first?.contents)

        let maximumAuraDiameter = (SharinganCursorHighlightView.eyeDiameter + 18) * 1.6
        XCTAssertGreaterThan(view.bounds.width, maximumAuraDiameter)
    }

    @MainActor
    func testEveryConfiguredSharinganStyleHasRenderableArtwork() {
        let styles = CursorHighlightStyle.basicSharinganStyles
            + CursorHighlightStyle.mangekyoStyles
            + CursorHighlightStyle.evolvedDojutsuStyles

        XCTAssertTrue(CursorHighlightStyle.allCases.contains(.mangekyoHikari))
        XCTAssertTrue(CursorHighlightStyle.mangekyoStyles.contains(.mangekyoHikari))
        for style in styles {
            XCTAssertNotNil(
                SharinganArtwork.renderedArtwork(for: style),
                "Missing or invalid artwork for \(style.rawValue)"
            )
        }
    }

    @MainActor
    func testBuildsTargetFrameInsideVisibleScreen() {
        let visible = CGRect(x: 100, y: 40, width: 1200, height: 900)
        let frame = WindowGeometry.targetFrame(
            for: UnitWindowFrame(2.0 / 3.0, 0.5, 1.0 / 3.0, 0.5),
            in: visible
        )
        XCTAssertEqual(frame, CGRect(x: 900, y: 490, width: 400, height: 450))
    }

    func testCorrectsPositionAfterApplicationConstrainsRequestedHeight() {
        let target = CGRect(x: -1920, y: 0, width: 1280, height: 1080)
        let safariResult = CGRect(x: -1600, y: 30, width: 1280, height: 1050)

        XCTAssertEqual(
            WindowGeometry.correctedOriginAfterApplyingFrame(
                actualFrame: safariResult,
                targetFrame: target
            ),
            target.origin
        )
    }

    func testCorrectsPositionAfterRequestedSizeHasSettled() {
        let target = CGRect(x: 100, y: 40, width: 800, height: 600)

        XCTAssertEqual(
            WindowGeometry.correctedOriginAfterApplyingFrame(
                actualFrame: CGRect(x: 125, y: 70, width: 800, height: 600),
                targetFrame: target
            ),
            target.origin
        )
    }

    func testDoesNotCorrectPositionThatAlreadyMatchesTarget() {
        let target = CGRect(x: 100, y: 40, width: 800, height: 600)

        XCTAssertNil(
            WindowGeometry.correctedOriginAfterApplyingFrame(
                actualFrame: CGRect(x: 100, y: 40, width: 900, height: 550),
                targetFrame: target
            )
        )
    }

    func testRetriesSizeWhenApplicationHasNotAcceptedBothDimensions() {
        let target = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.correctedSizeAfterApplyingFrame(
                actualFrame: CGRect(x: 0, y: 25, width: 1440, height: 760),
                targetFrame: target
            ),
            target.size
        )
        XCTAssertNil(
            WindowGeometry.correctedSizeAfterApplyingFrame(
                actualFrame: CGRect(x: 0, y: 25, width: 1436, height: 870),
                targetFrame: target
            )
        )
    }

    func testMovesBeforeGrowingWhenCurrentOriginWouldClipTargetSize() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.frameMutationOrder(
                currentFrame: CGRect(x: 360, y: 244, width: 720, height: 438),
                targetFrame: visibleFrame,
                visibleFrame: visibleFrame
            ),
            .positionThenSize
        )
    }

    func testShrinksBeforeMovingWhenCurrentSizeWouldClipAtTargetOrigin() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.frameMutationOrder(
                currentFrame: visibleFrame,
                targetFrame: CGRect(x: 720, y: 25, width: 720, height: 875),
                visibleFrame: visibleFrame
            ),
            .sizeThenPosition
        )
    }

    func testKeepsSizeFirstWhenTargetSizeFitsAtCurrentOrigin() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.frameMutationOrder(
                currentFrame: CGRect(x: 0, y: 25, width: 720, height: 875),
                targetFrame: CGRect(x: 720, y: 25, width: 720, height: 875),
                visibleFrame: visibleFrame
            ),
            .sizeThenPosition
        )
    }

    func testCompletedFrameSkipsSlowConvergencePath() {
        let target = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.frameFollowUp(actualFrame: target, targetFrame: target),
            .complete
        )
    }

    func testPositionOnlyMismatchUsesPositionCorrection() {
        let target = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.frameFollowUp(
                actualFrame: CGRect(x: 40, y: 60, width: 1440, height: 875),
                targetFrame: target
            ),
            .correctPosition
        )
    }

    func testSizeMismatchUsesSettlementAndRetry() {
        let target = CGRect(x: 0, y: 25, width: 1440, height: 875)

        XCTAssertEqual(
            WindowGeometry.frameFollowUp(
                actualFrame: CGRect(x: 0, y: 25, width: 1200, height: 760),
                targetFrame: target
            ),
            .settleAndRetrySize
        )
    }

    func testFrameSettlementWaitsForResizeAndStableSamples() {
        let initial = CGRect(x: -1440, y: 555, width: 960, height: 525)
        let target = CGRect(x: -1920, y: 0, width: 1280, height: 1080)
        var tracker = WindowFrameSettlementTracker(
            initialFrame: initial,
            targetFrame: target,
            requiredStableSamples: 2
        )

        XCTAssertFalse(tracker.record(initial))
        XCTAssertFalse(tracker.record(initial))

        let constrained = CGRect(x: -1600, y: 30, width: 1280, height: 1050)
        XCTAssertFalse(tracker.record(constrained))
        XCTAssertFalse(tracker.record(constrained))
        XCTAssertTrue(tracker.record(constrained))
    }

    func testFrameSettlementDefaultRequiresAQuietWindowAfterResize() {
        let initial = CGRect(x: 300, y: 200, width: 900, height: 700)
        let target = CGRect(x: 0, y: 25, width: 1440, height: 875)
        var tracker = WindowFrameSettlementTracker(
            initialFrame: initial,
            targetFrame: target
        )
        let widthPhase = CGRect(x: 0, y: 200, width: 1440, height: 700)
        let finalPhase = CGRect(x: 0, y: 25, width: 1440, height: 875)

        for _ in 0..<9 {
            XCTAssertFalse(tracker.record(widthPhase))
        }
        XCTAssertFalse(tracker.record(finalPhase))
        for _ in 0..<7 {
            XCTAssertFalse(tracker.record(finalPhase))
        }
        XCTAssertTrue(tracker.record(finalPhase))
    }

    func testWindowServerInspectorReturnsFrontmostAdjustableWindowFrame() {
        let processIdentifier: pid_t = 42
        let tinyFrame = CGRect(x: 0, y: 0, width: 80, height: 30)
        let frontmostFrame = CGRect(x: -1920, y: 555, width: 960, height: 600)
        let backgroundFrame = CGRect(x: -1920, y: 0, width: 1920, height: 600)
        let windows = [
            windowServerRecord(pid: processIdentifier, frame: tinyFrame),
            windowServerRecord(pid: processIdentifier, frame: frontmostFrame),
            windowServerRecord(pid: processIdentifier, frame: backgroundFrame)
        ]

        XCTAssertEqual(
            WindowServerWindowInspector.frontmostVisibleWindowFrame(
                processIdentifier: processIdentifier,
                windows: windows
            ),
            frontmostFrame
        )
    }

    func testWindowServerInspectorUsesElevatedPanelWhenNoNormalWindowExists() {
        let processIdentifier: pid_t = 42
        let quickTerminalFrame = CGRect(x: 0, y: 0, width: 1440, height: 500)

        XCTAssertEqual(
            WindowServerWindowInspector.frontmostVisibleWindowFrame(
                processIdentifier: processIdentifier,
                windows: [
                    windowServerRecord(
                        pid: processIdentifier,
                        frame: quickTerminalFrame,
                        layer: 3
                    )
                ]
            ),
            quickTerminalFrame
        )
    }

    func testWindowServerInspectorPrefersNormalWindowOverElevatedPanel() {
        let processIdentifier: pid_t = 42
        let panelFrame = CGRect(x: 0, y: 0, width: 1440, height: 500)
        let normalFrame = CGRect(x: 100, y: 100, width: 900, height: 700)

        XCTAssertEqual(
            WindowServerWindowInspector.frontmostVisibleWindowFrame(
                processIdentifier: processIdentifier,
                windows: [
                    windowServerRecord(pid: processIdentifier, frame: panelFrame, layer: 3),
                    windowServerRecord(pid: processIdentifier, frame: normalFrame)
                ]
            ),
            normalFrame
        )
    }

    @MainActor
    func testConvertsAppKitCoordinatesToAccessibilityCoordinates() {
        let appKitRect = CGRect(x: -1000, y: 1080, width: 1000, height: 800)
        let converted = WindowGeometry.appKitToAccessibility(appKitRect, primaryScreenMaxY: 1080)
        XCTAssertEqual(converted, CGRect(x: -1000, y: -800, width: 1000, height: 800))
    }

    @MainActor
    func testMovesWindowToNextScreenPreservingRelativePosition() {
        let source = CGRect(x: 0, y: 20, width: 1200, height: 800)
        let destination = CGRect(x: 1200, y: 40, width: 1600, height: 1000)
        let current = CGRect(x: 300, y: 220, width: 600, height: 400)

        let moved = WindowGeometry.frameByMoving(current, from: source, to: destination)
        XCTAssertEqual(moved, CGRect(x: 1700, y: 340, width: 600, height: 400))
    }

    @MainActor
    func testCentersWindowWithoutChangingSize() {
        let visible = CGRect(x: 100, y: 50, width: 1400, height: 900)
        let current = CGRect(x: 0, y: 0, width: 600, height: 400)
        XCTAssertEqual(
            WindowGeometry.centeredFrame(current, in: visible),
            CGRect(x: 500, y: 300, width: 600, height: 400)
        )
    }

    @MainActor
    func testFindsScreenContainingPoint() {
        let screens = [
            WindowLayoutScreenGeometry(
                fullFrame: CGRect(x: -1000, y: 0, width: 1000, height: 800),
                visibleFrame: CGRect(x: -1000, y: 0, width: 1000, height: 760)
            ),
            WindowLayoutScreenGeometry(
                fullFrame: CGRect(x: 0, y: 0, width: 1200, height: 900),
                visibleFrame: CGRect(x: 0, y: 20, width: 1200, height: 840)
            )
        ]
        XCTAssertEqual(
            WindowGeometry.screenIndex(containing: CGPoint(x: -500, y: 300), geometries: screens),
            0
        )
        XCTAssertEqual(
            WindowGeometry.screenIndex(containing: CGPoint(x: 800, y: 300), geometries: screens),
            1
        )
    }

    func testPointerMoveContinuesAtCurrentLocationWithOneScreen() throws {
        let pointer = CGPoint(x: 420, y: 260)
        let screen = WindowLayoutScreenGeometry(
            fullFrame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            visibleFrame: CGRect(x: 0, y: 20, width: 1200, height: 840)
        )

        XCTAssertEqual(
            try PointerMover.targetLocation(from: pointer, geometries: [screen]),
            pointer
        )
    }

    func testPointerMoveTargetsTheCenterOfTheNextScreen() throws {
        let screens = [
            WindowLayoutScreenGeometry(
                fullFrame: CGRect(x: 0, y: 0, width: 1200, height: 900),
                visibleFrame: CGRect(x: 0, y: 20, width: 1200, height: 840)
            ),
            WindowLayoutScreenGeometry(
                fullFrame: CGRect(x: 1200, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 1200, y: 40, width: 1600, height: 920)
            )
        ]

        XCTAssertEqual(
            try PointerMover.targetLocation(
                from: CGPoint(x: 600, y: 450),
                geometries: screens
            ),
            CGPoint(x: 2000, y: 500)
        )
    }

    private func windowServerRecord(
        pid: pid_t,
        frame: CGRect,
        layer: Int = 0
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: 1),
            kCGWindowBounds as String: frame.dictionaryRepresentation
        ]
    }
}
