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

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.29))
    private let headRadius: CGFloat = 0.155

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Shoulders.
        let body = UIBezierPath()
        body.move(to: p(0.28, 0.58))
        body.addQuadCurve(to: p(0.10, 0.99), controlPoint: p(0.12, 0.78))
        body.addLine(to: p(0.90, 0.99))
        body.addQuadCurve(to: p(0.72, 0.58), controlPoint: p(0.88, 0.78))
        body.addQuadCurve(to: p(0.5, 0.52), controlPoint: p(0.5, 0.58))
        body.addQuadCurve(to: p(0.28, 0.58), controlPoint: p(0.5, 0.58))
        body.close()
        Self.coat.setFill()
        body.fill()

        // Tail: curls up from the body's base along the right edge — a cat-
        // specific cue no other character in the roster has.
        let tail = UIBezierPath()
        tail.move(to: p(0.86, 0.94))
        tail.addCurve(to: p(0.99, 0.55), controlPoint1: p(0.99, 0.90), controlPoint2: p(1.00, 0.72))
        tail.addCurve(to: p(0.88, 0.42), controlPoint1: p(0.98, 0.42), controlPoint2: p(0.93, 0.38))
        tail.addCurve(to: p(0.94, 0.60), controlPoint1: p(0.94, 0.44), controlPoint2: p(0.96, 0.52))
        tail.addCurve(to: p(0.82, 0.92), controlPoint1: p(0.94, 0.75), controlPoint2: p(0.90, 0.88))
        tail.close()
        Self.coatShadow.setFill()
        tail.fill()

        // Ears: sharp triangles set close on top of the head, with a pink
        // inner triangle — the classic cat silhouette cue.
        for sign: CGFloat in [-1, 1] {
            let base1 = point(headCenter.fx + sign * headRadius * 0.15, headCenter.fy - headRadius * 0.85, in: stage)
            let base2 = point(headCenter.fx + sign * headRadius * 0.85, headCenter.fy - headRadius * 0.45, in: stage)
            let tip = point(headCenter.fx + sign * headRadius * 0.55, headCenter.fy - headRadius * 1.65, in: stage)
            let ear = UIBezierPath()
            ear.move(to: base1)
            ear.addLine(to: tip)
            ear.addLine(to: base2)
            ear.close()
            Self.coat.setFill()
            ear.fill()

            let innerScale: CGFloat = 0.55
            let innerBase1 = point(headCenter.fx + sign * headRadius * 0.24, headCenter.fy - headRadius * 0.80, in: stage)
            let innerBase2 = point(headCenter.fx + sign * headRadius * 0.68, headCenter.fy - headRadius * 0.55, in: stage)
            let innerTip = point(headCenter.fx + sign * headRadius * 0.50, headCenter.fy - headRadius * (0.85 + 0.80 * innerScale), in: stage)
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
        let muzzleCenter = point(headCenter.fx, headCenter.fy + headRadius * 0.55, in: stage)
        let muzzleW = stage.width * headRadius * 1.35
        let muzzleH = stage.width * headRadius * 0.95
        let muzzle = UIBezierPath(ovalIn: CGRect(x: muzzleCenter.x - muzzleW / 2, y: muzzleCenter.y - muzzleH / 2,
                                                  width: muzzleW, height: muzzleH))
        Self.muzzle.setFill()
        muzzle.fill()

        // Small triangular nose, just above the mouth aperture.
        let noseCenter = point(headCenter.fx, mouthCentre.fy - 0.03, in: stage)
        let noseW = stage.width * 0.028
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: noseCenter.x - noseW, y: noseCenter.y - noseW * 0.6))
        nose.addLine(to: CGPoint(x: noseCenter.x + noseW, y: noseCenter.y - noseW * 0.6))
        nose.addLine(to: CGPoint(x: noseCenter.x, y: noseCenter.y + noseW * 0.7))
        nose.close()
        Self.nose.setFill()
        nose.fill()

        // Whiskers: three short lines each side, from the muzzle outward.
        for sign: CGFloat in [-1, 1] {
            for dy: CGFloat in [-0.02, 0.0, 0.02] {
                let start = point(headCenter.fx + sign * headRadius * 0.5, mouthCentre.fy - 0.01 + dy, in: stage)
                let end = point(headCenter.fx + sign * headRadius * 1.25, mouthCentre.fy - 0.02 + dy, in: stage)
                let whisker = UIBezierPath()
                whisker.move(to: start)
                whisker.addLine(to: end)
                whisker.lineWidth = stage.width * 0.004
                whisker.lineCapStyle = .round
                Theme.robeShadow.withAlphaComponent(0.7).setStroke()
                whisker.stroke()
            }
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [headCenter.fx - 0.06, headCenter.fx + 0.06] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.03, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.03, y: c.y))
                lash.lineWidth = stage.width * 0.011
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            // Almond shape with pointed corners — a cat-specific eye
            // silhouette, distinct from every round-eyed character.
            let w = stage.width * 0.052
            let h = stage.width * 0.036
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - w, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), controlPoint: CGPoint(x: c.x, y: c.y - h))
            eye.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), controlPoint: CGPoint(x: c.x, y: c.y + h))
            eye.close()
            UIColor(red: 0.62, green: 0.78, blue: 0.30, alpha: 1).setFill()
            eye.fill()

            // Vertical slit pupil — the single strongest "cat, not any
            // other character" eye cue.
            let slitW = w * 0.22
            let slitH = h * 1.55
            let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - slitW / 2, y: c.y - slitH / 2, width: slitW, height: slitH))
            UIColor.black.setFill()
            pupil.fill()
        }
    }
}
