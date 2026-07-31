import UIKit

/// A front-facing cow head over simple rounded shoulders: floppy ears
/// sticking out sideways, a pair of small stubby horns, an irregular dark
/// patch over one eye and another on the shoulder, and a big pale muzzle the
/// wide-set nostrils and the mouth aperture sit inside. The muzzle is
/// deliberately oversized relative to the rest of the face — per the design
/// brief, the mouth is the instrument, and a big pale patch on an otherwise
/// two-tone coat is the natural place to put a wide, clearly-morphing
/// aperture that still reads at ~120pt.
struct CowCharacter: Character {
    let id = "cow"
    let displayName = "Cow"

    // MARK: - Derived tones
    //
    // Every colour here is derived in HSB space from an existing `Theme`
    // colour via `adjusted`, the same approach `MonkCharacter` uses for its
    // robe tones, rather than hand-picked constants that could drift: a
    // warm near-white coat from `Theme.skin` desaturated and brightened,
    // dark patches from `Theme.robeShadow` darkened, and a pale pink-tan
    // muzzle from `Theme.skin` lightened further still.
    private static let coat = Theme.skin.adjusted(saturationScale: 0.22, brightnessScale: 1.24)
    private static let coatShadow = Self.coat.adjusted(brightnessScale: 0.90)
    private static let patch = Theme.robeShadow.adjusted(saturationScale: 0.85, brightnessScale: 0.42)
    private static let muzzle = Theme.skin.adjusted(saturationScale: 0.58, brightnessScale: 1.12)
    private static let muzzleOutline = Theme.skin.adjusted(saturationScale: 0.85, brightnessScale: 0.66)
    private static let horn = Self.coat.adjusted(brightnessScale: 0.80)
    private static let hornOutline = Self.horn.adjusted(brightnessScale: 0.55)
    private static let earInner = Theme.skin.adjusted(saturationScale: 0.65, brightnessScale: 0.90)

    // MARK: - Mouth anchors — broad and comparatively flat throughout: a
    // wide grazing mouth, distinct from the monk's narrow-to-wide sweep, the
    // fish's round pucker, and the unicorn/old-man's narrower muzzle/beard
    // openings.
    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.18, 0.08), (0.30, 0.14), (0.42, 0.20), (0.50, 0.13), (0.56, 0.07),
    ]

    /// Continuous interpolation across the five anchor shapes above. Callers
    /// pass a `CharacterView.quantisedVowel(_:)` value, which is what
    /// produces the stepped frame-by-frame motion; this function itself
    /// stays smooth so the anchor geometry can be reasoned about and tested
    /// independently of the stepping.
    func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(Self.mouthAnchors.count - 1)
        let i = min(Int(scaled), Self.mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = Self.mouthAnchors[i], b = Self.mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    /// A wide local reference frame — the muzzle is broad, so the aperture
    /// at its widest anchor needs the room to stay inside it.
    let mouthBoxFraction: CGFloat = 0.34
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.60)

    private let headCenter = (fx: CGFloat(0.5), fy: CGFloat(0.27))
    private let headRadius: CGFloat = 0.19

    func drawBody(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Shoulders: a simple rounded trapezoid, coat-coloured.
        let body = UIBezierPath()
        body.move(to: p(0.22, 0.64))
        body.addQuadCurve(to: p(0.05, 0.99), controlPoint: p(0.06, 0.84))
        body.addLine(to: p(0.95, 0.99))
        body.addQuadCurve(to: p(0.78, 0.64), controlPoint: p(0.94, 0.84))
        body.addQuadCurve(to: p(0.5, 0.575), controlPoint: p(0.5, 0.64))
        body.addQuadCurve(to: p(0.22, 0.64), controlPoint: p(0.5, 0.64))
        body.close()
        Self.coat.setFill()
        body.fill()

        // A single irregular dark patch low on the shoulder, clipped to the
        // body's own silhouette so the blob can never spill past the coat's
        // outline (the same technique `MonkCharacter` uses for its drape
        // line).
        context.saveGState()
        body.addClip()
        let bodyPatch = UIBezierPath()
        bodyPatch.move(to: p(0.60, 0.68))
        bodyPatch.addQuadCurve(to: p(0.90, 0.80), controlPoint: p(0.86, 0.62))
        bodyPatch.addQuadCurve(to: p(0.82, 0.99), controlPoint: p(0.97, 0.92))
        bodyPatch.addQuadCurve(to: p(0.56, 0.90), controlPoint: p(0.70, 0.99))
        bodyPatch.addQuadCurve(to: p(0.60, 0.68), controlPoint: p(0.52, 0.80))
        bodyPatch.close()
        Self.patch.setFill()
        bodyPatch.fill()
        context.restoreGState()

        // Ears and horns are drawn before the head circle so it overlaps
        // their inner attachment point — the same layering trick
        // `MonkCharacter`'s ears and `UnicornCharacter`'s horn/ears use —
        // leaving only the outer, sideways-jutting part visible.
        drawEars(in: stage)
        drawHorns(in: stage)
        drawHead(in: stage)
        drawMuzzle(in: stage)
    }

    /// Floppy ears sticking out sideways at head height — alongside the
    /// muzzle, the single strongest "this is a cow, not a horse or unicorn"
    /// cue, so drawn wide, rounded, and slightly drooping rather than the
    /// unicorn's tall pointed pair.
    private func drawEars(in stage: CGRect) {
        for sign: CGFloat in [-1, 1] {
            let cx = headCenter.fx + sign * headRadius * 0.85
            let rootTop = point(cx, headCenter.fy - headRadius * 0.35, in: stage)
            let rootBottom = point(cx, headCenter.fy + headRadius * 0.30, in: stage)
            let tip = point(cx + sign * headRadius * 1.05, headCenter.fy + headRadius * 0.08, in: stage)
            let ear = UIBezierPath()
            ear.move(to: rootTop)
            ear.addQuadCurve(to: tip,
                              controlPoint: point(cx + sign * headRadius * 0.70, headCenter.fy - headRadius * 0.30, in: stage))
            ear.addQuadCurve(to: rootBottom,
                              controlPoint: point(cx + sign * headRadius * 0.78, headCenter.fy + headRadius * 0.42, in: stage))
            ear.close()
            Self.coat.setFill()
            ear.fill()
            Self.coatShadow.setStroke()
            ear.lineWidth = stage.width * 0.006
            ear.stroke()

            // Inner-ear shading: a small crescent tucked against the ear's
            // root rather than a dot floating mid-flap, so it reads as
            // shading on the ear rather than a stray spot next to it.
            let innerR = stage.width * 0.020
            let innerC = point(cx + sign * headRadius * 0.18, headCenter.fy - headRadius * 0.02, in: stage)
            let inner = UIBezierPath(ovalIn: CGRect(x: innerC.x - innerR, y: innerC.y - innerR,
                                                      width: innerR * 2, height: innerR * 1.5))
            Self.earInner.withAlphaComponent(0.75).setFill()
            inner.fill()
        }
    }

    /// Small, stubby, slightly outward-curving horns — deliberately modest
    /// (per the design brief, "small horns or ears") so the sideways ears
    /// stay the dominant silhouette cue rather than competing with a tall
    /// unicorn-style spike.
    private func drawHorns(in stage: CGRect) {
        for sign: CGFloat in [-1, 1] {
            // Base set close to top-centre (rather than out near the ears)
            // and the tip curving outward — a thicker base than the first
            // pass so the whole horn reads as a solid wedge rather than a
            // thin sliver that could be mistaken for a stray hair.
            let base = point(headCenter.fx + sign * headRadius * 0.36, headCenter.fy - headRadius * 0.84, in: stage)
            let tip = point(headCenter.fx + sign * headRadius * 0.66, headCenter.fy - headRadius * 1.40, in: stage)
            let baseHalf = stage.width * 0.026

            let horn = UIBezierPath()
            horn.move(to: CGPoint(x: base.x, y: base.y + baseHalf * 0.4))
            horn.addQuadCurve(to: tip,
                               controlPoint: CGPoint(x: base.x - sign * baseHalf * 0.6, y: base.y - stage.width * 0.11))
            horn.addQuadCurve(to: CGPoint(x: base.x + sign * baseHalf * 1.7, y: base.y + baseHalf * 0.4),
                               controlPoint: CGPoint(x: base.x + sign * stage.width * 0.055, y: base.y - stage.width * 0.05))
            horn.close()

            Self.horn.setFill()
            horn.fill()
            Self.hornOutline.setStroke()
            horn.lineWidth = stage.width * 0.006
            horn.stroke()
        }
    }

    private func drawHead(in stage: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let center = point(headCenter.fx, headCenter.fy, in: stage)
        let head = UIBezierPath(arcCenter: center, radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Self.coat.setFill()
        head.fill()

        // An irregular patch over one eye/temple — the classic "cow with a
        // patch" cue — clipped to the head circle so it can never bulge past
        // the face's own silhouette.
        context.saveGState()
        head.addClip()
        let eyePatch = UIBezierPath()
        eyePatch.move(to: point(headCenter.fx - headRadius * 1.05, headCenter.fy - headRadius * 0.15, in: stage))
        eyePatch.addQuadCurve(to: point(headCenter.fx - headRadius * 0.35, headCenter.fy - headRadius * 0.95, in: stage),
                               controlPoint: point(headCenter.fx - headRadius * 0.95, headCenter.fy - headRadius * 0.95, in: stage))
        eyePatch.addQuadCurve(to: point(headCenter.fx - headRadius * 0.05, headCenter.fy - headRadius * 0.05, in: stage),
                               controlPoint: point(headCenter.fx - headRadius * 0.15, headCenter.fy - headRadius * 0.55, in: stage))
        eyePatch.addQuadCurve(to: point(headCenter.fx - headRadius * 0.75, headCenter.fy + headRadius * 0.35, in: stage),
                               controlPoint: point(headCenter.fx - headRadius * 0.35, headCenter.fy + headRadius * 0.30, in: stage))
        eyePatch.addQuadCurve(to: point(headCenter.fx - headRadius * 1.05, headCenter.fy - headRadius * 0.15, in: stage),
                               controlPoint: point(headCenter.fx - headRadius * 1.10, headCenter.fy + headRadius * 0.10, in: stage))
        eyePatch.close()
        Self.patch.setFill()
        eyePatch.fill()
        context.restoreGState()
    }

    /// A big pale muzzle patch — the design brief's suggested "natural fit"
    /// for the mouth: wide-set nostrils sit near its top, and
    /// `CharacterView` composites the moving mouth aperture near its bottom
    /// on top of it.
    private func drawMuzzle(in stage: CGRect) {
        let center = point(mouthCentre.fx, headCenter.fy + headRadius * 1.42, in: stage)
        let w = stage.width * 0.38
        let h = stage.width * 0.30
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let muzzle = UIBezierPath(ovalIn: rect)
        Self.muzzle.setFill()
        muzzle.fill()
        Self.muzzleOutline.setStroke()
        muzzle.lineWidth = stage.width * 0.008
        muzzle.stroke()

        // Wide-set nostrils near the top of the muzzle — the *distance*
        // between them, not just their own size, is the cue that reads as
        // "cow" rather than a generic snout.
        for dx: CGFloat in [-0.075, 0.075] {
            let nc = CGPoint(x: center.x + dx * stage.width, y: center.y - h * 0.20)
            let nw = stage.width * 0.032
            let nh = stage.width * 0.020
            let nostril = UIBezierPath(ovalIn: CGRect(x: nc.x - nw / 2, y: nc.y - nh / 2, width: nw, height: nh))
            UIColor.black.withAlphaComponent(0.42).setFill()
            nostril.fill()
        }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        for cx: CGFloat in [headCenter.fx - 0.075, headCenter.fx + 0.075] {
            let c = point(cx, headCenter.fy - 0.01, in: stage)
            if blinking {
                let lash = UIBezierPath()
                lash.move(to: CGPoint(x: c.x - stage.width * 0.04, y: c.y))
                lash.addLine(to: CGPoint(x: c.x + stage.width * 0.04, y: c.y))
                lash.lineWidth = stage.width * 0.013
                lash.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                lash.stroke()
                continue
            }
            let r = stage.width * 0.044
            let eye = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r * 0.85, width: r * 2, height: r * 1.7))
            UIColor.white.setFill()
            eye.fill()
            let irisR = r * 0.62
            let iris = UIBezierPath(ovalIn: CGRect(x: c.x - irisR, y: c.y - irisR * 0.55, width: irisR * 2, height: irisR * 2))
            UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1).setFill()
            iris.fill()
            let hl = irisR * 0.30
            let highlight = UIBezierPath(ovalIn: CGRect(x: c.x - hl * 1.4, y: c.y - hl * 1.2, width: hl * 2, height: hl * 2))
            UIColor.white.setFill()
            highlight.fill()
        }
    }
}
