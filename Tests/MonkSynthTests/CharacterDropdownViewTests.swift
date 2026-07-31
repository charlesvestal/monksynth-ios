import XCTest
import UIKit
@testable import MonkSynth

/// Covers `CharacterDropdownView` — the plain-text-list overlay
/// `CharacterSelector`'s `⌄` opens, replacing the old character-art grid
/// (`CharacterPickerView`) — plus `PluginView`'s wiring of it (opening from
/// the selector, applying and dismissing on a row tap). `CharacterDropdownRow`
/// is private to `CharacterDropdownView.swift`, so these tests reach it the
/// same way the old suite reached `CharacterCell`: via public
/// `UIView`/`UIControl` APIs (`subviews`, `isAccessibilityElement`,
/// `accessibilityLabel`, `sendActions(for:)`) rather than the concrete type.
final class CharacterDropdownViewTests: XCTestCase {

    // MARK: - Helpers

    /// Depth-first walk collecting every accessible element's label —
    /// standing in for "one row per character" without needing to name the
    /// private `CharacterDropdownRow` type.
    private func accessibleLabels(in view: UIView) -> [String] {
        var out: [String] = []
        if view.isAccessibilityElement, let label = view.accessibilityLabel {
            out.append(label)
        }
        for sub in view.subviews { out += accessibleLabels(in: sub) }
        return out
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

    private func makeDropdown(current: Character = CharacterRegistry.defaultCharacter,
                               size: CGSize = CGSize(width: 390, height: 700)) -> CharacterDropdownView {
        let dropdown = CharacterDropdownView(frame: CGRect(origin: .zero, size: size), current: current)
        dropdown.setNeedsLayout()
        dropdown.layoutIfNeeded()
        return dropdown
    }

    // MARK: - Lists every registered character

    /// The count is derived from `CharacterRegistry.all` itself, not
    /// hardcoded — the roster is expected to grow, and this test must keep
    /// passing without editing it when that happens.
    func testDropdownListsExactlyOneRowPerRegisteredCharacter() {
        let dropdown = makeDropdown()
        let labels = accessibleLabels(in: dropdown)
        XCTAssertEqual(labels.count, CharacterRegistry.all.count,
            "expected one accessible row per registry entry, got \(labels.count) for \(CharacterRegistry.all.count) characters")
        XCTAssertEqual(Set(labels), Set(CharacterRegistry.all.map(\.displayName)),
            "every character's display name must appear exactly among the dropdown's rows")
    }

    // MARK: - Rows meet the 44pt HIG row height

    func testEveryRowIs44PointsTall() {
        let dropdown = makeDropdown()
        for character in CharacterRegistry.all {
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
    /// a plain list of 44pt rows must scroll cleanly here instead.
    func testContentExceedsVisibleAreaAtAVeryShortHostRect() throws {
        let dropdown = makeDropdown(size: CGSize(width: 375, height: 180))
        let scrollView = try XCTUnwrap(firstScrollView(in: dropdown))
        XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height,
            "at a very short host rect the dropdown's content must exceed the visible area")
    }

    // MARK: - PluginView wiring

    /// Opening the dropdown via the character selector's `⌄` (the same
    /// route `CharacterSelector.onOpenDropdown` fires from a tap or a
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
