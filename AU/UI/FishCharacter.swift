import UIKit

/// A stylised profile-view fish, facing right: fanned side fins, a dorsal
/// fin, a big round oval body with a pale belly and scale-arc markings, and
/// puckered lips at the snout. Sings on a lagoon reef.
struct FishCharacter: ToonCharacter {
    let id = "fish"
    let displayName = "Fish"
    let palette = Palette(accent: UIColor(hex: 0xFFB02E), skyTop: UIColor(hex: 0x2B8FBE),
                          skyBottom: UIColor(hex: 0x155A86), ground: UIColor(hex: 0xE8CF8F))
    let mouthStyle = ToonMouth.Style(x: 150, y: 182, scale: 0.85, variant: .lips, lip: UIColor(hex: 0xFF6F61))

    private static let fin = UIColor(hex: 0xFF9A3C)
    private static let finLine = UIColor(hex: 0xD4651A)

    func drawToonBody() {
        Toon.shape(Toon.path("M60 158 C16 116 -2 196 16 250 C36 230 54 214 70 206 Z"), fill: Self.fin)
        Toon.stroke(Toon.path("M52 170 L28 160 M50 190 L20 200 M54 206 L28 234"), width: Toon.fine, color: Self.finLine)
        Toon.shape(Toon.path("M240 158 C284 116 302 196 284 250 C264 230 246 214 230 206 Z"), fill: Self.fin)
        Toon.stroke(Toon.path("M248 170 L272 160 M250 190 L280 200 M246 206 L272 234"), width: Toon.fine, color: Self.finLine)
        Toon.shape(Toon.path("M108 92 C100 34 150 4 200 16 C188 40 192 66 200 92 Z"), fill: Self.fin)
        Toon.stroke(Toon.path("M128 70 C130 46 146 28 166 20 M150 66 C156 48 168 34 184 26"), width: Toon.fine, color: Self.finLine)
        Toon.shape(Toon.ellipse(150, 168, 108, 112), fill: UIColor(hex: 0xF57F22))
        Toon.fill(Toon.ellipse(150, 225, 62, 40), UIColor(hex: 0xFFC27A))
        for (x, y) in [(110, 210), (150, 214), (190, 210), (130, 240), (170, 240)] {
            Toon.stroke(Toon.path("M\(x - 12) \(y) Q\(x) \(y + 12) \(x + 12) \(y)"), width: Toon.fine, color: Self.finLine)
        }
        Toon.fill(Toon.rotated(Toon.ellipse(102, 88, 22, 12), degrees: -30, cx: 102, cy: 88), UIColor.white.withAlphaComponent(0.4))
    }

    func drawToonFace(_ e: Expression) {
        if e.blinking {
            Toon.eyeClosed(108, 128, 20)
            Toon.eyeClosed(192, 128, 20)
        } else {
            Toon.eyeOpen(108, 126, 28, look: CGPoint(x: 3, y: 2))
            Toon.eyeOpen(192, 126, 28, look: CGPoint(x: -3, y: 2))
        }
    }
}
