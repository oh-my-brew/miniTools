import AppKit
import Carbon
import XCTest
@testable import MiniTools

final class SafariWindowServiceTests: XCTestCase {
    func testUsesTabGroupNameWhenWindowTitleContainsCurrentTabSuffix() {
        XCTAssertEqual(
            SafariWindowService.displayTitle(
                windowTitle: "开发资料 — Swift Documentation",
                tabTitle: "Swift Documentation"
            ),
            "开发资料"
        )
    }

    func testFallsBackToActiveTabTitleWithoutTabGroup() {
        XCTAssertEqual(
            SafariWindowService.displayTitle(
                windowTitle: "Swift Documentation",
                tabTitle: "Swift Documentation"
            ),
            "Swift Documentation"
        )
    }

    func testBuildsSortsAndPreservesFrontmostWindow() throws {
        let records = [
            SafariAXWindowRecord(id: "84", windowTitle: "Zeta", tabTitle: "Zeta", wasActiveWindow: true),
            SafariAXWindowRecord(id: "81", windowTitle: "工作 — Alpha", tabTitle: "Alpha", wasActiveWindow: false),
            SafariAXWindowRecord(id: "82", windowTitle: "Beta", tabTitle: "Beta", wasActiveWindow: false)
        ]

        let windows = SafariWindowService.makeWindowItems(from: records)
        XCTAssertEqual(Set(windows.map(\.title)), Set(["Beta", "Zeta", "工作"]))
        XCTAssertTrue(zip(windows, windows.dropFirst()).allSatisfy { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) != .orderedDescending
        })
        XCTAssertEqual(windows.first(where: \.wasActiveWindow)?.id, "84")
        XCTAssertEqual(windows.first(where: { $0.id == "81" })?.hasTabGroup, true)
        XCTAssertEqual(windows.first(where: { $0.id == "82" })?.hasTabGroup, false)
    }

    func testSafariPanelLayoutUsesOneColumnAndNeverExceedsAvailableSize() {
        let available = CGSize(width: 1200, height: 800)
        let layout = SafariPanelLayout.calculate(windowCount: 50, availableSize: available)

        XCTAssertEqual(layout.contentSize.width, FeaturePanelMetrics.preferredWidth)
        XCTAssertLessThanOrEqual(layout.contentSize.width, available.width)
        XCTAssertLessThanOrEqual(layout.contentSize.height, available.height)
        XCTAssertGreaterThan(layout.rowHeight, 0)
        XCTAssertGreaterThanOrEqual(layout.rowSpacing, 0)
    }

    @MainActor
    func testSafariPanelSelectionKeysOpenWindowImmediately() async {
        let windows = [
            SafariWindowItem(id: "1", title: "Alpha", wasActiveWindow: false, hasTabGroup: false),
            SafariWindowItem(id: "2", title: "Beta", wasActiveWindow: true, hasTabGroup: true),
            SafariWindowItem(id: "3", title: "Gamma", wasActiveWindow: false, hasTabGroup: false)
        ]
        let activated = expectation(description: "直接打开字母键对应的 Safari 窗口")
        let viewModel = SafariWindowPanelViewModel(
            initialWindows: windows,
            client: SafariWindowClient(
                fetchWindows: { windows },
                activateWindow: { id in
                    XCTAssertEqual(id, "1")
                    activated.fulfill()
                },
                activateWindows: { _ in },
                createWindow: {}
            )
        )

        XCTAssertEqual(SafariWindowPanelViewModel.selectionKeys.joined(), "asdfqwerzxcvtgbyhuiopl")
        XCTAssertFalse(SafariWindowPanelViewModel.selectionKeys.contains("n"))
        XCTAssertEqual(viewModel.selectedWindowID, "2")
        XCTAssertTrue(viewModel.handleSelectionKey("a"))
        XCTAssertEqual(viewModel.selectedWindowID, "1")
        await fulfillment(of: [activated], timeout: 1)
        XCTAssertTrue(viewModel.handleSelectionKey("j"))
        XCTAssertEqual(viewModel.selectedWindowID, "2")
        XCTAssertTrue(viewModel.handleSelectionKey("k"))
        XCTAssertEqual(viewModel.selectedWindowID, "1")
        XCTAssertFalse(viewModel.handleSelectionKey("1"))
    }

    @MainActor
    func testArrowKeysMoveSafariWindowSelection() throws {
        let windows = [
            SafariWindowItem(id: "1", title: "Alpha", wasActiveWindow: true, hasTabGroup: false),
            SafariWindowItem(id: "2", title: "Beta", wasActiveWindow: false, hasTabGroup: false),
            SafariWindowItem(id: "3", title: "Gamma", wasActiveWindow: false, hasTabGroup: false)
        ]
        let viewModel = SafariWindowPanelViewModel(
            initialWindows: windows,
            client: SafariWindowClient(
                fetchWindows: { windows },
                activateWindow: { _ in },
                activateWindows: { _ in },
                createWindow: {}
            )
        )

        XCTAssertTrue(viewModel.handleCommand(.moveSelection(1)))
        XCTAssertEqual(viewModel.selectedWindowID, "2")
        XCTAssertTrue(viewModel.handleCommand(.moveSelection(-1)))
        XCTAssertEqual(viewModel.selectedWindowID, "1")
    }

    @MainActor
    func testSpaceNoLongerOpensWindowAndEnterStillDoes() async throws {
        let windows = [
            SafariWindowItem(id: "1", title: "Alpha", wasActiveWindow: true, hasTabGroup: false)
        ]
        let activated = expectation(description: "回车打开当前 Safari 窗口")
        let viewModel = SafariWindowPanelViewModel(
            initialWindows: windows,
            client: SafariWindowClient(
                fetchWindows: { windows },
                activateWindow: { _ in activated.fulfill() },
                activateWindows: { _ in },
                createWindow: {}
            )
        )

        XCTAssertNil(FeaturePanelCommandRouter.command(for: try keyEvent(keyCode: kVK_Space)))
        XCTAssertTrue(viewModel.handleCommand(.execute))
        await fulfillment(of: [activated], timeout: 1)
    }

    @MainActor
    func testMOpensEverySafariWindowWithoutATabGroup() async {
        let windows = [
            SafariWindowItem(id: "1", title: "Alpha", wasActiveWindow: true, hasTabGroup: false),
            SafariWindowItem(id: "2", title: "Work", wasActiveWindow: false, hasTabGroup: true),
            SafariWindowItem(id: "3", title: "Gamma", wasActiveWindow: false, hasTabGroup: false)
        ]
        let activated = expectation(description: "打开全部未分组 Safari 窗口")
        let viewModel = SafariWindowPanelViewModel(
            initialWindows: windows,
            client: SafariWindowClient(
                fetchWindows: { windows },
                activateWindow: { _ in },
                activateWindows: { ids in
                    XCTAssertEqual(ids, ["1", "3"])
                    activated.fulfill()
                },
                createWindow: {}
            )
        )

        XCTAssertTrue(viewModel.handleSelectionKey("m"))
        await fulfillment(of: [activated], timeout: 1)
    }

    @MainActor
    func testNCreatesNewSafariWindow() async {
        let created = expectation(description: "新建 Safari 窗口")
        let viewModel = SafariWindowPanelViewModel(
            initialWindows: [
                SafariWindowItem(
                    id: "1",
                    title: "Alpha",
                    wasActiveWindow: true,
                    hasTabGroup: false
                )
            ],
            client: SafariWindowClient(
                fetchWindows: { [] },
                activateWindow: { _ in },
                activateWindows: { _ in },
                createWindow: {
                    created.fulfill()
                }
            )
        )

        XCTAssertTrue(viewModel.handleSelectionKey("n"))
        await fulfillment(of: [created], timeout: 1)
    }

    @MainActor
    func testCompletedLoadFromClosedSessionDoesNotReplaceWindows() async {
        let viewModel = SafariWindowPanelViewModel(
            client: SafariWindowClient(
                fetchWindows: {
                    Thread.sleep(forTimeInterval: 0.05)
                    return [SafariWindowItem(
                        id: "stale",
                        title: "Stale",
                        wasActiveWindow: false,
                        hasTabGroup: false
                    )]
                },
                activateWindow: { _ in },
                activateWindows: { _ in },
                createWindow: {}
            )
        )

        viewModel.beginSession()
        viewModel.endSession()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(viewModel.windows.isEmpty)
    }

    private func keyEvent(keyCode: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }
}
