import AVFoundation
import UIKit

/// A classic sheet ghost: a single rounded blob — no separate head or body
/// — with a domed top and a scalloped, wavy hem. Its voice is upstream's
/// "Rabten" factory preset, verbatim — see `FactoryVoiceTable`'s doc
/// comment for the measurement and the full mapping. Sings in a moonlit
/// graveyard.
struct GhostCharacter: ToonCharacter {
    let id = "ghost"
    let displayName = "Ghost"
    let palette = Palette(accent: UIColor(hex: 0x9AE6FF), skyTop: UIColor(hex: 0x1C2250),
                          skyBottom: UIColor(hex: 0x3A3F7C), ground: UIColor(hex: 0x2C4A3E))
    let mouthStyle = ToonMouth.Style(x: 150, y: 178, scale: 0.85, variant: .bare)

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    func drawToonBody() {
        Toon.shape(Toon.path("M62 290 L62 140 C62 54 238 54 238 140 L238 290 C224 270 214 300 200 282 C186 266 174 300 160 282 C146 266 134 300 120 282 C106 266 94 300 80 282 C72 274 68 280 62 290 Z"),
                   fill: UIColor(hex: 0xF4F2FF), shadow: UIColor(hex: 0xCFCAF2))
    }

    func drawToonFace(_ e: Expression) {
        if e.blinking {
            Toon.eyeClosed(122, 130, 15)
            Toon.eyeClosed(178, 130, 15)
        } else {
            Toon.fill(Toon.ellipse(122, 128, 14, 19), Toon.ink)
            Toon.fill(Toon.ellipse(178, 128, 14, 19), Toon.ink)
            Toon.highlight(117, 120, 4.5)
            Toon.highlight(173, 120, 4.5)
        }
        Toon.cheek(100, 158, 12)
        Toon.cheek(200, 158, 12)
    }
}
