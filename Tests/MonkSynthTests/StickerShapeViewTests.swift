import XCTest
import UIKit
@testable import MonkSynth

/// The header discs and drawer pill are one shape-layer path, not
/// cornerRadius + border (which leaves a jagged fill fringe outside the
/// ring and traces the shadow from rendered alpha).
final class StickerShapeViewTests: XCTestCase {

    private func laidOut(_ v: StickerShapeView, _ size: CGSize) -> StickerShapeView {
        v.frame = CGRect(origin: .zero, size: size)
        v.layoutIfNeeded()
        return v
    }

    private func assertRect(_ a: CGRect?, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        guard let a else { return XCTFail("no path", file: file, line: line) }
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(x, y, accuracy: 1e-6, "\(a) vs \(b)", file: file, line: line)
        }
    }

    func testDiscIsAnInsetCirclePathWithNoLayerBorder() throws {
        let v = laidOut(StickerShapeView(fill: Theme.cream), CGSize(width: 36, height: 36))
        let shape = try XCTUnwrap(v.layer as? CAShapeLayer)
        let half = Theme.outline / 2
        assertRect(shape.path?.boundingBox, CGRect(x: half, y: half, width: 36 - 2 * half, height: 36 - 2 * half))
        XCTAssertEqual(shape.lineWidth, Theme.outline)
        XCTAssertEqual(shape.strokeColor, Theme.ink.cgColor)
        XCTAssertEqual(shape.fillColor, Theme.cream.cgColor)
        XCTAssertEqual(v.layer.borderWidth, 0)
        XCTAssertEqual(v.layer.cornerRadius, 0)
        XCTAssertNil(v.backgroundColor)
        XCTAssertFalse(v.isUserInteractionEnabled)
        XCTAssertNil(shape.shadowPath, "no shadow unless asked for")
    }

    func testDropShadowUsesTheOuterCircleAsAHardPath() throws {
        let v = laidOut(StickerShapeView(fill: Theme.cream, dropShadow: true), CGSize(width: 36, height: 36))
        let shape = try XCTUnwrap(v.layer as? CAShapeLayer)
        assertRect(shape.shadowPath?.boundingBox, CGRect(x: 0, y: 0, width: 36, height: 36))
        XCTAssertEqual(shape.shadowRadius, 0)
        XCTAssertEqual(shape.shadowOpacity, 1)
        XCTAssertEqual(shape.shadowOffset, CGSize(width: 0, height: 3))
        XCTAssertEqual(shape.shadowColor, Theme.ink.cgColor)
    }

    func testCapsuleFollowsBoundsChanges() throws {
        let v = laidOut(StickerShapeView(fill: Theme.cream), CGSize(width: 44, height: 20))
        let shape = try XCTUnwrap(v.layer as? CAShapeLayer)
        let half = Theme.outline / 2
        assertRect(shape.path?.boundingBox, CGRect(x: half, y: half, width: 44 - 2 * half, height: 20 - 2 * half))
        _ = laidOut(v, CGSize(width: 60, height: 24))
        assertRect(shape.path?.boundingBox, CGRect(x: half, y: half, width: 60 - 2 * half, height: 24 - 2 * half))
    }
}
