import UIKit
import XCTest
@testable import MonkSynth

final class ToonTests: XCTestCase {
    func testLinesAndClose() {
        XCTAssertEqual(Toon.path("M0 0 L10 0 L10 10 Z").bounds, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    func testCubic() {
        XCTAssertLessThan(Toon.path("M0 0 C0 -10 20 -10 20 0").bounds.minY, -5)
    }

    func testQuadratic() {
        XCTAssertLessThan(Toon.path("M0 0 Q10 -20 20 0").bounds.minY, -5)
    }

    func testCircularArcSweepsOverTheTop() {
        let b = Toon.path("M0 0 A10 10 0 0 1 20 0").bounds
        XCTAssertEqual(b.minY, -10, accuracy: 0.01)
        XCTAssertEqual(b.minX, 0, accuracy: 0.01)
        XCTAssertEqual(b.maxX, 20, accuracy: 0.01)
    }

    func testCompactNumberSyntax() {
        let b = Toon.path("M-2.5-3L4 5").bounds
        XCTAssertEqual(b.minX, -2.5, accuracy: 1e-9)
        XCTAssertEqual(b.minY, -3, accuracy: 1e-9)
        XCTAssertEqual(b.maxY, 5, accuracy: 1e-9)
    }

    func testHexColour() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: 0x2B1D1A).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r * 255, 43, accuracy: 0.01)
        XCTAssertEqual(g * 255, 29, accuracy: 0.01)
        XCTAssertEqual(b * 255, 26, accuracy: 0.01)
        XCTAssertEqual(a, 1)
    }

    func testInStageMapsTheThreeHundredUnitSquareOntoTheStage() {
        let stage = CGRect(x: 10, y: 20, width: 150, height: 150)
        let r = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        var mapped = CGPoint.zero
        _ = r.image { _ in
            Toon.inStage(stage) { ctx in
                mapped = CGPoint(x: 300, y: 300).applying(ctx.ctm)
            }
        }
        // ctm includes the renderer's own flip/scale; compare against the
        // same context's mapping of the stage corner instead.
        var expected = CGPoint.zero
        _ = r.image { ctx in expected = CGPoint(x: stage.maxX, y: stage.maxY).applying(ctx.cgContext.ctm) }
        XCTAssertEqual(mapped.x, expected.x, accuracy: 0.01)
        XCTAssertEqual(mapped.y, expected.y, accuracy: 0.01)
    }
}
