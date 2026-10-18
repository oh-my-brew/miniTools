import AppKit
import Carbon
import QuartzCore
import QuickLookUI
import SwiftUI

@MainActor
final class ClipboardHistoryPanelController: NSObject, NSWindowDelegate,
    @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var onOpenSettings: (() -> Void)?

    private let settings: AppSettings
    private let store: ClipboardHistoryStore
    private let monitor: ClipboardHistoryMonitor
    private let eventPoster: ClipboardHistoryEventPosting
    private var previousApplication: NSRunningApplication?
    private var previewURL: URL?
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
        rememberFrontmostApplication()
        positionPanel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.makeKeyAndOrderFront(nil)
        guard !reduceMotion else { return }
        let originalFrame = panel.frame
        panel.setFrameOrigin(CGPoint(x: originalFrame.minX, y: originalFrame.minY - 10))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(originalFrame, display: true)
        }
    }

    func close(restoreFocus: Bool) {
        guard !isClosing else { return }
        isClosing = true
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared()?.orderOut(nil)
        }
        previewURL = nil
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
        panel.contentView = TransparentHostingView(
            rootView: ClipboardHistoryPanelView(
                viewModel: viewModel,
                onPaste: { [weak self] item, plainTextOnly in
                    self?.perform(item: item, plainTextOnly: plainTextOnly, shouldPaste: true)
                },
                onOpenSettings: { [weak self] in self?.onOpenSettings?() }
            )
        )
        return panel
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let inset = ClipboardHistoryPanelMetrics.screenInset
        panel.setFrame(
            NSRect(
                x: visibleFrame.minX + inset,
                y: visibleFrame.minY + ClipboardHistoryPanelMetrics.bottomInset,
                width: max(640, visibleFrame.width - inset * 2),
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
            showPreview()
            return true
        }
        if (event.keyCode == UInt16(kVK_Delete)
            || event.keyCode == UInt16(kVK_ForwardDelete)), !viewModel.isSearchEditing {
            viewModel.deleteSelection()
            return true
        }
        return false
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
        Task {
            do {
                guard let url = try await viewModel.previewURL() else {
                    viewModel.showMessage("此内容无法预览")
                    return
                }
                previewURL = url
                guard let quickLook = QLPreviewPanel.shared() else { return }
                quickLook.dataSource = self
                quickLook.delegate = self
                quickLook.reloadData()
                quickLook.makeKeyAndOrderFront(nil)
            } catch {
                viewModel.showMessage(error.localizedDescription)
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        previewURL = nil
        self.panel.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing,
              let window = notification.object as? NSWindow,
              window === panel,
              previewURL == nil else { return }
        close(restoreFocus: false)
    }

    private func rememberFrontmostApplication() {
        let current = NSWorkspace.shared.frontmostApplication
        if current?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = current
        }
    }
}
