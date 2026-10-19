import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    var onOpenPanel: (() -> Void)?
    var onOpenClipboardHistory: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onCheckForBetaUpdates: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleClosedLidRunning: (() -> Void)?
    var onMenuWillOpen: (() -> Void)?

    static let toolPanelTitle = "工具面板"
    static let clipboardHistoryTitle = "剪贴板历史"
    static let closedLidRunningTitle = "合盖运行"
    static let checkForUpdatesTitle = "检查更新…"
    static let checkForBetaUpdatesTitle = "检查 Beta 更新…"

    private var statusItem: NSStatusItem?
    private var panelItem: NSMenuItem?
    private var clipboardHistoryItem: NSMenuItem?
    private var closedLidRunningItem: NSMenuItem?

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusBarIcon()

        let menu = NSMenu()
        menu.delegate = self

        let panelItem = NSMenuItem(
            title: Self.toolPanelTitle,
            action: #selector(openPanel),
            keyEquivalent: ""
        )
        panelItem.target = self
        panelItem.image = AppArtwork.hammerIcon(size: NSSize(width: 15, height: 15))
        menu.addItem(panelItem)
        self.panelItem = panelItem

        let clipboardHistoryItem = NSMenuItem(
            title: Self.clipboardHistoryTitle,
            action: #selector(openClipboardHistory),
            keyEquivalent: ""
        )
        clipboardHistoryItem.target = self
        clipboardHistoryItem.image = menuIcon(systemName: "clipboard")
        menu.addItem(clipboardHistoryItem)
        self.clipboardHistoryItem = clipboardHistoryItem

        let closedLidRunningItem = NSMenuItem(
            title: Self.closedLidRunningTitle,
            action: #selector(toggleClosedLidRunning),
            keyEquivalent: ""
        )
        closedLidRunningItem.target = self
        closedLidRunningItem.image = menuIcon(systemName: "laptopcomputer")
        menu.addItem(closedLidRunningItem)
        self.closedLidRunningItem = closedLidRunningItem

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: Self.checkForUpdatesTitle,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        checkForUpdatesItem.image = menuIcon(systemName: "arrow.triangle.2.circlepath")
        menu.addItem(checkForUpdatesItem)

        let checkForBetaUpdatesItem = NSMenuItem(
            title: Self.checkForBetaUpdatesTitle,
            action: #selector(checkForBetaUpdates),
            keyEquivalent: ""
        )
        checkForBetaUpdatesItem.target = self
        checkForBetaUpdatesItem.image = menuIcon(systemName: "flask")
        menu.addItem(checkForBetaUpdatesItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = menuIcon(systemName: "gearshape")
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "退出 miniTools",
            action: #selector(terminate),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = menuIcon(systemName: "power")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    func update(
        settings: AppSettings,
        shortcutCoordinator: GlobalShortcutCoordinator,
        closedLidRunningController: ClosedLidRunningController
    ) {
        panelItem?.title = shortcutCoordinator.panelError == nil
            ? "\(Self.toolPanelTitle)（\(settings.panelShortcut.displayName)）"
            : "\(Self.toolPanelTitle)：快捷键冲突"
        clipboardHistoryItem?.title = shortcutCoordinator.clipboardHistoryError == nil
            ? "\(Self.clipboardHistoryTitle)（\(settings.clipboardHistoryShortcut.displayName)）"
            : "\(Self.clipboardHistoryTitle)：快捷键冲突"

        let isBusy = closedLidRunningController.isBusy
        let isEnabled = closedLidRunningController.isFeatureEnabled
        let actualSleepDisabled = closedLidRunningController.actualSleepDisabled
        let tooltip = closedLidRunningController.lastError
            ?? "SleepDisabled 实际值：\(closedLidRunningController.actualStateTitle)"
        closedLidRunningItem?.title = Self.closedLidRunningTitle
        closedLidRunningItem?.state = if isBusy {
            .mixed
        } else if isEnabled {
            .on
        } else {
            .off
        }
        closedLidRunningItem?.isEnabled = !isBusy
        closedLidRunningItem?.toolTip = tooltip

        statusItem?.button?.image = statusBarIcon(
            isClosedLidRunning: actualSleepDisabled == true
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    @objc private func openPanel() {
        onOpenPanel?()
    }

    @objc private func openClipboardHistory() {
        onOpenClipboardHistory?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func checkForBetaUpdates() {
        onCheckForBetaUpdates?()
    }

    @objc private func toggleClosedLidRunning() {
        onToggleClosedLidRunning?()
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }

    private func menuIcon(systemName: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 15, height: 15)
        return image
    }

    private func statusBarIcon(isClosedLidRunning: Bool = false) -> NSImage? {
        let image = AppArtwork.hammerStatusIcon(isActive: isClosedLidRunning)
        image?.accessibilityDescription = "miniTools"
        return image
    }
}
