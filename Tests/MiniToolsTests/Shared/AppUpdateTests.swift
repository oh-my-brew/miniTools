import Foundation
import Sparkle
import XCTest
@testable import MiniTools

final class AppUpdateTests: XCTestCase {
    func testVersionDisplayIncludesMatchingBetaBuildRound() {
        XCTAssertEqual(AppVersion.displayName(version: "2026.10.20.1", build: "20261020.1.3"),
                       "2026.10.20.1 · Beta 构建 3")
        XCTAssertEqual(AppVersion.displayName(version: "2026.10.20.1", build: "50"), "2026.10.20.1")
        XCTAssertEqual(AppVersion.displayName(version: "2026.10.20.1", build: "20261019.1.3"), "2026.10.20.1")
        XCTAssertEqual(AppVersion.displayName(version: "2026.10.20.1", build: "20261020.1.0"), "2026.10.20.1")
        XCTAssertEqual(AppVersion.displayName(version: nil, build: nil), "开发构建")
    }

    func testCalendarBuildVersionSortsAfterLegacyWorkflowRunNumber() {
        let comparator = SUStandardVersionComparator.default

        XCTAssertEqual(
            comparator.compareVersion("41", toVersion: "20261019.4.1"),
            .orderedAscending
        )
        XCTAssertEqual(
            comparator.compareVersion("20261019.4.1", toVersion: "20261019.4.2"),
            .orderedAscending
        )
        XCTAssertEqual(
            comparator.compareVersion("20261019.4.2", toVersion: "20261020.1.1"),
            .orderedAscending
        )
    }

    @MainActor
    func testUpdateChannelsUseSeparateSignedFeedLocations() {
        XCTAssertEqual(
            AppUpdateChannel.stable.feedURL.absoluteString,
            "https://github.com/oh-my-brew/miniTools/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            AppUpdateChannel.beta.feedURL.absoluteString,
            "https://github.com/oh-my-brew/miniTools/releases/download/beta/appcast-beta.xml"
        )
    }
}
