import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let panelShortcut = "panelShortcut"
        static let lastFeaturePanel = "lastFeaturePanel"
        static let windowControlShortcuts = "windowControlShortcuts"
        static let compressionQuality = "compressionQuality"
        static let cursorHighlightStyles = "cursorHighlightStyles"
        static let mouseBindings = "mouseBindings"
        static let mouseDragThresholdRatio = "mouseDragThresholdRatio"
        static let closedLidRunningEnabled = "closedLidRunningEnabled"
        static let dsStoreManagementEnabled = "dsStoreManagementEnabled"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let legacyMouseDragThreshold = "mouseDragThreshold"
        static let restoredHikariCursorStyle = "restoredHikariCursorStyleV1"

        static let previousEncodingConversionShortcut = "encodingConversionShortcut"
        static let previousSafariWindowShortcut = "safariWindowShortcut"
        static let legacyEncodingConversionShortcut = "contentPanelShortcut"
        static let legacyGlobalShortcut = "globalShortcut"
        static let legacySafariWindowShortcut = "safariGlobalShortcut"
    }

    @Published private(set) var panelShortcut: KeyboardShortcut
    @Published private(set) var lastFeaturePanel: FeaturePanelKind
    @Published private(set) var windowControlShortcuts: [WindowControlID: KeyboardShortcut]
    @Published private(set) var cursorHighlightStyles: Set<CursorHighlightStyle>
    @Published private(set) var mouseBindings: [MouseBindingKey: AppCommand]
    @Published private(set) var mouseDragThresholdRatio: Double
    @Published private(set) var closedLidRunningEnabled: Bool
    @Published private(set) var dsStoreManagementEnabled: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published var compressionQuality: Double {
        didSet {
            defaults.set(compressionQuality, forKey: Keys.compressionQuality)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        panelShortcut = Self.loadPanelShortcut(defaults: defaults)
        lastFeaturePanel = defaults.string(forKey: Keys.lastFeaturePanel)
            .flatMap(FeaturePanelKind.init(rawValue:)) ?? .encodingConversion
        windowControlShortcuts = Self.loadWindowControlShortcuts(defaults: defaults)
        var loadedCursorHighlightStyles = Self.loadCursorHighlightStyles(defaults: defaults)
        if !defaults.bool(forKey: Keys.restoredHikariCursorStyle) {
            loadedCursorHighlightStyles.insert(.mangekyoHikari)
            Self.persistCursorHighlightStyles(
                loadedCursorHighlightStyles,
                defaults: defaults
            )
            defaults.set(true, forKey: Keys.restoredHikariCursorStyle)
        }
        cursorHighlightStyles = loadedCursorHighlightStyles
        mouseBindings = Self.loadMouseBindings(defaults: defaults)
        mouseDragThresholdRatio = Self.loadMouseDragThresholdRatio(defaults: defaults)
        closedLidRunningEnabled = defaults.bool(forKey: Keys.closedLidRunningEnabled)
        dsStoreManagementEnabled = defaults.bool(forKey: Keys.dsStoreManagementEnabled)
        launchAtLoginEnabled = defaults.bool(forKey: Keys.launchAtLoginEnabled)

        let storedQuality = defaults.double(forKey: Keys.compressionQuality)
        compressionQuality = storedQuality == 0 ? 0.7 : storedQuality
    }

    func updatePanelShortcut(_ shortcut: KeyboardShortcut) {
        panelShortcut = shortcut
        Self.persist(shortcut, key: Keys.panelShortcut, defaults: defaults)
    }

    func updateLastFeaturePanel(_ panel: FeaturePanelKind) {
        guard panel != lastFeaturePanel else { return }
        lastFeaturePanel = panel
        defaults.set(panel.rawValue, forKey: Keys.lastFeaturePanel)
    }

    func updateWindowControlShortcut(_ shortcut: KeyboardShortcut, for id: WindowControlID) {
        windowControlShortcuts[id] = shortcut
        saveWindowControlShortcuts()
    }

    func windowControlShortcut(for id: WindowControlID) -> KeyboardShortcut {
        windowControlShortcuts[id] ?? WindowControlCatalog.defaultShortcuts[id] ?? .panelDefault
    }

    func isCursorHighlightStyleEnabled(_ style: CursorHighlightStyle) -> Bool {
        cursorHighlightStyles.contains(style)
    }

    func mouseCommand(
        for button: MouseSideButton,
        gesture: MouseButtonGesture
    ) -> AppCommand? {
        mouseBindings[MouseBindingKey(button: button, gesture: gesture)]
    }

    func hasMouseBindings(for button: MouseSideButton) -> Bool {
        mouseBindings.keys.contains(where: { $0.button == button })
    }

    func updateMouseCommand(
        _ command: AppCommand?,
        for button: MouseSideButton,
        gesture: MouseButtonGesture
    ) {
        let key = MouseBindingKey(button: button, gesture: gesture)
        if let command {
            mouseBindings[key] = command
        } else {
            mouseBindings.removeValue(forKey: key)
        }
        Self.persistMouseBindings(mouseBindings, defaults: defaults)
    }

    func updateMouseDragThresholdRatio(_ ratio: Double) {
        let normalized = MouseGestureConfiguration.normalizedDragThresholdRatio(ratio)
        guard normalized != mouseDragThresholdRatio else { return }
        mouseDragThresholdRatio = normalized
        defaults.set(normalized, forKey: Keys.mouseDragThresholdRatio)
    }

    func updateClosedLidRunningEnabled(_ enabled: Bool) {
        guard enabled != closedLidRunningEnabled else { return }
        closedLidRunningEnabled = enabled
        defaults.set(enabled, forKey: Keys.closedLidRunningEnabled)
    }

    func updateDSStoreManagementEnabled(_ enabled: Bool) {
        guard enabled != dsStoreManagementEnabled else { return }
        dsStoreManagementEnabled = enabled
        defaults.set(enabled, forKey: Keys.dsStoreManagementEnabled)
    }

    func updateLaunchAtLoginEnabled(_ enabled: Bool) {
        guard enabled != launchAtLoginEnabled else { return }
        launchAtLoginEnabled = enabled
        defaults.set(enabled, forKey: Keys.launchAtLoginEnabled)
    }

    @discardableResult
    func updateCursorHighlightStyle(
        _ style: CursorHighlightStyle,
        isEnabled: Bool
    ) -> Bool {
        var updatedStyles = cursorHighlightStyles
        if isEnabled {
            updatedStyles.insert(style)
        } else {
            updatedStyles.remove(style)
        }
        cursorHighlightStyles = updatedStyles
        Self.persistCursorHighlightStyles(updatedStyles, defaults: defaults)
        return true
    }

    private func saveWindowControlShortcuts() {
        let encoded = Dictionary(
            uniqueKeysWithValues: windowControlShortcuts.map { ($0.key.rawValue, $0.value) }
        )
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        defaults.set(data, forKey: Keys.windowControlShortcuts)
    }

    private static func loadPanelShortcut(defaults: UserDefaults) -> KeyboardShortcut {
        if let shortcut = decodeShortcut(defaults.data(forKey: Keys.panelShortcut)) {
            if shortcut == .previousPanelDefault {
                persist(.panelDefault, key: Keys.panelShortcut, defaults: defaults)
                return .panelDefault
            }
            return shortcut
        }

        let migrated = migratedPanelShortcut(defaults: defaults) ?? .panelDefault
        persist(migrated, key: Keys.panelShortcut, defaults: defaults)
        return migrated
    }

    private static func migratedPanelShortcut(defaults: UserDefaults) -> KeyboardShortcut? {
        if let shortcut = decodeShortcut(
            defaults.data(forKey: Keys.previousEncodingConversionShortcut)
        ) {
            return shortcut
        }
        if let shortcut = decodeShortcut(
            defaults.data(forKey: Keys.legacyEncodingConversionShortcut)
        ) {
            return shortcut
        }
        if let shortcut = decodeShortcut(defaults.data(forKey: Keys.legacyGlobalShortcut)) {
            return shortcut == .legacyEncodingPanelDefault ? .panelDefault : shortcut
        }
        if let shortcut = decodeShortcut(
            defaults.data(forKey: Keys.previousSafariWindowShortcut)
        ) {
            return shortcut == .previousSafariPanelDefault ? .panelDefault : shortcut
        }
        if let shortcut = decodeShortcut(
            defaults.data(forKey: Keys.legacySafariWindowShortcut)
        ) {
            return shortcut == .legacySafariPanelDefault ? .panelDefault : shortcut
        }
        return nil
    }

    private static func persist(
        _ shortcut: KeyboardShortcut,
        key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadWindowControlShortcuts(
        defaults: UserDefaults
    ) -> [WindowControlID: KeyboardShortcut] {
        var shortcuts = WindowControlCatalog.defaultShortcuts
        guard
            let data = defaults.data(forKey: Keys.windowControlShortcuts),
            let stored = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data)
        else {
            return shortcuts
        }
        for (rawID, shortcut) in stored {
            guard let id = WindowControlID(rawValue: rawID) else { continue }
            shortcuts[id] = shortcut
        }
        return shortcuts
    }

    private static func loadCursorHighlightStyles(
        defaults: UserDefaults
    ) -> Set<CursorHighlightStyle> {
        let availableStyles = Set(CursorHighlightStyle.allCases)
        guard
            let data = defaults.data(forKey: Keys.cursorHighlightStyles),
            let stored = try? JSONDecoder().decode([CursorHighlightStyle].self, from: data)
        else {
            return availableStyles
        }
        return Set(stored).intersection(availableStyles)
    }

    private static func persistCursorHighlightStyles(
        _ styles: Set<CursorHighlightStyle>,
        defaults: UserDefaults
    ) {
        let orderedStyles = CursorHighlightStyle.allCases.filter(styles.contains)
        guard let data = try? JSONEncoder().encode(orderedStyles) else { return }
        defaults.set(data, forKey: Keys.cursorHighlightStyles)
    }

    private static func loadMouseBindings(
        defaults: UserDefaults
    ) -> [MouseBindingKey: AppCommand] {
        guard
            let data = defaults.data(forKey: Keys.mouseBindings),
            let stored = try? JSONDecoder().decode([MouseBinding].self, from: data)
        else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0.command) })
    }

    private static func persistMouseBindings(
        _ bindings: [MouseBindingKey: AppCommand],
        defaults: UserDefaults
    ) {
        let ordered = MouseSideButton.allCases.flatMap { button in
            MouseButtonGesture.allCases.compactMap { gesture -> MouseBinding? in
                guard let command = bindings[MouseBindingKey(button: button, gesture: gesture)] else {
                    return nil
                }
                return MouseBinding(button: button, gesture: gesture, command: command)
            }
        }
        guard let data = try? JSONEncoder().encode(ordered) else { return }
        defaults.set(data, forKey: Keys.mouseBindings)
    }

    private static func loadMouseDragThresholdRatio(defaults: UserDefaults) -> Double {
        if defaults.object(forKey: Keys.mouseDragThresholdRatio) != nil {
            return MouseGestureConfiguration.normalizedDragThresholdRatio(
                defaults.double(forKey: Keys.mouseDragThresholdRatio)
            )
        }

        guard defaults.object(forKey: Keys.legacyMouseDragThreshold) != nil else {
            return MouseGestureConfiguration.defaultDragThresholdRatio
        }
        let migrated = MouseGestureConfiguration.normalizedDragThresholdRatio(
            defaults.double(forKey: Keys.legacyMouseDragThreshold)
                / MouseGestureConfiguration.legacyReferenceScreenWidth
        )
        defaults.set(migrated, forKey: Keys.mouseDragThresholdRatio)
        defaults.removeObject(forKey: Keys.legacyMouseDragThreshold)
        return migrated
    }

    private static func decodeShortcut(_ data: Data?) -> KeyboardShortcut? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
    }

}
