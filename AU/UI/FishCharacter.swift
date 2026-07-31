import UIKit

/// A stylised profile-view fish, facing right: an oval body, a fanned tail
/// at the back, a big round eye, and prominent puckered lips at the snout —
/// the "reads instantly in silhouette" set the design doc asks for. First
/// pass; the user will iterate on the art with the render harness.
struct FishCharacter: Character {
    let id = "fish"
    let displayName = "Fish"

    private static let bodyColor = UIColor(red: 0.90, green: 0.46, blue: 0.24, alpha: 1)
    private static let bellyColor = UIColor(red: 0.98, green: 0.80, blue: 0.55, alpha: 1)
    private static let finColor = Self.bodyColor.adjusted(brightnessScale: 0.72)
    private static let lipColor = UIColor(red: 0.86, green: 0.38, blue: 0.42, alpha: 1)

    // MARK: - Mouth anchors — a fish "pucker" stays roughly round throughout
    // the vowel range rather than the monk's narrow-to-wide sweep, so the
    // two characters' sweeps are genuinely different shapes, not just
    // differently-scaled copies of the same one.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.42, 0.30), (0.55, 0.46), (0.62, 0.62), (0.50, 0.48), (0.34, 0.28),
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
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.80, 0.56)

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Tail: a fanned triangle at the back (left) of the body.
        // Kept inside 0...1 (rather than bleeding off-stage like the monk's
        // drape line does) so it survives being rendered at the small,
        // tightly-cropped cell sizes the render harness — and a collapsed
        // AUv3 strip — actually use, instead of being clipped away.
        let tail = UIBezierPath()
        tail.move(to: p(0.24, 0.50))
        tail.addLine(to: p(0.02, 0.26))
        tail.addLine(to: p(0.11, 0.50))
        tail.addLine(to: p(0.02, 0.76))
        tail.close()
        Self.finColor.setFill()
        tail.fill()

        // Dorsal fin, on top of the body.
        let dorsal = UIBezierPath()
        dorsal.move(to: p(0.38, 0.30))
        dorsal.addQuadCurve(to: p(0.62, 0.28), controlPoint: p(0.50, 0.08))
        dorsal.addQuadCurve(to: p(0.55, 0.34), controlPoint: p(0.58, 0.30))
        dorsal.close()
        Self.finColor.setFill()
        dorsal.fill()

        // Body: an egg-ish oval, wider at the back, tapering toward the
        // snout on the right.
        let body = UIBezierPath()
        body.move(to: p(0.16, 0.50))
        body.addCurve(to: p(0.50, 0.20), controlPoint1: p(0.18, 0.32), controlPoint2: p(0.32, 0.21))
        body.addCurve(to: p(0.82, 0.44), controlPoint1: p(0.66, 0.19), controlPoint2: p(0.78, 0.30))
        body.addCurve(to: p(0.88, 0.56), controlPoint1: p(0.86, 0.48), controlPoint2: p(0.88, 0.51))
        body.addCurve(to: p(0.80, 0.68), controlPoint1: p(0.88, 0.61), controlPoint2: p(0.85, 0.65))
        body.addCurve(to: p(0.48, 0.90), controlPoint1: p(0.74, 0.74), controlPoint2: p(0.62, 0.89))
        body.addCurve(to: p(0.16, 0.50), controlPoint1: p(0.30, 0.91), controlPoint2: p(0.14, 0.70))
        body.close()
        Self.bodyColor.setFill()
        body.fill()

        // Pale belly patch, lower-front.
        let belly = UIBezierPath()
        belly.move(to: p(0.30, 0.62))
        belly.addQuadCurve(to: p(0.60, 0.80), controlPoint: p(0.42, 0.84))
        belly.addQuadCurve(to: p(0.34, 0.50), controlPoint: p(0.24, 0.66))
        belly.close()
        Self.bellyColor.withAlphaComponent(0.8).setFill()
        belly.fill()

        // Pectoral fin.
        let pectoral = UIBezierPath()
        pectoral.move(to: p(0.50, 0.62))
        pectoral.addQuadCurve(to: p(0.44, 0.86), controlPoint: p(0.52, 0.78))
        pectoral.addQuadCurve(to: p(0.40, 0.64), controlPoint: p(0.40, 0.76))
        pectoral.close()
        Self.finColor.withAlphaComponent(0.9).setFill()
        pectoral.fill()

        // Prominent lips: a fixed puckered ring around the snout, sized a
        // little larger than the mouth aperture's own widest anchor so it
        // always frames it rather than being poked through by it. A thick
        // stroke over a faint fill reads as a fleshy pucker even at the
        // small sizes this character renders at (~120pt tall).
        let lipCenter = p(mouthCentre.fx, mouthCentre.fy)
        let lipW = stage.width * mouthBoxFraction * 0.85
        let lipH = stage.width * mouthBoxFraction * 0.85
        let lips = UIBezierPath(ovalIn: CGRect(x: lipCenter.x - lipW / 2, y: lipCenter.y - lipH / 2,
                                                width: lipW, height: lipH))
        Self.lipColor.withAlphaComponent(0.35).setFill()
        lips.fill()
        lips.lineWidth = stage.width * 0.032
        Self.lipColor.setStroke()
        lips.stroke()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let c = point(0.60, 0.38, in: stage)
        let r = stage.width * (blinking ? 0.006 : 0.075)
        let eyeW = stage.width * 0.15

        if blinking {
            let lid = UIBezierPath()
            lid.move(to: CGPoint(x: c.x - eyeW / 2, y: c.y))
            lid.addLine(to: CGPoint(x: c.x + eyeW / 2, y: c.y))
            lid.lineWidth = stage.width * 0.018
            lid.lineCapStyle = .round
            UIColor.black.withAlphaComponent(0.6).setStroke()
            lid.stroke()
            return
        }

        let white = UIBezierPath(ovalIn: CGRect(x: c.x - eyeW / 2, y: c.y - eyeW / 2, width: eyeW, height: eyeW))
        UIColor.white.setFill()
        white.fill()

        let pupilR = r
        let pupil = UIBezierPath(ovalIn: CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2))
        UIColor.black.setFill()
        pupil.fill()

        let highlightR = pupilR * 0.35
        let hl = point(0.615, 0.365, in: stage)
        let highlight = UIBezierPath(ovalIn: CGRect(x: hl.x - highlightR, y: hl.y - highlightR,
                                                      width: highlightR * 2, height: highlightR * 2))
        UIColor.white.setFill()
        highlight.fill()
    }
}
