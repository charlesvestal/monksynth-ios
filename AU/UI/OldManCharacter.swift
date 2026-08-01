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
        // --- Cardigan ---
        var bodyShoulderLeftX: CGFloat = 0.28
        var bodyShoulderLeftY: CGFloat = 0.52
        var bodyLeftControlX: CGFloat = 0.10
        var bodyLeftControlY: CGFloat = 0.75
        var bodyHemLeftX: CGFloat = 0.06
        var bodyHemY: CGFloat = 0.99
        var bodyHemRightX: CGFloat = 0.94
        var bodyRightControlX: CGFloat = 0.90
        var bodyRightControlY: CGFloat = 0.75
        var bodyShoulderRightX: CGFloat = 0.72
        var bodyShoulderRightY: CGFloat = 0.52
        var bodyNeckX: CGFloat = 0.5
        var bodyNeckY: CGFloat = 0.46
        var bodyNeckControlY: CGFloat = 0.52

        // --- Zip trim ---
        var zipTopY: CGFloat = 0.47
        var zipBottomY: CGFloat = 0.99
        var zipLineWidthFraction: CGFloat = 0.012

        // --- Side hair (bald on top; tufts at the sides) ---
        /// *** How far the side hair sits from the head's centre ***, in
        /// head-radius units — the tuft's outward bulge control point. Kept
        /// a little over 1.0 (past the head's own radius) so the tuft
        /// visibly puffs out past the head's silhouette instead of sitting
        /// inside it, where the head fill (drawn first now — see below)
        /// would hide it.
        var sideHairOuterRadius: CGFloat = 1.35
        /// How far in from the outer bulge the tuft's thin inner edge sits,
        /// in head-radius units — the taper that gives the tuft some body
        /// instead of reading as a flat wedge.
        var sideHairInnerTaperRadius: CGFloat = 0.68
        /// Where the tuft attaches to the head at the top, in head-radius
        /// units from centre.
        var sideHairTopAttachRadius: CGFloat = 0.88
        /// How far above the head's centre — i.e. above the equator, the
        /// head's widest point — each tuft's top sits, in head-radius
        /// units. Must stay positive (above centre) so the tuft doesn't
        /// start below the head's widest point.
        var sideHairTopLift: CGFloat = 0.38
        /// Vertical position of the tuft's two curve control points, in
        /// head-radius units above centre.
        var sideHairBulgeLift: CGFloat = 0.12

        // --- Forehead wrinkle lines ---
        /// Vertical position of each line, in head-radius units above head
        /// centre (negative values only). Kept well clear of the brow
        /// (~-0.30r) so the lines read as forehead creases, not a second
        /// pair of eyebrows sitting right on top of the first.
        var wrinkleDepths: [CGFloat] = [-0.60, -0.72, -0.85]
        /// Half-width of each line, in head-radius units, paired index-for-
        /// index with `wrinkleDepths` — varied (not a uniform width) so the
        /// band doesn't read as a mechanically regular set of identical
        /// arcs.
        var wrinkleHalfWidths: [CGFloat] = [0.50, 0.42, 0.28]
        var wrinkleCurveLift: CGFloat = 0.05
        var wrinkleLineWidthFraction: CGFloat = 0.004
        /// Kept low so the lines read as a light crease, not a bold second
        /// brow.
        var wrinkleAlpha: CGFloat = 0.30

        // --- Beard ---
        /// Where the beard attaches at the top on each side, in head-radius
        /// units.
        var beardTopCornerRadius: CGFloat = 0.98
        var beardTopCornerDepth: CGFloat = 0.05
        var beardChinControlRadius: CGFloat = 0.7
        var beardChinControlDepth: CGFloat = 1.9
        var beardChinDepth: CGFloat = 2.05
        var beardTopControlDepth: CGFloat = 0.55
        var beardStrokeLineWidthFraction: CGFloat = 0.006
        var beardStrokeAlpha: CGFloat = 0.5

        // --- Ears ---
        var earRadius: CGFloat = 0.98
        var earWidthFraction: CGFloat = 0.042
        var earHeightFraction: CGFloat = 0.07

        // --- Eyes / brows ---
        var eyeXOffset: CGFloat = 0.06
        var eyeYOffset: CGFloat = 0.02
        var browHalfWidthFraction: CGFloat = 0.045
        var browStartLiftFraction: CGFloat = 0.03
        var browEndLiftFraction: CGFloat = 0.035
        var browControlLiftFraction: CGFloat = 0.055
        var browLineWidthFraction: CGFloat = 0.022
        var eyeHalfWidthFraction: CGFloat = 0.032
        var eyeCurveDepthOpenFraction: CGFloat = 0.014
        var eyeCurveDepthBlinkFraction: CGFloat = 0.005
        var eyeLineWidthFraction: CGFloat = 0.012
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Cardigan: a simple rounded trapezoid, not the monk's robe rig —
        // a plainly different silhouette, and one small enough to keep this
        // a first pass rather than a second full costume system.
        let body = UIBezierPath()
        body.move(to: p(g.bodyShoulderLeftX, g.bodyShoulderLeftY))
        body.addQuadCurve(to: p(g.bodyHemLeftX, g.bodyHemY), controlPoint: p(g.bodyLeftControlX, g.bodyLeftControlY))
        body.addLine(to: p(g.bodyHemRightX, g.bodyHemY))
        body.addQuadCurve(to: p(g.bodyShoulderRightX, g.bodyShoulderRightY), controlPoint: p(g.bodyRightControlX, g.bodyRightControlY))
        body.addQuadCurve(to: p(g.bodyNeckX, g.bodyNeckY), controlPoint: p(g.bodyNeckX, g.bodyNeckControlY))
        body.addQuadCurve(to: p(g.bodyShoulderLeftX, g.bodyShoulderLeftY), controlPoint: p(g.bodyNeckX, g.bodyNeckControlY))
        body.close()
        Self.cardigan.setFill()
        body.fill()

        // Zip trim down the centre.
        let zipTrim = UIBezierPath()
        zipTrim.move(to: p(g.bodyNeckX, g.zipTopY))
        zipTrim.addLine(to: p(g.bodyNeckX, g.zipBottomY))
        zipTrim.lineWidth = stage.width * g.zipLineWidthFraction
        Self.cardiganTrim.setStroke()
        zipTrim.stroke()

        // Head. Filled BEFORE the side-hair tufts and wrinkles (unlike the
        // original ordering, which drew the tufts first): the tufts used
        // to sit mostly *inside* the head's own radius, so the head fill
        // silently painted over their top halves, leaving only the sliver
        // that happened to poke past the circle visible — which read as
        // "the tufts start below the head's widest point" even though the
        // path coordinates said otherwise. Drawing hair on top of skin, as
        // real hair does, makes what's coded match what's rendered.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.skin.setFill()
        head.fill()

        // A little ear crescent on each side, matching the monk's approach.
        // Drawn before the side-hair tufts (moved up from its original
        // position after the beard) so a tuft growing over the top of the
        // ear — real sideburns often do — reads as hair over ear rather
        // than being erased by the ear painting on top of it.
        for cx: CGFloat in [headCenter.fx - headRadius * g.earRadius, headCenter.fx + headRadius * g.earRadius] {
            let c = point(cx, headCenter.fy, in: stage)
            let w = stage.width * g.earWidthFraction
            let h = stage.width * g.earHeightFraction
            let ear = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            Self.skin.setFill()
            ear.fill()
        }

        // Side hair tufts (bald on top). Each tuft's bottom anchor is the
        // beard's own top-corner point (`beardTopCornerRadius`/
        // `beardTopCornerDepth`, also used below), so hair and beard always
        // meet with no seam, however either is retuned; its top sits above
        // the head's equator (`sideHairTopLift` > 0), and its belly bulges
        // out to `sideHairOuterRadius`, past the head's own silhouette, so
        // it reads as hair growing from the side rather than a detached
        // comma sitting near the head.
        for side: CGFloat in [-1, 1] {
            let bottom = point(headCenter.fx + side * headRadius * g.beardTopCornerRadius,
                                headCenter.fy + headRadius * g.beardTopCornerDepth, in: stage)
            let top = point(headCenter.fx + side * headRadius * g.sideHairTopAttachRadius,
                             headCenter.fy - headRadius * g.sideHairTopLift, in: stage)
            let outerControl = point(headCenter.fx + side * headRadius * g.sideHairOuterRadius,
                                      headCenter.fy - headRadius * g.sideHairBulgeLift, in: stage)
            let innerControl = point(headCenter.fx + side * headRadius * g.sideHairInnerTaperRadius,
                                      headCenter.fy - headRadius * g.sideHairBulgeLift, in: stage)

            let tuft = UIBezierPath()
            tuft.move(to: bottom)
            tuft.addQuadCurve(to: top, controlPoint: outerControl)
            tuft.addQuadCurve(to: bottom, controlPoint: innerControl)
            tuft.close()
            Self.hairShadow.setFill()
            tuft.fill()
        }

        // Forehead wrinkle lines.
        for (dy, halfWidth) in zip(g.wrinkleDepths, g.wrinkleHalfWidths) {
            let line = UIBezierPath()
            line.move(to: point(headCenter.fx - headRadius * halfWidth, headCenter.fy + headRadius * dy, in: stage))
            line.addQuadCurve(to: point(headCenter.fx + headRadius * halfWidth, headCenter.fy + headRadius * dy, in: stage),
                               controlPoint: point(headCenter.fx, headCenter.fy + headRadius * (dy - g.wrinkleCurveLift), in: stage))
            line.lineWidth = stage.width * g.wrinkleLineWidthFraction
            Self.hairShadow.withAlphaComponent(g.wrinkleAlpha).setStroke()
            line.stroke()
        }

        // Beard: covers the lower half of the face and chin. Drawn before
        // the mouth aperture (which `CharacterView` composites on top of
        // everything last), so the moving mouth reads as an opening within
        // the beard rather than sitting oddly on top of skin.
        let beard = UIBezierPath()
        beard.move(to: point(headCenter.fx - headRadius * g.beardTopCornerRadius, headCenter.fy + headRadius * g.beardTopCornerDepth, in: stage))
        beard.addQuadCurve(to: point(headCenter.fx, headCenter.fy + headRadius * g.beardChinDepth, in: stage),
                            controlPoint: point(headCenter.fx - headRadius * g.beardChinControlRadius, headCenter.fy + headRadius * g.beardChinControlDepth, in: stage))
        beard.addQuadCurve(to: point(headCenter.fx + headRadius * g.beardTopCornerRadius, headCenter.fy + headRadius * g.beardTopCornerDepth, in: stage),
                            controlPoint: point(headCenter.fx + headRadius * g.beardChinControlRadius, headCenter.fy + headRadius * g.beardChinControlDepth, in: stage))
        beard.addQuadCurve(to: point(headCenter.fx - headRadius * g.beardTopCornerRadius, headCenter.fy + headRadius * g.beardTopCornerDepth, in: stage),
                            controlPoint: point(headCenter.fx, headCenter.fy + headRadius * g.beardTopControlDepth, in: stage))
        beard.close()
        Self.hair.setFill()
        beard.fill()
        Self.hairShadow.withAlphaComponent(g.beardStrokeAlpha).setStroke()
        beard.lineWidth = stage.width * g.beardStrokeLineWidthFraction
        beard.stroke()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy - g.eyeYOffset, in: stage)

            // Heavy brow above the eye, always drawn.
            let brow = UIBezierPath()
            brow.move(to: CGPoint(x: c.x - stage.width * g.browHalfWidthFraction, y: c.y - stage.width * g.browStartLiftFraction))
            brow.addQuadCurve(to: CGPoint(x: c.x + stage.width * g.browHalfWidthFraction, y: c.y - stage.width * g.browEndLiftFraction),
                               controlPoint: CGPoint(x: c.x, y: c.y - stage.width * g.browControlLiftFraction))
            brow.lineWidth = stage.width * g.browLineWidthFraction
            brow.lineCapStyle = .round
            Self.hairShadow.setStroke()
            brow.stroke()

            let halfWidth = stage.width * g.eyeHalfWidthFraction
            let curveDepth = stage.width * (blinking ? g.eyeCurveDepthBlinkFraction : g.eyeCurveDepthOpenFraction)
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - halfWidth, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + halfWidth, y: c.y),
                              controlPoint: CGPoint(x: c.x, y: c.y + curveDepth))
            eye.lineWidth = stage.width * g.eyeLineWidthFraction
            eye.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            eye.stroke()
        }
    }
}
