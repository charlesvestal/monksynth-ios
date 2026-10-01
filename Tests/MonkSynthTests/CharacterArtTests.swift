import UIKit
import XCTest
@testable import MonkSynth

/// Art guarantees every drawn character must keep: one connected figure
/// (no floating heads, collars or beads), nothing clipped at the stage edge,
/// and a mouth big enough to read.
final class CharacterArtTests: XCTestCase {

    static var toons: [ToonCharacter] { CharacterRegistry.all.compactMap { $0 as? ToonCharacter } }

    /// Task 3 expects these six; Task 4 changes this to all twelve.
    static let expectedToonIDs: Set<String> = ["monk", "fish", "unicorn", "girl", "oldman", "cow"]

    func testExpectedCharactersAreToons() {
        XCTAssertTrue(Self.expectedToonIDs.isSubset(of: Set(Self.toons.map(\.id))))
    }

    /// Renders the figure alone and returns an alpha mask (true = opaque).
    static func mask(_ c: Character, vowel: Float = 0.5) -> (w: Int, h: Int, opaque: [Bool]) {
        let side = 300
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let stage = CGRect(x: 0, y: 0, width: side, height: side)
            c.drawBody(in: stage)
            c.drawFace(in: stage, expression: Expression(blinking: false, loudness: 0, vowel: vowel))
            c.drawMouth(in: stage, vowel: vowel, amplitudeBoost: 1)
            c.drawOverMouth(in: stage)
        }
        let cg = img.cgImage!
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let ctx = CGContext(data: &data, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Measured directly (see this task's commit message): for a CGContext
        // built this way — data buffer + `draw(_:in:)` of a CGImage that was
        // itself produced by `UIGraphicsImageRenderer` — row 0 of `data`
        // already IS the top of the drawn image (confirmed by rendering only
        // `drawToonBody()` and checking which raw row holds the y≈300 robe
        // hem: it's row 299, not row 0). No flip is needed; a flip here
        // would silently turn every "top" check into a "bottom" check.
        var opaque = [Bool](repeating: false, count: side * side)
        for y in 0..<side { for x in 0..<side {
            opaque[y * side + x] = data[(y * side + x) * 4 + 3] > 127
        } }
        return (side, side, opaque)
    }

    func testEveryFigureIsOneConnectedPiece() {
        for c in Self.toons {
            let m = Self.mask(c)
            var seen = [Bool](repeating: false, count: m.opaque.count)
            var regions: [Int] = []
            for start in 0..<m.opaque.count where m.opaque[start] && !seen[start] {
                var stack = [start]; seen[start] = true; var size = 0
                while let i = stack.popLast() {
                    size += 1
                    let x = i % m.w, y = i / m.w
                    for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && ny >= 0 && nx < m.w && ny < m.h {
                        let j = ny * m.w + nx
                        if m.opaque[j] && !seen[j] { seen[j] = true; stack.append(j) }
                    }
                }
                regions.append(size)
            }
            regions.sort(by: >)
            let stray = regions.dropFirst().reduce(0, +)
            XCTAssertLessThanOrEqual(stray, 12,
                "\(c.id) has \(regions.count) separate pieces (largest \(regions.prefix(4))) — something is floating")
        }
    }

    func testNothingClipsAtTheTopOrSides() {
        for c in Self.toons {
            let m = Self.mask(c)
            for x in 0..<m.w { XCTAssertFalse(m.opaque[x], "\(c.id) touches the top edge at x=\(x)"); if m.opaque[x] { break } }
            for y in 0..<m.h {
                XCTAssertFalse(m.opaque[y * m.w], "\(c.id) touches the left edge at y=\(y)")
                XCTAssertFalse(m.opaque[y * m.w + m.w - 1], "\(c.id) touches the right edge at y=\(y)")
                if m.opaque[y * m.w] || m.opaque[y * m.w + m.w - 1] { break }
            }
        }
    }

    func testMouthsAreBigEnoughToRead() {
        for c in Self.toons {
            XCTAssertGreaterThanOrEqual(c.mouthShape(vowel: 0.5).h * c.mouthBoxFraction, 0.11, "\(c.id) AH too short")
            XCTAssertGreaterThanOrEqual(c.mouthShape(vowel: 1).w * c.mouthBoxFraction, 0.14, "\(c.id) EE too narrow")
        }
    }
}
