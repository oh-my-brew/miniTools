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
        XCTAssertFalse(state.capsChanged(down: false).used)
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
