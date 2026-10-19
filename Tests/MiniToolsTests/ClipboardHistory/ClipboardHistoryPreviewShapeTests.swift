import CoreGraphics
import XCTest
@testable import MiniTools

final class ClipboardHistoryPreviewShapeTests: XCTestCase {
    func testPointerAndBodyHaveOneClosedOutlineWithoutBaseStroke() {
        let path = ClipboardHistoryPreviewShape.path(size: CGSize(width: 560, height: 360), pointerX: 280)
        var starts = 0
        var closes = 0
        var baseCrossings = 0
        var current = CGPoint.zero
        path.applyWithBlock { element in
            let value = element.pointee
            switch value.type {
            case .moveToPoint:
                starts += 1
                current = value.points[0]
            case .addLineToPoint:
                let next = value.points[0]
                if current.y == ClipboardHistoryPreviewShape.pointerHeight,
                   next.y == current.y,
                   min(current.x, next.x) < 280, max(current.x, next.x) > 280 {
                    baseCrossings += 1
                }
                current = next
            case .addQuadCurveToPoint:
                current = value.points[1]
            case .addCurveToPoint:
                current = value.points[2]
            case .closeSubpath:
                closes += 1
            @unknown default:
                XCTFail("Unknown path element")
            }
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(baseCrossings, 0)
        XCTAssertTrue(path.contains(CGPoint(x: 280, y: 5)))
        XCTAssertTrue(path.contains(CGPoint(x: 280, y: 13)))
        XCTAssertFalse(path.contains(CGPoint(x: 250, y: 5)))
    }

    func testPointerIsRoundedAndRemainsInsideCanvasAtScreenEdges() {
        let size = CGSize(width: 340, height: 240)
        for anchor: CGFloat in [-100, 0, 170, 340, 440] {
            let path = ClipboardHistoryPreviewShape.path(size: size, pointerX: anchor)
            let bounds = path.boundingBoxOfPath
            XCTAssertGreaterThanOrEqual(bounds.minX, 0.5)
            XCTAssertGreaterThanOrEqual(bounds.minY, 0.5)
            XCTAssertLessThanOrEqual(bounds.maxX, size.width - 0.5)
            XCTAssertLessThanOrEqual(bounds.maxY, size.height - 0.5)
            let center = min(max(anchor, 32.5), size.width - 32.5)
            XCTAssertTrue(path.contains(CGPoint(x: center, y: 5)))
            XCTAssertFalse(path.contains(CGPoint(x: center, y: 0.5)))
            XCTAssertTrue(path.contains(CGPoint(x: 1, y: 40)))
            XCTAssertTrue(path.contains(CGPoint(x: size.width - 1, y: 40)))
        }
    }

    func testInvalidSizeDoesNotCreateMalformedPath() {
        XCTAssertTrue(ClipboardHistoryPreviewShape.path(size: .zero, pointerX: 0).isEmpty)
        XCTAssertTrue(ClipboardHistoryPreviewShape.path(size: CGSize(width: 560, height: 10), pointerX: 280).isEmpty)
    }
}
