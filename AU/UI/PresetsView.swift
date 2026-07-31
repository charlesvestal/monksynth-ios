import UIKit

/// Dismissible overlay listing every preset — the six read-only factory ones
/// (`kFactoryPresets`) and the user's own saved ones (`store.
/// savedUserPresets`, each shown with the character it was saved with) —
/// plus, where the current container supports it (see
/// `PresetStoring.supportsUserPresets`), a way to save whatever's currently
/// loaded under a new name and to delete a saved one. This is the home for
/// "saving custom presets (use last selected image for it?)" -> "character
/// image plus a name."
///
/// Modelled on `AboutView`/`MoreAppsView`/`CharacterDropdownView`: scrim,
/// centred panel, tap-outside-to-dismiss, and it scrolls when the content
/// doesn't fit — an AUv3 host can hand this view an extremely short rect,
/// and both the factory list and the user's own list only grow over time.
final class PresetsView: UIView {

    /// Fired when the user taps outside the panel or the close button,
    /// without picking anything.
    var onClose: (() -> Void)?
    /// A factory preset row was tapped — the index into `kFactoryPresets`.
    /// The owner applies it (sound only; factory presets carry no saved
    /// character — see the task) and dismisses this overlay.
    var onSelectFactoryPreset: ((Int) -> Void)?
    /// A user preset row was tapped, already resolved to its full
    /// `PresetSnapshot` (params + character). The owner applies it (sound
    /// AND character together) and dismisses this overlay.
    var onSelectUserPreset: ((PresetSnapshot) -> Void)?

    private let store: PresetStoring

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let closeButton = UIButton(type: .system)

    private let saveRow = PresetSaveRow()
    private let feedbackLabel = UILabel()

    private let userSectionHeader = UILabel()
    private let emptyLabel = UILabel()
    private let userRowsContainer = UIStackView()
    private var userRows: [PresetUserRow] = []

    private static let panelPadding: CGFloat = 16
    private static let closeButtonHeight: CGFloat = 40
    private static let closeButtonGap: CGFloat = 12
    private static let maxPanelWidth: CGFloat = 340

    init(frame: CGRect, store: PresetStoring) {
        self.store = store
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // Tap-outside-to-dismiss: same delegate trick as
        // `AboutView`/`MoreAppsView`/`CharacterDropdownView` — refuse any
        // touch landing on `panel` or a descendant of it.
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
        stack.spacing = 10
        scrollView.addSubview(stack)

        let title = UILabel()
        title.text = NSLocalizedString("presets.title", comment: "Presets overlay title")
        title.font = Theme.label(16, weight: .bold)
        title.textColor = Theme.textPrimary
        title.numberOfLines = 0
        stack.addArrangedSubview(title)

        installSaveSection()

        addSectionHeader(NSLocalizedString("presets.factory", comment: "Factory presets section header"))
        for (index, preset) in kFactoryPresets.enumerated() {
            let row = PresetFactoryRow(name: preset.name)
            row.onTap = { [weak self] in self?.onSelectFactoryPreset?(index) }
            stack.addArrangedSubview(row)
        }

        userSectionHeader.text = NSLocalizedString("presets.user", comment: "User presets section header")
        userSectionHeader.font = Theme.label(12, weight: .semibold)
        userSectionHeader.textColor = Theme.textDim
        stack.addArrangedSubview(userSectionHeader)

        emptyLabel.text = NSLocalizedString("presets.empty", comment: "Shown when there are no saved user presets yet")
        emptyLabel.font = Theme.label(12, weight: .regular)
        emptyLabel.textColor = Theme.textDim
        emptyLabel.numberOfLines = 0
        userRowsContainer.axis = .vertical
        userRowsContainer.alignment = .fill
        userRowsContainer.spacing = 8
        userRowsContainer.addArrangedSubview(emptyLabel)
        stack.addArrangedSubview(userRowsContainer)
        refreshUserPresetRows()

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

    private func addSectionHeader(_ text: String) {
        let l = UILabel()
        l.text = text
        l.font = Theme.label(12, weight: .semibold)
        l.textColor = Theme.textDim
        stack.addArrangedSubview(l)
    }

    // MARK: - Save section

    /// Only installs the name field + Save button when the current
    /// container actually supports saving (see `PresetStoring.
    /// supportsUserPresets`'s doc comment: "without offering a save button
    /// that cannot work"). Otherwise a short explanatory line takes its
    /// place — degrading, not silently omitting.
    private func installSaveSection() {
        guard store.supportsUserPresets else {
            let l = UILabel()
            l.text = NSLocalizedString(
                "presets.unsupportedHost",
                comment: "Shown when the current host does not support saving user presets")
            l.font = Theme.label(11, weight: .regular)
            l.textColor = Theme.textDim
            l.numberOfLines = 0
            stack.addArrangedSubview(l)
            return
        }

        saveRow.onSave = { [weak self] in self?.handleSaveTapped() }
        stack.addArrangedSubview(saveRow)

        feedbackLabel.font = Theme.label(11, weight: .regular)
        feedbackLabel.textColor = .systemRed
        feedbackLabel.numberOfLines = 0
        feedbackLabel.isHidden = true
        stack.addArrangedSubview(feedbackLabel)
    }

    private func handleSaveTapped() {
        let name = saveRow.nameField.text ?? ""
        let result = store.saveCurrentAsUserPreset(named: name)
        switch result {
        case .success:
            feedbackLabel.isHidden = true
            saveRow.nameField.text = ""
            saveRow.nameField.resignFirstResponder()
            refreshUserPresetRows()
        case .emptyName:
            showFeedback(NSLocalizedString("presets.error.emptyName", comment: "Shown when saving with a blank name"))
        case .duplicateName:
            showFeedback(NSLocalizedString(
                "presets.error.duplicateName", comment: "Shown when saving under a name that's already taken"))
        case .unsupported, .failed:
            showFeedback(NSLocalizedString(
                "presets.error.saveFailed", comment: "Shown when saving fails for any other reason"))
        }
        setNeedsLayout()
    }

    private func showFeedback(_ text: String) {
        feedbackLabel.text = text
        feedbackLabel.isHidden = false
    }

    // MARK: - User preset rows

    /// Rebuilds `userRowsContainer` from `store.savedUserPresets` — called
    /// once at init and again after every save/delete, so the list always
    /// reflects the store's current contents without this view needing any
    /// state of its own beyond what it just asked the store for.
    private func refreshUserPresetRows() {
        for row in userRows {
            userRowsContainer.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        userRows = []

        let saved = store.savedUserPresets
        emptyLabel.isHidden = !saved.isEmpty
        for preset in saved {
            let row = PresetUserRow(preset: preset, showsDelete: store.supportsUserPresets)
            row.onTap = { [weak self] in
                guard let self, let snapshot = self.store.snapshot(forUserPresetNamed: preset.name) else { return }
                self.onSelectUserPreset?(snapshot)
            }
            row.onDelete = { [weak self] in
                guard let self else { return }
                self.store.deleteUserPreset(named: preset.name)
                self.refreshUserPresetRows()
            }
            userRowsContainer.addArrangedSubview(row)
            userRows.append(row)
        }
        setNeedsLayout()
    }

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
        // fitting-size approach as `AboutView`/`MoreAppsView`/
        // `CharacterDropdownView`.
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

extension PresetsView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                            shouldReceive touch: UITouch) -> Bool {
        guard let touchView = touch.view else { return true }
        return !touchView.isDescendant(of: panel)
    }
}

/// The "save current as a new preset" row: a name field plus a Save button.
/// A dedicated manual-layout `UIView` (matching this app's established style
/// — see `PresetFactoryRow`/`PresetUserRow` below, and `CharacterDropdownRow`/
/// `MoreAppsRow` elsewhere) rather than a nested `UIStackView`, so it slots
/// into `PresetsView`'s own outer stack exactly like every other row.
private final class PresetSaveRow: UIView {
    let nameField = UITextField()
    private let saveButton = UIButton(type: .system)

    var onSave: (() -> Void)?

    static let height: CGFloat = 44
    private static let saveButtonWidth: CGFloat = 92

    override init(frame: CGRect) {
        super.init(frame: frame)

        nameField.placeholder = NSLocalizedString(
            "presets.namePlaceholder", comment: "Placeholder text in the new-preset name field")
        nameField.borderStyle = .roundedRect
        nameField.font = Theme.label(13, weight: .regular)
        nameField.textColor = Theme.textPrimary
        nameField.returnKeyType = .done
        nameField.clearButtonMode = .whileEditing
        nameField.delegate = self
        addSubview(nameField)

        var saveConfig = UIButton.Configuration.filled()
        saveConfig.title = NSLocalizedString(
            "presets.save", comment: "Button that saves the current patch as a new user preset")
        saveConfig.baseBackgroundColor = Theme.accent
        saveConfig.baseForegroundColor = Theme.background
        saveConfig.cornerStyle = .medium
        saveButton.configuration = saveConfig
        saveButton.titleLabel?.font = Theme.label(13, weight: .semibold)
        saveButton.titleLabel?.adjustsFontSizeToFitWidth = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        addSubview(saveButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 8
        let saveW = min(Self.saveButtonWidth, max(0, bounds.width * 0.4))
        nameField.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - saveW - gap), height: bounds.height)
        saveButton.frame = CGRect(x: bounds.width - saveW, y: 0, width: saveW, height: bounds.height)
    }

    @objc private func saveTapped() {
        nameField.resignFirstResponder()
        onSave?()
    }
}

extension PresetSaveRow: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveTapped()
        return true
    }
}

/// A factory preset row: plain name, tappable, 44pt. Deliberately no
/// checkmark/selected-state (unlike `CharacterDropdownRow`) — this overlay
/// doesn't track "the currently loaded preset" (only the character dropdown
/// does, and only because the character stays visible on screen the whole
/// time; a preset name doesn't), so there is nothing meaningful to mark as
/// current.
private final class PresetFactoryRow: UIControl {
    private let nameLabel = UILabel()
    var onTap: (() -> Void)?

    static let height: CGFloat = 44

    init(name: String) {
        super.init(frame: .zero)
        backgroundColor = Theme.panel
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = Theme.panelBorder.cgColor

        nameLabel.text = name
        nameLabel.font = Theme.label(15, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)

        isAccessibilityElement = true
        accessibilityLabel = name
        accessibilityTraits = .button

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 14
        nameLabel.frame = CGRect(x: pad, y: 0, width: max(0, bounds.width - pad * 2), height: bounds.height)
    }

    @objc private func tapped() { onTap?() }
}

/// A user preset row: the character it was saved with (rendered via
/// `CharacterView.thumbnail(of:size:)` — a single static draw, no live
/// display link; see that function's doc comment), its name, and — when the
/// store supports it — a delete button. Tapping the row (anywhere outside
/// the delete button) loads it; the delete button is its own nested
/// `UIControl` so tapping it never also triggers the row's own tap — UIKit
/// hit-tests each touch to exactly one control, whichever is frontmost at
/// that point, so the two never fire together.
private final class PresetUserRow: UIControl {
    private let thumbnail = UIImageView()
    private let nameLabel = UILabel()
    private let deleteButton = UIButton(type: .system)

    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    static let height: CGFloat = 56
    private static let thumbnailSize: CGFloat = 40
    private static let deleteButtonWidth: CGFloat = 44

    init(preset: SavedPreset, showsDelete: Bool) {
        super.init(frame: .zero)
        backgroundColor = Theme.panel
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = Theme.panelBorder.cgColor

        let character = CharacterRegistry.character(withID: preset.characterID)
        thumbnail.image = CharacterView.thumbnail(
            of: character, size: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize))
        thumbnail.contentMode = .scaleAspectFit
        thumbnail.isUserInteractionEnabled = false
        addSubview(thumbnail)

        nameLabel.text = preset.name
        nameLabel.font = Theme.label(14, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)

        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = Theme.textDim
        deleteButton.isHidden = !showsDelete
        // A plain `UIButton`'s `isAccessibilityElement` isn't reliably `true`
        // by default (it can depend on live window/hierarchy state) — set it
        // explicitly, same as every custom row/control elsewhere in this
        // app, so VoiceOver can always find this as its own element,
        // independent of the row's own `isAccessibilityElement`. Only when
        // actually shown: a hidden control has no business claiming to be an
        // accessible element either.
        deleteButton.isAccessibilityElement = showsDelete
        deleteButton.accessibilityLabel = showsDelete ? NSLocalizedString(
            "presets.delete.accessibility", comment: "Accessibility label for a user preset row's delete button") : nil
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)

        // A single accessible element for the row itself (load); the delete
        // button is separately accessible with its own label, mirroring how
        // `CharacterDropdownRow`/`MoreAppsRow` keep their labels
        // non-interactive (`isUserInteractionEnabled = false`) so VoiceOver
        // doesn't double-announce the same text.
        isAccessibilityElement = true
        accessibilityLabel = preset.name
        accessibilityTraits = .button

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad: CGFloat = 8
        let deleteW: CGFloat = deleteButton.isHidden ? 0 : Self.deleteButtonWidth
        thumbnail.frame = CGRect(x: pad, y: (bounds.height - Self.thumbnailSize) / 2,
                                  width: Self.thumbnailSize, height: Self.thumbnailSize)
        deleteButton.frame = CGRect(x: bounds.width - deleteW, y: 0, width: deleteW, height: bounds.height)
        let nameX = pad + Self.thumbnailSize + 10
        let nameW = max(0, bounds.width - nameX - deleteW - pad)
        nameLabel.frame = CGRect(x: nameX, y: 0, width: nameW, height: bounds.height)
    }

    @objc private func tapped() { onTap?() }
    @objc private func deleteTapped() { onDelete?() }
}
