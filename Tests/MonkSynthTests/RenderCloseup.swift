// Closeup render harness for evaluating character geometry. Not an assertion test.
//
//   scripts/test.sh MonkSynthTests/RenderCloseup && open /tmp/closeup.png
//
// Renders EVERY registered character large, with a 10% grid overlay, so
// misalignment between parts is measurable rather than eyeballed. Set
// `onlyIDs` to narrow to specific characters while iterating on a fix.
import UIKit
import XCTest
@testable import MonkSynth

final class RenderCloseup: XCTestCase {

    /// Empty = every registered character. Narrow while iterating.
    private static let onlyIDs: [String] = []
    private static let cell = CGSize(width: 420, height: 420)
    private static let columns = 4

    func testWriteCloseup() throws {
        let chars = Self.onlyIDs.isEmpty
            ? CharacterRegistry.all
            : Self.onlyIDs.compactMap { id in CharacterRegistry.all.first { $0.id == id } }
        XCTAssertFalse(chars.isEmpty)

        let labelH: CGFloat = 22
        let cols = min(Self.columns, chars.count)
        let rows = (chars.count + cols - 1) / cols
        let sheet = CGSize(width: Self.cell.width * CGFloat(cols),
                           height: (Self.cell.height + labelH) * CGFloat(rows))

        let image = UIGraphicsImageRenderer(size: sheet).image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))

            for (i, character) in chars.enumerated() {
                let col = i % cols, row = i / cols
                let x = Self.cell.width * CGFloat(col)
                let y = (Self.cell.height + labelH) * CGFloat(row)

                let view = CharacterView(frame: CGRect(origin: .zero, size: Self.cell))
                view.backgroundColor = .clear
                view.character = character
                view.vowel = 0.5
                view.amplitude = 0
                view.noteActive = false
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: x, y: y + labelH)
                view.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()

                // 10% grid over the centred square stage, so "is the head
                // floating" is a measurement rather than an impression.
                let frame = CGRect(x: x, y: y + labelH,
                                   width: Self.cell.width, height: Self.cell.height)
                let side = min(frame.width, frame.height)
                let stage = CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2,
                                   width: side, height: side)
                ctx.cgContext.setLineWidth(0.5)
                for step in 1..<10 {
                    let f = CGFloat(step) / 10.0
                    UIColor.systemTeal.withAlphaComponent(step == 5 ? 0.5 : 0.18).setStroke()
                    ctx.cgContext.stroke(CGRect(x: stage.minX, y: stage.minY + stage.height * f,
                                                width: stage.width, height: 0))
                    ctx.cgContext.stroke(CGRect(x: stage.minX + stage.width * f, y: stage.minY,
                                                width: 0, height: stage.height))
                }

                ("\(character.displayName) (\(character.id))" as NSString).draw(
                    at: CGPoint(x: x + 6, y: y + 3),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                                     .foregroundColor: Theme.textPrimary])
            }
        }
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/closeup.png"))
        print("SNAPSHOT_WRITTEN /tmp/closeup.png bytes=\(data.count)")
    }
}
