import UIKit

/// A stylised profile-view fish, facing right: an oval body, a fanned tail
/// at the back, a big round eye, and prominent puckered lips at the snout —
/// the "reads instantly in silhouette" set the design doc asks for. Rebuilt
/// against the 90s pre-rendered-3D style spec: every surface shades through
/// `Shading`'s primitives, and nothing is stroked.
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
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Tail: a fanned triangle at the back (left) of the body. Kept
        // inside 0...1 (rather than bleeding off-stage) so it survives being
        // rendered at the small, tightly-cropped cell sizes the render
        // harness — and a collapsed AUv3 strip — actually use.
        let tail = UIBezierPath()
        tail.move(to: p(0.24, 0.50))
        tail.addLine(to: p(0.02, 0.26))
        tail.addLine(to: p(0.11, 0.50))
        tail.addLine(to: p(0.02, 0.76))
        tail.close()
        Shading.freeform(tail.cgPath, boundingBox: tail.bounds, color: Self.finColor, into: context)

        // Dorsal fin, on top of the body.
        let dorsal = UIBezierPath()
        dorsal.move(to: p(0.38, 0.30))
        dorsal.addQuadCurve(to: p(0.62, 0.28), controlPoint: p(0.50, 0.08))
        dorsal.addQuadCurve(to: p(0.55, 0.34), controlPoint: p(0.58, 0.30))
        dorsal.close()
        Shading.freeform(dorsal.cgPath, boundingBox: dorsal.bounds, color: Self.finColor, into: context)

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
        Shading.freeform(body.cgPath, boundingBox: body.bounds, color: Self.bodyColor, into: context)

        // Pale belly patch, lower-front — shaded against the whole body's
        // bounds so it reveals the body's own lighting rather than getting
        // an independent hot spot of its own.
        context.saveGState()
        body.addClip()
        let belly = UIBezierPath()
        belly.move(to: p(0.30, 0.62))
        belly.addQuadCurve(to: p(0.60, 0.80), controlPoint: p(0.42, 0.84))
        belly.addQuadCurve(to: p(0.34, 0.50), controlPoint: p(0.24, 0.66))
        belly.close()
        belly.addClip()
        Shading.radialShade(in: body.bounds, color: Self.bellyColor, into: context)
        context.restoreGState()

        // Pectoral fin.
        let pectoral = UIBezierPath()
        pectoral.move(to: p(0.50, 0.62))
        pectoral.addQuadCurve(to: p(0.44, 0.86), controlPoint: p(0.52, 0.78))
        pectoral.addQuadCurve(to: p(0.40, 0.64), controlPoint: p(0.40, 0.76))
        pectoral.close()
        Shading.freeform(pectoral.cgPath, boundingBox: pectoral.bounds, color: Self.finColor, into: context)

        // A soft contact shadow where the pectoral fin meets the body.
        Shading.occlusion(under: CGRect(x: p(0.38, 0.58).x, y: p(0.5, 0.58).y,
                                         width: p(0.54, 0.70).x - p(0.38, 0.58).x,
                                         height: p(0.5, 0.70).y - p(0.5, 0.58).y),
                           into: context)

        // Prominent lips: a fixed puckered ring around the snout, built as
        // a torus (an outer contour with an inner "hole" wound the same
        // direction, filled even-odd) rather than a stroked circle — sized a
        // little larger than the mouth aperture's own widest anchor so it
        // always frames it rather than being poked through by it.
        let lipCenter = p(mouthCentre.fx, mouthCentre.fy)
        let outerR = stage.width * mouthBoxFraction * 0.46
        let innerR = outerR * 0.62
        let ring = CGMutablePath()
        ring.addEllipse(in: CGRect(x: lipCenter.x - outerR, y: lipCenter.y - outerR, width: outerR * 2, height: outerR * 2))
        ring.addEllipse(in: CGRect(x: lipCenter.x - innerR, y: lipCenter.y - innerR, width: innerR * 2, height: innerR * 2))
        Shading.freeform(ring, boundingBox: ring.boundingBox, color: Self.lipColor, fillRule: .evenOdd, into: context)
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let c = point(0.60, 0.38, in: stage)
        let eyeW = stage.width * 0.15

        if blinking {
            let h = stage.width * 0.014
            Shading.recess(in: CGRect(x: c.x - eyeW / 2, y: c.y - h / 2, width: eyeW, height: h), into: context)
            return
        }

        let whiteRect = CGRect(x: c.x - eyeW / 2, y: c.y - eyeW / 2, width: eyeW, height: eyeW)
        Shading.sphere(in: whiteRect, color: .white, into: context)

        let pupilR = eyeW * 0.30
        let pupilRect = CGRect(x: c.x - pupilR, y: c.y - pupilR, width: pupilR * 2, height: pupilR * 2)
        Shading.sphere(in: pupilRect, color: UIColor(white: 0.06, alpha: 1), into: context)
    }
}
