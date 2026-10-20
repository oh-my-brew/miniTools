import AppKit
import XCTest
@testable import MiniTools

final class ClipboardHistoryBrowsingTests: XCTestCase {
    func testResumeTimeoutAndUseAreIndependentOfRepeatedClose() {
        let ids = (0..<4).map { _ in UUID() }
        let date = Date(timeIntervalSince1970: 1000)
        var state = ClipboardHistoryBrowsingState()
        XCTAssertFalse(state.open(at: date))
        state.close(at: date, ids: ids, selectedID: ids[2], offset: 503, stride: 250)
        // A redundant window-close notification must not extend the five-minute window.
        state.close(at: date.addingTimeInterval(200), ids: ids, selectedID: ids[0], offset: 0, stride: 250)
        XCTAssertTrue(state.open(at: date.addingTimeInterval(300)))
        XCTAssertEqual(state.restoredSelection(in: ids), ids[2])
        state.didUseItem()
        state.close(at: date.addingTimeInterval(300), ids: ids, selectedID: ids[2], offset: 503, stride: 250)
        XCTAssertFalse(state.open(at: date.addingTimeInterval(301)))
        state.close(at: date.addingTimeInterval(301), ids: ids, selectedID: ids[2], offset: 503, stride: 250)
        XCTAssertFalse(state.open(at: date.addingTimeInterval(602)))
    }

    func testAnchorSurvivesNewCardsAndFallsBackNearDeletedCards() throws {
        let ids = (0..<5).map { _ in UUID() }
        let anchor = try XCTUnwrap(ClipboardHistoryBrowsingState.Anchor(ids: ids, offset: 513, stride: 250))
        XCTAssertEqual(anchor.offset(in: [UUID()] + ids, stride: 250), 763)
        XCTAssertEqual(anchor.offset(in: [ids[0], ids[1], ids[3], ids[4]], stride: 250), 513)
        XCTAssertEqual(anchor.offset(in: [], stride: 250), 0)
        XCTAssertEqual(ClipboardHistoryBrowsingState.Anchor.nearest(
            to: ids[4], oldOrder: ids, surviving: Array(ids.prefix(3))), ids[2])
    }

    func testKeyboardOnlyScrollsEnoughToRevealCard() {
        func offset(_ index: Int, current: CGFloat = 250) -> CGFloat {
            ClipboardHistoryBrowsingState.visibleOffset(index: index, current: current,
                viewport: 750, cardWidth: 236, stride: 250, leadingInset: 2)
        }
        XCTAssertEqual(offset(2), 250) // Already fully visible; do not center it.
        XCTAssertEqual(offset(4), 490)
        XCTAssertEqual(offset(0), 0)
    }

    @MainActor
    func testReopenRestoresQuerySelectionAndAnchorUntilUsedOrExpired() async throws {
        try await withModel { model, captures, advance in
            model.present()
            model.query = "match"
            model.select(captures[2].item.id)
            model.updateViewport(CGRect(x: 503, y: 0, width: 500, height: 240))
            model.dismiss()
            advance(60)
            await model.record(self.capture("match new", date: 20))
            model.present()
            XCTAssertEqual(model.query, "match")
            XCTAssertEqual(model.selectedID, captures[2].item.id)
            XCTAssertEqual(model.scrollRequest.offset, 753)
            model.dismiss()
            advance(301)
            model.present()
            XCTAssertEqual(model.query, "")
            XCTAssertEqual(model.selectedID, model.items.first?.id)
            XCTAssertEqual(model.scrollRequest.offset, 0)

            model.select(captures[3].item.id)
            let sequence = model.scrollRequest.sequence
            model.didUseItem() // Called only after a successful pasteboard write.
            await model.promoteUsedItem(captures[3].item)
            XCTAssertEqual(model.items.first?.id, captures[3].item.id)
            XCTAssertEqual(model.scrollRequest.sequence, sequence) // No scroll before closing.
            model.dismiss()
            advance(1)
            model.present()
            XCTAssertEqual(model.selectedID, captures[3].item.id)
            XCTAssertEqual(model.query, "")
            XCTAssertEqual(model.scrollRequest.offset, 0)
        }
    }

    @MainActor
    func testSearchAlwaysStartsAtFirstResultEvenWhenSelectionIDDoesNotChange() async throws {
        try await withModel { model, _, _ in
            model.present()
            model.updateViewport(CGRect(x: 510, y: 0, width: 500, height: 240))
            let selected = model.selectedID
            model.query = "match"
            XCTAssertEqual(model.selectedID, selected)
            XCTAssertEqual(model.scrollRequest.offset, 0)
            model.query = "不存在"
            XCTAssertNil(model.selectedID)
            model.clearSearch()
            XCTAssertEqual(model.selectedID, model.items.first?.id)
            XCTAssertEqual(model.scrollRequest.offset, 0)
        }
    }

    @MainActor
    func testCaptureDoesNotInterruptBrowsingSearchOrPreviewAndDeletionStaysNearby() async throws {
        try await withModel { model, captures, _ in
            model.present()
            model.select(captures[3].item.id)
            model.updateViewport(CGRect(x: 503, y: 0, width: 500, height: 240))
            await model.record(self.capture("new", date: 20))
            XCTAssertEqual(model.selectedID, captures[3].item.id)
            XCTAssertEqual(model.scrollRequest.offset, 753)
            model.query = "match"
            model.select(captures[2].item.id)
            await model.record(self.capture("match another", date: 21))
            XCTAssertEqual(model.selectedID, captures[2].item.id)
            model.clearSearch()
            model.select(captures[1].item.id)
            model.updateViewport(CGRect(x: 0, y: 0, width: 1000, height: 240))
            model.setPreviewVisible(true)
            await model.record(self.capture("preview guard", date: 22))
            XCTAssertEqual(model.selectedID, captures[1].item.id)
            model.setPreviewVisible(false)
            await model.deleteSelectedItem()
            XCTAssertEqual(model.selectedID, captures[2].item.id)
            model.updateViewport(CGRect(x: 0, y: 0, width: 1000, height: 240))
            await model.record(self.capture("follow latest", date: 23))
            XCTAssertEqual(model.selectedID, model.items.first?.id)
            XCTAssertEqual(model.scrollRequest.offset, 0)
        }
    }

    @MainActor
    func testFailedOperationDoesNotInvalidateResume() async throws {
        try await withModel { model, captures, advance in
            model.present()
            model.select(captures[2].item.id)
            model.updateViewport(CGRect(x: 510, y: 0, width: 500, height: 240))
            let sequence = model.scrollRequest.sequence
            XCTAssertNotNil(model.visibleItem(number: 1))
            XCTAssertEqual(model.selectedID, captures[2].item.id)
            XCTAssertEqual(model.scrollRequest.sequence, sequence)
            model.showMessage("写入失败") // Failure paths do not call didUseItem.
            model.dismiss()
            advance(1)
            model.present()
            XCTAssertEqual(model.selectedID, captures[2].item.id)
            XCTAssertEqual(model.scrollRequest.offset, 510)
        }
    }

    @MainActor
    private func withModel(_ body: @MainActor (ClipboardHistoryViewModel, [ClipboardHistoryCapture], @MainActor (TimeInterval) -> Void) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BrowseTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardHistoryStore(rootURL: root)
        let captures = (0..<6).map { capture("match \($0)", date: Double(10 - $0)) }
        for capture in captures { _ = try await store.save(capture) }
        var date = Date(timeIntervalSince1970: 1000)
        let model = ClipboardHistoryViewModel(store: store, retention: .forever, now: { date })
        await model.reload()
        try await body(model, captures, { date = date.addingTimeInterval($0) })
    }

    private func capture(_ text: String, date: Double) -> ClipboardHistoryCapture {
        let id = UUID()
        let representation = ClipboardHistoryRepresentation(itemIndex: 0,
            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue, fileName: "payload.bin")
        return ClipboardHistoryCapture(item: ClipboardHistoryItem(id: id,
            copiedAt: Date(timeIntervalSince1970: date), sourceBundleIdentifier: nil,
            sourceApplicationName: nil, kind: .text, summary: text, searchableText: text,
            plainText: text, contentHash: id.uuidString, pixelWidth: nil, pixelHeight: nil,
            thumbnailFileName: nil, representations: [representation]),
            payloads: [.init(itemIndex: 0, typeIdentifier: representation.typeIdentifier, data: Data(text.utf8))],
            thumbnailData: nil)
    }
}
