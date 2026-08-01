import AVFoundation
import UIKit

/// A punk rocker: a tall jagged mohawk in acid green, a spiked leather-
/// jacket collar, and a safety-pin cheek piercing. Its voice is upstream's
/// "Jamyang" factory preset, verbatim — one of the two middle-brightness
/// presets of the six measured, matched to the sharper-edged, younger of
/// the two remaining archetypes among the six new characters, once dog/
/// ghost (darkest) and cat (brightest) were placed (see
/// `FactoryVoiceTable`'s doc comment for the measurement and the full
/// mapping). Placeholder art, like every character added by this task — the
/// user is replacing all character art with their own later, so this
/// deliberately stays a first pass: an instantly-readable silhouette and a
/// mouth that sweeps distinctly across the vowel range, nothing more.
struct PunkCharacter: Character {
    let id = "punk"
    let displayName = "Punk"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    // Raised well above an original (0.12, 0.12, 0.14) — barely brighter
    // than `Theme.background`'s (0.082, 0.086, 0.102), so the jacket was
    // nearly invisible against the dark stage and the studs read as
    // diamonds floating in a void. Still reads as black leather at this
    // brightness, just now with enough separation from the background to
    // actually show a silhouette.
    private static let jacket = UIColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1)
    private static let jacketTrim = UIColor(white: 0.75, alpha: 1)
    private static let mohawk = UIColor(red: 0.58, green: 0.92, blue: 0.20, alpha: 1)
    private static let mohawkShadow = Self.mohawk.adjusted(brightnessScale: 0.65)
    private static let skin = Theme.skin.adjusted(saturationScale: 0.85, brightnessScale: 0.98)

    // MARK: - Mouth anchors — a smirk: width grows steadily while height
    // dips then rises, a shape no other character's sweep produces.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.18, 0.12), (0.28, 0.10), (0.36, 0.08), (0.42, 0.14), (0.46, 0.20),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.24
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.42)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.32))
    private let headRadius: CGFloat = 0.15

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
        // --- Jacket ---
        var jacketShoulderLeftX: CGFloat = 0.26
        var jacketShoulderY: CGFloat = 0.56
        var jacketHemLeftX: CGFloat = 0.06
        var jacketHemY: CGFloat = 0.99
        var jacketLeftControlX: CGFloat = 0.10
        var jacketLeftControlY: CGFloat = 0.78
        var jacketHemRightX: CGFloat = 0.94
        var jacketShoulderRightX: CGFloat = 0.74
        var jacketRightControlX: CGFloat = 0.90
        var jacketRightControlY: CGFloat = 0.78
        var jacketNeckX: CGFloat = 0.5
        var jacketNeckY: CGFloat = 0.50
        var jacketNeckControlY: CGFloat = 0.56

        // --- Neck ---
        /// How far above the head's own bottom edge the skin neck patch's
        /// top sits, in head-radius units — kept slightly INSIDE the head
        /// circle so there is no seam between head fill and neck fill. An
        /// earlier version had no neck at all: the head sat directly over
        /// empty background above the jacket's own collar point.
        var neckTopOffsetRadii: CGFloat = 0.85
        /// Half-width of the neck patch's top edge, matched to (very
        /// slightly wider than) the head circle's own half-width at
        /// `neckTopOffsetRadii`, so the head fill (drawn after) fully
        /// covers the seam with no visible corner. The patch is a TRIANGLE
        /// down to the jacket's own V-neck point (`jacketNeckX`/
        /// `jacketNeckY`), not a rectangle — see `FireFighterCharacter`'s
        /// identical field for why a rectangle reads as a notch cut out of
        /// the silhouette instead of a smoothly tapering neck.
        var neckTopHalfWidthFraction: CGFloat = 0.079

        // --- Studs ---
        var studXs: [CGFloat] = [0.20, 0.32, 0.68, 0.80]
        var studY: CGFloat = 0.60
        var studHalfWidthFraction: CGFloat = 0.022

        // --- Mohawk ---
        /// `baseY`'s own head-radius multiplier — where each spike's base
        /// sits, just inside the head's own top edge.
        var mohawkBaseRadii: CGFloat = 0.85
        /// Each spike's `(x, headRadius multiplier)` pair. A multiplier
        /// LARGER than `mohawkBaseRadii` subtracts more from `headCenter.fy`
        /// (a smaller/higher-up y), so the tip pokes above the head instead
        /// of landing back inside the circle where the head fill would hide
        /// it — exactly the bug an earlier version of this shape had.
        var mohawkSpikes: [(x: CGFloat, m: CGFloat)] = [
            (0.42, 1.2), (0.46, 1.6), (0.50, 2.0), (0.54, 1.6), (0.58, 1.2),
        ]
        var mohawkLeftX: CGFloat = 0.40
        var mohawkRightX: CGFloat = 0.60
        var mohawkSpikeWidth: CGFloat = 0.02
        var mohawkStrokeLineWidthFraction: CGFloat = 0.006

        // --- Safety-pin cheek piercing ---
        var pinXOffsetRadii: CGFloat = 0.85
        var pinYOffsetRadii: CGFloat = 0.35
        var pinHalfWidthFraction: CGFloat = 0.02
        var pinHalfHeightFraction: CGFloat = 0.012
        var pinCurveDepthFraction: CGFloat = 0.018
        var pinLineWidthFraction: CGFloat = 0.006
        var pinDotXOffsetFraction: CGFloat = 0.014
        var pinDotYOffsetFraction: CGFloat = 0.018
        var pinDotSizeFraction: CGFloat = 0.008

        // --- Eyes ---
        var eyeXOffset: CGFloat = 0.075
        var eyeYOffset: CGFloat = 0.01
        var eyeHalfWidthFraction: CGFloat = 0.034
        var eyeFlickOpenFraction: CGFloat = 0.022
        var eyeFlickBlinkFraction: CGFloat = 0.004
        var eyeLineWidthFraction: CGFloat = 0.018
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Jacket collar with a couple of spiked studs along the shoulder
        // line.
        let body = UIBezierPath()
        body.move(to: p(g.jacketShoulderLeftX, g.jacketShoulderY))
        body.addQuadCurve(to: p(g.jacketHemLeftX, g.jacketHemY), controlPoint: p(g.jacketLeftControlX, g.jacketLeftControlY))
        body.addLine(to: p(g.jacketHemRightX, g.jacketHemY))
        body.addQuadCurve(to: p(g.jacketShoulderRightX, g.jacketShoulderY), controlPoint: p(g.jacketRightControlX, g.jacketRightControlY))
        body.addQuadCurve(to: p(g.jacketNeckX, g.jacketNeckY), controlPoint: p(g.jacketNeckX, g.jacketNeckControlY))
        body.addQuadCurve(to: p(g.jacketShoulderLeftX, g.jacketShoulderY), controlPoint: p(g.jacketNeckX, g.jacketNeckControlY))
        body.close()
        Self.jacket.setFill()
        body.fill()

        // Neck: a skin patch bridging the head's own bottom edge down to
        // the jacket's collar point, so the head reads as attached rather
        // than floating over empty background. A triangle tapering to the
        // jacket's own point, not a rectangle — see
        // `neckTopHalfWidthFraction`'s doc comment for why.
        let neckTop = headCenter.fy + headRadius * g.neckTopOffsetRadii
        let neck = UIBezierPath()
        neck.move(to: p(headCenter.fx - g.neckTopHalfWidthFraction, neckTop))
        neck.addLine(to: p(g.jacketNeckX, g.jacketNeckY))
        neck.addLine(to: p(headCenter.fx + g.neckTopHalfWidthFraction, neckTop))
        neck.close()
        Self.skin.setFill()
        neck.fill()

        for cx in g.studXs {
            let c = p(cx, g.studY)
            let s = stage.width * g.studHalfWidthFraction
            let stud = UIBezierPath()
            stud.move(to: CGPoint(x: c.x, y: c.y - s))
            stud.addLine(to: CGPoint(x: c.x + s, y: c.y))
            stud.addLine(to: CGPoint(x: c.x, y: c.y + s))
            stud.addLine(to: CGPoint(x: c.x - s, y: c.y))
            stud.close()
            Self.jacketTrim.setFill()
            stud.fill()
        }

        // Mohawk: a jagged crest of five spikes rising from the top-centre
        // of the head — the single most important silhouette cue, drawn
        // deliberately tall and saturated, the same "exaggerate the one cue
        // that matters" approach `UnicornCharacter`'s horn takes. Drawn
        // before the head so it overlaps the root cleanly.
        let mohawk = UIBezierPath()
        let baseY = headCenter.fy - headRadius * g.mohawkBaseRadii
        mohawk.move(to: point(g.mohawkLeftX, baseY, in: stage))
        for spike in g.mohawkSpikes {
            mohawk.addLine(to: point(spike.x, headCenter.fy - headRadius * spike.m, in: stage))
            mohawk.addLine(to: point(spike.x + g.mohawkSpikeWidth, baseY, in: stage))
        }
        mohawk.addLine(to: point(g.mohawkRightX, baseY, in: stage))
        mohawk.close()
        Self.mohawk.setFill()
        mohawk.fill()
        Self.mohawkShadow.setStroke()
        mohawk.lineWidth = stage.width * g.mohawkStrokeLineWidthFraction
        mohawk.stroke()

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.skin.setFill()
        head.fill()

        // Safety-pin cheek piercing.
        let pinCenter = point(headCenter.fx + headRadius * g.pinXOffsetRadii, headCenter.fy + headRadius * g.pinYOffsetRadii, in: stage)
        let pin = UIBezierPath()
        pin.move(to: CGPoint(x: pinCenter.x - stage.width * g.pinHalfWidthFraction, y: pinCenter.y - stage.width * g.pinHalfHeightFraction))
        pin.addQuadCurve(to: CGPoint(x: pinCenter.x + stage.width * g.pinHalfWidthFraction, y: pinCenter.y - stage.width * g.pinHalfHeightFraction),
                          controlPoint: CGPoint(x: pinCenter.x, y: pinCenter.y + stage.width * g.pinCurveDepthFraction))
        pin.lineWidth = stage.width * g.pinLineWidthFraction
        Self.jacketTrim.setStroke()
        pin.stroke()
        let pinDot = UIBezierPath(ovalIn: CGRect(x: pinCenter.x + stage.width * g.pinDotXOffsetFraction, y: pinCenter.y - stage.width * g.pinDotYOffsetFraction,
                                                  width: stage.width * g.pinDotSizeFraction, height: stage.width * g.pinDotSizeFraction))
        Self.jacketTrim.setFill()
        pinDot.fill()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        // Set well apart (headCenter.fx ± 0.075, vs. a typical ± 0.05-0.06
        // elsewhere) and with a pronounced flick — an earlier version placed
        // these too close together with too shallow a flick, and the two
        // short strokes visually fused into one flat line at ~120pt instead
        // of reading as two separate eyes.
        let g = geometry
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy - g.eyeYOffset, in: stage)
            let halfWidth = stage.width * g.eyeHalfWidthFraction
            let flick = stage.width * (blinking ? g.eyeFlickBlinkFraction : g.eyeFlickOpenFraction)
            // Sharp, angular eyeliner-style eyes: a straight line from the
            // inner corner (near the nose) to the outer corner, flicked
            // upward — distinct from every rounded/curved eye elsewhere in
            // the roster. `outward` mirrors the flick direction between the
            // two eyes: -1 for the left eye (whose outer corner is further
            // LEFT, away from the nose), +1 for the right.
            let outward: CGFloat = cx < headCenter.fx ? -1 : 1
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - halfWidth * outward, y: c.y + flick * 0.25))
            eye.addLine(to: CGPoint(x: c.x + halfWidth * outward, y: c.y - flick))
            eye.lineWidth = stage.width * g.eyeLineWidthFraction
            eye.lineCapStyle = .round
            UIColor.black.setStroke()
            eye.stroke()
        }
    }
}
