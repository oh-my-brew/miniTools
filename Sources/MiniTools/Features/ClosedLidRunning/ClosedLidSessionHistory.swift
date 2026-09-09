import Foundation

enum ClosedLidStopReason: String, Codable, Equatable, Sendable {
    case manual
    case lowBattery
    case legacyAutomatic

    var title: String {
        switch self {
        case .manual: "手动关闭"
        case .lowBattery: "电量低于 20% 后自动关闭"
        case .legacyAutomatic: "旧版本自动关闭"
        }
    }
}

struct ClosedLidSessionHistory: Codable, Equatable, Sendable {
    let startedAt: Date
    let stoppedAt: Date?
    let stopReason: ClosedLidStopReason?

    var isActive: Bool { stoppedAt == nil }

    var stopSummary: String? {
        guard let stoppedAt, let stopReason else { return nil }
        let timestamp = stoppedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
        )
        return "\(timestamp) · \(stopReason.title)"
    }
}

private struct ClosedLidSessionHistoryArchive: Codable {
    let activeSession: ClosedLidSessionHistory?
    let recentClosedSessions: [ClosedLidSessionHistory]
}

private struct LegacyClosedLidSessionHistoryArchive: Decodable {
    struct Session: Decodable {
        let startedAt: Date
        let stoppedAt: Date?
        let stopReason: String?
    }

    let activeSession: Session?
    let recentClosedSessions: [Session]?
}

@MainActor
final class ClosedLidSessionHistoryStore {
    static let maximumRecentSessionCount = 5

    private static let storageKey = "closedLidSessionHistoryArchiveV4"
    private static let obsoleteStorageKeys = [
        "closedLidSessionHistoryArchiveV3",
        "closedLidSessionHistoryArchiveV2",
        "closedLidSessionHistory"
    ]

    private let defaults: UserDefaults
    private(set) var activeSession: ClosedLidSessionHistory?
    private(set) var recentClosedSessions: [ClosedLidSessionHistory]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let archive = try? JSONDecoder().decode(
               ClosedLidSessionHistoryArchive.self,
               from: data
           ) {
            activeSession = archive.activeSession?.isActive == true
                ? archive.activeSession
                : nil
            recentClosedSessions = Array(
                archive.recentClosedSessions
                    .filter { !$0.isActive && $0.stopReason != nil }
                    .prefix(Self.maximumRecentSessionCount)
            )
            return
        }

        let legacyArchive = Self.obsoleteStorageKeys
            .compactMap { defaults.data(forKey: $0) }
            .compactMap {
                try? JSONDecoder().decode(LegacyClosedLidSessionHistoryArchive.self, from: $0)
            }
            .first
        activeSession = legacyArchive?.activeSession.flatMap(Self.migrateActiveSession)
        recentClosedSessions = Array(
            (legacyArchive?.recentClosedSessions ?? [])
                .compactMap(Self.migrateClosedSession)
                .prefix(Self.maximumRecentSessionCount)
        )
        for key in Self.obsoleteStorageKeys { defaults.removeObject(forKey: key) }
        persist()
    }

    @discardableResult
    func recordStarted(at date: Date = Date()) -> ClosedLidSessionHistory {
        let session = ClosedLidSessionHistory(
            startedAt: date,
            stoppedAt: nil,
            stopReason: nil
        )
        activeSession = session
        persist()
        return session
    }

    @discardableResult
    func recordStopped(
        reason: ClosedLidStopReason,
        at date: Date = Date()
    ) -> ClosedLidSessionHistory? {
        guard let current = activeSession else { return recentClosedSessions.first }
        let session = ClosedLidSessionHistory(
            startedAt: current.startedAt,
            stoppedAt: date,
            stopReason: reason
        )
        activeSession = nil
        recentClosedSessions.insert(session, at: 0)
        if recentClosedSessions.count > Self.maximumRecentSessionCount {
            recentClosedSessions.removeLast(
                recentClosedSessions.count - Self.maximumRecentSessionCount
            )
        }
        persist()
        return session
    }

    private static func migrateActiveSession(
        _ session: LegacyClosedLidSessionHistoryArchive.Session
    ) -> ClosedLidSessionHistory? {
        guard session.stoppedAt == nil else { return nil }
        return ClosedLidSessionHistory(
            startedAt: session.startedAt,
            stoppedAt: nil,
            stopReason: nil
        )
    }

    private static func migrateClosedSession(
        _ session: LegacyClosedLidSessionHistoryArchive.Session
    ) -> ClosedLidSessionHistory? {
        guard let stoppedAt = session.stoppedAt, let rawReason = session.stopReason else {
            return nil
        }
        let reason: ClosedLidStopReason = switch rawReason {
        case "manual": .manual
        case "lowBattery": .lowBattery
        default: .legacyAutomatic
        }
        return ClosedLidSessionHistory(
            startedAt: session.startedAt,
            stoppedAt: stoppedAt,
            stopReason: reason
        )
    }

    private func persist() {
        let archive = ClosedLidSessionHistoryArchive(
            activeSession: activeSession,
            recentClosedSessions: recentClosedSessions
        )
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
