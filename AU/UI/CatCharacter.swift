import AVFoundation
import UIKit

/// A front-facing cat: triangular ears with pink inner tips, a curled
/// tail, tabby stripe markings, and whiskers drawn over the mouth. Its
/// voice is upstream's "Tinley" factory preset, verbatim — see
/// `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping. Sings on a windowsill at night.
struct CatCharacter: ToonCharacter {
    let id = "cat"
    let displayName = "Cat"
    let palette = Palette(accent: UIColor(hex: 0x7EE07E), skyTop: UIColor(hex: 0x2E2546),
                          skyBottom: UIColor(hex: 0x4A3B66), ground: UIColor(hex: 0xC79A6A))
    let mouthStyle = ToonMouth.Style(x: 150, y: 172, scale: 0.6, variant: .muzzle)

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let fur = UIColor(hex: 0xEE9A45)
    private static let stripe = UIColor(hex: 0xC46A1E)

    func drawToonBody() {
        Toon.shape(Toon.path("M238 300 C270 280 290 240 270 210 C260 196 244 204 252 214 C264 232 248 270 222 286 Z"), fill: Self.fur, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M40 300 C46 252 84 224 118 216 C120 200 118 184 116 170 L184 170 C182 184 180 200 182 216 C216 224 254 252 260 300 Z"), fill: Self.fur)
        Toon.stroke(Toon.path("M84 252 C92 244 100 242 108 244"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M72 276 C82 266 92 264 100 266"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M216 252 C208 244 200 242 192 244"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M228 276 C218 266 208 264 200 266"), width: Toon.medium, color: Self.stripe)
        Toon.shape(Toon.path("M84 96 L80 30 L132 64 Z"), fill: Self.fur, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M216 96 L220 30 L168 64 Z"), fill: Self.fur, lineWidth: Toon.medium)
        Toon.fill(Toon.path("M92 82 L90 46 L120 66 Z"), UIColor(hex: 0xF6A3AD))
        Toon.fill(Toon.path("M208 82 L210 46 L180 66 Z"), UIColor(hex: 0xF6A3AD))
        Toon.shape(Toon.ellipse(150, 128, 78, 72), fill: UIColor(hex: 0xF2A14C))
        Toon.stroke(Toon.path("M150 62 L150 82"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M134 64 L136 80"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M166 64 L164 80"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M80 128 L94 128"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M78 140 L92 138"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M220 128 L206 128"), width: Toon.medium, color: Self.stripe)
        Toon.stroke(Toon.path("M222 140 L208 138"), width: Toon.medium, color: Self.stripe)
        Toon.shape(Toon.circle(135, 152, 16), fill: UIColor(hex: 0xFFF6EA), lineWidth: Toon.medium, shaded: false)
        Toon.shape(Toon.circle(165, 152, 16), fill: UIColor(hex: 0xFFF6EA), lineWidth: Toon.medium, shaded: false)
    }

    func drawToonFace(_ e: Expression) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -8)
        if e.blinking {
            Toon.eyeClosed(120, 120, 15)
            Toon.eyeClosed(180, 120, 15)
        } else {
            Toon.shape(Toon.path("M102 120 C110 104 132 104 138 120 C132 134 110 134 102 120 Z"), fill: UIColor(hex: 0x9AE86A), lineWidth: Toon.medium, shaded: false)
            Toon.shape(Toon.path("M162 120 C168 104 190 104 198 120 C190 134 168 134 162 120 Z"), fill: UIColor(hex: 0x9AE86A), lineWidth: Toon.medium, shaded: false)
            Toon.fill(Toon.ellipse(120, 120, 4, 11), Toon.ink)
            Toon.fill(Toon.ellipse(180, 120, 4, 11), Toon.ink)
            Toon.highlight(116, 114, 2.5)
            Toon.highlight(176, 114, 2.5)
        }
        Toon.shape(Toon.path("M141 141 L159 141 L150 151 Z"), fill: UIColor(hex: 0xF48A9A), lineWidth: Toon.fine, shaded: false)
        ctx.restoreGState()
    }

    func drawToonOverMouth() {
        Toon.stroke(Toon.path("M120 148 L70 140"), width: 2.5)
        Toon.stroke(Toon.path("M120 158 L72 162"), width: 2.5)
        Toon.stroke(Toon.path("M180 148 L230 140"), width: 2.5)
        Toon.stroke(Toon.path("M180 158 L228 162"), width: 2.5)
    }

    /// A night-time alley: a lit window behind, the sill level with the ground.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), cx = W / 2
            Backdrop.window(cx, gy - 6, W * 0.7, gy - H * 0.08, u: u)
            Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: self.palette.ground, u: u)
        }
    }
}
