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

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Turnout coat: bright safety yellow with a reflective stripe —
        // the colour alone is a strong, unambiguous cue against the dark
        // background.
        let body = UIBezierPath()
        body.move(to: p(0.24, 0.62))
        body.addQuadCurve(to: p(0.06, 0.99), controlPoint: p(0.08, 0.82))
        body.addLine(to: p(0.94, 0.99))
        body.addQuadCurve(to: p(0.76, 0.62), controlPoint: p(0.92, 0.82))
        body.addQuadCurve(to: p(0.5, 0.56), controlPoint: p(0.5, 0.62))
        body.addQuadCurve(to: p(0.24, 0.62), controlPoint: p(0.5, 0.62))
        body.close()
        Self.coat.setFill()
        body.fill()

        let stripe = UIBezierPath()
        stripe.move(to: p(0.10, 0.78))
        stripe.addLine(to: p(0.90, 0.78))
        stripe.addLine(to: p(0.90, 0.86))
        stripe.addLine(to: p(0.10, 0.86))
        stripe.close()
        Self.stripe.setFill()
        stripe.fill()

        // Helmet brim: a wide flattened ellipse extending well past the
        // head's own silhouette on both sides — the single strongest "fire
        // fighter, not any other character" cue, the same "exaggerate the
        // one cue that matters" approach `UnicornCharacter`'s horn and
        // `PunkCharacter`'s mohawk take. Drawn before the head/helmet dome
        // so the dome overlaps its centre cleanly.
        let brimCenter = point(headCenter.fx, headCenter.fy - headRadius * 0.05, in: stage)
        let brimW = stage.width * headRadius * 2.7
        let brimH = stage.width * headRadius * 0.62
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
        let domeRect = CGRect(x: point(headCenter.fx, headCenter.fy, in: stage).x - stage.width * headRadius * 1.06,
                               y: point(headCenter.fx, headCenter.fy, in: stage).y - stage.width * headRadius * 1.30,
                               width: stage.width * headRadius * 2.12,
                               height: stage.width * headRadius * 1.55)
        let dome = UIBezierPath(ovalIn: domeRect)
        Self.helmet.setFill()
        dome.fill()

        // Small knob at the very top.
        let knobCenter = point(headCenter.fx, headCenter.fy - headRadius * 1.28, in: stage)
        let knobR = stage.width * 0.018
        let knob = UIBezierPath(ovalIn: CGRect(x: knobCenter.x - knobR, y: knobCenter.y - knobR,
                                                width: knobR * 2, height: knobR * 2))
        Self.badge.setFill()
        knob.fill()

        // Front badge, centred on the brow.
        let badgeCenter = point(headCenter.fx, headCenter.fy - headRadius * 0.55, in: stage)
        let badgeW = stage.width * 0.09
        let badgeH = stage.width * 0.06
        let badgeShape = UIBezierPath(ovalIn: CGRect(x: badgeCenter.x - badgeW / 2, y: badgeCenter.y - badgeH / 2,
                                                      width: badgeW, height: badgeH))
        Self.badge.setFill()
        badgeShape.fill()
        Self.helmetShadow.setStroke()
        badgeShape.lineWidth = stage.width * 0.005
        badgeShape.stroke()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let halfWidth = stage.width * 0.048
        let curveDepth = stage.width * (blinking ? 0.010 : 0.024)
        for cx: CGFloat in [headCenter.fx - 0.065, headCenter.fx + 0.065] {
            let c = point(cx, headCenter.fy + 0.01, in: stage)
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - halfWidth, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + halfWidth, y: c.y),
                              controlPoint: CGPoint(x: c.x, y: c.y + curveDepth))
            eye.lineWidth = stage.width * 0.015
            eye.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            eye.stroke()
        }
    }
}
