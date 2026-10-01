import AVFoundation
import UIKit

/// A fire fighter: a red dome helmet with a flared brim and a gold front
/// badge, a safety-yellow turnout coat with a reflective band, and a
/// moustache drawn over the mouth. Its voice is upstream's "Dorje" factory
/// preset, verbatim — see `FactoryVoiceTable`'s doc comment for the
/// measurement and the full mapping. Sings in front of a brick wall.
struct FireFighterCharacter: ToonCharacter {
    let id = "firefighter"
    let displayName = "Fire Fighter"
    let palette = Palette(accent: UIColor(hex: 0xFF5A3C), skyTop: UIColor(hex: 0xC9644A),
                          skyBottom: UIColor(hex: 0xB4523C), ground: UIColor(hex: 0x8D8F96))
    let mouthStyle = ToonMouth.Style(x: 150, y: 178, scale: 0.75, variant: .lips, lip: UIColor(hex: 0xC86A5A))

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    func drawToonBody() {
        let coat = Toon.path("M30 300 C38 246 80 218 150 216 C220 218 262 246 270 300 Z")
        Toon.shape(coat, fill: UIColor(hex: 0xF2B33A))
        Toon.clipped(to: coat) {
            let band = Toon.rect(0, 258, 300, 18)
            Toon.fill(band, UIColor(hex: 0xE9EEF2))
            Toon.stroke(band, width: 3.5)
            Toon.fill(Toon.rect(0, 265, 300, 4), UIColor(hex: 0xC9D1D8))
        }
        Toon.stroke(coat, width: Toon.bold)
        Toon.shape(Toon.path("M108 214 L130 238 L150 222 L170 238 L192 214 Z"), fill: UIColor(hex: 0xD79A2A), lineWidth: Toon.medium)
        Toon.shape(Toon.path("M130 184 L170 184 L172 220 L128 220 Z"), fill: UIColor(hex: 0xE8B48C), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(150, 136, 62), fill: UIColor(hex: 0xEEBD93))
        Toon.shape(Toon.path("M70 92 C66 70 110 64 150 64 C190 64 234 70 230 92 C200 98 100 98 70 92 Z"), fill: UIColor(hex: 0xD8372D))
        Toon.shape(Toon.path("M96 82 C96 30 204 30 204 82 Z"), fill: UIColor(hex: 0xE2433A))
        Toon.shape(Toon.path("M136 40 L164 40 L168 76 L132 76 Z"), fill: UIColor(hex: 0xF6CF4A), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(150, 58, 7), fill: UIColor(hex: 0xD8372D), lineWidth: 3)
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        if e.blinking {
            Toon.eyeClosed(126, 128, 12)
            Toon.eyeClosed(174, 128, 12)
        } else {
            Toon.eyeOpen(126, 126, 13)
            Toon.eyeOpen(174, 126, 13)
        }
        Toon.stroke(Toon.path("M110 \(108 + lift) L138 \(110 + lift)"), width: Toon.medium)
        Toon.stroke(Toon.path("M162 \(110 + lift) L190 \(108 + lift)"), width: Toon.medium)
        Toon.shape(Toon.ellipse(150, 150, 12, 10), fill: UIColor(hex: 0xE0A07C), lineWidth: Toon.medium)
    }

    func drawToonOverMouth() {
        Toon.shape(Toon.path("M118 166 C128 156 144 158 150 164 C156 158 172 156 182 166 C170 172 158 170 150 166 C142 170 130 172 118 166 Z"),
                   fill: UIColor(hex: 0x7A3D22), lineWidth: Toon.fine)
    }
}
