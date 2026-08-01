import AVFoundation
import UIKit

/// A fire fighter: a red dome helmet with a wide flared brim and a gold
/// front badge, over a bright safety-yellow turnout coat with a reflective
/// stripe. Its voice is upstream's "Dorje" factory preset, verbatim — one
/// of the two middle-brightness presets of the six measured, matched to the
/// burlier, deeper-voiced of the two remaining archetypes among the six new
/// characters, once dog/ghost (darkest) and cat (brightest) were placed
/// (see `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping). Placeholder art, like every character added by this task — the
/// user is replacing all character art with their own later, so this
/// deliberately stays a first pass: an instantly-readable silhouette and a
/// mouth that sweeps distinctly across the vowel range, nothing more.
struct FireFighterCharacter: Character {
    let id = "firefighter"
    let displayName = "Fire Fighter"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let helmet = UIColor(red: 0.72, green: 0.14, blue: 0.12, alpha: 1)
    private static let helmetShadow = Self.helmet.adjusted(brightnessScale: 0.72)
    private static let badge = UIColor(red: 0.86, green: 0.70, blue: 0.24, alpha: 1)
    private static let coat = UIColor(red: 0.96, green: 0.78, blue: 0.14, alpha: 1)
    private static let stripe = UIColor(white: 0.92, alpha: 1)
    private static let skin = Theme.skin

    // MARK: - Mouth anchors — a commanding, wide-open shout: swells quickly
    // then eases, a distinct hump shape from every other character's own
    // trend.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.16, 0.18), (0.26, 0.26), (0.36, 0.32), (0.44, 0.24), (0.48, 0.16),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.25
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.44)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.34))
    private let headRadius: CGFloat = 0.165

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
        // --- Coat ---
        var coatShoulderLeftX: CGFloat = 0.24
        var coatShoulderY: CGFloat = 0.62
        var coatHemLeftX: CGFloat = 0.06
        var coatHemY: CGFloat = 0.99
        var coatLeftControlX: CGFloat = 0.08
        var coatLeftControlY: CGFloat = 0.82
        var coatHemRightX: CGFloat = 0.94
        var coatShoulderRightX: CGFloat = 0.76
        var coatRightControlX: CGFloat = 0.92
        var coatRightControlY: CGFloat = 0.82
        var coatNeckX: CGFloat = 0.5
        /// Where the coat's own collar band sits — the Y at which the
        /// shoulder curves stop converging and hand off to the flat-topped
        /// neck column (`neckWidth`) below. A SECOND prior attempt (after
        /// the original 0.56) collapsed this to a single point at 0.50,
        /// which — combined with the neck patch tapering to that same
        /// point — made the whole coat read as a funnel/cone balanced
        /// point-up under the chin instead of a body with a neck. Restored
        /// to a real collar: the shoulder curves now land on the two edges
        /// of `neckWidth` at this Y, not on one shared point.
        var coatNeckY: CGFloat = 0.50
        /// How far in from each shoulder point (`coatShoulderLeftX`/
        /// `coatShoulderRightX`), as a stage fraction, the shoulder-to-neck
        /// curve's own control point sits — with its Y pinned to
        /// `coatNeckY`, the same height as the collar itself (not
        /// `coatShoulderY`, the shoulder height). Keeping the control point
        /// near the SHOULDER (not centred under the chin, where the two
        /// curves' destinations already are) is what makes the curve drop
        /// to collar height while still close to full shoulder width, then
        /// stay flat over to the neck — the shoulders read as "spreading
        /// out then stepping up to the collar", not tapering inward in a
        /// concave wasp-waist pinch. A centred control point (an earlier
        /// version's approach) pulled the curve in toward the midline far
        /// too early, carving a concave notch into the silhouette right
        /// where the neck meets the shoulders.
        var shoulderNeckControlInset: CGFloat = 0.12

        // --- Neck ---
        /// How far above the head's own bottom edge the skin neck column's
        /// top sits, in head-radius units — kept slightly INSIDE the head
        /// circle (rather than starting exactly at its edge) so there is no
        /// seam between head fill and neck fill.
        var neckTopOffsetRadii: CGFloat = 0.90
        /// Half-width of the neck column — used at BOTH its top edge (just
        /// under the head) and its bottom edge (at the coat's own collar,
        /// `coatNeckY`), so the column reads as a cylinder of constant
        /// width rather than a triangle tapering to a point. This is what
        /// actually makes it a *neck* rather than a funnel: an earlier
        /// version tapered this patch down to a single point at the coat's
        /// V-neck apex, which — even though the patch itself wasn't a
        /// notch-cornered rectangle — still read as the coat rising to a
        /// sharp spike directly under the chin. Chosen via
        /// `RenderSweep` (SWEEP_CHARACTER=firefighter,
        /// SWEEP_CONSTANT=neckWidth): noticeably narrower than the head
        /// (head half-width ≈ 0.165) but clearly wider than a point.
        var neckWidth: CGFloat = 0.075

        // --- Stripe ---
        var stripeTopY: CGFloat = 0.78
        var stripeBottomY: CGFloat = 0.86
        var stripeLeftX: CGFloat = 0.10
        var stripeRightX: CGFloat = 0.90

        // --- Helmet brim ---
        /// Vertical centre of the flared brim, in head-radius units above
        /// head centre — raised from an original 0.05 (barely above head
        /// centre, i.e. at eyebrow height) to sit right at the dome's own
        /// lower edge (`domeYInsetRadii` minus `domeHeightRadii`), so the
        /// brim reads as the flared rim where the dome ends instead of an
        /// ellipse slicing straight across the middle of the face.
        var brimCenterOffsetRadii: CGFloat = 0.32
        var brimWidthRadii: CGFloat = 2.7
        /// Shrunk from an original 0.62 so the brim's own lower edge stays
        /// comfortably above the eyes now that it sits much higher.
        var brimHeightRadii: CGFloat = 0.36

        // --- Helmet dome ---
        var domeXInsetRadii: CGFloat = 1.06
        var domeYInsetRadii: CGFloat = 1.30
        var domeWidthRadii: CGFloat = 2.12
        /// *** How tall the dome is ***, in head-radius units. An original
        /// 1.55 — combined with `domeYInsetRadii` of 1.30 — put the dome's
        /// own lower edge 0.25 head-radii BELOW head centre, well past the
        /// eyebrow line, so the helmet's fill painted directly over where
        /// `drawEyes` draws the eyes. Shrunk to 0.98 so the dome's lower
        /// edge sits at `domeYInsetRadii - domeHeightRadii` = 0.32
        /// head-radii ABOVE centre — clearly above `eyeYOffset` — leaving
        /// the whole face, eyes included, unobstructed below it.
        var domeHeightRadii: CGFloat = 0.98

        // --- Knob ---
        /// Raised very slightly from an original 1.28 so it still pokes out
        /// past the dome's own (now-shorter) top — unchanged in practice
        /// since `domeYInsetRadii` itself didn't move.
        var knobOffsetRadii: CGFloat = 1.28
        var knobRadiusFraction: CGFloat = 0.018

        // --- Badge ---
        /// Re-centred on the dome's own new, shorter band (0.32...1.30
        /// head-radii above centre — midpoint ~0.81) from an original 0.55,
        /// which sat below the dome's new lower edge and would otherwise
        /// float on bare skin instead of on the helmet.
        var badgeOffsetRadii: CGFloat = 0.81
        var badgeWidthFraction: CGFloat = 0.09
        var badgeHeightFraction: CGFloat = 0.06
        var badgeStrokeLineWidthFraction: CGFloat = 0.005

        // --- Eyes ---
        var eyeXOffset: CGFloat = 0.065
        var eyeYOffset: CGFloat = 0.01
        var eyeHalfWidthFraction: CGFloat = 0.048
        var eyeCurveDepthOpenFraction: CGFloat = 0.024
        var eyeCurveDepthBlinkFraction: CGFloat = 0.010
        var eyeLineWidthFraction: CGFloat = 0.015
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Turnout coat: bright safety yellow with a reflective stripe —
        // the colour alone is a strong, unambiguous cue against the dark
        // background.
        let body = UIBezierPath()
        body.move(to: p(g.coatShoulderLeftX, g.coatShoulderY))
        body.addQuadCurve(to: p(g.coatHemLeftX, g.coatHemY), controlPoint: p(g.coatLeftControlX, g.coatLeftControlY))
        body.addLine(to: p(g.coatHemRightX, g.coatHemY))
        body.addQuadCurve(to: p(g.coatShoulderRightX, g.coatShoulderY), controlPoint: p(g.coatRightControlX, g.coatRightControlY))
        body.addQuadCurve(to: p(g.coatNeckX + g.neckWidth, g.coatNeckY),
                           controlPoint: p(g.coatShoulderRightX - g.shoulderNeckControlInset, g.coatNeckY))
        body.addLine(to: p(g.coatNeckX - g.neckWidth, g.coatNeckY))
        body.addQuadCurve(to: p(g.coatShoulderLeftX, g.coatShoulderY),
                           controlPoint: p(g.coatShoulderLeftX + g.shoulderNeckControlInset, g.coatNeckY))
        body.close()
        Self.coat.setFill()
        body.fill()

        // Neck: a skin-coloured COLUMN of constant width (`neckWidth`,
        // reused at both edges) bridging the head's own bottom edge down to
        // the coat's own collar, so the head reads as attached to a real
        // neck rather than floating, and the coat reads as shoulders
        // spreading from the neck's base rather than a funnel rising to a
        // point under the chin — the same technique `MonkCharacter` uses
        // for its own neck.
        let neckTop = headCenter.fy + headRadius * g.neckTopOffsetRadii
        let neck = UIBezierPath()
        neck.move(to: p(headCenter.fx - g.neckWidth, neckTop))
        neck.addLine(to: p(headCenter.fx - g.neckWidth, g.coatNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckWidth, g.coatNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckWidth, neckTop))
        neck.close()
        Self.skin.setFill()
        neck.fill()

        let stripe = UIBezierPath()
        stripe.move(to: p(g.stripeLeftX, g.stripeTopY))
        stripe.addLine(to: p(g.stripeRightX, g.stripeTopY))
        stripe.addLine(to: p(g.stripeRightX, g.stripeBottomY))
        stripe.addLine(to: p(g.stripeLeftX, g.stripeBottomY))
        stripe.close()
        Self.stripe.setFill()
        stripe.fill()

        // Helmet brim: a wide flattened ellipse extending well past the
        // head's own silhouette on both sides — the single strongest "fire
        // fighter, not any other character" cue, the same "exaggerate the
        // one cue that matters" approach `UnicornCharacter`'s horn and
        // `PunkCharacter`'s mohawk take. Drawn before the head/helmet dome
        // so the dome overlaps its centre cleanly.
        let brimCenter = point(headCenter.fx, headCenter.fy - headRadius * g.brimCenterOffsetRadii, in: stage)
        let brimW = stage.width * headRadius * g.brimWidthRadii
        let brimH = stage.width * headRadius * g.brimHeightRadii
        let brim = UIBezierPath(ovalIn: CGRect(x: brimCenter.x - brimW / 2, y: brimCenter.y - brimH / 2,
                                                width: brimW, height: brimH))
        Self.helmetShadow.setFill()
        brim.fill()

        // Face.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.skin.setFill()
        head.fill()

        // Helmet dome: covers the top half of the head, like a hard hat,
        // leaving the face visible below the brim line.
        let domeRect = CGRect(x: point(headCenter.fx, headCenter.fy, in: stage).x - stage.width * headRadius * g.domeXInsetRadii,
                               y: point(headCenter.fx, headCenter.fy, in: stage).y - stage.width * headRadius * g.domeYInsetRadii,
                               width: stage.width * headRadius * g.domeWidthRadii,
                               height: stage.width * headRadius * g.domeHeightRadii)
        let dome = UIBezierPath(ovalIn: domeRect)
        Self.helmet.setFill()
        dome.fill()

        // Small knob at the very top.
        let knobCenter = point(headCenter.fx, headCenter.fy - headRadius * g.knobOffsetRadii, in: stage)
        let knobR = stage.width * g.knobRadiusFraction
        let knob = UIBezierPath(ovalIn: CGRect(x: knobCenter.x - knobR, y: knobCenter.y - knobR,
                                                width: knobR * 2, height: knobR * 2))
        Self.badge.setFill()
        knob.fill()

        // Front badge, centred on the brow.
        let badgeCenter = point(headCenter.fx, headCenter.fy - headRadius * g.badgeOffsetRadii, in: stage)
        let badgeW = stage.width * g.badgeWidthFraction
        let badgeH = stage.width * g.badgeHeightFraction
        let badgeShape = UIBezierPath(ovalIn: CGRect(x: badgeCenter.x - badgeW / 2, y: badgeCenter.y - badgeH / 2,
                                                      width: badgeW, height: badgeH))
        Self.badge.setFill()
        badgeShape.fill()
        Self.helmetShadow.setStroke()
        badgeShape.lineWidth = stage.width * g.badgeStrokeLineWidthFraction
        badgeShape.stroke()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        let halfWidth = stage.width * g.eyeHalfWidthFraction
        let curveDepth = stage.width * (blinking ? g.eyeCurveDepthBlinkFraction : g.eyeCurveDepthOpenFraction)
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy + g.eyeYOffset, in: stage)
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - halfWidth, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + halfWidth, y: c.y),
                              controlPoint: CGPoint(x: c.x, y: c.y + curveDepth))
            eye.lineWidth = stage.width * g.eyeLineWidthFraction
            eye.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            eye.stroke()
        }
    }
}
