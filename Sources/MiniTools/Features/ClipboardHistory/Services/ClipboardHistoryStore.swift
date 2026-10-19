import AppKit
import Foundation

actor ClipboardHistoryStore {
    enum StoreError: LocalizedError {
        case missingPayload

        var errorDescription: String? { "剪贴板历史内容不完整" }
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadItems(retention: ClipboardHistoryRetention, now: Date = Date()) throws -> [ClipboardHistoryItem] {
        try ensureRootExists()
        var items: [ClipboardHistoryItem] = []
        for directory in try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let metadataURL = directory.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let item = try? decoder.decode(ClipboardHistoryItem.self, from: data) else {
                continue
            }
            items.append(item)
        }
        let kept = try prune(items: items, retention: retention, now: now)
        return kept.sorted { $0.copiedAt > $1.copiedAt }
    }

    func save(
        _ capture: ClipboardHistoryCapture,
        replacing duplicate: ClipboardHistoryItem? = nil
    ) throws -> ClipboardHistoryItem {
        try ensureRootExists()
        if let duplicate {
            try? fileManager.removeItem(at: itemDirectory(duplicate.id))
        }
        let directory = itemDirectory(capture.item.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (descriptor, payload) in zip(capture.item.representations, capture.payloads) {
            try payload.data.write(
                to: directory.appendingPathComponent(descriptor.fileName),
                options: .atomic
            )
        }
        if let thumbnailData = capture.thumbnailData,
           let fileName = capture.item.thumbnailFileName {
            try thumbnailData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        }
        try encoder.encode(capture.item).write(
            to: directory.appendingPathComponent("metadata.json"),
            options: .atomic
        )
        return capture.item
    }

    func payloads(for item: ClipboardHistoryItem) throws -> [ClipboardHistoryCapturedRepresentation] {
        let directory = itemDirectory(item.id)
        return try item.representations.map { representation in
            let url = directory.appendingPathComponent(representation.fileName)
            guard let data = try? Data(contentsOf: url) else { throw StoreError.missingPayload }
            return ClipboardHistoryCapturedRepresentation(
                itemIndex: representation.itemIndex,
                typeIdentifier: representation.typeIdentifier,
                data: data
            )
        }
    }

    func thumbnailData(for item: ClipboardHistoryItem) -> Data? {
        guard let fileName = item.thumbnailFileName else { return nil }
        return try? Data(contentsOf: itemDirectory(item.id).appendingPathComponent(fileName))
    }

    func previewURL(for item: ClipboardHistoryItem) throws -> URL? {
        if item.kind == .files,
           let payload = try payloads(for: item).first(where: {
               $0.typeIdentifier == NSPasteboard.PasteboardType.fileURL.rawValue
           }),
           let value = String(data: payload.data, encoding: .utf8),
           let url = URL(string: value) {
            return url
        }
        let payloads = try payloads(for: item)
        let preferred = payloads.first(where: { $0.typeIdentifier == "public.png" })
            ?? payloads.first(where: { $0.typeIdentifier == "public.tiff" })
            ?? payloads.first(where: { $0.typeIdentifier == "public.jpeg" })
            ?? payloads.first(where: { $0.typeIdentifier == NSPasteboard.PasteboardType.rtf.rawValue })
            ?? payloads.first(where: { $0.typeIdentifier == NSPasteboard.PasteboardType.html.rawValue })
        let data: Data
        let fileExtension: String
        if let preferred {
            data = preferred.data
            fileExtension = previewExtension(for: preferred.typeIdentifier)
        } else if let plainText = item.plainText {
            data = Data(plainText.utf8)
            fileExtension = "txt"
        } else {
            return nil
        }
        let previewDirectory = rootURL.appendingPathComponent("Previews", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let url = previewDirectory.appendingPathComponent("\(item.id.uuidString).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }

    func delete(_ item: ClipboardHistoryItem) throws {
        try fileManager.removeItem(at: itemDirectory(item.id))
    }

    func deleteAll() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try ensureRootExists()
    }

    private func prune(
        items: [ClipboardHistoryItem],
        retention: ClipboardHistoryRetention,
        now: Date
    ) throws -> [ClipboardHistoryItem] {
        guard let interval = retention.interval else { return items }
        let cutoff = now.addingTimeInterval(-interval)
        var kept: [ClipboardHistoryItem] = []
        for item in items {
            if item.copiedAt < cutoff {
                try? fileManager.removeItem(at: itemDirectory(item.id))
            } else {
                kept.append(item)
            }
        }
        return kept
    }

    private func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func itemDirectory(_ id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func previewExtension(for type: String) -> String {
        if type.contains("png") { return "png" }
        if type.contains("tiff") { return "tiff" }
        if type.contains("jpeg") { return "jpg" }
        if type == NSPasteboard.PasteboardType.rtf.rawValue { return "rtf" }
        if type == NSPasteboard.PasteboardType.html.rawValue { return "html" }
        return "dat"
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("com.omzcj.minitools", isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
    }
}
