import CoreGraphics
import XCTest
@testable import MiniTools

final class WindowManagementTests: XCTestCase {
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
    func testCatalogMatchesRequestedShortcutOrder() {
        XCTAssertEqual(
            WindowControlCatalog.layoutCommands.map(\.id),
            [.upperLeft, .upperRight, .lowerLeft, .lowerRight, .left, .right,
             .horizontalHalves, .verticalThirds, .maximize]
        )
        XCTAssertTrue(
            WindowControlCatalog.layoutCommands
                .filter { $0.id != .verticalThirds }
                .allSatisfy { $0.frames.count == 2 }
        )
        XCTAssertEqual(
            WindowControlCatalog.layoutCommand(for: .verticalThirds)?.frames.count,
            3
        )
        XCTAssertEqual(WindowControlCatalog.descriptors.count, 12)
        XCTAssertEqual(
            WindowControlCatalog.windowLayoutDescriptors.map(\.id),
            [.upperLeft, .upperRight, .lowerLeft, .lowerRight, .left, .right,
             .horizontalHalves, .verticalThirds, .maximize, .centerWindow]
        )
        XCTAssertEqual(
            WindowControlCatalog.crossScreenDescriptors.map(\.id),
            [.moveWindowToNextScreen, .movePointerToNextScreen]
        )
    }

    func testSystemWindowActionsOnlyCoverMatchingCycleCandidates() {
        XCTAssertEqual(
            SystemWindowActionResolver.layoutAction(for: .upperLeft, candidateIndex: 0),
            .topLeft
        )
        XCTAssertNil(
            SystemWindowActionResolver.layoutAction(for: .upperLeft, candidateIndex: 1)
        )
        XCTAssertNil(
            SystemWindowActionResolver.layoutAction(for: .left, candidateIndex: 0)
        )
        XCTAssertEqual(
            SystemWindowActionResolver.layoutAction(for: .left, candidateIndex: 1),
            .left
        )
        XCTAssertNil(
            SystemWindowActionResolver.layoutAction(for: .right, candidateIndex: 0)
        )
        XCTAssertEqual(
            SystemWindowActionResolver.layoutAction(for: .right, candidateIndex: 1),
            .right
        )
        XCTAssertEqual(
            SystemWindowActionResolver.layoutAction(for: .horizontalHalves, candidateIndex: 1),
            .bottom
        )
        XCTAssertNil(
            SystemWindowActionResolver.layoutAction(for: .verticalThirds, candidateIndex: 0)
        )
        XCTAssertNil(
            SystemWindowActionResolver.layoutAction(for: .verticalThirds, candidateIndex: 2)
        )
        XCTAssertEqual(
            SystemWindowActionResolver.layoutAction(for: .maximize, candidateIndex: 1),
            .fill
        )
    }

    func testCrossScreenMenuCandidatesIncludeEnglishFallbacks() {
        XCTAssertTrue(
            SystemWindowMenuService.moveToDisplayTitles(displayName: "Studio Display")
                .contains("Move to “Studio Display”")
        )
        XCTAssertTrue(
            SystemWindowMenuService.moveBackToMacTitles()
                .contains("Move Window Back to Mac")
        )
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

    @MainActor
    func testCyclesToSecondFrameAndBack() {
        let first = CGRect(x: 0, y: 0, width: 600, height: 800)
        let second = CGRect(x: 0, y: 0, width: 400, height: 800)

        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: first, candidates: [first, second]),
            second
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: second, candidates: [first, second]),
            first
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(
                currentFrame: CGRect(x: 50, y: 50, width: 500, height: 500),
                candidates: [first, second]
            ),
            first
        )
    }

    @MainActor
    func testCyclesByPlacementWhenApplicationConstrainsWindowSize() {
        let upper = CGRect(x: -1920, y: 0, width: 1920, height: 540)
        let lower = CGRect(x: -1920, y: 540, width: 1920, height: 540)

        XCTAssertEqual(
            WindowGeometry.nextTarget(
                currentFrame: CGRect(x: -1920, y: 30, width: 1920, height: 600),
                candidates: [upper, lower]
            ),
            lower
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(
                currentFrame: CGRect(x: -1920, y: 555, width: 960, height: 600),
                candidates: [upper, lower]
            ),
            upper
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(
                currentFrame: CGRect(x: -1800, y: 250, width: 900, height: 600),
                candidates: [upper, lower]
            ),
            upper
        )
    }

    func testSideCommandsStartAtTwoThirdsThenHalfWidth() throws {
        let left = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .left))
        let right = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .right))

        XCTAssertEqual(left.frames.map(\.width), [2.0 / 3.0, 0.5])
        XCTAssertEqual(left.frames.map(\.x), [0, 0])
        XCTAssertEqual(right.frames.map(\.width), [2.0 / 3.0, 0.5])
        XCTAssertEqual(right.frames.map(\.x), [1.0 / 3.0, 0.5])
        XCTAssertEqual(
            WindowControlCatalog.descriptors.first(where: { $0.id == .left })?.subtitle,
            "三分之二 ↔ 二分之一宽"
        )
        XCTAssertEqual(
            WindowControlCatalog.descriptors.first(where: { $0.id == .right })?.subtitle,
            "三分之二 ↔ 二分之一宽"
        )
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .right, candidateIndex: 0),
            "右侧区域 · 三分之二宽"
        )
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .right, candidateIndex: 1),
            "右侧区域 · 二分之一宽"
        )
    }

    func testThirdsCommandCyclesLeftMiddleRight() throws {
        let thirds = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .verticalThirds))

        XCTAssertEqual(thirds.frames.map(\.x), [0, 1.0 / 3.0, 2.0 / 3.0])
        XCTAssertEqual(thirds.frames.map(\.width), [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0])
        XCTAssertEqual(
            WindowControlCatalog.descriptors.first(where: { $0.id == .verticalThirds })?.title,
            "左中右三分之一切换"
        )
        XCTAssertEqual(
            WindowControlCatalog.descriptors.first(where: { $0.id == .verticalThirds })?.subtitle,
            "左侧三分之一 ↔ 中间三分之一 ↔ 右侧三分之一"
        )
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .verticalThirds, candidateIndex: 1),
            "中间三分之一"
        )
        XCTAssertEqual(
            WindowControlCatalog.statisticsID(for: .verticalThirds, candidateIndex: 2),
            "verticalThirds.2"
        )

        let visibleFrame = CGRect(x: 0, y: 25, width: 1600, height: 900)
        let targets = thirds.frames.map {
            WindowGeometry.targetFrame(for: $0, in: visibleFrame)
        }

        // 左 → 中 → 右 → 左
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: targets[0], candidates: targets),
            targets[1]
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: targets[1], candidates: targets),
            targets[2]
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: targets[2], candidates: targets),
            targets[0]
        )
    }

    func testSwitchingRegionRestartsWithTheHalfWidthCandidate() throws {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1600, height: 900)
        let upperLeft = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .upperLeft))
        let upperRight = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .upperRight))
        let left = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .left))

        let rightTargets = upperRight.frames.map {
            WindowGeometry.targetFrame(for: $0, in: visibleFrame)
        }
        let leftTargets = left.frames.map {
            WindowGeometry.targetFrame(for: $0, in: visibleFrame)
        }
        let upperLeftHalf = WindowGeometry.targetFrame(
            for: upperLeft.frames[0],
            in: visibleFrame
        )

        // 左上区域半宽时按右上区域，应先给右上区域半宽。
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: upperLeftHalf, candidates: rightTargets),
            rightTargets[0]
        )

        // 已经在右上区域半宽里继续按同一快捷键，才进入三分之一宽。
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: rightTargets[0], candidates: rightTargets),
            rightTargets[1]
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: rightTargets[1], candidates: rightTargets),
            rightTargets[0]
        )

        // 满高右半屏按右上区域，不应直接跳到三分之一宽。
        let rightFullHeight = CGRect(
            x: visibleFrame.midX,
            y: visibleFrame.minY,
            width: visibleFrame.width / 2,
            height: visibleFrame.height
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: rightFullHeight, candidates: rightTargets),
            rightTargets[0]
        )

        // 左侧区域：满高三分之二宽 → 二分之一宽；再按 → 回到三分之二宽。
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: leftTargets[0], candidates: leftTargets),
            leftTargets[1]
        )
        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: leftTargets[1], candidates: leftTargets),
            leftTargets[0]
        )
    }

    func testConstrainedWindowSizeStillCyclesWithinItsOwnRegion() throws {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1600, height: 900)
        let upperLeft = try XCTUnwrap(WindowControlCatalog.layoutCommand(for: .upperLeft))
        let targets = upperLeft.frames.map {
            WindowGeometry.targetFrame(for: $0, in: visibleFrame)
        }
        let constrained = CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width / 2,
            height: visibleFrame.height * 0.9
        )

        XCTAssertEqual(
            WindowGeometry.nextTarget(currentFrame: constrained, candidates: targets),
            targets[1]
        )
    }

    func testStatisticsNameDistinguishesCycleTargets() {
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .upperLeft, candidateIndex: 0),
            "左上区域 · 半宽"
        )
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .upperLeft, candidateIndex: 1),
            "左上区域 · 三分之一宽"
        )
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .centerWindow, candidateIndex: 0),
            "窗口居中"
        )
        XCTAssertEqual(
            WindowControlCatalog.targetTitle(for: .maximize, candidateIndex: 1),
            "铺满当前屏幕"
        )
        XCTAssertEqual(
            WindowControlCatalog.statisticsID(for: .upperLeft, candidateIndex: 1),
            "upperLeft.1"
        )
        XCTAssertEqual(
            WindowControlCatalog.statisticsID(for: .centerWindow, candidateIndex: 0),
            "centerWindow"
        )
        XCTAssertTrue(
            WindowControlCatalog.layoutCommands.allSatisfy {
                $0.frames.count == $0.targetTitles.count
            }
        )
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

    private func windowServerRecord(pid: pid_t, frame: CGRect) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowAlpha as String: NSNumber(value: 1),
            kCGWindowBounds as String: frame.dictionaryRepresentation
        ]
    }
}
