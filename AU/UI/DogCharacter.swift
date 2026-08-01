import AVFoundation
import UIKit

/// A front-facing dog head over simple shoulders: floppy drooping ears, a
/// protruding tan snout with a dark nose, and a wide panting mouth. Its
/// voice is upstream's "Monastary" factory preset, verbatim — the single
/// darkest of the six measured presets, matched to the largest/deepest
/// archetype of the six new characters (see `FactoryVoiceTable`'s doc
/// comment for the measurement and the full mapping). Placeholder art, like
/// every character added by this task — the user is replacing all
/// character art with their own later, so this deliberately stays a first
/// pass: an instantly-readable silhouette and a mouth that sweeps
/// distinctly across the vowel range, nothing more.
struct DogCharacter: Character {
    let id = "dog"
    let displayName = "Dog"

    var savedParameters: [Param: AUValue]? { FactoryVoiceTable.values(for: id) }

    private static let coat = UIColor(red: 0.78, green: 0.56, blue: 0.30, alpha: 1)
    private static let coatShadow = Self.coat.adjusted(brightnessScale: 0.72)
    private static let snout = UIColor(red: 0.92, green: 0.82, blue: 0.66, alpha: 1)
    private static let nose = UIColor(red: 0.16, green: 0.13, blue: 0.12, alpha: 1)

    // MARK: - Mouth anchors — a panting mouth: opens progressively wider AND
    // taller across the whole sweep, unlike every other character's
    // narrow-then-flattening trend.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.20, 0.14), (0.32, 0.24), (0.44, 0.34), (0.52, 0.40), (0.58, 0.44),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.30
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.56)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.185

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Shoulders.
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

        // Floppy, drooping ears — the strongest "dog, not cow/unicorn" cue,
        // hanging DOWN past the jawline rather than jutting sideways (cow)
        // or standing tall and pointed (unicorn). Drawn before the head so
        // it overlaps their root.
        for sign: CGFloat in [-1, 1] {
            let rootX = headCenter.fx + sign * headRadius * 0.92
            let root = point(rootX, headCenter.fy - headRadius * 0.15, in: stage)
            let tip = point(rootX + sign * headRadius * 0.15, headCenter.fy + headRadius * 1.55, in: stage)
            let outerCtrl = point(rootX + sign * headRadius * 0.62, headCenter.fy + headRadius * 0.55, in: stage)
            let innerCtrl = point(rootX + sign * headRadius * 0.05, headCenter.fy + headRadius * 1.05, in: stage)
            let ear = UIBezierPath()
            ear.move(to: root)
            ear.addQuadCurve(to: tip, controlPoint: outerCtrl)
            ear.addQuadCurve(to: root, controlPoint: innerCtrl)
            ear.close()
            Self.coatShadow.setFill()
            ear.fill()
        }

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.coat.setFill()
        head.fill()

        // Snout: a tan oval protruding below the head, the mouth aperture's
        // own local frame — with a dark nose at its tip.
        let snoutCenter = point(mouthCentre.fx, headCenter.fy + headRadius * 1.20, in: stage)
        let snoutW = stage.width * 0.30
        let snoutH = stage.width * 0.26
        let snout = UIBezierPath(ovalIn: CGRect(x: snoutCenter.x - snoutW / 2, y: snoutCenter.y - snoutH / 2,
                                                 width: snoutW, height: snoutH))
        Self.snout.setFill()
        snout.fill()

        let noseW = stage.width * 0.07
        let noseCenter = CGPoint(x: snoutCenter.x, y: snoutCenter.y - snoutH * 0.28)
        let nose = UIBezierPath(ovalIn: CGRect(x: noseCenter.x - noseW / 2, y: noseCenter.y - noseW * 0.7,
                                                width: noseW, height: noseW * 1.1))
        Self.nose.setFill()
        nose.fill()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [headCenter.fx - 0.07, headCenter.fx + 0.07] {
            let c = point(cx, headCenter.fy - 0.02, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.038, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.038, y: c.y))
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
            let pupilR = r * 0.6
            let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
            Self.nose.setFill()
            pupil.fill()
        }
    }
}
