import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import MiniTools

final class DefaultApplicationTests: XCTestCase {
    func testCatalogMapsEveryExtensionToTheExpectedDeclaredContentType() throws {
        XCTAssertEqual(DefaultApplicationFileTypeCatalog.supported.count, 12)

        for fileType in DefaultApplicationFileTypeCatalog.supported {
            let resolved = try XCTUnwrap(fileType.resolvedContentType)
            XCTAssertEqual(resolved.identifier, fileType.expectedContentTypeIdentifier)
            XCTAssertFalse(resolved.isDynamic)
            for filenameExtension in fileType.filenameExtensions {
                XCTAssertTrue(
                    DefaultApplicationFileType.contentTypes(for: filenameExtension)
                        .contains(where: {
                            $0.identifier == fileType.expectedContentTypeIdentifier
                        }),
                    "\(filenameExtension) did not resolve to \(fileType.expectedContentTypeIdentifier)"
                )
            }
        }
    }

    func testCatalogDoesNotContainBroadCatchAllTypes() {
        let forbidden = Set([
            UTType.item.identifier,
            UTType.content.identifier,
            UTType.data.identifier,
            UTType.text.identifier
        ])

        XCTAssertTrue(
            DefaultApplicationFileTypeCatalog.supported.allSatisfy {
                !forbidden.contains($0.expectedContentTypeIdentifier)
            }
        )
    }

    @MainActor
    func testRefreshShowsActualDefaultsAndUnavailableSublimeState() throws {
        let fileType = try XCTUnwrap(DefaultApplicationFileTypeCatalog.supported.first)
        let textEdit = application("TextEdit", "com.apple.TextEdit")
        let client = FakeDefaultApplicationClient(
            sublimeText: nil,
            defaults: [fileType.expectedContentTypeIdentifier: textEdit]
        )
        let model = DefaultApplicationSettingsModel(client: client, fileTypes: [fileType])

        model.refresh()

        XCTAssertNil(model.sublimeTextApplication)
        XCTAssertEqual(model.rows.first?.currentApplication, textEdit)
        XCTAssertFalse(try XCTUnwrap(model.rows.first).isUpdating)
    }

    @MainActor
    func testUnavailableSublimeDoesNotRequestAChange() async throws {
        let fileType = try XCTUnwrap(DefaultApplicationFileTypeCatalog.supported.first)
        let textEdit = application("TextEdit", "com.apple.TextEdit")
        let client = FakeDefaultApplicationClient(
            sublimeText: nil,
            defaults: [fileType.expectedContentTypeIdentifier: textEdit]
        )
        let model = DefaultApplicationSettingsModel(client: client, fileTypes: [fileType])
        model.refresh()

        await model.setSublimeText(for: fileType.id)

        XCTAssertTrue(client.requestedContentTypeIdentifiers.isEmpty)
        XCTAssertEqual(model.rows.first?.currentApplication, textEdit)
        XCTAssertEqual(model.rows.first?.message?.kind, .error)
        XCTAssertTrue(model.rows.first?.message?.text.contains("未找到 Sublime Text") == true)
    }

    @MainActor
    func testSettingSublimeUsesExactTypeAndVerifiesTheResult() async throws {
        let fileType = try XCTUnwrap(
            DefaultApplicationFileTypeCatalog.supported.first(where: { $0.id == "markdown" })
        )
        let sublime = application("Sublime Text", "com.sublimetext.4")
        let textEdit = application("TextEdit", "com.apple.TextEdit")
        let client = FakeDefaultApplicationClient(
            sublimeText: sublime,
            defaults: [fileType.expectedContentTypeIdentifier: textEdit]
        )
        let model = DefaultApplicationSettingsModel(client: client, fileTypes: [fileType])
        model.refresh()

        await model.setSublimeText(for: fileType.id)

        XCTAssertEqual(client.requestedContentTypeIdentifiers, ["net.daringfireball.markdown"])
        XCTAssertEqual(model.rows.first?.currentApplication, sublime)
        XCTAssertEqual(model.rows.first?.message?.kind, .success)
    }

    @MainActor
    func testSuccessfulRequestThatIsNotAppliedShowsVerificationFailure() async throws {
        let fileType = try XCTUnwrap(DefaultApplicationFileTypeCatalog.supported.first)
        let sublime = application("Sublime Text", "com.sublimetext.4")
        let textEdit = application("TextEdit", "com.apple.TextEdit")
        let client = FakeDefaultApplicationClient(
            sublimeText: sublime,
            defaults: [fileType.expectedContentTypeIdentifier: textEdit]
        )
        client.appliesChanges = false
        let model = DefaultApplicationSettingsModel(client: client, fileTypes: [fileType])
        model.refresh()

        await model.setSublimeText(for: fileType.id)

        XCTAssertEqual(model.rows.first?.currentApplication, textEdit)
        XCTAssertEqual(model.rows.first?.message?.kind, .error)
        XCTAssertTrue(model.rows.first?.message?.text.contains("当前仍为 TextEdit") == true)
    }

    @MainActor
    func testRejectedRequestRequeriesAndShowsTheError() async throws {
        let fileType = try XCTUnwrap(DefaultApplicationFileTypeCatalog.supported.first)
        let sublime = application("Sublime Text", "com.sublimetext.4")
        let textEdit = application("TextEdit", "com.apple.TextEdit")
        let client = FakeDefaultApplicationClient(
            sublimeText: sublime,
            defaults: [fileType.expectedContentTypeIdentifier: textEdit]
        )
        client.setError = TestError.rejected
        let model = DefaultApplicationSettingsModel(client: client, fileTypes: [fileType])
        model.refresh()

        await model.setSublimeText(for: fileType.id)

        XCTAssertEqual(model.rows.first?.currentApplication, textEdit)
        XCTAssertEqual(model.rows.first?.message?.kind, .error)
        XCTAssertTrue(model.rows.first?.message?.text.contains("用户已拒绝") == true)
    }

    private func application(
        _ name: String,
        _ bundleIdentifier: String
    ) -> DefaultApplicationIdentity {
        DefaultApplicationIdentity(
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }
}

@MainActor
private final class FakeDefaultApplicationClient: DefaultApplicationClient {
    var appliesChanges = true
    var setError: Error?
    private(set) var requestedContentTypeIdentifiers: [String] = []

    private let sublimeText: DefaultApplicationIdentity?
    private var defaults: [String: DefaultApplicationIdentity]

    init(
        sublimeText: DefaultApplicationIdentity?,
        defaults: [String: DefaultApplicationIdentity]
    ) {
        self.sublimeText = sublimeText
        self.defaults = defaults
    }

    func sublimeTextApplication() -> DefaultApplicationIdentity? {
        sublimeText
    }

    func defaultApplication(for contentType: UTType) -> DefaultApplicationIdentity? {
        defaults[contentType.identifier]
    }

    func setDefaultApplication(
        _ application: DefaultApplicationIdentity,
        for contentType: UTType
    ) async throws {
        requestedContentTypeIdentifiers.append(contentType.identifier)
        if let setError { throw setError }
        if appliesChanges {
            defaults[contentType.identifier] = application
        }
    }
}

private enum TestError: LocalizedError {
    case rejected

    var errorDescription: String? { "用户已拒绝" }
}
