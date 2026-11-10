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
        XCTAssertTrue(state.capsChanged(down: true).isEmpty)
        XCTAssertFalse(state.keyDown(UInt16(kVK_ANSI_X), modifiers: [], isRepeat: false,
                                     safariFrontmost: false).consume)
        XCTAssertEqual(state.keyDown(UInt16(kVK_ANSI_J), modifiers: [], isRepeat: false,
                                     safariFrontmost: false).actions,
                       [.shortcutDown(UInt16(kVK_ANSI_J))])
        XCTAssertTrue(state.keyDown(UInt16(kVK_ANSI_J), modifiers: [], isRepeat: true,
                                     safariFrontmost: false).consume)
        XCTAssertEqual(state.capsChanged(down: false), [.cancelShortcuts])
        XCTAssertTrue(state.keyUp(UInt16(kVK_ANSI_J)).consume)
        XCTAssertTrue(state.capsChanged(down: true).isEmpty)
        XCTAssertEqual(state.capsChanged(down: false), [.cancelShortcuts])
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
        XCTAssertEqual(state.capsChanged(down: false), [.cancelShortcuts])
    }

    func testControlMappingsRequireExactHyperChordAndEnabledRule() {
        let hyper: KeyboardRemappingState.Modifiers = [.command, .option, .shift, .control]
        for (rule, codes) in [
            (KeyboardRemappingRule.homerowControlShortcuts,
             [kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period]),
            (.ghosttyControlShortcut, [kVK_ANSI_Slash])
        ] {
            for rawCode in codes {
                let code = UInt16(rawCode)
                var state = KeyboardRemappingState()
                XCTAssertFalse(state.keyDown(code, modifiers: hyper, isRepeat: false,
                                             safariFrontmost: false).consume)
                state.enabled = [rule]
                let nonMatching: [KeyboardRemappingState.Modifiers] = [
                    [], [.command, .option, .control], [.command, .shift, .option],
                    [.control, .shift]
                ]
                for modifiers in nonMatching {
                    XCTAssertFalse(state.keyDown(code, modifiers: modifiers, isRepeat: false,
                                                 safariFrontmost: false).consume)
                }
                let result = state.keyDown(code, modifiers: hyper, isRepeat: false,
                                           safariFrontmost: false)
                XCTAssertTrue(result.consume)
                XCTAssertEqual(result.actions, [.sendControlShortcut(code)])
                XCTAssertTrue(state.keyDown(code, modifiers: hyper, isRepeat: true,
                                            safariFrontmost: false).actions.isEmpty)
                XCTAssertTrue(state.keyUp(code).consume)
                XCTAssertFalse(state.keyUp(code).consume)
            }
        }
    }

    func testCapsControlMappingAndMiniToolsShortcutPriority() {
        let code = UInt16(kVK_ANSI_M)
        var state = KeyboardRemappingState()
        state.enabled = [.capsShortcuts, .homerowControlShortcuts]
        _ = state.capsChanged(down: true)
        XCTAssertEqual(state.keyDown(code, modifiers: [], isRepeat: false,
                                     safariFrontmost: false).actions, [.sendControlShortcut(code)])
        XCTAssertTrue(state.keyUp(code).consume)
        XCTAssertEqual(state.capsChanged(down: false), [.cancelShortcuts])

        state.availableCapsKeys = [code]
        _ = state.capsChanged(down: true)
        XCTAssertEqual(state.keyDown(code, modifiers: [], isRepeat: false,
                                     safariFrontmost: false).actions, [.shortcutDown(code)])
        XCTAssertEqual(state.keyUp(code).actions, [.shortcutUp(code)])
        _ = state.capsChanged(down: false)
        XCTAssertFalse(state.keyDown(code, modifiers: [.command, .option, .shift, .control],
                                     isRepeat: false, safariFrontmost: false).consume)
    }

    func testCapsLatchStaysUnchangedThroughHeldShortcutInBothDirections() {
        for original in [false, true] {
            var latch = CapsLockLatchState()
            var keys = KeyboardRemappingState()
            keys.enabled = [.capsShortcuts]
            keys.availableCapsKeys = [UInt16(kVK_ANSI_J)]
            latch.pressed()
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
            XCTAssertEqual(keys.capsChanged(down: false), [.cancelShortcuts])
            XCTAssertEqual(latch.released(), original)
        }
    }

    func testCapsLatchPreservesCaseOnLoneTapAndDoesNotGuessWithoutSystemEvent() {
        var latch = CapsLockLatchState()
        latch.pressed()
        XCTAssertEqual(latch.observedChange(to: true), false)
        XCTAssertEqual(latch.released(), false)
        XCTAssertNil(latch.observedChange(to: true))
        latch.pressed()
        XCTAssertEqual(latch.observedChange(to: false), true)
        XCTAssertEqual(latch.released(), true)
        XCTAssertNil(latch.released())
        latch.pressed()
        XCTAssertEqual(latch.observedChange(to: true), false)
        XCTAssertEqual(latch.cancel(), false)
    }

    func testCapsLatchIgnoresBothSessionEventsAfterPhysicalRelease() {
        for original in [false, true] {
            var latch = CapsLockLatchState()
            latch.pressed()
            XCTAssertNil(latch.released())
            XCTAssertEqual(latch.observedChange(to: !original), original)
            XCTAssertNil(latch.observedChange(to: !original))
            latch.pressed()
            XCTAssertEqual(latch.observedChange(to: original), !original)
            XCTAssertEqual(latch.released(), !original)
        }
    }

    func testCapsTapHasNoInputSourceActionAndUnassignedKeysPassThrough() {
        var keys = KeyboardRemappingState()
        keys.enabled = [.capsShortcuts]
        XCTAssertTrue(keys.capsChanged(down: true).isEmpty)
        let unassigned = UInt16(kVK_ANSI_F)
        XCTAssertFalse(keys.keyDown(unassigned, modifiers: [], isRepeat: false,
                                     safariFrontmost: false).consume)
        XCTAssertFalse(keys.keyUp(unassigned).consume)
        XCTAssertEqual(keys.capsChanged(down: false), [.cancelShortcuts])
        XCTAssertTrue(keys.capsChanged(down: false).isEmpty)
    }

    func testCapsInputSourceSwitchNeedsAnEnabledLoneTap() {
        var keys = KeyboardRemappingState()
        XCTAssertTrue(keys.capsChanged(down: true).isEmpty)
        XCTAssertTrue(keys.capsChanged(down: false).isEmpty)

        keys.enabled = [.capsInputSourceSwitch]
        XCTAssertTrue(keys.capsChanged(down: true).isEmpty)
        XCTAssertEqual(keys.capsChanged(down: false), [.cancelShortcuts, .switchInputSource])
        XCTAssertTrue(keys.capsChanged(down: false).isEmpty)

        _ = keys.capsChanged(down: true)
        let f = UInt16(kVK_ANSI_F)
        XCTAssertFalse(keys.keyDown(f, modifiers: [], isRepeat: false,
                                     safariFrontmost: false).consume)
        XCTAssertFalse(keys.keyUp(f).consume)
        XCTAssertEqual(keys.capsChanged(down: false),
                       [.cancelShortcuts, .capsTapBlocked(.otherKey)])

        _ = keys.capsChanged(down: true)
        keys.otherModifierChanged()
        XCTAssertEqual(keys.capsChanged(down: false),
                       [.cancelShortcuts, .capsTapBlocked(.modifierChanged)])

        _ = keys.capsChanged(down: true, modifiersHeld: true)
        XCTAssertEqual(keys.capsChanged(down: false),
                       [.cancelShortcuts, .capsTapBlocked(.heldModifier)])
    }

    func testCapsShortcutAndInputSourceSwitchAreIndependent() {
        var keys = KeyboardRemappingState()
        keys.enabled = [.capsShortcuts, .capsInputSourceSwitch]
        keys.availableCapsKeys = [UInt16(kVK_ANSI_J)]
        _ = keys.capsChanged(down: true)
        XCTAssertEqual(keys.keyDown(UInt16(kVK_ANSI_J), modifiers: [], isRepeat: false,
                                    safariFrontmost: false).actions,
                       [.shortcutDown(UInt16(kVK_ANSI_J))])
        XCTAssertEqual(keys.capsChanged(down: false),
                       [.cancelShortcuts, .capsTapBlocked(.otherKey)])
        _ = keys.capsChanged(down: true)
        XCTAssertEqual(keys.capsChanged(down: false), [.cancelShortcuts, .switchInputSource])

        _ = keys.capsChanged(down: true)
        _ = keys.rightCommandChanged(down: true, at: 1)
        XCTAssertEqual(keys.capsChanged(down: false),
                       [.cancelShortcuts, .capsTapBlocked(.modifierChanged)])
        keys.reset()
        XCTAssertTrue(keys.capsChanged(down: false).isEmpty)
    }

    func testInputSourceChoiceUsesLastNonASCIIInputSource() {
        XCTAssertEqual(CapsInputSourceChoice.target(
            current: "chinese", ascii: "english", previous: nil
        ), "english")
        XCTAssertEqual(CapsInputSourceChoice.target(
            current: "english", ascii: "english", previous: "chinese"
        ), "chinese")
        XCTAssertNil(CapsInputSourceChoice.target(
            current: "english", ascii: "english", previous: nil
        ))
        XCTAssertNil(CapsInputSourceChoice.target(
            current: "english", ascii: "english", previous: "english"
        ))
    }

    func testCapsOnlyTriggersEnabledHomerowAndGhosttyMappings() {
        for (rule, codes) in [
            (KeyboardRemappingRule.homerowControlShortcuts,
             [kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period]),
            (.ghosttyControlShortcut, [kVK_ANSI_Slash])
        ] {
            for rawCode in codes {
                let code = UInt16(rawCode)
                var keys = KeyboardRemappingState()
                keys.enabled = [.capsShortcuts]
                _ = keys.capsChanged(down: true)
                XCTAssertFalse(keys.keyDown(code, modifiers: [], isRepeat: false,
                                             safariFrontmost: false).consume)
                XCTAssertFalse(keys.keyUp(code).consume)
                _ = keys.capsChanged(down: false)

                keys.enabled.insert(rule)
                _ = keys.capsChanged(down: true)
                XCTAssertEqual(keys.keyDown(code, modifiers: [], isRepeat: false,
                                             safariFrontmost: false).actions,
                               [.sendControlShortcut(code)])
                XCTAssertTrue(keys.keyUp(code).consume)
                _ = keys.capsChanged(down: false)
            }
        }
    }

    func testCapsChordDoesNotRunEscapeOrSafariHideMappings() {
        var state = KeyboardRemappingState()
        state.enabled = [.capsShortcuts, .commandEscape, .shiftEscape, .safariHide]
        _ = state.capsChanged(down: true)
        XCTAssertFalse(state.keyDown(UInt16(kVK_Escape), modifiers: .command,
                                     isRepeat: false, safariFrontmost: false).consume)
        XCTAssertFalse(state.keyDown(UInt16(kVK_ANSI_Q), modifiers: .command,
                                     isRepeat: false, safariFrontmost: true).consume)
        _ = state.capsChanged(down: false)
        XCTAssertEqual(state.keyDown(UInt16(kVK_Escape), modifiers: .command,
                                     isRepeat: false, safariFrontmost: false).actions,
                       [.sendGrave(.command)])
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
