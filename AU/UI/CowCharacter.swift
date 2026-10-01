import UIKit

/// A front-facing cow head over rounded shoulders: floppy ears, small
/// stubby horns, a dark patch over one eye and another on the shoulder, a
/// bell at the chest, and a big pale muzzle the mouth aperture opens
/// inside of. Sings in a pasture.
struct CowCharacter: ToonCharacter {
    let id = "cow"
    let displayName = "Cow"
    let palette = Palette(accent: UIColor(hex: 0x5AA7D8), skyTop: UIColor(hex: 0x9FD6F2),
                          skyBottom: UIColor(hex: 0xE3F4FB), ground: UIColor(hex: 0x86CD66))
    let mouthStyle = ToonMouth.Style(x: 150, y: 196, scale: 0.8, variant: .muzzle)

    private static let coat = UIColor(hex: 0xFBF5EA)
    private static let patch = UIColor(hex: 0x2F2A2A)
    private static let horn = UIColor(hex: 0xEFE3C4)
    private static let ear = UIColor(hex: 0xF2C4B8)

    func drawToonBody() {
        Toon.shape(Toon.path("M36 300 C44 250 86 222 150 222 C214 222 256 250 264 300 Z"), fill: Self.coat)
        Toon.shape(Toon.path("M200 240 C230 246 252 270 258 300 L200 300 C196 280 188 262 200 240 Z"), fill: Self.patch, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M92 66 C70 60 64 36 76 26 C82 44 96 50 108 54 Z"), fill: Self.horn, lineWidth: Toon.medium)
        Toon.shape(Toon.path("M208 66 C230 60 236 36 224 26 C218 44 204 50 192 54 Z"), fill: Self.horn, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(62, 108, 30, 14), fill: Self.ear, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(238, 108, 30, 14), fill: Self.ear, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 112, 72, 66), fill: Self.coat)
        Toon.shape(Toon.path("M96 74 C110 58 140 64 138 90 C136 116 112 130 92 122 C82 108 84 86 96 74 Z"), fill: Self.patch, lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 180, 72, 48), fill: UIColor(hex: 0xF6B9B0))
        Toon.fill(Toon.ellipse(124, 160, 7, 10), UIColor(hex: 0x9A5A55))
        Toon.fill(Toon.ellipse(176, 160, 7, 10), UIColor(hex: 0x9A5A55))
        Toon.shape(Toon.path("M136 228 L164 228 L170 262 L130 262 Z"), fill: UIColor(hex: 0xF2BD3A), lineWidth: Toon.medium)
    }

    func drawToonFace(_ e: Expression) {
        if e.blinking {
            Toon.eyeClosed(118, 104, 13)
            Toon.eyeClosed(182, 104, 13)
        } else {
            Toon.eyeOpen(118, 102, 15)
            Toon.eyeOpen(182, 102, 15)
        }
    }

    /// A pasture: a red barn behind, a split-rail fence running along the right.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), cx = W / 2, L = W * 0.12, R = W * 0.88
            Backdrop.cloud(cx + W * 0.25, H * 0.2, 0.6, u: u)
            Backdrop.barn(L + 20, gy, H / 330, u: u)
            Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: self.palette.ground, u: u)
            Backdrop.fence(R - 110, W + 10, gy + 4, u: u)
        }
    }
}
