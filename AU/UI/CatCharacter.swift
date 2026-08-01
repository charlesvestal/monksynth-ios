import AVFoundation
import UIKit

/// A front-facing cat head over simple shoulders and a curled tail: sharp
/// triangular ears, a small pink nose, whiskers, and almond-shaped eyes
/// with vertical pupils. Its voice is upstream's "Tinley" factory preset,
/// verbatim — the single brightest of the six measured presets, matched to
/// the smallest/sharpest archetype of the six new characters (see
/// `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping). Placeholder art, like every character added by this task — the
/// user is replacing all character art with their own later, so this
/// deliberately stays a first pass: an instantly-readable silhouette and a
/// mouth that sweeps distinctly across the vowel range, nothing more.
struct CatCharacter: Character {
    let id = "cat"
    let displayName = "Cat"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let coat = UIColor(red: 0.88, green: 0.55, blue: 0.24, alpha: 1)
    private static let coatShadow = Self.coat.adjusted(brightnessScale: 0.78)
    private static let muzzle = UIColor(red: 0.97, green: 0.90, blue: 0.78, alpha: 1)
    private static let innerEar = UIColor(red: 0.93, green: 0.68, blue: 0.68, alpha: 1)
    private static let nose = UIColor(red: 0.85, green: 0.45, blue: 0.50, alpha: 1)

    // MARK: - Mouth anchors — small throughout, staying compact even at the
    // widest anchor: a cat's mouth barely shows.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.08, 0.10), (0.14, 0.14), (0.20, 0.10), (0.24, 0.06), (0.28, 0.04),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.20
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.345)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.28))
    // Enlarged from an original 0.155 — small relative to the torso below
    // it compared to every other head-and-shoulders character in the
    // roster (dog is 0.185, fire fighter 0.165) — so the head reads as
    // proportionate rather than undersized.
    private let headRadius: CGFloat = 0.175

    // MARK: - Tunable geometry
    //
    // Everything `drawBody`/`drawEyes` position or size, gathered here so
    // the rig can be tuned by editing one block instead of hunting through
    // Bezier paths — and so `Tests/MonkSynthTests/RenderSweep.swift` can
    // mutate a single field on a copy of the character before rendering it,
    // without touching the drawing code at all (that's why this is a
    // `struct` held in a `var`, not baked in as `let` constants). Most
    // fields are head-radius units measured from `headCenter` — i.e. the
    // value the original inline literal multiplied `headRadius` by; a few
    // (noted individually) are plain stage fractions instead, matching
    // whatever the original code did.
    struct Geometry {
        // --- Shoulders ---
        var bodyShoulderLeftX: CGFloat = 0.28
        var bodyShoulderY: CGFloat = 0.58
        var bodyHemLeftX: CGFloat = 0.10
        var bodyHemY: CGFloat = 0.99
        var bodyLeftControlX: CGFloat = 0.12
        var bodyLeftControlY: CGFloat = 0.78
        var bodyHemRightX: CGFloat = 0.90
        var bodyShoulderRightX: CGFloat = 0.72
        var bodyRightControlX: CGFloat = 0.88
        var bodyRightControlY: CGFloat = 0.78
        var bodyNeckX: CGFloat = 0.5
        /// Where the body's own collar band sits — the Y at which the
        /// shoulder curves stop converging and hand off to the flat-topped
        /// neck column (`neckWidth`) below, rather than to a single point.
        /// A previous version tapered the body all the way to one point
        /// here (with the neck patch below ALSO tapering toward that same
        /// point), which read as the whole torso rising to a sharp funnel
        /// point directly under the chin instead of a body with a neck.
        var bodyNeckY: CGFloat = 0.52
        /// How far in from each shoulder point, as a stage fraction, the
        /// shoulder-to-neck curve's own control point sits — with its Y
        /// pinned to `bodyNeckY` (the collar height), not `bodyShoulderY`
        /// (the shoulder height). Keeping the control point near the
        /// SHOULDER rather than centred under the chin (where the two
        /// curves' destinations already are) makes the shoulders read as
        /// spreading out then stepping up to the collar, instead of tapering
        /// inward in a concave wasp-waist pinch right where the neck meets
        /// the shoulders — what a centre-anchored control point produced.
        var shoulderNeckControlInset: CGFloat = 0.12

        // --- Neck ---
        /// How far above the head's own bottom edge the neck column's top
        /// sits, in head-radius units — deep enough to sit safely under the
        /// muzzle patch (drawn afterwards, on top), so the visible sliver
        /// below the muzzle reads as a neck continuing down into the
        /// shoulders rather than a gap of bare background between chin and
        /// shoulders.
        var neckTopOffsetRadii: CGFloat = 0.85
        /// Half-width of the neck column — used at BOTH its top edge (just
        /// under the head/muzzle) and its bottom edge (at the body's own
        /// collar, `bodyNeckY`), so it reads as a cylinder of constant
        /// width, noticeably narrower than the head, rather than a triangle
        /// tapering to a point. Chosen via `RenderSweep`
        /// (SWEEP_CHARACTER=cat, SWEEP_CONSTANT=neckWidth).
        var neckWidth: CGFloat = 0.095

        // --- Tail ---
        // Four cubic segments, base to tip and back to a second base point
        // close to the first — named `tailXxxCn` for the two control points
        // feeding into anchor point `tailXxx`, in path order. Both base
        // points (`tailStartX/Y`, `tailEndX/Y`) are pulled well INSIDE the
        // torso's own silhouette (verified against `bodyShoulderRightX`'s
        // curve — at y=0.88 the body's own right edge is at x≈0.88, well
        // right of 0.74) rather than sitting right at its edge: an earlier
        // version rooted the tail almost exactly ON the body's own outline,
        // which read as the tail starting detached next to the torso
        // instead of growing out of it.
        var tailStartX: CGFloat = 0.74
        var tailStartY: CGFloat = 0.88
        var tailTipX: CGFloat = 0.99
        var tailTipY: CGFloat = 0.55
        var tailTipC1X: CGFloat = 0.92
        var tailTipC1Y: CGFloat = 0.82
        var tailTipC2X: CGFloat = 1.00
        var tailTipC2Y: CGFloat = 0.70
        var tailInnerX: CGFloat = 0.88
        var tailInnerY: CGFloat = 0.42
        var tailInnerC1X: CGFloat = 0.98
        var tailInnerC1Y: CGFloat = 0.40
        var tailInnerC2X: CGFloat = 0.92
        var tailInnerC2Y: CGFloat = 0.36
        var tailMidX: CGFloat = 0.94
        var tailMidY: CGFloat = 0.60
        var tailMidC1X: CGFloat = 0.92
        var tailMidC1Y: CGFloat = 0.42
        var tailMidC2X: CGFloat = 0.96
        var tailMidC2Y: CGFloat = 0.50
        var tailEndX: CGFloat = 0.70
        var tailEndY: CGFloat = 0.90
        var tailEndC1X: CGFloat = 0.94
        var tailEndC1Y: CGFloat = 0.74
        var tailEndC2X: CGFloat = 0.82
        var tailEndC2Y: CGFloat = 0.90

        // --- Ears ---
        var earBase1XRadii: CGFloat = 0.15
        var earBase1YRadii: CGFloat = 0.85
        var earBase2XRadii: CGFloat = 0.85
        var earBase2YRadii: CGFloat = 0.45
        var earTipXRadii: CGFloat = 0.55
        var earTipYRadii: CGFloat = 1.65
        var earInnerScale: CGFloat = 0.55
        var earInnerBase1XRadii: CGFloat = 0.24
        var earInnerBase1YRadii: CGFloat = 0.80
        var earInnerBase2XRadii: CGFloat = 0.68
        var earInnerBase2YRadii: CGFloat = 0.55
        var earInnerTipXRadii: CGFloat = 0.50
        var earInnerTipYBaseRadii: CGFloat = 0.85
        var earInnerTipYScaleRadii: CGFloat = 0.80

        // --- Muzzle ---
        var muzzleOffsetRadii: CGFloat = 0.55
        var muzzleWidthRadii: CGFloat = 1.35
        var muzzleHeightRadii: CGFloat = 0.95

        // --- Nose ---
        var noseYOffset: CGFloat = 0.03
        var noseWidthFraction: CGFloat = 0.028
        var noseHalfHeightScale: CGFloat = 0.6
        var noseTipHeightScale: CGFloat = 0.7

        // --- Whiskers ---
        var whiskerInnerRadii: CGFloat = 0.5
        var whiskerOuterRadii: CGFloat = 1.25
        var whiskerDys: [CGFloat] = [-0.02, 0.0, 0.02]
        var whiskerStartYOffset: CGFloat = -0.01
        var whiskerEndYOffset: CGFloat = -0.02
        var whiskerLineWidthFraction: CGFloat = 0.004

        // --- Eyes ---
        var eyeXOffset: CGFloat = 0.06
        var eyeYOffset: CGFloat = 0.01
        var eyeLashHalfWidthFraction: CGFloat = 0.03
        var eyeLashLineWidthFraction: CGFloat = 0.011
        var eyeHalfWidthFraction: CGFloat = 0.052
        var eyeHalfHeightFraction: CGFloat = 0.036
        var pupilWidthScale: CGFloat = 0.22
        var pupilHeightScale: CGFloat = 1.55
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Shoulders.
        let body = UIBezierPath()
        body.move(to: p(g.bodyShoulderLeftX, g.bodyShoulderY))
        body.addQuadCurve(to: p(g.bodyHemLeftX, g.bodyHemY), controlPoint: p(g.bodyLeftControlX, g.bodyLeftControlY))
        body.addLine(to: p(g.bodyHemRightX, g.bodyHemY))
        body.addQuadCurve(to: p(g.bodyShoulderRightX, g.bodyShoulderY), controlPoint: p(g.bodyRightControlX, g.bodyRightControlY))
        body.addQuadCurve(to: p(g.bodyNeckX + g.neckWidth, g.bodyNeckY),
                           controlPoint: p(g.bodyShoulderRightX - g.shoulderNeckControlInset, g.bodyNeckY))
        body.addLine(to: p(g.bodyNeckX - g.neckWidth, g.bodyNeckY))
        body.addQuadCurve(to: p(g.bodyShoulderLeftX, g.bodyShoulderY),
                           controlPoint: p(g.bodyShoulderLeftX + g.shoulderNeckControlInset, g.bodyNeckY))
        body.close()
        Self.coat.setFill()
        body.fill()

        // Neck: a COLUMN of constant width (`neckWidth`, reused at both
        // edges) bridging the head's own bottom edge down to the body's own
        // collar, so the head reads as attached to a real neck rather than
        // a coat funnelling to a point under the chin. Coloured with the
        // same darker shade the tail/ears use — distinct from both the
        // head and the shoulders below (both plain `coat`) — so the eye
        // reads head → neck → shoulders as three parts instead of one
        // continuous fur-coloured cone. Drawn before the head/muzzle so
        // they cover its top portion cleanly, leaving only the sliver below
        // the muzzle visible — the same technique `MonkCharacter` uses for
        // its own neck.
        let neckTop = headCenter.fy + headRadius * g.neckTopOffsetRadii
        let neck = UIBezierPath()
        neck.move(to: p(headCenter.fx - g.neckWidth, neckTop))
        neck.addLine(to: p(headCenter.fx - g.neckWidth, g.bodyNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckWidth, g.bodyNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckWidth, neckTop))
        neck.close()
        Self.coatShadow.setFill()
        neck.fill()

        // Tail: curls up from the body's base along the right edge — a cat-
        // specific cue no other character in the roster has.
        let tail = UIBezierPath()
        tail.move(to: p(g.tailStartX, g.tailStartY))
        tail.addCurve(to: p(g.tailTipX, g.tailTipY), controlPoint1: p(g.tailTipC1X, g.tailTipC1Y), controlPoint2: p(g.tailTipC2X, g.tailTipC2Y))
        tail.addCurve(to: p(g.tailInnerX, g.tailInnerY), controlPoint1: p(g.tailInnerC1X, g.tailInnerC1Y), controlPoint2: p(g.tailInnerC2X, g.tailInnerC2Y))
        tail.addCurve(to: p(g.tailMidX, g.tailMidY), controlPoint1: p(g.tailMidC1X, g.tailMidC1Y), controlPoint2: p(g.tailMidC2X, g.tailMidC2Y))
        tail.addCurve(to: p(g.tailEndX, g.tailEndY), controlPoint1: p(g.tailEndC1X, g.tailEndC1Y), controlPoint2: p(g.tailEndC2X, g.tailEndC2Y))
        tail.close()
        Self.coatShadow.setFill()
        tail.fill()

        // Ears: sharp triangles set close on top of the head, with a pink
        // inner triangle — the classic cat silhouette cue.
        for sign: CGFloat in [-1, 1] {
            let base1 = point(headCenter.fx + sign * headRadius * g.earBase1XRadii, headCenter.fy - headRadius * g.earBase1YRadii, in: stage)
            let base2 = point(headCenter.fx + sign * headRadius * g.earBase2XRadii, headCenter.fy - headRadius * g.earBase2YRadii, in: stage)
            let tip = point(headCenter.fx + sign * headRadius * g.earTipXRadii, headCenter.fy - headRadius * g.earTipYRadii, in: stage)
            let ear = UIBezierPath()
            ear.move(to: base1)
            ear.addLine(to: tip)
            ear.addLine(to: base2)
            ear.close()
            Self.coat.setFill()
            ear.fill()

            let innerBase1 = point(headCenter.fx + sign * headRadius * g.earInnerBase1XRadii, headCenter.fy - headRadius * g.earInnerBase1YRadii, in: stage)
            let innerBase2 = point(headCenter.fx + sign * headRadius * g.earInnerBase2XRadii, headCenter.fy - headRadius * g.earInnerBase2YRadii, in: stage)
            let innerTip = point(headCenter.fx + sign * headRadius * g.earInnerTipXRadii, headCenter.fy - headRadius * (g.earInnerTipYBaseRadii + g.earInnerTipYScaleRadii * g.earInnerScale), in: stage)
            let inner = UIBezierPath()
            inner.move(to: innerBase1)
            inner.addLine(to: innerTip)
            inner.addLine(to: innerBase2)
            inner.close()
            Self.innerEar.setFill()
            inner.fill()
        }

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.coat.setFill()
        head.fill()

        // Pale muzzle patch, lower-front of the face.
        let muzzleCenter = point(headCenter.fx, headCenter.fy + headRadius * g.muzzleOffsetRadii, in: stage)
        let muzzleW = stage.width * headRadius * g.muzzleWidthRadii
        let muzzleH = stage.width * headRadius * g.muzzleHeightRadii
        let muzzle = UIBezierPath(ovalIn: CGRect(x: muzzleCenter.x - muzzleW / 2, y: muzzleCenter.y - muzzleH / 2,
                                                  width: muzzleW, height: muzzleH))
        Self.muzzle.setFill()
        muzzle.fill()

        // Small triangular nose, just above the mouth aperture.
        let noseCenter = point(headCenter.fx, mouthCentre.fy - g.noseYOffset, in: stage)
        let noseW = stage.width * g.noseWidthFraction
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: noseCenter.x - noseW, y: noseCenter.y - noseW * g.noseHalfHeightScale))
        nose.addLine(to: CGPoint(x: noseCenter.x + noseW, y: noseCenter.y - noseW * g.noseHalfHeightScale))
        nose.addLine(to: CGPoint(x: noseCenter.x, y: noseCenter.y + noseW * g.noseTipHeightScale))
        nose.close()
        Self.nose.setFill()
        nose.fill()

        // Whiskers: three short lines each side, from the muzzle outward.
        for sign: CGFloat in [-1, 1] {
            for dy in g.whiskerDys {
                let start = point(headCenter.fx + sign * headRadius * g.whiskerInnerRadii, mouthCentre.fy + g.whiskerStartYOffset + dy, in: stage)
                let end = point(headCenter.fx + sign * headRadius * g.whiskerOuterRadii, mouthCentre.fy + g.whiskerEndYOffset + dy, in: stage)
                let whisker = UIBezierPath()
                whisker.move(to: start)
                whisker.addLine(to: end)
                whisker.lineWidth = stage.width * g.whiskerLineWidthFraction
                whisker.lineCapStyle = .round
                Theme.robeShadow.withAlphaComponent(0.7).setStroke()
                whisker.stroke()
            }
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy - g.eyeYOffset, in: stage)
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
            // Almond shape with pointed corners — a cat-specific eye
            // silhouette, distinct from every round-eyed character.
            let w = stage.width * g.eyeHalfWidthFraction
            let h = stage.width * g.eyeHalfHeightFraction
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - w, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), controlPoint: CGPoint(x: c.x, y: c.y - h))
            eye.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), controlPoint: CGPoint(x: c.x, y: c.y + h))
            eye.close()
            UIColor(red: 0.62, green: 0.78, blue: 0.30, alpha: 1).setFill()
            eye.fill()

            // Vertical slit pupil — the single strongest "cat, not any
            // other character" eye cue.
            let slitW = w * g.pupilWidthScale
            let slitH = h * g.pupilHeightScale
            let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - slitW / 2, y: c.y - slitH / 2, width: slitW, height: slitH))
            UIColor.black.setFill()
            pupil.fill()
        }
    }
}
