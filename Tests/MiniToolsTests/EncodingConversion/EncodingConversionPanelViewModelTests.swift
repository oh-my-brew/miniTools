import AppKit
import Carbon
import XCTest
@testable import MiniTools

final class EncodingConversionPanelViewModelTests: XCTestCase {
    @MainActor
    func testSearchAcceptsOnlyASCIILettersDigitsAndSeparatingSpaces() {
        let viewModel = EncodingConversionPanelViewModel(compressionQuality: 0.7)

        viewModel.updateSearchQuery("中文 B64-* qr_2  ")

        XCTAssertEqual(viewModel.searchQuery, "B64 qr2 ")
        XCTAssertEqual(viewModel.normalizedSearchQuery, "b64 qr2")
    }

    @MainActor
    func testSearchFlattensAndRanksTheBestTitleMatchFirst() {
        let sections = TextActionCatalog.sections(for: "plain text")
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            initialSections: sections,
            initialSelectedActionID: sections.first?.actions.first?.id
        )

        viewModel.updateSearchQuery("decode")

        XCTAssertEqual(viewModel.filteredSections.map(\.id), ["search"])
        XCTAssertEqual(viewModel.searchResults.first?.title, "URL Decode")
        XCTAssertEqual(viewModel.selectedActionID, viewModel.searchResults.first?.id)
        XCTAssertEqual(
            viewModel.directShortcutNumber(forActionID: viewModel.searchResults[0].id),
            1
        )
        XCTAssertEqual(
            viewModel.actionID(forDirectShortcutIndex: 0),
            viewModel.searchResults[0].id
        )
        if viewModel.searchResults.count > 1 {
            XCTAssertEqual(
                viewModel.directShortcutNumber(forActionID: viewModel.searchResults[1].id),
                2
            )
            XCTAssertEqual(
                viewModel.actionID(forDirectShortcutIndex: 1),
                viewModel.searchResults[1].id
            )
        }
    }

    @MainActor
    func testSearchReassignsJSONAndBase64ShortcutsFromOne() throws {
        let sections = TextActionCatalog.sections(for: #"{"b": 1, "a": 2}"#)
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            initialSections: sections,
            initialSelectedActionID: sections.first?.actions.first?.id
        )

        XCTAssertEqual(viewModel.directShortcutNumber(forActionID: "json.sort"), 2)
        XCTAssertEqual(viewModel.directShortcutNumber(forActionID: "base64.encode"), 5)
        XCTAssertEqual(viewModel.directShortcutNumber(forActionID: "base64.decode"), 6)

        viewModel.updateSearchQuery("json sort")

        XCTAssertEqual(viewModel.visibleActions.map(\.id), ["json.sort"])
        XCTAssertEqual(viewModel.directShortcutNumber(forActionID: "json.sort"), 1)
        XCTAssertEqual(viewModel.actionID(forDirectShortcutIndex: 0), "json.sort")

        viewModel.updateSearchQuery("base64")

        XCTAssertEqual(
            viewModel.visibleActions.map(\.id),
            ["base64.encode", "base64.decode"]
        )
        XCTAssertEqual(viewModel.directShortcutNumber(forActionID: "base64.encode"), 1)
        XCTAssertEqual(viewModel.directShortcutNumber(forActionID: "base64.decode"), 2)
        XCTAssertEqual(viewModel.actionID(forDirectShortcutIndex: 0), "base64.encode")
        XCTAssertEqual(viewModel.actionID(forDirectShortcutIndex: 1), "base64.decode")
    }

    @MainActor
    func testShowsAtMostTwoRecentActionsWithoutRecommendations() {
        let recentStore = RecentEncodingActionStore()
        recentStore.record("hash.sha256")
        recentStore.record("qr.generate")
        recentStore.record("url.encode")
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            recentActionStore: recentStore,
            initialSections: TextActionCatalog.sections(for: "plain text")
        )

        XCTAssertEqual(viewModel.sections.first?.id, "recent")
        XCTAssertEqual(viewModel.sections.first?.actions.map(\.id), ["url.encode", "qr.generate"])
        XCTAssertEqual(viewModel.sections.flatMap(\.actions).filter { $0.id == "url.encode" }.count, 1)
    }

    @MainActor
    func testRecommendationSuppressesRecentSection() {
        let recentStore = RecentEncodingActionStore()
        recentStore.record("url.encode")
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            recentActionStore: recentStore,
            initialSections: TextActionCatalog.sections(for: "https%3A%2F%2Fexample.com")
        )

        XCTAssertEqual(viewModel.sections.first?.id, "recommended")
        XCTAssertFalse(viewModel.sections.contains(where: { $0.id == "recent" }))
    }

    @MainActor
    func testImageRecognitionDoesNotReplaceAUserSelection() {
        let compressionAction = ToolAction(
            id: "image.compress",
            title: "压缩图片",
            subtitle: "",
            systemImage: "photo",
            isRecommended: false
        ) { .text("unused") }
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            initialSections: [ToolActionSection(
                id: "image",
                title: "图片处理",
                actions: [compressionAction]
            )],
            initialSelectedActionID: compressionAction.id
        )
        viewModel.select("image.compress")

        viewModel.applyRecognizedImageContents(
            RecognizedImageContents(qrPayload: "payload", recognizedText: nil)
        )

        XCTAssertEqual(viewModel.selectedActionID, "image.compress")
        XCTAssertEqual(viewModel.sections.first?.id, "recognized")
    }

    @MainActor
    func testImageRecognitionIsSelectedBeforeUserInteraction() {
        let viewModel = EncodingConversionPanelViewModel(compressionQuality: 0.7)

        viewModel.applyRecognizedImageContents(
            RecognizedImageContents(qrPayload: "payload", recognizedText: nil)
        )

        XCTAssertEqual(viewModel.selectedActionID, "image.qr")
    }

    @MainActor
    func testControlJKNoLongerMovesSelection() throws {
        let sections = TextActionCatalog.sections(for: "plain text")
        let firstActionID = try XCTUnwrap(sections.flatMap(\.actions).first?.id)
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            initialSections: sections,
            initialSelectedActionID: firstActionID
        )

        XCTAssertNil(FeaturePanelCommandRouter.command(for: try keyEvent(
            keyCode: kVK_ANSI_J,
            characters: "j",
            modifiers: .control
        )))
        XCTAssertNil(FeaturePanelCommandRouter.command(for: try keyEvent(
            keyCode: kVK_ANSI_K,
            characters: "k",
            modifiers: .control
        )))
        XCTAssertEqual(viewModel.selectedActionID, firstActionID)
    }

    @MainActor
    func testEscapeClearsSearchBeforeClosingPanel() throws {
        let viewModel = EncodingConversionPanelViewModel(compressionQuality: 0.7)
        var didCancel = false
        viewModel.onCancel = { didCancel = true }
        viewModel.updateSearchQuery("json")

        XCTAssertTrue(viewModel.handleCommand(.cancel))
        XCTAssertFalse(didCancel)
        XCTAssertEqual(viewModel.searchQuery, "")

        XCTAssertTrue(viewModel.handleCommand(.cancel))
        XCTAssertTrue(didCancel)
    }

    @MainActor
    func testCompletedOperationFromClosedSessionDoesNotWriteClipboard() async {
        let slowAction = ToolAction(
            id: "slow",
            title: "Slow",
            subtitle: "",
            systemImage: "clock",
            isRecommended: false
        ) {
            Thread.sleep(forTimeInterval: 0.05)
            return .text("stale")
        }
        var didWrite = false
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            client: EncodingConversionClient(
                readClipboard: { .text("input") },
                writeClipboard: { _ in didWrite = true },
                recognizeImage: { _ in RecognizedImageContents(qrPayload: nil, recognizedText: nil) }
            ),
            initialSections: [
                ToolActionSection(id: "test", title: "Test", actions: [slowAction])
            ],
            initialSelectedActionID: slowAction.id
        )

        viewModel.performSelectedAction()
        viewModel.endSession()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertFalse(didWrite)
    }

    @MainActor
    func testSuccessfulActionIsReportedOnlyAfterClipboardWrite() async {
        let action = ToolAction(
            id: "test.success",
            title: "测试成功",
            subtitle: "",
            systemImage: "checkmark",
            isRecommended: false
        ) { .text("output") }
        var successfulActions: [(String, String)] = []
        let viewModel = EncodingConversionPanelViewModel(
            compressionQuality: 0.7,
            client: EncodingConversionClient(
                readClipboard: { .text("input") },
                writeClipboard: { _ in },
                recognizeImage: { _ in RecognizedImageContents(qrPayload: nil, recognizedText: nil) }
            ),
            initialSections: [
                ToolActionSection(id: "test", title: "Test", actions: [action])
            ],
            initialSelectedActionID: action.id
        )
        viewModel.onSuccessfulAction = { successfulActions.append(($0, $1)) }

        viewModel.performSelectedAction()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(successfulActions.count, 1)
        XCTAssertEqual(successfulActions.first?.0, action.id)
        XCTAssertEqual(successfulActions.first?.1, action.title)
    }

    private func keyEvent(
        keyCode: Int,
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }
}
