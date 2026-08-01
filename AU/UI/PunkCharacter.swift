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

    private static let jacket = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
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

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Jacket collar with a couple of spiked studs along the shoulder
        // line.
        let body = UIBezierPath()
        body.move(to: p(0.26, 0.56))
        body.addQuadCurve(to: p(0.06, 0.99), controlPoint: p(0.10, 0.78))
        body.addLine(to: p(0.94, 0.99))
        body.addQuadCurve(to: p(0.74, 0.56), controlPoint: p(0.90, 0.78))
        body.addQuadCurve(to: p(0.5, 0.50), controlPoint: p(0.5, 0.56))
        body.addQuadCurve(to: p(0.26, 0.56), controlPoint: p(0.5, 0.56))
        body.close()
        Self.jacket.setFill()
        body.fill()

        for cx: CGFloat in [0.20, 0.32, 0.68, 0.80] {
            let c = p(cx, 0.60)
            let s = stage.width * 0.022
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
        // before the head so it overlaps the root cleanly. `baseY` sits just
        // inside the head's own top edge (headCenter.fy - headRadius); each
        // spike's own multiplier must be LARGER than the 0.85 `baseY` uses
        // (a bigger multiplier subtracts more from headCenter.fy, i.e. a
        // SMALLER/higher-up y) or its tip lands back inside the head circle
        // instead of poking above it — invisible once the head fill fires,
        // exactly the bug an earlier version of this shape had.
        let mohawk = UIBezierPath()
        let baseY = headCenter.fy - headRadius * 0.85
        let spikes: [(x: CGFloat, m: CGFloat)] = [
            (0.42, 1.2), (0.46, 1.6), (0.50, 2.0), (0.54, 1.6), (0.58, 1.2),
        ]
        mohawk.move(to: point(0.40, baseY, in: stage))
        for spike in spikes {
            mohawk.addLine(to: point(spike.x, headCenter.fy - headRadius * spike.m, in: stage))
            mohawk.addLine(to: point(spike.x + 0.02, baseY, in: stage))
        }
        mohawk.addLine(to: point(0.60, baseY, in: stage))
        mohawk.close()
        Self.mohawk.setFill()
        mohawk.fill()
        Self.mohawkShadow.setStroke()
        mohawk.lineWidth = stage.width * 0.006
        mohawk.stroke()

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.skin.setFill()
        head.fill()

        // Safety-pin cheek piercing.
        let pinCenter = point(headCenter.fx + headRadius * 0.85, headCenter.fy + headRadius * 0.35, in: stage)
        let pin = UIBezierPath()
        pin.move(to: CGPoint(x: pinCenter.x - stage.width * 0.02, y: pinCenter.y - stage.width * 0.012))
        pin.addQuadCurve(to: CGPoint(x: pinCenter.x + stage.width * 0.02, y: pinCenter.y - stage.width * 0.012),
                          controlPoint: CGPoint(x: pinCenter.x, y: pinCenter.y + stage.width * 0.018))
        pin.lineWidth = stage.width * 0.006
        Self.jacketTrim.setStroke()
        pin.stroke()
        let pinDot = UIBezierPath(ovalIn: CGRect(x: pinCenter.x + stage.width * 0.014, y: pinCenter.y - stage.width * 0.018,
                                                  width: stage.width * 0.008, height: stage.width * 0.008))
        Self.jacketTrim.setFill()
        pinDot.fill()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        // Set well apart (headCenter.fx ± 0.075, vs. a typical ± 0.05-0.06
        // elsewhere) and with a pronounced flick — an earlier version placed
        // these too close together with too shallow a flick, and the two
        // short strokes visually fused into one flat line at ~120pt instead
        // of reading as two separate eyes.
        for cx: CGFloat in [headCenter.fx - 0.075, headCenter.fx + 0.075] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            let halfWidth = stage.width * 0.034
            let flick = stage.width * (blinking ? 0.004 : 0.022)
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
            eye.lineWidth = stage.width * 0.018
            eye.lineCapStyle = .round
            UIColor.black.setStroke()
            eye.stroke()
        }
    }
}
