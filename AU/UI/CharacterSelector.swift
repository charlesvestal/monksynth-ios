import UIKit

/// A quiet, centred label replacing the old edge arrows, the tap-the-art
/// grid picker, and (as of this revision) the filled-pill "‹ Monk ⌄ ›"
/// control that followed it:
///
/// ```
///    ‹   Monk   ›
/// ```
///
/// No background, no border, no chevron — reported as "silly", reading as a
/// chunky widget when the character name is a minor, ambient readout, not
/// the main event. Now it's just glyphs and text sitting directly on
/// `Theme.background`, in `Theme.textDim`, small type. Tapping the NAME
/// itself is the entire "open the list" affordance; there is no separate
/// chevron mark.
///
/// The current character's NAME is shown as text (never its art — that was
/// the old picker's whole problem at AUM-strip sizes, see
/// `CharacterDropdownView`'s doc comment). `‹`/`›` step to the
/// previous/next character, wrapping; tapping the name opens
/// `CharacterDropdownView`.
///
/// `CharacterSelector` owns no character-stepping or voice-loading logic of
/// its own — it only relays user intent through three closures.
/// `PluginView` wires `onStepBackward`/`onStepForward` straight to
/// `CharacterView.stepBackward()`/`stepForward()` (unchanged from what the
/// old arrow buttons called) and `onOpenDropdown` to presenting
/// `CharacterDropdownView`, so every existing guarantee about a character
/// change also loading its voice through `setValue(_:originator:)` is
/// untouched — this view never touches `CharacterVoiceTable` or the
/// parameter tree, exactly as `CharacterView` itself never did.
///
/// Lives in `PluginView`'s header row, centred (see
/// `PluginView.characterSelectorFrame(bounds:safeArea:infoButton:handle:)`),
/// not beside the character art — unlike the arrows it replaces, that means
/// it never disappears just because the stage collapsed at a short host
/// rect. That's deliberate: the task this shipped for called it out by name
/// as "a real gain, not an accident".
///
/// A future roster will have names longer than "Monk" ("Opera Singer",
/// "Fire Fighter"). `nameLabel` truncates (`.byTruncatingTail`) rather than
/// growing the view — `PluginView.characterSelectorFrame` hands this view a
/// width computed purely from layout geometry (so it never collides with
/// `infoButton`, whatever the string), and the content clips to whatever
/// width it's given rather than the other way around.
final class CharacterSelector: UIView {

    /// `‹` tapped — step to the previous character (wrapping).
    var onStepBackward: (() -> Void)?
    /// `›` tapped — step to the next character (wrapping).
    var onStepForward: (() -> Void)?
    /// The name tapped (or VoiceOver double-tapped) — open
    /// `CharacterDropdownView`. The name IS the whole "open the list"
    /// affordance now; there is no separate chevron target.
    var onOpenDropdown: (() -> Void)?

    /// The name currently shown. `PluginView` keeps this in sync with
    /// `CharacterView.character.displayName` via `CharacterView.onCharacterChanged`,
    /// so it tracks every route a character can change through — the
    /// arrows, a dropdown row, or a programmatic restore (host automation,
    /// `fullState`, `UserDefaults`) — not just the two routes this view
    /// itself can trigger.
    var characterName: String = "" {
        didSet {
            guard oldValue != characterName else { return }
            nameLabel.text = characterName
            nameControl.accessibilityValue = characterName
        }
    }

    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    private let nameControl = AdjustableControl()
    private let nameLabel = UILabel()

    /// Ideal width for each arrow button when there's room for it. Matches
    /// the old `PluginView.arrowHitSize` this view replaces. The visible
    /// glyph drawn inside that width is much smaller (see the thin, small
    /// `arrowConfig` below) — same "small glyph, big hit region" pattern as
    /// `PluginView.infoButton` and the drawer handle.
    private static let idealArrowWidth: CGFloat = 44
    /// The floor an arrow's width shrinks to — never below this — when the
    /// row is too narrow to give every one of the three targets its ideal
    /// width at once. See `layoutSubviews`.
    private static let minArrowWidth: CGFloat = 32
    /// The name target's own floor, protected the same way: at the row's
    /// narrowest realistic width (the AUM strip, 375×180 — see
    /// `PluginViewTests`/`RenderUISnapshot`) the arithmetic in
    /// `layoutSubviews` still clears this without needing to invoke the
    /// floor at all, so this mostly documents the invariant rather than
    /// actively biting today.
    private static let minNameWidth: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        // No pill, no border: just the glyphs and the name sitting directly
        // on whatever's behind this view (`Theme.background`, in practice).
        // Reported feedback was that the filled capsule this view used to
        // draw read as "silly" — an over-designed control for something
        // that's meant to recede, not announce itself.
        backgroundColor = .clear

        // Thin, small, dim: a quiet mark rather than a button. The tap
        // target underneath (`leftButton`/`rightButton`'s own frame, set in
        // `layoutSubviews`) stays at `idealArrowWidth`/height regardless —
        // only the visible glyph shrinks.
        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .light)
        leftButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: arrowConfig), for: .normal)
        rightButton.setImage(UIImage(systemName: "chevron.right", withConfiguration: arrowConfig), for: .normal)
        for button in [leftButton, rightButton] {
            button.tintColor = Theme.textDim
            addSubview(button)
        }
        leftButton.accessibilityLabel = NSLocalizedString(
            "character.previous", comment: "Steps to the previous character")
        rightButton.accessibilityLabel = NSLocalizedString(
            "character.next", comment: "Steps to the next character")
        leftButton.addTarget(self, action: #selector(stepBackwardTapped), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(stepForwardTapped), for: .touchUpInside)

        nameLabel.font = Theme.label(12, weight: .regular)
        nameLabel.textColor = Theme.textDim
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        // Truncates rather than shrinks: a future roster will have names
        // longer than "Monk" ("Opera Singer", "Fire Fighter"), and this
        // view is handed a width computed purely from layout geometry (see
        // `PluginView.characterSelectorFrame`) that never grows to
        // accommodate a longer string — an ellipsis at the clamped width
        // reads better in a label this quiet than shrinking the font to
        // the point of illegibility.
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isUserInteractionEnabled = false
        nameControl.addSubview(nameLabel)

        // A single adjustable accessibility element, per the task: the name
        // as the VALUE, previous/next as the ADJUST actions (a VoiceOver
        // swipe up/down steps the character without needing to find the
        // small `‹`/`›` glyphs), and the hint explains what double-tapping
        // the name itself does — there is no separate chevron mark to
        // describe.
        nameControl.isAccessibilityElement = true
        nameControl.accessibilityLabel = NSLocalizedString(
            "characterSelector.label",
            comment: "Accessibility label naming the character selector's adjustable name/dropdown control")
        nameControl.accessibilityHint = NSLocalizedString(
            "characterSelector.hint",
            comment: "Accessibility hint for the character selector: swipe to step, double-tap to open the full list")
        nameControl.accessibilityTraits = .adjustable
        nameControl.onIncrement = { [weak self] in self?.onStepForward?() }
        nameControl.onDecrement = { [weak self] in self?.onStepBackward?() }
        nameControl.onActivate = { [weak self] in self?.onOpenDropdown?() }
        nameControl.addTarget(self, action: #selector(openDropdownTapped), for: .touchUpInside)
        addSubview(nameControl)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func stepBackwardTapped() { onStepBackward?() }
    @objc private func stepForwardTapped() { onStepForward?() }
    @objc private func openDropdownTapped() { onOpenDropdown?() }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Ideal: both arrows at their full width. When the row is too
        // narrow for that (only the shortest AUM-strip-style host rects —
        // see `PluginView.characterSelectorFrame`), shrink both arrows
        // toward their floor together, split evenly, to protect the name
        // target's own width rather than starving it first.
        let total = bounds.width
        let neededForIdeal = Self.idealArrowWidth * 2 + Self.minNameWidth
        var arrowW = Self.idealArrowWidth
        if total < neededForIdeal {
            let deficit = neededForIdeal - total
            arrowW = max(Self.minArrowWidth, Self.idealArrowWidth - deficit / 2)
        }
        let nameW = max(0, total - arrowW * 2)

        leftButton.frame = CGRect(x: 0, y: 0, width: arrowW, height: bounds.height)
        nameControl.frame = CGRect(x: arrowW, y: 0, width: nameW, height: bounds.height)
        rightButton.frame = CGRect(x: total - arrowW, y: 0, width: arrowW, height: bounds.height)

        // No chevron to carve room for any more — the label gets the whole
        // name control's width, minus a hair of breathing room on each side.
        let labelW = max(0, nameControl.bounds.width - 4)
        nameLabel.frame = CGRect(x: 2, y: 0, width: labelW, height: nameControl.bounds.height)
    }
}

/// The name's own tap target. A `UIControl` (so a normal tap fires the
/// standard `.touchUpInside` action `CharacterSelector` uses to open the
/// dropdown) that also implements `accessibilityIncrement`/
/// `accessibilityDecrement` (a VoiceOver swipe up/down) and overrides
/// `accessibilityActivate` (a VoiceOver double-tap) so it reads as one
/// value-adjustable element rather than a plain button — see
/// `CharacterSelector.init`'s accessibility setup.
private final class AdjustableControl: UIControl {
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    var onActivate: (() -> Void)?

    override func accessibilityIncrement() { onIncrement?() }
    override func accessibilityDecrement() { onDecrement?() }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}
