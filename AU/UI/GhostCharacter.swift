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

    /// A moonlit graveyard: a starry night sky, blank tombstones either side.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.clip(to: rect); ctx.translateBy(x: rect.minX, y: rect.minY)
        let W = rect.width, H = rect.height, u = stage.width / Toon.stageUnits
        let gy = (H * 0.72).rounded(), cx = W / 2, L = W * 0.12, R = W * 0.88
        Backdrop.sky(CGRect(x: 0, y: 0, width: W, height: H), top: palette.skyTop, bottom: palette.skyBottom)
        Backdrop.moon(R - 20, H * 0.2, min(34, H * 0.09), u: u)
        Backdrop.star(L + 10, H * 0.14, 6, u: u)
        Backdrop.star(cx - W * 0.2, H * 0.08, 4, u: u)
        Backdrop.star(cx + W * 0.15, H * 0.12, 5, u: u)
        Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: palette.ground, u: u)
        Backdrop.tomb(L + 10, gy + 6, H / 300, u: u)
        Backdrop.tomb(R - 10, gy + 8, H / 360, u: u)
        ctx.restoreGState()
    }
}
