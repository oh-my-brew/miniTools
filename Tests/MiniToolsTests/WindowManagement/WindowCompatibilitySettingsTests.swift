import Foundation
import XCTest
@testable import MiniTools

final class WindowCompatibilitySettingsTests: XCTestCase {
    private let notes = "com.apple.Notes"

    @MainActor
    func testNewSettingsIncludeNotesAlongsideExistingApplications() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.windowCompatibilityApplications, WindowAdjustmentPolicy.defaultBundleIdentifiers)
        XCTAssertEqual(settings.windowCompatibilityApplications.count, 7)
        XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: notes,
                       compatibleApplications: settings.windowCompatibilityApplications), .compatible)
    }

    @MainActor
    func testNotesCanBeAddedWithoutDuplicatesAndPersists() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.addWindowCompatibilityApplication(notes)
        settings.addWindowCompatibilityApplication(notes)
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.windowCompatibilityApplications.count, 7)
        XCTAssertTrue(restored.windowCompatibilityApplications.isSuperset(of: WindowAdjustmentPolicy.defaultBundleIdentifiers))
        XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: notes,
                       compatibleApplications: restored.windowCompatibilityApplications), .compatible)
    }

    @MainActor
    func testRemovingBuiltInsAndClearingAllSurvivesReload() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.removeWindowCompatibilityApplication("com.apple.Safari")
        XCTAssertFalse(AppSettings(defaults: defaults).windowCompatibilityApplications.contains("com.apple.Safari"))
        for identifier in settings.windowCompatibilityApplications {
            settings.removeWindowCompatibilityApplication(identifier)
        }
        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.windowCompatibilityApplications.isEmpty)
        XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: "com.apple.Safari",
                       compatibleApplications: restored.windowCompatibilityApplications), .baseline)
    }

    @MainActor
    func testExplicitRestoreReplacesCustomListWithDefaults() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.removeWindowCompatibilityApplication("com.apple.Safari")
        settings.addWindowCompatibilityApplication(notes)
        settings.restoreDefaultWindowCompatibilityApplications()
        XCTAssertEqual(AppSettings(defaults: defaults).windowCompatibilityApplications,
                       WindowAdjustmentPolicy.defaultBundleIdentifiers)
    }

    func testConfiguredListReplacesBuiltInsAndUsesExactIdentifiers() {
        let configured: Set<String> = [notes]
        for other in [nil, "com.apple.Safari", "com.apple.Notes.Helper", "com.apple.notes", "com.apple.*"] {
            XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: other,
                           compatibleApplications: configured), .baseline)
        }
        XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: notes,
                       compatibleApplications: configured), .compatible)
    }

    func testMetadataRequiresAnApplicationAndValidIdentifier() throws {
        let app = try XCTUnwrap(WindowCompatibilityApplication(info: [
            "CFBundleIdentifier": notes, "CFBundlePackageType": "APPL", "CFBundleDisplayName": "备忘录"
        ]))
        XCTAssertEqual(app.bundleIdentifier, notes)
        XCTAssertEqual(app.name, "备忘录")
        XCTAssertNil(WindowCompatibilityApplication(info: ["CFBundleIdentifier": notes]))
        XCTAssertNil(WindowCompatibilityApplication(info: ["CFBundleIdentifier": notes, "CFBundlePackageType": "BNDL"]))
        XCTAssertNil(WindowCompatibilityApplication(info: ["CFBundlePackageType": "APPL"]))
        let fallback = WindowCompatibilityApplication(info: [
            "CFBundleIdentifier": notes, "CFBundlePackageType": "APPL", "CFBundleDisplayName": "  ", "CFBundleName": "Notes"
        ])
        XCTAssertEqual(fallback?.name, "Notes")
    }

    @MainActor
    func testInvalidOrWildcardIdentifiersNeverExpandTheList() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        for invalid in ["", "*", "com.apple.*", "com apple.Notes", "com.apple.Notes\n", "/Applications/Notes.app", ".com.apple", "com..apple"] {
            XCTAssertFalse(WindowCompatibilityApplication.isValidBundleIdentifier(invalid))
            settings.addWindowCompatibilityApplication(invalid)
        }
        XCTAssertEqual(settings.windowCompatibilityApplications, WindowAdjustmentPolicy.defaultBundleIdentifiers)
    }

    @MainActor
    func testStoredListFiltersInvalidEntriesAndRetainsUnknownApps() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([notes, notes, "com.example.NotInstalled", "*", ""], forKey: "windowCompatibilityApplications")
        XCTAssertEqual(AppSettings(defaults: defaults).windowCompatibilityApplications, [notes, "com.example.NotInstalled"])
        defaults.set(42, forKey: "windowCompatibilityApplications")
        XCTAssertEqual(AppSettings(defaults: defaults).windowCompatibilityApplications, WindowAdjustmentPolicy.defaultBundleIdentifiers)
    }

    @MainActor
    func testActionSnapshotIsIndependentOfLaterSettingsChanges() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let custom = "com.example.WindowApp"
        let snapshot = settings.windowCompatibilityApplications
        settings.addWindowCompatibilityApplication(custom)
        XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: custom, compatibleApplications: snapshot), .baseline)
        XCTAssertEqual(WindowAdjustmentPolicy.resolve(bundleIdentifier: custom,
                       compatibleApplications: settings.windowCompatibilityApplications), .compatible)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "WindowCompatibilitySettingsTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
}
