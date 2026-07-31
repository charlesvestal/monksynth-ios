import UIKit

/// An old man: bushy eyebrows over deep-set eyes, forehead wrinkles, a wide
/// grey beard the mouth aperture opens inside of, and a simple cardigan.
/// First pass; the user will iterate on the art with the render harness.
struct OldManCharacter: Character {
    let id = "oldman"
    let displayName = "Old Man"

    private static let cardigan = UIColor(red: 0.30, green: 0.35, blue: 0.42, alpha: 1)
    private static let cardiganTrim = Self.cardigan.adjusted(brightnessScale: 1.35)
    private static let hair = UIColor(white: 0.82, alpha: 1)
    private static let hairShadow = UIColor(white: 0.68, alpha: 1)
    private static let skin = Theme.skin.adjusted(saturationScale: 0.75, brightnessScale: 0.92)

    // MARK: - Mouth anchors — wide but shallow throughout, mostly hidden by
    // the moustache/beard; distinct trend from every other character.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.14, 0.16), (0.22, 0.20), (0.30, 0.15), (0.36, 0.10), (0.40, 0.06),
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
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.40)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.165

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Cardigan: a simple rounded trapezoid, not the monk's robe rig —
        // a plainly different silhouette, and one small enough to keep this
        // a first pass rather than a second full costume system.
        let body = UIBezierPath()
        body.move(to: p(0.28, 0.52))
        body.addQuadCurve(to: p(0.06, 0.99), controlPoint: p(0.10, 0.75))
        body.addLine(to: p(0.94, 0.99))
        body.addQuadCurve(to: p(0.72, 0.52), controlPoint: p(0.90, 0.75))
        body.addQuadCurve(to: p(0.5, 0.46), controlPoint: p(0.5, 0.52))
        body.addQuadCurve(to: p(0.28, 0.52), controlPoint: p(0.5, 0.52))
        body.close()
        Self.cardigan.setFill()
        body.fill()

        // Zip trim down the centre.
        let zip = UIBezierPath()
        zip.move(to: p(0.5, 0.47))
        zip.addLine(to: p(0.5, 0.99))
        zip.lineWidth = stage.width * 0.012
        Self.cardiganTrim.setStroke()
        zip.stroke()

        // Side hair tufts (bald on top).
        for cx: CGFloat in [headCenter.fx - headRadius * 0.92, headCenter.fx + headRadius * 0.92] {
            let tuft = UIBezierPath()
            tuft.move(to: point(cx, headCenter.fy - headRadius * 0.1, in: stage))
            tuft.addQuadCurve(to: point(cx, headCenter.fy + headRadius * 0.85, in: stage),
                               controlPoint: point(cx + (cx < headCenter.fx ? -0.05 : 0.05), headCenter.fy + headRadius * 0.4, in: stage))
            tuft.addQuadCurve(to: point(cx + (cx < headCenter.fx ? -0.05 : 0.05), headCenter.fy - headRadius * 0.1, in: stage),
                               controlPoint: point(cx + (cx < headCenter.fx ? -0.09 : 0.09), headCenter.fy + headRadius * 0.4, in: stage))
            tuft.close()
            Self.hairShadow.setFill()
            tuft.fill()
        }

        // Head.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.skin.setFill()
        head.fill()

        // Forehead wrinkle lines.
        for dy: CGFloat in [-0.62, -0.50, -0.40] {
            let line = UIBezierPath()
            line.move(to: point(headCenter.fx - headRadius * 0.55, headCenter.fy + headRadius * dy, in: stage))
            line.addQuadCurve(to: point(headCenter.fx + headRadius * 0.55, headCenter.fy + headRadius * dy, in: stage),
                               controlPoint: point(headCenter.fx, headCenter.fy + headRadius * (dy - 0.05), in: stage))
            line.lineWidth = stage.width * 0.005
            Self.hairShadow.withAlphaComponent(0.6).setStroke()
            line.stroke()
        }

        // Beard: covers the lower half of the face and chin. Drawn before
        // the mouth aperture (which `CharacterView` composites on top of
        // everything last), so the moving mouth reads as an opening within
        // the beard rather than sitting oddly on top of skin.
        let beard = UIBezierPath()
        beard.move(to: point(headCenter.fx - headRadius * 0.98, headCenter.fy + headRadius * 0.05, in: stage))
        beard.addQuadCurve(to: point(headCenter.fx, headCenter.fy + headRadius * 2.05, in: stage),
                            controlPoint: point(headCenter.fx - headRadius * 0.7, headCenter.fy + headRadius * 1.9, in: stage))
        beard.addQuadCurve(to: point(headCenter.fx + headRadius * 0.98, headCenter.fy + headRadius * 0.05, in: stage),
                            controlPoint: point(headCenter.fx + headRadius * 0.7, headCenter.fy + headRadius * 1.9, in: stage))
        beard.addQuadCurve(to: point(headCenter.fx - headRadius * 0.98, headCenter.fy + headRadius * 0.05, in: stage),
                            controlPoint: point(headCenter.fx, headCenter.fy + headRadius * 0.55, in: stage))
        beard.close()
        Self.hair.setFill()
        beard.fill()
        Self.hairShadow.withAlphaComponent(0.5).setStroke()
        beard.lineWidth = stage.width * 0.006
        beard.stroke()

        // A little ear crescent on each side, matching the monk's approach.
        for cx: CGFloat in [headCenter.fx - headRadius * 0.98, headCenter.fx + headRadius * 0.98] {
            let c = point(cx, headCenter.fy, in: stage)
            let w = stage.width * 0.042
            let h = stage.width * 0.07
            let ear = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            Self.skin.setFill()
            ear.fill()
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [headCenter.fx - 0.06, headCenter.fx + 0.06] {
            let c = point(cx, headCenter.fy - 0.02, in: stage)

            // Heavy brow above the eye, always drawn.
            let brow = UIBezierPath()
            brow.move(to: CGPoint(x: c.x - stage.width * 0.045, y: c.y - stage.width * 0.03))
            brow.addQuadCurve(to: CGPoint(x: c.x + stage.width * 0.045, y: c.y - stage.width * 0.035),
                               controlPoint: CGPoint(x: c.x, y: c.y - stage.width * 0.055))
            brow.lineWidth = stage.width * 0.022
            brow.lineCapStyle = .round
            Self.hairShadow.setStroke()
            brow.stroke()

            let halfWidth = stage.width * 0.032
            let curveDepth = stage.width * (blinking ? 0.005 : 0.014)
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - halfWidth, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + halfWidth, y: c.y),
                              controlPoint: CGPoint(x: c.x, y: c.y + curveDepth))
            eye.lineWidth = stage.width * 0.012
            eye.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            eye.stroke()
        }
    }
}
