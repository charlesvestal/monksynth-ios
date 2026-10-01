// App-icon generator. Not an assertion test — it renders the monk in his
// scene into a 1024x1024 opaque PNG for Host/Assets.xcassets. Run:
//
//   scripts/test.sh MonkSynthTests/RenderAppIcon && open /tmp/monk_icon.png
//
// The App Store rejects icons containing an alpha channel, so the canvas is
// filled opaque and the PNG is re-encoded without alpha.
import UIKit
import XCTest
@testable import MonkSynth

final class RenderAppIcon: XCTestCase {

    func testWriteAppIcon() throws {
        let side: CGFloat = 1024
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true           // no alpha channel
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format)

        let image = renderer.image { ctx in
            // Lay the scene out in a 300-point square — the size the mockup's
            // scenes were drawn at — and scale it up, so the props (sun,
            // flags, mountains) keep the proportions they have on stage
            // instead of shrinking to specks on a 1024-pixel canvas.
            let canvasSide: CGFloat = 300
            ctx.cgContext.scaleBy(x: side / canvasSide, y: side / canvasSide)
            let canvas = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)
            // Head and shoulders, like CharacterThumbnail but tighter: the
            // face is what reads at 40pt on a home screen. Show a 230-unit
            // window of the 300-unit stage centred on (150, 150) — the top
            // of the head to the beads on the robe.
            // Always the monk, matching the default character.
            let monk = MonkCharacter()
            let window: CGFloat = 230, centre = CGPoint(x: 150, y: 150)
            let k = canvasSide / window
            let stage = CGRect(x: canvasSide / 2 - centre.x * k, y: canvasSide / 2 - centre.y * k,
                               width: Toon.stageUnits * k, height: Toon.stageUnits * k)
            monk.drawBackdrop(in: canvas, stage: stage)
            // Singing a round OH: open enough to read as singing at 40pt,
            // small enough that the lips stay inside the chin.
            let vowel: Float = 0.3
            monk.drawBody(in: stage)
            monk.drawFace(in: stage, expression: Expression(blinking: false, loudness: 0, vowel: vowel))
            monk.drawMouth(in: stage, vowel: vowel, amplitudeBoost: 1)
            monk.drawOverMouth(in: stage)
        }

        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/monk_icon.png"))
        print("ICON_WRITTEN /tmp/monk_icon.png bytes=\(data.count)")
    }
}
