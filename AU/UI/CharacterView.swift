import UIKit

/// Renders whichever `Character` is selected and owns everything about
/// *when* it moves: the idle state machine (`IdleAnimator`), the 24-frame
/// vowel quantisation, the stepped amplitude swell, display-link gating,
/// Reduce Motion handling, and the detach-when-collapsed behaviour. Only
/// appearance is delegated to `character` — see `Character`'s doc comment.
///
/// Was `MonkView` until this task added four more characters; the type was
/// renamed because "MonkView" stopped being an accurate name once it could
/// draw a fish. Behaviour (`quantisedVowel`, the idle machine, the mouth's
/// amplitude swell) is unchanged from that version.
///
/// This view NEVER calls into `dsp/` or `RenderContext` — the render thread
/// owns the DSP engine, and calling `monk_synth_get_vowel()` or similar from
/// here would be a data race. It only reads the plain `vowel` / `amplitude`
/// / `noteActive` properties its owner writes from the main thread (the AU
/// publishes those into `RenderContext.uiVowel` etc. after each render).
final class CharacterView: UIView {

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

    /// The character currently on screen. Defaults to the monk — the
    /// roster's first entry and the persisted default (see
    /// `CharacterRegistry`). Settable directly (state restore, or an owner
    /// applying a value read from `fullState`/`UserDefaults`); tap-to-cycle
    /// (`cycleCharacter()`) is just this setter plus the roster walk plus
    /// the name overlay.
    var character: Character = MonkCharacter() {
        didSet {
            updateAccessibility()
            setNeedsDisplay()
        }
    }

    /// Fired whenever the user's gesture (a tap OR a long-press — see
    /// `handleTap`/`handleLongPress`) cycles to the next character — never
    /// fired for a programmatic `character =` assignment, so an owner
    /// applying a restored/loaded value can't bounce right back into
    /// whatever wrote it. The owner uses this to persist the new selection
    /// (AU `fullState`, or `UserDefaults` in the standalone host).
    var onCharacterChange: ((Character) -> Void)?

    /// Fired immediately after `onCharacterChange`, but ONLY by a tap — never
    /// by a long-press. This is the "and load its voice" half of the tap
    /// gesture: tap changes character AND sound, long-press changes the
    /// character only and leaves whatever sound is currently dialled in
    /// alone. `CharacterView` itself has no notion of parameters or voices —
    /// it only tells its owner "the user asked for this character's voice
    /// too", exactly as `onCharacterChange` already tells it "the user asked
    /// for this character". The owner (`AudioUnitViewController`/
    /// `RootViewController`) is what actually knows how to look up and apply
    /// a voice.
    var onVoiceLoad: ((Character) -> Void)?

    // MARK: - Idle animation

    private var idle = IdleAnimator()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var accumulatedMs: Double = 0
    private var reduceMotionObserver: NSObjectProtocol?

    /// How many discrete mouth positions the vowel range is divided into.
    ///
    /// Upstream drove the mouth from a sprite sheet — 24 frames across the
    /// vowel range — and the resulting stepped, puppet-like motion is a real
    /// part of the original's charm, not an artefact to be smoothed away. An
    /// early version of this port interpolated continuously; it read as
    /// slicker and less alive. So the vector rig is quantised back to the
    /// same frame count: `Character.mouthShape` stays a continuous function
    /// (it is the shape definition), and `quantisedVowel` steps its INPUT.
    /// Shared by every character — no character overrides its timing, only
    /// its shapes (see the design doc's "out of scope" list).
    static let vowelFrameCount = 24

    /// Snaps a vowel position to the nearest of `vowelFrameCount` steps, so
    /// the mouth advances in visible frames rather than gliding.
    static func quantisedVowel(_ v: Float) -> Float {
        let clamped = min(max(v, 0), 1)
        let steps = Float(vowelFrameCount - 1)
        return (clamped * steps).rounded() / steps
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityTraits = .button
        updateAccessibility()

        addSubview(nameOverlay)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        // Without this, a held-and-released touch would fire BOTH: the long
        // press recognizes at `minimumPressDuration` while the finger is
        // still down (UILongPressGestureRecognizer has no upper bound on
        // hold time), and a plain UITapGestureRecognizer still recognizes on
        // release regardless of how long the touch was held. Making the tap
        // wait for the long press to actually FAIL (i.e. the touch lifted
        // before the long-press threshold) is what makes the two gestures
        // mutually exclusive: hold past the threshold and only the long
        // press fires; release quickly and only the tap fires. See
        // `handleTap`/`handleLongPress` for what "only" means here — tap
        // loads the voice, long-press deliberately does not.
        tap.require(toFail: longPress)
        addGestureRecognizer(tap)
        addGestureRecognizer(longPress)

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

    // MARK: - Tap-to-cycle (and load its voice) / long-press-to-cycle (character only)

    /// A tap changes character AND loads its voice — `cycleCharacter()` for
    /// the picture, `onVoiceLoad` for the sound. This is the gesture users
    /// reach for by default; the user was warned it can overwrite a patch
    /// they've dialled in, and chose it anyway (see the task). Long-press
    /// (`handleLongPress`) is the escape hatch that leaves the sound alone.
    @objc private func handleTap() {
        cycleCharacter()
        onVoiceLoad?(character)
    }

    /// Character only — deliberately does NOT fire `onVoiceLoad`. Gated to
    /// `.began` so a held touch fires this exactly once, not once per
    /// re-recognition tick.
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        cycleCharacter()
    }

    /// Advances to the next character in `CharacterRegistry.all`, wrapping
    /// from the last entry back to the first, and briefly overlays its
    /// name. Shared by both gestures above; never loads a voice itself —
    /// see `handleTap` for the one caller that also wants that.
    func cycleCharacter() {
        let next = CharacterRegistry.character(after: character)
        character = next
        onCharacterChange?(next)
        showNameOverlay(next.displayName)
    }

    /// VoiceOver's double-tap is the direct equivalent of a sighted user's
    /// single tap (it's how a non-`UIControl` accessibility element exposes
    /// its primary action) — so this mirrors `handleTap`, not
    /// `handleLongPress`: character AND voice. The character-only path stays
    /// reachable to VoiceOver users too, just via a different route (a
    /// physical long-press still works under VoiceOver on most iOS
    /// versions, and the hint below calls it out explicitly either way).
    override func accessibilityActivate() -> Bool {
        cycleCharacter()
        onVoiceLoad?(character)
        return true
    }

    private func updateAccessibility() {
        let format = NSLocalizedString(
            "character.accessibility",
            comment: "Accessibility label for the character view; %@ is the current character's display name.")
        accessibilityLabel = String(format: format, character.displayName)
        accessibilityHint = NSLocalizedString(
            "character.accessibilityHint",
            comment: "Accessibility hint for the character view, explaining both gestures.")
    }

    // MARK: - Name overlay

    /// Small pill showing the character's name for ~1s after cycling.
    /// `isUserInteractionEnabled` stays at its default `false` so taps
    /// landing on it still reach `CharacterView`'s own tap gesture rather
    /// than being swallowed by the label.
    private let nameOverlay: UILabel = {
        let label = UILabel()
        label.font = Theme.label(15, weight: .semibold)
        label.textColor = Theme.textPrimary
        label.textAlignment = .center
        label.alpha = 0
        label.backgroundColor = Theme.panel.withAlphaComponent(0.88)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        return label
    }()

    private func showNameOverlay(_ name: String) {
        nameOverlay.text = "  \(name)  "
        nameOverlay.layer.removeAllAnimations()
        nameOverlay.alpha = 1
        setNeedsLayout()
        layoutIfNeeded()
        UIView.animate(withDuration: 0.35, delay: 0.65, options: [.beginFromCurrentState], animations: {
            self.nameOverlay.alpha = 0
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fitting = nameOverlay.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let width = min(bounds.width, fitting.width)
        let height = fitting.height + 4
        nameOverlay.frame = CGRect(x: (bounds.width - width) / 2, y: 6, width: width, height: height)
    }

    // MARK: - Display link

    /// True while the idle animation should keep fidgeting. Reduce Motion
    /// suppresses idle fidgeting only — it does not suppress the
    /// instrument's own response, so a genuinely sounding note still
    /// animates the mouth regardless of this flag.
    private var idleShouldRun: Bool { !UIAccessibility.isReduceMotionEnabled }

    /// The display link only runs while there is something to animate: a
    /// note sounding, or the idle animation actively fidgeting. Otherwise it
    /// is torn down so an off-screen or motionless character costs nothing.
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
        // aspect ratios: every shape is defined in stage-relative fractions
        // (0...1 across both axes) and mapped through `point`.
        let side = min(rect.width, rect.height)
        let stage = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)

        character.drawBody(in: stage)

        let pose = currentPose
        character.drawEyes(in: stage, blinking: pose.blinking)
        // Quantised, not continuous: the mouth advances in discrete frames the
        // way the original sprite sheet did. See `quantisedVowel`.
        drawMouth(in: stage, vowel: Self.quantisedVowel(pose.vowel))
    }

    private func point(_ fx: CGFloat, _ fy: CGFloat, in stage: CGRect) -> CGPoint {
        CGPoint(x: stage.minX + fx * stage.width, y: stage.minY + fy * stage.height)
    }

    /// Draws the mouth aperture on every character's behalf, from its
    /// `mouthShape`/`mouthCentre`/`mouthBoxFraction`. Shared, not
    /// per-character: the aperture is always a plain dark oval — a "hole"
    /// reading as an open mouth against any character's face — so a
    /// character wanting a distinctive fixed mouth *frame* (the fish's
    /// prominent lips, the old man's beard) draws that fixed part itself in
    /// `drawBody`, and this composites the moving aperture on top of it.
    private func drawMouth(in stage: CGRect, vowel: Float) {
        let shape = character.mouthShape(vowel: vowel)
        // Step the amplitude swell too. A continuously-scaling mouth would
        // reintroduce exactly the glide that quantising the vowel removes —
        // the whole point is that the character moves in frames.
        let ampSteps: Float = 4
        let amp = (min(max(amplitude, 0), 1) * ampSteps).rounded() / ampSteps
        let ampBoost = 1 + CGFloat(amp) * 0.35
        let box = stage.width * character.mouthBoxFraction
        let w = box * shape.w
        let h = box * shape.h * ampBoost
        let c = point(character.mouthCentre.fx, character.mouthCentre.fy, in: stage)

        let mouth = UIBezierPath(ovalIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        Theme.background.setFill()
        mouth.fill()
        Theme.robeShadow.withAlphaComponent(0.5).setStroke()
        mouth.lineWidth = stage.width * 0.008
        mouth.stroke()
    }
}
