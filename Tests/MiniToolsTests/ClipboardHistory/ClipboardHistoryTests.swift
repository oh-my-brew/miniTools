import AppKit
import XCTest
@testable import MiniTools

final class ClipboardHistoryTests: XCTestCase {
    func testCapturesRichTextAndPreservesPlainTextAlternative() throws {
        let pasteboard = NSPasteboard(name: .init("ClipboardHistoryTests.\(UUID())"))
        pasteboard.clearContents()
        let attributed = NSAttributedString(
            string: "Hello rich text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        let rtf = try XCTUnwrap(
            attributed.rtf(from: NSRange(location: 0, length: attributed.length))
        )
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("Hello rich text", forType: .string)
        pasteboardItem.setData(rtf, forType: .rtf)
        XCTAssertTrue(pasteboard.writeObjects([pasteboardItem]))

        let capture = try XCTUnwrap(
            ClipboardHistoryCaptureService.capture(
                from: pasteboard,
                sourceApplication: nil,
                now: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(capture.item.kind, .richText)
        XCTAssertEqual(capture.item.plainText, "Hello rich text")
        XCTAssertTrue(capture.payloads.contains { $0.typeIdentifier == NSPasteboard.PasteboardType.rtf.rawValue })
        XCTAssertTrue(capture.payloads.contains { $0.typeIdentifier == NSPasteboard.PasteboardType.string.rawValue })
    }

    func testSkipsTransientAndMiniToolsGeneratedContent() {
        for ignoredType in [
            NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
            ClipboardHistoryCaptureService.markerType
        ] {
            let pasteboard = NSPasteboard(name: .init("ClipboardHistoryTests.\(UUID())"))
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString("secret", forType: .string)
            item.setString("1", forType: ignoredType)
            XCTAssertTrue(pasteboard.writeObjects([item]))
            XCTAssertNil(
                ClipboardHistoryCaptureService.capture(
                    from: pasteboard,
                    sourceApplication: nil
                )
            )
        }
    }

    @MainActor
    func testPlainTextWritingDropsRichRepresentation() throws {
        let source = NSPasteboard(name: .init("ClipboardHistoryTests.source.\(UUID())"))
        source.clearContents()
        let sourceItem = NSPasteboardItem()
        sourceItem.setString("Plain", forType: .string)
        sourceItem.setData(Data("{\\rtf1 Rich}".utf8), forType: .rtf)
        XCTAssertTrue(source.writeObjects([sourceItem]))
        let capture = try XCTUnwrap(
            ClipboardHistoryCaptureService.capture(from: source, sourceApplication: nil)
        )

        let destination = NSPasteboard(name: .init("ClipboardHistoryTests.destination.\(UUID())"))
        try ClipboardHistoryPasteService.write(
            item: capture.item,
            payloads: capture.payloads,
            plainTextOnly: true,
            to: destination
        )

        XCTAssertEqual(destination.string(forType: .string), "Plain")
        XCTAssertNil(destination.data(forType: .rtf))
        XCTAssertNotNil(destination.string(forType: ClipboardHistoryCaptureService.markerType))
    }

    func testStorePersistsPayloadAndPrunesExpiredItems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryTests.\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardHistoryStore(rootURL: root)
        let oldCapture = makeCapture(text: "old", date: Date(timeIntervalSince1970: 0))
        let recentCapture = makeCapture(text: "recent", date: Date(timeIntervalSince1970: 100_000))
        _ = try await store.save(oldCapture)
        _ = try await store.save(recentCapture)

        let items = try await store.loadItems(
            retention: .oneDay,
            now: Date(timeIntervalSince1970: 100_001)
        )

        XCTAssertEqual(items.map(\.plainText), ["recent"])
        let payloads = try await store.payloads(for: try XCTUnwrap(items.first))
        XCTAssertEqual(payloads.first?.data, Data("recent".utf8))
    }

    func testSearchMatchesContentAndSourceApplication() {
        var capture = makeCapture(text: "deployment notes", date: Date())
        capture.item.sourceApplicationName = "Safari"
        capture.item.searchableText += "\nSafari"
        XCTAssertTrue(
            ClipboardHistoryViewModel.matches(capture.item, query: "safari deploy")
        )
        XCTAssertFalse(
            ClipboardHistoryViewModel.matches(capture.item, query: "safari missing")
        )
    }

    private func makeCapture(text: String, date: Date) -> ClipboardHistoryCapture {
        let id = UUID()
        let representation = ClipboardHistoryRepresentation(
            itemIndex: 0,
            typeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
            fileName: "payload-0.bin"
        )
        let item = ClipboardHistoryItem(
            id: id,
            copiedAt: date,
            sourceBundleIdentifier: nil,
            sourceApplicationName: nil,
            kind: .text,
            summary: text,
            searchableText: text,
            plainText: text,
            contentHash: id.uuidString,
            pixelWidth: nil,
            pixelHeight: nil,
            thumbnailFileName: nil,
            representations: [representation]
        )
        return ClipboardHistoryCapture(
            item: item,
            payloads: [
                ClipboardHistoryCapturedRepresentation(
                    itemIndex: 0,
                    typeIdentifier: representation.typeIdentifier,
                    data: Data(text.utf8)
                )
            ],
            thumbnailData: nil
        )
    }
}
