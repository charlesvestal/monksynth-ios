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

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Neck/shoulders, so the head doesn't float above nothing.
        let neck = UIBezierPath()
        neck.move(to: p(0.30, 0.55))
        neck.addQuadCurve(to: p(0.14, 0.99), controlPoint: p(0.12, 0.72))
        neck.addLine(to: p(0.86, 0.99))
        neck.addQuadCurve(to: p(0.70, 0.55), controlPoint: p(0.88, 0.72))
        neck.close()
        Self.coat.setFill()
        neck.fill()

        // Mane: smooth teardrop strands cascading down the left side of the
        // neck/head, drawn before the head/muzzle so they read as flowing
        // *behind* the face rather than a flat polygon pasted on top.
        let maneStrands: [(UIColor, CGPoint, CGPoint, CGFloat)] = [
            // (colour, root on the head/neck, tip, bulge width)
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
            color.withAlphaComponent(0.92).setFill()
            strand.fill()
        }

        // Ears: tall, clearly pointed horse-style triangles well up and
        // apart on top of the head, with a soft pink inner-ear hint.
        for cx: CGFloat in [headCenter.fx - headRadius * 0.7, headCenter.fx + headRadius * 0.7] {
            let ear = UIBezierPath()
            ear.move(to: point(cx - 0.05, headCenter.fy - headRadius * 0.55, in: stage))
            ear.addLine(to: point(cx - 0.006, headCenter.fy - headRadius * 1.85, in: stage))
            ear.addLine(to: point(cx + 0.05, headCenter.fy - headRadius * 0.55, in: stage))
            ear.close()
            Self.coat.setFill()
            ear.fill()
            Self.coatShadow.setStroke()
            ear.lineWidth = stage.width * 0.007
            ear.stroke()

            let inner = UIBezierPath()
            inner.move(to: point(cx - 0.022, headCenter.fy - headRadius * 0.60, in: stage))
            inner.addLine(to: point(cx - 0.002, headCenter.fy - headRadius * 1.55, in: stage))
            inner.addLine(to: point(cx + 0.022, headCenter.fy - headRadius * 0.60, in: stage))
            inner.close()
            UIColor(red: 0.93, green: 0.75, blue: 0.78, alpha: 0.85).setFill()
            inner.fill()
        }

        // Horn: a tall golden spiral cone rising between the ears — the
        // single most important silhouette cue, so it is deliberately taller
        // and more strongly outlined than a realistic proportion would be.
        let hornBase = point(headCenter.fx, headCenter.fy - headRadius * 0.78, in: stage)
        let hornTip = point(headCenter.fx + 0.018, headCenter.fy - headRadius * 2.35, in: stage)
        let hornHalfWidth = stage.width * 0.034
        let horn = UIBezierPath()
        horn.move(to: CGPoint(x: hornBase.x - hornHalfWidth, y: hornBase.y))
        horn.addLine(to: hornTip)
        horn.addLine(to: CGPoint(x: hornBase.x + hornHalfWidth, y: hornBase.y))
        horn.close()
        Self.horn.setFill()
        horn.fill()
        Self.hornOutline.setStroke()
        horn.lineWidth = stage.width * 0.006
        horn.stroke()
        // Spiral hints: short diagonals climbing the horn's length.
        for t: CGFloat in [0.2, 0.42, 0.64] {
            let y = hornBase.y - (hornBase.y - hornTip.y) * t
            let halfW = hornHalfWidth * (1 - t) * 0.9
            let line = UIBezierPath()
            line.move(to: CGPoint(x: hornBase.x - halfW, y: y))
            line.addLine(to: CGPoint(x: hornBase.x + halfW * 0.6, y: y - stage.width * 0.018))
            line.lineWidth = stage.width * 0.005
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
        let muzzleCenter = point(mouthCentre.fx, headCenter.fy + headRadius * 1.35, in: stage)
        let muzzleW = stage.width * 0.20
        let muzzleH = stage.width * 0.30
        let muzzleRect = CGRect(x: muzzleCenter.x - muzzleW / 2, y: muzzleCenter.y - muzzleH / 2,
                                 width: muzzleW, height: muzzleH)
        let muzzle = UIBezierPath(ovalIn: muzzleRect)
        Self.muzzle.setFill()
        muzzle.fill()
        Self.muzzleOutline.setStroke()
        muzzle.lineWidth = stage.width * 0.008
        muzzle.stroke()

        // Nostril dots, upper-front of the muzzle.
        for dx: CGFloat in [-0.032, 0.032] {
            let nc = CGPoint(x: muzzleCenter.x + dx * stage.width, y: muzzleCenter.y - muzzleH * 0.18)
            let r = stage.width * 0.011
            let nostril = UIBezierPath(ovalIn: CGRect(x: nc.x - r, y: nc.y - r, width: r * 2, height: r * 2))
            UIColor.black.withAlphaComponent(0.45).setFill()
            nostril.fill()
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [headCenter.fx - 0.075, headCenter.fx + 0.075] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.045, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.045, y: c.y))
                lash.lineWidth = stage.width * 0.014
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * 0.048
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 1.15))
            UIColor.white.setFill()
            eye.fill()
            let irisR = r * 0.62
            let iris = UIBezierPath(ovalIn: CGRect(x: c.x - irisR, y: c.y - irisR * 0.5, width: irisR * 2, height: irisR * 2))
            UIColor(red: 0.34, green: 0.22, blue: 0.10, alpha: 1).setFill()
            iris.fill()
            let hl = r * 0.2
            let highlight = UIBezierPath(ovalIn: CGRect(x: c.x - hl * 1.6, y: c.y - hl * 1.1, width: hl * 2, height: hl * 2))
            UIColor.white.setFill()
            highlight.fill()
            // A short lash flick — the girlish-friendly cue that reads
            // instantly at small sizes even without detail.
            let lash = UIBezierPath()
            lash.move(to: CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.6))
            lash.addLine(to: CGPoint(x: c.x + r * 1.3, y: c.y - r * 1.1))
            lash.lineWidth = stage.width * 0.01
            lash.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            lash.stroke()
        }
    }
}
