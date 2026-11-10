import Carbon
import Foundation

enum KeyboardRemappingRule: String, CaseIterable, Identifiable {
    case commandEscape
    case shiftEscape
    case safariHide
    case capsShortcuts
    case capsInputSourceSwitch
    case doubleRightCommand
    case homerowControlShortcuts
    case ghosttyControlShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandEscape: "⌘Esc → ⌘`"
        case .shiftEscape: "⇧Esc → ⇧`"
        case .safariHide: "Safari：⌘Q → 隐藏"
        case .capsShortcuts: "Caps Lock → miniTools / 已启用映射"
        case .capsInputSourceSwitch: "单按 Caps Lock → 切换输入法"
        case .doubleRightCommand: "双击右 Command → Codex"
        case .homerowControlShortcuts: "Homerow：Caps Lock / ⌃⌥⇧⌘ + M、,、. → ⌃+同键"
        case .ghosttyControlShortcut: "Ghostty：Caps Lock / ⌃⌥⇧⌘ + / → ⌃/"
        }
    }

    static func controlShortcut(for code: UInt16, enabled: Set<Self>) -> Bool {
        if enabled.contains(.homerowControlShortcuts),
           [kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period].contains(Int(code)) {
            return true
        }
        return enabled.contains(.ghosttyControlShortcut) && code == UInt16(kVK_ANSI_Slash)
    }
}

enum CapsInputSourceChoice {
    static func target(current: String, ascii: String, previous: String?) -> String? {
        if current != ascii { return ascii }
        guard let previous, previous != ascii else { return nil }
        return previous
    }
}

/// The Caps Lock flagsChanged event carries the new latch value. A HID callback
/// may run after that value has already changed, so reading HID on key-down
/// cannot reliably recover the state from before the press.
struct CapsLockLatchState {
    private(set) var original: Bool?
    private var physicalReleased = false
    private var suppressLateEvents = false

    mutating func pressed() {
        physicalReleased = false
        suppressLateEvents = false
    }

    mutating func observedChange(to newValue: Bool) -> Bool? {
        guard !suppressLateEvents else { return nil }
        if original == nil { original = !newValue }
        if physicalReleased {
            // HID release can precede both session flagsChanged events. Only
            // the first event identifies the old latch; the next belongs to
            // the same press and must not start another restoration.
            defer { original = nil; suppressLateEvents = true }
            return original
        }
        return original
    }

    mutating func released() -> Bool? {
        physicalReleased = true
        if original != nil { suppressLateEvents = true }
        defer { original = nil }
        return original
    }

    mutating func cancel() -> Bool? {
        defer {
            original = nil
            physicalReleased = false
            suppressLateEvents = false
        }
        return original
    }
}

struct KeyboardRemappingState {
    struct Modifiers: OptionSet {
        let rawValue: UInt8
        static let command = Self(rawValue: 1 << 0)
        static let shift = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)
        static let control = Self(rawValue: 1 << 3)
        static let hyper: Self = [.command, .shift, .option, .control]
    }

    enum Action: Equatable {
        case sendGrave(Modifiers)
        case hideSafari
        case openCodex
        case switchInputSource
        case shortcutDown(UInt16)
        case shortcutUp(UInt16)
        case cancelShortcuts
        case sendControlShortcut(UInt16)
    }

    struct Result {
        let consume: Bool
        let actions: [Action]

        static let pass = Self(consume: false, actions: [])
        static func handled(_ action: Action? = nil) -> Self {
            Self(consume: true, actions: action.map { [$0] } ?? [])
        }
    }

    var enabled: Set<KeyboardRemappingRule> = []
    var availableCapsKeys: Set<UInt16> = []
    private var capsHeld = false
    private var capsUsed = false
    private var consumedCapsKeys: Set<UInt16> = []
    private var consumedKeyUps: Set<UInt16> = []
    private var rightCommandHeld = false
    private var previousRightCommandRelease: TimeInterval?
    private var rightCommandChord = false

    mutating func reset() {
        capsHeld = false
        capsUsed = false
        consumedCapsKeys.removeAll()
        consumedKeyUps.removeAll()
        rightCommandHeld = false
        previousRightCommandRelease = nil
        rightCommandChord = false
    }

    /// HID reports the physical Caps Lock key, independently of its latched modifier flag.
    mutating func capsChanged(down: Bool, modifiersHeld: Bool = false) -> [Action] {
        guard enabled.contains(.capsShortcuts) || enabled.contains(.capsInputSourceSwitch) else {
            return []
        }
        if down {
            guard !capsHeld else { return [] }
            capsHeld = true
            capsUsed = modifiersHeld
            return []
        }
        guard capsHeld else { return [] }
        capsHeld = false
        let shouldSwitch = enabled.contains(.capsInputSourceSwitch) && !capsUsed
        capsUsed = false
        // Do not turn releasing Caps into a short press of a held layout key.
        return shouldSwitch ? [.cancelShortcuts, .switchInputSource] : [.cancelShortcuts]
    }

    mutating func keyDown(
        _ code: UInt16,
        modifiers: Modifiers,
        isRepeat: Bool,
        safariFrontmost: Bool
    ) -> Result {
        rightCommandChord = true
        previousRightCommandRelease = nil
        if capsHeld { capsUsed = true }
        if consumedCapsKeys.contains(code) || consumedKeyUps.contains(code) {
            return .handled()
        }
        if capsHeld, enabled.contains(.capsShortcuts),
           availableCapsKeys.contains(code),
           modifiers.isDisjoint(with: [.command, .option, .control]) {
            consumedCapsKeys.insert(code)
            return .handled(isRepeat ? nil : .shortcutDown(code))
        }
        let capsChord = capsHeld && enabled.contains(.capsShortcuts)
            && modifiers.isDisjoint(with: [.command, .option, .control])
        let hyperChord = modifiers == .hyper
        if (capsChord || hyperChord),
           !availableCapsKeys.contains(code),
           KeyboardRemappingRule.controlShortcut(for: code, enabled: enabled) {
            consumedKeyUps.insert(code)
            return .handled(isRepeat ? nil : .sendControlShortcut(code))
        }
        if !capsHeld, code == UInt16(kVK_Escape) {
            if enabled.contains(.commandEscape),
               modifiers.contains(.command),
               modifiers.isDisjoint(with: [.option, .control]) {
                consumedKeyUps.insert(code)
                return .handled(isRepeat ? nil : .sendGrave(
                    modifiers.contains(.shift) ? [.command, .shift] : [.command]
                ))
            }
            if enabled.contains(.shiftEscape), modifiers == [.shift] {
                consumedKeyUps.insert(code)
                return .handled(isRepeat ? nil : .sendGrave(.shift))
            }
        }
        if !capsHeld, enabled.contains(.safariHide), safariFrontmost,
           code == UInt16(kVK_ANSI_Q), modifiers == [.command] {
            consumedKeyUps.insert(code)
            return .handled(isRepeat ? nil : .hideSafari)
        }
        return .pass
    }

    mutating func keyUp(_ code: UInt16) -> Result {
        if consumedCapsKeys.remove(code) != nil {
            return .handled(capsHeld ? .shortcutUp(code) : nil)
        }
        if consumedKeyUps.remove(code) != nil {
            return .handled()
        }
        return .pass
    }

    /// Do not intercept either Command event: ordinary right Command chords still work.
    mutating func rightCommandChanged(down: Bool, at time: TimeInterval) -> Result {
        if capsHeld { capsUsed = true }
        guard enabled.contains(.doubleRightCommand) else { return .pass }
        if down {
            guard !rightCommandHeld else { return .pass }
            rightCommandHeld = true
            let isDouble = previousRightCommandRelease.map {
                time >= $0 && time - $0 <= 0.3 && !rightCommandChord
            } ?? false
            previousRightCommandRelease = nil
            rightCommandChord = false
            return Result(consume: false, actions: isDouble ? [.openCodex] : [])
        }
        guard rightCommandHeld else { return .pass }
        rightCommandHeld = false
        previousRightCommandRelease = rightCommandChord ? nil : time
        return .pass
    }

    mutating func otherModifierChanged() {
        if capsHeld { capsUsed = true }
        rightCommandChord = true
        previousRightCommandRelease = nil
    }
}
