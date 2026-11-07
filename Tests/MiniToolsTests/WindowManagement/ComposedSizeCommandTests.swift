import Carbon
import CoreGraphics
import XCTest
@testable import MiniTools

final class ComposedSizeCommandTests: XCTestCase {
    private let visible = CGRect(x: -1440, y: 40, width: 1440, height: 900)

    func testEveryShortAndLongSizeTargetPreservesCornerWhenAlreadySized() throws {
        for id in ComposedWindowControlCatalog.sizeIDs {
            for press in [WindowShortcutPress.short, .long] {
                let size = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: id, press: press))
                let target = WindowGeometry.targetFrame(for: size.frame, in: visible)
                for corner in [ComposedWindowPlacement.upperLeft, .lowerLeft, .upperRight, .lowerRight] {
                    let current = WindowGeometry.composedPlacementTarget(currentFrame: target, visibleFrame: visible, placement: corner).frame
                    XCTAssertNil(WindowGeometry.composedSizeTargetFrame(currentFrame: current, size: size, visibleFrame: visible))
                }
            }
        }
    }

    func testSameSizeAtArbitraryPositionDoesNotRequestInitialCentering() throws {
        let size = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .halfOrThirdHalfHeight, press: .long))
        let target = WindowGeometry.targetFrame(for: size.frame, in: visible)
        let current = CGRect(x: -1200, y: 100, width: target.width, height: target.height)
        XCTAssertNotEqual(current.origin, target.origin)
        XCTAssertNil(WindowGeometry.composedSizeTargetFrame(currentFrame: current, size: size, visibleFrame: visible))
        XCTAssertNotEqual(WindowGeometry.composedPlacementTarget(currentFrame: current, visibleFrame: visible, placement: .center).frame.origin,
                          current.origin) // Explicit centering is still available.
    }

    func testSizeToleranceMatchesAdjustmentEngineAndDoesNotIgnoreOneDimension() throws {
        let size = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .twoThirdsWidth, press: .short))
        let target = WindowGeometry.targetFrame(for: size.frame, in: visible)
        let near = CGRect(x: -1400, y: 100, width: target.width + 8, height: target.height - 8)
        XCTAssertNil(WindowGeometry.composedSizeTargetFrame(currentFrame: near, size: size, visibleFrame: visible))
        for actual in [CGSize(width: target.width + 9, height: target.height),
                       CGSize(width: target.width, height: target.height - 9)] {
            XCTAssertEqual(WindowGeometry.composedSizeTargetFrame(currentFrame: CGRect(origin: near.origin, size: actual),
                           size: size, visibleFrame: visible), target)
        }
    }

    func testChangedSizeStillUsesInitialCenteredOrTopPlacement() throws {
        let current = CGRect(x: -1440, y: 40, width: 300, height: 300)
        let narrow = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .halfOrThirdFullHeight, press: .short))
        let top = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .fullOrHalfHeight, press: .long))
        XCTAssertEqual(WindowGeometry.composedSizeTargetFrame(currentFrame: current, size: narrow, visibleFrame: visible),
                       CGRect(x: -1080, y: 40, width: 720, height: 900))
        XCTAssertEqual(WindowGeometry.composedSizeTargetFrame(currentFrame: current, size: top, visibleFrame: visible),
                       CGRect(x: -1440, y: 40, width: 1440, height: 450))
    }

    @MainActor
    func testFreshAndOldDefaultBindingsMatchScreenshotWithoutDuplicates() throws {
        let oldKeys: [ComposedWindowControlID: Int] = [
            .fullOrHalfHeight: kVK_ANSI_U, .twoThirdsWidth: kVK_ANSI_I,
            .halfOrThirdFullHeight: kVK_ANSI_J, .halfOrThirdHalfHeight: kVK_ANSI_K,
            .upperLeftPlacement: kVK_ANSI_Y, .lowerLeftPlacement: kVK_ANSI_H,
            .upperRightPlacement: kVK_ANSI_O, .lowerRightPlacement: kVK_ANSI_L
        ]
        let expected: [ComposedWindowControlID: Int] = [
            .fullOrHalfHeight: kVK_ANSI_Backslash, .twoThirdsWidth: kVK_ANSI_H,
            .halfOrThirdFullHeight: kVK_ANSI_L, .halfOrThirdHalfHeight: kVK_ANSI_O,
            .upperLeftPlacement: kVK_ANSI_U, .lowerLeftPlacement: kVK_ANSI_J,
            .upperRightPlacement: kVK_ANSI_I, .lowerRightPlacement: kVK_ANSI_K,
            .centerPlacement: kVK_Return
        ]
        for migrate in [false, true] {
            let suite = "ComposedSizeTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if migrate {
                let raw = Dictionary(uniqueKeysWithValues: oldKeys.map { ($0.key.rawValue, shortcut($0.value)) })
                defaults.set(try JSONEncoder().encode(raw), forKey: "composedWindowControlShortcuts")
            }
            let settings = AppSettings(defaults: defaults)
            for (id, code) in expected {
                XCTAssertEqual(settings.composedWindowControlShortcut(for: id), shortcut(code))
            }
            XCTAssertEqual(Set(settings.composedWindowControlShortcuts.values.map(\.keyCode)).count, expected.count)
            XCTAssertEqual(AppSettings(defaults: defaults).composedWindowControlShortcuts, settings.composedWindowControlShortcuts)
        }
    }

    @MainActor
    func testCustomBindingsAndChoosingOldKeysAfterMigrationArePreserved() throws {
        let suite = "ComposedSizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_U), carbonModifiers: UInt32(cmdKey | optionKey))
        defaults.set(try JSONEncoder().encode(["fullOrHalfHeight": custom]), forKey: "composedWindowControlShortcuts")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.composedWindowControlShortcut(for: .fullOrHalfHeight), custom)
        settings.updateComposedWindowControlShortcut(shortcut(kVK_ANSI_I), for: .twoThirdsWidth)
        XCTAssertEqual(AppSettings(defaults: defaults).composedWindowControlShortcut(for: .twoThirdsWidth), shortcut(kVK_ANSI_I))
    }

    private func shortcut(_ code: Int) -> KeyboardShortcut {
        KeyboardShortcut(keyCode: UInt32(code), carbonModifiers: KeyboardShortcut.panelDefault.carbonModifiers)
    }
}
