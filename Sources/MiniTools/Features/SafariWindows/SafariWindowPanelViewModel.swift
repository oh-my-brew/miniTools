import Foundation

@MainActor
final class SafariWindowPanelViewModel: ObservableObject {
    static let selectionKeys = Array("asdfqwerzxcvtgbyhuiopl").map(String.init)

    @Published private(set) var windows: [SafariWindowItem] = []
    @Published var selectedWindowID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isActivating = false
    @Published private(set) var errorMessage: String?
    @Published var layout: SafariPanelLayout = .empty

    var onWindowCountChanged: ((Int) -> Void)?
    var onWindowActivated: (() -> Void)?
    var onCancel: (() -> Void)?

    private var loadingTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private let scanWorker = SafariWindowScanWorker()
    private var cachedProcessIdentity: String?
    private var pendingWindows: [SafariWindowItem]?
    private var hasInteracted = false
    private let client: SafariWindowClient

    init(
        initialWindows: [SafariWindowItem] = [],
        client: SafariWindowClient = .live
    ) {
        windows = initialWindows
        selectedWindowID = initialWindows.first(where: \.wasActiveWindow)?.id ?? initialWindows.first?.id
        self.client = client
    }

    func beginSession() {
        sessionGeneration += 1
        hasInteracted = false
        let process = client.processIdentity()
        if process != cachedProcessIdentity {
            windows = []
            selectedWindowID = nil
            pendingWindows = nil
        } else if let pendingWindows {
            apply(pendingWindows)
            self.pendingWindows = nil
        }
        cachedProcessIdentity = process
        load()
    }

    func endSession() {
        sessionGeneration += 1
        loadingTask?.cancel()
        activationTask?.cancel()
        loadingTask = nil
        activationTask = nil
        isLoading = false
        isActivating = false
    }

    private func load() {
        loadingTask?.cancel()
        isLoading = true
        isActivating = false
        errorMessage = nil
        let fetchWindows = client.fetchWindows
        let generation = sessionGeneration
        let process = cachedProcessIdentity
        let worker = scanWorker

        loadingTask = Task { [weak self] in
            let result: Result<[SafariWindowItem], Error>
            do {
                result = .success(try await worker.fetch(fetchWindows))
            } catch {
                result = .failure(error)
            }
            guard let self,
                  !Task.isCancelled,
                  sessionGeneration == generation else {
                return
            }

            loadingTask = nil
            isLoading = false
            guard client.processIdentity() == process else {
                windows = []
                selectedWindowID = nil
                pendingWindows = nil
                errorMessage = "Safari 已退出或重启，请重新打开窗口列表"
                onWindowCountChanged?(0)
                return
            }
            switch result {
            case let .success(items):
                if hasInteracted {
                    // Freeze both row order and letter mapping during keyboard interaction.
                    pendingWindows = items
                } else {
                    apply(items)
                }
            case let .failure(error):
                if error is CancellationError { return }
                // Keep a valid process-scoped snapshot available when refresh is slow.
                errorMessage = error.localizedDescription
                onWindowCountChanged?(windows.count)
            }
        }
    }

    private func apply(_ items: [SafariWindowItem]) {
        if windows != items { windows = items }
        selectedWindowID = items.first(where: \.wasActiveWindow)?.id ?? items.first?.id
        errorMessage = items.isEmpty ? "Safari 未运行或当前没有浏览器窗口" : nil
        onWindowCountChanged?(items.count)
    }

    func activateSelectedWindow() {
        guard !isActivating, let selectedWindowID, validateWindowProcess() else { return }
        let activateWindow = client.activateWindow
        performActivation {
            try activateWindow(selectedWindowID)
        }
    }

    func activateAllUngroupedWindows() {
        guard !isActivating, validateWindowProcess() else { return }
        let windowIDs = windows.filter { !$0.hasTabGroup }.map(\.id)
        guard !windowIDs.isEmpty else {
            errorMessage = "当前没有不属于标签页组的 Safari 窗口"
            return
        }

        let activateWindows = client.activateWindows
        performActivation {
            try activateWindows(windowIDs)
        }
    }

    private func validateWindowProcess() -> Bool {
        guard client.processIdentity() == cachedProcessIdentity else {
            windows = []
            pendingWindows = nil
            selectedWindowID = nil
            errorMessage = "Safari 已退出或重启，请重新打开窗口列表"
            onWindowCountChanged?(0)
            return false
        }
        return true
    }

    func createWindow() {
        let createWindow = client.createWindow
        performActivation {
            try createWindow()
        }
    }

    private func performActivation(
        _ operation: @escaping @Sendable () throws -> Void
    ) {
        guard !isActivating else { return }
        hasInteracted = true
        isActivating = true
        errorMessage = nil
        let generation = sessionGeneration
        activationTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try operation() }
            }.value
            guard let self,
                  !Task.isCancelled,
                  sessionGeneration == generation else {
                return
            }
            activationTask = nil
            isActivating = false
            switch result {
            case .success:
                onWindowActivated?()
            case let .failure(error):
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
            activateSelectedWindow()
            return true
        case .cancel:
            onCancel?()
            return true
        case let .character(key):
            return handleSelectionKey(key)
        case .openSettings, .switchPanel, .directAction:
            return false
        }
    }

    func handleSelectionKey(_ key: String) -> Bool {
        if key == "n" {
            createWindow()
            return true
        }
        if key == "m" {
            activateAllUngroupedWindows()
            return true
        }
        if key == "j" {
            moveSelection(by: 1)
            return true
        }
        if key == "k" {
            moveSelection(by: -1)
            return true
        }
        if let index = Self.selectionKeys.firstIndex(of: key), windows.indices.contains(index) {
            hasInteracted = true
            selectedWindowID = windows[index].id
            activateSelectedWindow()
            return true
        }
        return false
    }

    func shortcut(at index: Int) -> String? {
        Self.selectionKeys.indices.contains(index) ? Self.selectionKeys[index] : nil
    }

    private func moveSelection(by offset: Int) {
        guard !windows.isEmpty else { return }
        hasInteracted = true
        errorMessage = nil
        let current = windows.firstIndex(where: { $0.id == selectedWindowID }) ?? 0
        let next = min(max(current + offset, 0), windows.count - 1)
        selectedWindowID = windows[next].id
    }
}
