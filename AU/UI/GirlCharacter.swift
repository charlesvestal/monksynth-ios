import UIKit

/// A little girl: a head over a big A-line dress, two round pigtails, and
/// big friendly eyes. Rebuilt against the 90s pre-rendered-3D style spec,
/// and two specific weaknesses the design review called out are fixed here:
/// the "hands" used to be two disconnected floating circles with nothing
/// joining them to the body — they're now proper tapered arms (shaded
/// tubes, `Shading.capsule`) running from a shoulder seam down to a small
/// hand, with a contact shadow at the shoulder so they read as attached.
/// And the head-to-dress ratio used to make her read as a traffic cone —
/// the head is bigger now and the dress starts from a rounded shoulder yoke
/// instead of a single sharp apex point at the neck, which was the other
/// half of that cue.
struct GirlCharacter: Character {
    let id = "girl"
    let displayName = "Little Girl"

    private static let hair = UIColor(red: 0.36, green: 0.20, blue: 0.13, alpha: 1)
    private static let dress = UIColor(red: 0.80, green: 0.32, blue: 0.52, alpha: 1)
    private static let cheek = UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 1)
    private static let iris = UIColor(red: 0.20, green: 0.42, blue: 0.30, alpha: 1)

    // MARK: - Mouth anchors — small throughout, unlike every other
    // character's sweep: a child's mouth barely opens at the low end and
    // stays compact even at the wide end.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.10, 0.16), (0.16, 0.20), (0.22, 0.15), (0.26, 0.10), (0.30, 0.06),
    ]

    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    let mouthBoxFraction: CGFloat = 0.26
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.275)

    // Bigger than the original 0.115 — the head-to-body ratio was reading
    // as a traffic cone; a bigger head is half the fix (the other half is
    // the rounded shoulder yoke `drawDress` uses instead of a sharp apex).
    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.215))
    private let headRadius: CGFloat = 0.145

    func drawBody(in stage: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        drawDress(in: stage, into: context)
        drawArms(in: stage, into: context)
        drawNeck(in: stage, into: context)
        drawPigtails(in: stage, into: context)
        drawHead(in: stage, into: context)
    }

    private func drawDress(in stage: CGRect, into context: CGContext) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // A big A-line dress — most of the stage is body, not head, on
        // purpose — but starting from a rounded shoulder yoke rather than a
        // single point at the neck, so the silhouette reads as a dress with
        // shoulders instead of a cone.
        let dress = UIBezierPath()
        dress.move(to: p(0.32, 0.42))
        dress.addQuadCurve(to: p(0.09, 0.99), controlPoint: p(0.15, 0.68))
        dress.addLine(to: p(0.91, 0.99))
        dress.addQuadCurve(to: p(0.68, 0.42), controlPoint: p(0.85, 0.68))
        dress.addQuadCurve(to: p(0.32, 0.42), controlPoint: p(0.5, 0.35))
        dress.close()
        Shading.freeform(dress.cgPath, boundingBox: dress.bounds, color: Self.dress, into: context)

        // Hem band, shaded as its own strip so it reads as a trimmed edge
        // rather than a flat stripe.
        context.saveGState()
        dress.addClip()
        let hem = UIBezierPath()
        hem.move(to: p(0.09, 0.90))
        hem.addLine(to: p(0.91, 0.90))
        hem.addLine(to: p(0.91, 0.99))
        hem.addLine(to: p(0.09, 0.99))
        hem.close()
        hem.addClip()
        Shading.radialShade(in: dress.bounds, color: Self.dress.adjusted(brightnessScale: 0.72), into: context)
        context.restoreGState()
    }

    /// Proper arms — a shaded tapered tube from a shoulder seam down to a
    /// small hand, instead of the free-floating circles this used to be.
    /// `Shading.capsule` only shades along its own rect's horizontal or
    /// vertical axis, so the rect is built pointing straight down in a
    /// local frame and the context is rotated to aim it from shoulder to
    /// hand — the same technique `Shading.cone`'s doc comment describes for
    /// a non-upright taper.
    private func drawArms(in stage: CGRect, into context: CGContext) {
        let shoulders: [CGPoint] = [point(0.31, 0.46, in: stage), point(0.69, 0.46, in: stage)]
        let hands: [CGPoint] = [point(0.22, 0.65, in: stage), point(0.78, 0.65, in: stage)]
        let armWidth = stage.width * 0.10

        for (shoulder, hand) in zip(shoulders, hands) {
            let dx = hand.x - shoulder.x
            let dy = hand.y - shoulder.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            let angle = atan2(-dx, dy)

            context.saveGState()
            context.translateBy(x: shoulder.x, y: shoulder.y)
            context.rotate(by: angle)
            let armRect = CGRect(x: -armWidth / 2, y: -armWidth * 0.3, width: armWidth, height: length + armWidth * 0.3)
            Shading.capsule(in: armRect, color: Theme.skin, axis: .vertical, into: context)

            // Contact shadow where the arm tucks under the shoulder seam.
            Shading.occlusion(under: CGRect(x: -armWidth * 0.6, y: -armWidth * 0.2,
                                             width: armWidth * 1.2, height: armWidth * 0.7),
                               into: context)
            context.restoreGState()

            // A small rounded hand at the far end.
            let handR = armWidth * 0.62
            Shading.sphere(in: CGRect(x: hand.x - handR, y: hand.y - handR, width: handR * 2, height: handR * 2),
                            color: Theme.skin, into: context)
        }
    }

    /// A short skin-toned neck so the (now bigger) head never appears to
    /// float above the dress's rounded yoke.
    private func drawNeck(in stage: CGRect, into context: CGContext) {
        let c = point(headCenter.fx, headCenter.fy + headRadius * 0.9, in: stage)
        let w = stage.width * 0.07
        let h = stage.width * 0.09
        Shading.capsule(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                         color: Theme.skin, axis: .vertical, into: context)
        Shading.occlusion(under: CGRect(x: c.x - w * 0.7, y: c.y + h * 0.15, width: w * 1.4, height: h * 0.4), into: context)
    }

    private func drawPigtails(in stage: CGRect, into context: CGContext) {
        for cx: CGFloat in [headCenter.fx - headRadius * 1.5, headCenter.fx + headRadius * 1.5] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            let r = stage.width * headRadius * 0.60
            Shading.sphere(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), color: Self.hair, into: context)

            // A short tapered lock trailing down from each bun, shaded as a
            // small capsule rather than a stroked wisp line.
            let outward: CGFloat = cx < headCenter.fx ? -1 : 1
            let lockLength = r * 1.6
            context.saveGState()
            context.translateBy(x: c.x, y: c.y + r * 0.5)
            context.rotate(by: outward * 0.35)
            let lockRect = CGRect(x: -r * 0.28, y: 0, width: r * 0.56, height: lockLength)
            Shading.capsule(in: lockRect, color: Self.hair, axis: .vertical, into: context)
            context.restoreGState()
        }
    }

    private func drawHead(in stage: CGRect, into context: CGContext) {
        let c = point(headCenter.fx, headCenter.fy, in: stage)
        let headRect = CGRect(x: c.x - stage.width * headRadius, y: c.y - stage.width * headRadius,
                               width: stage.width * headRadius * 2, height: stage.width * headRadius * 2)
        Shading.sphere(in: headRect, color: Theme.skin, into: context)

        // Fringe/bangs across the forehead.
        let bangs = UIBezierPath()
        bangs.move(to: point(headCenter.fx - headRadius * 0.95, headCenter.fy - headRadius * 0.25, in: stage))
        bangs.addQuadCurve(to: point(headCenter.fx, headCenter.fy - headRadius * 0.85, in: stage),
                            controlPoint: point(headCenter.fx - headRadius * 0.4, headCenter.fy - headRadius * 1.15, in: stage))
        bangs.addQuadCurve(to: point(headCenter.fx + headRadius * 0.95, headCenter.fy - headRadius * 0.25, in: stage),
                            controlPoint: point(headCenter.fx + headRadius * 0.4, headCenter.fy - headRadius * 1.15, in: stage))
        bangs.addQuadCurve(to: point(headCenter.fx, headCenter.fy - headRadius * 0.42, in: stage),
                            controlPoint: point(headCenter.fx, headCenter.fy - headRadius * 0.55, in: stage))
        bangs.close()
        Shading.freeform(bangs.cgPath, boundingBox: headRect, color: Self.hair, into: context)

        // Rosy cheeks — a soft, low-alpha blush sphere.
        for cx: CGFloat in [headCenter.fx - headRadius * 0.7, headCenter.fx + headRadius * 0.7] {
            let cc = point(cx, headCenter.fy + headRadius * 0.35, in: stage)
            let r = stage.width * headRadius * 0.30
            Shading.sphere(in: CGRect(x: cc.x - r, y: cc.y - r, width: r * 2, height: r * 2),
                            color: Self.cheek.withAlphaComponent(0.45), into: context)
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for cx: CGFloat in [headCenter.fx - 0.05, headCenter.fx + 0.05] {
            let c = point(cx, headCenter.fy, in: stage)
            if blinking {
                let w = stage.width * 0.05
                let h = stage.width * 0.009
                Shading.recess(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), into: context)
                continue
            }
            let r = stage.width * 0.034
            Shading.sphere(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), color: .white, into: context)
            let irisR = r * 0.68
            Shading.sphere(in: CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2),
                            color: Self.iris, into: context)
        }
    }
}
