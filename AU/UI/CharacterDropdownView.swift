import UIKit

/// Dismissible overlay listing the WHOLE character roster as plain text
/// rows: every built-in character, then upstream's six factory presets
/// (`FactoryPresetCharacter.all` — brought back into this list wearing a
/// borrowed face, see that type's doc comment for why), then every one of
/// the user's own saved entries — one list, not three. This is where
/// "characters" and "presets" actually merge (see the task: "Why are the
/// presets and characters different? It should be one list" / "I want only
/// the characters as presets"). Saving the current patch and deleting a
/// saved entry live here too — see `installSaveSection`/
/// `CharacterDropdownRow`'s delete button — rather than in a second,
/// separate overlay: there is now exactly one picker and exactly one way
/// in, matching the task's decision 1.
///
/// Modelled on `AboutView`/`MoreAppsView`: scrim, centred panel,
/// tap-outside-to-dismiss, and it scrolls when the content doesn't fit — an
/// AUv3 host can hand this view an extremely short rect (the AUM strip,
/// 375×180), and the roster — now built-ins, the six factory presets, plus
/// an open-ended number of saved entries — is expected to keep growing.
///
/// "Save current…" sits right after the built-in rows and the factory
/// section, BEFORE the "Saved" section — not at the very end of the whole
/// scrollable list, after every saved entry. Two things were tried and
/// rejected first: (1) at the very bottom, after the (open-ended) saved
/// list — with even a handful of saved entries already, that pushed Save
/// below the fold at a generous 700pt height, and the scroll distance to
/// reach it only grows every time the user saves another one, the opposite
/// of what a frequently-used control should do; (2) pinned above the close
/// button, outside the scrollable list entirely, so it's always on screen
/// with zero scrolling — but at the AUM strip (375×180) the fixed chrome
/// (padding, Save's own controls, the gaps, Close) alone consumes nearly the
/// whole 140pt the panel actually has, leaving no room at all for the row
/// list — the dropdown's actual primary job, choosing a character — to show
/// anything. Sitting right after the fixed built-in + factory rows is the
/// middle ground: reachable after scrolling a small, CONSTANT distance
/// regardless of how many entries have been saved (the built-in and factory
/// counts never change), while staying part of the same single scrollable
/// flow as everything else — no separate space-rationing logic, no risk of
/// starving the list — exactly the proven, already-tested scrolling
/// behaviour `AboutView`/`MoreAppsView`/the original built-ins-only version
/// of this view already rely on at the AUM strip.
final class CharacterDropdownView: UIView {

    /// Fired when the user taps outside the panel or the close button,
    /// without picking anything.
    var onClose: (() -> Void)?
    /// Fired when the user taps a row — built-in or saved. `PluginView`
    /// applies the selection via `CharacterView.select(_:)`, which loads its
    /// sound too (a saved entry's own params via `Character.savedParameters`,
    /// a built-in's voice via `CharacterVoiceTable` — see
    /// `AudioUnitViewController`/`RootViewController`'s `onCharacterSelected`
    /// wiring) and dismisses this overlay.
    var onSelect: ((Character) -> Void)?

    /// Where saved entries live, and where "Save current…"/delete act. `nil`
    /// only when a caller (some tests construct a bare `PluginView` without
    /// wiring one) has no store to hand over — the dropdown still opens and
    /// lists the built-in roster; it just offers no saved entries and no
    /// save/delete UI, degrading the same way `PresetStoring.
    /// supportsUserPresets == false` already does for an AUv3 host that
    /// declines the feature.
    private let store: PresetStoring?
    private let current: Character

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    /// Built once, never refreshed: the six built-in rows never change
    /// (unlike the saved section — see `savedSection`).
    private let builtInRows = UIStackView()
    /// Built once, never refreshed, exactly like `builtInRows`: the "Factory"
    /// section header + one row per `FactoryPresetCharacter.all` entry.
    /// Upstream's six factory presets are fixed data
    /// (`AU/FactoryPresets.swift`), not tied to any `PresetStoring` — unlike
    /// `savedSection` below, this section shows regardless of whether a
    /// store was even handed to this view.
    private let factorySection = UIStackView()
    /// Rebuilt after every save/delete: the "Saved" section header + one
    /// row per user entry. Kept as its own container (rather than mixed
    /// into `builtInRows`) so a refresh never has to touch — or risk
    /// reordering — the built-in rows or the save controls that sit between
    /// them and this section.
    private let savedSection = UIStackView()
    private let closeButton = UIButton(type: .system)

    private let saveRow = CharacterSaveRow()
    private let feedbackLabel = UILabel()

    private static let panelPadding: CGFloat = 16
    private static let closeButtonHeight: CGFloat = 40
    private static let closeButtonGap: CGFloat = 12
    private static let maxPanelWidth: CGFloat = 320

    /// The merged, ordered roster this dropdown lists: every built-in
    /// character (`CharacterRegistry.all`), then upstream's six factory
    /// presets (`FactoryPresetCharacter.all` — always present, independent
    /// of `store`), then every one of `store`'s saved user entries
    /// (`UserCharacter.all(from:)`) — see the task's decision 3, "built-ins
    /// first, then factory presets, then user entries." The count is always
    /// derived from these three sources, never hardcoded. Exposed as a
    /// `static` so tests can assert against exactly what a live instance
    /// will show without needing a laid-out view.
    static func characters(from store: PresetStoring?) -> [Character] {
        let builtinsAndFactory: [Character] = CharacterRegistry.all + FactoryPresetCharacter.all
        guard let store else { return builtinsAndFactory }
        return builtinsAndFactory + UserCharacter.all(from: store)
    }

    init(frame: CGRect, current: Character, store: PresetStoring?) {
        self.current = current
        self.store = store
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

        // Built once — the six built-in rows never change — and added to
        // `stack` here, BEFORE the save section and the saved section, so
        // their position in the scrollable flow is fixed for the view's
        // whole lifetime; `refreshSavedSection()` never touches this.
        builtInRows.axis = .vertical
        builtInRows.alignment = .fill
        builtInRows.spacing = 8
        stack.addArrangedSubview(builtInRows)
        for character in CharacterRegistry.all {
            let row = CharacterDropdownRow(character: character, isCurrent: character.id == current.id,
                                            kind: .builtIn, showsDelete: false)
            row.onTap = { [weak self] in self?.onSelect?(character) }
            builtInRows.addArrangedSubview(row)
        }

        // Factory presets — built once, right after the built-ins, exactly
        // like `builtInRows` (see `factorySection`'s doc comment): fixed
        // data, never refreshed, never deletable. A "Factory" header, mirroring
        // "Saved"'s header below, plus a per-row badge (see
        // `CharacterDropdownRow`) so the group still reads as distinct from
        // both built-ins and user entries even after scrolling the header
        // out of view.
        factorySection.axis = .vertical
        factorySection.alignment = .fill
        factorySection.spacing = 8
        stack.addArrangedSubview(factorySection)
        let factoryHeader = UILabel()
        factoryHeader.text = NSLocalizedString("characterPicker.factory", comment: "Section header above upstream's factory presets")
        factoryHeader.font = Theme.label(12, weight: .semibold)
        factoryHeader.textColor = Theme.textDim
        factorySection.addArrangedSubview(factoryHeader)
        for factoryCharacter in FactoryPresetCharacter.all {
            let row = CharacterDropdownRow(character: factoryCharacter, isCurrent: factoryCharacter.id == current.id,
                                            kind: .factory, showsDelete: false)
            row.onTap = { [weak self] in self?.onSelect?(factoryCharacter) }
            factorySection.addArrangedSubview(row)
        }

        // Save current… — see the class doc comment for why this sits here
        // (right after the fixed built-in + factory rows) rather than at the
        // very bottom of the whole list or pinned outside it entirely.
        installSaveSection()

        savedSection.axis = .vertical
        savedSection.alignment = .fill
        savedSection.spacing = 8
        stack.addArrangedSubview(savedSection)
        refreshSavedSection()

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

    // MARK: - Saved section

    /// Rebuilds `savedSection` (the "Saved" header + one row per user
    /// entry) from whatever `store` currently holds — called once at init
    /// and again after every save/delete, so the list always reflects the
    /// store's current contents without this view needing any state of its
    /// own beyond what it just asked for. Never touches `builtInRows` or
    /// the save controls above it. User rows carry a delete button only
    /// when `store.supportsUserPresets` (mirroring `PresetStoring.
    /// supportsUserPresets`'s own "don't offer a control that cannot work"
    /// contract).
    private func refreshSavedSection() {
        for row in savedSection.arrangedSubviews {
            savedSection.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        let userCharacters = store.map { UserCharacter.all(from: $0) } ?? []
        guard !userCharacters.isEmpty else {
            setNeedsLayout()
            return
        }

        // A section header, plus a small badge on every row below it (see
        // `CharacterDropdownRow`) — belt and suspenders so a saved entry
        // reads as visually distinct from a built-in even after scrolling
        // the header itself out of view at a short host rect.
        let header = UILabel()
        header.text = NSLocalizedString("characterPicker.saved", comment: "Section header above the user's saved characters")
        header.font = Theme.label(12, weight: .semibold)
        header.textColor = Theme.textDim
        savedSection.addArrangedSubview(header)

        let showsDelete = store?.supportsUserPresets ?? false
        for user in userCharacters {
            let row = CharacterDropdownRow(character: user, isCurrent: user.id == current.id,
                                            kind: .user, showsDelete: showsDelete)
            row.onTap = { [weak self] in self?.onSelect?(user) }
            row.onDelete = { [weak self] in
                guard let self else { return }
                self.store?.deleteUserPreset(named: user.name)
                self.refreshSavedSection()
            }
            savedSection.addArrangedSubview(row)
        }
        setNeedsLayout()
    }

    // MARK: - Save section

    /// Only installs the name field + Save button when there's a store AND
    /// it actually supports saving — otherwise a short explanatory line
    /// takes its place, matching `PresetStoring.supportsUserPresets`'s own
    /// doc comment ("without offering a save button that cannot work").
    /// Added directly to `stack`, right after `builtInRows`/`factorySection`
    /// — see the class doc comment for why here rather than at the end of
    /// the whole list.
    private func installSaveSection() {
        guard let store, store.supportsUserPresets else {
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

        saveRow.onSave = { [weak self] in self?.handleSaveTapped(store: store) }
        stack.addArrangedSubview(saveRow)

        feedbackLabel.font = Theme.label(11, weight: .regular)
        feedbackLabel.textColor = .systemRed
        feedbackLabel.numberOfLines = 0
        feedbackLabel.isHidden = true
        stack.addArrangedSubview(feedbackLabel)
    }

    private func handleSaveTapped(store: PresetStoring) {
        let name = saveRow.nameField.text ?? ""
        let result = store.saveCurrentAsUserPreset(named: name)
        switch result {
        case .success:
            feedbackLabel.isHidden = true
            saveRow.nameField.text = ""
            saveRow.nameField.resignFirstResponder()
            refreshSavedSection()
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
        // fitting-size approach as `AboutView`/`MoreAppsView`. Everything
        // (built-in rows, the save controls, the saved section) lives in
        // this one `stack`/`scrollView` — see the class doc comment for why
        // there's no separate pinned region for the save controls.
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

/// One tappable roster row: the character's name, a small badge identifying
/// which of the three groups it belongs to (see `Kind` — nothing for a
/// built-in, a star for a factory preset, a bookmark for a saved user
/// entry), a checkmark for whichever row is currently selected, and — for a
/// user entry, when the store supports it — a trailing delete button.
/// `UIControl`, not a plain view with a gesture recognizer, mirroring
/// `MoreAppsRow` — gets touch-down/up highlighting and the standard
/// `.button` accessibility affordances for free. Fixed at the HIG's 44pt
/// minimum row height, per the task.
private final class CharacterDropdownRow: UIControl {

    /// Which roster group a row belongs to — drives its badge (see `badge`
    /// below). Deliberately NOT the same thing as `showsDelete`: a factory
    /// preset gets its own distinct badge but never a delete button (it
    /// can't be deleted), while a user entry's delete button depends
    /// separately on `PresetStoring.supportsUserPresets`.
    enum Kind { case builtIn, factory, user }

    private let nameLabel = UILabel()
    private let badge = UIImageView()
    private let checkmark = UIImageView()
    private let deleteButton = UIButton(type: .system)

    var onTap: (() -> Void)?
    /// Only ever set (by `CharacterDropdownView.refreshSavedSection`) when
    /// this row was built with `showsDelete: true`.
    var onDelete: (() -> Void)?

    static let height: CGFloat = 44
    private static let checkmarkSize: CGFloat = 18
    private static let badgeSize: CGFloat = 14
    private static let deleteButtonWidth: CGFloat = 40

    /// SF Symbol per group — `nil` for a built-in, which gets no badge at
    /// all (it's the "default" look every row starts from).
    private static func badgeImageName(for kind: Kind) -> String? {
        switch kind {
        case .builtIn: return nil
        case .factory: return "star.fill"
        case .user: return "bookmark.fill"
        }
    }

    init(character: Character, isCurrent: Bool, kind: Kind, showsDelete: Bool) {
        super.init(frame: .zero)
        backgroundColor = isCurrent ? Theme.panelBorder : Theme.panel
        layer.cornerRadius = 8
        layer.borderWidth = isCurrent ? 2 : 1
        layer.borderColor = (isCurrent ? Theme.accent : Theme.panelBorder).cgColor

        // The badge (plus each group's own section header above its first
        // row — see `CharacterDropdownView.init`/`refreshSavedSection`) is
        // what makes a factory preset or a saved entry visually
        // distinguishable from a built-in, AND from each other, even when
        // the header itself has scrolled out of view at a short host rect
        // (the AUM strip) — a per-row cue that survives scrolling, not just
        // a one-time divider.
        let badgeImageName = Self.badgeImageName(for: kind)
        badge.image = badgeImageName.flatMap { UIImage(systemName: $0) }
        badge.tintColor = Theme.textDim
        badge.isHidden = badgeImageName == nil
        badge.contentMode = .scaleAspectFit
        badge.isUserInteractionEnabled = false
        badge.isAccessibilityElement = false
        addSubview(badge)

        nameLabel.text = character.displayName
        nameLabel.font = Theme.label(15, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isUserInteractionEnabled = false
        // The row itself is the single accessible surface for this whole
        // control (see `isAccessibilityElement = true`/`accessibilityLabel`
        // below) — silencing this decorative label explicitly is what keeps
        // VoiceOver (and any code walking the accessibility tree, like
        // `CharacterDropdownViewTests.rowLabels`) from encountering the same
        // name twice per row. `UILabel`'s own default `isAccessibilityElement`
        // is `true` whenever it has text, independent of
        // `isUserInteractionEnabled` — unlike `UIImageView` just above, this
        // one needs the explicit override.
        nameLabel.isAccessibilityElement = false
        addSubview(nameLabel)

        checkmark.image = UIImage(systemName: "checkmark")
        checkmark.tintColor = Theme.accent
        checkmark.isHidden = !isCurrent
        checkmark.isUserInteractionEnabled = false
        checkmark.isAccessibilityElement = false
        addSubview(checkmark)

        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.tintColor = Theme.textDim
        deleteButton.isHidden = !showsDelete
        // A plain `UIButton`'s `isAccessibilityElement` isn't reliably `true`
        // by default — set it explicitly, same as every custom row/control
        // elsewhere in this app, so VoiceOver can always find this as its
        // own element. Only when actually shown: a hidden control has no
        // business claiming to be an accessible element either.
        deleteButton.isAccessibilityElement = showsDelete
        deleteButton.accessibilityLabel = showsDelete ? NSLocalizedString(
            "presets.delete.accessibility", comment: "Accessibility label for a saved character row's delete button") : nil
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)

        // A single accessible element for the row itself (select); the
        // delete button is separately accessible with its own label — see
        // `PresetUserRow`'s identical reasoning in the design this replaces.
        // `.selected` makes VoiceOver announce "selected" for whichever
        // entry is current, the accessible equivalent of the checkmark.
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
        let deleteW: CGFloat = deleteButton.isHidden ? 0 : Self.deleteButtonWidth
        deleteButton.frame = CGRect(x: bounds.width - deleteW, y: 0, width: deleteW, height: bounds.height)

        let checkmarkW: CGFloat = checkmark.isHidden ? 0 : Self.checkmarkSize
        checkmark.frame = CGRect(x: bounds.width - deleteW - checkmarkW - (deleteW > 0 ? 4 : pad),
                                  y: (bounds.height - Self.checkmarkSize) / 2,
                                  width: Self.checkmarkSize, height: Self.checkmarkSize)

        let badgeW: CGFloat = badge.isHidden ? 0 : Self.badgeSize
        badge.frame = CGRect(x: pad, y: (bounds.height - Self.badgeSize) / 2,
                              width: badgeW, height: Self.badgeSize)

        let nameX = pad + (badgeW > 0 ? badgeW + 6 : 0)
        let trailingReserved = (bounds.width - checkmark.frame.minX) + 4
        let nameW = max(0, bounds.width - nameX - trailingReserved)
        nameLabel.frame = CGRect(x: nameX, y: 0, width: nameW, height: bounds.height)
    }

    @objc private func tapped() { onTap?() }
    @objc private func deleteTapped() { onDelete?() }
}

/// The "save current as a new character" row: a name field plus a Save
/// button — ported verbatim (behaviour and layout) from the deleted
/// `PresetsView.PresetSaveRow`, just renamed to live in this file. A
/// dedicated manual-layout `UIView` (matching this app's established style)
/// rather than a nested `UIStackView`, so it slots into
/// `CharacterDropdownView`'s own outer stack exactly like every other row.
private final class CharacterSaveRow: UIView {
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

extension CharacterSaveRow: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveTapped()
        return true
    }
}
