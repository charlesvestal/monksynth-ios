import UIKit

/// A cream-white unicorn head: pointed ears, a golden horn, a flowing
/// pastel mane down one side, and a muzzle the mouth aperture opens at the
/// end of. First pass; the user will iterate on the art with the render
/// harness.
struct UnicornCharacter: Character {
    let id = "unicorn"
    let displayName = "Unicorn"

    private static let coat = UIColor(white: 0.97, alpha: 1)
    private static let coatShadow = UIColor(white: 0.90, alpha: 1)
    private static let muzzle = UIColor(red: 0.96, green: 0.86, blue: 0.80, alpha: 1)
    private static let muzzleOutline = UIColor(red: 0.80, green: 0.66, blue: 0.60, alpha: 1)
    private static let horn = UIColor(red: 0.90, green: 0.74, blue: 0.32, alpha: 1)
    private static let hornOutline = UIColor(red: 0.68, green: 0.53, blue: 0.18, alpha: 1)
    private static let maneA = UIColor(red: 0.87, green: 0.55, blue: 0.86, alpha: 1)
    private static let maneB = UIColor(red: 0.55, green: 0.72, blue: 0.93, alpha: 1)
    private static let maneC = UIColor(red: 0.96, green: 0.62, blue: 0.72, alpha: 1)

    // MARK: - Mouth anchors — a horse-ish muzzle: wide and fairly flat
    // throughout, unlike the monk's narrow-to-wide sweep or the fish's
    // round pucker, so the three sweeps are genuinely distinct shapes.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.20, 0.10), (0.34, 0.16), (0.46, 0.20), (0.54, 0.15), (0.58, 0.09),
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
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.60)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.185

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
        // --- Neck/shoulders ---
        var neckShoulderLeftX: CGFloat = 0.30
        var neckShoulderY: CGFloat = 0.55
        var neckHemLeftX: CGFloat = 0.14
        var neckHemY: CGFloat = 0.99
        var neckLeftControlX: CGFloat = 0.12
        var neckLeftControlY: CGFloat = 0.72
        var neckHemRightX: CGFloat = 0.86
        var neckShoulderRightX: CGFloat = 0.70
        var neckRightControlX: CGFloat = 0.88
        var neckRightControlY: CGFloat = 0.72

        // --- Neck fill ---
        // A second, narrower patch bridging the head's own bottom edge down
        // to the shoulder block above, flared from roughly the head's own
        // width at the top to the shoulder corners at the bottom. An
        // earlier version had only the shoulder block (`neckShoulderY`
        // 0.55) with nothing between it and the head's own bottom edge
        // (headCenter.fy + headRadius ≈ 0.485 at its narrowest, less at the
        // sides), leaving a gap of bare background either side of the
        // muzzle.
        var neckFillTopOffsetRadii: CGFloat = 0.85
        var neckFillTopHalfWidthFraction: CGFloat = 0.10

        // --- Mane strands: (root, tip, bulge-width) in stage fractions ---
        var maneRoots: [(x: CGFloat, y: CGFloat)] = [
            (0.34, 0.14), (0.38, 0.22), (0.40, 0.34),
        ]
        var maneTips: [(x: CGFloat, y: CGFloat)] = [
            (0.06, 0.46), (0.10, 0.62), (0.14, 0.80),
        ]
        var maneBulges: [CGFloat] = [0.11, 0.10, 0.095]
        var maneAlpha: CGFloat = 0.92
        var maneInnerControlXFraction: CGFloat = 0.05
        var maneInnerControlYFraction: CGFloat = 0.03

        // --- Ears ---
        var earXOffsetRadii: CGFloat = 0.7
        var earOuterHalfWidthFraction: CGFloat = 0.05
        var earOuterYBottomRadii: CGFloat = 0.55
        var earOuterYTopRadii: CGFloat = 1.85
        var earOuterTipXOffsetFraction: CGFloat = 0.006
        var earOuterStrokeLineWidthFraction: CGFloat = 0.007
        var earInnerHalfWidthFraction: CGFloat = 0.022
        var earInnerYBottomRadii: CGFloat = 0.60
        var earInnerYTopRadii: CGFloat = 1.55
        var earInnerTipXOffsetFraction: CGFloat = 0.002

        // --- Horn ---
        var hornBaseOffsetRadii: CGFloat = 0.78
        var hornTipXOffsetFraction: CGFloat = 0.018
        var hornTipOffsetRadii: CGFloat = 2.35
        var hornHalfWidthFraction: CGFloat = 0.034
        var hornStrokeLineWidthFraction: CGFloat = 0.006
        var hornSpiralTs: [CGFloat] = [0.2, 0.42, 0.64]
        var hornSpiralWidthScale: CGFloat = 0.9
        var hornSpiralEndXScale: CGFloat = 0.6
        var hornSpiralRiseFraction: CGFloat = 0.018
        var hornSpiralLineWidthFraction: CGFloat = 0.005

        // --- Muzzle ---
        // Raised and widened from an original (1.35, 0.20, 0.30). At 1.35
        // head-radii below centre with a 0.20 width, the muzzle's own top
        // edge sat well inside the head circle in y but was narrower than
        // the head's own cross-section there (a 0.10 half-width against the
        // head's ~0.16), which read as a pinched "neck" right at the
        // seam — the muzzle looked like a separate, narrower shape hung
        // below the head (the "detached feed bag" the shape had to stop
        // reading as) rather than a snout continuous with the face. Raising
        // it to 1.05 head-radii nests it much deeper inside the head's own
        // silhouette, and widening it to 0.27 keeps its own half-width
        // (0.135) close to the head's cross-section at the new, shallower
        // seam, so the two blend instead of pinching.
        var muzzleOffsetRadii: CGFloat = 1.05
        var muzzleWidthFraction: CGFloat = 0.27
        var muzzleHeightFraction: CGFloat = 0.30
        var muzzleStrokeLineWidthFraction: CGFloat = 0.008
        var nostrilDxs: [CGFloat] = [-0.032, 0.032]
        var nostrilYScale: CGFloat = 0.18
        var nostrilRadiusFraction: CGFloat = 0.011

        // --- Eyes ---
        var eyeXOffset: CGFloat = 0.075
        var eyeYOffset: CGFloat = 0.01
        var eyeLashHalfWidthFraction: CGFloat = 0.045
        var eyeLashLineWidthFraction: CGFloat = 0.014
        var eyeRadiusFraction: CGFloat = 0.048
        var eyeHeightScale: CGFloat = 1.15
        var irisRadiusScale: CGFloat = 0.62
        var irisYScale: CGFloat = 0.5
        var highlightScale: CGFloat = 0.2
        var highlightXOffsetScale: CGFloat = 1.6
        var highlightYOffsetScale: CGFloat = 1.1
        var browLashStartXScale: CGFloat = 0.7
        var browLashStartYScale: CGFloat = 0.6
        var browLashEndXScale: CGFloat = 1.3
        var browLashEndYScale: CGFloat = 1.1
        var browLashLineWidthFraction: CGFloat = 0.01
    }

    var geometry = Geometry()

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let g = geometry

        // Neck/shoulders, so the head doesn't float above nothing.
        let neck = UIBezierPath()
        neck.move(to: p(g.neckShoulderLeftX, g.neckShoulderY))
        neck.addQuadCurve(to: p(g.neckHemLeftX, g.neckHemY), controlPoint: p(g.neckLeftControlX, g.neckLeftControlY))
        neck.addLine(to: p(g.neckHemRightX, g.neckHemY))
        neck.addQuadCurve(to: p(g.neckShoulderRightX, g.neckShoulderY), controlPoint: p(g.neckRightControlX, g.neckRightControlY))
        neck.close()
        Self.coat.setFill()
        neck.fill()

        // Neck fill: bridges the head's own bottom edge down to the
        // shoulder block above, so the sides of the head — away from where
        // the muzzle itself reaches down — read as attached rather than
        // floating over background. Drawn before the head so the head fill
        // covers its top portion cleanly, the same technique
        // `MonkCharacter`/`DogCharacter` use for their own necks.
        let neckFillTop = headCenter.fy + headRadius * g.neckFillTopOffsetRadii
        let neckFill = UIBezierPath()
        neckFill.move(to: p(headCenter.fx - g.neckFillTopHalfWidthFraction, neckFillTop))
        neckFill.addLine(to: p(g.neckShoulderLeftX, g.neckShoulderY))
        neckFill.addLine(to: p(g.neckShoulderRightX, g.neckShoulderY))
        neckFill.addLine(to: p(headCenter.fx + g.neckFillTopHalfWidthFraction, neckFillTop))
        neckFill.close()
        Self.coat.setFill()
        neckFill.fill()

        // Mane: smooth teardrop strands cascading down the left side of the
        // neck/head, drawn before the head/muzzle so they read as flowing
        // *behind* the face rather than a flat polygon pasted on top.
        let maneColors = [Self.maneA, Self.maneB, Self.maneC]
        for i in 0..<maneColors.count {
            let color = maneColors[i]
            let root = g.maneRoots[i]
            let tip = g.maneTips[i]
            let bulge = g.maneBulges[i]
            let r = p(root.x, root.y)
            let t = p(tip.x, tip.y)
            let mid = CGPoint(x: (r.x + t.x) / 2 - stage.width * bulge, y: (r.y + t.y) / 2)
            let strand = UIBezierPath()
            strand.move(to: r)
            strand.addQuadCurve(to: t, controlPoint: mid)
            strand.addQuadCurve(to: r, controlPoint: CGPoint(x: mid.x + stage.width * g.maneInnerControlXFraction, y: mid.y + stage.width * g.maneInnerControlYFraction))
            strand.close()
            color.withAlphaComponent(g.maneAlpha).setFill()
            strand.fill()
        }

        // Ears: tall, clearly pointed horse-style triangles well up and
        // apart on top of the head, with a soft pink inner-ear hint.
        for cx: CGFloat in [headCenter.fx - headRadius * g.earXOffsetRadii, headCenter.fx + headRadius * g.earXOffsetRadii] {
            let ear = UIBezierPath()
            ear.move(to: point(cx - g.earOuterHalfWidthFraction, headCenter.fy - headRadius * g.earOuterYBottomRadii, in: stage))
            ear.addLine(to: point(cx - g.earOuterTipXOffsetFraction, headCenter.fy - headRadius * g.earOuterYTopRadii, in: stage))
            ear.addLine(to: point(cx + g.earOuterHalfWidthFraction, headCenter.fy - headRadius * g.earOuterYBottomRadii, in: stage))
            ear.close()
            Self.coat.setFill()
            ear.fill()
            Self.coatShadow.setStroke()
            ear.lineWidth = stage.width * g.earOuterStrokeLineWidthFraction
            ear.stroke()

            let inner = UIBezierPath()
            inner.move(to: point(cx - g.earInnerHalfWidthFraction, headCenter.fy - headRadius * g.earInnerYBottomRadii, in: stage))
            inner.addLine(to: point(cx - g.earInnerTipXOffsetFraction, headCenter.fy - headRadius * g.earInnerYTopRadii, in: stage))
            inner.addLine(to: point(cx + g.earInnerHalfWidthFraction, headCenter.fy - headRadius * g.earInnerYBottomRadii, in: stage))
            inner.close()
            UIColor(red: 0.93, green: 0.75, blue: 0.78, alpha: 0.85).setFill()
            inner.fill()
        }

        // Horn: a tall golden spiral cone rising between the ears — the
        // single most important silhouette cue, so it is deliberately taller
        // and more strongly outlined than a realistic proportion would be.
        let hornBase = point(headCenter.fx, headCenter.fy - headRadius * g.hornBaseOffsetRadii, in: stage)
        let hornTip = point(headCenter.fx + g.hornTipXOffsetFraction, headCenter.fy - headRadius * g.hornTipOffsetRadii, in: stage)
        let hornHalfWidth = stage.width * g.hornHalfWidthFraction
        let horn = UIBezierPath()
        horn.move(to: CGPoint(x: hornBase.x - hornHalfWidth, y: hornBase.y))
        horn.addLine(to: hornTip)
        horn.addLine(to: CGPoint(x: hornBase.x + hornHalfWidth, y: hornBase.y))
        horn.close()
        Self.horn.setFill()
        horn.fill()
        Self.hornOutline.setStroke()
        horn.lineWidth = stage.width * g.hornStrokeLineWidthFraction
        horn.stroke()
        // Spiral hints: short diagonals climbing the horn's length.
        for t in g.hornSpiralTs {
            let y = hornBase.y - (hornBase.y - hornTip.y) * t
            let halfW = hornHalfWidth * (1 - t) * g.hornSpiralWidthScale
            let line = UIBezierPath()
            line.move(to: CGPoint(x: hornBase.x - halfW, y: y))
            line.addLine(to: CGPoint(x: hornBase.x + halfW * g.hornSpiralEndXScale, y: y - stage.width * g.hornSpiralRiseFraction))
            line.lineWidth = stage.width * g.hornSpiralLineWidthFraction
            Self.hornOutline.setStroke()
            line.stroke()
        }

        // Head: round.
        let head = UIBezierPath(arcCenter: point(headCenter.fx, headCenter.fy, in: stage),
                                 radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.coat.setFill()
        head.fill()

        // Muzzle: narrower than the head and clearly elongated downward
        // past its silhouette — a distinct protruding snout rather than a
        // flat patch on the face, with its own warm tone and outline so it
        // reads at a glance even at small sizes.
        let muzzleCenter = point(mouthCentre.fx, headCenter.fy + headRadius * g.muzzleOffsetRadii, in: stage)
        let muzzleW = stage.width * g.muzzleWidthFraction
        let muzzleH = stage.width * g.muzzleHeightFraction
        let muzzleRect = CGRect(x: muzzleCenter.x - muzzleW / 2, y: muzzleCenter.y - muzzleH / 2,
                                 width: muzzleW, height: muzzleH)
        let muzzle = UIBezierPath(ovalIn: muzzleRect)
        Self.muzzle.setFill()
        muzzle.fill()
        Self.muzzleOutline.setStroke()
        muzzle.lineWidth = stage.width * g.muzzleStrokeLineWidthFraction
        muzzle.stroke()

        // Nostril dots, upper-front of the muzzle.
        for dx in g.nostrilDxs {
            let nc = CGPoint(x: muzzleCenter.x + dx * stage.width, y: muzzleCenter.y - muzzleH * g.nostrilYScale)
            let r = stage.width * g.nostrilRadiusFraction
            let nostril = UIBezierPath(ovalIn: CGRect(x: nc.x - r, y: nc.y - r, width: r * 2, height: r * 2))
            UIColor.black.withAlphaComponent(0.45).setFill()
            nostril.fill()
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let g = geometry
        for cx: CGFloat in [headCenter.fx - g.eyeXOffset, headCenter.fx + g.eyeXOffset] {
            let c = point(cx, headCenter.fy - g.eyeYOffset, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * g.eyeLashHalfWidthFraction, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * g.eyeLashHalfWidthFraction, y: c.y))
                lash.lineWidth = stage.width * g.eyeLashLineWidthFraction
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * g.eyeRadiusFraction
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * g.eyeHeightScale))
            UIColor.white.setFill()
            eye.fill()
            let irisR = r * g.irisRadiusScale
            let iris = UIBezierPath(ovalIn: CGRect(x: c.x - irisR, y: c.y - irisR * g.irisYScale, width: irisR * 2, height: irisR * 2))
            UIColor(red: 0.34, green: 0.22, blue: 0.10, alpha: 1).setFill()
            iris.fill()
            let hl = r * g.highlightScale
            let highlight = UIBezierPath(ovalIn: CGRect(x: c.x - hl * g.highlightXOffsetScale, y: c.y - hl * g.highlightYOffsetScale, width: hl * 2, height: hl * 2))
            UIColor.white.setFill()
            highlight.fill()
            // A short lash flick — the girlish-friendly cue that reads
            // instantly at small sizes even without detail.
            let lash = UIBezierPath()
            lash.move(to: CGPoint(x: c.x + r * g.browLashStartXScale, y: c.y - r * g.browLashStartYScale))
            lash.addLine(to: CGPoint(x: c.x + r * g.browLashEndXScale, y: c.y - r * g.browLashEndYScale))
            lash.lineWidth = stage.width * g.browLashLineWidthFraction
            lash.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            lash.stroke()
        }
    }
}
