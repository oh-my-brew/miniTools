import ApplicationServices
import XCTest
@testable import MiniTools

final class SafariWindowActivationTests: XCTestCase {
    func testRestorationSettlesBeforeRaiseAndTimedOutSuccessIsVerified() throws {
        var time = 0.0
        var restored = false
        var frontmost = false
        var raises = 0
        let operation = SafariWindowActivation(isMinimized: { !restored }, restore: {
            .cannotComplete // The request was accepted, but the reply timed out.
        }, raise: {
            XCTAssertTrue(restored)
            raises += 1
            frontmost = true
            return .cannotComplete
        }, isFrontmost: { frontmost }, now: { time }, pause: {
            time += 0.05
            if time >= 0.1 { restored = true }
        })
        try operation.run()
        XCTAssertEqual(raises, 1)
    }

    func testOrdinaryWindowStillUsesOneImmediateRaiseWithoutWaiting() throws {
        var raises = 0
        try SafariWindowActivation(isMinimized: { false }, restore: {
            XCTFail("already restored"); return .success
        }, raise: { raises += 1; return .success }, isFrontmost: {
            XCTFail("successful action needs no timeout recovery"); return false
        }, pause: { XCTFail("no wait on normal fast path") }).run()
        XCTAssertEqual(raises, 1)
    }

    func testTransientRaiseTimeoutRetriesAndEventuallySucceeds() throws {
        var time = 0.0
        var raises = 0
        try SafariWindowActivation(isMinimized: { false }, restore: { .success }, raise: {
            raises += 1
            return raises == 1 ? .cannotComplete : .success
        }, isFrontmost: { false }, now: { time }, pause: { time += 0.05 }).run()
        XCTAssertEqual(raises, 2)
    }

    func testUnconfirmedTimeoutIsNotSilentlyAcceptedAndRetriesAreBounded() {
        var time = 0.0
        var raises = 0
        XCTAssertThrowsError(try SafariWindowActivation(isMinimized: { nil }, restore: { .success }, raise: {
            raises += 1; return .cannotComplete
        }, isFrontmost: { true }, now: { time }, pause: { time += 0.05 }).run())
        XCTAssertEqual(raises, 3)
    }

    func testRestoreFailureOrUnsettledMinimizationDoesNotRaise() {
        XCTAssertThrowsError(try SafariWindowActivation(isMinimized: { true }, restore: { .invalidUIElement },
            raise: { XCTFail("invalid window"); return .success }, isFrontmost: { false }).run())
        var time = 0.0
        XCTAssertThrowsError(try SafariWindowActivation(isMinimized: { true }, restore: { .success },
            raise: { XCTFail("still minimized"); return .success }, isFrontmost: { false },
            now: { time }, pause: { time += 0.05 }).run())
        XCTAssertGreaterThanOrEqual(time, 3)
    }

    func testPermanentRaiseFailureDoesNotRetryOrDisappear() {
        var raises = 0
        XCTAssertThrowsError(try SafariWindowActivation(isMinimized: { false }, restore: { .success },
            raise: { raises += 1; return .actionUnsupported }, isFrontmost: { true }).run())
        XCTAssertEqual(raises, 1)
    }

    func testBatchContinuesAfterFailureAndReportsPartialResult() {
        var attempted: [Int] = []
        XCTAssertThrowsError(try SafariWindowActivation.activateAll([3, 2, 1]) { target in
            attempted.append(target)
            if target == 2 { throw MiniToolsError.processingFailed("closed") }
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("2/3"))
            XCTAssertTrue(error.localizedDescription.contains("closed"))
        }
        XCTAssertEqual(attempted, [3, 2, 1])
    }

    func testBatchTransientRecoveryCompletesAllWindows() throws {
        var attempted: [Int] = []
        try SafariWindowActivation.activateAll([2, 1]) { target in
            var frontmost = false
            try SafariWindowActivation(isMinimized: { false }, restore: { .success }, raise: {
                attempted.append(target); frontmost = true; return .cannotComplete
            }, isFrontmost: { frontmost }).run()
        }
        XCTAssertEqual(attempted, [2, 1])
    }

    func testCancellationStopsRecoveryAndBatch() {
        XCTAssertThrowsError(try SafariWindowActivation(isMinimized: { true }, restore: {
            XCTFail("cancelled"); return .success
        }, raise: { .success }, isFrontmost: { false }, checkCancellation: { throw CancellationError() }).run())
        var attempted: [Int] = []
        XCTAssertThrowsError(try SafariWindowActivation.activateAll([1, 2]) { target in
            attempted.append(target); throw CancellationError()
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(attempted, [1])
    }
    @MainActor
    func testRecoveredSingleAndBatchActivationNotifyPanelToClose() async {
        for batch in [false, true] {
            let completed = expectation(description: "close panel after activation")
            let windows = [SafariWindowItem(id: "a", title: "a", wasActiveWindow: true, hasTabGroup: false)]
            let model = SafariWindowPanelViewModel(initialWindows: windows, client: .init(
                fetchWindows: { windows }, activateWindow: { _ in
                    try SafariWindowActivation(isMinimized: { false }, restore: { .success },
                        raise: { .cannotComplete }, isFrontmost: { true }).run()
                }, activateWindows: { ids in
                    try SafariWindowActivation.activateAll(ids) { _ in
                        try SafariWindowActivation(isMinimized: { false }, restore: { .success },
                            raise: { .cannotComplete }, isFrontmost: { true }).run()
                    }
                }, createWindow: {}))
            model.onWindowActivated = { completed.fulfill() }
            if batch { model.activateAllUngroupedWindows() } else { model.activateSelectedWindow() }
            await fulfillment(of: [completed], timeout: 1)
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.isActivating)
            model.endSession()
        }
    }

    @MainActor
    func testClosingPanelCancelsActivationWorker() async {
        let started = expectation(description: "worker started")
        let cancelled = expectation(description: "worker sees cancellation")
        let model = SafariWindowPanelViewModel(initialWindows: [
            .init(id: "a", title: "a", wasActiveWindow: true, hasTabGroup: false)
        ], client: .init(fetchWindows: { [] }, activateWindow: { _ in
            started.fulfill()
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while !Task.isCancelled && ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            if Task.isCancelled { cancelled.fulfill() }
            try Task.checkCancellation()
        }, activateWindows: { _ in }, createWindow: {}))
        model.onWindowActivated = { XCTFail("closed session must not publish success") }
        model.activateSelectedWindow()
        await fulfillment(of: [started], timeout: 1)
        model.endSession()
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertNil(model.errorMessage)
    }

}
