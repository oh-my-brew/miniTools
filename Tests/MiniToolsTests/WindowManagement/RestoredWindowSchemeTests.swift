import Carbon
import CoreGraphics
import XCTest
@testable import MiniTools

@MainActor
final class RestoredWindowSchemeTests: XCTestCase {
    func testRestoredSchemeRequiresFreshOptInAndKeepsClassicBindings() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("sizeAndPosition", forKey: "windowManagementMode")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.windowManagementMode, .classic)
        XCTAssertEqual(settings.windowLongPressThresholdMilliseconds, 200)
        let original = settings.windowControlShortcuts
        settings.updateWindowManagementMode(.sizeAndPosition)
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | optionKey))
        settings.updateComposedWindowControlShortcut(shortcut, for: .fullOrHalfHeight)
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.windowManagementMode, .sizeAndPosition)
        XCTAssertEqual(restored.composedWindowControlShortcut(for: .fullOrHalfHeight), shortcut)
        restored.updateWindowManagementMode(.classic)
        XCTAssertEqual(restored.windowControlShortcuts, original)
        XCTAssertEqual(AppSettings(defaults: defaults).windowManagementMode, .classic)
    }

    func testThresholdPersistsAndClampsToSupportedRange() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        for (value, expected) in [(250, 250), (-1, 100), (999, 600)] {
            settings.updateWindowLongPressThresholdMilliseconds(value)
            XCTAssertEqual(AppSettings(defaults: defaults).windowLongPressThresholdMilliseconds, expected)
        }
    }

    func testPlacementDoesNotWriteSizeForEitherPolicy() throws {
        for policy in [WindowAdjustmentPolicy.baseline, .compatible] {
            var frame = CGRect(x: 200, y: 100, width: 600, height: 600)
            let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
            let target = CGRect(x: 600, y: 300, width: 600, height: 600)
            var clock = 0.0
            let result = try WindowFrameAdjustment.run(
                target: target, read: { frame }, position: { frame.origin = $0 },
                size: { _ in XCTFail("Position-only command must not write AXSize") },
                check: {}, trace: WindowAdjustmentTrace(command: "composed.position.trailing", requestedAt: 0),
                policy: policy, initial: frame, allowsResize: false,
                placement: WindowFramePlacement(target: target, visible: screen),
                uptime: { clock }, wait: { clock += 0.012 }
            )
            XCTAssertEqual(result.outcome, .applied)
            XCTAssertEqual(result.frame, target)
        }
    }

    func testDefaultShortcutsDoNotOverlapSharedCrossScreenKeys() {
        let shared = WindowControlCatalog.crossScreenIDs.compactMap { WindowControlCatalog.defaultShortcuts[$0] }
        for shortcut in ComposedWindowControlCatalog.defaultShortcuts.values {
            XCTAssertFalse(shared.contains(shortcut))
        }
        XCTAssertEqual(ComposedWindowControlCatalog.defaultShortcuts[.fullOrHalfHeight]?.keyCode, UInt32(kVK_ANSI_U))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "RestoredWindowSchemeTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
}

@MainActor
final class HotKeyLongPressRecognizerTests: XCTestCase {
    private final class Scheduler {
        var delays: [Duration] = []
        var callbacks: [@MainActor () -> Void] = []
        var cancelled = 0
        func schedule(_ duration: Duration, fire: @escaping @MainActor () -> Void) -> () -> Void {
            delays.append(duration)
            callbacks.append(fire)
            return { self.cancelled += 1 }
        }
    }

    func testShortPressIsOnReleaseAndRepeatIsIgnored() {
        let scheduler = Scheduler()
        var short = 0, long = 0
        let recognizer = HotKeyLongPressRecognizer(schedule: scheduler.schedule,
            onShortPress: { short += 1 }, onLongPress: { long += 1 })
        recognizer.press(); recognizer.press()
        XCTAssertEqual(short, 0)
        XCTAssertEqual(scheduler.callbacks.count, 1)
        recognizer.release(); recognizer.release()
        scheduler.callbacks[0]() // A cancelled callback cannot emit a late long press.
        XCTAssertEqual(short, 1)
        XCTAssertEqual(long, 0)
    }

    func testLongPressFiresOnceAndSuppressesShortRelease() {
        let scheduler = Scheduler()
        var short = 0, long = 0
        let recognizer = HotKeyLongPressRecognizer(schedule: scheduler.schedule,
            onShortPress: { short += 1 }, onLongPress: { long += 1 })
        recognizer.press()
        XCTAssertEqual(scheduler.delays, [.milliseconds(200)])
        scheduler.callbacks[0](); scheduler.callbacks[0]()
        recognizer.press(); recognizer.release()
        XCTAssertEqual(short, 0)
        XCTAssertEqual(long, 1)
    }

    func testCancellationAndThresholdChangeInvalidateOldCallbacks() {
        let scheduler = Scheduler()
        var actions = 0
        let recognizer = HotKeyLongPressRecognizer(schedule: scheduler.schedule,
            onShortPress: { actions += 1 }, onLongPress: { actions += 1 })
        recognizer.press(); recognizer.cancel(); recognizer.release()
        recognizer.press(); recognizer.updateThreshold(.milliseconds(300))
        recognizer.press()
        scheduler.callbacks[0](); scheduler.callbacks[1]()
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(scheduler.delays.last, .milliseconds(300))
        scheduler.callbacks[2](); recognizer.release()
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(scheduler.cancelled, 3)
    }
}
