import Foundation
import XCTest
@testable import MiniTools

@MainActor
final class CapsInputSourceSwitcherTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let suite = "MiniToolsTests.CapsInputSourceSwitcher.\(UUID().uuidString)"
        let defaults: UserDefaults
        var current: String? = "doubao"
        var ascii: String? = "ABC"
        var selected: [String] = []
        var result: Result<FocusedInputSourceSelection.Route, FocusedInputSourceSelection.Failure>
            = .success(.focusedApplication)
        var onSelection: (() -> Void)?

        init() {
            defaults = UserDefaults(suiteName: suite)!
        }

        func switcher() -> CapsInputSourceSwitcher {
            CapsInputSourceSwitcher(defaults: defaults, client: .init(
                currentIdentifier: { self.current },
                asciiIdentifier: { self.ascii },
                select: { identifier, _ in
                    self.selected.append(identifier)
                    self.onSelection?()
                    return self.result
                }
            ))
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) rethrows {
        let fixture = Fixture()
        defer {
            fixture.onSelection = nil
            fixture.defaults.removePersistentDomain(forName: fixture.suite)
        }
        try body(fixture)
    }

    func testRemembersInputMethodAndSelectsExactTargetInBothDirections() throws {
        try withFixture { fixture in
            let switcher = fixture.switcher()
            let english = try switcher.toggle().get()
            XCTAssertEqual(english.previousIdentifier, "doubao")
            XCTAssertEqual(english.targetIdentifier, "ABC")
            XCTAssertEqual(english.route, .focusedApplication)
            fixture.current = "ABC"
            let chinese = try switcher.toggle().get()
            XCTAssertEqual(chinese.targetIdentifier, "doubao")
            XCTAssertEqual(fixture.selected, ["ABC", "doubao"])
        }
    }

    func testPreservesExistingRememberedIdentifierAcrossSwitcherInstances() throws {
        try withFixture { fixture in
            fixture.defaults.set("doubao", forKey: "capsLockPreviousInputSourceID")
            fixture.current = "ABC"
            let request = try fixture.switcher().toggle().get()
            XCTAssertEqual(request.targetIdentifier, "doubao")
        }
    }

    func testFailedSelectionDoesNotOverwriteRememberedInputMethod() {
        withFixture { fixture in
            fixture.defaults.set("savedIME", forKey: "capsLockPreviousInputSourceID")
            fixture.result = .failure(.deliveryFailed)
            XCTAssertEqual(fixture.switcher().toggle(), .failure(.selection(.deliveryFailed)))
            XCTAssertEqual(fixture.defaults.string(forKey: "capsLockPreviousInputSourceID"), "savedIME")
        }
    }

    func testMissingInputMethodAndUnreadableSourcesNeverSendRequests() {
        withFixture { fixture in
            fixture.current = "ABC"
            let switcher = fixture.switcher()
            XCTAssertEqual(switcher.toggle(), .failure(.noPreviousSource))
            fixture.current = nil
            XCTAssertEqual(switcher.toggle(), .failure(.unreadable))
            fixture.current = "doubao"
            fixture.ascii = nil
            XCTAssertEqual(switcher.toggle(), .failure(.unreadable))
            XCTAssertTrue(fixture.selected.isEmpty)
        }
    }

    func testRememberCurrentNeverReplacesInputMethodWithASCIILayout() throws {
        try withFixture { fixture in
            let switcher = fixture.switcher()
            switcher.rememberCurrent()
            fixture.current = "ABC"
            switcher.rememberCurrent()
            XCTAssertEqual(try switcher.toggle().get().targetIdentifier, "doubao")
        }
    }

    func testReentrantSelectionCannotStartAnotherRequest() throws {
        try withFixture { fixture in
            let switcher = fixture.switcher()
            fixture.onSelection = {
                XCTAssertEqual(switcher.toggle(), .failure(.busy))
            }
            _ = try switcher.toggle().get()
            XCTAssertEqual(fixture.selected, ["ABC"])
        }
    }

    func testCancelledReplyCannotPersistOrReportSuccessAndNextRequestCanRun() throws {
        try withFixture { fixture in
            let switcher = fixture.switcher()
            fixture.defaults.set("savedIME", forKey: "capsLockPreviousInputSourceID")
            fixture.onSelection = switcher.cancel
            XCTAssertEqual(switcher.toggle(), .failure(.selection(.cancelled)))
            XCTAssertEqual(fixture.defaults.string(forKey: "capsLockPreviousInputSourceID"), "savedIME")
            fixture.onSelection = nil
            XCTAssertEqual(try switcher.toggle().get().targetIdentifier, "ABC")
        }
    }

    func testReplyTimeoutIsPendingAndOtherInputSourcesAreNotReportedAsTarget() throws {
        try withFixture { fixture in
            fixture.defaults.set("doubao", forKey: "capsLockPreviousInputSourceID")
            fixture.current = "ABC"
            fixture.result = .success(.focusedApplicationAwaitingReply)
            let request = try fixture.switcher().toggle().get()
            XCTAssertTrue(request.pendingStatus.contains("响应超时"))
            XCTAssertTrue(request.confirmationStatus(observed: "ABC").contains("当前仍是 ABC"))
            let other = request.confirmationStatus(observed: "anotherIME")
            XCTAssertTrue(other.contains("目标为 doubao"))
            XCTAssertTrue(other.contains("其他输入源 anotherIME"))
            XCTAssertFalse(other.contains("已确认目标"))
            let delayed = request.confirmationStatus(observed: "doubao")
            XCTAssertTrue(delayed.contains("已确认目标输入源 doubao"))
            XCTAssertTrue(delayed.contains("中文输入就绪仍无法确认"))
            XCTAssertTrue(request.confirmationStatus(observed: nil).contains("无法读取"))
        }
    }
}
