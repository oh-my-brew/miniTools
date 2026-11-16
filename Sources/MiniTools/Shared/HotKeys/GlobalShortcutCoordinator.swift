import AppKit
import Carbon
import CoreGraphics
import Foundation

@MainActor
final class GlobalShortcutCoordinator: ObservableObject {
    @Published private(set) var panelError: String?
    @Published private(set) var clipboardHistoryError: String?
    @Published private(set) var windowControlErrors: [WindowControlID: String] = [:]
    @Published private(set) var composedWindowControlErrors: [ComposedWindowControlID: String] = [:]
    @Published private(set) var keyboardRemappingError: String?
    @Published private(set) var capsInputSourceStatus: String?

    var onStateChanged: (() -> Void)?

    private let settings: AppSettings
    private let panelHotKey: GlobalHotKey
    private let clipboardHistoryHotKey: GlobalHotKey
    private var windowControlHotKeys: [WindowControlID: GlobalHotKey] = [:]
    private var composedWindowControlHotKeys: [ComposedWindowControlID: GlobalHotKey] = [:]
    private var longPressRecognizers: [ComposedWindowControlID: HotKeyLongPressRecognizer] = [:]
    private var capsLongPressIDs: Set<ComposedWindowControlID> = []
    private var remappingActivationObserver: NSObjectProtocol?
    private let capsInputSourceSwitcher = CapsInputSourceSwitcher()
    private var capsInputSourceCheckGeneration = 0
    private lazy var remappingMonitor = KeyboardRemappingMonitor(
        availableCapsKeys: { [weak self] in self?.capsShortcutKeys ?? [] },
        perform: { [weak self] action in self?.handleRemappingAction(action) }
    )

    init(
        settings: AppSettings,
        showPanel: @escaping () -> Void,
        showClipboardHistory: @escaping () -> Void,
        performWindowControl: @escaping (WindowControlID) -> Void,
        performComposedWindowControl: @escaping (
            ComposedWindowControlID,
            WindowShortcutPress
        ) -> Void
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

        for (index, descriptor) in ComposedWindowControlCatalog.descriptors.enumerated() {
            let id = descriptor.id
            let identifier = UInt32(300 + index)
            if descriptor.supportsLongPress {
                let recognizer = HotKeyLongPressRecognizer(
                    threshold: .milliseconds(settings.windowLongPressThresholdMilliseconds),
                    onShortPress: {
                        performComposedWindowControl(id, .short)
                    },
                    onLongPress: {
                        performComposedWindowControl(id, .long)
                    }
                )
                longPressRecognizers[id] = recognizer
                composedWindowControlHotKeys[id] = GlobalHotKey(
                    identifier: identifier,
                    onPressed: {
                        recognizer.press()
                    },
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
        registerInitialClipboardHistoryShortcut()
        registerCrossScreenShortcuts()
        registerActiveLayoutShortcuts()
        remappingActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshKeyboardRemapping() }
        }
        refreshKeyboardRemapping()
        onStateChanged?()
    }

    func stop() {
        cancelCapsInputSourceRequest()
        remappingMonitor.stop()
        if let remappingActivationObserver {
            NotificationCenter.default.removeObserver(remappingActivationObserver)
            self.remappingActivationObserver = nil
        }
        cancelLongPresses()
        WindowLayoutService.cancelPendingAdjustments()
        panelHotKey.unregister()
        clipboardHistoryHotKey.unregister()
        for hotKey in windowControlHotKeys.values {
            hotKey.unregister()
        }
        for hotKey in composedWindowControlHotKeys.values {
            hotKey.unregister()
        }
    }

    func updateKeyboardRemappingRule(_ rule: KeyboardRemappingRule, enabled: Bool) {
        settings.updateKeyboardRemappingRule(rule, enabled: enabled)
        refreshKeyboardRemapping()
    }

    private func refreshKeyboardRemapping() {
        let rules = settings.keyboardRemappingRules
        if !rules.contains(.capsInputSourceSwitch) {
            cancelCapsInputSourceRequest()
            capsInputSourceStatus = nil
        }
        if rules.contains(.capsInputSourceSwitch) { capsInputSourceSwitcher.rememberCurrent() }
        guard !rules.isEmpty else {
            remappingMonitor.stop()
            keyboardRemappingError = nil
            return
        }
        guard AccessibilityAuthorization.isTrusted else {
            cancelCapsInputSourceRequest()
            remappingMonitor.stop()
            keyboardRemappingError = "需要在「通用」中授予辅助功能权限"
            return
        }
        guard CGPreflightListenEventAccess() else {
            cancelCapsInputSourceRequest()
            remappingMonitor.stop()
            keyboardRemappingError = "需要在「通用」中授予输入监控权限"
            return
        }
        if remappingMonitor.isRunning, remappingMonitor.enabled == rules,
           keyboardRemappingError == nil { return }
        cancelCapsInputSourceRequest()
        capsInputSourceStatus = nil
        remappingMonitor.stop()
        remappingMonitor.enabled = rules
        let running = remappingMonitor.start()
        if !rules.isDisjoint(with: [.capsShortcuts, .capsInputSourceSwitch]),
           !remappingMonitor.capsAvailable {
            keyboardRemappingError = "Caps Lock 物理按键监听不可用；其他已启用的映射仍可使用"
        } else {
            keyboardRemappingError = running ? nil : "键盘监听不可用，请检查系统授权"
        }
    }

    private func cancelCapsInputSourceRequest() {
        capsInputSourceCheckGeneration += 1
        capsInputSourceSwitcher.cancel()
    }

    private var capsShortcutKeys: Set<UInt16> {
        let hyper = KeyboardShortcut.panelDefault.carbonModifiers
        var codes: Set<UInt16> = []
        if settings.panelShortcut.carbonModifiers == hyper, panelError == nil {
            codes.insert(UInt16(settings.panelShortcut.keyCode))
        }
        for id in ComposedWindowControlCatalog.descriptors.map(\.id) {
            let shortcut = settings.composedWindowControlShortcut(for: id)
            if shortcut.carbonModifiers == hyper, composedWindowControlErrors[id] == nil {
                codes.insert(UInt16(shortcut.keyCode))
            }
        }
        for id in WindowControlCatalog.crossScreenIDs {
            let shortcut = settings.windowControlShortcut(for: id)
            if shortcut.carbonModifiers == hyper, windowControlErrors[id] == nil {
                codes.insert(UInt16(shortcut.keyCode))
            }
        }
        return codes
    }

    private func handleRemappingAction(_ action: KeyboardRemappingState.Action) {
        switch action {
        case let .sendGrave(modifiers):
            DispatchQueue.main.async {
                KeyboardRemappingMonitor.postGrave(modifiers)
            }
        case let .sendControlShortcut(code):
            DispatchQueue.main.async {
                KeyboardRemappingMonitor.postControlShortcut(code)
            }
        case let .sendMediaKey(key, isRepeat):
            let generation = remappingMonitor.generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.remappingMonitor.isRunning,
                      self.remappingMonitor.generation == generation,
                      self.settings.keyboardRemappingRules.contains(key.rule) else { return }
                KeyboardRemappingMonitor.postMediaKey(key, isRepeat: isRepeat)
            }
        case .hideSafari:
            DispatchQueue.main.async { [weak self] in
                guard let safari = NSWorkspace.shared.frontmostApplication,
                      safari.bundleIdentifier == "com.apple.Safari" else { return }
                if !safari.hide() {
                    self?.keyboardRemappingError = "Safari 未能隐藏"
                }
            }
        case .openCodex:
            DispatchQueue.main.async { [weak self] in
                guard let url = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.openai.codex"
                ) else {
                    self?.keyboardRemappingError = "未找到 Codex 应用"
                    return
                }
                NSWorkspace.shared.openApplication(
                    at: url, configuration: NSWorkspace.OpenConfiguration()
                ) { _, error in
                    guard let error else { return }
                    let message = "Codex 打开失败：\(error.localizedDescription)"
                    Task { @MainActor [weak self] in
                        self?.keyboardRemappingError = message
                    }
                }
            }
        case .capsPressObserved:
            cancelCapsInputSourceRequest()
            let generation = capsInputSourceCheckGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.capsInputSourceCheckGeneration == generation,
                      self.settings.keyboardRemappingRules.contains(.capsInputSourceSwitch)
                else { return }
                self.capsInputSourceStatus = "检测到 Caps Lock 按下，等待松开"
            }
        case .switchInputSource:
            cancelCapsInputSourceRequest()
            let generation = capsInputSourceCheckGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.capsInputSourceCheckGeneration == generation,
                      self.remappingMonitor.isRunning,
                      self.settings.keyboardRemappingRules.contains(.capsInputSourceSwitch) else {
                    return
                }
                let result = self.capsInputSourceSwitcher.toggle()
                guard self.capsInputSourceCheckGeneration == generation,
                      self.remappingMonitor.isRunning,
                      self.settings.keyboardRemappingRules.contains(.capsInputSourceSwitch) else {
                    return
                }
                let request: CapsInputSourceSwitcher.Request
                switch result {
                case let .failure(failure):
                    self.keyboardRemappingError = failure.message
                    self.capsInputSourceStatus = "已识别单按；切换请求失败"
                    return
                case let .success(value):
                    self.keyboardRemappingError = nil
                    request = value
                }
                self.capsInputSourceStatus = request.pendingStatus
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.capsInputSourceCheckGeneration == generation,
                          self.remappingMonitor.isRunning,
                          self.settings.keyboardRemappingRules.contains(.capsInputSourceSwitch) else {
                        return
                    }
                    self.capsInputSourceStatus = request.confirmationStatus(
                        observed: self.capsInputSourceSwitcher.currentIdentifier()
                    )
                }
            }
        case let .capsTapBlocked(reason):
            cancelCapsInputSourceRequest()
            let generation = capsInputSourceCheckGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.capsInputSourceCheckGeneration == generation,
                      self.settings.keyboardRemappingRules.contains(.capsInputSourceSwitch)
                else { return }
                switch reason {
                case .heldModifier:
                    self.capsInputSourceStatus = "未识别为单按：按下 Caps Lock 时检测到其他修饰键"
                case .otherKey:
                    self.capsInputSourceStatus = "未识别为单按：按住 Caps Lock 时检测到其他按键"
                case let .modifierChanged(code):
                    self.capsInputSourceStatus =
                        "未识别为单按：按住 Caps Lock 时检测到修饰键变化（键码 \(code)）"
                case .latchNotRestored:
                    self.capsInputSourceStatus = "已识别单按，但无法确认 Caps Lock 状态已恢复；未切换输入法"
                }
            }
        case let .shortcutDown(code):
            routeCapsShortcut(code, pressed: true)
        case let .shortcutUp(code):
            routeCapsShortcut(code, pressed: false)
        case .cancelInputSourceSwitch:
            cancelCapsInputSourceRequest()
        case .cancelShortcuts:
            for id in capsLongPressIDs { longPressRecognizers[id]?.cancel() }
            capsLongPressIDs.removeAll()
        }
    }

    private func routeCapsShortcut(_ code: UInt16, pressed: Bool) {
        let hyper = KeyboardShortcut.panelDefault.carbonModifiers
        func matches(_ shortcut: KeyboardShortcut) -> Bool {
            shortcut.carbonModifiers == hyper && shortcut.keyCode == UInt32(code)
        }
        if matches(settings.panelShortcut), panelError == nil {
            if pressed { panelHotKey.onPressed() }
            return
        }
        for descriptor in ComposedWindowControlCatalog.descriptors {
            if matches(settings.composedWindowControlShortcut(for: descriptor.id)),
               composedWindowControlErrors[descriptor.id] == nil,
               let key = composedWindowControlHotKeys[descriptor.id] {
                if descriptor.supportsLongPress {
                    if pressed {
                        capsLongPressIDs.insert(descriptor.id)
                    } else {
                        capsLongPressIDs.remove(descriptor.id)
                    }
                }
                if pressed { key.onPressed() } else { key.onReleased?() }
                return
            }
        }
        for id in WindowControlCatalog.crossScreenIDs {
            if matches(settings.windowControlShortcut(for: id)),
               windowControlErrors[id] == nil,
               let key = windowControlHotKeys[id] {
                if pressed { key.onPressed() }
                return
            }
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

    func updateWindowLongPressThresholdMilliseconds(_ milliseconds: Int) {
        settings.updateWindowLongPressThresholdMilliseconds(milliseconds)
        let threshold: Duration = .milliseconds(settings.windowLongPressThresholdMilliseconds)
        for recognizer in longPressRecognizers.values {
            recognizer.updateThreshold(threshold)
        }
        onStateChanged?()
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

    @discardableResult
    func updateComposedWindowControlShortcut(
        _ shortcut: KeyboardShortcut,
        for id: ComposedWindowControlID
    ) -> Bool {
        longPressRecognizers[id]?.cancel()
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
        composedWindowControlErrors[id] = nil
        settings.updateComposedWindowControlShortcut(shortcut, for: id)
        onStateChanged?()
        return true
    }

    func restoreDefaultWindowControlShortcuts() {
        for id in WindowControlCatalog.crossScreenIDs {
            windowControlHotKeys[id]?.unregister()
        }

        cancelLongPresses()
        for hotKey in composedWindowControlHotKeys.values {
            hotKey.unregister()
        }
        for descriptor in ComposedWindowControlCatalog.descriptors {
            _ = updateComposedWindowControlShortcut(descriptor.defaultShortcut, for: descriptor.id)
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

    private func registerActiveLayoutShortcuts() {
        for descriptor in ComposedWindowControlCatalog.descriptors {
            registerInitialComposedWindowControlShortcut(for: descriptor.id)
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
