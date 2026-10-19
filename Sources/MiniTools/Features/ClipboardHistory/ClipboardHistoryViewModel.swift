import AppKit
import Foundation

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var query = "" {
        didSet {
            if query != oldValue { isSearchEditing = true }
            normalizeSelection()
        }
    }
    @Published private(set) var selectedID: UUID?
    @Published var isSearchEditing = false
    @Published private(set) var message: String?
    @Published private(set) var thumbnails: [UUID: Data] = [:]
    @Published private(set) var fileURLs: [UUID: [URL]] = [:]
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var showsNumberShortcuts = false

    private let store: ClipboardHistoryStore
    private let applicationAppearanceCache = ClipboardHistoryApplicationAppearanceCache()
    private var retention: ClipboardHistoryRetention

    init(store: ClipboardHistoryStore, retention: ClipboardHistoryRetention) {
        self.store = store
        self.retention = retention
    }

    var visibleItems: [ClipboardHistoryItem] {
        items.filter { Self.matches($0, query: query) }
    }

    var selectedItem: ClipboardHistoryItem? {
        visibleItems.first(where: { $0.id == selectedID })
    }

    func start() {
        Task {
            do {
                let loaded = try await store.loadItems(retention: retention)
                items = loaded
                normalizeSelection()
                await loadVisiblePreviews()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func updateRetention(_ value: ClipboardHistoryRetention) {
        retention = value
        start()
    }

    func accept(_ capture: ClipboardHistoryCapture) {
        Task {
            do {
                let duplicate = items.first(where: { $0.contentHash == capture.item.contentHash })
                let shouldSelectSavedItem = duplicate == nil || selectedID == duplicate?.id
                let saved = try await store.save(capture, replacing: duplicate)
                if let duplicate {
                    thumbnails[duplicate.id] = nil
                    fileURLs[duplicate.id] = nil
                }
                items = try await store.loadItems(retention: retention)
                if shouldSelectSavedItem { selectedID = saved.id }
                if let thumbnail = await store.thumbnailData(for: saved) {
                    thumbnails[saved.id] = thumbnail
                }
                if saved.kind == .files {
                    fileURLs[saved.id] = try await store.fileURLs(for: saved)
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func select(_ id: UUID) {
        selectedID = id
        isSearchEditing = false
    }

    func moveSelection(by offset: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else { selectedID = nil; return }
        guard let selectedID,
              let index = visible.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = visible[0].id
            return
        }
        self.selectedID = visible[min(max(index + offset, 0), visible.count - 1)].id
        isSearchEditing = false
    }

    func selectVisibleItem(number: Int) -> ClipboardHistoryItem? {
        guard visibleItems.indices.contains(number - 1) else { return nil }
        let item = visibleItems[number - 1]
        selectedID = item.id
        return item
    }

    func focusSearch() {
        isSearchEditing = true
        searchFocusRequestID += 1
    }

    func updateCommandKey(isPressed: Bool) {
        showsNumberShortcuts = isPressed
    }

    func applicationAppearance(
        for item: ClipboardHistoryItem
    ) -> ClipboardHistoryApplicationAppearance? {
        applicationAppearanceCache.appearance(for: item)
    }

    func focusResults() {
        isSearchEditing = false
        normalizeSelection()
    }

    func clearSearch() {
        query = ""
        isSearchEditing = false
        normalizeSelection()
    }

    func payloads(for item: ClipboardHistoryItem) async throws
        -> [ClipboardHistoryCapturedRepresentation] {
        try await store.payloads(for: item)
    }

    func promoteUsedItem(_ item: ClipboardHistoryItem) async {
        do {
            let promoted = try await store.promote(item)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = promoted
            }
            items.sort { $0.copiedAt > $1.copiedAt }
            selectedID = promoted.id
        } catch {
            message = "内容已处理，但未能置顶：\(error.localizedDescription)"
        }
    }

    func previewURL() async throws -> URL? {
        guard let selectedItem else { return nil }
        return try await store.previewURL(for: selectedItem)
    }

    func deleteSelection() {
        guard let item = selectedItem else { return }
        Task {
            do {
                try await store.delete(item)
                items.removeAll { $0.id == item.id }
                thumbnails[item.id] = nil
                fileURLs[item.id] = nil
                normalizeSelection()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func deleteAll() async throws {
        try await store.deleteAll()
        items = []
        thumbnails = [:]
        fileURLs = [:]
        selectedID = nil
    }

    func showMessage(_ value: String) {
        message = value
    }

    private func normalizeSelection() {
        let visible = visibleItems
        if let selectedID, visible.contains(where: { $0.id == selectedID }) { return }
        selectedID = visible.first?.id
    }

    private func loadVisiblePreviews() async {
        for item in items.prefix(40) {
            if item.thumbnailFileName != nil,
               let data = await store.thumbnailData(for: item) {
                thumbnails[item.id] = data
            }
            if item.kind == .files,
               let URLs = try? await store.fileURLs(for: item) {
                fileURLs[item.id] = URLs
            }
        }
    }

    nonisolated static func matches(_ item: ClipboardHistoryItem, query: String) -> Bool {
        let terms = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return true }
        let value = item.searchableText.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        return terms.allSatisfy(value.contains)
    }
}
