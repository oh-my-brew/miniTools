import Carbon
import Foundation

@MainActor
final class GlobalShortcutCoordinator: ObservableObject {
    @Published private(set) var panelError: String?
    @Published private(set) var clipboardHistoryError: String?
    @Published private(set) var windowControlErrors: [WindowControlID: String] = [:]

    var onStateChanged: (() -> Void)?

    private let settings: AppSettings
    private let panelHotKey: GlobalHotKey
    private let clipboardHistoryHotKey: GlobalHotKey
    private var windowControlHotKeys: [WindowControlID: GlobalHotKey] = [:]

    init(
        settings: AppSettings,
        showPanel: @escaping () -> Void,
        showClipboardHistory: @escaping () -> Void,
        performWindowControl: @escaping (WindowControlID) -> Void
    ) {
        self.settings = settings
        panelHotKey = GlobalHotKey(identifier: 1, onPressed: showPanel)
        clipboardHistoryHotKey = GlobalHotKey(identifier: 2, onPressed: showClipboardHistory)

        for (index, descriptor) in WindowControlCatalog.descriptors.enumerated() {
            let id = descriptor.id
            windowControlHotKeys[id] = GlobalHotKey(identifier: UInt32(100 + index)) {
                performWindowControl(id)
            }
        }
    }

    func start() {
        registerInitialPanelShortcut()
        registerInitialClipboardHistoryShortcut()
        registerCrossScreenShortcuts()
        registerLayoutShortcuts()
        onStateChanged?()
    }

    func stop() {
        panelHotKey.unregister()
        clipboardHistoryHotKey.unregister()
        for hotKey in windowControlHotKeys.values {
            hotKey.unregister()
        }
    }

    @discardableResult
    func updatePanelShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        guard panelHotKey.register(shortcut) == noErr else {
            panelError = conflictMessage(name: "面板唤起", shortcut: shortcut)
            onStateChanged?()
            return false
        }
        panelError = nil
        settings.updatePanelShortcut(shortcut)
        onStateChanged?()
        return true
    }

    @discardableResult
    func updateClipboardHistoryShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        guard clipboardHistoryHotKey.register(shortcut) == noErr else {
            clipboardHistoryError = conflictMessage(name: "剪贴板历史", shortcut: shortcut)
            onStateChanged?()
            return false
        }
        clipboardHistoryError = nil
        settings.updateClipboardHistoryShortcut(shortcut)
        onStateChanged?()
        return true
    }

    @discardableResult
    func updateWindowControlShortcut(
        _ shortcut: KeyboardShortcut,
        for id: WindowControlID
    ) -> Bool {
        guard let hotKey = windowControlHotKeys[id], hotKey.register(shortcut) == noErr else {
            windowControlErrors[id] = conflictMessage(name: "窗口控制", shortcut: shortcut)
            onStateChanged?()
            return false
        }
        windowControlErrors[id] = nil
        settings.updateWindowControlShortcut(shortcut, for: id)
        onStateChanged?()
        return true
    }

    func restoreDefaultWindowControlShortcuts() {
        for hotKey in windowControlHotKeys.values {
            hotKey.unregister()
        }
        for descriptor in WindowControlCatalog.descriptors {
            _ = updateWindowControlShortcut(descriptor.defaultShortcut, for: descriptor.id)
        }
    }

    private func registerInitialPanelShortcut() {
        let configured = settings.panelShortcut
        if panelHotKey.register(configured) == noErr {
            panelError = nil
            return
        }
        if configured != .panelDefault, panelHotKey.register(.panelDefault) == noErr {
            settings.updatePanelShortcut(.panelDefault)
            panelError = nil
            return
        }
        panelError = conflictMessage(name: "面板唤起", shortcut: configured)
    }

    private func registerInitialClipboardHistoryShortcut() {
        let configured = settings.clipboardHistoryShortcut
        guard clipboardHistoryHotKey.register(configured) == noErr else {
            clipboardHistoryError = conflictMessage(name: "剪贴板历史", shortcut: configured)
            return
        }
        clipboardHistoryError = nil
    }

    private func registerCrossScreenShortcuts() {
        for id in WindowControlCatalog.crossScreenIDs {
            registerInitialWindowControlShortcut(for: id)
        }
    }

    private func registerLayoutShortcuts() {
        for id in WindowControlCatalog.windowLayoutIDs {
            registerInitialWindowControlShortcut(for: id)
        }
    }

    private func registerInitialWindowControlShortcut(for id: WindowControlID) {
        guard let hotKey = windowControlHotKeys[id] else { return }
        let configured = settings.windowControlShortcut(for: id)
        guard hotKey.register(configured) == noErr else {
            windowControlErrors[id] = conflictMessage(name: "窗口控制", shortcut: configured)
            return
        }
        windowControlErrors[id] = nil
    }

    private func conflictMessage(name: String, shortcut: KeyboardShortcut) -> String {
        "\(name)快捷键 \(shortcut.displayName) 注册失败，可能已被其他功能或应用占用。"
    }
}
