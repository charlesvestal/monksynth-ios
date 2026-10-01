import UIKit

/// A little girl: two round pigtail buns with pink bows, a flared pink dress
/// with a scalloped white collar, and a small round head. Sings on a
/// sunny playground.
struct GirlCharacter: ToonCharacter {
    let id = "girl"
    let displayName = "Little Girl"
    let palette = Palette(accent: UIColor(hex: 0xFF5FA2), skyTop: UIColor(hex: 0x8FD3F7),
                          skyBottom: UIColor(hex: 0xE6F7FF), ground: UIColor(hex: 0x7CC96A))
    let mouthStyle = ToonMouth.Style(x: 150, y: 170, scale: 0.7, variant: .lips, lip: UIColor(hex: 0xE2557A))

    private static let bun = UIColor(hex: 0x7A4425)
    private static let bow = UIColor(hex: 0xFF5FA2)

    func drawToonBody() {
        Toon.shape(Toon.circle(72, 78, 34), fill: Self.bun)
        Toon.shape(Toon.circle(228, 78, 34), fill: Self.bun)
        Toon.shape(Toon.path("M40 300 C48 248 88 222 150 222 C212 222 252 248 260 300 Z"), fill: UIColor(hex: 0xFF6FA8))
        Toon.shape(Toon.path("M150 226 C130 236 108 236 98 226 C110 214 130 212 150 220 C170 212 190 214 202 226 C192 236 170 236 150 226 Z"), fill: .white, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M132 186 L168 186 L170 222 L130 222 Z"), fill: UIColor(hex: 0xF2C39D), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(150, 128, 66), fill: UIColor(hex: 0xF6CBA6))
        Toon.shape(Toon.path("M84 124 C80 64 120 46 150 46 C180 46 220 64 216 124 C200 104 186 96 176 84 C160 100 128 104 100 104 C94 110 88 116 84 124 Z"), fill: UIColor(hex: 0x8A4D2A))
        Toon.shape(Toon.circle(100, 96, 9), fill: Self.bow, lineWidth: Toon.fine)
        Toon.shape(Toon.circle(200, 96, 9), fill: Self.bow, lineWidth: Toon.fine)
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        if e.blinking {
            Toon.eyeClosed(124, 132, 14)
            Toon.eyeClosed(176, 132, 14)
        } else {
            Toon.eyeOpen(124, 130, 16, iris: UIColor(hex: 0x2F7D5B))
            Toon.eyeOpen(176, 130, 16, iris: UIColor(hex: 0x2F7D5B))
        }
        Toon.stroke(Toon.path("M110 \(108 + lift) Q122 \(102 + lift) 134 \(106 + lift)"), width: Toon.fine)
        Toon.stroke(Toon.path("M166 \(106 + lift) Q178 \(102 + lift) 190 \(108 + lift)"), width: Toon.fine)
        Toon.cheek(106, 156, 13)
        Toon.cheek(194, 156, 13)
    }

    /// A sunny park: a tree on the left, a kite drifting on the right.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.clip(to: rect); ctx.translateBy(x: rect.minX, y: rect.minY)
        let W = rect.width, H = rect.height, u = stage.width / Toon.stageUnits
        let gy = (H * 0.72).rounded(), cx = W / 2, L = W * 0.12, R = W * 0.88
        Backdrop.sky(CGRect(x: 0, y: 0, width: W, height: H), top: palette.skyTop, bottom: palette.skyBottom)
        Backdrop.cloud(cx - W * 0.2, H * 0.18, 0.6, u: u)
        Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: palette.ground, u: u)
        Backdrop.tree(L + 6, gy + 6, H / 330, u: u)
        Backdrop.kite(R - 6, H * 0.2, 0.8, u: u)
        ctx.restoreGState()
    }
}
