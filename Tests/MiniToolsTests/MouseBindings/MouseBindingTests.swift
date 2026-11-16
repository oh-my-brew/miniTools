import CoreGraphics
import XCTest
@testable import MiniTools

final class MouseBindingTests: XCTestCase {
    func testCommandCatalogExposesOnlySizePositionAndCrossScreenActions() throws {
        let layouts = try XCTUnwrap(AppCommandCatalog.sections.first(where: { $0.id == "window-layout" }))
        XCTAssertEqual(layouts.commands, ComposedWindowControlCatalog.descriptors.map {
            .composedWindowControl($0.id)
        })
        XCTAssertEqual(WindowControlID.allCases, [.moveWindowToNextScreen, .movePointerToNextScreen])
        for command in layouts.commands {
            XCTAssertEqual(try JSONDecoder().decode(AppCommand.self, from: JSONEncoder().encode(command)), command)
            XCTAssertFalse(command.title.isEmpty)
            XCTAssertFalse(command.subtitle.isEmpty)
        }
    }

    @MainActor
    func testMouseBindingsAreEmptyByDefaultAndPersistOnlyAssignedActions() throws {
        let suiteName = "MiniToolsTests.MouseBindings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.mouseBindings.isEmpty)
        XCTAssertFalse(settings.hasMouseBindings(for: .button4))
        XCTAssertFalse(settings.hasMouseBindings(for: .button5))

        settings.updateMouseCommand(
            .windowControl(.movePointerToNextScreen),
            for: .button5,
            gesture: .dragRight
        )

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(
            restored.mouseCommand(for: .button5, gesture: .dragRight),
            .windowControl(.movePointerToNextScreen)
        )
        XCTAssertTrue(restored.hasMouseBindings(for: .button5))

        restored.updateMouseCommand(nil, for: .button5, gesture: .dragRight)
        XCTAssertTrue(AppSettings(defaults: defaults).mouseBindings.isEmpty)
    }

    @MainActor
    func testMouseDragThresholdRatioPersistsAndStaysWithinSupportedRange() throws {
        let suiteName = "MiniToolsTests.MouseDragThresholdRatio.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(
            settings.mouseDragThresholdRatio,
            MouseGestureConfiguration.defaultDragThresholdRatio
        )

        settings.updateMouseDragThresholdRatio(0.035)
        XCTAssertEqual(AppSettings(defaults: defaults).mouseDragThresholdRatio, 0.035)

        settings.updateMouseDragThresholdRatio(0.001)
        XCTAssertEqual(
            settings.mouseDragThresholdRatio,
            MouseGestureConfiguration.dragThresholdRatioRange.lowerBound
        )

        settings.updateMouseDragThresholdRatio(0.2)
        XCTAssertEqual(
            settings.mouseDragThresholdRatio,
            MouseGestureConfiguration.dragThresholdRatioRange.upperBound
        )
    }

    @MainActor
    func testMigratesLegacyPointThresholdToScreenRatio() throws {
        let suiteName = "MiniToolsTests.LegacyMouseDragThreshold.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(24.0, forKey: "mouseDragThreshold")

        XCTAssertEqual(AppSettings(defaults: defaults).mouseDragThresholdRatio, 0.02)
        XCTAssertNil(defaults.object(forKey: "mouseDragThreshold"))
        XCTAssertEqual(defaults.double(forKey: "mouseDragThresholdRatio"), 0.02)
    }

    func testMapsOnlyPhysicalButtonFourAndFiveEventNumbers() {
        XCTAssertEqual(MouseSideButton(eventButtonNumber: 3), .button4)
        XCTAssertEqual(MouseSideButton(eventButtonNumber: 4), .button5)
        XCTAssertNil(MouseSideButton(eventButtonNumber: 2))
        XCTAssertNil(MouseSideButton(eventButtonNumber: 5))
    }

    func testDragDirectionUsesThresholdAndDominantAxis() {
        let origin = CGPoint(x: 100, y: 100)

        XCTAssertNil(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 118, y: 100)
        ))
        XCTAssertEqual(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 140, y: 110)
        ), .right)
        XCTAssertEqual(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 90, y: 60)
        ), .up)
        XCTAssertEqual(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 100, y: 145)
        ), .down)

        XCTAssertNil(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 140, y: 100),
            screenSize: CGSize(width: 1_000, height: 500),
            thresholdRatio: 0.06
        ))
        XCTAssertEqual(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 170, y: 100),
            screenSize: CGSize(width: 1_000, height: 500),
            thresholdRatio: 0.06
        ), .right)
        XCTAssertNil(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 100, y: 75),
            screenSize: CGSize(width: 1_000, height: 500),
            thresholdRatio: 0.06
        ))
        XCTAssertEqual(MouseGestureRecognizer.dragDirection(
            from: origin,
            to: CGPoint(x: 100, y: 65),
            screenSize: CGSize(width: 1_000, height: 500),
            thresholdRatio: 0.06
        ), .up)
    }

    func testSingleClickExecutesImmediatelyWithoutDoubleClickBinding() {
        var recognizer = MouseGestureRecognizer()
        let down = MouseButtonEvent(
            button: .button4,
            phase: .down,
            location: .zero,
            timestamp: 1
        )
        let up = MouseButtonEvent(
            button: .button4,
            phase: .up,
            location: .zero,
            timestamp: 1.1
        )

        XCTAssertTrue(recognizer.handle(
            down,
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        ).isEmpty)
        XCTAssertEqual(recognizer.handle(
            up,
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        ), [.gesture(.button4, .singleClick)])
    }

    func testDoubleClickCancelsPendingSingleClick() throws {
        var recognizer = MouseGestureRecognizer()
        _ = recognizer.handle(
            event(.down, at: 1),
            supportsDoubleClick: true,
            doubleClickInterval: 0.4
        )
        let firstUp = recognizer.handle(
            event(.up, at: 1.05),
            supportsDoubleClick: true,
            doubleClickInterval: 0.4
        )
        guard case let .scheduleSingleClick(.button4, token, _) = try XCTUnwrap(firstUp.first) else {
            return XCTFail("Expected a pending single click")
        }

        _ = recognizer.handle(
            event(.down, at: 1.2),
            supportsDoubleClick: true,
            doubleClickInterval: 0.4
        )
        XCTAssertEqual(recognizer.handle(
            event(.up, at: 1.25),
            supportsDoubleClick: true,
            doubleClickInterval: 0.4
        ), [
            .cancelSingleClick(.button4, token),
            .gesture(.button4, .doubleClick)
        ])
        XCTAssertNil(recognizer.completePendingSingleClick(for: .button4, token: token))
    }

    func testDragPreviewAndReleaseProduceOneDirectionalGesture() {
        var recognizer = MouseGestureRecognizer()
        _ = recognizer.handle(
            event(.down, at: 1, location: CGPoint(x: 100, y: 100)),
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        )

        XCTAssertEqual(recognizer.handle(
            event(.dragged, at: 1.1, location: CGPoint(x: 135, y: 105)),
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        ), [
            .dragPreview(
                .button4,
                .right,
                CGPoint(x: 100, y: 100),
                CGPoint(x: 135, y: 105)
            )
        ])
        XCTAssertEqual(recognizer.handle(
            event(.dragged, at: 1.2, location: CGPoint(x: 145, y: 108)),
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        ), [
            .dragPreview(
                .button4,
                .right,
                CGPoint(x: 100, y: 100),
                CGPoint(x: 145, y: 108)
            )
        ])
        XCTAssertEqual(recognizer.handle(
            event(.up, at: 1.3, location: CGPoint(x: 145, y: 108)),
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        ), [
            .dismissDragPreview(.button4),
            .gesture(.button4, .dragRight)
        ])
    }

    func testStationaryHoldDoesNotBecomeClick() {
        var recognizer = MouseGestureRecognizer()
        _ = recognizer.handle(
            event(.down, at: 1),
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        )

        XCTAssertEqual(recognizer.handle(
            event(.up, at: 1 + MouseGestureRecognizer.maximumClickDuration + 0.1),
            supportsDoubleClick: false,
            doubleClickInterval: 0.4
        ), [.dismissDragPreview(.button4)])
    }

    private func event(
        _ phase: MouseButtonEventPhase,
        at timestamp: TimeInterval,
        location: CGPoint = .zero
    ) -> MouseButtonEvent {
        MouseButtonEvent(
            button: .button4,
            phase: phase,
            location: location,
            timestamp: timestamp
        )
    }
}
