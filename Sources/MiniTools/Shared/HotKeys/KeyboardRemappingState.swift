import Carbon
import Foundation

enum KeyboardRemappingRule: String, CaseIterable, Identifiable {
    case commandEscape
    case shiftEscape
    case safariHide
    case capsShortcuts
    case doubleRightCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandEscape: "⌘Esc → ⌘`"
        case .shiftEscape: "⇧Esc → ⇧`"
        case .safariHide: "Safari：⌘Q → 隐藏"
        case .capsShortcuts: "Caps Lock → miniTools 快捷键"
        case .doubleRightCommand: "双击右 Command → Codex"
        }
    }
}

/// The Caps Lock flagsChanged event carries the new latch value. A HID callback
/// may run after that value has already changed, so reading HID on key-down
/// cannot reliably recover the state from before the press.
struct CapsLockLatchState {
    private(set) var original: Bool?

    mutating func observedChange(to newValue: Bool) -> Bool {
        if original == nil { original = !newValue }
        return original!
    }

    mutating func released() -> Bool? {
        defer { original = nil }
        return original
    }

    mutating func cancel() -> Bool? {
        defer { original = nil }
        return original
    }
}

enum CapsInputSourceChoice {
    static func target(current: String, ascii: String, previous: String?) -> String? {
        if current != ascii { return ascii }
        guard let previous, previous != ascii else { return nil }
        return previous
    }
}

struct KeyboardRemappingState {
    struct Modifiers: OptionSet {
        let rawValue: UInt8
        static let command = Self(rawValue: 1 << 0)
        static let shift = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)
        static let control = Self(rawValue: 1 << 3)
    }

    enum Action: Equatable {
        case sendGrave(Modifiers)
        case hideSafari
        case openCodex
        case switchInputSource
        case shortcutDown(UInt16)
        case shortcutUp(UInt16)
        case cancelShortcuts
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
    /// Returns true when this press was used as a miniTools prefix.
    mutating func capsChanged(down: Bool) -> (used: Bool, actions: [Action]) {
        guard enabled.contains(.capsShortcuts) else { return (false, []) }
        if down {
            guard !capsHeld else { return (false, []) }
            capsHeld = true
            capsUsed = false
            return (false, [])
        }
        guard capsHeld else { return (false, []) }
        capsHeld = false
        let used = capsUsed
        capsUsed = false
        // Do not turn releasing Caps into a short press of a held layout key.
        return (used, used ? [.cancelShortcuts] : [.switchInputSource])
    }

    mutating func keyDown(
        _ code: UInt16,
        modifiers: Modifiers,
        isRepeat: Bool,
        safariFrontmost: Bool
    ) -> Result {
        rightCommandChord = true
        previousRightCommandRelease = nil
        if consumedCapsKeys.contains(code) || consumedKeyUps.contains(code) {
            return .handled()
        }
        if capsHeld { capsUsed = true }
        if capsHeld, enabled.contains(.capsShortcuts),
           availableCapsKeys.contains(code),
           modifiers.isDisjoint(with: [.command, .option, .control]) {
            capsUsed = true
            consumedCapsKeys.insert(code)
            return .handled(isRepeat ? nil : .shortcutDown(code))
        }
        if code == UInt16(kVK_Escape) {
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
        if enabled.contains(.safariHide), safariFrontmost,
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
        rightCommandChord = true
        previousRightCommandRelease = nil
    }
}
