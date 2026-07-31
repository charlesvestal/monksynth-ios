import UIKit

/// The default character: a bald, warm-faced chanting figure in a
/// saffron/maroon robe draped over one shoulder. Rebuilt against the 90s
/// pre-rendered-3D style spec (`docs/superpowers/specs/2026-07-31-character-style-spec.md`):
/// every surface is shaded through `Shading`'s primitives instead of flat
/// fills, and nothing is stroked — see that file's doc comment for why.
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
    // The saffron trim is derived from `Theme.robe` in HSB space rather than
    // a hand-picked constant that could drift out of sync with it: lighter
    // and desaturated toward yellow. `Theme.robe`'s own hue is ~9°
    // (red-orange); the shift must be *positive* to move toward
    // yellow/saffron (~35°) — a negative shift wraps the other way round the
    // hue circle into pink/magenta.
    private static let robeSaffron = Theme.robe.adjusted(hueShift: 0.07, saturationScale: 0.60, brightnessScale: 1.7)

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
    /// is tuned.
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

        Shading.freeform(torso.cgPath, boundingBox: torso.bounds, color: Theme.robe, into: context)

        // The drape line: from the base of the neck, sweeping *well down*
        // across the chest before exiting off the right edge of the stage.
        // Everything in the torso silhouette above/right of this line
        // becomes bare skin — clip to `torso` first so the fill can never
        // leak past the body's real outline, then clip to "above the line"
        // and shade. This needs to sag substantially below the torso's own
        // shoulder curve (which only drops from fy 0.50 to 0.58) or the
        // exposed region is squeezed to a hairline sliver between the two
        // curves.
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
        // Shaded against the whole torso's bounding box, not the small
        // patch's own — a patch of bare skin on a lit robe should reveal
        // the body's own lighting, not get an independent hot spot.
        Shading.radialShade(in: torso.bounds, color: Theme.skin, into: context)
        context.restoreGState()

        // Saffron piping along the visible drape line: a thin filled ribbon
        // (the stroke outline of the drape curve, filled rather than
        // stroked) shaded like a piece of trimmed fabric, clipped to the
        // torso so it can never extend past the body's own silhouette.
        context.saveGState()
        torso.addClip()
        let ribbonPath = drapeLine.cgPath.copy(
            strokingWithWidth: stage.width * 0.02, lineCap: .round, lineJoin: .round, miterLimit: 1)
        Shading.freeform(ribbonPath, boundingBox: ribbonPath.boundingBox, color: Self.robeSaffron, into: context)
        context.restoreGState()
    }

    /// The neck, always fully skin-coloured regardless of which shoulder is
    /// bare — it is the strip directly beneath the head that connects it to
    /// `torsoPath`'s own neckline, so the head never appears to float.
    private func drawNeck(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let neck = UIBezierPath()
        neck.move(to: p(0.44, 0.43))
        neck.addLine(to: p(0.56, 0.43))
        neck.addLine(to: p(neckBottomRight.fx, neckBottomRight.fy))
        neck.addLine(to: p(neckBottomLeft.fx, neckBottomLeft.fy))
        neck.close()
        Shading.freeform(neck.cgPath, boundingBox: neck.bounds, color: Theme.skin, into: context)
    }

    private let faceCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private let headRadius: CGFloat = 0.17

    private func drawHead(in stage: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let center = point(faceCenter.fx, faceCenter.fy, in: stage)
        let headRect = CGRect(x: center.x - stage.width * headRadius, y: center.y - stage.width * headRadius,
                               width: stage.width * headRadius * 2, height: stage.width * headRadius * 2)

        // Ears: drawn before the head sphere so it overlaps their inner
        // half, leaving only an outer crescent visible on a bald head.
        for cx: CGFloat in [faceCenter.fx - headRadius * 0.96,
                             faceCenter.fx + headRadius * 0.96] {
            let c = point(cx, faceCenter.fy + 0.018, in: stage)
            let w = stage.width * 0.045
            let h = stage.width * 0.076
            Shading.sphere(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                            color: Theme.skin, into: context)
        }

        Shading.sphere(in: headRect, color: Theme.skin, into: context)
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // A calm, half-lidded meditation look rather than fully round eyes:
        // a shallow recessed socket, thinner still when blinking. Both
        // states are the same `Shading.recess` primitive at a different
        // aspect, so there is no stroke standing in for an eyelid line.
        let halfWidth = stage.width * 0.05
        let halfHeight = stage.width * (blinking ? 0.006 : 0.021)
        for cx: CGFloat in [0.415, 0.585] {
            let c = point(cx, 0.296, in: stage)
            Shading.recess(in: CGRect(x: c.x - halfWidth, y: c.y - halfHeight,
                                       width: halfWidth * 2, height: halfHeight * 2),
                            into: context)
        }
    }
}
