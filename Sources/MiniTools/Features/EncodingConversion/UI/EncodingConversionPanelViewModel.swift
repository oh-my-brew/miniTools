import AppKit
import Foundation

@MainActor
final class EncodingConversionPanelViewModel: ObservableObject {
    @Published private var baseSections: [ToolActionSection] = []
    @Published private var recognizedSection: ToolActionSection?
    @Published private(set) var contentKind: ClipboardContentKind?
    @Published private(set) var contentSummary = "等待剪贴板内容"
    @Published private(set) var contentPreview = ""
    @Published private(set) var thumbnailImage: NSImage?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isExecuting = false
    @Published private(set) var errorMessage: String?
    @Published var selectedActionID: String?
    @Published private(set) var searchQuery = ""
    @Published private(set) var focusRequestID = 0

    var onActionCompleted: (() -> Void)?
    var onSuccessfulAction: ((String, String) -> Void)?
    var onCancel: (() -> Void)?

    private var compressionQuality: Double
    private let client: EncodingConversionClient
    private let recentActionStore: RecentEncodingActionStore
    private var analysisTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private var recentActionIDs: [String]
    private var selectionBeforeSearch: String?
    private var userHasNavigatedSelection = false

    init(
        compressionQuality: Double,
        client: EncodingConversionClient = .live,
        recentActionStore: RecentEncodingActionStore = RecentEncodingActionStore(),
        initialSections: [ToolActionSection] = [],
        initialSelectedActionID: String? = nil
    ) {
        self.compressionQuality = compressionQuality
        self.client = client
        self.recentActionStore = recentActionStore
        recentActionIDs = recentActionStore.actionIDs
        recognizedSection = initialSections.first(where: { $0.id == "recognized" })
        baseSections = initialSections.filter { $0.id != "recognized" }
        selectedActionID = initialSelectedActionID
    }

    var sections: [ToolActionSection] {
        let sourceSections = availableSections
        guard !sourceSections.contains(where: { section in
            section.actions.contains(where: \.isRecommended)
        }) else {
            return sourceSections
        }

        let availableActions = sourceSections.flatMap(\.actions)
        let actionsByID = Dictionary(uniqueKeysWithValues: availableActions.map { ($0.id, $0) })
        let recentActions = recentActionIDs.compactMap { actionsByID[$0] }.prefix(2)
        guard !recentActions.isEmpty else { return sourceSections }

        let recentIDs = Set(recentActions.map(\.id))
        let remainingSections = sourceSections.compactMap { section -> ToolActionSection? in
            let remaining = section.actions.filter { !recentIDs.contains($0.id) }
            guard !remaining.isEmpty else { return nil }
            return ToolActionSection(id: section.id, title: section.title, actions: remaining)
        }
        return [ToolActionSection(id: "recent", title: "最近使用", actions: Array(recentActions))]
            + remainingSections
    }

    var allActions: [ToolAction] {
        availableSections.flatMap(\.actions)
    }

    var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isSearching: Bool {
        !normalizedSearchQuery.isEmpty
    }

    var searchTokens: [String] {
        normalizedSearchQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var searchResults: [ToolAction] {
        guard isSearching else { return [] }
        return allActions.enumerated()
            .compactMap { index, action -> (action: ToolAction, score: Int, index: Int)? in
                guard let score = action.searchScore(for: normalizedSearchQuery) else { return nil }
                return (action, score, index)
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
            }
            .map(\.action)
    }

    var filteredSections: [ToolActionSection] {
        guard isSearching else { return sections }
        let results = searchResults
        guard !results.isEmpty else { return [] }
        return [ToolActionSection(id: "search", title: "搜索结果", actions: results)]
    }

    var visibleActions: [ToolAction] {
        filteredSections.flatMap(\.actions)
    }

    func directShortcutNumber(forActionID id: String) -> Int? {
        guard let index = visibleActions.prefix(9).firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return index + 1
    }

    func actionID(forDirectShortcutIndex index: Int) -> String? {
        guard visibleActions.indices.contains(index), index < 9 else { return nil }
        return visibleActions[index].id
    }

    private var availableSections: [ToolActionSection] {
        if let recognizedSection {
            return [recognizedSection] + baseSections
        }
        return baseSections
    }

    func beginSession(compressionQuality: Double) {
        sessionGeneration += 1
        focusRequestID += 1
        self.compressionQuality = compressionQuality
        loadClipboard()
    }

    func endSession() {
        sessionGeneration += 1
        analysisTask?.cancel()
        executionTask?.cancel()
        analysisTask = nil
        executionTask = nil
        isAnalyzing = false
        isExecuting = false
    }

    private func loadClipboard() {
        analysisTask?.cancel()
        errorMessage = nil
        isAnalyzing = false
        isExecuting = false
        searchQuery = ""
        selectionBeforeSearch = nil
        userHasNavigatedSelection = false
        recognizedSection = nil
        baseSections = []
        recentActionIDs = recentActionStore.actionIDs

        do {
            let content = try client.readClipboard()
            contentKind = content.kind
            contentSummary = content.summary
            contentPreview = content.preview
            thumbnailImage = content.thumbnailData.flatMap(NSImage.init(data:))

            switch content {
            case let .text(text):
                baseSections = TextActionCatalog.sections(for: text)
                selectedActionID = visibleActions.first?.id

            case let .image(value):
                baseSections = ImageActionCatalog.sections(
                    for: value,
                    compressionQuality: compressionQuality
                )
                selectedActionID = visibleActions.first?.id
                analyzeImage(value.data)
            }
        } catch {
            baseSections = []
            recognizedSection = nil
            selectedActionID = nil
            contentKind = nil
            contentSummary = "等待剪贴板内容"
            contentPreview = "先复制一段文本或一张图片，再重新唤起"
            thumbnailImage = nil
            errorMessage = error.localizedDescription
        }
    }

    func updateSearchQuery(_ rawValue: String) {
        let sanitized = Self.sanitizeSearchQuery(rawValue)
        guard sanitized != searchQuery else { return }

        let wasSearching = isSearching
        if !wasSearching, !sanitized.trimmingCharacters(in: .whitespaces).isEmpty {
            selectionBeforeSearch = selectedActionID
        }
        searchQuery = sanitized

        if isSearching {
            selectedActionID = searchResults.first?.id
        } else if wasSearching {
            if !userHasNavigatedSelection,
               let recommendation = sections.flatMap(\.actions).first(where: \.isRecommended) {
                selectedActionID = recommendation.id
            } else if visibleActions.contains(where: { $0.id == selectionBeforeSearch }) {
                selectedActionID = selectionBeforeSearch
            } else {
                selectedActionID = visibleActions.first?.id
            }
            selectionBeforeSearch = nil
        } else {
            synchronizeSelectionWithFilter()
        }
    }

    static func sanitizeSearchQuery(_ rawValue: String) -> String {
        var result = ""
        for scalar in rawValue.unicodeScalars {
            let isLetter = (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
            let isDigit = (48...57).contains(scalar.value)
            if isLetter || isDigit {
                result.unicodeScalars.append(scalar)
            } else if scalar.properties.isWhitespace, !result.isEmpty, result.last != " " {
                result.append(" ")
            }
        }
        return result
    }

    func select(_ id: String) {
        userHasNavigatedSelection = true
        selectedActionID = id
    }

    func performSelectedAction() {
        guard
            let selectedActionID,
            visibleActions.contains(where: { $0.id == selectedActionID })
        else { return }
        performAction(id: selectedActionID)
    }

    func performAction(id: String) {
        guard !isExecuting, let action = allActions.first(where: { $0.id == id }) else { return }
        selectedActionID = id
        isExecuting = true
        errorMessage = nil
        userHasNavigatedSelection = true
        let operation = action.execute
        let generation = sessionGeneration

        executionTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try operation() }
            }.value
            guard let self,
                  !Task.isCancelled,
                  sessionGeneration == generation else {
                return
            }
            executionTask = nil

            switch result {
            case let .success(output):
                do {
                    try client.writeClipboard(output)
                    recentActionStore.record(action.id)
                    recentActionIDs = recentActionStore.actionIDs
                    onSuccessfulAction?(action.id, action.title)
                    isExecuting = false
                    onActionCompleted?()
                } catch {
                    isExecuting = false
                    errorMessage = error.localizedDescription
                }
            case let .failure(error):
                isExecuting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleCommand(_ command: FeaturePanelCommand) -> Bool {
        switch command {
        case let .moveSelection(offset):
            moveSelection(by: offset)
            return true
        case .execute:
            performSelectedAction()
            return true
        case .cancel:
            if isSearching {
                updateSearchQuery("")
            } else {
                onCancel?()
            }
            return true
        case let .directAction(index):
            guard let actionID = actionID(forDirectShortcutIndex: index) else { return false }
            performAction(id: actionID)
            return true
        case .openSettings, .switchPanel, .character:
            return false
        }
    }

    private func moveSelection(by offset: Int) {
        let actions = visibleActions
        guard !actions.isEmpty else { return }
        let current = actions.firstIndex(where: { $0.id == selectedActionID }) ?? 0
        let next = min(max(current + offset, 0), actions.count - 1)
        userHasNavigatedSelection = true
        selectedActionID = actions[next].id
    }

    private func synchronizeSelectionWithFilter() {
        let actions = visibleActions
        guard !actions.isEmpty else {
            selectedActionID = nil
            return
        }
        if !actions.contains(where: { $0.id == selectedActionID }) {
            selectedActionID = actions.first?.id
        }
    }

    private func analyzeImage(_ imageData: Data) {
        isAnalyzing = true
        let recognizeImage = client.recognizeImage
        let generation = sessionGeneration
        analysisTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try recognizeImage(imageData) }
            }.value
            guard let self,
                  !Task.isCancelled,
                  sessionGeneration == generation else {
                return
            }
            analysisTask = nil
            isAnalyzing = false

            switch result {
            case let .success(analysis):
                applyRecognizedImageContents(analysis)
            case let .failure(error):
                errorMessage = "图片识别失败：\(error.localizedDescription)"
            }
        }
    }

    func applyRecognizedImageContents(_ contents: RecognizedImageContents) {
        guard let section = ImageActionCatalog.recognizedSection(from: contents) else { return }
        recognizedSection = section
        if !isSearching, !userHasNavigatedSelection {
            selectedActionID = section.actions.first?.id
        }
        synchronizeSelectionWithFilter()
    }
}
