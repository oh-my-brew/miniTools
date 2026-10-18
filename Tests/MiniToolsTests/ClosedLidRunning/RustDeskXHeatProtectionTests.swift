import XCTest
@testable import MiniTools

@MainActor
final class RustDeskXHeatProtectionTests: XCTestCase {
    func testProtectionDefaultsToDisabledAndPersists() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.rustDeskXHeatProtectionEnabled)
        settings.updateRustDeskXHeatProtectionEnabled(true)
        XCTAssertTrue(AppSettings(defaults: defaults).rustDeskXHeatProtectionEnabled)
    }

    func testDisabledProtectionDoesNotStartMonitoring() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let monitor = FakeProtectionMonitor()
        let terminator = FakeProcessTerminator()
        let controller = RustDeskXHeatProtectionController(
            settings: AppSettings(defaults: defaults),
            monitor: monitor,
            terminator: terminator
        )

        controller.start()
        monitor.send(.sessionLocked)

        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertEqual(terminator.callCount, 0)
    }

    func testEnabledProtectionHandlesLockAndClosedLidEvents() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let monitor = FakeProtectionMonitor()
        let terminator = FakeProcessTerminator(runningCount: 1, terminatedCount: 1)
        let controller = RustDeskXHeatProtectionController(
            settings: AppSettings(defaults: defaults),
            monitor: monitor,
            terminator: terminator
        )

        controller.setEnabled(true)
        monitor.send(.sessionLocked)
        XCTAssertEqual(controller.lastAction, "已在锁屏时强制关闭 RustDeskX")

        monitor.send(.lidClosed)
        XCTAssertEqual(controller.lastAction, "已在合盖时强制关闭 RustDeskX")
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertEqual(terminator.callCount, 2)
    }

    func testDisablingProtectionStopsAndIgnoresLaterEvents() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let monitor = FakeProtectionMonitor()
        let terminator = FakeProcessTerminator(runningCount: 1, terminatedCount: 1)
        let controller = RustDeskXHeatProtectionController(
            settings: AppSettings(defaults: defaults),
            monitor: monitor,
            terminator: terminator
        )

        controller.setEnabled(true)
        controller.setEnabled(false)
        monitor.send(.sessionLocked)

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(terminator.callCount, 0)
        XCTAssertFalse(AppSettings(defaults: defaults).rustDeskXHeatProtectionEnabled)
    }

    func testProductionTerminatorTargetsOnlyRustDeskXBundleIdentifier() {
        XCTAssertEqual(
            WorkspaceRustDeskXProcessTerminator.bundleIdentifier,
            "com.omzcj.rustdeskx"
        )
    }

    func testClamshellEventOnlyTriggersForClosedStateChanges() {
        XCTAssertTrue(
            RustDeskXClamshellEvent.indicatesClosed(
                messageType: RustDeskXClamshellEvent.stateChangeMessage,
                argument: 1
            )
        )
        XCTAssertFalse(
            RustDeskXClamshellEvent.indicatesClosed(
                messageType: RustDeskXClamshellEvent.stateChangeMessage,
                argument: 0
            )
        )
        XCTAssertFalse(
            RustDeskXClamshellEvent.indicatesClosed(
                messageType: 0,
                argument: 1
            )
        )
    }

    func testTerminationFailureIsVisible() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let monitor = FakeProtectionMonitor()
        let controller = RustDeskXHeatProtectionController(
            settings: AppSettings(defaults: defaults),
            monitor: monitor,
            terminator: FakeProcessTerminator(runningCount: 1, terminatedCount: 0)
        )

        controller.setEnabled(true)
        monitor.send(.sessionLocked)

        XCTAssertEqual(controller.lastError, "锁屏时无法强制关闭 RustDeskX")
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MiniToolsTests.RustDeskXHeatProtection.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}

@MainActor
private final class FakeProtectionMonitor: RustDeskXProtectionEventMonitoring {
    var onTrigger: ((RustDeskXProtectionTrigger) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func send(_ trigger: RustDeskXProtectionTrigger) { onTrigger?(trigger) }
}

private final class FakeProcessTerminator: RustDeskXProcessTerminating {
    private(set) var callCount = 0
    private let runningCount: Int
    private let terminatedCount: Int

    init(runningCount: Int = 0, terminatedCount: Int = 0) {
        self.runningCount = runningCount
        self.terminatedCount = terminatedCount
    }

    func forceTerminateRunningInstances() -> RustDeskXTerminationResult {
        callCount += 1
        return RustDeskXTerminationResult(
            runningCount: runningCount,
            terminatedCount: terminatedCount
        )
    }
}
