import UIKit

/// Dismissible overlay listing every registered character's NAME as a plain
/// text row — what `CharacterSelector`'s `⌄` opens. Replaces the old
/// character-ART grid (`CharacterPickerView`, deleted along with
/// `CharacterView.snapshot(of:size:)`, which existed solely to render that
/// grid's cells): the user asked for exactly this, "Just list names in a
/// drop down". At AUM-strip sizes the grid was "technically scrollable but
/// practically unusable — a clipped sliver of one row plus a Close button
/// filling the panel"; a plain list of fixed-height text rows scrolls
/// cleanly at any height instead, including that same strip.
///
/// Modelled on `AboutView`/`MoreAppsView`: scrim, centred panel,
/// tap-outside-to-dismiss, and it scrolls when the content doesn't fit — an
/// AUv3 host can hand this view an extremely short rect, and the roster is
/// expected to keep growing.
final class CharacterDropdownView: UIView {

    /// Fired when the user taps outside the panel or the close button,
    /// without picking anything.
    var onClose: (() -> Void)?
    /// Fired when the user taps a row. `PluginView` applies the selection
    /// (via `CharacterView.select(_:)`, which loads its voice too) and
    /// dismisses this overlay.
    var onSelect: ((Character) -> Void)?

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let closeButton = UIButton(type: .system)

    private static let panelPadding: CGFloat = 16
    private static let closeButtonHeight: CGFloat = 40
    private static let closeButtonGap: CGFloat = 12
    private static let maxPanelWidth: CGFloat = 320

    init(frame: CGRect, current: Character) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // Tap-outside-to-dismiss: same delegate trick as
        // `AboutView`/`MoreAppsView` — refuse any touch that lands on
        // `panel` or a descendant of it, so tapping a row or the close
        // button doesn't also dismiss via the backdrop recognizer.
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        tap.delegate = self
        addGestureRecognizer(tap)

        panel.backgroundColor = Theme.panel
        panel.layer.cornerRadius = Theme.cornerRadius
        panel.layer.borderWidth = 1
        panel.layer.borderColor = Theme.panelBorder.cgColor
        panel.clipsToBounds = true
        addSubview(panel)

        scrollView.alwaysBounceVertical = true
        panel.addSubview(scrollView)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        scrollView.addSubview(stack)

        let title = UILabel()
        title.text = NSLocalizedString("characterPicker.title", comment: "Character picker overlay title")
        title.font = Theme.label(16, weight: .bold)
        title.textColor = Theme.textPrimary
        title.numberOfLines = 0
        stack.addArrangedSubview(title)

        for character in CharacterRegistry.all {
            let row = CharacterDropdownRow(character: character, isCurrent: character.id == current.id)
            row.onTap = { [weak self] in self?.onSelect?(character) }
            stack.addArrangedSubview(row)
        }

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.title = NSLocalizedString("about.close", comment: "Dismiss the about screen")
        closeConfig.baseBackgroundColor = Theme.panelBorder
        closeConfig.baseForegroundColor = Theme.textPrimary
        closeConfig.cornerStyle = .medium
        closeButton.configuration = closeConfig
        closeButton.titleLabel?.font = Theme.label(13, weight: .semibold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        panel.addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func backdropTapped() { onClose?() }
    @objc private func closeTapped() { onClose?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin: CGFloat = 20
        let w = min(Self.maxPanelWidth, bounds.width - margin * 2)
        let maxPanelH = bounds.height - margin * 2
        guard w > 0, maxPanelH > 0 else { return }

        let padding = Self.panelPadding
        let innerW = w - padding * 2

        // How tall the stack WANTS to be at this width — may exceed what's
        // actually available; the scroll view absorbs the difference. Same
        // fitting-size approach as `AboutView`/`MoreAppsView`.
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: innerW, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let contentH = max(0, fitting.height)

        let desiredPanelH = padding * 2 + contentH + Self.closeButtonGap + Self.closeButtonHeight
        let panelH = min(desiredPanelH, maxPanelH)

        panel.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - panelH / 2,
                              width: w, height: panelH)

        closeButton.frame = CGRect(x: padding, y: panelH - padding - Self.closeButtonHeight,
                                    width: innerW, height: Self.closeButtonHeight)

        let scrollH = max(0, panelH - padding * 2 - Self.closeButtonGap - Self.closeButtonHeight)
        scrollView.frame = CGRect(x: padding, y: padding, width: innerW, height: scrollH)
        stack.frame = CGRect(x: 0, y: 0, width: innerW, height: contentH)
        scrollView.contentSize = CGSize(width: innerW, height: contentH)
    }
}

extension CharacterDropdownView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                            shouldReceive touch: UITouch) -> Bool {
        guard let touchView = touch.view else { return true }
        return !touchView.isDescendant(of: panel)
    }
}

/// One tappable roster row: the character's name and, for the currently
/// selected character, a checkmark. `UIControl`, not a plain view with a
/// gesture recognizer, mirroring `MoreAppsRow` — gets touch-down/up
/// highlighting and the standard `.button` accessibility affordances for
/// free. Fixed at the HIG's 44pt minimum row height, per the task.
private final class CharacterDropdownRow: UIControl {
    private let nameLabel = UILabel()
    private let checkmark = UIImageView()

    var onTap: (() -> Void)?

    static let height: CGFloat = 44
    private static let checkmarkSize: CGFloat = 18

    init(character: Character, isCurrent: Bool) {
        super.init(frame: .zero)
        backgroundColor = isCurrent ? Theme.panelBorder : Theme.panel
        layer.cornerRadius = 8
        layer.borderWidth = isCurrent ? 2 : 1
        layer.borderColor = (isCurrent ? Theme.accent : Theme.panelBorder).cgColor

        nameLabel.text = character.displayName
        nameLabel.font = Theme.label(15, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)

        checkmark.image = UIImage(systemName: "checkmark")
        checkmark.tintColor = Theme.accent
        checkmark.isHidden = !isCurrent
        checkmark.isUserInteractionEnabled = false
        addSubview(checkmark)

        // A single accessible element per row — `nameLabel` isn't
        // separately accessible (see its `isUserInteractionEnabled = false`
        // above). `.selected` makes VoiceOver announce "selected" for
        // whichever character is current, the accessible equivalent of the
        // checkmark badge — no separate string needed for it.
        isAccessibilityElement = true
        accessibilityLabel = character.displayName
        accessibilityTraits = isCurrent ? [.button, .selected] : .button

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 14
        checkmark.frame = CGRect(x: bounds.width - Self.checkmarkSize - pad,
                                  y: (bounds.height - Self.checkmarkSize) / 2,
                                  width: Self.checkmarkSize, height: Self.checkmarkSize)
        let nameW = max(0, bounds.width - pad * 2 - Self.checkmarkSize - 4)
        nameLabel.frame = CGRect(x: pad, y: 0, width: nameW, height: bounds.height)
    }

    @objc private func tapped() { onTap?() }
}
