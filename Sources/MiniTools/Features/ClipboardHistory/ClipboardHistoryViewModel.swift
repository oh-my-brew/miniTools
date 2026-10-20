import AppKit
import Foundation

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = [] {
        didSet {
            // Membership/order changes invalidate reopening, not metadata or preview refreshes.
            if items.map(\.id) != oldValue.map(\.id) { browsing.didChangeStack() }
        }
    }
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            isSearchEditing = true
            selectedID = visibleItems.first?.id
            requestScroll(to: 0)
        }
    }
    @Published private(set) var selectedID: UUID?
    @Published var isSearchEditing = false
    @Published private(set) var message: String?
    @Published private(set) var thumbnails: [UUID: Data] = [:]
    @Published private(set) var fileURLs: [UUID: [URL]] = [:]
    @Published private(set) var searchFocusRequestID = 0
    @Published private(set) var showsNumberShortcuts = false

    @Published private(set) var scrollRequest = ClipboardHistoryScrollRequest(sequence: 0, offset: 0, animated: false)
    private var browsing = ClipboardHistoryBrowsingState()
    private var presentationGeneration = 0
    private var viewportOffset: CGFloat = 0
    private var viewportWidth: CGFloat = 0
    private var previewIsVisible = false
    private var cardStride: CGFloat { ClipboardHistoryPanelMetrics.cardWidth + ClipboardHistoryPanelMetrics.cardSpacing }

    func present() {
        guard !browsing.isPresented else { return }
        presentationGeneration += 1
        let resume = browsing.open()
        let ids = visibleItems.map(\.id)
        if resume && browsing.canRestoreContext(in: ids) {
            selectedID = browsing.restoredSelection(in: ids)
            requestScroll(to: browsing.anchor?.offset(in: ids, stride: cardStride) ?? 0)
        } else {
            query = ""
            isSearchEditing = false
            selectedID = items.first?.id
            requestScroll(to: 0)
        }
    }

    func dismiss() {
        guard browsing.isPresented else { return }
        presentationGeneration += 1
        browsing.close(ids: visibleItems.map(\.id), selectedID: selectedID,
                       offset: viewportOffset, stride: cardStride)
        previewIsVisible = false
    }

    func didUseItem() { browsing.didUseItem() }
    func setPreviewVisible(_ visible: Bool) { previewIsVisible = visible }

    func updateViewport(_ rect: CGRect) {
        guard browsing.isPresented else { return }
        viewportOffset = max(0, rect.minX)
        viewportWidth = rect.width
    }

    private func requestScroll(to offset: CGFloat, animated: Bool = false) {
        viewportOffset = max(0, offset)
        scrollRequest = .init(sequence: scrollRequest.sequence + 1, offset: viewportOffset, animated: animated)
    }

    private func revealSelection() {
        guard let id = selectedID, let index = visibleItems.firstIndex(where: { $0.id == id }) else { return }
        let offset = ClipboardHistoryBrowsingState.visibleOffset(
            index: index, current: viewportOffset, viewport: viewportWidth,
            cardWidth: ClipboardHistoryPanelMetrics.cardWidth, stride: cardStride, leadingInset: 2)
        if offset != viewportOffset { requestScroll(to: offset, animated: true) }
    }

    private func replaceItems(_ loaded: [ClipboardHistoryItem], followsNewest: Bool = false) {
        let ids = visibleItems.map(\.id)
        let anchor = ClipboardHistoryBrowsingState.Anchor(ids: ids, offset: viewportOffset, stride: cardStride)
        let previousSelection = selectedID
        items = loaded
        let newIDs = visibleItems.map(\.id)
        if followsNewest {
            selectedID = newIDs.first
            requestScroll(to: 0)
        } else {
            selectedID = ClipboardHistoryBrowsingState.Anchor.nearest(
                to: previousSelection, oldOrder: ids, surviving: newIDs)
            if browsing.isPresented { requestScroll(to: anchor?.offset(in: newIDs, stride: cardStride) ?? 0) }
        }
    }

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

    func start() { Task { await reload() } }

    func reload() async {
        do {
            let loaded = try await store.loadItems(retention: retention)
            replaceItems(loaded)
            await loadVisiblePreviews()
        } catch {
            message = error.localizedDescription
        }
    }

    func updateRetention(_ value: ClipboardHistoryRetention) {
        retention = value
        start()
    }

    func accept(_ capture: ClipboardHistoryCapture) { Task { await record(capture) } }

    func record(_ capture: ClipboardHistoryCapture) async {
        do {
            let duplicate = items.first(where: { $0.contentHash == capture.item.contentHash })
            let saved = try await store.save(capture, replacing: duplicate)
            browsing.didChangeStack()
            if let duplicate {
                thumbnails[duplicate.id] = nil
                fileURLs[duplicate.id] = nil
            }
            let loaded = try await store.loadItems(retention: retention)
            let followsNewest = browsing.isPresented && query.isEmpty && !isSearchEditing
                && !previewIsVisible && viewportOffset <= 2
            replaceItems(loaded, followsNewest: followsNewest)
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

    func enrichSearchableText(id: UUID, contentHash: String, text: String) async {
        guard items.contains(where: { $0.id == id && $0.contentHash == contentHash }) else { return }
        do {
            guard let updated = try await store.enrichSearchableText(id: id, contentHash: contentHash, text: text),
                  let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index] = updated // Metadata only: no reordering, recapture or resurrection.
        } catch {
            message = error.localizedDescription
        }
    }

    func select(_ id: UUID) {
        selectedID = id
        isSearchEditing = false
        revealSelection()
    }

    func moveSelection(by offset: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else { selectedID = nil; return }
        guard let selectedID,
              let index = visible.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = visible[0].id
            revealSelection()
            return
        }
        self.selectedID = visible[min(max(index + offset, 0), visible.count - 1)].id
        isSearchEditing = false
        revealSelection()
    }

    func visibleItem(number: Int) -> ClipboardHistoryItem? {
        guard visibleItems.indices.contains(number - 1) else { return nil }
        return visibleItems[number - 1]
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
        selectedID = items.first?.id
        requestScroll(to: 0)
    }

    func payloads(for item: ClipboardHistoryItem) async throws
        -> [ClipboardHistoryCapturedRepresentation] {
        try await store.payloads(for: item)
    }

    func promoteUsedItem(_ item: ClipboardHistoryItem) async {
        let generation = presentationGeneration
        do {
            let promoted = try await store.promote(item)
            browsing.didChangeStack()
            var updated = items
            if let index = updated.firstIndex(where: { $0.id == item.id }) {
                updated[index] = promoted
            }
            updated.sort { $0.copiedAt > $1.copiedAt }
            if generation == presentationGeneration {
                items = updated // The current operation closes the panel; do not scroll first.
            } else {
                replaceItems(updated) // A reopened panel retains its own browsing context.
            }
        } catch {
            message = "内容已处理，但未能置顶：\(error.localizedDescription)"
        }
    }

    func previewURL() async throws -> URL? {
        guard let selectedItem else { return nil }
        return try await store.previewURL(for: selectedItem)
    }

    func deleteSelection() { Task { await deleteSelectedItem() } }

    func deleteSelectedItem() async {
        guard let item = selectedItem else { return }
        do {
            try await store.delete(item)
            replaceItems(items.filter { $0.id != item.id })
            thumbnails[item.id] = nil
            fileURLs[item.id] = nil
            normalizeSelection()
        } catch {
            message = error.localizedDescription
        }
    }

    func deleteAll() async throws {
        try await store.deleteAll()
        items = []
        thumbnails = [:]
        fileURLs = [:]
        selectedID = nil
        requestScroll(to: 0)
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
