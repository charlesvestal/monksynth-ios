import XCTest
import UIKit
@testable import MonkSynth

/// Covers `CharacterPickerView` — the tap-the-character overlay that lists
/// every registered character and applies whichever one the user picks —
/// plus `PluginView`'s wiring of it (opening on a character tap, applying
/// and dismissing on selection). `CharacterCell`/`CharacterGridRow` are
/// private to `CharacterPickerView.swift`, so these tests reach them the
/// same way the rest of this suite reaches other files' private UI details:
/// via public `UIView`/`UIControl` APIs (`subviews`, `isAccessibilityElement`,
/// `accessibilityLabel`, `sendActions(for:)`) rather than the concrete type.
final class CharacterPickerViewTests: XCTestCase {

    // MARK: - Helpers

    /// Depth-first walk collecting every accessible element's label —
    /// standing in for "one cell per character" without needing to name the
    /// private `CharacterCell` type.
    private func accessibleLabels(in view: UIView) -> [String] {
        var out: [String] = []
        if view.isAccessibilityElement, let label = view.accessibilityLabel {
            out.append(label)
        }
        for sub in view.subviews { out += accessibleLabels(in: sub) }
        return out
    }

    /// Finds the (single) accessible descendant labelled `name` — a cell,
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

    private func makePicker(current: Character = CharacterRegistry.defaultCharacter,
                             size: CGSize = CGSize(width: 390, height: 700)) -> CharacterPickerView {
        let picker = CharacterPickerView(frame: CGRect(origin: .zero, size: size), current: current)
        picker.setNeedsLayout()
        picker.layoutIfNeeded()
        return picker
    }

    // MARK: - Lists every registered character

    /// The count is derived from `CharacterRegistry.all` itself, not
    /// hardcoded — the roster is expected to grow past six, and this test
    /// must keep passing without editing it when that happens.
    func testPickerListsExactlyOneCellPerRegisteredCharacter() {
        let picker = makePicker()
        let labels = accessibleLabels(in: picker)
        XCTAssertEqual(labels.count, CharacterRegistry.all.count,
            "expected one accessible cell per registry entry, got \(labels.count) for \(CharacterRegistry.all.count) characters")
        XCTAssertEqual(Set(labels), Set(CharacterRegistry.all.map(\.displayName)),
            "every character's display name must appear exactly among the picker's cells")
    }

    // MARK: - Current character indicated

    func testCurrentCharacterCellIsMarkedSelectedOthersAreNot() throws {
        let current = CharacterRegistry.all[1]
        let picker = makePicker(current: current)

        let currentCell = try XCTUnwrap(accessibleView(labeled: current.displayName, in: picker))
        XCTAssertTrue(currentCell.accessibilityTraits.contains(.selected))

        for other in CharacterRegistry.all where other.id != current.id {
            let cell = try XCTUnwrap(accessibleView(labeled: other.displayName, in: picker))
            XCTAssertFalse(cell.accessibilityTraits.contains(.selected),
                "\(other.id) must not be marked selected while \(current.id) is current")
        }
    }

    // MARK: - Selecting a cell

    func testTappingACellFiresOnSelectWithThatCharacterAndNoOthers() throws {
        let picker = makePicker(current: CharacterRegistry.defaultCharacter)
        let target = CharacterRegistry.all.last!   // deliberately not the current one

        var selections: [String] = []
        picker.onSelect = { selections.append($0.id) }

        let cell = try XCTUnwrap(accessibleView(labeled: target.displayName, in: picker) as? UIControl)
        cell.sendActions(for: .touchUpInside)

        XCTAssertEqual(selections, [target.id])
    }

    // MARK: - Dismissal

    func testBackdropTapFiresOnCloseWithoutSelectingAnything() {
        let picker = makePicker()
        var closedCount = 0
        picker.onClose = { closedCount += 1 }
        var selectedCount = 0
        picker.onSelect = { _ in selectedCount += 1 }

        picker.perform(Selector(("backdropTapped")))

        XCTAssertEqual(closedCount, 1)
        XCTAssertEqual(selectedCount, 0, "tapping outside must not apply any selection")
    }

    // MARK: - Scrolls at short host rects

    /// An AUv3 host can hand this view an extremely short rect (same
    /// concern `AboutView`/`MoreAppsView` already document), and the roster
    /// is expected to keep growing — so the content must actually exceed
    /// the visible area at a short size, proving there is something real to
    /// scroll rather than merely a scroll view that happens to never need
    /// to move.
    func testContentExceedsVisibleAreaAtAVeryShortHostRect() throws {
        let picker = makePicker(size: CGSize(width: 390, height: 160))
        let scrollView = try XCTUnwrap(firstScrollView(in: picker))
        XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height,
            "at a very short host rect the picker's content must exceed the visible area")
    }

    // MARK: - PluginView wiring

    /// Tapping the character opens the picker as a subview of `PluginView`
    /// — found generically (the concrete `CharacterPickerView` class is
    /// public, so a direct type check is fine here, unlike the private
    /// cell/row types above).
    func testTappingCharacterOpensPickerAsPluginViewSubview() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertFalse(view.subviews.contains(where: { $0 is CharacterPickerView }))

        view.stage.onOpenPicker?()

        XCTAssertTrue(view.subviews.contains(where: { $0 is CharacterPickerView }),
            "tapping the character must present a CharacterPickerView")
    }

    /// Selecting a character in the picker applies it to `stage` (character
    /// AND voice — see `CharacterView.select`) and dismisses the overlay.
    func testSelectingInPickerAppliesCharacterAndDismissesOverlay() throws {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        view.stage.onOpenPicker?()
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let picker = try XCTUnwrap(view.subviews.first(where: { $0 is CharacterPickerView }) as? CharacterPickerView)
        let target = CharacterRegistry.all[2]
        let cell = try XCTUnwrap(accessibleView(labeled: target.displayName, in: picker) as? UIControl)
        cell.sendActions(for: .touchUpInside)

        XCTAssertEqual(view.stage.character.id, target.id)
        XCTAssertFalse(view.subviews.contains(where: { $0 is CharacterPickerView }),
            "selecting a character must dismiss the picker overlay")
    }
}
