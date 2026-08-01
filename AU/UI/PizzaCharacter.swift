import AVFoundation
import UIKit

/// A single pizza slice, point-down: a thick golden crust along the top
/// edge, a yellow cheese body, and a scatter of pepperoni rounds — a
/// deliberately non-humanoid, non-animal silhouette so it reads as
/// something entirely different from the other eleven characters at a
/// glance. Its voice is upstream's "Ngawang" factory preset, verbatim —
/// pizza has no natural vocal pitch of its own (it's a slice of food), so
/// per the task it simply absorbs whichever preset is left over once the
/// other five characters are matched by archetype brightness (see
/// `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping). Placeholder art, like every character added by this task — the
/// user is replacing all character art with their own later, so this
/// deliberately stays a first pass: an instantly-readable silhouette and a
/// mouth that sweeps distinctly across the vowel range, nothing more.
struct PizzaCharacter: Character {
    let id = "pizza"
    let displayName = "Pizza"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let cheese = UIColor(red: 0.94, green: 0.74, blue: 0.22, alpha: 1)
    private static let crust = UIColor(red: 0.80, green: 0.56, blue: 0.28, alpha: 1)
    private static let crustShadow = Self.crust.adjusted(brightnessScale: 0.75)
    private static let pepperoni = UIColor(red: 0.72, green: 0.20, blue: 0.16, alpha: 1)

    // MARK: - Mouth anchors — a big impish grin that swells then eases back,
    // a distinct hump shape from every other character's own hump/flat/
    // monotonic trend.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.24, 0.10), (0.36, 0.20), (0.46, 0.30), (0.52, 0.22), (0.56, 0.14),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.26
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.56)

    /// The slice's own silhouette: a wide top edge tapering to a point at
    /// the bottom — used both as the cheese fill and as a clip for the
    /// crust/pepperoni layers so neither can spill past the outline.
    private func slicePath(in stage: CGRect) -> UIBezierPath {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let slice = UIBezierPath()
        slice.move(to: p(0.5, 0.97))
        slice.addQuadCurve(to: p(0.09, 0.16), controlPoint: p(0.20, 0.68))
        slice.addQuadCurve(to: p(0.91, 0.16), controlPoint: p(0.5, 0.06))
        slice.addQuadCurve(to: p(0.5, 0.97), controlPoint: p(0.80, 0.68))
        slice.close()
        return slice
    }

    func drawBody(in stage: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let slice = slicePath(in: stage)
        Self.cheese.setFill()
        slice.fill()

        context.saveGState()
        slice.addClip()
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Crust: a thick band along the top edge only.
        let crustBand = UIBezierPath()
        crustBand.move(to: p(0.02, 0.02))
        crustBand.addLine(to: p(0.98, 0.02))
        crustBand.addLine(to: p(0.91, 0.24))
        crustBand.addQuadCurve(to: p(0.09, 0.24), controlPoint: p(0.5, 0.14))
        crustBand.close()
        Self.crust.setFill()
        crustBand.fill()
        Self.crustShadow.setStroke()
        crustBand.lineWidth = stage.width * 0.01
        crustBand.stroke()

        // Pepperoni: three rounds scattered across the wider, upper-middle
        // part of the slice, well clear of the crust band and the mouth's
        // own local frame.
        let pepperoniSpots: [(fx: CGFloat, fy: CGFloat, r: CGFloat)] = [
            (0.30, 0.34, 0.075), (0.66, 0.30, 0.065), (0.50, 0.42, 0.07),
        ]
        for spot in pepperoniSpots {
            let c = p(spot.fx, spot.fy)
            let r = stage.width * spot.r
            let round = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Self.pepperoni.setFill()
            round.fill()
            // A few darker speckles per pepperoni for a little texture.
            for dx: CGFloat in [-0.35, 0.3] {
                let sc = CGPoint(x: c.x + dx * r, y: c.y + dx * r * 0.4)
                let sr = r * 0.16
                let speck = UIBezierPath(ovalIn: CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2))
                Self.pepperoni.adjusted(brightnessScale: 0.6).setFill()
                speck.fill()
            }
        }
        context.restoreGState()

        // Slice outline.
        Self.crustShadow.withAlphaComponent(0.6).setStroke()
        slice.lineWidth = stage.width * 0.008
        slice.stroke()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [0.40, 0.60] {
            let c = point(cx, 0.40, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.032, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.032, y: c.y))
                lash.lineWidth = stage.width * 0.013
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * 0.042
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            UIColor.white.setFill()
            eye.fill()
            let pupilR = r * 0.55
            let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
            UIColor.black.setFill()
            pupil.fill()
        }
    }
}
