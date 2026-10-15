import Carbon
import Foundation

@MainActor
final class GlobalShortcutCoordinator: ObservableObject {
    @Published private(set) var panelError: String?
    @Published private(set) var windowControlErrors: [WindowControlID: String] = [:]
    @Published private(set) var composedWindowControlErrors: [ComposedWindowControlID: String] = [:]

    var onStateChanged: (() -> Void)?

    private let settings: AppSettings
    private let panelHotKey: GlobalHotKey
    private var windowControlHotKeys: [WindowControlID: GlobalHotKey] = [:]
    private var composedWindowControlHotKeys: [ComposedWindowControlID: GlobalHotKey] = [:]
    private var longPressRecognizers: [ComposedWindowControlID: HotKeyLongPressRecognizer] = [:]

    init(
        settings: AppSettings,
        showPanel: @escaping () -> Void,
        performWindowControl: @escaping (WindowControlID) -> Void,
        performComposedWindowControl: @escaping (
            ComposedWindowControlID,
            WindowShortcutPress
        ) -> Void
    ) {
        self.settings = settings
        panelHotKey = GlobalHotKey(identifier: 1, onPressed: showPanel)

        for (index, descriptor) in WindowControlCatalog.descriptors.enumerated() {
            let id = descriptor.id
            windowControlHotKeys[id] = GlobalHotKey(identifier: UInt32(100 + index)) {
                performWindowControl(id)
            }
        }

        for (index, descriptor) in ComposedWindowControlCatalog.descriptors.enumerated() {
            let id = descriptor.id
            let identifier = UInt32(300 + index)
            if descriptor.supportsLongPress {
                let recognizer = HotKeyLongPressRecognizer(
                    onShortPress: { performComposedWindowControl(id, .short) },
                    onLongPress: { performComposedWindowControl(id, .long) }
                )
                longPressRecognizers[id] = recognizer
                composedWindowControlHotKeys[id] = GlobalHotKey(
                    identifier: identifier,
                    onPressed: recognizer.press,
                    onReleased: recognizer.release
                )
            } else {
                composedWindowControlHotKeys[id] = GlobalHotKey(identifier: identifier) {
                    performComposedWindowControl(id, .short)
                }
            }
        }
    }

    func start() {
        registerInitialPanelShortcut()
        registerCrossScreenShortcuts()
        registerActiveLayoutShortcuts()
        onStateChanged?()
    }

    func stop() {
        cancelLongPresses()
        panelHotKey.unregister()
        for hotKey in windowControlHotKeys.values {
            hotKey.unregister()
        }
        for hotKey in composedWindowControlHotKeys.values {
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

    func updateWindowManagementMode(_ mode: WindowManagementMode) {
        guard mode != settings.windowManagementMode else { return }
        deactivateLayoutShortcuts()
        settings.updateWindowManagementMode(mode)
        registerActiveLayoutShortcuts()
        onStateChanged?()
    }

    @discardableResult
    func updateWindowControlShortcut(
        _ shortcut: KeyboardShortcut,
        for id: WindowControlID
    ) -> Bool {
        let isActive = WindowControlCatalog.crossScreenIDs.contains(id)
            || settings.windowManagementMode == .classic
        if isActive {
            guard let hotKey = windowControlHotKeys[id], hotKey.register(shortcut) == noErr else {
                windowControlErrors[id] = conflictMessage(name: "窗口控制", shortcut: shortcut)
                onStateChanged?()
                return false
            }
        }
        windowControlErrors[id] = nil
        settings.updateWindowControlShortcut(shortcut, for: id)
        onStateChanged?()
        return true
    }

    @discardableResult
    func updateComposedWindowControlShortcut(
        _ shortcut: KeyboardShortcut,
        for id: ComposedWindowControlID
    ) -> Bool {
        longPressRecognizers[id]?.cancel()
        if settings.windowManagementMode == .sizeAndPosition {
            guard
                let hotKey = composedWindowControlHotKeys[id],
                hotKey.register(shortcut) == noErr
            else {
                composedWindowControlErrors[id] = conflictMessage(
                    name: "窗口控制",
                    shortcut: shortcut
                )
                onStateChanged?()
                return false
            }
        }
        composedWindowControlErrors[id] = nil
        settings.updateComposedWindowControlShortcut(shortcut, for: id)
        onStateChanged?()
        return true
    }

    func restoreDefaultWindowControlShortcuts() {
        for id in WindowControlCatalog.crossScreenIDs {
            windowControlHotKeys[id]?.unregister()
        }

        switch settings.windowManagementMode {
        case .classic:
            for id in WindowControlCatalog.windowLayoutIDs {
                windowControlHotKeys[id]?.unregister()
            }
            for id in WindowControlCatalog.windowLayoutIDs {
                guard let shortcut = WindowControlCatalog.defaultShortcuts[id] else { continue }
                _ = updateWindowControlShortcut(shortcut, for: id)
            }
        case .sizeAndPosition:
            cancelLongPresses()
            for hotKey in composedWindowControlHotKeys.values {
                hotKey.unregister()
            }
            for descriptor in ComposedWindowControlCatalog.descriptors {
                _ = updateComposedWindowControlShortcut(
                    descriptor.defaultShortcut,
                    for: descriptor.id
                )
            }
        }

        for id in WindowControlCatalog.crossScreenIDs {
            guard let shortcut = WindowControlCatalog.defaultShortcuts[id] else { continue }
            _ = updateWindowControlShortcut(shortcut, for: id)
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

    private func registerCrossScreenShortcuts() {
        for id in WindowControlCatalog.crossScreenIDs {
            registerInitialWindowControlShortcut(for: id)
        }
    }

    private func registerActiveLayoutShortcuts() {
        switch settings.windowManagementMode {
        case .classic:
            for id in WindowControlCatalog.windowLayoutIDs {
                registerInitialWindowControlShortcut(for: id)
            }
        case .sizeAndPosition:
            for descriptor in ComposedWindowControlCatalog.descriptors {
                registerInitialComposedWindowControlShortcut(for: descriptor.id)
            }
        }
    }

    private func deactivateLayoutShortcuts() {
        cancelLongPresses()
        for id in WindowControlCatalog.windowLayoutIDs {
            windowControlHotKeys[id]?.unregister()
        }
        for hotKey in composedWindowControlHotKeys.values {
            hotKey.unregister()
        }
        windowControlErrors = windowControlErrors.filter {
            WindowControlCatalog.crossScreenIDs.contains($0.key)
        }
        composedWindowControlErrors.removeAll()
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

    private func registerInitialComposedWindowControlShortcut(
        for id: ComposedWindowControlID
    ) {
        guard let hotKey = composedWindowControlHotKeys[id] else { return }
        let configured = settings.composedWindowControlShortcut(for: id)
        guard hotKey.register(configured) == noErr else {
            composedWindowControlErrors[id] = conflictMessage(
                name: "窗口控制",
                shortcut: configured
            )
            return
        }
        composedWindowControlErrors[id] = nil
    }

    private func cancelLongPresses() {
        for recognizer in longPressRecognizers.values {
            recognizer.cancel()
        }
    }

    private func conflictMessage(name: String, shortcut: KeyboardShortcut) -> String {
        "\(name)快捷键 \(shortcut.displayName) 注册失败，可能已被其他功能或应用占用。"
    }
}
