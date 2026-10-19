import AppKit

final class FloatingPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var modifierHandler: ((NSEvent.ModifierFlags) -> Void)?
    var scrollHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            modifierHandler?(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        }
        if event.type == .scrollWheel, scrollHandler?(event) == true { return }
        if event.type == .keyDown {
            // Let the input method consume arrows/Return while a composed character is active.
            if let editor = firstResponder as? NSTextView, editor.hasMarkedText() {
                super.sendEvent(event)
                return
            }
            if keyHandler?(event) == true { return }
        }
        super.sendEvent(event)
    }
}
