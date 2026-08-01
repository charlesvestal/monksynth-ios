// Closeup render harness for tuning character geometry. Not an assertion test.
//
//   scripts/test.sh MonkSynthTests/RenderCloseup && open /tmp/closeup.png
//
// Set CLOSEUP_IDS to pick characters. Renders large, with a light grid overlay
// so misalignment between parts is measurable rather than eyeballed.
import UIKit
import XCTest
@testable import MonkSynth

final class RenderCloseup: XCTestCase {

    /// Which characters to inspect, by id.
    private static let ids = ["girl", "oldman"]
    private static let cell = CGSize(width: 440, height: 440)

    func testWriteCloseup() throws {
        let chars = Self.ids.compactMap { id in
            CharacterRegistry.all.first { $0.id == id }
        }
        XCTAssertEqual(chars.count, Self.ids.count, "unknown id in CLOSEUP list")

        let labelH: CGFloat = 20
        let sheet = CGSize(width: Self.cell.width * CGFloat(chars.count),
                           height: Self.cell.height + labelH)
        let image = UIGraphicsImageRenderer(size: sheet).image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))

            for (i, character) in chars.enumerated() {
                let x = Self.cell.width * CGFloat(i)
                let frame = CGRect(x: x, y: labelH,
                                   width: Self.cell.width, height: Self.cell.height)

                let view = CharacterView(frame: CGRect(origin: .zero, size: Self.cell))
                view.backgroundColor = .clear
                view.character = character
                view.vowel = 0.5
                view.amplitude = 0.0
                view.noteActive = false
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: x, y: labelH)
                view.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()

                // Grid every 10% of the stage square, so vertical alignment of
                // hairlines/ears against the head can be read off numerically
                // instead of guessed at.
                let side = min(frame.width, frame.height)
                let stage = CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2,
                                   width: side, height: side)
                ctx.cgContext.setLineWidth(0.5)
                for step in 1..<10 {
                    let f = CGFloat(step) / 10.0
                    let major = step == 5
                    UIColor.systemTeal.withAlphaComponent(major ? 0.55 : 0.22).setStroke()
                    ctx.cgContext.stroke(CGRect(x: stage.minX, y: stage.minY + stage.height * f,
                                                width: stage.width, height: 0))
                    ctx.cgContext.stroke(CGRect(x: stage.minX + stage.width * f, y: stage.minY,
                                                width: 0, height: stage.height))
                }

                ("\(character.displayName) (\(character.id))" as NSString).draw(
                    at: CGPoint(x: x + 6, y: 2),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                                     .foregroundColor: Theme.textPrimary])
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/closeup.png"))
        print("SNAPSHOT_WRITTEN /tmp/closeup.png bytes=\(data.count)")
    }
}
