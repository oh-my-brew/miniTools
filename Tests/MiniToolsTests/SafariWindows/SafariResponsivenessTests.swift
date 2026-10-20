import Foundation
import XCTest
@testable import MiniTools

private final class SafariTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var identity = "original"
    func next() -> Int { lock.withLock { count += 1; return count } }
    func value() -> Int { lock.withLock { count } }
    func process() -> String { lock.withLock { identity } }
    func restart() { lock.withLock { identity = "restarted" } }
}

final class SafariResponsivenessTests: XCTestCase {
    private func window(_ id: String) -> SafariWindowItem {
        .init(id: id, title: id, wasActiveWindow: false, hasTabGroup: false)
    }

    @MainActor
    func testSlowRefreshRetainsSnapshotAndFreezesLetterMappingUntilNextOpen() async {
        let old = [window("a"), window("b")]
        let updated = [window("new"), window("a"), window("b")]
        let started = expectation(description: "refresh started")
        let release = DispatchSemaphore(value: 0)
        let state = SafariTestState()
        let model = SafariWindowPanelViewModel(initialWindows: old, client: .init(
            fetchWindows: {
                if state.next() == 1 { started.fulfill(); release.wait() }
                return updated
            }, activateWindow: { _ in }, activateWindows: { _ in }, createWindow: {}))
        model.beginSession()
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.windows, old)
        XCTAssertTrue(model.handleCommand(.moveSelection(1)))
        XCTAssertEqual(model.selectedWindowID, "b")
        release.signal()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.windows, old)
        XCTAssertEqual(model.selectedWindowID, "b")
        model.endSession()
        model.beginSession()
        XCTAssertEqual(model.windows, updated)
        model.endSession()
    }

    @MainActor
    func testRefreshFailureKeepsUsableSnapshot() async {
        let old = [window("a")]
        let model = SafariWindowPanelViewModel(initialWindows: old, client: .init(
            fetchWindows: { throw MiniToolsError.processingFailed("slow") },
            activateWindow: { _ in }, activateWindows: { _ in }, createWindow: {}))
        model.beginSession()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.windows, old)
        XCTAssertEqual(model.errorMessage, "slow")
        model.endSession()
    }

    @MainActor
    func testRestartInvalidatesCachedRowsAndPreventsActivatingOldProcess() async {
        let old = [window("a")]
        let state = SafariTestState()
        let model = SafariWindowPanelViewModel(client: .init(fetchWindows: { old },
            activateWindow: { _ in XCTFail("old process must not activate") },
            activateWindows: { _ in XCTFail("old process must not activate") }, createWindow: {},
            processIdentity: state.process))
        model.beginSession()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.windows, old)
        state.restart()
        model.activateSelectedWindow()
        XCTAssertTrue(model.windows.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        model.endSession()
        model.beginSession()
        XCTAssertTrue(model.windows.isEmpty) // No old rows shown during the next refresh.
        model.endSession()
    }

    func testWorkerCancelsQueuedScansAndDoesNotOverlapSlowCalls() async throws {
        let worker = SafariWindowScanWorker()
        let firstStarted = expectation(description: "first scan started")
        let release = DispatchSemaphore(value: 0)
        let state = SafariTestState()
        let old = [window("old")]
        let new = [window("new")]
        let first = Task {
            try await worker.fetch {
                firstStarted.fulfill()
                release.wait()
                return old
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)
        first.cancel()
        let second = Task { try await worker.fetch { _ = state.next(); return new } }
        // Even an uncooperative in-flight synchronous call must finish before the next begins.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(state.value(), 0)
        release.signal()
        let result = try await second.value
        _ = await first.result
        XCTAssertEqual(result, new)
        XCTAssertEqual(state.value(), 1)
    }

    @MainActor
    func testReopenDropsOldScanAndOnlyAppliesNewSession() async {
        let started = expectation(description: "old scan started")
        let release = DispatchSemaphore(value: 0)
        let state = SafariTestState()
        let stale = [window("stale")]
        let current = [window("current")]
        let model = SafariWindowPanelViewModel(client: .init(fetchWindows: {
            if state.next() == 1 { started.fulfill(); release.wait(); return stale }
            return current
        }, activateWindow: { _ in }, activateWindows: { _ in }, createWindow: {}))
        model.beginSession()
        await fulfillment(of: [started], timeout: 1)
        model.endSession()
        model.beginSession()
        release.signal()
        await waitUntil { !model.isLoading }
        XCTAssertEqual(model.windows, current)
        model.endSession()
    }

    func testCachedWebAreaPathAvoidsFullWalkAndInvalidPathFallsBack() throws {
        var nodes: [Int: SafariTreeNode<Int>] = [:]
        nodes[0] = .init(role: "AXWindow", title: nil, description: nil, children: Array(1...100))
        for i in 1...100 {
            nodes[i] = .init(role: i == 100 ? "AXWebArea" : "AXGroup",
                title: i == 100 ? "page" : nil, description: nil, children: [])
        }
        var reads = 0
        let read: (Int) throws -> SafariTreeNode<Int> = { id in
            reads += 1
            return try XCTUnwrap(nodes[id])
        }
        let first = try SafariWebAreaLocator.locate(root: 0, cachedPath: nil, read: read, check: {})
        XCTAssertEqual(first?.title, "page")
        XCTAssertEqual(reads, 101)
        reads = 0
        let cached = try SafariWebAreaLocator.locate(root: 0, cachedPath: first?.path, read: read, check: {})
        XCTAssertEqual(cached?.title, "page")
        XCTAssertEqual(reads, 2)
        let fallback = try SafariWebAreaLocator.locate(root: 0, cachedPath: [500], read: read, check: {})
        XCTAssertEqual(fallback?.title, "page")
    }

    func testBudgetAndCancellationStopTraversalWithoutAXAccess() {
        XCTAssertThrowsError(try SafariWindowScanBudget(timeout: .zero).check())
        var reads = 0
        XCTAssertThrowsError(try SafariWebAreaLocator.locate(root: 0, cachedPath: nil, read: { _ in
            reads += 1
            return SafariTreeNode<Int>(role: "AXGroup", title: nil, description: nil, children: [0])
        }, check: { throw CancellationError() }))
        XCTAssertEqual(reads, 0)
        XCTAssertNil(try SafariWebAreaLocator.locate(root: 0, cachedPath: nil, read: { _ in
            reads += 1
            return SafariTreeNode<Int>(role: "AXGroup", title: nil, description: nil, children: [0])
        }, check: {}))
        XCTAssertLessThanOrEqual(reads, 250)
    }

    func testPathCacheIsScopedToSafariLaunch() {
        let cache = SafariWindowPathCache()
        cache.replace(["a": .init(title: "page", path: [1, 2])], for: "pid:launch1")
        XCTAssertEqual(cache.snapshot(for: "pid:launch1")["a"]?.path, [1, 2])
        XCTAssertTrue(cache.snapshot(for: "pid:launch2").isEmpty)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out", file: file, line: line)
    }
}
