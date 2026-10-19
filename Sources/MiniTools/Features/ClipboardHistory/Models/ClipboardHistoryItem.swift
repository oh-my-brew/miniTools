import Foundation

enum ClipboardHistoryKind: String, Codable, Sendable {
    case text
    case richText
    case link
    case color
    case image
    case files

    var title: String {
        switch self {
        case .text: "文本"
        case .richText: "文本"
        case .link: "链接"
        case .color: "颜色"
        case .image: "图片"
        case .files: "文件"
        }
    }
}

enum ClipboardHistoryRetention: String, CaseIterable, Codable, Sendable {
    case oneDay
    case oneWeek
    case oneMonth
    case oneYear
    case forever

    static let defaultValue: Self = .oneMonth

    var title: String {
        switch self {
        case .oneDay: "1 天"
        case .oneWeek: "1 周"
        case .oneMonth: "1 个月"
        case .oneYear: "1 年"
        case .forever: "永久"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .oneDay: 86_400
        case .oneWeek: 7 * 86_400
        case .oneMonth: 30 * 86_400
        case .oneYear: 365 * 86_400
        case .forever: nil
        }
    }
}

struct ClipboardHistoryRepresentation: Codable, Equatable, Sendable {
    let itemIndex: Int
    let typeIdentifier: String
    let fileName: String
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var copiedAt: Date
    var sourceBundleIdentifier: String?
    var sourceApplicationName: String?
    let kind: ClipboardHistoryKind
    let summary: String
    var searchableText: String
    let plainText: String?
    let contentHash: String
    let pixelWidth: Int?
    let pixelHeight: Int?
    let thumbnailFileName: String?
    let representations: [ClipboardHistoryRepresentation]

    var supportsPlainText: Bool {
        guard let plainText else { return false }
        return !plainText.isEmpty
    }
}

struct ClipboardHistoryCapturedRepresentation: Sendable {
    let itemIndex: Int
    let typeIdentifier: String
    let data: Data
}

struct ClipboardHistoryRichTextPayload: Sendable {
    let data: Data
    let typeIdentifier: String
}

struct ClipboardHistoryCapture: Sendable {
    var item: ClipboardHistoryItem
    let payloads: [ClipboardHistoryCapturedRepresentation]
    let thumbnailData: Data?
}
