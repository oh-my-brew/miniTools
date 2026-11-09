import Carbon
import Foundation

/// Toggle between the current input method and the user's ASCII keyboard
/// layout. Remember the exact non-ASCII source so a restart does not silently
/// substitute a different Chinese (or other) input method.
@MainActor
final class CapsInputSourceSwitcher {
    private static let previousIDKey = "capsLockPreviousInputSourceID"
    private let defaults: UserDefaults
    private var previousSource: TISInputSource?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func rememberCurrent() {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let currentID = identifier(of: current),
              let asciiID = identifier(of: ascii),
              currentID != asciiID else { return }
        previousSource = current
        defaults.set(currentID, forKey: Self.previousIDKey)
    }

    /// Returns a user-facing error when the previous source is unavailable.
    func toggle() -> String? {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let currentID = identifier(of: current),
              let asciiID = identifier(of: ascii) else {
            return "无法读取当前输入法"
        }
        let previous = defaults.string(forKey: Self.previousIDKey)
        guard let target = CapsInputSourceChoice.target(
            current: currentID, ascii: asciiID, previous: previous
        ) else {
            return "请先手动切换到另一种输入法，再单按 Caps Lock"
        }
        let inputSource: TISInputSource
        if target == asciiID {
            inputSource = ascii
        } else if let previousSource, identifier(of: previousSource) == target {
            inputSource = previousSource
        } else {
            let enabledSources = TISCreateInputSourceList(nil, false).takeRetainedValue()
            var foundSource: TISInputSource?
            for index in 0..<CFArrayGetCount(enabledSources) {
                guard let pointer = CFArrayGetValueAtIndex(enabledSources, index) else { continue }
                let candidate = Unmanaged<TISInputSource>.fromOpaque(pointer).takeUnretainedValue()
                if identifier(of: candidate) == target {
                    foundSource = candidate
                    break
                }
            }
            guard let source = foundSource else {
                return "原输入法已不可用，请先手动选择一种输入法"
            }
            inputSource = source
        }
        guard TISSelectInputSource(inputSource) == noErr else {
            return "切换输入法失败，请检查输入法是否已启用"
        }
        if target == asciiID {
            previousSource = current
            defaults.set(currentID, forKey: Self.previousIDKey)
        }
        return nil
    }

    private func identifier(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
