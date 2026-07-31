import UIKit

/// Compact horizontal control replacing the old edge arrows plus the
/// tap-the-art grid picker:
///
/// ```
///    ‹   Monk  ⌄   ›
/// ```
///
/// The current character's NAME is shown as text (never its art — that was
/// the old picker's whole problem at AUM-strip sizes, see
/// `CharacterDropdownView`'s doc comment). `‹`/`›` step to the
/// previous/next character, wrapping; the name and the `⌄` chevron share one
/// tap target that opens `CharacterDropdownView`.
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
/// Lives in `PluginView`'s header row (see
/// `PluginView.characterSelectorFrame(bounds:safeArea:infoButton:handle:)`),
/// not beside the character art — unlike the arrows it replaces, that means
/// it never disappears just because the stage collapsed at a short host
/// rect. That's deliberate: the task this shipped for called it out by name
/// as "a real gain, not an accident".
final class CharacterSelector: UIView {

    /// `‹` tapped — step to the previous character (wrapping).
    var onStepBackward: (() -> Void)?
    /// `›` tapped — step to the next character (wrapping).
    var onStepForward: (() -> Void)?
    /// The name or the `⌄` chevron tapped (or VoiceOver double-tapped) —
    /// open `CharacterDropdownView`.
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
    private let chevron = UIImageView()

    /// Ideal width for each arrow button when there's room for it. Matches
    /// the old `PluginView.arrowHitSize` this view replaces.
    private static let idealArrowWidth: CGFloat = 44
    /// The floor an arrow's width shrinks to — never below this — when the
    /// row is too narrow to give every one of the three targets its ideal
    /// width at once. See `layoutSubviews`.
    private static let minArrowWidth: CGFloat = 32
    /// The name+chevron target's own floor, protected the same way: at the
    /// row's narrowest realistic width (the AUM strip, 375×180 — see
    /// `PluginViewTests`/`RenderUISnapshot`) the arithmetic in
    /// `layoutSubviews` still clears this without needing to invoke the
    /// floor at all, so this mostly documents the invariant rather than
    /// actively biting today.
    private static let minNameWidth: CGFloat = 44
    private static let chevronWidth: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.panel
        layer.borderWidth = 1
        layer.borderColor = Theme.panelBorder.cgColor
        clipsToBounds = true

        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
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

        nameLabel.font = Theme.label(13, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        // Shrinks rather than truncates at the row's narrowest realistic
        // width (the AUM strip) — a shrunk-but-whole name reads better in a
        // widget this small than an ellipsis eating half of it.
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.55
        nameLabel.isUserInteractionEnabled = false
        nameControl.addSubview(nameLabel)

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        chevron.image = UIImage(systemName: "chevron.down", withConfiguration: chevronConfig)
        chevron.tintColor = Theme.textDim
        chevron.contentMode = .center
        chevron.isUserInteractionEnabled = false
        nameControl.addSubview(chevron)

        // A single adjustable accessibility element, per the task: the name
        // as the VALUE, previous/next as the ADJUST actions (a VoiceOver
        // swipe up/down steps the character without needing to find the
        // small `‹`/`›` glyphs), and the hint explains what the chevron's
        // affordance (double-tap) does.
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
        layer.cornerRadius = bounds.height / 2

        // Ideal: both arrows at their full width. When the row is too
        // narrow for that (only the shortest AUM-strip-style host rects —
        // see `PluginView.characterSelectorFrame`), shrink both arrows
        // toward their floor together, split evenly, to protect the
        // name+chevron target's own width rather than starving it first.
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

        let chevronW = min(Self.chevronWidth, nameControl.bounds.width)
        let labelW = max(0, nameControl.bounds.width - chevronW - 2)
        nameLabel.frame = CGRect(x: 2, y: 0, width: labelW, height: nameControl.bounds.height)
        chevron.frame = CGRect(x: nameControl.bounds.width - chevronW, y: 0,
                                width: chevronW, height: nameControl.bounds.height)
    }
}

/// The name+chevron combined tap target. A `UIControl` (so a normal tap
/// fires the standard `.touchUpInside` action `CharacterSelector` uses to
/// open the dropdown) that also implements `accessibilityIncrement`/
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
