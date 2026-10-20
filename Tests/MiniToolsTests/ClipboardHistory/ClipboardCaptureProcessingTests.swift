import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MiniTools

final class ClipboardCaptureProcessingTests: XCTestCase {
    @MainActor
    func testPlainRepresentationWinsEvenWhenHTMLIsAdvertisedFirst() throws {
        let board = NSPasteboard(name: .init("CaptureProcessing.\(UUID())"))
        let item = NSPasteboardItem()
        item.setString("<p>HTML alternative</p>", forType: .html)
        item.setString("plain alternative", forType: .string)
        board.clearContents()
        board.writeObjects([item])
        let snapshot = try XCTUnwrap(ClipboardHistoryCaptureService.snapshot(from: board, sourceApplication: nil))
        XCTAssertEqual(snapshot.plainText, "plain alternative")
        XCTAssertEqual(ClipboardHistoryCaptureService.process(snapshot)?.item.kind, .richText)
    }

    @MainActor
    func testMonitorProcessesOffMainActorAndDeliversInCopyOrder() async {
        let board = NSPasteboard(name: .init("CaptureProcessing.\(UUID())"))
        let received = expectation(description: "copies processed")
        received.expectedFulfillmentCount = 2
        var values: [String] = []
        let monitor = ClipboardHistoryMonitor(pasteboard: board, process: { snapshot in
            XCTAssertFalse(Thread.isMainThread)
            return ClipboardHistoryCaptureService.process(snapshot)
        })
        monitor.onCapture = { capture in
            values.append(capture.item.plainText ?? "")
            received.fulfill()
        }
        monitor.start(enabled: true)
        defer { monitor.stop() }
        for text in ["first", "second"] {
            board.clearContents()
            board.setString(text, forType: .string)
            monitor.poll()
        }
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(values, ["first", "second"])
    }

    @MainActor
    func testDisablingCaptureDropsLateProcessingResult() async {
        let board = NSPasteboard(name: .init("CaptureProcessing.\(UUID())"))
        let started = expectation(description: "processing started")
        let released = DispatchSemaphore(value: 0)
        let delivered = expectation(description: "disabled capture must not deliver")
        delivered.isInverted = true
        let monitor = ClipboardHistoryMonitor(pasteboard: board, process: { snapshot in
            started.fulfill()
            released.wait()
            return ClipboardHistoryCaptureService.process(snapshot)
        })
        monitor.onCapture = { _ in delivered.fulfill() }
        monitor.start(enabled: true)
        defer { monitor.stop() }
        board.clearContents()
        board.setString("copy", forType: .string)
        monitor.poll()
        await fulfillment(of: [started], timeout: 1)
        monitor.setEnabled(false)
        released.signal()
        await fulfillment(of: [delivered], timeout: 0.1)
    }

    @MainActor
    func testOCRWaitsForPersistenceAndUsesMetadataCallback() async {
        let board = NSPasteboard(name: .init("CaptureProcessing.\(UUID())"))
        let enriched = expectation(description: "OCR metadata delivered")
        var persisted = false
        var captures = 0
        let monitor = ClipboardHistoryMonitor(pasteboard: board, recognize: { _ in
            XCTAssertFalse(Thread.isMainThread)
            return "recognized"
        })
        monitor.onCapture = { _ in
            try? await Task.sleep(for: .milliseconds(20))
            persisted = true
            captures += 1
        }
        monitor.onRecognizedText = { _, _, text in
            XCTAssertTrue(persisted)
            XCTAssertEqual(text, "recognized")
            enriched.fulfill()
        }
        monitor.start(enabled: true)
        defer { monitor.stop() }
        board.clearContents()
        board.setData(Data([0]), forType: .png) // Fake payload; OCR client is injected.
        monitor.poll()
        await fulfillment(of: [enriched], timeout: 2)
        XCTAssertEqual(captures, 1)
    }

    func testImageProcessingProducesDownsampledPNGWithoutAppKitDrawing() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2048, height: 1024, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let snapshot = ClipboardHistoryCaptureService.Snapshot(payloads: [
            .init(itemIndex: 0, typeIdentifier: "public.png", data: data as Data)
        ], plainText: nil, imageData: data as Data, fileNames: [], hasRichText: false,
            sourceBundleIdentifier: nil, sourceName: nil, copiedAt: Date(timeIntervalSince1970: 100))
        let result = await Task.detached { ClipboardHistoryCaptureService.process(snapshot) }.value
        let capture = try XCTUnwrap(result)
        XCTAssertEqual(capture.item.pixelWidth, 2048)
        XCTAssertEqual(capture.item.pixelHeight, 1024)
        let thumbnail = try XCTUnwrap(capture.thumbnailData)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 480)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 240)
    }
}
