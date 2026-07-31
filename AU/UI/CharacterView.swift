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
        // A window move can change the effective screen scale (e.g. moving
        // between simulators/screens with different `screen.scale`), which
        // is part of the body cache's key — force a redraw so a stale cache
        // rendered at the wrong scale isn't left on screen.
        setNeedsDisplay()
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

    // MARK: - Body cache
    //
    // `drawBody` is the expensive part now — six-plus `Shading` gradients
    // per character — and it never changes between frames: only the eyes
    // (blink) and the mouth (vowel/amplitude) animate. Rendering it into a
    // `UIImage` once and compositing that same bitmap every tick, instead
    // of replaying the gradient calls at up to 120Hz, is the difference
    // between "a few gradients on note-on/blink/vowel-step" and "a few
    // gradients every single frame" inside a host that's already doing
    // audio work. See the style spec's "Performance" section.
    //
    // The cache key is exactly the spec's three invalidation triggers
    // (character id, size, screen scale) — no separate "dirty" flag is
    // needed because `draw(_:)` recomputes the key every call and only
    // re-renders when it no longer matches.
    private struct BodyCacheKey: Equatable {
        let characterID: String
        let size: CGSize
        let scale: CGFloat
    }
    private var bodyCacheKey: BodyCacheKey?
    private var bodyCacheImage: UIImage?

    /// The screen scale to render the cached body at. Prefers the window's
    /// actual screen (so a view dragged to a different-scale display
    /// re-renders crisp), falling back to the trait collection and then
    /// `UIScreen.main` for views not yet in a window — the render-harness
    /// tests construct a `CharacterView` and snapshot it without ever
    /// adding it to a window.
    private var effectiveScale: CGFloat {
        if let windowScale = window?.screen.scale, windowScale > 0 { return windowScale }
        let traitScale = traitCollection.displayScale
        return traitScale > 0 ? traitScale : UIScreen.main.scale
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        // A centred square "stage" so the rig never distorts under odd
        // aspect ratios: every shape is defined in stage-relative fractions
        // (0...1 across both axes) and mapped through `point`. Derived from
        // `bounds` rather than the passed-in `rect` so it stays correct
        // regardless of what UIKit chooses to invalidate — `contentMode =
        // .redraw` (set in `init`) means a bounds change always triggers a
        // full redraw of this view anyway.
        let side = min(bounds.width, bounds.height)
        let stage = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)

        let scale = effectiveScale
        let key = BodyCacheKey(characterID: character.id, size: bounds.size, scale: scale)
        if bodyCacheKey != key {
            bodyCacheImage = renderBodyImage(stage: stage.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
                                              size: bounds.size, scale: scale)
            bodyCacheKey = key
        }
        bodyCacheImage?.draw(in: bounds)

        let pose = currentPose
        character.drawEyes(in: stage, blinking: pose.blinking)
        // Quantised, not continuous: the mouth advances in discrete frames the
        // way the original sprite sheet did. See `quantisedVowel`.
        drawMouth(in: stage, vowel: Self.quantisedVowel(pose.vowel))
    }

    /// Renders `character.drawBody` once into an offscreen bitmap at the
    /// given size/scale. `stage` is already shifted to a (0,0)-origin local
    /// coordinate space matching the renderer's own canvas — `bounds.origin`
    /// is practically always `.zero` for this view, but shifting explicitly
    /// keeps the cached image correct even if that ever stops being true,
    /// since the image is later composited back via `draw(in: bounds)`
    /// which reapplies that same origin.
    private func renderBodyImage(stage: CGRect, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            character.drawBody(in: stage)
        }
    }

    private func point(_ fx: CGFloat, _ fy: CGFloat, in stage: CGRect) -> CGPoint {
        CGPoint(x: stage.minX + fx * stage.width, y: stage.minY + fy * stage.height)
    }

    /// Draws the mouth aperture on every character's behalf, from its
    /// `mouthShape`/`mouthCentre`/`mouthBoxFraction`. Shared, not
    /// per-character: the aperture is always a `Shading.recess` — a
    /// genuine hole into the face, not a flat dark oval pasted on top of
    /// it — so a character wanting a distinctive fixed mouth *frame* (the
    /// fish's prominent lips, the old man's beard) draws that fixed part
    /// itself in `drawBody`, and this composites the moving aperture on top
    /// of it. Drawn fresh every frame (not part of the cached body image)
    /// since this is exactly the part that animates.
    private func drawMouth(in stage: CGRect, vowel: Float) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
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

        Shading.recess(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), into: context)
    }
}
