import UIKit

/// Dismissible overlay listing every registered character for the user to
/// choose from directly, modelled on `AboutView`/`MoreAppsView`: scrim,
/// centred panel, tap-outside-to-dismiss, and it scrolls when the content
/// doesn't fit — an AUv3 host can hand this view an extremely short rect
/// (see `PluginView`'s own doc comment on host-supplied sizes), and the
/// roster is expected to grow well past its current six entries.
///
/// A GRID, not a list: this panel exists specifically to show each
/// character's ART, not just its name — `MoreAppsRow`'s one-line-per-entry
/// list reads fine for app names, but reduces a character down to text,
/// which defeats the point of a picker whose whole job is "recognise the
/// look you want". Several thumbnails per row is also simply a better fit
/// for a roster that's about to outgrow six: a list of even a dozen
/// full-width rows requires far more scrolling than the same dozen laid out
/// three across.
///
/// Renders each cell's art via `CharacterView.snapshot(of:size:)` — the
/// actual character rig, not a re-implementation of it — per the task's
/// "render each character's actual art in the cell... reuse rather than
/// reimplement".
final class CharacterPickerView: UIView {

    /// Fired when the user taps outside the panel or the close button,
    /// without picking anything.
    var onClose: (() -> Void)?
    /// Fired when the user taps a cell. `PluginView` applies the selection
    /// (via `CharacterView.select(_:)`) and dismisses this overlay.
    var onSelect: ((Character) -> Void)?

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let closeButton = UIButton(type: .system)

    private static let panelPadding: CGFloat = 16
    private static let closeButtonHeight: CGFloat = 40
    private static let closeButtonGap: CGFloat = 12
    private static let maxPanelWidth: CGFloat = 360

    /// Three across reads comfortably at `maxPanelWidth` (360pt: ~16pt
    /// padding on each side, three ~96pt cells, two ~12pt gaps) without the
    /// art shrinking so small it stops being recognisable, and keeps the
    /// panel from growing to a height dominated by a single very wide row
    /// on today's six-character roster (two rows of three). Not tied to the
    /// roster's exact count — a seventh, seedy, or eleventh character just
    /// adds another (possibly partial) row.
    private static let columns = 3

    init(frame: CGRect, current: Character) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // Tap-outside-to-dismiss: same delegate trick as
        // `AboutView`/`MoreAppsView` — refuse any touch that lands on
        // `panel` or a descendant of it, so tapping a cell or the close
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
        stack.spacing = 12
        scrollView.addSubview(stack)

        let title = UILabel()
        title.text = NSLocalizedString("characterPicker.title", comment: "Character picker overlay title")
        title.font = Theme.label(18, weight: .bold)
        title.textColor = Theme.textPrimary
        title.numberOfLines = 0
        stack.addArrangedSubview(title)

        let all = CharacterRegistry.all
        var start = all.startIndex
        while start < all.endIndex {
            let end = min(start + Self.columns, all.endIndex)
            let row = CharacterGridRow(characters: Array(all[start..<end]), currentID: current.id) { [weak self] character in
                self?.onSelect?(character)
            }
            stack.addArrangedSubview(row)
            start = end
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

extension CharacterPickerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                            shouldReceive touch: UITouch) -> Bool {
        guard let touchView = touch.view else { return true }
        return !touchView.isDescendant(of: panel)
    }
}

/// One row of up to `CharacterPickerView.columns` cells, manually laid out
/// left-to-right at a fixed cell size — matching this app's general
/// preference for `layoutSubviews` frame math over Auto Layout constraints
/// for anything below the panel-level scroll/stack scaffolding (see
/// `MoreAppsRow` for the same pattern applied to a single row). Sits as one
/// arranged subview inside `CharacterPickerView.stack`, so the panel's
/// existing "fitting size, then scroll if it doesn't fit" machinery treats
/// a whole row exactly like it already treats a label or a button.
private final class CharacterGridRow: UIView {
    private let cells: [CharacterCell]

    static let cellSize = CGSize(width: 92, height: 116)
    static let spacing: CGFloat = 12

    init(characters: [Character], currentID: String, onSelect: @escaping (Character) -> Void) {
        cells = characters.map { character in
            let cell = CharacterCell(character: character, isCurrent: character.id == currentID)
            cell.onTap = { onSelect(character) }
            return cell
        }
        super.init(frame: .zero)
        cells.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Width is whatever the stack's `.fill` alignment gives it; only the
    /// height needs to be intrinsic so `systemLayoutSizeFitting` can size
    /// the panel around a stack of these rows.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.cellSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 0
        for cell in cells {
            cell.frame = CGRect(x: x, y: 0, width: Self.cellSize.width, height: Self.cellSize.height)
            x += Self.cellSize.width + Self.spacing
        }
    }
}

/// One tappable roster entry: the character's actual rendered art (via
/// `CharacterView.snapshot(of:size:)`, never re-implemented here), its
/// name, and — for the currently-selected character — a highlighted border
/// plus a checkmark badge. `UIControl`, not a plain view with a gesture
/// recognizer, mirroring `MoreAppsRow`: gets touch-down/up highlighting and
/// the standard `.button` accessibility affordances for free.
private final class CharacterCell: UIControl {
    private let artView = UIImageView()
    private let nameLabel = UILabel()
    private let checkmark = UIImageView()

    var onTap: (() -> Void)?

    private static let artInset: CGFloat = 8
    private static let checkmarkSize: CGFloat = 18

    init(character: Character, isCurrent: Bool) {
        super.init(frame: .zero)
        backgroundColor = Theme.panel
        layer.cornerRadius = 8
        layer.borderWidth = isCurrent ? 2 : 1
        layer.borderColor = (isCurrent ? Theme.accent : Theme.panelBorder).cgColor

        let artSize = CharacterGridRow.cellSize.width - Self.artInset * 2
        artView.image = CharacterView.snapshot(
            of: character, size: CGSize(width: artSize, height: artSize))
        artView.contentMode = .scaleAspectFit
        artView.isUserInteractionEnabled = false
        addSubview(artView)

        nameLabel.text = character.displayName
        nameLabel.font = Theme.label(11, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.textAlignment = .center
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)

        checkmark.image = UIImage(systemName: "checkmark.circle.fill")
        checkmark.tintColor = Theme.accent
        checkmark.isHidden = !isCurrent
        checkmark.isUserInteractionEnabled = false
        addSubview(checkmark)

        // A single accessible element per cell — `artView`/`nameLabel`
        // aren't separately accessible (see their `isUserInteractionEnabled
        // = false` above, which also keeps VoiceOver from stopping on them
        // individually since they're plain image/label views, not controls).
        // `.selected` makes VoiceOver announce "selected" for whichever
        // character is current, which is the accessible equivalent of the
        // checkmark badge — no separate string needed for it.
        isAccessibilityElement = true
        accessibilityLabel = character.displayName
        accessibilityTraits = isCurrent ? [.button, .selected] : .button

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let artSize = bounds.width - Self.artInset * 2
        artView.frame = CGRect(x: Self.artInset, y: Self.artInset, width: artSize, height: artSize)
        nameLabel.frame = CGRect(x: 2, y: artView.frame.maxY + 4,
                                  width: bounds.width - 4, height: 16)
        checkmark.frame = CGRect(x: bounds.width - Self.checkmarkSize - 4, y: 4,
                                  width: Self.checkmarkSize, height: Self.checkmarkSize)
    }

    @objc private func tapped() { onTap?() }
}
