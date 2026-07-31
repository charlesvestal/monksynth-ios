import UIKit

/// An old man: bushy eyebrows over deep-set eyes, forehead wrinkles, a wide
/// grey beard the mouth aperture opens inside of, and a simple cardigan.
/// Rebuilt against the 90s pre-rendered-3D style spec: every surface shades
/// through `Shading`'s primitives, and nothing is stroked — the brow, the
/// wrinkles, and the cardigan's zip trim were the strokiest things about the
/// original pass and are all shaded shapes now.
struct OldManCharacter: Character {
    let id = "oldman"
    let displayName = "Old Man"

    private static let cardigan = UIColor(red: 0.30, green: 0.35, blue: 0.42, alpha: 1)
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
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Cardigan: a simple rounded trapezoid, not the monk's robe rig —
        // a plainly different silhouette.
        let body = UIBezierPath()
        body.move(to: p(0.28, 0.52))
        body.addQuadCurve(to: p(0.06, 0.99), controlPoint: p(0.10, 0.75))
        body.addLine(to: p(0.94, 0.99))
        body.addQuadCurve(to: p(0.72, 0.52), controlPoint: p(0.90, 0.75))
        body.addQuadCurve(to: p(0.5, 0.46), controlPoint: p(0.5, 0.52))
        body.addQuadCurve(to: p(0.28, 0.52), controlPoint: p(0.5, 0.52))
        body.close()
        Shading.freeform(body.cgPath, boundingBox: body.bounds, color: Self.cardigan, into: context)

        // Zip trim down the centre — a thin shaded strip, not a stroke.
        context.saveGState()
        body.addClip()
        let zipRect = CGRect(x: p(0.5, 0.47).x - stage.width * 0.008, y: p(0.5, 0.47).y,
                              width: stage.width * 0.016, height: p(0.5, 0.99).y - p(0.5, 0.47).y)
        Shading.capsule(in: zipRect, color: Self.cardigan.adjusted(brightnessScale: 1.35), axis: .vertical, into: context)
        context.restoreGState()

        // Side hair tufts (bald on top).
        for cx: CGFloat in [headCenter.fx - headRadius * 0.92, headCenter.fx + headRadius * 0.92] {
            let tuft = UIBezierPath()
            tuft.move(to: point(cx, headCenter.fy - headRadius * 0.1, in: stage))
            tuft.addQuadCurve(to: point(cx, headCenter.fy + headRadius * 0.85, in: stage),
                               controlPoint: point(cx + (cx < headCenter.fx ? -0.05 : 0.05), headCenter.fy + headRadius * 0.4, in: stage))
            tuft.addQuadCurve(to: point(cx + (cx < headCenter.fx ? -0.05 : 0.05), headCenter.fy - headRadius * 0.1, in: stage),
                               controlPoint: point(cx + (cx < headCenter.fx ? -0.09 : 0.09), headCenter.fy + headRadius * 0.4, in: stage))
            tuft.close()
            Shading.freeform(tuft.cgPath, boundingBox: tuft.bounds, color: Self.hairShadow, into: context)
        }

        // Head.
        let headRect = CGRect(x: point(headCenter.fx, headCenter.fy, in: stage).x - stage.width * headRadius,
                               y: point(headCenter.fx, headCenter.fy, in: stage).y - stage.width * headRadius,
                               width: stage.width * headRadius * 2, height: stage.width * headRadius * 2)
        Shading.sphere(in: headRect, color: Self.skin, into: context)

        // Forehead wrinkle lines — thin recessed grooves instead of stroked
        // curves, so they read as creases in the skin rather than linework.
        context.saveGState()
        context.addEllipse(in: headRect)
        context.clip()
        for dy: CGFloat in [-0.58, -0.44] {
            let c = point(headCenter.fx, headCenter.fy + headRadius * dy, in: stage)
            let w = stage.width * headRadius * 0.85
            let h = stage.width * 0.005
            Shading.occlusion(under: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), into: context)
        }
        context.restoreGState()

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
        Shading.freeform(beard.cgPath, boundingBox: beard.bounds, color: Self.hair, into: context)

        // A little ear crescent on each side, matching the monk's approach.
        for cx: CGFloat in [headCenter.fx - headRadius * 0.98, headCenter.fx + headRadius * 0.98] {
            let c = point(cx, headCenter.fy, in: stage)
            let w = stage.width * 0.042
            let h = stage.width * 0.07
            Shading.sphere(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), color: Self.skin, into: context)
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for cx: CGFloat in [headCenter.fx - 0.06, headCenter.fx + 0.06] {
            let c = point(cx, headCenter.fy - 0.02, in: stage)

            // Heavy brow above the eye, shaded as a small stubby capsule
            // (a rounded ridge) rather than a stroked arc.
            let browRect = CGRect(x: c.x - stage.width * 0.05, y: c.y - stage.width * 0.058,
                                   width: stage.width * 0.10, height: stage.width * 0.024)
            Shading.capsule(in: browRect, color: Self.hairShadow, axis: .horizontal, into: context)

            // Deep-set eye: a small recessed socket rather than a stroked
            // curve, thinner still when blinking.
            let halfWidth = stage.width * 0.032
            let halfHeight = stage.width * (blinking ? 0.004 : 0.010)
            Shading.recess(in: CGRect(x: c.x - halfWidth, y: c.y - halfHeight, width: halfWidth * 2, height: halfHeight * 2),
                            into: context)
        }
    }
}
