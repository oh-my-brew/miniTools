import Carbon
import XCTest
@testable import MiniTools

final class KeyboardRemappingStateTests: XCTestCase {
    func testEscapeMappingsOnlyConsumeTheirExactModifiers() {
        var state = KeyboardRemappingState()
        state.enabled = [.commandEscape, .shiftEscape]
        let esc = UInt16(kVK_Escape)
        XCTAssertEqual(state.keyDown(esc, modifiers: .command, isRepeat: false,
                                     safariFrontmost: false).actions, [.sendGrave(.command)])
        XCTAssertTrue(state.keyUp(esc).consume)
        XCTAssertEqual(state.keyDown(esc, modifiers: [.command, .shift], isRepeat: false,
                                     safariFrontmost: false).actions,
                       [.sendGrave([.command, .shift])])
        XCTAssertTrue(state.keyUp(esc).consume)
        XCTAssertEqual(state.keyDown(esc, modifiers: .shift, isRepeat: false,
                                     safariFrontmost: false).actions, [.sendGrave(.shift)])
        XCTAssertTrue(state.keyUp(esc).consume)
        XCTAssertFalse(state.keyDown(esc, modifiers: [.option, .shift], isRepeat: false,
                                         safariFrontmost: false).consume)
        XCTAssertFalse(state.keyDown(esc, modifiers: [], isRepeat: false,
                                         safariFrontmost: false).consume)
    }

    func testSafariHideOnlyReplacesFrontmostSafariCommandQ() {
        var state = KeyboardRemappingState()
        state.enabled = [.safariHide]
        let q = UInt16(kVK_ANSI_Q)
        XCTAssertFalse(state.keyDown(q, modifiers: .command, isRepeat: false,
                                     safariFrontmost: false).consume)
        XCTAssertFalse(state.keyDown(q, modifiers: [.command, .shift], isRepeat: false,
                                     safariFrontmost: true).consume)
        let result = state.keyDown(q, modifiers: .command, isRepeat: false,
                                   safariFrontmost: true)
        XCTAssertTrue(result.consume)
        XCTAssertEqual(result.actions, [.hideSafari])
        XCTAssertTrue(state.keyUp(q).consume)
    }

    func testCapsPrefixOnlyRoutesAssignedKeysAndCancelsHeldSizeOnRelease() {
        var state = KeyboardRemappingState()
        state.enabled = [.capsShortcuts]
        state.availableCapsKeys = [UInt16(kVK_ANSI_J)]
        XCTAssertFalse(state.capsChanged(down: true).used)
        XCTAssertFalse(state.keyDown(UInt16(kVK_ANSI_X), modifiers: [], isRepeat: false,
                                     safariFrontmost: false).consume)
        XCTAssertEqual(state.keyDown(UInt16(kVK_ANSI_J), modifiers: [], isRepeat: false,
                                     safariFrontmost: false).actions,
                       [.shortcutDown(UInt16(kVK_ANSI_J))])
        XCTAssertTrue(state.keyDown(UInt16(kVK_ANSI_J), modifiers: [], isRepeat: true,
                                     safariFrontmost: false).consume)
        XCTAssertEqual(state.capsChanged(down: false).actions, [.cancelShortcuts])
        XCTAssertTrue(state.keyUp(UInt16(kVK_ANSI_J)).consume)
        XCTAssertFalse(state.capsChanged(down: true).used)
        XCTAssertEqual(state.capsChanged(down: false).actions, [.switchInputSource])
    }

    func testCapsPrefixReleasesHeldKeyBeforeCaps() {
        var state = KeyboardRemappingState()
        state.enabled = [.capsShortcuts]
        state.availableCapsKeys = [UInt16(kVK_ANSI_J)]
        _ = state.capsChanged(down: true)
        _ = state.keyDown(UInt16(kVK_ANSI_J), modifiers: [], isRepeat: false,
                          safariFrontmost: false)
        XCTAssertEqual(state.keyUp(UInt16(kVK_ANSI_J)).actions,
                       [.shortcutUp(UInt16(kVK_ANSI_J))])
        XCTAssertTrue(state.capsChanged(down: false).used)
    }

    func testCapsLatchStaysUnchangedThroughHeldShortcutInBothDirections() {
        for original in [false, true] {
            var latch = CapsLockLatchState()
            var keys = KeyboardRemappingState()
            keys.enabled = [.capsShortcuts]
            keys.availableCapsKeys = [UInt16(kVK_ANSI_J)]
            _ = keys.capsChanged(down: true)
            // By the time HID reports the physical press, the system may already
            // have toggled. The flagsChanged transition still identifies the old state.
            XCTAssertEqual(latch.observedChange(to: !original), original)
            XCTAssertEqual(keys.keyDown(UInt16(kVK_ANSI_J), modifiers: [],
                                        isRepeat: false, safariFrontmost: false).actions,
                           [.shortcutDown(UInt16(kVK_ANSI_J))])
            XCTAssertEqual(latch.observedChange(to: !original), original)
            XCTAssertTrue(keys.keyDown(UInt16(kVK_ANSI_J), modifiers: [],
                                       isRepeat: true, safariFrontmost: false).consume)
            _ = keys.keyUp(UInt16(kVK_ANSI_J))
            XCTAssertTrue(keys.capsChanged(down: false).used)
            XCTAssertEqual(latch.released(), original)
        }
    }

    func testCapsLatchPreservesCaseOnLoneTapAndDoesNotGuessWithoutSystemEvent() {
        var latch = CapsLockLatchState()
        XCTAssertEqual(latch.observedChange(to: true), false)
        XCTAssertEqual(latch.released(), false)
        XCTAssertEqual(latch.observedChange(to: false), true)
        XCTAssertEqual(latch.released(), true)
        XCTAssertNil(latch.released())
        // A late system event can still reveal the state before a fast tap.
        XCTAssertEqual(latch.observedChange(to: true), false)
        XCTAssertEqual(latch.cancel(), false)
    }

    func testCapsTapInputSourceChoiceKeepsTheExactPreviouslySelectedMethod() {
        let abc = "com.apple.keylayout.ABC"
        let doubao = "com.bytedance.inputmethod.doubaoime.pinyin"
        XCTAssertEqual(CapsInputSourceChoice.target(current: doubao, ascii: abc, previous: nil),
                       abc)
        XCTAssertEqual(CapsInputSourceChoice.target(current: abc, ascii: abc, previous: doubao),
                       doubao)
        XCTAssertNil(CapsInputSourceChoice.target(current: abc, ascii: abc, previous: nil))
        XCTAssertNil(CapsInputSourceChoice.target(current: abc, ascii: abc, previous: abc))
    }

    func testDoubleRightCommandDoesNotStealNormalChord() {
        var state = KeyboardRemappingState()
        state.enabled = [.doubleRightCommand]
        XCTAssertTrue(state.rightCommandChanged(down: true, at: 1).actions.isEmpty)
        _ = state.rightCommandChanged(down: false, at: 1.05)
        let double = state.rightCommandChanged(down: true, at: 1.34)
        XCTAssertFalse(double.consume)
        XCTAssertEqual(double.actions, [.openCodex])
        _ = state.rightCommandChanged(down: false, at: 1.37)

        _ = state.rightCommandChanged(down: true, at: 2)
        _ = state.keyDown(UInt16(kVK_ANSI_C), modifiers: .command, isRepeat: false,
                           safariFrontmost: false)
        _ = state.rightCommandChanged(down: false, at: 2.1)
        XCTAssertTrue(state.rightCommandChanged(down: true, at: 2.2).actions.isEmpty)
    }

    func testDoubleRightCommandExpiresAndOtherModifiersCancel() {
        var state = KeyboardRemappingState()
        state.enabled = [.doubleRightCommand]
        _ = state.rightCommandChanged(down: true, at: 1)
        _ = state.rightCommandChanged(down: false, at: 1.1)
        XCTAssertTrue(state.rightCommandChanged(down: true, at: 1.401).actions.isEmpty)
        _ = state.rightCommandChanged(down: false, at: 1.5)
        state.otherModifierChanged()
        XCTAssertTrue(state.rightCommandChanged(down: true, at: 1.6).actions.isEmpty)
    }
}
