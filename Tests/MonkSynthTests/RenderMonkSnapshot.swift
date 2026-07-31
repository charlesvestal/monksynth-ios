// Visual-check harness. Not an assertion test — it renders CharacterView so a
// human can look at each character, because no test can tell us whether the
// monk looks like a monk or the fish looks like a fish. Run:
//
//   scripts/test.sh MonkSynthTests/RenderMonkSnapshot && open /tmp/monk_sheet.png
//
// Writes /tmp/monk_sheet.png (vowel sweep), /tmp/monk_aspect.png (extreme
// aspect ratios, to confirm the rig letterboxes rather than distorting), and
// /tmp/characters.png (all five characters across the vowel sweep).
import UIKit
import XCTest
@testable import MonkSynth

final class RenderMonkSnapshot: XCTestCase {

    func testWriteSnapshotSheet() throws {
        let cell = CGSize(width: 220, height: 260)
        let poses: [(String, Float, Float, Bool)] = [
            ("idle",       0.5, 0.0, false),
            ("vowel-0.00", 0.0, 0.8, true),
            ("vowel-0.25", 0.25, 0.8, true),
            ("vowel-0.50", 0.5, 0.8, true),
            ("vowel-0.75", 0.75, 0.8, true),
            ("vowel-1.00", 1.0, 0.8, true),
        ]

        let sheet = CGSize(width: cell.width * CGFloat(poses.count), height: cell.height)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            for (i, pose) in poses.enumerated() {
                let view = CharacterView(frame: CGRect(origin: .zero, size: cell))
                view.backgroundColor = .clear
                view.vowel = pose.1
                view.amplitude = pose.2
                view.noteActive = pose.3
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: cell.width * CGFloat(i), y: 0)
                view.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()

                let label = pose.0 as NSString
                label.draw(at: CGPoint(x: cell.width * CGFloat(i) + 8, y: cell.height - 18),
                           withAttributes: [.font: UIFont.systemFont(ofSize: 11),
                                            .foregroundColor: Theme.textDim])
            }
        }

        let data = try XCTUnwrap(image.pngData())
        let path = "/tmp/monk_sheet.png"
        try data.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count)")
    }

    /// All five characters across the vowel sweep, at the small-ish sizes
    /// they actually render at (per the design brief, "as small as ~120pt
    /// tall") — the honesty check for "instantly distinguishable in
    /// silhouette". Required by the characters task; look at the output
    /// with the Read tool, don't just check it wrote bytes.
    func testWriteAllCharactersSweep() throws {
        let cell = CGSize(width: 140, height: 160)
        let vowels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let labelH: CGFloat = 16

        let cols = vowels.count
        let rows = CharacterRegistry.all.count
        let sheet = CGSize(width: cell.width * CGFloat(cols),
                           height: (cell.height + labelH) * CGFloat(rows) + labelH)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))

            for (row, character) in CharacterRegistry.all.enumerated() {
                let rowY = labelH + CGFloat(row) * (cell.height + labelH)
                ("\(character.displayName) (\(character.id))" as NSString).draw(
                    at: CGPoint(x: 6, y: rowY - labelH + 1),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                                     .foregroundColor: Theme.textPrimary])

                for (col, v) in vowels.enumerated() {
                    let view = CharacterView(frame: CGRect(origin: .zero, size: cell))
                    view.backgroundColor = .clear
                    view.character = character
                    view.vowel = v
                    view.amplitude = 0.8
                    view.noteActive = true
                    ctx.cgContext.saveGState()
                    ctx.cgContext.translateBy(x: cell.width * CGFloat(col), y: rowY)
                    view.layer.render(in: ctx.cgContext)
                    ctx.cgContext.restoreGState()

                    ("v=\(v)" as NSString).draw(
                        at: CGPoint(x: cell.width * CGFloat(col) + 4, y: rowY + cell.height - 14),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 9),
                                         .foregroundColor: Theme.textDim])
                }
            }
        }

        let data = try XCTUnwrap(image.pngData())
        let path = "/tmp/characters.png"
        try data.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count)")
    }

    /// Ad hoc check for the "must not distort at extreme aspect ratios"
    /// requirement: render the same mid-vowel pose into a very wide/short
    /// frame and a very tall/narrow frame side by side against a square
    /// frame, so a human can confirm the character stays centred and
    /// undistorted (only letterboxed) in each.
    func testWriteAspectRatioSheet() throws {
        let frames: [(String, CGSize)] = [
            ("square-260", CGSize(width: 260, height: 260)),
            ("wide-480x120", CGSize(width: 480, height: 120)),
            ("tall-160x420", CGSize(width: 160, height: 420)),
        ]
        let gap: CGFloat = 12
        let sheetWidth = frames.reduce(0) { $0 + $1.1.width + gap }
        let sheetHeight = frames.map(\.1.height).max() ?? 260
        let sheet = CGSize(width: sheetWidth, height: sheetHeight)
        let renderer = UIGraphicsImageRenderer(size: sheet)
        let image = renderer.image { ctx in
            Theme.background.setFill()
            ctx.fill(CGRect(origin: .zero, size: sheet))
            var x: CGFloat = 0
            for (name, size) in frames {
                let view = CharacterView(frame: CGRect(origin: .zero, size: size))
                view.backgroundColor = .clear
                view.vowel = 0.5
                view.amplitude = 0.8
                view.noteActive = true
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: x, y: 0)
                view.layer.render(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
                (name as NSString).draw(at: CGPoint(x: x + 4, y: sheet.height - 14),
                                         withAttributes: [.font: UIFont.systemFont(ofSize: 10),
                                                           .foregroundColor: Theme.textDim])
                x += size.width + gap
            }
        }
        let data = try XCTUnwrap(image.pngData())
        let path = "/tmp/monk_aspect.png"
        try data.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT_WRITTEN \(path) bytes=\(data.count)")
    }
}
