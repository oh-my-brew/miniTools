import CoreFoundation
import XCTest
@testable import MiniTools

@MainActor
final class FocusedInputSourceSelectionTests: XCTestCase {
    func testOnlyReceiveTimeoutMeansTheRequestMayStillBeExecuting() {
        switch FocusedInputSourceTransport.delivery(for: kCFMessagePortReceiveTimeout) {
        case .awaitingReply: break
        default: XCTFail("A receive timeout does not mean delivery failed")
        }
        for status in [
            kCFMessagePortSendTimeout, kCFMessagePortIsInvalid,
            kCFMessagePortTransportError, kCFMessagePortBecameInvalidError
        ] {
            switch FocusedInputSourceTransport.delivery(for: status) {
            case .failed: break
            default: XCTFail("Unexpected status mapping for \(status)")
            }
        }
    }

    func testSelectsInKeyboardFocusProcessWithoutLocalSelection() {
        var delivered: [Int32] = []
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { 42 }, isCurrent: { true },
            deliver: { delivered.append($0); return .replied },
            selectLocally: { XCTFail("Must select inside the focus process"); return false }
        )
        XCTAssertEqual(result, .success(.focusedApplication))
        XCTAssertEqual(delivered, [42])
    }

    func testColdInputContextMayReplyLaterWithoutDuplicateSelection() {
        var sends = 0
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { 42 }, isCurrent: { true },
            deliver: { _ in sends += 1; return .awaitingReply },
            selectLocally: { XCTFail("A late reply must not cause another selection"); return true }
        )
        XCTAssertEqual(result, .success(.focusedApplicationAwaitingReply))
        XCTAssertEqual(sends, 1)
    }

    func testUnavailableCapabilityFallsBackOnceWithStableFocus() {
        var localCalls = 0
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { 42 }, isCurrent: { true },
            deliver: { _ in .unavailable },
            selectLocally: { localCalls += 1; return true }
        )
        XCTAssertEqual(result, .success(.local))
        XCTAssertEqual(localCalls, 1)
    }

    func testOwnProcessAndUnknownFocusUseLocalSelection() {
        for focus: Int32? in [10, nil] {
            let result = FocusedInputSourceSelection.select(
                currentProcess: 10, focusedProcess: { focus }, isCurrent: { true },
                deliver: { _ in XCTFail("No other focus process"); return .failed },
                selectLocally: { true }
            )
            XCTAssertEqual(result, .success(.local))
        }
    }

    func testDeliveryFailureDoesNotSendAnotherSelection() {
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { 42 }, isCurrent: { true },
            deliver: { _ in .failed },
            selectLocally: { XCTFail("Do not retry an attempted delivery"); return true }
        )
        XCTAssertEqual(result, .failure(.deliveryFailed))
    }

    func testFocusChangeDuringPreparationStopsBeforeDelivery() {
        var reads = 0
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10,
            focusedProcess: { reads += 1; return reads == 1 ? 42 : 43 },
            isCurrent: { true },
            deliver: { _ in XCTFail("Focus already changed"); return .replied },
            selectLocally: { XCTFail("Do not switch in the new application"); return true }
        )
        XCTAssertEqual(result, .failure(.focusChanged))
    }

    func testFocusChangeDuringDeliveryStopsFallbackAndConfirmation() {
        for delivery: FocusedInputSourceSelection.Delivery in [.unavailable, .replied, .awaitingReply] {
            var focus: Int32 = 42
            let result = FocusedInputSourceSelection.select(
                currentProcess: 10, focusedProcess: { focus }, isCurrent: { true },
                deliver: { _ in focus = 43; return delivery },
                selectLocally: { XCTFail("Focus changed"); return true }
            )
            XCTAssertEqual(result, .failure(.focusChanged))
        }
    }

    func testCancellationBeforeSelectionDoesNotReadFocusOrSend() {
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10,
            focusedProcess: { XCTFail("Already cancelled"); return 42 },
            isCurrent: { false },
            deliver: { _ in XCTFail("Already cancelled"); return .replied },
            selectLocally: { XCTFail("Already cancelled"); return true }
        )
        XCTAssertEqual(result, .failure(.cancelled))
    }

    func testCancellationDuringReplyRunLoopPreventsFallback() {
        var current = true
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { 42 }, isCurrent: { current },
            deliver: { _ in current = false; return .unavailable },
            selectLocally: { XCTFail("Rule was disabled during the reply"); return true }
        )
        XCTAssertEqual(result, .failure(.cancelled))
    }

    func testCancellationDuringFocusQueryStopsBeforeDelivery() {
        var current = true
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { current = false; return 42 },
            isCurrent: { current },
            deliver: { _ in XCTFail("Cancelled while querying focus"); return .replied },
            selectLocally: { XCTFail("Cancelled while querying focus"); return true }
        )
        XCTAssertEqual(result, .failure(.cancelled))
    }

    func testLocalFailureIsReported() {
        let result = FocusedInputSourceSelection.select(
            currentProcess: 10, focusedProcess: { nil }, isCurrent: { true },
            deliver: { _ in XCTFail("No focus process"); return .unavailable },
            selectLocally: { false }
        )
        XCTAssertEqual(result, .failure(.localSelectionFailed))
    }
}
