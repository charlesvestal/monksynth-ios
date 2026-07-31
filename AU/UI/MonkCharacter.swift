import UIKit

/// The default character: a bald, warm-faced chanting figure in a
/// saffron/maroon robe draped over one shoulder, built from layered
/// `UIBezierPath`s. This is upstream's original — and, until this file
/// existed, MonkSynth's *only* — face, moved here unchanged from `MonkView`
/// when that view grew into `CharacterView` to support five characters.
/// See `CharacterView` for the animation (idle state machine, vowel
/// quantisation, amplitude swell) every character shares.
///
/// Layers, back to front: robe (torso silhouette + clipped bare-shoulder
/// skin), neck, ears, head, eyes. `CharacterView` draws the mouth aperture
/// itself, on every character's behalf, from `mouthShape`/`mouthCentre`/
/// `mouthBoxFraction` below.
struct MonkCharacter: Character {
    let id = "monk"
    let displayName = "Monk"

    // MARK: - Derived robe tones
    //
    // Rather than hand-picking two more raw colour constants that could
    // drift out of sync with `Theme.robe`, the saffron trim and the fold
    // shadow are both derived from it in HSB space: lighter + desaturated
    // toward yellow for the saffron piping, darker for the fold shadow.
    // `Theme.robe`'s own hue is ~9° (red-orange); the shift must be
    // *positive* to move toward yellow/saffron (~35°) — a negative shift
    // wraps the other way round the hue circle into pink/magenta, which is
    // what an earlier version of this constant actually rendered as.
    private static let robeSaffron = Theme.robe.adjusted(hueShift: 0.07, saturationScale: 0.60, brightnessScale: 1.7)
    private static let robeFold = Theme.robe.adjusted(saturationScale: 1.05, brightnessScale: 0.62)

    // MARK: - Mouth anchors: (width, height) of the aperture in unit-square
    // space, roughly OO / OH / AH / EH / EE.

    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.16, 0.26), (0.26, 0.30), (0.34, 0.22), (0.40, 0.13), (0.44, 0.07),
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

    /// The mouth's own local reference frame, scaled to the head so it can
    /// never poke past the jawline at the widest anchor.
    let mouthBoxFraction: CGFloat = 0.27
    let mouthCentre: (fx: CGFloat, fy: CGFloat) = (0.5, 0.394)

    // MARK: - Body

    /// The torso's true silhouette: symmetric, rounded shoulders on both
    /// sides — the same shape a robe covering the *whole* body would have.
    /// `drawRobe` reuses this exact path as a clip mask for the bare
    /// shoulder, so that patch's outer edge is always pixel-identical to
    /// the body's real silhouette no matter how the drape-line curve below
    /// is tuned. (Four earlier attempts hand-matched a separate curve to
    /// the robe's own edge and either left a gap or bulged past it; this
    /// is structurally immune to that class of bug.)
    private let neckBottomLeft = (fx: CGFloat(0.43), fy: CGFloat(0.50))
    private let neckBottomRight = (fx: CGFloat(0.57), fy: CGFloat(0.50))
    private let leftShoulderTop = (fx: CGFloat(0.20), fy: CGFloat(0.58))
    private let rightShoulderTop = (fx: CGFloat(0.80), fy: CGFloat(0.58))

    private func torsoPath(in stage: CGRect) -> UIBezierPath {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let torso = UIBezierPath()
        torso.move(to: p(leftShoulderTop.fx, leftShoulderTop.fy))
        torso.addQuadCurve(to: p(neckBottomLeft.fx, neckBottomLeft.fy), controlPoint: p(0.27, 0.50))
        torso.addLine(to: p(neckBottomRight.fx, neckBottomRight.fy))
        torso.addQuadCurve(to: p(rightShoulderTop.fx, rightShoulderTop.fy), controlPoint: p(0.73, 0.50))
        torso.addQuadCurve(to: p(0.92, 0.78), controlPoint: p(0.90, 0.66))
        torso.addCurve(to: p(0.90, 0.99), controlPoint1: p(0.95, 0.86), controlPoint2: p(0.95, 0.95))
        torso.addQuadCurve(to: p(0.10, 0.99), controlPoint: p(0.5, 1.06))
        torso.addCurve(to: p(0.08, 0.78), controlPoint1: p(0.05, 0.95), controlPoint2: p(0.05, 0.86))
        torso.addQuadCurve(to: p(leftShoulderTop.fx, leftShoulderTop.fy), controlPoint: p(0.10, 0.66))
        torso.close()
        return torso
    }

    func drawBody(in stage: CGRect) {
        drawRobe(in: stage)
        drawNeck(in: stage)
        drawHead(in: stage)
    }

    private func drawRobe(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let torso = torsoPath(in: stage)

        Theme.robe.setFill()
        torso.fill()

        // A soft, narrow fold low on the (always-robed) left/centre so the
        // robe reads as fabric rather than a flat wash.
        let fold = UIBezierPath()
        fold.move(to: p(0.5, 0.72))
        fold.addQuadCurve(to: p(0.475, 0.97), controlPoint: p(0.455, 0.86))
        fold.addQuadCurve(to: p(0.525, 0.97), controlPoint: p(0.5, 0.95))
        fold.addQuadCurve(to: p(0.5, 0.72), controlPoint: p(0.545, 0.86))
        fold.close()
        Self.robeFold.withAlphaComponent(0.22).setFill()
        fold.fill()

        // The drape line: from the base of the neck, sweeping *well down*
        // across the chest before exiting off the right edge of the stage.
        // Everything in the torso silhouette above/right of this line
        // becomes bare skin — clip to `torso` first so the fill can never
        // leak past the body's real outline, then clip to "above the line"
        // and flood-fill. This needs to sag substantially below the
        // torso's own shoulder curve (which only drops from fy 0.50 to
        // 0.58) or the exposed region is squeezed to a hairline sliver
        // between the two curves — an earlier version of this line hugged
        // the torso's edge too closely and the bare shoulder was nearly
        // invisible as a result.
        let drapeLine = UIBezierPath()
        drapeLine.move(to: p(neckBottomRight.fx, neckBottomRight.fy))
        drapeLine.addQuadCurve(to: p(1.05, 0.82), controlPoint: p(0.74, 0.64))

        guard let cut = drapeLine.copy() as? UIBezierPath else { return }
        cut.addLine(to: p(1.05, -0.05))
        cut.addLine(to: p(neckBottomRight.fx, -0.05))
        cut.close()

        context.saveGState()
        torso.addClip()
        cut.addClip()
        Theme.skin.setFill()
        context.fill(stage)
        context.restoreGState()

        // Saffron trim along the visible drape line — clipped to the torso
        // too, so it can never extend past the body's own silhouette the
        // way the very first version's floating sash did.
        context.saveGState()
        torso.addClip()
        drapeLine.lineWidth = stage.width * 0.014
        drapeLine.lineCapStyle = .round
        Self.robeSaffron.withAlphaComponent(0.85).setStroke()
        drapeLine.stroke()
        context.restoreGState()
    }

    /// The neck, always fully skin-coloured regardless of which shoulder is
    /// bare — it is the strip directly beneath the head that connects it
    /// to `torsoPath`'s own neckline, so the head never appears to float.
    private func drawNeck(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let neck = UIBezierPath()
        neck.move(to: p(0.44, 0.43))
        neck.addLine(to: p(0.56, 0.43))
        neck.addLine(to: p(neckBottomRight.fx, neckBottomRight.fy))
        neck.addLine(to: p(neckBottomLeft.fx, neckBottomLeft.fy))
        neck.close()
        Theme.skin.setFill()
        neck.fill()
    }

    private let faceCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.17

    private func drawHead(in stage: CGRect) {
        let center = point(faceCenter.fx, faceCenter.fy, in: stage)

        // Ears: drawn before the head circle so it overlaps their inner
        // half, leaving only an outer crescent visible on a bald head.
        for cx: CGFloat in [faceCenter.fx - headRadius * 0.96,
                             faceCenter.fx + headRadius * 0.96] {
            let c = point(cx, faceCenter.fy + 0.018, in: stage)
            let w = stage.width * 0.045
            let h = stage.width * 0.076
            let ear = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            Theme.skin.setFill()
            ear.fill()
        }

        let head = UIBezierPath(arcCenter: center, radius: stage.width * headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Theme.skin.setFill()
        head.fill()
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        let halfWidth = stage.width * 0.05
        let curveDepth = stage.width * (blinking ? 0.011 : 0.027)
        let lineWidth = stage.width * 0.015
        for cx: CGFloat in [0.415, 0.585] {
            let c = point(cx, 0.296, in: stage)
            let eye = UIBezierPath()
            eye.move(to: CGPoint(x: c.x - halfWidth, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + halfWidth, y: c.y),
                              controlPoint: CGPoint(x: c.x, y: c.y + curveDepth))
            eye.lineWidth = lineWidth
            eye.lineCapStyle = .round
            Theme.robeShadow.setStroke()
            eye.stroke()
        }
    }
}
