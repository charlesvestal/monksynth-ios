import UIKit

/// The monk character: a hooded chanting figure built from layered
/// `UIBezierPath`s in a centred square "stage" so the rig never distorts
/// under odd aspect ratios (iPhone SE portrait strip up to iPad Pro).
///
/// Layers, back to front: robe, sash, head, hood, eyes, mouth. The mouth is
/// the only continuously-morphing element — it interpolates across five
/// anchor shapes with `vowel`, unlike upstream's 24 discrete sprite frames.
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

    // MARK: - Mouth anchors: (width, height) of the aperture in unit-square
    // space, roughly OO / OH / AH / EH / EE.

    private static let mouthAnchors: [(w: CGFloat, h: CGFloat)] = [
        (0.16, 0.26), (0.26, 0.30), (0.34, 0.22), (0.40, 0.13), (0.44, 0.07),
    ]

    /// Continuous interpolation across the five anchor shapes above — this
    /// is what replaces upstream's 24 discrete sprite frames.
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
        drawSash(in: stage)
        drawHead(in: stage)
        drawHood(in: stage)

        let pose = currentPose
        drawEyes(in: stage, blinking: pose.blinking)
        drawMouth(in: stage, vowel: pose.vowel)
    }

    private func point(_ fx: CGFloat, _ fy: CGFloat, in stage: CGRect) -> CGPoint {
        CGPoint(x: stage.minX + fx * stage.width, y: stage.minY + fy * stage.height)
    }

    private func drawRobe(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        let robe = UIBezierPath()
        robe.move(to: p(0.34, 0.56))
        robe.addQuadCurve(to: p(0.18, 0.64), controlPoint: p(0.22, 0.56))
        robe.addCurve(to: p(0.08, 0.97), controlPoint1: p(0.06, 0.72), controlPoint2: p(0.04, 0.86))
        robe.addQuadCurve(to: p(0.92, 0.97), controlPoint: p(0.5, 1.05))
        robe.addCurve(to: p(0.82, 0.64), controlPoint1: p(0.96, 0.86), controlPoint2: p(0.94, 0.72))
        robe.addQuadCurve(to: p(0.66, 0.56), controlPoint: p(0.78, 0.56))
        robe.addQuadCurve(to: p(0.34, 0.56), controlPoint: p(0.5, 0.615))
        robe.close()
        Theme.robe.setFill()
        robe.fill()

        // A soft fold down the centre so the robe reads as fabric rather
        // than a flat wash.
        let fold = UIBezierPath()
        fold.move(to: p(0.5, 0.60))
        fold.addQuadCurve(to: p(0.46, 0.95), controlPoint: p(0.40, 0.78))
        fold.addQuadCurve(to: p(0.54, 0.95), controlPoint: p(0.5, 0.92))
        fold.addQuadCurve(to: p(0.5, 0.60), controlPoint: p(0.58, 0.78))
        fold.close()
        Theme.robeShadow.withAlphaComponent(0.35).setFill()
        fold.fill()
    }

    private func drawSash(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        let sash = UIBezierPath()
        sash.move(to: p(0.30, 0.60))
        sash.addLine(to: p(0.64, 0.97))
        sash.lineWidth = stage.width * 0.10
        sash.lineCapStyle = .round
        Theme.robeShadow.withAlphaComponent(0.75).setStroke()
        sash.stroke()

        // A thin warm trim down the centre of the sash.
        let trim = UIBezierPath()
        trim.move(to: p(0.30, 0.60))
        trim.addLine(to: p(0.64, 0.97))
        trim.lineWidth = stage.width * 0.018
        trim.lineCapStyle = .round
        Theme.accent.withAlphaComponent(0.9).setStroke()
        trim.stroke()
    }

    /// Head and hood share a centre; the head circle is drawn larger than
    /// the hood's face opening so the opening is always backed by skin —
    /// no aspect ratio or proportion tweak can reveal a transparent gap.
    private static let faceCenter = (fx: CGFloat(0.5), fy: CGFloat(0.40))
    private static let headRadius: CGFloat = 0.22
    private static let holeRadius: CGFloat = 0.19

    private func drawHead(in stage: CGRect) {
        let center = point(Self.faceCenter.fx, Self.faceCenter.fy, in: stage)
        let head = UIBezierPath(arcCenter: center, radius: stage.width * Self.headRadius,
                                 startAngle: 0, endAngle: .pi * 2, clockwise: true)
        Theme.skin.setFill()
        head.fill()
    }

    private func drawHood(in stage: CGRect) {
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { point(fx, fy, in: stage) }

        // Outer silhouette: a rounded arch over the head that drapes down
        // onto the shoulders.
        let hood = UIBezierPath()
        hood.move(to: p(0.16, 0.66))
        hood.addQuadCurve(to: p(0.5, 0.10), controlPoint: p(0.18, 0.20))
        hood.addQuadCurve(to: p(0.84, 0.66), controlPoint: p(0.82, 0.20))
        hood.addQuadCurve(to: p(0.74, 0.74), controlPoint: p(0.80, 0.70))
        hood.addLine(to: p(0.26, 0.74))
        hood.addQuadCurve(to: p(0.16, 0.66), controlPoint: p(0.20, 0.70))
        hood.close()

        // Face opening: a hole cut from the hood (even-odd fill) that
        // reveals the head painted underneath, framed by a rim of fabric.
        let center = point(Self.faceCenter.fx, Self.faceCenter.fy, in: stage)
        let holeR = stage.width * Self.holeRadius
        let faceHole = UIBezierPath(arcCenter: center, radius: holeR,
                                     startAngle: 0, endAngle: .pi * 2, clockwise: true)
        hood.append(faceHole)
        hood.usesEvenOddFillRule = true

        Theme.robe.setFill()
        hood.fill()

        // Inner rim shadow so the opening reads as a hood, not a hole.
        Theme.robeShadow.withAlphaComponent(0.6).setStroke()
        faceHole.lineWidth = stage.width * 0.012
        faceHole.stroke()
    }

    private func drawEyes(in stage: CGRect, blinking: Bool) {
        let w = stage.width * 0.07
        let h = stage.width * 0.045
        for cx: CGFloat in [0.415, 0.585] {
            let c = point(cx, 0.385, in: stage)
            if blinking {
                let line = UIBezierPath()
                line.move(to: CGPoint(x: c.x - w / 2, y: c.y))
                line.addLine(to: CGPoint(x: c.x + w / 2, y: c.y))
                line.lineWidth = stage.width * 0.01
                line.lineCapStyle = .round
                Theme.robeShadow.setStroke()
                line.stroke()
            } else {
                let eye = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
                Theme.robeShadow.setFill()
                eye.fill()
            }
        }
    }

    /// The mouth's own local reference frame — smaller than the face
    /// opening so it can never poke past the hood at the widest anchor.
    private static let mouthBoxFraction: CGFloat = 0.36
    private static let mouthCenter = (fx: CGFloat(0.5), fy: CGFloat(0.515))

    private func drawMouth(in stage: CGRect, vowel: Float) {
        let shape = Self.mouthShape(vowel: vowel)
        let ampBoost = 1 + CGFloat(min(max(amplitude, 0), 1)) * 0.35
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
