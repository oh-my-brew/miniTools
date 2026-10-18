import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let shortcutCoordinator: GlobalShortcutCoordinator
    private let mouseBindingCoordinator: MouseBindingCoordinator
    private let closedLidRunningController: ClosedLidRunningController
    private let rustDeskXHeatProtectionController: RustDeskXHeatProtectionController
    private let dsStoreManagementController: DSStoreManagementController
    private let clipboardHistoryController: ClipboardHistoryPanelController
    private let usageStatistics: UsageStatisticsStore
    private lazy var window = makeWindow()

    init(
        settings: AppSettings,
        shortcutCoordinator: GlobalShortcutCoordinator,
        mouseBindingCoordinator: MouseBindingCoordinator,
        closedLidRunningController: ClosedLidRunningController,
        rustDeskXHeatProtectionController: RustDeskXHeatProtectionController,
        dsStoreManagementController: DSStoreManagementController,
        clipboardHistoryController: ClipboardHistoryPanelController,
        usageStatistics: UsageStatisticsStore
    ) {
        self.settings = settings
        self.shortcutCoordinator = shortcutCoordinator
        self.mouseBindingCoordinator = mouseBindingCoordinator
        self.closedLidRunningController = closedLidRunningController
        self.rustDeskXHeatProtectionController = rustDeskXHeatProtectionController
        self.dsStoreManagementController = dsStoreManagementController
        self.clipboardHistoryController = clipboardHistoryController
        self.usageStatistics = usageStatistics
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = SettingsView(
            settings: settings,
            shortcutCoordinator: shortcutCoordinator,
            mouseBindingCoordinator: mouseBindingCoordinator,
            closedLidRunningController: closedLidRunningController,
            rustDeskXHeatProtectionController: rustDeskXHeatProtectionController,
            dsStoreManagementController: dsStoreManagementController,
            clipboardHistoryController: clipboardHistoryController,
            usageStatistics: usageStatistics
        )
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "miniTools 设置"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "MiniTools.Settings")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 540)
        window.setContentSize(NSSize(width: 900, height: 650))
        window.center()
        return window
    }
}
