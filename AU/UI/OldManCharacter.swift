import UIKit

/// An old man: a blue-grey cardigan with a zip trim, bald on top with tufts
/// of side hair, a wide grey beard, bushy brows and a moustache drawn over
/// the mouth. Sings on a porch at dusk.
struct OldManCharacter: ToonCharacter {
    let id = "oldman"
    let displayName = "Gerald"
    let palette = Palette(accent: UIColor(hex: 0xE0A84A), skyTop: UIColor(hex: 0xE9D3A3),
                          skyBottom: UIColor(hex: 0xE2C690), ground: UIColor(hex: 0x8A5A3B))
    let mouthStyle = ToonMouth.Style(x: 150, y: 178, scale: 0.72, variant: .lips, lip: UIColor(hex: 0xC47F6F))

    private static let hair = UIColor(hex: 0xF4F3EE)

    func drawToonBody() {
        Toon.shape(Toon.path("M30 300 C38 246 80 214 150 212 C220 214 262 246 270 300 Z"), fill: UIColor(hex: 0x5F6E8C))
        Toon.shape(Toon.path("M118 214 L150 270 L182 214 Z"), fill: Self.hair, lineWidth: Toon.medium)
        Toon.stroke(Toon.path("M150 270 L150 300"), width: Toon.medium)
        Toon.fill(Toon.circle(160, 284, 4), Toon.ink)
        Toon.shape(Toon.path("M100 92 C72 90 60 116 68 138 C58 152 70 170 90 164 L104 120 Z"), fill: Self.hair, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M200 92 C228 90 240 116 232 138 C242 152 230 170 210 164 L196 120 Z"), fill: Self.hair, lineWidth: Toon.medium)
        Toon.shape(Toon.circle(84, 124, 14), fill: UIColor(hex: 0xE2B08A), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(216, 124, 14), fill: UIColor(hex: 0xE2B08A), lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 116, 66, 72), fill: UIColor(hex: 0xE8B991))
        Toon.shape(Toon.path("M92 140 C90 200 110 252 150 262 C190 252 210 200 208 140 C190 150 170 150 150 148 C130 150 110 150 92 140 Z"), fill: Self.hair)
        Toon.stroke(Toon.path("M128 72 Q150 66 172 72"), width: Toon.fine, color: UIColor(hex: 0xC99A74))
        Toon.stroke(Toon.path("M132 84 Q150 79 168 84"), width: Toon.fine, color: UIColor(hex: 0xC99A74))
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        Toon.shape(Toon.path("M100 \(104 + lift) C108 \(88 + lift) 132 \(90 + lift) 140 \(102 + lift) C126 \(98 + lift) 112 \(100 + lift) 100 \(104 + lift) Z"),
                   fill: Self.hair, lineWidth: Toon.fine)
        Toon.shape(Toon.path("M200 \(104 + lift) C192 \(88 + lift) 168 \(90 + lift) 160 \(102 + lift) C174 \(98 + lift) 188 \(100 + lift) 200 \(104 + lift) Z"),
                   fill: Self.hair, lineWidth: Toon.fine)
        // The old man's eyes are closed, blink or not.
        Toon.eyeClosed(122, 116, 11)
        Toon.eyeClosed(178, 116, 11)
        Toon.shape(Toon.ellipse(150, 138, 14, 12), fill: UIColor(hex: 0xD99A7A), lineWidth: Toon.medium)
    }

    func drawToonOverMouth() {
        Toon.shape(Toon.path("M108 162 C120 148 140 150 150 158 C160 150 180 148 192 162 C176 166 162 166 150 162 C138 166 124 166 108 162 Z"),
                   fill: Self.hair, lineWidth: Toon.medium)
    }

    /// A wallpapered room: striped wall, a night window, a floor lamp.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), L = W * 0.12, R = W * 0.88
            Backdrop.stripes(W, gy, u: u)
            Backdrop.window(L + 34, gy - H * 0.2, min(90, W * 0.2), H * 0.32, u: u)
            Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: self.palette.ground, u: u)
            Backdrop.lamp(R - 6, gy + 4, H / 300, u: u)
        }
    }
}
