import Foundation
@testable import MiniTools
import XCTest

@MainActor
final class UsageStatisticsStoreTests: XCTestCase {
    func testRecordsOnlyRequestedSuccessfulActionsAndPersists() throws {
        let defaults = try makeDefaults()
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-25T08:00:00Z"))
        let store = UsageStatisticsStore(defaults: defaults)

        store.record(
            id: "base64Encode",
            title: "Base64 编码",
            category: .encodingConversion,
            at: date
        )
        store.record(
            id: "base64Encode",
            title: "Base64 编码",
            category: .encodingConversion,
            at: date
        )

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[0].totalCount, 2)
        XCTAssertEqual(store.count(for: store.records[0], recentDays: 7, relativeTo: date), 2)

        let restored = UsageStatisticsStore(defaults: defaults)
        XCTAssertEqual(restored.records, store.records)
    }

    func testRecentCountsAndClear() throws {
        let defaults = try makeDefaults()
        let formatter = ISO8601DateFormatter()
        let oldDate = try XCTUnwrap(formatter.date(from: "2026-08-01T08:00:00Z"))
        let recentDate = try XCTUnwrap(formatter.date(from: "2026-09-24T08:00:00Z"))
        let now = try XCTUnwrap(formatter.date(from: "2026-09-25T08:00:00Z"))
        let store = UsageStatisticsStore(defaults: defaults)

        store.record(id: "left", title: "左侧区域", category: .windowManagement, at: oldDate)
        store.record(id: "left", title: "左侧区域", category: .windowManagement, at: recentDate)

        XCTAssertEqual(store.totalCount(), 2)
        XCTAssertEqual(store.totalCount(recentDays: 7, relativeTo: now), 1)

        store.clear(at: now)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(store.startedAt, now)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "UsageStatisticsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
