import UIKit

/// The header's character control:
///
/// ```
///    (‹)   Monk ⌄   (›)
/// ```
///
/// Two round sticker buttons (cream, ink outline, hard ink shadow) step to
/// the previous/next character, wrapping; between them the character's name
/// in heavy rounded type with a small chevron in the character's accent after it.
/// Tapping the name opens `CharacterDropdownView`; the chevron is drawn on
/// the name control's layer, not a separate tap target.
///
/// The current character's NAME is shown as text (never its art — that was
/// the old picker's whole problem at AUM-strip sizes, see
/// `CharacterDropdownView`'s doc comment).
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
/// not beside the character art, so it is there at every host size —
/// including the AUM strip with the drawer open, where the scene is dropped
/// altogether.
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
            setNeedsLayout()
        }
    }

    /// The colour of the chevron after the name — the accent passed to the
    /// last `applyPalette(accent:)`.
    private(set) var chevronColor: UIColor = Theme.defaultAccent

    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    private let nameControl = AdjustableControl()
    private let nameLabel = UILabel()
    /// The round sticker faces behind the arrow glyphs. Non-interactive
    /// subviews at the back of each button, so the buttons' own frames stay
    /// the (larger) tap targets.
    private let leftDisc = StickerShapeView(fill: Theme.cream, dropShadow: true)
    private let rightDisc = StickerShapeView(fill: Theme.cream, dropShadow: true)
    /// The accent chevron after the name, drawn on `nameControl`'s layer.
    private let chevron = CAShapeLayer()

    /// Diameter of the visible arrow buttons.
    static let arrowDiscSize: CGFloat = 36
    private static let chevronSize = CGSize(width: 11, height: 7)
    private static let chevronGap: CGFloat = 5

    /// Ideal width for each arrow button when there's room for it. Matches
    /// the old `PluginView.arrowHitSize` this view replaces. The visible
    /// sticker disc drawn inside that width is smaller (`arrowDiscSize`) —
    /// same "small glyph, big hit region" pattern as
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
        backgroundColor = .clear

        // Small heavy ink glyphs on round cream sticker faces. The tap
        // target underneath (`leftButton`/`rightButton`'s own frame, set in
        // `layoutSubviews`) stays at `idealArrowWidth`/height regardless —
        // only the visible disc is smaller.
        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .heavy)
        leftButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: arrowConfig), for: .normal)
        rightButton.setImage(UIImage(systemName: "chevron.right", withConfiguration: arrowConfig), for: .normal)
        for (button, disc) in [(leftButton, leftDisc), (rightButton, rightDisc)] {
            button.tintColor = Theme.ink
            button.insertSubview(disc, at: 0)
            addSubview(button)
        }
        leftButton.accessibilityLabel = NSLocalizedString(
            "character.previous", comment: "Steps to the previous character")
        rightButton.accessibilityLabel = NSLocalizedString(
            "character.next", comment: "Steps to the next character")
        leftButton.addTarget(self, action: #selector(stepBackwardTapped), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(stepForwardTapped), for: .touchUpInside)

        nameLabel.font = Theme.display(22)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        // Shrinks a little, then truncates: this view is handed a width
        // computed purely from layout geometry (see
        // `PluginView.characterSelectorFrame`) that never grows to
        // accommodate a longer string. At the AUM strip that width is too
        // narrow for even "Monk" at 22pt, so the name steps down toward
        // 11pt before it ellipsizes.
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.5
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isUserInteractionEnabled = false
        nameControl.addSubview(nameLabel)

        chevron.fillColor = nil
        chevron.lineWidth = 3
        chevron.lineCap = .round
        chevron.lineJoin = .round
        chevron.strokeColor = chevronColor.cgColor
        let cs = Self.chevronSize
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 1.5, y: 1.5))
        path.addLine(to: CGPoint(x: cs.width / 2, y: cs.height - 1.5))
        path.addLine(to: CGPoint(x: cs.width - 1.5, y: 1.5))
        chevron.path = path.cgPath
        chevron.bounds = CGRect(origin: .zero, size: cs)
        nameControl.layer.addSublayer(chevron)

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

    /// Re-tints the chevron after the name with the character's accent.
    func applyPalette(accent: UIColor) {
        chevronColor = accent
        chevron.strokeColor = chevronColor.cgColor
    }

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

        let disc = min(Self.arrowDiscSize, arrowW - 4, bounds.height - 4)
        for (button, view) in [(leftButton, leftDisc), (rightButton, rightDisc)] {
            view.frame = CGRect(x: (button.bounds.width - disc) / 2, y: (button.bounds.height - disc) / 2 - 1.5,
                                width: disc, height: disc)
            // UIButton adds its image view lazily (at the back) during its
            // own layout; lay it out first so the disc can go behind it.
            button.layoutIfNeeded()
            button.sendSubviewToBack(view)
        }

        // The name and its chevron are centred as one group; the name
        // truncates to whatever is left once the chevron has its room.
        let room = Self.chevronSize.width + Self.chevronGap
        let available = max(0, nameControl.bounds.width - 4 - room)
        let textW = ceil(nameLabel.sizeThatFits(CGSize(width: .greatestFiniteMagnitude,
                                                         height: nameControl.bounds.height)).width)
        let labelW = min(textW, available)
        let x = max(2, (nameControl.bounds.width - labelW - room) / 2)
        nameLabel.frame = CGRect(x: x, y: 0, width: labelW, height: nameControl.bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chevron.position = CGPoint(x: nameLabel.frame.maxX + Self.chevronGap + Self.chevronSize.width / 2,
                                   y: nameControl.bounds.midY + 1)
        CATransaction.commit()
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
