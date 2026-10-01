import UIKit
import XCTest
@testable import MonkSynth

private struct ProbeCharacter: ToonCharacter {
    let id = "probe"
    let displayName = "Probe"
    let palette = Palette.neutral
    let mouthStyle = ToonMouth.Style(x: 150, y: 150, scale: 1, variant: .bare)
    func drawToonBody() { Toon.shape(Toon.circle(150, 150, 120), fill: .white) }
    func drawToonFace(_ e: Expression) {}
}

final class ToonMouthTests: XCTestCase {
    func testAnchorsMatchTheMockup() {
        let expected: [(CGFloat, CGFloat)] = [(24, 26), (34, 40), (50, 56), (64, 34), (74, 18)]
        for (i, (w, h)) in expected.enumerated() {
            let p = ToonMouth.params(vowel: Float(i) / 4)
            XCTAssertEqual(p.w, w, accuracy: 1e-6)
            XCTAssertEqual(p.h, h, accuracy: 1e-6)
        }
    }

    func testContinuous() {
        // The width bound is 0.65, not the plan's 0.6: with the mockup's
        // own ANCHORS (locked down by testAnchorsMatchTheMockup above), the
        // OH→AH segment steps width by 16 units over a 0.25-wide vowel
        // span, i.e. 16/0.25 * 0.01 == 0.64 per 0.01-apart sample — a real,
        // exact value, not float noise, that the plan's literal 0.6
        // doesn't leave room for. 0.65 keeps the test's actual intent (no
        // big jumps) while fitting the real anchor data.
        var prev = ToonMouth.params(vowel: 0)
        for i in 1...100 {
            let p = ToonMouth.params(vowel: Float(i) / 100)
            XCTAssertLessThanOrEqual(abs(p.w - prev.w), 0.65)
            XCTAssertLessThanOrEqual(abs(p.h - prev.h), 0.9)
            prev = p
        }
    }

    func testEEIsMuchWiderForItsHeightThanOO() {
        let oo = ToonMouth.params(vowel: 0), ee = ToonMouth.params(vowel: 1)
        XCTAssertGreaterThanOrEqual((ee.w / ee.h) / (oo.w / oo.h), 3)
    }

    func testMouthShapeIsInStageFractions() {
        let c = ProbeCharacter()
        let ah = c.mouthShape(vowel: 0.5)
        XCTAssertEqual(ah.w, 50.0 / 300, accuracy: 1e-6)
        XCTAssertEqual(ah.h, 56.0 / 300, accuracy: 1e-6)
        XCTAssertEqual(c.mouthCentre.fx, 0.5, accuracy: 1e-6)
        XCTAssertEqual(c.mouthBoxFraction, 1)
    }

    func testDrawsAMouthThroughCharacterView() throws {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        view.character = ProbeCharacter()
        view.noteActive = true
        view.vowel = 0.5

        // Render through a known RGBA8 context rather than sampling the
        // UIGraphicsImageRenderer image's raw dataProvider bytes directly:
        // the renderer's backing CGImage pixel format/byte order is not
        // guaranteed by the API, so redrawing into an explicitly-created
        // RGBA context (as `ToonTests`/`ShadowTests` already do elsewhere
        // in this suite) is the reliable way to sample a pixel.
        let img = UIGraphicsImageRenderer(size: view.bounds.size).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: colorSpace, bitmapInfo: bitmapInfo))
        let cgImage = try XCTUnwrap(img.cgImage)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // The cavity colour (#4A1622) must appear at the mouth centre.
        let i = (150 * width + 150) * 4
        let (r, g, b) = (pixels[i], pixels[i + 1], pixels[i + 2])
        XCTAssertLessThan(Int(r), 120); XCTAssertLessThan(Int(g), 60); XCTAssertLessThan(Int(b), 80)
    }
}
