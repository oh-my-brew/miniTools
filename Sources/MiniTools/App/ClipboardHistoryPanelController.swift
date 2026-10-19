import AppKit
import Carbon
import QuartzCore
import SwiftUI

@MainActor
final class ClipboardHistoryPanelController: NSObject, NSWindowDelegate {
    var onOpenSettings: (() -> Void)?

    private let settings: AppSettings
    private let store: ClipboardHistoryStore
    private let monitor: ClipboardHistoryMonitor
    private let eventPoster: ClipboardHistoryEventPosting
    private var previousApplication: NSRunningApplication?
    private let previewPanelController = ClipboardHistoryPreviewPanelController()
    private var selectedCardFrame: CGRect?
    private var previewTask: Task<Void, Never>?
    private var previewedItemID: UUID?
    private var sessionGeneration = 0
    private var isClosing = false

    private lazy var viewModel = ClipboardHistoryViewModel(
        store: store,
        retention: settings.clipboardHistoryRetention
    )
    private lazy var panel = makePanel()

    init(
        settings: AppSettings,
        store: ClipboardHistoryStore = ClipboardHistoryStore(),
        monitor: ClipboardHistoryMonitor = ClipboardHistoryMonitor(),
        eventPoster: ClipboardHistoryEventPosting = SystemClipboardHistoryEventPoster()
    ) {
        self.settings = settings
        self.store = store
        self.monitor = monitor
        self.eventPoster = eventPoster
        super.init()
        monitor.onCapture = { [weak self] capture in self?.viewModel.accept(capture) }
        monitor.onError = { [weak self] message in self?.viewModel.showMessage(message) }
    }

    var isPresented: Bool { panel.isVisible }

    func start() {
        viewModel.start()
        monitor.start(enabled: settings.clipboardHistoryEnabled)
    }

    func stop() {
        monitor.stop()
        close(restoreFocus: false)
    }

    func setCaptureEnabled(_ enabled: Bool) {
        settings.updateClipboardHistoryEnabled(enabled)
        monitor.setEnabled(enabled)
    }

    func updateRetention(_ retention: ClipboardHistoryRetention) {
        settings.updateClipboardHistoryRetention(retention)
        viewModel.updateRetention(retention)
    }

    func deleteAll() async throws {
        try await viewModel.deleteAll()
    }

    func toggle() {
        if isPresented {
            close(restoreFocus: true)
        } else {
            show()
        }
    }

    func show() {
        sessionGeneration += 1
        viewModel.updateCommandKey(isPressed: false)
        rememberFrontmostApplication()
        positionPanel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0.78
        panel.makeKeyAndOrderFront(nil)
        guard !reduceMotion else { return }
        let originalFrame = panel.frame
        panel.setFrameOrigin(CGPoint(x: originalFrame.minX, y: originalFrame.minY - 4))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }
    }

    func close(restoreFocus: Bool) {
        guard !isClosing else { return }
        isClosing = true
        sessionGeneration += 1
        previewTask?.cancel()
        previewTask = nil
        closePreview()
        panel.orderOut(nil)
        if restoreFocus { previousApplication?.activate(options: []) }
        previousApplication = nil
        isClosing = false
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: 1000, height: ClipboardHistoryPanelMetrics.height)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.keyHandler = { [weak self] event in self?.handleKeyEvent(event) ?? false }
        panel.modifierHandler = { [weak self] modifiers in
            self?.viewModel.updateCommandKey(isPressed: modifiers.contains(.command))
        }
        panel.scrollHandler = { [weak self] event in self?.handleScrollEvent(event) ?? false }
        panel.contentView = TransparentHostingView(
            rootView: ClipboardHistoryPanelView(
                viewModel: viewModel,
                onPaste: { [weak self] item, plainTextOnly in
                    self?.perform(item: item, plainTextOnly: plainTextOnly, shouldPaste: true)
                },
                onOpenSettings: { [weak self] in self?.onOpenSettings?() },
                onSelectedCardFrameChange: { [weak self] frame in
                    self?.selectedCardFrameDidChange(frame)
                }
            )
        )
        return panel
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        guard let screenFrame = screen?.frame else { return }
        let inset = ClipboardHistoryPanelMetrics.screenInset
        panel.setFrame(
            NSRect(
                x: screenFrame.minX + inset,
                y: screenFrame.minY + ClipboardHistoryPanelMetrics.bottomInset,
                width: max(640, screenFrame.width - inset * 2),
                height: ClipboardHistoryPanelMetrics.height
            ),
            display: true
        )
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)

        if command, event.keyCode == UInt16(kVK_ANSI_Comma) {
            onOpenSettings?()
            return true
        }
        if command, event.keyCode == UInt16(kVK_ANSI_F) {
            viewModel.focusSearch()
            return true
        }
        if event.keyCode == UInt16(kVK_Tab) {
            viewModel.isSearchEditing ? viewModel.focusResults() : viewModel.focusSearch()
            return true
        }
        if event.keyCode == UInt16(kVK_Escape) {
            if previewPanelController.isVisible {
                closePreview()
                return true
            }
            if !viewModel.query.isEmpty || viewModel.isSearchEditing {
                viewModel.clearSearch()
            } else {
                close(restoreFocus: true)
            }
            return true
        }
        if command, event.keyCode == UInt16(kVK_ANSI_C) {
            guard let item = viewModel.selectedItem else { return true }
            perform(item: item, plainTextOnly: shift, shouldPaste: false)
            return true
        }
        if command, let number = number(for: event.keyCode) {
            guard let item = viewModel.selectVisibleItem(number: number) else { return true }
            perform(item: item, plainTextOnly: shift, shouldPaste: true)
            return true
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            if viewModel.isSearchEditing {
                viewModel.focusResults()
            } else if let item = viewModel.selectedItem {
                perform(item: item, plainTextOnly: shift, shouldPaste: true)
            }
            return true
        }
        if event.keyCode == UInt16(kVK_LeftArrow) {
            viewModel.moveSelection(by: -1)
            return true
        }
        if event.keyCode == UInt16(kVK_RightArrow) || event.keyCode == UInt16(kVK_DownArrow) {
            viewModel.moveSelection(by: 1)
            return true
        }
        if event.keyCode == UInt16(kVK_UpArrow) {
            viewModel.moveSelection(by: -1)
            return true
        }
        if event.keyCode == UInt16(kVK_Space), !viewModel.isSearchEditing {
            if previewPanelController.isVisible {
                closePreview()
            } else {
                showPreview()
            }
            return true
        }
        if (event.keyCode == UInt16(kVK_Delete)
            || event.keyCode == UInt16(kVK_ForwardDelete)), !viewModel.isSearchEditing {
            viewModel.deleteSelection()
            return true
        }
        if isTextInputEvent(event) {
            viewModel.focusSearch()
        }
        return false
    }

    private func isTextInputEvent(_ event: NSEvent) -> Bool {
        ClipboardHistoryInputBehavior.shouldExpandSearch(
            characters: event.characters,
            modifiers: event.modifierFlags
        )
    }

    private func handleScrollEvent(_ event: NSEvent) -> Bool {
        guard let scrollView = findHorizontalScrollView(in: panel.contentView),
              let documentView = scrollView.documentView else { return false }

        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        let rawDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        let delta = event.hasPreciseScrollingDeltas ? rawDelta : rawDelta * 12
        let clipView = scrollView.contentView
        let targetX = ClipboardHistoryHorizontalScrollBehavior.targetOffset(
            current: clipView.bounds.origin.x,
            delta: delta,
            contentWidth: documentView.bounds.width,
            viewportWidth: clipView.bounds.width
        )
        clipView.scroll(to: CGPoint(x: targetX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func findHorizontalScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView,
           let documentView = scrollView.documentView,
           documentView.bounds.width > scrollView.contentView.bounds.width {
            return scrollView
        }
        for subview in view.subviews {
            if let result = findHorizontalScrollView(in: subview) { return result }
        }
        return nil
    }

    private func number(for keyCode: UInt16) -> Int? {
        let mapping: [UInt16: Int] = [
            UInt16(kVK_ANSI_1): 1, UInt16(kVK_ANSI_2): 2, UInt16(kVK_ANSI_3): 3,
            UInt16(kVK_ANSI_4): 4, UInt16(kVK_ANSI_5): 5, UInt16(kVK_ANSI_6): 6,
            UInt16(kVK_ANSI_7): 7, UInt16(kVK_ANSI_8): 8, UInt16(kVK_ANSI_9): 9
        ]
        return mapping[keyCode]
    }

    private func perform(
        item: ClipboardHistoryItem,
        plainTextOnly: Bool,
        shouldPaste: Bool
    ) {
        Task {
            do {
                let payloads = try await viewModel.payloads(for: item)
                try ClipboardHistoryPasteService.write(
                    item: item,
                    payloads: payloads,
                    plainTextOnly: plainTextOnly
                )
                guard shouldPaste else {
                    close(restoreFocus: true)
                    return
                }
                let canPost = eventPoster.canPostEvents
                if !canPost { _ = eventPoster.requestAccess() }
                close(restoreFocus: true)
                guard canPost else { return }
                try? await Task.sleep(for: .milliseconds(80))
                eventPoster.postPasteShortcut()
            } catch {
                viewModel.showMessage(error.localizedDescription)
            }
        }
    }

    private func showPreview() {
        guard let requestedItemID = viewModel.selectedItem?.id else { return }
        previewTask?.cancel()
        let generation = sessionGeneration
        previewTask = Task {
            do {
                guard let requestedItem = viewModel.selectedItem else { return }
                let usesCustomPreview = requestedItem.kind == .text
                    || requestedItem.kind == .richText
                    || requestedItem.kind == .color
                let url: URL?
                if usesCustomPreview {
                    url = nil
                } else {
                    guard let previewURL = try await viewModel.previewURL() else {
                        viewModel.showMessage("此内容无法预览")
                        return
                    }
                    url = previewURL
                }
                guard !Task.isCancelled,
                      generation == sessionGeneration,
                      panel.isVisible,
                      viewModel.selectedItem?.id == requestedItemID else { return }
                guard let item = viewModel.selectedItem,
                      let screenFrame = panel.screen?.frame else { return }
                previewedItemID = item.id
                previewPanelController.show(
                    url: url,
                    item: item,
                    anchorX: selectedCardScreenMidX,
                    parentPanelTop: panel.frame.maxY,
                    screenFrame: screenFrame
                )
            } catch {
                guard !Task.isCancelled, generation == sessionGeneration else { return }
                viewModel.showMessage(error.localizedDescription)
            }
        }
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewedItemID = nil
        previewPanelController.close()
    }

    private var selectedCardScreenMidX: CGFloat {
        panel.frame.minX + (selectedCardFrame?.midX ?? panel.frame.width / 2)
    }

    private func selectedCardFrameDidChange(_ frame: CGRect?) {
        selectedCardFrame = frame
        if previewPanelController.isVisible,
           previewedItemID != viewModel.selectedItem?.id {
            closePreview()
            showPreview()
            return
        }
        guard let screenFrame = panel.screen?.frame else { return }
        previewPanelController.reposition(
            anchorX: selectedCardScreenMidX,
            parentPanelTop: panel.frame.maxY,
            screenFrame: screenFrame
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing,
              let window = notification.object as? NSWindow,
              window === panel else { return }
        close(restoreFocus: false)
    }

    private func rememberFrontmostApplication() {
        let current = NSWorkspace.shared.frontmostApplication
        if current?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = current
        }
    }
}
