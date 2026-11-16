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
        XCTAssertEqual(settings.clipboardHistoryShortcut, .clipboardHistoryDefault)
        XCTAssertTrue(settings.clipboardHistoryEnabled)
        XCTAssertEqual(settings.clipboardHistoryRetention, .oneMonth)
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
    func testUpdatesAndPersistsClipboardHistorySettings() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_H),
            carbonModifiers: UInt32(cmdKey | optionKey)
        )

        settings.updateClipboardHistoryShortcut(shortcut)
        settings.updateClipboardHistoryEnabled(false)
        settings.updateClipboardHistoryRetention(.oneYear)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.clipboardHistoryShortcut, shortcut)
        XCTAssertFalse(restored.clipboardHistoryEnabled)
        XCTAssertEqual(restored.clipboardHistoryRetention, .oneYear)
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

        settings.updateWindowControlShortcut(shortcut, for: .moveWindowToNextScreen)

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.windowControlShortcut(for: .moveWindowToNextScreen), shortcut)
    }

    @MainActor
    func testClassicPreferencesAreIgnoredWithoutDiscardingOtherMouseBindings() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(controlKey | optionKey))
        defaults.set(try JSONEncoder().encode([
            "upperLeft": shortcut, "moveWindowToNextScreen": shortcut
        ]), forKey: "windowControlShortcuts")
        let settings = AppSettings(defaults: defaults)
        settings.updateComposedWindowControlShortcut(shortcut, for: .fullOrHalfHeight)
        settings.updateWindowLongPressThresholdMilliseconds(600)
        settings.updateMouseCommand(.windowControl(.moveWindowToNextScreen), for: .button4, gesture: .doubleClick)
        settings.updateMouseCommand(.showFeaturePanel(.safariWindows), for: .button5, gesture: .singleClick)
        settings.updateMouseCommand(.composedWindowControl(.lowerRightPlacement), for: .button5, gesture: .dragRight)
        let valid = try XCTUnwrap(defaults.data(forKey: "mouseBindings"))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [[String: Any]])
        for (index, retired) in ["upperLeft", "centerWindow", "maximize"].enumerated() {
            raw.insert(["button": 3, "gesture": ["singleClick", "dragUp", "dragDown"][index],
                        "command": ["windowControl": ["_0": retired]]], at: index)
        }
        defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: "mouseBindings")
        defaults.set("classic", forKey: "windowManagementModeV2")
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.mouseBindings, settings.mouseBindings)
        XCTAssertEqual(restored.windowControlShortcuts.keys.count, 2)
        XCTAssertEqual(restored.windowControlShortcut(for: .moveWindowToNextScreen), shortcut)
        XCTAssertEqual(restored.composedWindowControlShortcut(for: .fullOrHalfHeight), shortcut)
        XCTAssertEqual(restored.windowLongPressThresholdMilliseconds, 600)
        XCTAssertEqual(restored.cursorHighlightStyles, settings.cursorHighlightStyles)
        restored.updateMouseCommand(.composedWindowControl(.centerPlacement), for: .button4, gesture: .singleClick)
        XCTAssertEqual(AppSettings(defaults: defaults).mouseBindings, restored.mouseBindings)
    }

    @MainActor
    func testVolumeRulesDefaultOffAndPersistIndependently() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let rules: Set<KeyboardRemappingRule> = [.f10Mute, .f11VolumeDown, .f12VolumeUp]
        XCTAssertTrue(settings.keyboardRemappingRules.isDisjoint(with: rules))
        for rule in rules { settings.updateKeyboardRemappingRule(rule, enabled: true) }
        settings.updateKeyboardRemappingRule(.f11VolumeDown, enabled: false)
        XCTAssertEqual(AppSettings(defaults: defaults).keyboardRemappingRules, [.f10Mute, .f12VolumeUp])
    }

    @MainActor
    func testCapsInputSourceSwitchDefaultsOffAndPersistsIndependently() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.keyboardRemappingRules.contains(.capsInputSourceSwitch))
        settings.updateKeyboardRemappingRule(.capsShortcuts, enabled: true)
        settings.updateKeyboardRemappingRule(.capsInputSourceSwitch, enabled: true)
        settings.updateKeyboardRemappingRule(.capsShortcuts, enabled: false)
        XCTAssertEqual(AppSettings(defaults: defaults).keyboardRemappingRules,
                       [.capsInputSourceSwitch])
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
        XCTAssertEqual(StatusMenuController.toolPanelTitle, "工具面板")
        XCTAssertEqual(StatusMenuController.closedLidRunningTitle, "合盖运行")
        XCTAssertEqual(StatusMenuController.checkForUpdatesTitle, "检查更新…")
        XCTAssertEqual(StatusMenuController.checkForBetaUpdatesTitle, "检查 Beta 更新…")
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
