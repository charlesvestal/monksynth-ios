import AVFoundation
import UIKit

/// A classic sheet ghost: a single rounded blob (no separate head/body —
/// the whole silhouette IS the ghost), a domed top, and a wavy scalloped
/// hem. Its voice is upstream's "Rabten" factory preset, verbatim — the
/// second-darkest of the six measured presets, matched to one of the two
/// largest/deepest archetypes among the six new characters (see
/// `FactoryVoiceTable`'s doc comment for the measurement, the full mapping,
/// and the honest call-out that Rabten is also upstream's own all-defaults
/// patch — the most vanilla-sounding of the six — which reads a little
/// anticlimactic for an ostensibly "spooky" character even though the
/// numbers back the pairing). Placeholder art, like every character added
/// by this task — the user is replacing all character art with their own
/// later, so this deliberately stays a first pass: an instantly-readable
/// silhouette and a mouth that sweeps distinctly across the vowel range,
/// nothing more.
struct GhostCharacter: Character {
    let id = "ghost"
    let displayName = "Ghost"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let sheet = UIColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1)
    private static let sheetShadow = Self.sheet.adjusted(brightnessScale: 0.90)
    private static let eye = UIColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1)

    // MARK: - Mouth anchors — a round, breathy "oOoo" moan: stays roughly
    // round throughout with only a small swell, unlike every other
    // character's clearer narrow-to-wide (or wide-to-narrow) trend.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.30, 0.30), (0.34, 0.36), (0.36, 0.38), (0.34, 0.34), (0.30, 0.28),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.22
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.56)

    /// The ghost's whole silhouette — no separate head/body split, since a
    /// sheet ghost is one continuous shape from crown to hem.
    private func bodyPath(in stage: CGRect) -> UIBezierPath {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let body = UIBezierPath()
        body.move(to: p(0.5, 0.04))
        body.addCurve(to: p(0.92, 0.46), controlPoint1: p(0.78, 0.02), controlPoint2: p(0.92, 0.20))
        body.addLine(to: p(0.92, 0.72))
        // Four scallops across the hem, right to left.
        body.addQuadCurve(to: p(0.76, 0.72), controlPoint: p(0.84, 0.94))
        body.addQuadCurve(to: p(0.60, 0.72), controlPoint: p(0.68, 0.94))
        body.addQuadCurve(to: p(0.44, 0.72), controlPoint: p(0.52, 0.94))
        body.addQuadCurve(to: p(0.28, 0.72), controlPoint: p(0.36, 0.94))
        body.addQuadCurve(to: p(0.08, 0.72), controlPoint: p(0.20, 0.94))
        body.addLine(to: p(0.08, 0.46))
        body.addCurve(to: p(0.5, 0.04), controlPoint1: p(0.08, 0.20), controlPoint2: p(0.22, 0.02))
        body.close()
        return body
    }

    func drawBody(in stage: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let body = bodyPath(in: stage)
        Self.sheet.setFill()
        body.fill()

        // A soft shading fold down one side, clipped to the body's own
        // silhouette so it can never spill past the outline — the same
        // technique `MonkCharacter`'s robe fold and `CowCharacter`'s shoulder
        // patch use.
        context.saveGState()
        body.addClip()
        let fold = UIBezierPath()
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        fold.move(to: p(0.68, 0.10))
        fold.addQuadCurve(to: p(0.80, 0.60), controlPoint: p(0.86, 0.32))
        fold.addQuadCurve(to: p(0.66, 0.88), controlPoint: p(0.82, 0.78))
        fold.addQuadCurve(to: p(0.58, 0.50), controlPoint: p(0.60, 0.70))
        fold.addQuadCurve(to: p(0.68, 0.10), controlPoint: p(0.52, 0.28))
        fold.close()
        Self.sheetShadow.withAlphaComponent(0.55).setFill()
        fold.fill()
        context.restoreGState()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [0.40, 0.60] {
            let c = point(cx, 0.34, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.03, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.03, y: c.y))
                lash.lineWidth = stage.width * 0.014
                lash.lineCapStyle = .round
                Self.eye.setStroke()
                lash.stroke()
                continue
            }
            // Plain solid dark ovals — deliberately no white sclera, unlike
            // every other character — the simplest "hollow eye socket" cue
            // that reads as ghostly at a glance.
            let w = stage.width * 0.052
            let h = stage.width * 0.068
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            Self.eye.setFill()
            eye.fill()
        }
    }
}
