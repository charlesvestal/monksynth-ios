import XCTest
import UIKit
import AVFoundation
@testable import MonkSynth

/// Covers `CharacterDropdownView` — the single overlay tapping
/// `CharacterSelector`'s name opens, listing the built-in roster AND the
/// user's own saved entries as one merged list (see the task: "Why are the
/// presets and characters different? It should be one list"), plus saving
/// the current patch and deleting a saved entry — the deleted `PresetsView`'s
/// job, now folded in here — and `PluginView`'s wiring of it (opening from
/// the selector, applying and dismissing on a row tap). `CharacterDropdownRow`
/// is private to `CharacterDropdownView.swift`, so these tests reach it the
/// same way the old suite reached `CharacterCell`: via public
/// `UIView`/`UIControl` APIs (`subviews`, `isAccessibilityElement`,
/// `accessibilityLabel`, `sendActions(for:)`) rather than the concrete type.
final class CharacterDropdownViewTests: XCTestCase {

    // MARK: - Fake store

    /// In-memory `PresetStoring` fixture — mirrors the fake the deleted
    /// `PresetsViewTests` used, so this file never touches
    /// `MonkSynthAU`'s real `AUAudioUnit`-backed storage nor
    /// `StandalonePresetStore`'s `UserDefaults` (both covered separately).
    private final class FakePresetStore: PresetStoring {
        var supportsUserPresets: Bool
        private(set) var savedUserPresets: [SavedPreset] = []
        private var snapshots: [String: PresetSnapshot] = [:]

        init(supportsUserPresets: Bool = true) { self.supportsUserPresets = supportsUserPresets }

        func snapshot(forUserPresetNamed name: String) -> PresetSnapshot? { snapshots[name] }

        @discardableResult
        func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .emptyName }
            guard !savedUserPresets.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
            else { return .duplicateName }
            savedUserPresets.append(SavedPreset(name: trimmed, characterID: "fish"))
            snapshots[trimmed] = PresetSnapshot(params: Param.allCases.map(\.defaultValue), characterID: "fish")
            return .success
        }

        func deleteUserPreset(named name: String) {
            savedUserPresets.removeAll { $0.name == name }
            snapshots[name] = nil
        }

        /// Test-only seam for seeding rows directly, bypassing `save`'s
        /// hardcoded "fish" character — lets tests exercise a specific
        /// character face (and specific params) per row.
        func seed(_ preset: SavedPreset, params: [AUValue] = Param.allCases.map(\.defaultValue)) {
            savedUserPresets.append(preset)
            snapshots[preset.name] = PresetSnapshot(params: params, characterID: preset.characterID)
        }
    }

    // MARK: - Helpers

    /// Depth-first walk collecting every accessible element's label —
    /// standing in for "one row per character" without needing to name the
    /// private `CharacterDropdownRow` type. This also picks up the panel's
    /// own chrome (the title, the Close button, and — with no store — the
    /// "can't save presets here" explanatory line all default to
    /// accessible, being plain `UILabel`/`UIButton`s with non-empty text),
    /// which is real UIKit behaviour but not what a COUNT of "one row per
    /// character" means to test — see `rowLabels(in:)` below, which is what
    /// every count-sensitive test actually wants.
    private func accessibleLabels(in view: UIView) -> [String] {
        var out: [String] = []
        if view.isAccessibilityElement, let label = view.accessibilityLabel {
            out.append(label)
        }
        for sub in view.subviews { out += accessibleLabels(in: sub) }
        return out
    }

    /// `accessibleLabels`, narrowed to just the roster ROW labels — every
    /// built-in, factory, and user-entry display name that's actually
    /// present in `dropdown`'s own merged list (`CharacterDropdownView.
    /// characters(from:)`), which is exactly what a "one row per character"
    /// count means. Filtering by an ALLOWLIST of real roster names (rather
    /// than a blocklist of the panel's chrome strings — the title, Close,
    /// the delete button, the unsupported-host line) is what makes this
    /// robust to the panel growing more explanatory text over time, and
    /// avoids hardcoding those strings a second time in this file.
    private func rowLabels(in dropdown: CharacterDropdownView, store: PresetStoring?) -> [String] {
        let rosterNames = Set(CharacterDropdownView.characters(from: store).map(\.displayName))
        return accessibleLabels(in: dropdown).filter { rosterNames.contains($0) }
    }

    /// Finds the (single) accessible descendant labelled `name` — a row,
    /// identified the same way VoiceOver would identify it.
    private func accessibleView(labeled name: String, in view: UIView) -> UIView? {
        if view.isAccessibilityElement, view.accessibilityLabel == name { return view }
        for sub in view.subviews {
            if let found = accessibleView(labeled: name, in: sub) { return found }
        }
        return nil
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView { return sv }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    private func firstTextField(in view: UIView) -> UITextField? {
        if let tf = view as? UITextField { return tf }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }

    private func makeDropdown(current: Character = CharacterRegistry.defaultCharacter,
                               store: PresetStoring? = nil,
                               size: CGSize = CGSize(width: 390, height: 700)) -> CharacterDropdownView {
        let dropdown = CharacterDropdownView(frame: CGRect(origin: .zero, size: size), current: current, store: store)
        dropdown.setNeedsLayout()
        dropdown.layoutIfNeeded()
        return dropdown
    }

    /// Drives a save exactly the way pressing Return in the name field
    /// would, mirroring the deleted `PresetsViewTests`'s identical helper.
    private func triggerSave(in view: CharacterDropdownView) {
        guard let field = firstTextField(in: view) else {
            XCTFail("no name field found — is the store's supportsUserPresets true?")
            return
        }
        _ = field.delegate?.textFieldShouldReturn?(field)
    }

    // MARK: - Lists every registered character (no store)

    /// The count is derived from `CharacterRegistry.all` PLUS
    /// `FactoryPresetCharacter.all` — both fixed, but neither hardcoded here
    /// as a literal number — since factory presets show regardless of
    /// whether a store was even wired. No store wired: this is the "bare
    /// `PluginView`, nothing saved yet" case.
    func testDropdownListsExactlyOneRowPerRegisteredCharacterWithNoStore() {
        let dropdown = makeDropdown()
        let labels = rowLabels(in: dropdown, store: nil)
        let expected = CharacterRegistry.all.count + FactoryPresetCharacter.all.count
        XCTAssertEqual(labels.count, expected,
            "expected one accessible row per registry entry plus every factory preset, got \(labels.count) for \(expected)")
        let expectedNames = Set(CharacterRegistry.all.map(\.displayName) + FactoryPresetCharacter.all.map(\.displayName))
        XCTAssertEqual(Set(labels), expectedNames)
    }

    // MARK: - Merged list: built-ins, then factory presets, then user entries

    /// The dropdown's list is built-ins, then factory presets, then user
    /// entries, and its count is derived from the registry plus the factory
    /// table plus the store — never hardcoded. This is the actual "one
    /// list" the task asks for.
    func testDropdownListsBuiltInsThenFactoryThenUserEntriesFromTheStore() {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Sunrise", characterID: "unicorn"))
        store.seed(SavedPreset(name: "Bubbles", characterID: "fish"))
        let dropdown = makeDropdown(store: store)

        let labels = rowLabels(in: dropdown, store: store)
        let expectedCount = CharacterDropdownView.characters(from: store).count
        XCTAssertEqual(expectedCount, CharacterRegistry.all.count + FactoryPresetCharacter.all.count + 2)
        XCTAssertEqual(labels.count, expectedCount,
            "row count must equal the registry plus the factory table plus the store's saved entries, not a hardcoded number")

        let expectedNames = Set(CharacterRegistry.all.map(\.displayName)
            + FactoryPresetCharacter.all.map(\.displayName) + ["Sunrise", "Bubbles"])
        XCTAssertEqual(Set(labels), expectedNames)
    }

    /// Built-ins always come first, in registry order, then every factory
    /// preset in `kFactoryPresets`' own order, with user entries last —
    /// proven by walking the merged list `CharacterDropdownView` itself
    /// derives, matching the task's decision 3.
    func testMergedListPutsBuiltInsBeforeFactoryBeforeUserEntries() {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Zzz First Alphabetically", characterID: "monk"))

        let merged = CharacterDropdownView.characters(from: store)
        let builtinCount = CharacterRegistry.all.count
        let factoryCount = FactoryPresetCharacter.all.count

        XCTAssertEqual(Array(merged.prefix(builtinCount)).map(\.id),
                        CharacterRegistry.all.map(\.id))
        XCTAssertEqual(Array(merged[builtinCount..<(builtinCount + factoryCount)]).map(\.id),
                        FactoryPresetCharacter.all.map(\.id),
                        "factory presets must follow the built-ins directly, in kFactoryPresets order")
        XCTAssertEqual(merged.last?.displayName, "Zzz First Alphabetically",
            "a user entry must never sort ahead of the built-in roster or the factory presets, even alphabetically")
    }

    // MARK: - Rows meet the 44pt HIG row height

    func testEveryRowIs44PointsTall() {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Saved One", characterID: "cow"))
        let dropdown = makeDropdown(store: store)
        for character in CharacterDropdownView.characters(from: store) {
            let row = accessibleView(labeled: character.displayName, in: dropdown)
            XCTAssertEqual(row?.bounds.height ?? -1, 44, accuracy: 0.5,
                "\(character.id)'s row must be 44pt tall")
        }
    }

    // MARK: - Current character indicated

    func testCurrentCharacterRowIsMarkedSelectedOthersAreNot() throws {
        let current = CharacterRegistry.all[1]
        let dropdown = makeDropdown(current: current)

        let currentRow = try XCTUnwrap(accessibleView(labeled: current.displayName, in: dropdown))
        XCTAssertTrue(currentRow.accessibilityTraits.contains(.selected))

        for other in CharacterRegistry.all where other.id != current.id {
            let row = try XCTUnwrap(accessibleView(labeled: other.displayName, in: dropdown))
            XCTAssertFalse(row.accessibilityTraits.contains(.selected),
                "\(other.id) must not be marked selected while \(current.id) is current")
        }
    }

    /// A saved user entry can be the current character too — not just a
    /// built-in — and gets the exact same "selected" treatment.
    func testCurrentUserEntryRowIsMarkedSelected() throws {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "My Patch", characterID: "girl"))
        let current = try XCTUnwrap(UserCharacter.all(from: store).first)
        let dropdown = makeDropdown(current: current, store: store)

        let row = try XCTUnwrap(accessibleView(labeled: "My Patch", in: dropdown))
        XCTAssertTrue(row.accessibilityTraits.contains(.selected))

        for builtin in CharacterRegistry.all {
            let builtinRow = try XCTUnwrap(accessibleView(labeled: builtin.displayName, in: dropdown))
            XCTAssertFalse(builtinRow.accessibilityTraits.contains(.selected))
        }
    }

    // MARK: - Selecting a row

    func testTappingARowFiresOnSelectWithThatCharacterAndNoOthers() throws {
        let dropdown = makeDropdown(current: CharacterRegistry.defaultCharacter)
        let target = CharacterRegistry.all.last!   // deliberately not the current one

        var selections: [String] = []
        dropdown.onSelect = { selections.append($0.id) }

        let row = try XCTUnwrap(accessibleView(labeled: target.displayName, in: dropdown) as? UIControl)
        row.sendActions(for: .touchUpInside)

        XCTAssertEqual(selections, [target.id])
    }

    /// Selecting a SAVED entry's row fires `onSelect` with a real
    /// `UserCharacter`, carrying its own saved parameters — not merely its
    /// name — so the owner can restore the saved sound, not the face's
    /// built-in voice (task decision 5).
    func testTappingAUserEntryRowFiresOnSelectWithItsSavedParameters() throws {
        let store = FakePresetStore()
        var params = Param.allCases.map(\.defaultValue)
        params[Int(Param.headSize.rawValue)] = 0.42
        store.seed(SavedPreset(name: "Custom", characterID: "cow"), params: params)
        let dropdown = makeDropdown(store: store)

        var selected: Character?
        dropdown.onSelect = { selected = $0 }

        let row = try XCTUnwrap(accessibleView(labeled: "Custom", in: dropdown) as? UIControl)
        row.sendActions(for: .touchUpInside)

        let user = try XCTUnwrap(selected as? UserCharacter)
        XCTAssertEqual(user.name, "Custom")
        XCTAssertEqual(user.faceID, "cow")
        XCTAssertEqual(user.savedParameters?[.headSize], 0.42)
    }

    // MARK: - Dismissal

    func testBackdropTapFiresOnCloseWithoutSelectingAnything() {
        let dropdown = makeDropdown()
        var closedCount = 0
        dropdown.onClose = { closedCount += 1 }
        var selectedCount = 0
        dropdown.onSelect = { _ in selectedCount += 1 }

        dropdown.perform(Selector(("backdropTapped")))

        XCTAssertEqual(closedCount, 1)
        XCTAssertEqual(selectedCount, 0, "tapping outside must not apply any selection")
    }

    // MARK: - Scrolls at short host rects

    /// An AUv3 host can hand this view an extremely short rect (same
    /// concern `AboutView`/`MoreAppsView` already document), and the roster
    /// is expected to keep growing — so the content must actually exceed
    /// the visible area at a short size, proving there is something real to
    /// scroll rather than merely a scroll view that happens to never need
    /// to move. This is exactly the failure mode the old art grid had at
    /// AUM-strip sizes ("a clipped sliver of one row plus a Close button");
    /// a plain list of 44pt rows — now with user entries and the save
    /// section besides — must scroll cleanly here instead.
    func testContentExceedsVisibleAreaAtAVeryShortHostRect() throws {
        let store = FakePresetStore()
        for i in 0..<5 { store.seed(SavedPreset(name: "Preset \(i)", characterID: "monk")) }
        let dropdown = makeDropdown(store: store, size: CGSize(width: 375, height: 180))
        let scrollView = try XCTUnwrap(firstScrollView(in: dropdown))
        XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height,
            "at a very short host rect the dropdown's content must exceed the visible area")
    }

    // MARK: - Saving

    func testSavingValidNameAddsItToTheListAsAUserEntry() throws {
        let store = FakePresetStore()
        let dropdown = makeDropdown(store: store)
        let field = try XCTUnwrap(firstTextField(in: dropdown))

        field.text = "Brand New"
        triggerSave(in: dropdown)

        XCTAssertEqual(store.savedUserPresets.map(\.name), ["Brand New"])
        XCTAssertEqual(field.text, "")
        XCTAssertTrue(accessibleLabels(in: dropdown).contains("Brand New"),
            "a freshly-saved entry must appear in the dropdown's own list without needing to reopen it")
    }

    func testSavingWithEmptyNameCreatesNothing() throws {
        let store = FakePresetStore()
        let dropdown = makeDropdown(store: store)
        let field = try XCTUnwrap(firstTextField(in: dropdown))

        field.text = "   "
        triggerSave(in: dropdown)

        XCTAssertTrue(store.savedUserPresets.isEmpty)
    }

    func testSavingWithDuplicateNameCreatesNothingNew() throws {
        let store = FakePresetStore()
        let dropdown = makeDropdown(store: store)
        let field = try XCTUnwrap(firstTextField(in: dropdown))

        field.text = "Same Name"
        triggerSave(in: dropdown)
        field.text = "Same Name"
        triggerSave(in: dropdown)

        XCTAssertEqual(store.savedUserPresets.count, 1)
    }

    /// No store at all (some tests construct a bare `PluginView`) must not
    /// offer save UI that cannot work.
    func testNoStoreOffersNoSaveUI() {
        let dropdown = makeDropdown(store: nil)
        XCTAssertNil(firstTextField(in: dropdown))
    }

    /// A host that declines user presets (`supportsUserPresets == false`)
    /// degrades the same way — no save UI offered.
    func testUnsupportedStoreOffersNoSaveUI() {
        let store = FakePresetStore(supportsUserPresets: false)
        let dropdown = makeDropdown(store: store)
        XCTAssertNil(firstTextField(in: dropdown))
    }

    // MARK: - Deleting: user entries only

    func testDeletingAUserEntryRemovesItFromTheList() throws {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Temp", characterID: "cow"))
        let dropdown = makeDropdown(store: store)
        XCTAssertTrue(accessibleLabels(in: dropdown).contains("Temp"))

        let deleteButton = try XCTUnwrap(accessibleView(
            labeled: NSLocalizedString("presets.delete.accessibility", comment: ""), in: dropdown) as? UIControl)
        deleteButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(store.savedUserPresets.isEmpty)
        XCTAssertFalse(accessibleLabels(in: dropdown).contains("Temp"))
    }

    /// Built-in characters can never be deleted — no delete control exists
    /// on their rows at all, regardless of how many user entries exist
    /// alongside them.
    func testBuiltInCharactersOfferNoDeleteControl() {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Some Save", characterID: "monk"))
        let dropdown = makeDropdown(store: store)

        // Exactly one delete control exists in the whole panel — the single
        // user entry's — never one per built-in row.
        let deleteLabel = NSLocalizedString("presets.delete.accessibility", comment: "")
        func countDeleteControls(in view: UIView) -> Int {
            var count = view.isAccessibilityElement && view.accessibilityLabel == deleteLabel ? 1 : 0
            for sub in view.subviews { count += countDeleteControls(in: sub) }
            return count
        }
        XCTAssertEqual(countDeleteControls(in: dropdown), 1)
    }

    /// When the store doesn't support user presets, even a saved entry's
    /// row offers no delete control — mirrors `PresetStoring.
    /// supportsUserPresets`'s "don't offer a control that cannot work"
    /// contract.
    func testUnsupportedStoreOffersNoDeleteControlEvenForExistingEntries() {
        let store = FakePresetStore(supportsUserPresets: false)
        store.seed(SavedPreset(name: "Read Only", characterID: "monk"))
        let dropdown = makeDropdown(store: store)

        XCTAssertNil(accessibleView(
            labeled: NSLocalizedString("presets.delete.accessibility", comment: ""), in: dropdown))
        XCTAssertTrue(accessibleLabels(in: dropdown).contains("Read Only"), "the row itself still lists, read-only")
    }

    // MARK: - Factory presets appear in the in-app list, each with a face

    /// Upstream's six factory presets stay available to HOSTS through
    /// `MonkSynthAU.factoryPresets`/`currentPreset` (see `PresetTests`), AND
    /// now appear in this app's own picker too, each wearing a face —
    /// reversing the earlier "factory presets have no face so they're
    /// dropped" decision (see the task).
    func testAllSixFactoryPresetNamesAppearInTheDropdownEachWithANonNilFace() {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Something", characterID: "monk"))
        let dropdown = makeDropdown(store: store)

        let labels = Set(accessibleLabels(in: dropdown))
        for preset in kFactoryPresets {
            XCTAssertTrue(labels.contains(preset.name), "factory preset \"\(preset.name)\" is missing from the in-app list")
        }
        for character in FactoryPresetCharacter.all {
            XCTAssertFalse(character.faceID.isEmpty, "\(character.displayName) has an empty faceID")
        }
    }

    /// Selecting a factory preset's row applies ITS OWN parameters, never
    /// the borrowed face's built-in voice — the same regression
    /// `testTappingAUserEntryRowFiresOnSelectWithItsSavedParameters` already
    /// guards for saved user entries, now proven for factory presets too.
    func testTappingAFactoryPresetRowFiresOnSelectWithItsOwnSavedParameters() throws {
        let dropdown = makeDropdown()
        let target = try XCTUnwrap(FactoryPresetCharacter.all.first(where: { $0.displayName == "Monastary" }))

        var selected: Character?
        dropdown.onSelect = { selected = $0 }

        let row = try XCTUnwrap(accessibleView(labeled: "Monastary", in: dropdown) as? UIControl)
        row.sendActions(for: .touchUpInside)

        let preset = try XCTUnwrap(selected as? FactoryPresetCharacter)
        XCTAssertEqual(preset.displayName, "Monastary")
        let expectedHeadSize = kFactoryPresets.first(where: { $0.name == "Monastary" })!.values[Int(Param.headSize.rawValue)]
        XCTAssertEqual(preset.savedParameters?[.headSize], expectedHeadSize)
        XCTAssertEqual(preset.faceID, target.faceID)
    }

    /// Factory presets can never be deleted — no delete control exists on
    /// their rows, exactly like built-ins, regardless of how many user
    /// entries exist alongside them.
    func testFactoryPresetRowsOfferNoDeleteControl() throws {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Some Save", characterID: "monk"))
        let dropdown = makeDropdown(store: store)
        let deleteLabel = NSLocalizedString("presets.delete.accessibility", comment: "")

        for preset in kFactoryPresets {
            let row = try XCTUnwrap(accessibleView(labeled: preset.name, in: dropdown))
            XCTAssertNil(accessibleView(labeled: deleteLabel, in: row),
                "\(preset.name)'s row must not offer a delete control")
        }
    }

    // MARK: - PluginView wiring

    /// Opening the dropdown by tapping the character selector's name (the
    /// same route `CharacterSelector.onOpenDropdown` fires from a tap or a
    /// VoiceOver double-tap) presents it as a subview of `PluginView`.
    func testOpeningTheSelectorsDropdownPresentsCharacterDropdownViewAsPluginViewSubview() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertFalse(view.subviews.contains(where: { $0 is CharacterDropdownView }))

        view.characterSelector.onOpenDropdown?()

        XCTAssertTrue(view.subviews.contains(where: { $0 is CharacterDropdownView }),
            "opening the selector's dropdown must present a CharacterDropdownView")
    }

    /// Selecting a character in the dropdown applies it to `stage`
    /// (character AND voice — see `CharacterView.select`) and dismisses the
    /// overlay.
    func testSelectingInDropdownAppliesCharacterAndDismissesOverlay() throws {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.characterSelector.onOpenDropdown?()
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let dropdown = try XCTUnwrap(view.subviews.first(where: { $0 is CharacterDropdownView }) as? CharacterDropdownView)
        let target = CharacterRegistry.all[2]
        let row = try XCTUnwrap(accessibleView(labeled: target.displayName, in: dropdown) as? UIControl)
        row.sendActions(for: .touchUpInside)

        XCTAssertEqual(view.stage.character.id, target.id)
        XCTAssertFalse(view.subviews.contains(where: { $0 is CharacterDropdownView }),
            "selecting a character must dismiss the dropdown overlay")
    }

    /// `PluginView` hands its own `presetStore` straight to the dropdown, so
    /// a real app's saved entries actually show up through the real wiring,
    /// not just when a test constructs `CharacterDropdownView` directly.
    func testPluginViewPassesItsPresetStoreToTheDropdown() throws {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Via PluginView", characterID: "fish"))
        view.presetStore = store
        view.setNeedsLayout()
        view.layoutIfNeeded()

        view.characterSelector.onOpenDropdown?()
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let dropdown = try XCTUnwrap(view.subviews.first(where: { $0 is CharacterDropdownView }) as? CharacterDropdownView)
        XCTAssertTrue(accessibleLabels(in: dropdown).contains("Via PluginView"))
    }

    /// Tapping outside the dropdown dismisses it without changing the
    /// currently-selected character.
    func testTappingOutsideDropdownDismissesWithoutChangingCharacter() throws {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.characterSelector.onOpenDropdown?()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let before = view.stage.character.id

        let dropdown = try XCTUnwrap(view.subviews.first(where: { $0 is CharacterDropdownView }) as? CharacterDropdownView)
        dropdown.perform(Selector(("backdropTapped")))

        XCTAssertEqual(view.stage.character.id, before)
        XCTAssertFalse(view.subviews.contains(where: { $0 is CharacterDropdownView }))
    }
}
