import AVFoundation
import UIKit

/// A punk rocker: a tall jagged mohawk in acid green, a leather jacket with
/// a popped white-lined collar and scattered studs, and a safety-pin cheek
/// piercing. Its voice is upstream's "Jamyang" factory preset, verbatim —
/// see `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping. Sings on a club stage between the speaker stacks.
struct PunkCharacter: ToonCharacter {
    let id = "punk"
    let displayName = "Punk"
    let palette = Palette(accent: UIColor(hex: 0x7DFF3A), skyTop: UIColor(hex: 0x2A1F44),
                          skyBottom: UIColor(hex: 0x130D20), ground: UIColor(hex: 0x3B2F2B))
    let mouthStyle = ToonMouth.Style(x: 150, y: 180, scale: 0.75, variant: .lips, lip: UIColor(hex: 0x6B3A6A))

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    // The mohawk's tips are each +6 in y from gen.mjs so they clear the
    // stage's top edge (gen.mjs's own path clips there at scale 1).
    private static let mohawk = Toon.path("M118 82 L112 32 L130 68 L134 16 L146 64 L152 8 L160 64 L170 18 L172 68 L188 34 L184 84 C164 76 136 76 118 82 Z")

    func drawToonBody() {
        Toon.shape(Toon.path("M30 300 C38 246 80 216 150 214 C220 216 262 246 270 300 Z"), fill: UIColor(hex: 0x2B2A35))
        Toon.shape(Toon.path("M110 216 L150 280 L190 216 L172 216 L150 250 L128 216 Z"), fill: UIColor(hex: 0x45434F), lineWidth: Toon.medium)
        Toon.shape(Toon.path("M128 216 L150 250 L172 216 Z"), fill: UIColor(hex: 0xF2F2F2), lineWidth: Toon.medium)
        for (x, y) in [(64, 262), (80, 244), (236, 262), (220, 244), (100, 290), (200, 290)] {
            Toon.shape(Toon.circle(CGFloat(x), CGFloat(y), 5), fill: UIColor(hex: 0xD9DDE3), lineWidth: 2.5, shaded: false)
        }
        Toon.shape(Toon.path("M132 184 L168 184 L170 220 L130 220 Z"), fill: UIColor(hex: 0xE7B590), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(84, 134, 14), fill: UIColor(hex: 0xE7B590), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(216, 134, 14), fill: UIColor(hex: 0xE7B590), lineWidth: Toon.medium)
        Toon.shape(Toon.circle(80, 146, 4), fill: UIColor(hex: 0xD9DDE3), lineWidth: 2, shaded: false)
        Toon.shape(Toon.circle(220, 146, 4), fill: UIColor(hex: 0xD9DDE3), lineWidth: 2, shaded: false)
        Toon.shape(Toon.ellipse(150, 132, 66, 68), fill: UIColor(hex: 0xEDBE97))
        Toon.shape(Self.mohawk, fill: UIColor(hex: 0x7DFF3A), lineWidth: Toon.medium)
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        if e.blinking {
            Toon.eyeClosed(124, 128, 13)
            Toon.eyeClosed(176, 128, 13)
        } else {
            Toon.shape(Toon.ellipse(124, 128, 15, 12), fill: .white, lineWidth: Toon.medium, shaded: false)
            Toon.fill(Toon.circle(126, 129, 7), Toon.ink)
            Toon.highlight(123, 126, 2.5)
            Toon.shape(Toon.ellipse(176, 128, 15, 12), fill: .white, lineWidth: Toon.medium, shaded: false)
            Toon.fill(Toon.circle(174, 129, 7), Toon.ink)
            Toon.highlight(171, 126, 2.5)
        }
        Toon.stroke(Toon.path("M106 \(106 + lift) L140 \(116 + lift)"), width: Toon.bold)
        Toon.stroke(Toon.path("M194 \(106 + lift) L160 \(116 + lift)"), width: Toon.bold)
        Toon.stroke(Toon.path("M146 150 Q150 156 156 150"), width: Toon.fine)
        Toon.stroke(Toon.circle(160, 154, 5), width: 3, color: UIColor(hex: 0xD9DDE3))
    }

    /// A dive-bar stage: coloured spotlights either side, an amp stacked on each end.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.clip(to: rect); ctx.translateBy(x: rect.minX, y: rect.minY)
        let W = rect.width, H = rect.height, u = stage.width / Toon.stageUnits
        let gy = (H * 0.72).rounded(), L = W * 0.12, R = W * 0.88
        Backdrop.sky(CGRect(x: 0, y: 0, width: W, height: H), top: palette.skyTop, bottom: palette.skyBottom)
        Backdrop.spot(L + 30, W, gy, color: UIColor(hex: 0xFF4FD8), u: u)
        Backdrop.spot(R - 30, W, gy, color: UIColor(hex: 0x7DFF3A), u: u)
        Backdrop.ground(CGRect(x: 0, y: 0, width: W, height: H), y: gy, color: palette.ground, u: u)
        Backdrop.amp(L, gy + 2, H / 300, u: u)
        Backdrop.amp(R, gy + 2, H / 300, u: u)
        ctx.restoreGState()
    }
}
