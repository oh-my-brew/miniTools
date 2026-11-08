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

    func testChangedSizeKeepsUpperLeftCorner() throws {
        let current = CGRect(x: -1440, y: 40, width: 300, height: 300)
        let narrow = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .halfOrThirdFullHeight, press: .short))
        let top = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .fullOrHalfHeight, press: .long))
        XCTAssertEqual(WindowGeometry.composedSizeTargetFrame(currentFrame: current, size: narrow, visibleFrame: visible),
                       CGRect(x: -1440, y: 40, width: 720, height: 900))
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
            .fullOrHalfHeight: kVK_ANSI_Backslash, .twoThirdsWidth: kVK_ANSI_I,
            .halfOrThirdFullHeight: kVK_ANSI_J, .halfOrThirdHalfHeight: kVK_ANSI_K,
            .upperLeftPlacement: kVK_ANSI_U, .lowerLeftPlacement: kVK_ANSI_H,
            .upperRightPlacement: kVK_ANSI_O, .lowerRightPlacement: kVK_ANSI_L,
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
        settings.updateComposedWindowControlShortcut(shortcut(kVK_ANSI_H), for: .twoThirdsWidth)
        XCTAssertEqual(AppSettings(defaults: defaults).composedWindowControlShortcut(for: .twoThirdsWidth), shortcut(kVK_ANSI_H))
    }

    func testAllResizeTargetsKeepEachMatchingCornerWithSmallOffsets() throws {
        for corner in [ComposedWindowPlacement.upperLeft, .lowerLeft, .upperRight, .lowerRight] {
            let current = WindowGeometry.composedPlacementTarget(
                currentFrame: CGRect(x: 0, y: 0, width: 300, height: 250),
                visibleFrame: visible, placement: corner).frame.offsetBy(dx: 5.5, dy: -7.5)
            XCTAssertEqual(WindowGeometry.composedResizeAnchor(currentFrame: current, visibleFrame: visible), corner)
            let placement = WindowFramePlacement(resizing: corner, currentFrame: current, visible: visible)
            for id in ComposedWindowControlCatalog.sizeIDs {
                for press in [WindowShortcutPress.short, .long] {
                    let size = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: id, press: press))
                    let target = try XCTUnwrap(WindowGeometry.composedSizeTargetFrame(
                        currentFrame: current, size: size, visibleFrame: visible))
                    XCTAssertEqual(point(target, corner), point(current, corner))
                    XCTAssertEqual(placement.origin(for: target.size), target.origin)
                }
            }
        }
    }

    func testCornerToleranceNeedsBothAxesAndIncludesEightPoints() {
        for offset in [CGFloat(-8), 8] {
            let current = CGRect(x: visible.minX + offset, y: visible.minY - offset, width: 300, height: 250)
            XCTAssertEqual(WindowGeometry.composedResizeAnchor(currentFrame: current, visibleFrame: visible), .upperLeft)
        }
        for offset in [CGPoint(x: 8.01, y: 0), CGPoint(x: 0, y: -8.01), CGPoint(x: 0, y: 100)] {
            let current = CGRect(x: visible.minX + offset.x, y: visible.minY + offset.y, width: 300, height: 250)
            XCTAssertEqual(WindowGeometry.composedResizeAnchor(currentFrame: current, visibleFrame: visible), .center)
        }
    }

    func testMatchingCornerPriorityForFullAndNearlyFullWindows() {
        let cases: [(CGRect, ComposedWindowPlacement)] = [
            (visible, .upperLeft),
            (CGRect(x: visible.minX, y: visible.minY, width: 300, height: visible.height), .upperLeft),
            (CGRect(x: visible.maxX - 300, y: visible.minY, width: 300, height: visible.height), .upperRight),
            (CGRect(x: visible.minX, y: visible.maxY - 250, width: visible.width, height: 250), .lowerLeft),
            (visible.insetBy(dx: 7, dy: 7), .upperLeft)
        ]
        for (frame, expected) in cases {
            XCTAssertEqual(WindowGeometry.composedResizeAnchor(currentFrame: frame, visibleFrame: visible), expected)
        }
    }

    func testNoCornerAlwaysCentersIncludingFullWidthHalfHeight() throws {
        let current = CGRect(x: -1200, y: 180, width: 300, height: 250)
        for id in ComposedWindowControlCatalog.sizeIDs {
            for press in [WindowShortcutPress.short, .long] {
                let size = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: id, press: press))
                let target = try XCTUnwrap(WindowGeometry.composedSizeTargetFrame(
                    currentFrame: current, size: size, visibleFrame: visible))
                XCTAssertEqual(target, WindowGeometry.centeredFrame(target, in: visible))
            }
        }
    }

    func testCompatibleResizeKeepsActualCornerWhenApplicationEnforcesMinimumSize() throws {
        for corner in [ComposedWindowPlacement.upperLeft, .lowerLeft, .upperRight, .lowerRight, .center] {
            let initial = WindowGeometry.composedPlacementTarget(
                currentFrame: CGRect(x: 0, y: 0, width: 300, height: 250),
                visibleFrame: visible, placement: corner).frame.offsetBy(dx: 3, dy: 4)
            for id in [ComposedWindowControlID.fullOrHalfHeight, .halfOrThirdHalfHeight] {
                let size = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: id, press: .long))
                let target = try XCTUnwrap(WindowGeometry.composedSizeTargetFrame(
                    currentFrame: initial, size: size, visibleFrame: visible))
                let placement = WindowGeometry.composedSizePlacement(currentFrame: initial, visibleFrame: visible)
                var actual = initial
                var time: TimeInterval = 0
                let result = try WindowFrameAdjustment.run(
                    target: target, read: { actual }, position: { actual.origin = $0 },
                    size: { actual.size = CGSize(width: max($0.width, 800), height: max($0.height, 600)) },
                    check: {}, trace: WindowAdjustmentTrace(command: "test", requestedAt: 0),
                    policy: .compatible, initial: initial, placement: placement,
                    uptime: { time }, wait: { time += 0.02 })
                XCTAssertEqual(result.frame.origin, placement.origin(for: result.frame.size))
                if corner == .center {
                    XCTAssertEqual(result.frame, WindowGeometry.centeredFrame(result.frame, in: visible))
                } else {
                    XCTAssertEqual(point(result.frame, corner), point(initial, corner))
                }
            }
        }
    }

    @MainActor
    func testPreviousReleaseDefaultMigrationIsOnceOnlyAndKeepsCustomBindings() throws {
        let suite = "ComposedSizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous: [ComposedWindowControlID: Int] = [
            .fullOrHalfHeight: kVK_ANSI_Backslash, .twoThirdsWidth: kVK_ANSI_H,
            .halfOrThirdFullHeight: kVK_ANSI_L, .halfOrThirdHalfHeight: kVK_ANSI_O,
            .upperLeftPlacement: kVK_ANSI_U, .lowerLeftPlacement: kVK_ANSI_J,
            .upperRightPlacement: kVK_ANSI_I, .lowerRightPlacement: kVK_ANSI_K,
            .centerPlacement: kVK_Return
        ]
        var raw = Dictionary(uniqueKeysWithValues: previous.map { ($0.key.rawValue, shortcut($0.value)) })
        let custom = shortcut(kVK_ANSI_R)
        raw[ComposedWindowControlID.centerPlacement.rawValue] = custom
        defaults.set(try JSONEncoder().encode(raw), forKey: "composedWindowControlShortcuts")
        defaults.set(true, forKey: "composedScreenshotDefaultsMigrated")
        let settings = AppSettings(defaults: defaults)
        for id in ComposedWindowControlID.allCases {
            XCTAssertEqual(settings.composedWindowControlShortcut(for: id),
                           id == .centerPlacement ? custom : ComposedWindowControlCatalog.defaultShortcuts[id])
        }
        settings.updateComposedWindowControlShortcut(shortcut(kVK_ANSI_H), for: .twoThirdsWidth)
        XCTAssertEqual(AppSettings(defaults: defaults).composedWindowControlShortcut(for: .twoThirdsWidth), shortcut(kVK_ANSI_H))
    }

    private func point(_ frame: CGRect, _ corner: ComposedWindowPlacement) -> CGPoint {
        switch corner {
        case .upperLeft: CGPoint(x: frame.minX, y: frame.minY)
        case .lowerLeft: CGPoint(x: frame.minX, y: frame.maxY)
        case .upperRight: CGPoint(x: frame.maxX, y: frame.minY)
        case .lowerRight: CGPoint(x: frame.maxX, y: frame.maxY)
        case .center: CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    private func shortcut(_ code: Int) -> KeyboardShortcut {
        KeyboardShortcut(keyCode: UInt32(code), carbonModifiers: KeyboardShortcut.panelDefault.carbonModifiers)
    }
}
