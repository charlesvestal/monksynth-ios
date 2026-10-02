import UIKit

/// The monk: shaved head, maroon robe with a saffron sash, prayer beads
/// draped on the robe below the neckline. Sings on a Himalayan terrace.
struct MonkCharacter: ToonCharacter {
    let id = "monk"
    let displayName = "Jerry"
    let palette = Palette(accent: UIColor(hex: 0xF0A020), skyTop: UIColor(hex: 0xF7B57A),
                          skyBottom: UIColor(hex: 0xFBE6C4), ground: UIColor(hex: 0xB98A55))
    let mouthStyle = ToonMouth.Style(x: 150, y: 165, scale: 0.8, variant: .lips, lip: UIColor(hex: 0xC8735F))

    private static let skin = UIColor(hex: 0xE4B085)

    func drawToonBody() {
        Toon.shape(Toon.path("M126 168 L174 168 L176 234 L124 234 Z"), fill: Self.skin, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M30 300 C40 246 78 214 116 209 C128 230 172 230 184 209 C222 214 260 246 270 300 Z"),
                   fill: UIColor(hex: 0xA8322A))
        Toon.shape(Toon.path("M98 216 C104 212 110 210 116 209 C150 238 204 266 232 300 L188 300 C166 272 134 248 98 216 Z"),
                   fill: UIColor(hex: 0xF2A51F), lineWidth: Toon.medium)
        for i in 0..<9 {
            let t = CGFloat(i) / 8
            let x = (1 - t) * (1 - t) * 104 + 2 * t * (1 - t) * 150 + t * t * 196
            let y = (1 - t) * (1 - t) * 214 + 2 * t * (1 - t) * 268 + t * t * 214
            Toon.shape(Toon.circle(x, y, 6), fill: UIColor(hex: 0x6E3F22), lineWidth: 3)
        }
        Toon.shape(Toon.circle(84, 128, 15), fill: Self.skin, lineWidth: Toon.medium)
        Toon.shape(Toon.circle(216, 128, 15), fill: Self.skin, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 118, 68, 72), fill: UIColor(hex: 0xE9BB8F))
        Toon.fill(Toon.ellipse(128, 70, 16, 9), UIColor.white.withAlphaComponent(0.45))
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        Toon.stroke(Toon.path("M112 \(102 + lift) Q124 \(96 + lift) 136 \(101 + lift)"), width: Toon.fine)
        Toon.stroke(Toon.path("M164 \(101 + lift) Q176 \(96 + lift) 188 \(102 + lift)"), width: Toon.fine)
        // The monk's eyes are closed in meditation, blink or not.
        Toon.eyeClosed(124, 120, 13)
        Toon.eyeClosed(176, 120, 13)
        Toon.stroke(Toon.path("M148 128 Q144 142 152 146"), width: Toon.fine)
        Toon.cheek(108, 146)
        Toon.cheek(192, 146)
    }

    /// Himalayan terrace: distant mountains, a low sun, prayer flags strung overhead.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), R = W * 0.88, L = W * 0.12, cx = W / 2
            Backdrop.sun(R - W * 0.06, gy - H * 0.3, min(30, H * 0.08), u: u)
            Backdrop.mountain(L + 20, gy, H / 300, u: u)
            Backdrop.mountain(R, gy, H / 380, u: u)
            Backdrop.mountain(cx + W * 0.3, gy, H / 460, u: u)
            Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: self.palette.ground, u: u)
            Backdrop.flags(-10, W + 10, H * 0.08, u: u)
        }
    }
}
