import XCTest
import UIKit
@testable import MonkSynth

/// Covers `CharacterSelector` — the compact "‹ Monk ⌄ ›" control replacing
/// the old edge arrows and the tap-the-art picker gesture — plus
/// `PluginView`'s wiring of it: stepping the visible `CharacterView`
/// (wraparound, exactly what the old arrows did) and opening
/// `CharacterDropdownView`.
///
/// `CharacterSelector`'s three interactive subviews (`‹`, the name+`⌄`
/// target, `›`) are found structurally rather than by matching localized
/// accessibility text (`character.previous`/`character.next`/
/// `characterSelector.label` all go through `NSLocalizedString`, and this
/// process's `Bundle.main` resolution for a unit-test bundle is exactly the
/// kind of thing `LocalizationTests` exists to pin down separately) — the
/// two `UIButton`s are `‹`/`›` (left-to-right by X position), and the one
/// remaining subview is the name+chevron target.
final class CharacterSelectorTests: XCTestCase {

    // MARK: - Helpers

    private func arrowButtons(in selector: CharacterSelector) -> (left: UIButton, right: UIButton) {
        let buttons = selector.subviews.compactMap { $0 as? UIButton }
            .sorted { $0.frame.minX < $1.frame.minX }
        precondition(buttons.count == 2, "expected exactly two UIButtons (‹ and ›) in CharacterSelector")
        return (buttons[0], buttons[1])
    }

    private func nameControl(in selector: CharacterSelector) -> UIControl? {
        selector.subviews.first(where: { !($0 is UIButton) }) as? UIControl
    }

    private func makeSelector(width: CGFloat = 210, height: CGFloat = 44) -> CharacterSelector {
        let selector = CharacterSelector(frame: CGRect(x: 0, y: 0, width: width, height: height))
        selector.setNeedsLayout()
        selector.layoutIfNeeded()
        return selector
    }

    // MARK: - ‹ / › step, with wraparound (standalone widget)

    func testLeftButtonFiresOnStepBackwardOnly() {
        let selector = makeSelector()
        var backward = 0, forward = 0, opened = 0
        selector.onStepBackward = { backward += 1 }
        selector.onStepForward = { forward += 1 }
        selector.onOpenDropdown = { opened += 1 }

        arrowButtons(in: selector).left.sendActions(for: .touchUpInside)

        XCTAssertEqual(backward, 1)
        XCTAssertEqual(forward, 0)
        XCTAssertEqual(opened, 0)
    }

    func testRightButtonFiresOnStepForwardOnly() {
        let selector = makeSelector()
        var backward = 0, forward = 0, opened = 0
        selector.onStepBackward = { backward += 1 }
        selector.onStepForward = { forward += 1 }
        selector.onOpenDropdown = { opened += 1 }

        arrowButtons(in: selector).right.sendActions(for: .touchUpInside)

        XCTAssertEqual(backward, 0)
        XCTAssertEqual(forward, 1)
        XCTAssertEqual(opened, 0)
    }

    // MARK: - Name/chevron target opens the dropdown

    func testTappingTheNameControlFiresOnOpenDropdownOnly() throws {
        let selector = makeSelector()
        var backward = 0, forward = 0, opened = 0
        selector.onStepBackward = { backward += 1 }
        selector.onStepForward = { forward += 1 }
        selector.onOpenDropdown = { opened += 1 }

        let control = try XCTUnwrap(nameControl(in: selector))
        control.sendActions(for: .touchUpInside)

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(backward, 0)
        XCTAssertEqual(forward, 0)
    }

    // MARK: - Accessibility: reads as one value-adjustable control

    /// Per the task: the name control is `.adjustable`, with the character
    /// name as its VALUE, previous/next as the increment/decrement ADJUST
    /// actions (a VoiceOver swipe, not just the tiny `‹`/`›` glyphs), and
    /// double-tap (`accessibilityActivate`) opening the dropdown — exactly
    /// what the chevron visually promises.
    func testNameControlIsAnAdjustableAccessibilityElement() throws {
        let selector = makeSelector()
        let control = try XCTUnwrap(nameControl(in: selector))

        XCTAssertTrue(control.isAccessibilityElement)
        XCTAssertTrue(control.accessibilityTraits.contains(.adjustable))
        XCTAssertNotNil(control.accessibilityLabel)
        XCTAssertFalse(control.accessibilityLabel?.isEmpty ?? true)
        XCTAssertNotNil(control.accessibilityHint)
        XCTAssertFalse(control.accessibilityHint?.isEmpty ?? true)
    }

    func testCharacterNameDrivesTheNameControlsAccessibilityValue() throws {
        let selector = makeSelector()
        let control = try XCTUnwrap(nameControl(in: selector))

        selector.characterName = "Fish"
        XCTAssertEqual(control.accessibilityValue, "Fish")

        selector.characterName = "Unicorn"
        XCTAssertEqual(control.accessibilityValue, "Unicorn")
    }

    func testAccessibilityIncrementAndDecrementStepTheCharacter() throws {
        let selector = makeSelector()
        var backward = 0, forward = 0
        selector.onStepBackward = { backward += 1 }
        selector.onStepForward = { forward += 1 }
        let control = try XCTUnwrap(nameControl(in: selector))

        control.accessibilityIncrement()
        XCTAssertEqual(forward, 1)
        XCTAssertEqual(backward, 0)

        control.accessibilityDecrement()
        XCTAssertEqual(backward, 1)
        XCTAssertEqual(forward, 1)
    }

    func testAccessibilityActivateOpensTheDropdownAndReturnsTrue() throws {
        let selector = makeSelector()
        var opened = 0
        selector.onOpenDropdown = { opened += 1 }
        let control = try XCTUnwrap(nameControl(in: selector))

        let handled = control.accessibilityActivate()

        XCTAssertTrue(handled)
        XCTAssertEqual(opened, 1)
    }

    // MARK: - 44pt minimum tap target, at the widths PluginView actually produces

    /// Every one of the three targets — not just the row as a whole — must
    /// clear the 44pt HIG minimum, at both the roomiest width the selector
    /// gets (a tall phone portrait) and the tightest one it's actually
    /// asked to render at (the AUM strip, 375×180, where
    /// `PluginView.characterSelectorFrame` clamps the width to dodge the
    /// drawer handle). Widths come from `PluginView.layout` itself rather
    /// than being hand-picked, so this stays honest about what the widget
    /// is really given.
    func testAllThreeTargetsMeetMinimumTapTargetAtRealisticWidths() {
        let widths: [CGFloat] = [
            PluginView.layout(in: CGRect(x: 0, y: 0, width: 375, height: 180)).characterSelector.width,
            PluginView.layout(in: CGRect(x: 0, y: 0, width: 390, height: 844)).characterSelector.width,
        ]
        for width in widths {
            let selector = makeSelector(width: width)
            XCTAssertEqual(selector.subviews.count, 3,
                "expected exactly three interactive targets (‹, name+⌄, ›) at width \(width)")
            for sub in selector.subviews {
                XCTAssertGreaterThanOrEqual(sub.frame.width, 44,
                    "target \(sub) narrower than 44pt at selector width \(width)")
                XCTAssertGreaterThanOrEqual(sub.frame.height, 44,
                    "target \(sub) shorter than 44pt at selector width \(width)")
            }
        }
    }

    // MARK: - PluginView wiring: the actual buttons step the actual stage

    /// End-to-end version of the arrow-stepping contract, exercised through
    /// `PluginView.characterSelector`'s REAL buttons (not a direct call to
    /// `stage.stepForward()`) — the count of steps to visit the whole
    /// roster is derived from `CharacterRegistry.all`, never hardcoded.
    func testSelectorArrowsStepPluginViewsStageWithWraparound() throws {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertEqual(view.stage.character.id, "monk")

        let (left, right) = arrowButtons(in: view.characterSelector)

        var forwardVisited = [view.stage.character.id]
        for _ in 0..<CharacterRegistry.all.count {
            right.sendActions(for: .touchUpInside)
            forwardVisited.append(view.stage.character.id)
        }
        XCTAssertEqual(forwardVisited, CharacterRegistry.all.map(\.id) + ["monk"],
            "stepping › through the whole roster must wrap back to monk")

        var backwardVisited = [view.stage.character.id]
        for _ in 0..<CharacterRegistry.all.count {
            left.sendActions(for: .touchUpInside)
            backwardVisited.append(view.stage.character.id)
        }
        let expectedBackward = [CharacterRegistry.defaultCharacter.id]
            + CharacterRegistry.all.dropFirst().reversed().map(\.id)
            + [CharacterRegistry.defaultCharacter.id]
        XCTAssertEqual(backwardVisited, expectedBackward,
            "stepping ‹ through the whole roster must wrap back around in reverse")
    }

    /// The selector's displayed name tracks `stage.character` across every
    /// route it can change through — its own arrows, AND a direct
    /// programmatic assignment (the route `AudioUnitViewController`/
    /// `RootViewController` use to seed/restore the view) that never goes
    /// through the selector at all.
    func testSelectorNameTracksStageCharacterAcrossEveryChangeRoute() throws {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout(); view.layoutIfNeeded()
        let control = try XCTUnwrap(nameControl(in: view.characterSelector))
        XCTAssertEqual(control.accessibilityValue, "Monk")

        arrowButtons(in: view.characterSelector).right.sendActions(for: .touchUpInside)
        XCTAssertEqual(control.accessibilityValue, "Fish")

        view.stage.character = CowCharacter()   // programmatic, e.g. a restored session
        XCTAssertEqual(control.accessibilityValue, "Cow")
    }
}
