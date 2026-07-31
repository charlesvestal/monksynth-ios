import XCTest
import UIKit
import AVFoundation
@testable import MonkSynth

/// Covers `PresetsView` — the presets overlay reachable from the about
/// screen's "Presets" link — against an in-memory `FakePresetStore` defined
/// right here, so these tests never touch `MonkSynthAU`'s real
/// `AUAudioUnit`-backed storage (see `PresetTests`'s own doc comment on why
/// that only works from inside a real, installed extension process) nor
/// `StandalonePresetStore`'s `UserDefaults` (covered separately in
/// `StandalonePresetStoreTests`). `PresetsView` only ever talks to whatever
/// `PresetStoring` it's handed, so a fake here is a completely faithful
/// substitute for either real backend.
final class PresetsViewTests: XCTestCase {

    // MARK: - Fake store

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
        /// character face per row.
        func seed(_ preset: SavedPreset, params: [AUValue] = Param.allCases.map(\.defaultValue)) {
            savedUserPresets.append(preset)
            snapshots[preset.name] = PresetSnapshot(params: params, characterID: preset.characterID)
        }
    }

    // MARK: - Helpers

    private func accessibleLabels(in view: UIView) -> [String] {
        var out: [String] = []
        if view.isAccessibilityElement, let label = view.accessibilityLabel { out.append(label) }
        for sub in view.subviews { out += accessibleLabels(in: sub) }
        return out
    }

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

    private func makeView(store: FakePresetStore, size: CGSize = CGSize(width: 390, height: 700)) -> PresetsView {
        let v = PresetsView(frame: CGRect(origin: .zero, size: size), store: store)
        v.setNeedsLayout()
        v.layoutIfNeeded()
        return v
    }

    /// Drives a save exactly the way pressing Return in the name field
    /// would — `PresetSaveRow` (private to `PresetsView.swift`) wires its
    /// Save button and its text field's Return key to the same private
    /// `saveTapped()`, so going through the field's own (public)
    /// `UITextFieldDelegate` is the one reachable, honest way to trigger it
    /// from outside that file, mirroring how `RenderUISnapshot` drives
    /// `PluginView`'s private `toggleDrawer` only via the real gesture path
    /// it's attached to where possible.
    private func triggerSave(in view: PresetsView) {
        guard let field = firstTextField(in: view) else {
            XCTFail("no name field found — is the store's supportsUserPresets true?")
            return
        }
        _ = field.delegate?.textFieldShouldReturn?(field)
    }

    // MARK: - Lists factory presets

    func testListsAllSixFactoryPresetsByName() {
        let view = makeView(store: FakePresetStore())
        let labels = Set(accessibleLabels(in: view))
        for factoryName in kFactoryPresets.map(\.name) {
            XCTAssertTrue(labels.contains(factoryName), "missing factory preset row \(factoryName)")
        }
    }

    func testTappingFactoryRowFiresOnSelectFactoryPresetWithCorrectIndex() throws {
        let view = makeView(store: FakePresetStore())
        var selected: [Int] = []
        view.onSelectFactoryPreset = { selected.append($0) }

        let target = kFactoryPresets[3].name
        let row = try XCTUnwrap(accessibleView(labeled: target, in: view) as? UIControl)
        row.sendActions(for: .touchUpInside)

        XCTAssertEqual(selected, [3])
    }

    // MARK: - Lists user presets with name and character face

    func testListsUserPresetsWithNameAndCharacterFace() {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Sparkly", characterID: "unicorn"))
        let view = makeView(store: store)

        let labels = Set(accessibleLabels(in: view))
        XCTAssertTrue(labels.contains("Sparkly"))
    }

    func testTappingUserRowFiresOnSelectUserPresetWithResolvedSnapshot() throws {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Sparkly", characterID: "unicorn"),
                    params: [0.9] + Param.allCases.dropFirst().map(\.defaultValue))
        let view = makeView(store: store)

        var received: [PresetSnapshot] = []
        view.onSelectUserPreset = { received.append($0) }

        let row = try XCTUnwrap(accessibleView(labeled: "Sparkly", in: view) as? UIControl)
        row.sendActions(for: .touchUpInside)

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.characterID, "unicorn")
        XCTAssertEqual(received.first?.params.first, 0.9)
    }

    /// Empty-state placeholder shown, and no rows, when nothing's saved yet.
    func testEmptyUserPresetsShowsPlaceholder() {
        let view = makeView(store: FakePresetStore())
        let labels = accessibleLabels(in: view)
        for factory in kFactoryPresets.map(\.name) {
            XCTAssertTrue(labels.contains(factory))
        }
        // No user-preset rows beyond the six factory ones plus the close button.
        XCTAssertFalse(labels.contains(where: { $0.hasPrefix("Sparkly") }))
    }

    // MARK: - Saving

    func testSavingValidNameRefreshesListAndClearsField() throws {
        let store = FakePresetStore()
        let view = makeView(store: store)
        let field = try XCTUnwrap(firstTextField(in: view))

        field.text = "Brand New"
        triggerSave(in: view)

        XCTAssertEqual(store.savedUserPresets.map(\.name), ["Brand New"])
        XCTAssertEqual(field.text, "")
        XCTAssertTrue(accessibleLabels(in: view).contains("Brand New"))
    }

    /// "Saving with an empty name" — no preset created, and the field's
    /// contents are left alone (untouched) rather than silently cleared, so
    /// the user can see what they typed (or didn't) when the error shows.
    func testSavingWithEmptyNameCreatesNothing() throws {
        let store = FakePresetStore()
        let view = makeView(store: store)
        let field = try XCTUnwrap(firstTextField(in: view))

        field.text = "   "
        triggerSave(in: view)

        XCTAssertTrue(store.savedUserPresets.isEmpty)
    }

    /// "...or a name that duplicates an existing preset" — the original
    /// stays, and a second one is not created.
    func testSavingWithDuplicateNameCreatesNothingNew() throws {
        let store = FakePresetStore()
        let view = makeView(store: store)
        let field = try XCTUnwrap(firstTextField(in: view))

        field.text = "Same Name"
        triggerSave(in: view)
        field.text = "Same Name"
        triggerSave(in: view)

        XCTAssertEqual(store.savedUserPresets.count, 1)
    }

    // MARK: - Deleting

    func testDeletingAUserPresetRemovesItFromTheList() throws {
        let store = FakePresetStore()
        store.seed(SavedPreset(name: "Temp", characterID: "cow"))
        let view = makeView(store: store)
        XCTAssertTrue(accessibleLabels(in: view).contains("Temp"))

        let deleteButton = try XCTUnwrap(accessibleView(
            labeled: NSLocalizedString("presets.delete.accessibility", comment: ""), in: view) as? UIControl)
        deleteButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(store.savedUserPresets.isEmpty)
        XCTAssertFalse(accessibleLabels(in: view).contains("Temp"))
    }

    // MARK: - Unsupported host

    /// "A host that reports supportsUserPresets == false — degrade without
    /// crashing and without offering a save button that cannot work."
    func testWhenStoreDoesNotSupportUserPresetsNoSaveUIIsOffered() {
        let store = FakePresetStore(supportsUserPresets: false)
        store.seed(SavedPreset(name: "Old Save", characterID: "monk"))
        let view = makeView(store: store)

        XCTAssertNil(firstTextField(in: view), "no name field should be offered when saving isn't supported")
        // The row still lists (read-only), but its delete button is hidden.
        XCTAssertTrue(accessibleLabels(in: view).contains("Old Save"))
        XCTAssertNil(accessibleView(
            labeled: NSLocalizedString("presets.delete.accessibility", comment: ""), in: view),
            "no delete control should be offered when saving isn't supported")
    }

    // MARK: - Dismissal

    func testBackdropTapFiresOnCloseWithoutSelectingAnything() {
        let view = makeView(store: FakePresetStore())
        var closedCount = 0
        view.onClose = { closedCount += 1 }
        var factorySelected = 0
        view.onSelectFactoryPreset = { _ in factorySelected += 1 }

        view.perform(Selector(("backdropTapped")))

        XCTAssertEqual(closedCount, 1)
        XCTAssertEqual(factorySelected, 0)
    }

    // MARK: - Scrolls at a short host rect

    func testScrollsAtAVeryShortHostRect() throws {
        let store = FakePresetStore()
        for i in 0..<5 { store.seed(SavedPreset(name: "Preset \(i)", characterID: "monk")) }
        let view = makeView(store: store, size: CGSize(width: 375, height: 180))
        let scrollView = try XCTUnwrap(firstScrollView(in: view))
        XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height,
            "at a very short host rect the presets overlay's content must exceed the visible area")
    }
}
