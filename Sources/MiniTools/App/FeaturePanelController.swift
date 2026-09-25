import AppKit
import SwiftUI

@MainActor
final class FeaturePanelController: NSObject, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?

    private let settings: AppSettings
    private let recentActionStore: RecentEncodingActionStore
    private let usageStatistics: UsageStatisticsStore
    private let englishInputSourceSession = EnglishInputSourceSession()

    private var activePanel: FeaturePanelKind?
    private var hasLoadedEncodingContent = false
    private var hasLoadedSafariWindows = false
    private var isPresentationPending = false
    private var previousApplication: NSRunningApplication?
    private var isClosing = false

    private lazy var selectionModel = FeaturePanelSelectionModel(
        selection: settings.lastFeaturePanel
    )

    private lazy var encodingViewModel: EncodingConversionPanelViewModel = {
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: settings.compressionQuality,
            recentActionStore: recentActionStore
        )
        viewModel.onActionCompleted = { [weak self] in
            self?.close(restoreFocus: true)
        }
        viewModel.onSuccessfulAction = { [weak self] id, title in
            self?.usageStatistics.record(
                id: id,
                title: title,
                category: .encodingConversion
            )
        }
        viewModel.onCancel = { [weak self] in
            self?.close(restoreFocus: true)
        }
        return viewModel
    }()

    private lazy var safariViewModel: SafariWindowPanelViewModel = {
        let viewModel = SafariWindowPanelViewModel()
        viewModel.onWindowCountChanged = { [weak self] count in
            self?.safariWindowCountDidChange(count)
        }
        viewModel.onWindowActivated = { [weak self] in
            self?.close(restoreFocus: false)
        }
        viewModel.onCancel = { [weak self] in
            self?.close(restoreFocus: true)
        }
        return viewModel
    }()

    private lazy var panel: FloatingPanel = makePanel()

    init(
        settings: AppSettings,
        usageStatistics: UsageStatisticsStore,
        recentActionStore: RecentEncodingActionStore = RecentEncodingActionStore(
            defaults: .standard
        )
    ) {
        self.settings = settings
        self.usageStatistics = usageStatistics
        self.recentActionStore = recentActionStore
        super.init()
    }

    var isPresented: Bool {
        panel.isVisible || isPresentationPending
    }

    func prepare() {
        _ = panel
    }

    func toggleLastUsedPanel() {
        if isPresented {
            close(restoreFocus: true)
            return
        }

        rememberFrontmostApplication()
        activate(settings.lastFeaturePanel, shouldPresent: true)
    }

    func show(_ kind: FeaturePanelKind) {
        if isPresented {
            activate(kind, shouldPresent: true)
            return
        }

        rememberFrontmostApplication()
        activate(kind, shouldPresent: true)
    }

    func close(restoreFocus: Bool) {
        guard !isClosing else { return }
        isClosing = true

        isPresentationPending = false
        panel.orderOut(nil)
        activePanel = nil
        hasLoadedEncodingContent = false
        hasLoadedSafariWindows = false
        encodingViewModel.endSession()
        safariViewModel.endSession()
        englishInputSourceSession.end()
        restorePreviousApplicationIfNeeded(restoreFocus)

        isClosing = false
    }

    func stop() {
        isPresentationPending = false
        encodingViewModel.endSession()
        safariViewModel.endSession()
        englishInputSourceSession.end()
    }

    private func activate(_ kind: FeaturePanelKind, shouldPresent: Bool) {
        activePanel = kind
        selectionModel.selection = kind
        settings.updateLastFeaturePanel(kind)

        switch kind {
        case .encodingConversion:
            englishInputSourceSession.begin()
            if !hasLoadedEncodingContent {
                hasLoadedEncodingContent = true
                encodingViewModel.beginSession(
                    compressionQuality: settings.compressionQuality
                )
            }
            setPanelSize(encodingPanelSize(), for: panel)
            if shouldPresent {
                showPanel()
            }

        case .safariWindows:
            englishInputSourceSession.end()
            if !hasLoadedSafariWindows {
                hasLoadedSafariWindows = true
                isPresentationPending = shouldPresent && !panel.isVisible
                safariViewModel.beginSession()
                return
            }

            updateSafariLayout(for: safariViewModel.windows.count)
            if shouldPresent {
                showPanel()
            }
        }
    }

    private func switchPanel() {
        guard panel.isVisible, let activePanel else { return }
        let destination: FeaturePanelKind = activePanel == .encodingConversion
            ? .safariWindows
            : .encodingConversion
        activate(destination, shouldPresent: false)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let command = FeaturePanelCommandRouter.command(for: event) else {
            return false
        }

        switch command {
        case .openSettings:
            onOpenSettings?()
            return true
        case .switchPanel:
            switchPanel()
            return true
        default:
            switch activePanel {
            case .encodingConversion:
                return encodingViewModel.handleCommand(command)
            case .safariWindows:
                return safariViewModel.handleCommand(command)
            case nil:
                return false
            }
        }
    }

    private func safariWindowCountDidChange(_ count: Int) {
        updateSafariLayout(for: count)
        guard isPresentationPending else { return }
        isPresentationPending = false
        showPanel()
    }

    private func updateSafariLayout(for count: Int) {
        let layout = FeaturePanelLayoutPolicy.safariLayout(
            windowCount: count,
            in: targetVisibleFrame()
        )
        safariViewModel.layout = layout

        guard activePanel == .safariWindows else { return }
        setPanelSize(layout.contentSize, for: panel)
    }

    private func encodingPanelSize() -> NSSize {
        FeaturePanelLayoutPolicy.encodingPanelSize(
            in: targetVisibleFrame()
        )
    }

    private func targetVisibleFrame() -> CGRect {
        targetScreen()?.visibleFrame ?? FeaturePanelLayoutPolicy.fallbackVisibleFrame
    }

    private func targetScreen() -> NSScreen? {
        if panel.isVisible, let screen = panel.screen {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
    }

    private func setPanelSize(_ contentSize: NSSize, for window: NSWindow) {
        let targetFrame = FeaturePanelLayoutPolicy.targetFrame(
            contentSize: contentSize,
            visibleFrame: targetVisibleFrame(),
            currentFrame: window.isVisible ? window.frame : nil
        )
        window.setFrame(
            targetFrame,
            display: true,
            animate: false
        )
    }

    private func showPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> FloatingPanel {
        let window = FloatingPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(
                    width: FeaturePanelMetrics.preferredWidth,
                    height: FeaturePanelMetrics.encodingPanelHeight
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isMovableByWindowBackground = true
        window.keyHandler = { [weak self] event in
            self?.handleKeyEvent(event) ?? false
        }
        window.contentView = TransparentHostingView(
            rootView: FeaturePanelView(
                selectionModel: selectionModel,
                encodingViewModel: encodingViewModel,
                safariViewModel: safariViewModel,
                onSelectPanel: { [weak self] kind in
                    self?.activate(kind, shouldPresent: false)
                }
            )
        )
        return window
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing,
              let window = notification.object as? NSWindow,
              window === panel else {
            return
        }
        close(restoreFocus: false)
    }

    private func rememberFrontmostApplication() {
        let current = NSWorkspace.shared.frontmostApplication
        if current?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = current
        }
    }

    private func restorePreviousApplicationIfNeeded(_ shouldRestore: Bool) {
        if shouldRestore {
            previousApplication?.activate(options: [])
        }
        previousApplication = nil
    }
}
