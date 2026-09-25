import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    var onOpenPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleClosedLidRunning: (() -> Void)?
    var onMenuWillOpen: (() -> Void)?

    static let toolPanelTitle = "工具面板"
    static let closedLidRunningTitle = "合盖运行"

    private var statusItem: NSStatusItem?
    private var panelItem: NSMenuItem?
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

    @objc private func openSettings() {
        onOpenSettings?()
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
