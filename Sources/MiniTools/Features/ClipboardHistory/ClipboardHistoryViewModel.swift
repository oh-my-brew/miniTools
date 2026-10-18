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
    @Published private(set) var searchFocusRequestID = 0

    private let store: ClipboardHistoryStore
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
                await loadVisibleThumbnails()
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
                items = try await store.loadItems(retention: retention)
                if shouldSelectSavedItem { selectedID = saved.id }
                if let thumbnail = await store.thumbnailData(for: saved) {
                    thumbnails[saved.id] = thumbnail
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

    private func loadVisibleThumbnails() async {
        for item in items.prefix(40) where item.thumbnailFileName != nil {
            if let data = await store.thumbnailData(for: item) {
                thumbnails[item.id] = data
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
