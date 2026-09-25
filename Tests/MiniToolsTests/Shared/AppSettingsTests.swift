import Carbon
import XCTest
@testable import MiniTools

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testUsesUnifiedPanelShortcutAndEncodingPanelByDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.panelShortcut, .panelDefault)
        XCTAssertEqual(settings.panelShortcut.displayName, "⌃⌥⇧⌘Space")
        XCTAssertEqual(settings.lastFeaturePanel, .encodingConversion)
    }

    @MainActor
    func testMigratesLegacyDefaultsToUnifiedPanelDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONEncoder().encode(KeyboardShortcut.legacyEncodingPanelDefault),
            forKey: "globalShortcut"
        )
        defaults.set(
            try JSONEncoder().encode(KeyboardShortcut.legacySafariPanelDefault),
            forKey: "safariGlobalShortcut"
        )

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.panelShortcut, .panelDefault)
    }

    @MainActor
    func testMigratesPreviousEncodingShortcutToUnifiedPanelShortcut() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_E),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        defaults.set(
            try JSONEncoder().encode(shortcut),
            forKey: "encodingConversionShortcut"
        )

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.panelShortcut, shortcut)
        let migratedData = try XCTUnwrap(defaults.data(forKey: "panelShortcut"))
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcut.self, from: migratedData), shortcut)
    }

    @MainActor
    func testMigratesCustomizedSafariShortcutWhenNoEncodingShortcutExists() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_B),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        )
        defaults.set(
            try JSONEncoder().encode(shortcut),
            forKey: "safariWindowShortcut"
        )

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.panelShortcut, shortcut)
    }

    @MainActor
    func testUpdatesAndPersistsPanelShortcut() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_C),
            carbonModifiers: UInt32(cmdKey | controlKey)
        )

        settings.updatePanelShortcut(shortcut)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.panelShortcut, shortcut)
    }

    @MainActor
    func testMigratesPreviousPanelDefaultToNewDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONEncoder().encode(KeyboardShortcut.previousPanelDefault),
            forKey: "panelShortcut"
        )

        XCTAssertEqual(AppSettings(defaults: defaults).panelShortcut, .panelDefault)
    }

    @MainActor
    func testUpdatesAndPersistsLastFeaturePanel() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.updateLastFeaturePanel(.safariWindows)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.lastFeaturePanel, .safariWindows)
    }

    @MainActor
    func testUpdatesAndPersistsWindowControlShortcut() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_M),
            carbonModifiers: UInt32(controlKey | optionKey)
        )

        settings.updateWindowControlShortcut(shortcut, for: .centerWindow)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.windowControlShortcut(for: .centerWindow), shortcut)
    }

    @MainActor
    func testSystemWindowActionsDefaultToDisabledAndPersist() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.usesSystemWindowActions)
        settings.updateUsesSystemWindowActions(true)

        XCTAssertTrue(AppSettings(defaults: defaults).usesSystemWindowActions)
    }

    @MainActor
    func testEnablesEveryCursorHighlightStyleByDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.cursorHighlightStyles, Set(CursorHighlightStyle.allCases))
    }

    @MainActor
    func testUpdatesAndPersistsCursorHighlightStyles() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.updateCursorHighlightStyle(.spectrumFlow, isEnabled: false))
        XCTAssertTrue(settings.updateCursorHighlightStyle(.mangekyoItachi, isEnabled: false))

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.cursorHighlightStyles.contains(.spectrumFlow))
        XCTAssertFalse(restored.cursorHighlightStyles.contains(.mangekyoItachi))
        XCTAssertEqual(
            restored.cursorHighlightStyles.count,
            CursorHighlightStyle.allCases.count - 2
        )
    }

    @MainActor
    func testRestoresGameCursorStyleToAnExistingSelectionOnce() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONEncoder().encode([
                CursorHighlightStyle.mangekyoItachi
            ]),
            forKey: "cursorHighlightStyles"
        )

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(
            settings.cursorHighlightStyles,
            [.mangekyoHikari, .mangekyoItachi]
        )

        XCTAssertTrue(
            settings.updateCursorHighlightStyle(.mangekyoHikari, isEnabled: false)
        )
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.cursorHighlightStyles, [.mangekyoItachi])
    }

    @MainActor
    func testAllowsEveryCursorHighlightStyleToBeDisabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        for style in CursorHighlightStyle.allCases {
            XCTAssertTrue(settings.updateCursorHighlightStyle(style, isEnabled: false))
        }

        XCTAssertTrue(settings.cursorHighlightStyles.isEmpty)
        XCTAssertTrue(AppSettings(defaults: defaults).cursorHighlightStyles.isEmpty)
    }

    @MainActor
    func testClosedLidRunningMenuTitles() {
        XCTAssertEqual(StatusMenuController.enableClosedLidRunningTitle, "启动合盖运行")
        XCTAssertEqual(StatusMenuController.disableClosedLidRunningTitle, "关闭合盖运行")
    }

    @MainActor
    func testPersistsClosedLidRunningFeatureSwitch() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.closedLidRunningEnabled)
        settings.updateClosedLidRunningEnabled(true)
        XCTAssertTrue(AppSettings(defaults: defaults).closedLidRunningEnabled)
    }

    @MainActor
    func testDSStoreManagementDefaultsToDisabledAndPersistsConfiguration() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.dsStoreManagementEnabled)
        XCTAssertFalse(settings.launchAtLoginEnabled)

        settings.updateDSStoreManagementEnabled(true)
        settings.updateLaunchAtLoginEnabled(true)

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.dsStoreManagementEnabled)
        XCTAssertTrue(restored.launchAtLoginEnabled)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MiniToolsTests.AppSettings.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
