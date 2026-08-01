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

    // MARK: - Tunable geometry
    //
    // Everything `drawBody`/`drawEyes` position or size, gathered here so
    // the rig can be tuned by editing one block instead of hunting through
    // Bezier paths — and so `Tests/MonkSynthTests/RenderSweep.swift` can
    // mutate a single field on a copy of the character before rendering it,
    // without touching the drawing code at all (that's why this is a
    // `struct` held in a `var`, not baked in as `let` constants).
    struct Geometry {
        // --- Silhouette ---
        var crownX: CGFloat = 0.5
        var crownY: CGFloat = 0.04
        var crownRightX: CGFloat = 0.92
        var crownRightY: CGFloat = 0.46
        var crownC1X: CGFloat = 0.78
        var crownC1Y: CGFloat = 0.02
        var crownC2X: CGFloat = 0.92
        var crownC2Y: CGFloat = 0.20
        var shoulderY: CGFloat = 0.72
        /// Five scallops across the hem, right to left: each pair is the
        /// scallop's own bottom point and the control point that pulls it
        /// down into a wave. The last one's `x` is also `leftX` below — the
        /// point where the hem meets the vertical left edge.
        var scallops: [(x: CGFloat, controlX: CGFloat)] = [
            (0.76, 0.84), (0.60, 0.68), (0.44, 0.52), (0.28, 0.36), (0.08, 0.20),
        ]
        var scallopY: CGFloat = 0.72
        var scallopControlY: CGFloat = 0.94
        var leftX: CGFloat = 0.08
        var leftEdgeTopY: CGFloat = 0.46
        var crownLeftC1X: CGFloat = 0.08
        var crownLeftC1Y: CGFloat = 0.20
        var crownLeftC2X: CGFloat = 0.22
        var crownLeftC2Y: CGFloat = 0.02

        // --- Eyes ---
        var eyeLeftX: CGFloat = 0.40
        var eyeRightX: CGFloat = 0.60
        var eyeY: CGFloat = 0.34
        var eyeLashHalfWidthFraction: CGFloat = 0.03
        var eyeLashLineWidthFraction: CGFloat = 0.014
        var eyeWidthFraction: CGFloat = 0.052
        var eyeHeightFraction: CGFloat = 0.068
    }

    var geometry = Geometry()

    /// The ghost's whole silhouette — no separate head/body split, since a
    /// sheet ghost is one continuous shape from crown to hem.
    private func bodyPath(in stage: CGRect) -> UIBezierPath {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry
        let body = UIBezierPath()
        body.move(to: p(g.crownX, g.crownY))
        body.addCurve(to: p(g.crownRightX, g.crownRightY), controlPoint1: p(g.crownC1X, g.crownC1Y), controlPoint2: p(g.crownC2X, g.crownC2Y))
        body.addLine(to: p(g.crownRightX, g.shoulderY))
        for scallop in g.scallops {
            body.addQuadCurve(to: p(scallop.x, g.scallopY), controlPoint: p(scallop.controlX, g.scallopControlY))
        }
        body.addLine(to: p(g.leftX, g.leftEdgeTopY))
        body.addCurve(to: p(g.crownX, g.crownY), controlPoint1: p(g.crownLeftC1X, g.crownLeftC1Y), controlPoint2: p(g.crownLeftC2X, g.crownLeftC2Y))
        body.close()
        return body
    }

    func drawBody(in stage: CGRect) {
        let body = bodyPath(in: stage)
        Self.sheet.setFill()
        body.fill()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        for cx: CGFloat in [g.eyeLeftX, g.eyeRightX] {
            let c = point(cx, g.eyeY, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * g.eyeLashHalfWidthFraction, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * g.eyeLashHalfWidthFraction, y: c.y))
                lash.lineWidth = stage.width * g.eyeLashLineWidthFraction
                lash.lineCapStyle = .round
                Self.eye.setStroke()
                lash.stroke()
                continue
            }
            // Plain solid dark ovals — deliberately no white sclera, unlike
            // every other character — the simplest "hollow eye socket" cue
            // that reads as ghostly at a glance.
            let w = stage.width * g.eyeWidthFraction
            let h = stage.width * g.eyeHeightFraction
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            Self.eye.setFill()
            eye.fill()
        }
    }
}
