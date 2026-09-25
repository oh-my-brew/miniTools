import Foundation

enum UsageStatisticsCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case encodingConversion
    case windowManagement
    case mouseCrossScreen

    var id: Self { self }

    var title: String {
        switch self {
        case .encodingConversion: "编码与转换"
        case .windowManagement: "窗口管理"
        case .mouseCrossScreen: "鼠标跨屏"
        }
    }
}

struct UsageStatisticsRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let category: UsageStatisticsCategory
    var title: String
    var totalCount: Int
    var lastUsedAt: Date
    var dailyCounts: [String: Int]
}

private struct UsageStatisticsArchive: Codable {
    var startedAt: Date
    var records: [UsageStatisticsRecord]
}

@MainActor
final class UsageStatisticsStore: ObservableObject {
    static let retentionDays = 90

    @Published private(set) var startedAt: Date
    @Published private(set) var records: [UsageStatisticsRecord]

    private let defaults: UserDefaults
    private let storageKey: String
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "usageStatisticsArchive",
        calendar: Calendar = UsageStatisticsStore.utcCalendar
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.calendar = calendar

        if let data = defaults.data(forKey: storageKey),
           let archive = try? JSONDecoder().decode(UsageStatisticsArchive.self, from: data) {
            startedAt = archive.startedAt
            records = archive.records
        } else {
            startedAt = Date()
            records = []
            let archive = UsageStatisticsArchive(startedAt: startedAt, records: records)
            if let data = try? JSONEncoder().encode(archive) {
                defaults.set(data, forKey: storageKey)
            }
        }
    }

    func record(
        id: String,
        title: String,
        category: UsageStatisticsCategory,
        at date: Date = Date()
    ) {
        let recordID = "\(category.rawValue).\(id)"
        let day = dayKey(for: date)

        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].title = title
            records[index].totalCount += 1
            records[index].lastUsedAt = date
            records[index].dailyCounts[day, default: 0] += 1
        } else {
            records.append(UsageStatisticsRecord(
                id: recordID,
                category: category,
                title: title,
                totalCount: 1,
                lastUsedAt: date,
                dailyCounts: [day: 1]
            ))
        }

        pruneDailyCounts(relativeTo: date)
        persist()
    }

    func count(
        for record: UsageStatisticsRecord,
        recentDays: Int,
        relativeTo date: Date = Date()
    ) -> Int {
        guard recentDays > 0 else { return 0 }
        let start = calendar.date(
            byAdding: .day,
            value: -(recentDays - 1),
            to: calendar.startOfDay(for: date)
        ) ?? date
        return record.dailyCounts.reduce(into: 0) { result, entry in
            guard let day = parsedDate(forDayKey: entry.key), day >= start else { return }
            result += entry.value
        }
    }

    func totalCount(recentDays: Int? = nil, relativeTo date: Date = Date()) -> Int {
        records.reduce(into: 0) { result, record in
            result += recentDays.map {
                count(for: record, recentDays: $0, relativeTo: date)
            } ?? record.totalCount
        }
    }

    func records(in category: UsageStatisticsCategory) -> [UsageStatisticsRecord] {
        records
            .filter { $0.category == category }
            .sorted {
                let lhsCount = count(for: $0, recentDays: 30)
                let rhsCount = count(for: $1, recentDays: 30)
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                if $0.totalCount != $1.totalCount { return $0.totalCount > $1.totalCount }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func clear(at date: Date = Date()) {
        startedAt = date
        records = []
        persist()
    }

    private func pruneDailyCounts(relativeTo date: Date) {
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(Self.retentionDays - 1),
            to: calendar.startOfDay(for: date)
        ) ?? date
        for index in records.indices {
            records[index].dailyCounts = records[index].dailyCounts.filter { entry in
                guard let day = parsedDate(forDayKey: entry.key) else { return false }
                return day >= cutoff
            }
        }
    }

    private func persist() {
        let archive = UsageStatisticsArchive(startedAt: startedAt, records: records)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func dayKey(for date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func parsedDate(forDayKey key: String) -> Date? {
        Self.dayFormatter.date(from: key)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
