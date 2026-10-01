import UIKit

/// A cream unicorn head: pointed ears, a golden spiral horn, a two-tone
/// pink/blue flowing mane draped down one side, and a pale pink muzzle the
/// mouth aperture opens inside of. Sings on a rainbow meadow.
struct UnicornCharacter: ToonCharacter {
    let id = "unicorn"
    let displayName = "Unicorn"
    let palette = Palette(accent: UIColor(hex: 0xB77CF2), skyTop: UIColor(hex: 0xBFE3FF),
                          skyBottom: UIColor(hex: 0xFFE6F4), ground: UIColor(hex: 0x9EDC8B))
    let mouthStyle = ToonMouth.Style(x: 150, y: 190, scale: 0.75, variant: .muzzle)

    private static let coat = UIColor(hex: 0xFBF6FF)
    private static let iris = UIColor(hex: 0x6B3FA0)

    func drawToonBody() {
        Toon.shape(Toon.path("M50 300 C58 250 90 220 150 220 C210 220 242 250 250 300 Z"), fill: Self.coat)
        Toon.shape(Toon.path("M124 48 C74 56 36 118 40 244 C56 214 74 196 98 186 C92 140 98 92 124 48 Z"), fill: UIColor(hex: 0xFF8FC7))
        Toon.shape(Toon.path("M112 74 C80 112 66 172 76 252 C90 224 104 208 122 198 C108 160 104 116 112 74 Z"), fill: UIColor(hex: 0x8FB8FF))
        Toon.shape(Toon.path("M100 60 L86 14 L124 46 Z"), fill: Self.coat, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M200 60 L214 14 L176 46 Z"), fill: Self.coat, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 112, 64, 70), fill: Self.coat)
        Toon.shape(Toon.path("M108 66 C114 40 140 36 156 50 C142 54 130 62 122 76 C116 72 112 70 108 66 Z"), fill: UIColor(hex: 0xC78CFF), lineWidth: Toon.medium)
        Toon.shape(Toon.path("M138 52 L150 4 L162 52 Z"), fill: UIColor(hex: 0xF8C94A), lineWidth: Toon.medium)
        Toon.stroke(Toon.path("M141 40 L159 34 M144 27 L157 22"), width: Toon.fine)
        Toon.shape(Toon.ellipse(150, 178, 54, 42), fill: UIColor(hex: 0xF8CFD8))
    }

    func drawToonFace(_ e: Expression) {
        if e.blinking {
            Toon.eyeClosed(120, 118, 15)
            Toon.eyeClosed(180, 118, 15)
        } else {
            Toon.eyeOpen(120, 116, 18, iris: Self.iris)
            Toon.eyeOpen(180, 116, 18, iris: Self.iris)
        }
        Toon.stroke(Toon.path("M104 100 L98 94 M108 96 L104 88 M196 100 L202 94 M192 96 L196 88"), width: Toon.fine)
        Toon.fill(Toon.ellipse(132, 160, 5, 7), Toon.ink)
        Toon.fill(Toon.ellipse(168, 160, 5, 7), Toon.ink)
        Toon.cheek(100, 142)
        Toon.cheek(200, 142)
    }

    /// Pastel meadow under a rainbow, with a couple of drifting clouds.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), cx = W / 2, L = W * 0.12, R = W * 0.88
            Backdrop.rainbow(cx, gy, min(W * 0.48, H * 0.62), u: u)
            Backdrop.cloud(L + 10, H * 0.24, 0.8, u: u)
            Backdrop.cloud(R - 10, H * 0.34, 0.65, u: u)
            Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: self.palette.ground, u: u)
        }
    }
}
