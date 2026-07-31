import UIKit

/// A cream-white unicorn head: pointed ears, a golden horn, a flowing
/// pastel mane down one side, and a muzzle the mouth aperture opens at the
/// end of. Rebuilt against the 90s pre-rendered-3D style spec: every surface
/// shades through `Shading`'s primitives, nothing is stroked, and two
/// specific weaknesses the design review called out are fixed here —
/// the muzzle now reads as a form growing out of the face (a soft contact
/// shadow at the seam, an overlapping "bridge", its own gentle highlight)
/// rather than a flat ellipse sitting on top of it, and the eyes lost the
/// angled lash-flick that read as an annoyed/furrowed brow — they're just
/// big, round, and softly lidded now.
struct UnicornCharacter: Character {
    let id = "unicorn"
    let displayName = "Unicorn"

    private static let coat = UIColor(white: 0.97, alpha: 1)
    private static let muzzle = UIColor(red: 0.96, green: 0.86, blue: 0.80, alpha: 1)
    private static let horn = UIColor(red: 0.90, green: 0.74, blue: 0.32, alpha: 1)
    private static let maneA = UIColor(red: 0.87, green: 0.55, blue: 0.86, alpha: 1)
    private static let maneB = UIColor(red: 0.55, green: 0.72, blue: 0.93, alpha: 1)
    private static let maneC = UIColor(red: 0.96, green: 0.62, blue: 0.72, alpha: 1)
    private static let innerEar = UIColor(red: 0.93, green: 0.75, blue: 0.78, alpha: 1)
    private static let iris = UIColor(red: 0.34, green: 0.22, blue: 0.10, alpha: 1)

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
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.585)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.185

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Neck/shoulders, so the head doesn't float above nothing.
        let neck = UIBezierPath()
        neck.move(to: p(0.30, 0.55))
        neck.addQuadCurve(to: p(0.14, 0.99), controlPoint: p(0.12, 0.72))
        neck.addLine(to: p(0.86, 0.99))
        neck.addQuadCurve(to: p(0.70, 0.55), controlPoint: p(0.88, 0.72))
        neck.close()
        Shading.freeform(neck.cgPath, boundingBox: neck.bounds, color: Self.coat, into: context)

        // Mane: smooth teardrop strands cascading down the left side of the
        // neck/head, drawn before the head/muzzle so they read as flowing
        // *behind* the face rather than a flat polygon pasted on top.
        let maneStrands: [(UIColor, CGPoint, CGPoint, CGFloat)] = [
            (Self.maneA, CGPoint(x: 0.34, y: 0.14), CGPoint(x: 0.06, y: 0.46), 0.11),
            (Self.maneB, CGPoint(x: 0.38, y: 0.22), CGPoint(x: 0.10, y: 0.62), 0.10),
            (Self.maneC, CGPoint(x: 0.40, y: 0.34), CGPoint(x: 0.14, y: 0.80), 0.095),
        ]
        for (color, root, tip, bulge) in maneStrands {
            let r = p(root.x, root.y)
            let t = p(tip.x, tip.y)
            let mid = CGPoint(x: (r.x + t.x) / 2 - stage.width * bulge, y: (r.y + t.y) / 2)
            let strand = UIBezierPath()
            strand.move(to: r)
            strand.addQuadCurve(to: t, controlPoint: mid)
            strand.addQuadCurve(to: r, controlPoint: CGPoint(x: mid.x + stage.width * 0.05, y: mid.y + stage.width * 0.03))
            strand.close()
            Shading.freeform(strand.cgPath, boundingBox: strand.bounds, color: color, into: context)
        }

        // Ears: tall, clearly pointed horse-style triangles well up and
        // apart on top of the head, with a soft pink inner-ear hint.
        for cx: CGFloat in [headCenter.fx - headRadius * 0.7, headCenter.fx + headRadius * 0.7] {
            let ear = UIBezierPath()
            ear.move(to: point(cx - 0.05, headCenter.fy - headRadius * 0.55, in: stage))
            ear.addLine(to: point(cx - 0.006, headCenter.fy - headRadius * 1.85, in: stage))
            ear.addLine(to: point(cx + 0.05, headCenter.fy - headRadius * 0.55, in: stage))
            ear.close()
            Shading.freeform(ear.cgPath, boundingBox: ear.bounds, color: Self.coat, into: context)

            let inner = UIBezierPath()
            inner.move(to: point(cx - 0.022, headCenter.fy - headRadius * 0.60, in: stage))
            inner.addLine(to: point(cx - 0.002, headCenter.fy - headRadius * 1.55, in: stage))
            inner.addLine(to: point(cx + 0.022, headCenter.fy - headRadius * 0.60, in: stage))
            inner.close()
            Shading.freeform(inner.cgPath, boundingBox: ear.bounds, color: Self.innerEar, into: context)
        }

        // Horn: a tall golden cone rising between the ears — the single
        // most important silhouette cue, so it is deliberately taller than
        // a realistic proportion would be. `Shading.cone` alone reads as a
        // clean, smooth spike at the small sizes this renders at; a first
        // pass added recessed rings climbing it for a spiral cue, but at
        // ~120pt those just read as a stack of separate segments, so the
        // taper is left smooth.
        let hornBase = point(headCenter.fx, headCenter.fy - headRadius * 0.78, in: stage)
        let hornTip = point(headCenter.fx, headCenter.fy - headRadius * 2.35, in: stage)
        let hornHalfWidth = stage.width * 0.036
        let hornRect = CGRect(x: hornBase.x - hornHalfWidth, y: hornTip.y,
                               width: hornHalfWidth * 2, height: hornBase.y - hornTip.y)
        Shading.cone(in: hornRect, color: Self.horn, into: context)

        // Head: round.
        let headRect = CGRect(x: point(headCenter.fx, headCenter.fy, in: stage).x - stage.width * headRadius,
                               y: point(headCenter.fx, headCenter.fy, in: stage).y - stage.width * headRadius,
                               width: stage.width * headRadius * 2, height: stage.width * headRadius * 2)
        Shading.sphere(in: headRect, color: Self.coat, into: context)

        drawMuzzle(in: stage, into: context)
    }

    /// The muzzle, rebuilt so it reads as a form growing out of the face
    /// rather than a flat ellipse pasted on top of it: it overlaps well up
    /// into the head's own silhouette (instead of merely touching its
    /// bottom edge), a soft occlusion shadow sits right at that seam like a
    /// real contact shadow under a brow ridge, and — critically — there is
    /// no stroked outline ringing it, which was the strongest "cutout mask"
    /// cue in the previous pass.
    private func drawMuzzle(in stage: CGRect, into context: CGContext) {
        let headPoint = point(headCenter.fx, headCenter.fy, in: stage)
        let muzzleCenter = point(mouthCentre.fx, headCenter.fy + headRadius * 1.06, in: stage)
        let muzzleW = stage.width * 0.20
        let muzzleH = stage.width * 0.30
        let muzzleRect = CGRect(x: muzzleCenter.x - muzzleW / 2, y: muzzleCenter.y - muzzleH / 2,
                                 width: muzzleW, height: muzzleH)
        Shading.sphere(in: muzzleRect, color: Self.muzzle, into: context)

        // A soft coat-coloured wash over just the muzzle's top, so the
        // coat-to-muzzle colour change reads as a gradient in the fur —
        // like a real horse's tan-to-white blend at the nose bridge —
        // rather than a hard edge between two overlapping shapes.
        context.saveGState()
        context.addEllipse(in: muzzleRect)
        context.clip()
        context.clip(to: CGRect(x: muzzleRect.minX, y: muzzleRect.minY, width: muzzleRect.width, height: muzzleRect.height * 0.4))
        Shading.radialShade(in: CGRect(x: headPoint.x - stage.width * headRadius, y: headPoint.y - stage.width * headRadius,
                                        width: stage.width * headRadius * 2, height: stage.width * headRadius * 2),
                             color: Self.coat.withAlphaComponent(0.45), into: context)
        context.restoreGState()

        // A soft contact shadow right where the muzzle meets the head, so
        // the join reads as one form growing from another rather than two
        // shapes overlapping.
        let seamY = headPoint.y + stage.width * headRadius * 0.55
        Shading.occlusion(under: CGRect(x: muzzleCenter.x - muzzleW * 0.42, y: seamY - stage.width * 0.02,
                                         width: muzzleW * 0.84, height: stage.width * 0.09),
                           into: context)

        // Nostrils as small recessed holes, not flat dots.
        for dx: CGFloat in [-0.032, 0.032] {
            let nc = CGPoint(x: muzzleCenter.x + dx * stage.width, y: muzzleCenter.y - muzzleH * 0.16)
            let nr = stage.width * 0.013
            Shading.recess(in: CGRect(x: nc.x - nr, y: nc.y - nr * 0.8, width: nr * 2, height: nr * 1.6), into: context)
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for cx: CGFloat in [headCenter.fx - 0.075, headCenter.fx + 0.075] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            if blinking {
                let w = stage.width * 0.09
                let h = stage.width * 0.012
                Shading.recess(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), into: context)
                continue
            }
            let r = stage.width * 0.048
            let eyeRect = CGRect(x: c.x - r, y: c.y - r * 0.575, width: r * 2, height: r * 1.15)
            Shading.sphere(in: eyeRect, color: .white, into: context)

            let irisR = r * 0.62
            let irisRect = CGRect(x: c.x - irisR, y: c.y - irisR * 0.5, width: irisR * 2, height: irisR * 2)
            Shading.sphere(in: irisRect, color: Self.iris, into: context)

            // A soft upper-lid shadow, not an angled lash mark — gentle
            // rather than the sharp diagonal accent that used to read as a
            // furrowed, annoyed brow.
            let lidRect = CGRect(x: c.x - r * 0.95, y: c.y - r * 0.62, width: r * 1.9, height: r * 0.55)
            Shading.occlusion(under: lidRect, into: context)
        }
    }
}
