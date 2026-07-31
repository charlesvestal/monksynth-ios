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
    /// lookup plus `onCharacterSelected`.
    var character: Character = MonkCharacter() {
        didSet {
            setNeedsDisplay()
            onCharacterChanged?(character)
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
    /// happening"): an arrow or a dropdown selection is unambiguous, so
    /// there is no accidental-sound-change case left to guard against. One
    /// callback, always both effects: the owner (`AudioUnitViewController`/
    /// `RootViewController`) persists `character.id` AND loads
    /// `CharacterVoiceTable.voice(for:)` into the parameter tree via
    /// `setValue(_:originator:)`, every time, no modes.
    var onCharacterSelected: ((Character) -> Void)?

    /// Fired on EVERY change to `character` — both user-driven (routed
    /// through `applyCharacter`, which also fires `onCharacterSelected`) and
    /// purely programmatic (a direct `character = ...` assignment, e.g.
    /// `AudioUnitViewController` seeding from `au.characterID` at bind time,
    /// or reacting to `onCharacterIDChange` when a session/preset restores
    /// later; `RootViewController` restoring from `UserDefaults`). Those
    /// direct-assignment routes never go through `applyCharacter`, so
    /// `onCharacterSelected` alone can't keep `PluginView.characterSelector`'s
    /// name label in sync with them — this fires unconditionally instead,
    /// specifically for that purpose. `onCharacterSelected` stays scoped to
    /// the narrower "the user changed it, go persist + load its voice" case.
    var onCharacterChanged: ((Character) -> Void)?

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
        // Purely decorative now: the character art has no gesture of its
        // own (see the class doc comment on `onCharacterSelected`/
        // `onCharacterChanged`) — `CharacterSelector` is the single place
        // that names the current character and lets it be changed, so this
        // view is neither interactive nor an accessibility element, rather
        // than duplicating what the selector already offers.
        isUserInteractionEnabled = false
        isAccessibilityElement = false

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

    // MARK: - Stepping and selecting (CharacterSelector's ‹/›/dropdown)

    /// Advances to the next character in `CharacterRegistry.all`, wrapping
    /// from the last entry back to the first. What `CharacterSelector`'s
    /// `›` button calls (via `PluginView`).
    func stepForward() {
        applyCharacter(CharacterRegistry.character(after: character))
    }

    /// Steps to the previous character, wrapping from the first entry back
    /// to the last. What `CharacterSelector`'s `‹` button calls.
    func stepBackward() {
        applyCharacter(CharacterRegistry.character(before: character))
    }

    /// Jumps straight to `newCharacter` — what `CharacterDropdownView` calls
    /// when the user taps a row. Applies unconditionally, even if
    /// `newCharacter` is already the current one: re-loading the same
    /// voice is a harmless no-op, and treating "picked the character
    /// that's already selected" as a special case would just be extra
    /// branching for no observable benefit.
    func select(_ newCharacter: Character) {
        applyCharacter(newCharacter)
    }

    /// The one place `character` actually changes in response to the user:
    /// updates the picture and fires `onCharacterSelected` (persist id +
    /// load voice — see that property's doc comment). Shared by
    /// `stepForward`/`stepBackward`/`select` so all three routes behave
    /// identically, per the task's "one behaviour, no modes".
    private func applyCharacter(_ next: Character) {
        character = next
        onCharacterSelected?(next)
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

    // MARK: - Static thumbnails (presets overlay)

    /// Renders `character`'s idle, non-blinking pose into a plain image,
    /// sized to `size` — what `PresetsView` shows as a saved user preset's
    /// face. Deliberately does NOT add the view to a window: `CharacterView`
    /// only ever starts its `CADisplayLink` once `window != nil` (see
    /// `updateDisplayLink`), so a bare, never-windowed instance drawn once
    /// via `layer.render(in:)` — the same technique `RenderUISnapshot`
    /// already relies on for whole-plugin snapshots — costs exactly one
    /// synchronous draw and nothing more: no live animation timer for what
    /// is, in a preset list, a static thumbnail.
    static func thumbnail(of character: Character, size: CGSize) -> UIImage {
        let view = CharacterView(frame: CGRect(origin: .zero, size: size))
        view.character = character
        return UIGraphicsImageRenderer(size: size).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
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

    /// Computes the stepped amplitude swell and hands off to
    /// `character.drawMouth` — the character's own behalf, not this view's:
    /// a drawn character (`Character`'s default `drawMouth` implementation)
    /// paints a plain dark oval sized from `mouthShape`/`mouthCentre`/
    /// `mouthBoxFraction`, while an image-backed one (`SpriteCharacter`)
    /// composites a mouth frame instead. `CharacterView` deliberately knows
    /// nothing about which kind of character it's holding — see
    /// `Character.drawMouth`'s doc comment.
    private func drawMouth(in stage: CGRect, vowel: Float) {
        // Step the amplitude swell too. A continuously-scaling mouth would
        // reintroduce exactly the glide that quantising the vowel removes —
        // the whole point is that the character moves in frames.
        let ampSteps: Float = 4
        let amp = (min(max(amplitude, 0), 1) * ampSteps).rounded() / ampSteps
        let ampBoost = 1 + CGFloat(amp) * 0.35
        character.drawMouth(in: stage, vowel: vowel, amplitudeBoost: ampBoost)
    }
}
