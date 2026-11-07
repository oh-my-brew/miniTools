import Carbon
import CoreGraphics
import XCTest
@testable import MiniTools

@MainActor
final class WindowDefaultsUpdateTests: XCTestCase {
    func testFreshAndHistoricalDefaultsUsePunctuationKeys() throws {
        for historical in [false, true] {
            let suite = "WindowDefaultsUpdateTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if historical {
                try store([.moveWindowToNextScreen: shortcut(kVK_ANSI_P),
                           .movePointerToNextScreen: shortcut(kVK_ANSI_Semicolon)], in: defaults)
            }
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.windowControlShortcut(for: .moveWindowToNextScreen), shortcut(kVK_ANSI_Semicolon))
            XCTAssertEqual(settings.windowControlShortcut(for: .movePointerToNextScreen), shortcut(kVK_ANSI_Quote))
            XCTAssertEqual(settings.windowControlShortcut(for: .movePointerToNextScreen).displayName, "⌃⌥⇧⌘'")
            XCTAssertEqual(settings.panelShortcut, .panelDefault)
        }
    }

    func testCustomBindingsSurviveMigrationAndOldKeysCanBeChosenAfterward() throws {
        let suite = "WindowDefaultsUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try store([.moveWindowToNextScreen: shortcut(kVK_ANSI_N),
                   .movePointerToNextScreen: shortcut(kVK_ANSI_M),
                   .upperLeft: shortcut(kVK_ANSI_A)], in: defaults)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.windowControlShortcut(for: .moveWindowToNextScreen), shortcut(kVK_ANSI_N))
        XCTAssertEqual(settings.windowControlShortcut(for: .movePointerToNextScreen), shortcut(kVK_ANSI_M))
        XCTAssertEqual(settings.windowControlShortcut(for: .upperLeft), shortcut(kVK_ANSI_A))
        settings.updateWindowControlShortcut(shortcut(kVK_ANSI_P), for: .moveWindowToNextScreen)
        settings.updateWindowControlShortcut(shortcut(kVK_ANSI_Semicolon), for: .movePointerToNextScreen)
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.windowControlShortcut(for: .moveWindowToNextScreen), shortcut(kVK_ANSI_P))
        XCTAssertEqual(restored.windowControlShortcut(for: .movePointerToNextScreen), shortcut(kVK_ANSI_Semicolon))
    }

    func testStoredSixAppListIsNotExpandedAndRemovedNotesStayRemoved() throws {
        let suite = "WindowDefaultsUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous = WindowAdjustmentPolicy.defaultBundleIdentifiers.subtracting(["com.apple.Notes"])
        defaults.set(Array(previous), forKey: "windowCompatibilityApplications")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.windowCompatibilityApplications, previous)
        settings.restoreDefaultWindowCompatibilityApplications()
        XCTAssertTrue(settings.windowCompatibilityApplications.contains("com.apple.Notes"))
        settings.removeWindowCompatibilityApplication("com.apple.Notes")
        XCTAssertEqual(AppSettings(defaults: defaults).windowCompatibilityApplications, previous)
    }

    func testUShortAndLongPressTargetsKeepIUnchangedAndPositionTopBottom() throws {
        XCTAssertEqual(ComposedWindowControlCatalog.descriptor(for: .twoThirdsWidth)?.supportsLongPress, false)
        XCTAssertEqual(ComposedWindowControlCatalog.descriptor(for: .fullOrHalfHeight)?.supportsLongPress, true)
        let short = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .twoThirdsWidth, press: .short))
        let long = try XCTUnwrap(ComposedWindowControlCatalog.sizeTarget(for: .fullOrHalfHeight, press: .long))
        XCTAssertEqual(short.frame, UnitWindowFrame(1.0 / 6, 0, 2.0 / 3, 1))
        XCTAssertEqual(long.frame, UnitWindowFrame(0, 0, 1, 0.5))
        XCTAssertEqual(ComposedWindowControlCatalog.sizeTarget(for: .fullOrHalfHeight, press: .short)?.frame, UnitWindowFrame(0, 0, 1, 1))
        let screen = CGRect(x: -1440, y: 40, width: 1440, height: 900)
        let frame = WindowGeometry.targetFrame(for: long.frame, in: screen)
        let top = WindowGeometry.composedPlacementTarget(currentFrame: frame, visibleFrame: screen, placement: .upperLeft)
        let bottom = WindowGeometry.composedPlacementTarget(currentFrame: frame, visibleFrame: screen, placement: .lowerLeft)
        XCTAssertEqual(top.frame, frame)
        XCTAssertEqual(bottom.frame, CGRect(x: -1440, y: 490, width: 1440, height: 450))
        XCTAssertEqual(WindowGeometry.composedPlacementTarget(currentFrame: frame, visibleFrame: screen, placement: .center).frame,
                       CGRect(x: -1440, y: 265, width: 1440, height: 450))
    }

    private func shortcut(_ code: Int) -> KeyboardShortcut {
        KeyboardShortcut(keyCode: UInt32(code), carbonModifiers: KeyboardShortcut.panelDefault.carbonModifiers)
    }

    private func store(_ shortcuts: [WindowControlID: KeyboardShortcut], in defaults: UserDefaults) throws {
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        defaults.set(try JSONEncoder().encode(raw), forKey: "windowControlShortcuts")
    }
}
