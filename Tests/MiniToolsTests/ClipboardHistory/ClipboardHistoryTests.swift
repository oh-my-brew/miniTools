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

    func testPromotingUsedItemMovesItToFrontWithoutChangingPayload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryTests.\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardHistoryStore(rootURL: root)
        let first = try await store.save(
            makeCapture(text: "first", date: Date(timeIntervalSince1970: 100))
        )
        _ = try await store.save(
            makeCapture(text: "second", date: Date(timeIntervalSince1970: 200))
        )

        _ = try await store.promote(first, at: Date(timeIntervalSince1970: 300))
        let items = try await store.loadItems(retention: .forever)

        XCTAssertEqual(items.map(\.plainText), ["first", "second"])
        let payloads = try await store.payloads(for: try XCTUnwrap(items.first))
        XCTAssertEqual(payloads.first?.data, Data("first".utf8))
    }

    func testStoreRecoversFileURLsForCardPresentation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryTests.\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardHistoryStore(rootURL: root)
        let fileURL = URL(fileURLWithPath: "/Users/test/Documents/example.txt")
        let representation = ClipboardHistoryRepresentation(
            itemIndex: 0,
            typeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue,
            fileName: "payload-0.bin"
        )
        let item = ClipboardHistoryItem(
            id: UUID(),
            copiedAt: Date(),
            sourceBundleIdentifier: "com.apple.finder",
            sourceApplicationName: "Finder",
            kind: .files,
            summary: fileURL.lastPathComponent,
            searchableText: fileURL.path,
            plainText: nil,
            contentHash: UUID().uuidString,
            pixelWidth: nil,
            pixelHeight: nil,
            thumbnailFileName: nil,
            representations: [representation]
        )
        let capture = ClipboardHistoryCapture(
            item: item,
            payloads: [
                ClipboardHistoryCapturedRepresentation(
                    itemIndex: 0,
                    typeIdentifier: representation.typeIdentifier,
                    data: Data(fileURL.absoluteString.utf8)
                )
            ],
            thumbnailData: nil
        )
        let saved = try await store.save(capture)
        let storedFileURLs = try await store.fileURLs(for: saved)

        XCTAssertEqual(storedFileURLs, [fileURL])
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

    func testRelativeTimeUsesCoarseUnits() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertEqual(
            ClipboardHistoryRelativeTimeFormatter.string(
                from: now.addingTimeInterval(-42),
                relativeTo: now
            ),
            "刚刚"
        )
        XCTAssertEqual(
            ClipboardHistoryRelativeTimeFormatter.string(
                from: now.addingTimeInterval(-12 * 60),
                relativeTo: now
            ),
            "12 分钟前"
        )
        XCTAssertEqual(
            ClipboardHistoryRelativeTimeFormatter.string(
                from: now.addingTimeInterval(-3 * 3_600),
                relativeTo: now
            ),
            "3 小时前"
        )
    }

    func testLinkPresentationUsesLocalURLMetadata() throws {
        let presentation = try XCTUnwrap(
            ClipboardHistoryLinkPresentation(
                text: "https://github.com/nfzerox/VirtualMacOniPad?tab=readme"
            )
        )
        XCTAssertEqual(presentation.host, "github.com")
        XCTAssertEqual(presentation.title, "VirtualMacOniPad")
        XCTAssertEqual(presentation.displayURL, "github.com/nfzerox/VirtualMacOniPad")
    }

    func testPreviewFrameAnchorsToCardAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let centered = ClipboardHistoryPreviewLayout.frame(
            size: CGSize(width: 440, height: 320),
            anchorX: 500,
            panelTop: 250,
            screenFrame: screen
        )
        XCTAssertEqual(centered.midX, 500)
        XCTAssertEqual(centered.minY, 262)

        let clamped = ClipboardHistoryPreviewLayout.frame(
            size: CGSize(width: 440, height: 320),
            anchorX: 980,
            panelTop: 500,
            screenFrame: screen
        )
        XCTAssertEqual(clamped.maxX, 982)
        XCTAssertEqual(clamped.maxY, 682)
    }

    func testTextPreviewGrowsForLongContent() {
        let short = makeCapture(text: "short", date: Date()).item
        let long = makeCapture(text: String(repeating: "long text ", count: 40), date: Date()).item
        let shortSize = ClipboardHistoryPreviewLayout.size(for: short)
        let longSize = ClipboardHistoryPreviewLayout.size(for: long)

        XCTAssertGreaterThan(longSize.width, shortSize.width)
        XCTAssertGreaterThan(longSize.height, shortSize.height)
    }

    func testColorPresentationMatchesPasteStyleMetadata() throws {
        let presentation = try XCTUnwrap(ClipboardHistoryColorPresentation(text: "#125566"))

        XCTAssertEqual(presentation.hex, "#125566")
        XCTAssertEqual(presentation.rgbDescription, "RGB 18, 85, 102")
        XCTAssertEqual(presentation.hslDescription, "HSL 192, 82, 24")
        XCTAssertEqual(presentation.hsbDescription, "HSB 192, 82, 40")
        XCTAssertEqual(presentation.foregroundColor, .white)
    }

    func testTextMetricsUseSystemWordBoundariesAndLineCount() {
        let metrics = ClipboardHistoryTextMetrics(text: "hello world\n中文测试")

        XCTAssertEqual(metrics.characters, 16)
        XCTAssertEqual(metrics.words, 4)
        XCTAssertEqual(metrics.lines, 2)
        XCTAssertEqual(metrics.description, "16 个字符  ·  4 单词  ·  2 行")
    }

    func testIconPaletteUsesDominantSaturatedColorAndMonochromeFallback() {
        let orange = ClipboardHistoryIconPalette.representativeColor(
            samples: Array(
                repeating: .init(red: 1, green: 0.45, blue: 0.05, alpha: 1),
                count: 24
            ) + Array(
                repeating: .init(red: 1, green: 1, blue: 1, alpha: 1),
                count: 8
            )
        )
        XCTAssertGreaterThan(orange.red, orange.green)
        XCTAssertGreaterThan(orange.green, orange.blue)

        let monochrome = ClipboardHistoryIconPalette.representativeColor(
            samples: Array(
                repeating: .init(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
                count: 24
            )
        )
        XCTAssertEqual(monochrome, ClipboardHistoryIconPalette.monochromeFallback)
    }

    func testHorizontalScrollUsesVerticalDeltaAndClampsWithoutElasticOverscroll() {
        XCTAssertEqual(
            ClipboardHistoryHorizontalScrollBehavior.targetOffset(
                current: 240,
                delta: -80,
                contentWidth: 1_200,
                viewportWidth: 600
            ),
            320
        )
        XCTAssertEqual(
            ClipboardHistoryHorizontalScrollBehavior.targetOffset(
                current: 20,
                delta: 100,
                contentWidth: 1_200,
                viewportWidth: 600
            ),
            0
        )
        XCTAssertEqual(
            ClipboardHistoryHorizontalScrollBehavior.targetOffset(
                current: 580,
                delta: -100,
                contentWidth: 1_200,
                viewportWidth: 600
            ),
            600
        )
    }

    func testFirstComposedTextKeyExpandsSearchBeforeQueryCommits() {
        XCTAssertTrue(
            ClipboardHistoryInputBehavior.shouldExpandSearch(
                characters: "n",
                modifiers: []
            )
        )
        XCTAssertTrue(
            ClipboardHistoryInputBehavior.shouldExpandSearch(
                characters: "你",
                modifiers: []
            )
        )
        XCTAssertFalse(
            ClipboardHistoryInputBehavior.shouldExpandSearch(
                characters: "1",
                modifiers: [.command]
            )
        )
    }

    @MainActor
    func testCommandShortcutVisibilityFollowsModifierState() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryViewModelTests.\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = ClipboardHistoryViewModel(
            store: ClipboardHistoryStore(rootURL: root),
            retention: .oneMonth
        )

        XCTAssertFalse(viewModel.showsNumberShortcuts)
        viewModel.updateCommandKey(isPressed: true)
        XCTAssertTrue(viewModel.showsNumberShortcuts)
        viewModel.updateCommandKey(isPressed: false)
        XCTAssertFalse(viewModel.showsNumberShortcuts)
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
