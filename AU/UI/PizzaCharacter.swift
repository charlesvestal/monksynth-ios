import AVFoundation
import UIKit

/// A single pizza slice, point-down: a thick golden crust along the top
/// edge, a cheese body, pepperoni rounds, and a basil leaf — a deliberately
/// non-humanoid, non-animal silhouette. Its voice is upstream's "Ngawang"
/// factory preset, verbatim — see `FactoryVoiceTable`'s doc comment for the
/// measurement and the full mapping. Sings on a checkered picnic table.
struct PizzaCharacter: ToonCharacter {
    let id = "pizza"
    let displayName = "Peppo"
    let palette = Palette(accent: UIColor(hex: 0xFF4B3A), skyTop: UIColor(hex: 0xF6E4C4),
                          skyBottom: UIColor(hex: 0xEFD5AA), ground: UIColor(hex: 0xE04B3C))
    let mouthStyle = ToonMouth.Style(x: 150, y: 168, scale: 0.75, variant: .bare)

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let pepperoniSpots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (82, 94, 13), (218, 96, 13), (176, 214, 13), (124, 222, 11),
    ]

    func drawToonBody() {
        Toon.shape(Toon.path("M47.1 64.2 A250 250 0 0 1 252.9 64.2 L150 292 Z"), fill: UIColor(hex: 0xF8C948))
        Toon.stroke(Toon.path("M44 68 A250 250 0 0 1 256 68"), width: 34)
        Toon.stroke(Toon.path("M44 68 A250 250 0 0 1 256 68"), width: 25, color: UIColor(hex: 0xD9913E))
        Toon.stroke(Toon.path("M60 58 A250 250 0 0 1 240 58"), width: 5, color: UIColor(hex: 0xEAB36A))
        for spot in Self.pepperoniSpots {
            Toon.shape(Toon.circle(spot.x, spot.y, spot.r), fill: UIColor(hex: 0xD8402F), lineWidth: Toon.medium)
            Toon.fill(Toon.circle(spot.x - spot.r * 0.3, spot.y - spot.r * 0.2, spot.r * 0.18), UIColor(hex: 0x8A2318))
            Toon.fill(Toon.circle(spot.x + spot.r * 0.35, spot.y + spot.r * 0.25, spot.r * 0.15), UIColor(hex: 0x8A2318))
        }
        Toon.shape(Toon.path("M138 250 L144 236 L150 252 Z"), fill: UIColor(hex: 0x7AB648), lineWidth: 2.5, shaded: false)
    }

    func drawToonFace(_ e: Expression) {
        let lift = -e.loudness * 6
        if e.blinking {
            Toon.eyeClosed(128, 122, 13)
            Toon.eyeClosed(172, 122, 13)
        } else {
            Toon.eyeOpen(128, 120, 15)
            Toon.eyeOpen(172, 120, 15)
        }
        Toon.stroke(Toon.path("M114 \(98 + lift) Q126 \(92 + lift) 138 \(98 + lift)"), width: Toon.fine)
        Toon.stroke(Toon.path("M162 \(98 + lift) Q174 \(92 + lift) 186 \(98 + lift)"), width: Toon.fine)
        Toon.cheek(108, 146, 10, color: UIColor(hex: 0xF08A5A))
        Toon.cheek(192, 146, 10, color: UIColor(hex: 0xF08A5A))
    }

    /// A pizzeria counter: the checkerboard tablecloth doubles as the ground, with a candle lit on the right.
    func drawBackdrop(in rect: CGRect, stage: CGRect) {
        Backdrop.scene(in: rect, stage: stage, palette: palette) { W, H, u in
            let gy = (H * 0.72).rounded(), R = W * 0.88
            Backdrop.checker(W, H, gy, u: u)
            Backdrop.candle(R - 10, gy + 10, H / 300, u: u)
        }
    }
}
