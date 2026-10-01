import AVFoundation
import UIKit

/// A front-facing dog: floppy drooping ears, a tan muzzle patch holding a
/// dark button nose, and a red collar with a gold tag. Its voice is
/// upstream's "Monastary" factory preset, verbatim — see
/// `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping. Sings in a backyard by its doghouse.
struct DogCharacter: ToonCharacter {
    let id = "dog"
    let displayName = "Dog"
    let palette = Palette(accent: UIColor(hex: 0xFF7A3D), skyTop: UIColor(hex: 0x9FD6F2),
                          skyBottom: UIColor(hex: 0xE9F6FF), ground: UIColor(hex: 0x8BCF68))
    let mouthStyle = ToonMouth.Style(x: 150, y: 186, scale: 0.72, variant: .muzzle)

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    func drawToonBody() {
        Toon.shape(Toon.path("M36 300 C44 248 86 216 150 216 C214 216 256 248 264 300 Z"), fill: UIColor(hex: 0xC98A4A))
        Toon.shape(Toon.path("M114 166 L186 166 L190 228 L110 228 Z"), fill: UIColor(hex: 0xC98A4A), lineWidth: Toon.medium)
        Toon.shape(Toon.path("M108 210 C130 222 170 222 192 210 L194 228 C170 240 130 240 106 228 Z"), fill: UIColor(hex: 0xE0413A), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(150, 246, 12), fill: UIColor(hex: 0xF6CF4A), lineWidth: Toon.medium)
        Toon.shape(Toon.ellipse(150, 118, 70, 68), fill: UIColor(hex: 0xD49452))
        Toon.shape(Toon.path("M86 80 C50 84 42 150 56 200 C70 206 88 190 96 170 C100 140 104 104 86 80 Z"), fill: UIColor(hex: 0x7A4A26))
        Toon.shape(Toon.path("M214 80 C250 84 258 150 244 200 C230 206 212 190 204 170 C200 140 196 104 214 80 Z"), fill: UIColor(hex: 0x7A4A26))
        Toon.shape(Toon.ellipse(150, 172, 50, 40), fill: UIColor(hex: 0xF3DCB8))
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        if e.blinking {
            Toon.eyeClosed(124, 118, 13)
            Toon.eyeClosed(176, 118, 13)
        } else {
            Toon.eyeOpen(124, 116, 15, iris: UIColor(hex: 0x5A3315))
            Toon.eyeOpen(176, 116, 15, iris: UIColor(hex: 0x5A3315))
        }
        Toon.stroke(Toon.path("M110 \(96 + lift) Q122 \(88 + lift) 134 \(94 + lift)"), width: Toon.medium)
        Toon.stroke(Toon.path("M166 \(94 + lift) Q178 \(88 + lift) 190 \(96 + lift)"), width: Toon.medium)
        Toon.shape(Toon.path("M134 140 C134 130 166 130 166 140 C166 152 156 158 150 158 C144 158 134 152 134 140 Z"),
                   fill: Toon.ink, lineWidth: Toon.fine, shaded: false)
        Toon.highlight(144, 138, 3.5)
    }

    /// A backyard: a cloud drifting, a doghouse on the right, a bone on the left.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), L = W * 0.12, R = W * 0.88
            Backdrop.cloud(L + 20, H * 0.2, 0.6, u: u)
            Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: self.palette.ground, u: u)
            Backdrop.doghouse(R - 16, gy + 6, H / 300, u: u)
            Backdrop.bone(L + 10, gy + 30, 0.8, u: u)
        }
    }
}
