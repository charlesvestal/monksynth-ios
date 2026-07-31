import UIKit

/// The monk character: a bald, warm-faced chanting figure in a saffron/maroon
/// robe draped over one shoulder, built from layered `UIBezierPath`s in a
/// centred square "stage" so the rig never distorts under odd aspect ratios
/// (iPhone SE portrait strip up to iPad Pro).
///
/// Layers, back to front: robe (torso silhouette + clipped bare-shoulder
/// skin), neck, ears, head, eyes, mouth. The mouth is the only
/// continuously-morphing element — it interpolates across five anchor
/// shapes with `vowel`, unlike upstream's 24 discrete sprite frames.
/// Everything else is a fixed pose except the eyes' blink state, which
/// upstream's idle state machine (`IdleAnimator`, ported from
/// `cpp/src/monk_view.h`) drives while no note is sounding.
///
/// This view NEVER calls into `dsp/` or `RenderContext` — the render thread
/// owns the DSP engine, and calling `monk_synth_get_vowel()` or similar from
/// here would be a data race. It only reads the plain `vowel` / `amplitude`
/// / `noteActive` properties its owner writes from the main thread (the AU
/// publishes those into `RenderContext.uiVowel` etc. after each render;
/// wiring that up to this view is a later task).
final class MonkView: UIView {

    // MARK: - Public surface (owner writes these from the main thread)

    /// Set by the owner each display tick.
    var vowel: Float = 0.5 { didSet { setNeedsDisplay() } }
    /// Opens the mouth further when loud.
    var amplitude: Float = 0 { didSet { setNeedsDisplay() } }
    /// Resets the idle animation when a note starts, and starts/stops the
    /// display link.
    var noteActive: Bool = false {
        didSet {
            guard oldValue != noteActive else { return }
            if noteActive { idle.reset() }
            updateDisplayLink()
            setNeedsDisplay()
        }
    }

    // MARK: - Idle animation

    private var idle = IdleAnimator()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var accumulatedMs: Double = 0
    private var reduceMotionObserver: NSObjectProtocol?

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

    /// How many discrete mouth positions the vowel range is divided into.
    ///
    /// Upstream drove the mouth from a sprite sheet — 24 frames across the
    /// vowel range — and the resulting stepped, puppet-like motion is a real
    /// part of the original's charm, not an artefact to be smoothed away. An
    /// early version of this port interpolated continuously; it read as
    /// slicker and less alive. So the vector rig is quantised back to the same
    /// frame count: `mouthShape` stays a continuous function (it is the shape
    /// definition), and `quantisedVowel` steps its INPUT.
    static let vowelFrameCount = 24

    /// Snaps a vowel position to the nearest of `vowelFrameCount` steps, so
    /// the mouth advances in visible frames rather than gliding.
    static func quantisedVowel(_ v: Float) -> Float {
        let clamped = min(max(v, 0), 1)
        let steps = Float(vowelFrameCount - 1)
        return (clamped * steps).rounded() / steps
    }

    /// Continuous interpolation across the five anchor shapes above. Callers
    /// pass a `quantisedVowel(_:)` value, which is what produces the stepped
    /// frame-by-frame motion; this function itself stays smooth so the anchor
    /// geometry can be reasoned about and tested independently of the stepping.
    static func mouthShape(vowel v: Float) -> (w: CGFloat, h: CGFloat) {
        let clamped = min(max(v, 0), 1)
        let scaled = CGFloat(clamped) * CGFloat(mouthAnchors.count - 1)
        let i = min(Int(scaled), mouthAnchors.count - 2)
        let t = scaled - CGFloat(i)
        let a = mouthAnchors[i], b = mouthAnchors[i + 1]
        return (a.w + (b.w - a.w) * t, a.h + (b.h - a.h) * t)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("monk.label", comment: "the monk")

        // Reduce Motion can be toggled while the view is on screen; react so
        // an idle shuffle in progress freezes immediately rather than
        // waiting for the next note or window transition.
        reduceMotionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateDisplayLink()
            self?.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        displayLink?.invalidate()
        if let observer = reduceMotionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        lastTimestamp = nil
        updateDisplayLink()
    }

    // MARK: - Display link

    /// True while the idle animation should keep fidgeting. Reduce Motion
    /// suppresses idle fidgeting only — it does not suppress the
    /// instrument's own response, so a genuinely sounding note still
    /// animates the mouth regardless of this flag.
    private var idleShouldRun: Bool { !UIAccessibility.isReduceMotionEnabled }

    /// The display link only runs while there is something to animate: a
    /// note sounding, or the idle animation actively fidgeting. Otherwise it
    /// is torn down so an off-screen or motionless monk costs nothing.
    private func updateDisplayLink() {
        let shouldRun = window != nil && (noteActive || idleShouldRun)
        if shouldRun {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = nil
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        // While a note sounds the pose is driven directly by the live
        // vowel/amplitude the owner writes (via their `didSet`), not by the
        // idle animator — nothing to advance here.
        guard !noteActive, idleShouldRun else { return }

        defer { lastTimestamp = link.timestamp }
        guard let last = lastTimestamp else { return }

        accumulatedMs += (link.timestamp - last) * 1000
        var advanced = false
        while accumulatedMs >= Double(IdleAnimator.tickMs) {
            accumulatedMs -= Double(IdleAnimator.tickMs)
            idle.advance()
            advanced = true
        }
        if advanced { setNeedsDisplay() }
    }

    // MARK: - Pose

    /// The pose actually drawn: the live vowel while a note sounds, the
    /// frozen HOLD pose under Reduce Motion, otherwise the idle animator's
    /// current pose.
    private var currentPose: (vowel: Float, blinking: Bool) {
        if noteActive { return (vowel, false) }
        if UIAccessibility.isReduceMotionEnabled {
            return (IdleAnimator.vowel(forFrame: 5), false)
        }
        return idle.pose
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }

        // A centred square "stage" so the rig never distorts under odd
        // aspect ratios: every shape below is defined in stage-relative
        // fractions (0...1 across both axes) and mapped through `point`.
        let side = min(rect.width, rect.height)
        let stage = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)

        drawRobe(in: stage)
        drawNeck(in: stage)
        drawHead(in: stage)

        let pose = currentPose
        drawEyes(in: stage, blinking: pose.blinking)
        // Quantised, not continuous: the mouth advances in discrete frames the
        // way the original sprite sheet did. See `quantisedVowel`.
        drawMouth(in: stage, vowel: Self.quantisedVowel(pose.vowel))
    }

    private func point(_ fx: CGFloat, _ fy: CGFloat, in stage: CGRect) -> CGPoint {
        CGPoint(x: stage.minX + fx * stage.width, y: stage.minY + fy * stage.height)
    }

    /// The torso's true silhouette: symmetric, rounded shoulders on both
    /// sides — the same shape a robe covering the *whole* body would have.
    /// `drawRobe` reuses this exact path as a clip mask for the bare
    /// shoulder, so that patch's outer edge is always pixel-identical to
    /// the body's real silhouette no matter how the drape-line curve below
    /// is tuned. (Four earlier attempts hand-matched a separate curve to
    /// the robe's own edge and either left a gap or bulged past it; this
    /// is structurally immune to that class of bug.)
    private static let neckBottomLeft = (fx: CGFloat(0.43), fy: CGFloat(0.50))
    private static let neckBottomRight = (fx: CGFloat(0.57), fy: CGFloat(0.50))
    private static let leftShoulderTop = (fx: CGFloat(0.20), fy: CGFloat(0.58))
    private static let rightShoulderTop = (fx: CGFloat(0.80), fy: CGFloat(0.58))

    private func torsoPath(in stage: CGRect) -> UIBezierPath {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }
        let torso = UIBezierPath()
        torso.move(to: p(Self.leftShoulderTop.fx, Self.leftShoulderTop.fy))
        torso.addQuadCurve(to: p(Self.neckBottomLeft.fx, Self.neckBottomLeft.fy), controlPoint: p(0.27, 0.50))
        torso.addLine(to: p(Self.neckBottomRight.fx, Self.neckBottomRight.fy))
        torso.addQuadCurve(to: p(Self.rightShoulderTop.fx, Self.rightShoulderTop.fy), controlPoint: p(0.73, 0.50))
        torso.addQuadCurve(to: p(0.92, 0.78), controlPoint: p(0.90, 0.66))
        torso.addCurve(to: p(0.90, 0.99), controlPoint1: p(0.95, 0.86), controlPoint2: p(0.95, 0.95))
        torso.addQuadCurve(to: p(0.10, 0.99), controlPoint: p(0.5, 1.06))
        torso.addCurve(to: p(0.08, 0.78), controlPoint1: p(0.05, 0.95), controlPoint2: p(0.05, 0.86))
        torso.addQuadCurve(to: p(Self.leftShoulderTop.fx, Self.leftShoulderTop.fy), controlPoint: p(0.10, 0.66))
        torso.close()
        return torso
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
        drapeLine.move(to: p(Self.neckBottomRight.fx, Self.neckBottomRight.fy))
        drapeLine.addQuadCurve(to: p(1.05, 0.82), controlPoint: p(0.74, 0.64))

        guard let cut = drapeLine.copy() as? UIBezierPath else { return }
        cut.addLine(to: p(1.05, -0.05))
        cut.addLine(to: p(Self.neckBottomRight.fx, -0.05))
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
        neck.addLine(to: p(Self.neckBottomRight.fx, Self.neckBottomRight.fy))
        neck.addLine(to: p(Self.neckBottomLeft.fx, Self.neckBottomLeft.fy))
        neck.close()
        Theme.skin.setFill()
        neck.fill()
    }

    private static let faceCenter = (fx: CGFloat(0.5), fy: CGFloat(0.30))
    private static let headRadius: CGFloat = 0.17

    private func drawHead(in stage: CGRect) {
        let center = point(Self.faceCenter.fx, Self.faceCenter.fy, in: stage)

        // Ears: drawn before the head circle so it overlaps their inner
        // half, leaving only an outer crescent visible on a bald head.
        for cx: CGFloat in [Self.faceCenter.fx - Self.headRadius * 0.96,
                             Self.faceCenter.fx + Self.headRadius * 0.96] {
            let c = point(cx, Self.faceCenter.fy + 0.018, in: stage)
            let w = stage.width * 0.045
            let h = stage.width * 0.076
            let ear = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            Theme.skin.setFill()
            ear.fill()
        }

        let head = UIBezierPath(arcCenter: center, radius: stage.width * Self.headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Theme.skin.setFill()
        head.fill()
    }

    private func drawEyes(in stage: CGRect, blinking: Bool) {
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

    /// The mouth's own local reference frame, scaled to the head so it can
    /// never poke past the jawline at the widest anchor.
    private static let mouthBoxFraction: CGFloat = 0.27
    private static let mouthCenter = (fx: CGFloat(0.5), fy: CGFloat(0.394))

    private func drawMouth(in stage: CGRect, vowel: Float) {
        let shape = Self.mouthShape(vowel: vowel)
        // Step the amplitude swell too. A continuously-scaling mouth would
        // reintroduce exactly the glide that quantising the vowel removes —
        // the whole point is that the character moves in frames.
        let ampSteps: Float = 4
        let amp = (min(max(amplitude, 0), 1) * ampSteps).rounded() / ampSteps
        let ampBoost = 1 + CGFloat(amp) * 0.35
        let box = stage.width * Self.mouthBoxFraction
        let w = box * shape.w
        let h = box * shape.h * ampBoost
        let c = point(Self.mouthCenter.fx, Self.mouthCenter.fy, in: stage)

        let mouth = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        Theme.background.setFill()
        mouth.fill()
        Theme.robeShadow.withAlphaComponent(0.5).setStroke()
        mouth.lineWidth = stage.width * 0.008
        mouth.stroke()
    }
}

private extension UIColor {
    /// Returns a copy of this colour with hue shifted and saturation /
    /// brightness scaled in HSB space. Used to derive the robe's saffron
    /// trim and fold-shadow tones from `Theme.robe` so there is a single
    /// source of truth for the robe's base colour instead of separate
    /// hand-picked constants that could drift out of sync with it.
    func adjusted(hueShift: CGFloat = 0, saturationScale: CGFloat = 1, brightnessScale: CGFloat = 1) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var shiftedHue = (h + hueShift).truncatingRemainder(dividingBy: 1)
        if shiftedHue < 0 { shiftedHue += 1 }
        return UIColor(hue: shiftedHue,
                        saturation: min(max(s * saturationScale, 0), 1),
                        brightness: min(max(b * brightnessScale, 0), 1),
                        alpha: a)
    }
}
