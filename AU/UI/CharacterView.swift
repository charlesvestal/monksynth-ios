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
    /// applying a value read from `fullState`/`UserDefaults`); `stepForward()`/
    /// `stepBackward()`/`select(_:)` are just this setter plus a roster
    /// lookup plus the name overlay and `onCharacterSelected`.
    var character: Character = MonkCharacter() {
        didSet {
            updateAccessibility()
            setNeedsDisplay()
        }
    }

    /// Fired whenever the user actually changes the character — an arrow
    /// step or a picker selection (see `stepForward`/`stepBackward`/
    /// `select`) — never for a programmatic `character =` assignment, so an
    /// owner applying a restored/loaded value can't bounce right back into
    /// whatever wrote it.
    ///
    /// There used to be two callbacks here (`onCharacterChange` for "persist
    /// the id" and `onVoiceLoad`, fired only by a tap, for "and load its
    /// sound") because a long-press could change the character WITHOUT its
    /// voice. That escape hatch is gone — the user rejected it explicitly
    /// ("have arrows instead of tap to change. Then you know what's
    /// happening"): an arrow or a picker selection is unambiguous, so there
    /// is no accidental-sound-change case left to guard against. One
    /// callback, always both effects: the owner (`AudioUnitViewController`/
    /// `RootViewController`) persists `character.id` AND loads
    /// `CharacterVoiceTable.voice(for:)` into the parameter tree via
    /// `setValue(_:originator:)`, every time, no modes.
    var onCharacterSelected: ((Character) -> Void)?

    /// Fired when the user taps (or VoiceOver-activates) the character
    /// itself. `CharacterView` has no notion of overlays — exactly as it has
    /// no notion of parameters or voices (see the class doc comment) — so
    /// the owner (`PluginView`) is what actually presents the character
    /// picker in response.
    var onOpenPicker: (() -> Void)?

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
        addGestureRecognizer(tap)

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

    // MARK: - Stepping and selecting (arrows / picker)

    /// Advances to the next character in `CharacterRegistry.all`, wrapping
    /// from the last entry back to the first. What the "next character"
    /// arrow calls.
    func stepForward() {
        applyCharacter(CharacterRegistry.character(after: character))
    }

    /// Steps to the previous character, wrapping from the first entry back
    /// to the last. What the "previous character" arrow calls.
    func stepBackward() {
        applyCharacter(CharacterRegistry.character(before: character))
    }

    /// Jumps straight to `newCharacter` — what the picker overlay calls
    /// when the user taps a cell. Applies unconditionally, even if
    /// `newCharacter` is already the current one: re-loading the same
    /// voice is a harmless no-op, and treating "tapped the character
    /// that's already selected" as a special case would just be extra
    /// branching for no observable benefit.
    func select(_ newCharacter: Character) {
        applyCharacter(newCharacter)
    }

    /// The one place `character` actually changes in response to the user:
    /// updates the picture, fires `onCharacterSelected` (persist id + load
    /// voice — see that property's doc comment), and briefly overlays the
    /// new name. Shared by `stepForward`/`stepBackward`/`select` so all
    /// three routes behave identically, per the task's "one behaviour, no
    /// modes".
    private func applyCharacter(_ next: Character) {
        character = next
        onCharacterSelected?(next)
        showNameOverlay(next.displayName)
    }

    /// A tap on the character itself opens the picker — it does not, by
    /// itself, change anything. See `onOpenPicker`.
    @objc private func handleTap() {
        onOpenPicker?()
    }

    /// VoiceOver's double-tap is the direct equivalent of a sighted user's
    /// single tap (it's how a non-`UIControl` accessibility element exposes
    /// its primary action) — so this mirrors `handleTap`: it opens the
    /// picker, it does not change the character. Once the picker is open,
    /// each of its cells is its own accessible element a VoiceOver user can
    /// navigate to and double-tap to select — see `CharacterPickerView`.
    override func accessibilityActivate() -> Bool {
        onOpenPicker?()
        return true
    }

    private func updateAccessibility() {
        let format = NSLocalizedString(
            "character.accessibility",
            comment: "Accessibility label for the character view; %@ is the current character's display name.")
        accessibilityLabel = String(format: format, character.displayName)
        accessibilityHint = NSLocalizedString(
            "character.accessibilityHint",
            comment: "Accessibility hint for the character view, explaining that it opens a picker.")
    }

    // MARK: - Name overlay

    /// Small pill showing the character's name for ~1s after a step/select.
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

    // MARK: - Static snapshot rendering (for the character picker)

    /// Renders `character`'s idle pose into a plain, standalone image sized
    /// `size` — how the picker overlay (`CharacterPickerView`) shows each
    /// roster entry's art. Reuses this view's own `draw(_:)` (a temporary,
    /// never-window-attached instance) rather than the picker reimplementing
    /// any character drawing itself, per the task's "render each character's
    /// actual art in the cell... reuse rather than reimplement".
    ///
    /// Deliberately a one-shot render, not N live `CharacterView`s embedded
    /// in the grid: a `CharacterView` starts its own idle-animation
    /// `CADisplayLink` as soon as it's attached to a window (see
    /// `didMoveToWindow`/`updateDisplayLink`), so a picker listing a roster
    /// that's "about to grow well beyond six" would otherwise spin up one
    /// display link per cell for no visible benefit — the picker is a
    /// momentary overlay, not a place anyone watches for idle fidgeting.
    /// This view is never added to a window, so no display link is ever
    /// created; the returned `UIImage` is completely static.
    static func snapshot(of character: Character, size: CGSize) -> UIImage {
        let view = CharacterView(frame: CGRect(origin: .zero, size: size))
        view.character = character
        view.backgroundColor = .clear
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return UIGraphicsImageRenderer(size: size).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }
}
