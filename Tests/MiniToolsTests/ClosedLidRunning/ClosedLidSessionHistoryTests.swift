import Foundation
import XCTest
@testable import MiniTools

@MainActor
final class ClosedLidSessionHistoryTests: XCTestCase {
    func testPersistsActiveSessionAndCompletedHistory() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let startedAt = Date(timeIntervalSince1970: 100)
        let stoppedAt = Date(timeIntervalSince1970: 200)
        let store = ClosedLidSessionHistoryStore(defaults: defaults)

        let active = ClosedLidSessionHistory(
            startedAt: startedAt,
            stoppedAt: nil,
            stopReason: nil
        )
        XCTAssertEqual(store.recordStarted(at: startedAt), active)

        let completed = ClosedLidSessionHistory(
            startedAt: startedAt,
            stoppedAt: stoppedAt,
            stopReason: .lowBattery
        )
        XCTAssertEqual(store.recordStopped(reason: .lowBattery, at: stoppedAt), completed)
        XCTAssertEqual(store.recentClosedSessions, [completed])
        XCTAssertEqual(
            ClosedLidSessionHistoryStore(defaults: defaults).recentClosedSessions,
            [completed]
        )
    }

    func testKeepsOnlyFiveMostRecentClosedSessions() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ClosedLidSessionHistoryStore(defaults: defaults)

        for index in 0..<7 {
            store.recordStarted(at: Date(timeIntervalSince1970: TimeInterval(index * 10)))
            store.recordStopped(
                reason: index.isMultiple(of: 2) ? .manual : .lowBattery,
                at: Date(timeIntervalSince1970: TimeInterval(index * 10 + 5))
            )
        }

        XCTAssertEqual(store.recentClosedSessions.count, 5)
        XCTAssertEqual(
            store.recentClosedSessions.compactMap(\.stoppedAt),
            [65, 55, 45, 35, 25].map(Date.init(timeIntervalSince1970:))
        )
    }

    func testMigratesLegacyDurationsAndStopReasons() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = LegacyHistoryArchive(
            activeSession: nil,
            recentClosedSessions: [
                LegacySession(
                    startedAt: Date(timeIntervalSince1970: 100),
                    stoppedAt: Date(timeIntervalSince1970: 200),
                    stopReason: "thermalPressure",
                    duration: "twoHours"
                )
            ]
        )
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "closedLidSessionHistoryArchiveV3"
        )

        let store = ClosedLidSessionHistoryStore(defaults: defaults)

        XCTAssertEqual(store.recentClosedSessions.first?.stopReason, .legacyAutomatic)
        XCTAssertNil(defaults.data(forKey: "closedLidSessionHistoryArchiveV3"))
    }

    func testBatteryPolicyUsesHysteresisAndOneMinuteInterval() {
        XCTAssertEqual(ClosedLidBatteryPolicy.disableBelowPercent, 20)
        XCTAssertEqual(ClosedLidBatteryPolicy.enableAbovePercent, 25)
        XCTAssertEqual(ClosedLidBatteryPolicy.monitoringInterval, .seconds(60))
        XCTAssertEqual(
            ClosedLidBatteryPolicy.targetSleepDisabled(batteryPercent: 19),
            false
        )
        XCTAssertNil(ClosedLidBatteryPolicy.targetSleepDisabled(batteryPercent: 20))
        XCTAssertNil(ClosedLidBatteryPolicy.targetSleepDisabled(batteryPercent: 25))
        XCTAssertEqual(
            ClosedLidBatteryPolicy.targetSleepDisabled(batteryPercent: 26),
            true
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ClosedLidSessionHistoryTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}

private struct LegacyHistoryArchive: Codable {
    let activeSession: LegacySession?
    let recentClosedSessions: [LegacySession]
}

private struct LegacySession: Codable {
    let startedAt: Date
    let stoppedAt: Date?
    let stopReason: String?
    let duration: String?
}
