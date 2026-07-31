// App-icon generator. Not an assertion test — it renders the monk into a
// 1024x1024 opaque PNG for Host/Assets.xcassets. Run:
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
            // Warm dark ground so the maroon robe and skin read strongly at
            // small sizes rather than dissolving into the system wallpaper.
            Theme.background.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

            // Draw the monk oversized and shifted up, so the icon crops to the
            // head and shoulders — the face is what reads at 40pt on a home
            // screen; a full-body figure would be an unrecognisable smudge.
            // Always the monk, matching the default character — the design
            // doc explicitly keeps changing the app icon out of scope.
            let scale: CGFloat = 1.62
            let box = CGSize(width: side * scale, height: side * scale)
            let view = CharacterView(frame: CGRect(origin: .zero, size: box))
            view.backgroundColor = .clear
            view.character = MonkCharacter()
            view.vowel = 0.42          // mouth open mid-chant, clearly singing
            view.amplitude = 0.7
            view.noteActive = true

            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: -(box.width - side) / 2,
                                      y: -(box.height - side) * 0.30)
            view.layer.render(in: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }

        let data = try XCTUnwrap(image.pngData())
        try data.write(to: URL(fileURLWithPath: "/tmp/monk_icon.png"))
        print("ICON_WRITTEN /tmp/monk_icon.png bytes=\(data.count)")
    }
}
