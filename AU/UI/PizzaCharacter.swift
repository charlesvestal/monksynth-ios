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

    // MARK: - Tunable geometry
    //
    // Everything `drawBody`/`drawEyes` position or size, gathered here so
    // the rig can be tuned by editing one block instead of hunting through
    // Bezier paths — and so `Tests/MonkSynthTests/RenderSweep.swift` can
    // mutate a single field on a copy of the character before rendering it,
    // without touching the drawing code at all (that's why this is a
    // `struct` held in a `var`, not baked in as `let` constants).
    struct Geometry {
        // --- Slice silhouette ---
        var apexX: CGFloat = 0.5
        var apexY: CGFloat = 0.97
        var leftCrustX: CGFloat = 0.09
        var leftCrustY: CGFloat = 0.16
        var leftControlX: CGFloat = 0.20
        var leftControlY: CGFloat = 0.68
        var rightCrustX: CGFloat = 0.91
        var rightCrustY: CGFloat = 0.16
        var topControlY: CGFloat = 0.06
        var rightControlX: CGFloat = 0.80
        var rightControlY: CGFloat = 0.68

        // --- Crust band ---
        var crustTopLeftX: CGFloat = 0.02
        var crustTopY: CGFloat = 0.02
        var crustTopRightX: CGFloat = 0.98
        var crustInnerRightX: CGFloat = 0.91
        var crustInnerY: CGFloat = 0.24
        var crustInnerControlY: CGFloat = 0.14
        var crustInnerLeftX: CGFloat = 0.09
        var crustStrokeLineWidthFraction: CGFloat = 0.01

        // --- Pepperoni ---
        // Moved clear of the eyes (`eyeY` 0.40, x 0.40/0.60) and the mouth
        // aperture's own box (centred (0.5, 0.56)) — an earlier layout had
        // one pepperoni overlapping each eye and a THIRD centred between
        // them, which read as a nose sitting on the face rather than a
        // topping on the slice. These sit to the sides at eye height and
        // below the mouth instead, so the face reads first and the
        // toppings read second.
        var pepperoniSpots: [(fx: CGFloat, fy: CGFloat, r: CGFloat)] = [
            (0.26, 0.46, 0.075), (0.74, 0.42, 0.065), (0.50, 0.80, 0.075),
        ]
        var speckleDxs: [CGFloat] = [-0.35, 0.3]
        var speckleDyScale: CGFloat = 0.4
        var speckleRadiusScale: CGFloat = 0.16
        var speckleBrightnessScale: CGFloat = 0.6

        // --- Outline ---
        var outlineAlpha: CGFloat = 0.6
        var outlineLineWidthFraction: CGFloat = 0.008

        // --- Eyes ---
        var eyeLeftX: CGFloat = 0.40
        var eyeRightX: CGFloat = 0.60
        var eyeY: CGFloat = 0.40
        var eyeLashHalfWidthFraction: CGFloat = 0.032
        var eyeLashLineWidthFraction: CGFloat = 0.013
        var eyeRadiusFraction: CGFloat = 0.042
        var pupilRadiusScale: CGFloat = 0.55
    }

    var geometry = Geometry()

    /// The slice's own silhouette: a wide top edge tapering to a point at
    /// the bottom — used both as the cheese fill and as a clip for the
    /// crust/pepperoni layers so neither can spill past the outline.
    private func slicePath(in stage: CGRect) -> UIBezierPath {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry
        let slice = UIBezierPath()
        slice.move(to: p(g.apexX, g.apexY))
        slice.addQuadCurve(to: p(g.leftCrustX, g.leftCrustY), controlPoint: p(g.leftControlX, g.leftControlY))
        slice.addQuadCurve(to: p(g.rightCrustX, g.rightCrustY), controlPoint: p(g.apexX, g.topControlY))
        slice.addQuadCurve(to: p(g.apexX, g.apexY), controlPoint: p(g.rightControlX, g.rightControlY))
        slice.close()
        return slice
    }

    func drawBody(in stage: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let g = geometry
        let slice = slicePath(in: stage)
        Self.cheese.setFill()
        slice.fill()

        context.saveGState()
        slice.addClip()
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Crust: a thick band along the top edge only.
        let crustBand = UIBezierPath()
        crustBand.move(to: p(g.crustTopLeftX, g.crustTopY))
        crustBand.addLine(to: p(g.crustTopRightX, g.crustTopY))
        crustBand.addLine(to: p(g.crustInnerRightX, g.crustInnerY))
        crustBand.addQuadCurve(to: p(g.crustInnerLeftX, g.crustInnerY), controlPoint: p(g.apexX, g.crustInnerControlY))
        crustBand.close()
        Self.crust.setFill()
        crustBand.fill()
        Self.crustShadow.setStroke()
        crustBand.lineWidth = stage.width * g.crustStrokeLineWidthFraction
        crustBand.stroke()

        // Pepperoni: three rounds scattered across the slice, kept clear of
        // the eyes and mouth so the face reads first.
        for spot in g.pepperoniSpots {
            let c = p(spot.fx, spot.fy)
            let r = stage.width * spot.r
            let round = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Self.pepperoni.setFill()
            round.fill()
            // A few darker speckles per pepperoni for a little texture.
            for dx in g.speckleDxs {
                let sc = CGPoint(x: c.x + dx * r, y: c.y + dx * r * g.speckleDyScale)
                let sr = r * g.speckleRadiusScale
                let speck = UIBezierPath(ovalIn: CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2))
                Self.pepperoni.adjusted(brightnessScale: g.speckleBrightnessScale).setFill()
                speck.fill()
            }
        }
        context.restoreGState()

        // Slice outline.
        Self.crustShadow.withAlphaComponent(g.outlineAlpha).setStroke()
        slice.lineWidth = stage.width * g.outlineLineWidthFraction
        slice.stroke()
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
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * g.eyeRadiusFraction
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            UIColor.white.setFill()
            eye.fill()
            let pupilR = r * g.pupilRadiusScale
            let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
            UIColor.black.setFill()
            pupil.fill()
        }
    }
}
