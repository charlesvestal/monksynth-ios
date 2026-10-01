import XCTest
import UIKit
@testable import MonkSynth

/// Covers `CharacterSelector` — the quiet, centred "‹ Monk ›" label
/// replacing the old edge arrows, the tap-the-art picker gesture, and the
/// filled-pill control that followed it — plus `PluginView`'s wiring of it:
/// stepping the visible `CharacterView` (wraparound, exactly what the old
/// arrows did) and opening `CharacterDropdownView` by tapping the name
/// (there is no separate chevron target anymore).
///
/// `CharacterSelector`'s three interactive subviews (`‹`, the name target,
/// `›`) are found structurally rather than by matching localized
/// accessibility text (`character.previous`/`character.next`/
/// `characterSelector.label` all go through `NSLocalizedString`, and this
/// process's `Bundle.main` resolution for a unit-test bundle is exactly the
/// kind of thing `LocalizationTests` exists to pin down separately) — the
/// two `UIButton`s are `‹`/`›` (left-to-right by X position), and the one
/// remaining subview is the name target.
final class CharacterSelectorTests: XCTestCase {

    // MARK: - Fake store (for the "arrows cycle saved entries too" test below)

    /// In-memory `PresetStoring` fixture — mirrors the fake
    /// `CharacterDropdownViewTests`/`RenderUISnapshot` each keep privately
    /// to their own file; this file needs its own for the same reason
    /// those do (each is `private`/`fileprivate` to its own file), not
    /// because the shape differs.
    private final class FakePresetStore: PresetStoring {
        let supportsUserPresets = true
        private(set) var savedUserPresets: [SavedPreset] = []
        private var snapshots: [String: PresetSnapshot] = [:]

        func snapshot(forUserPresetNamed name: String) -> PresetSnapshot? { snapshots[name] }
        func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult { .unsupported }
        func deleteUserPreset(named name: String) {}

        func seed(_ name: String, characterID: String) {
            savedUserPresets.append(SavedPreset(name: name, characterID: characterID))
            snapshots[name] = PresetSnapshot(params: Param.allCases.map(\.defaultValue), characterID: characterID)
        }
    }

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

    private func nameLabel(in selector: CharacterSelector) throws -> UILabel {
        let control = try XCTUnwrap(nameControl(in: selector))
        return try XCTUnwrap(control.subviews.first(where: { $0 is UILabel }) as? UILabel)
    }

    /// Matches `PluginView.characterSelectorMaxWidth` — the widest the
    /// selector is ever actually given at a roomy host size.
    private func makeSelector(width: CGFloat = 180, height: CGFloat = 44) -> CharacterSelector {
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

    // MARK: - Name target opens the dropdown (there is no separate chevron)

    /// Tapping the name is the ENTIRE "open the list" affordance now — no
    /// separate chevron target exists to fire this. Also, structurally,
    /// `nameControl` has exactly one subview (`nameLabel`): the old chevron
    /// `UIImageView` is gone.
    func testTappingTheNameControlFiresOnOpenDropdownOnly() throws {
        let selector = makeSelector()
        var backward = 0, forward = 0, opened = 0
        selector.onStepBackward = { backward += 1 }
        selector.onStepForward = { forward += 1 }
        selector.onOpenDropdown = { opened += 1 }

        let control = try XCTUnwrap(nameControl(in: selector))
        XCTAssertEqual(control.subviews.count, 1,
            "expected only the name label inside the name control — no separate chevron subview")
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
    /// what tapping the name itself does visually.
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
                "expected exactly three interactive targets (‹, name, ›) at width \(width)")
            for sub in selector.subviews {
                XCTAssertGreaterThanOrEqual(sub.frame.width, 44,
                    "target \(sub) narrower than 44pt at selector width \(width)")
                XCTAssertGreaterThanOrEqual(sub.frame.height, 44,
                    "target \(sub) shorter than 44pt at selector width \(width)")
            }
        }
    }

    /// The visible discs and glyphs are smaller than the buttons; that must
    /// not shrink the touch targets underneath them — same "small glyph, big hit region"
    /// pattern already used by `PluginView.infoButton` and the drawer
    /// handle. Checks the glyph/label itself renders far smaller than its
    /// own tap target, at the roomiest width the selector is ever given.
    func testVisibleGlyphsAreSmallerThanTheirTapTargets() {
        let selector = makeSelector()
        let (left, right) = arrowButtons(in: selector)
        for button in [left, right] {
            let imageSize = button.imageView?.image?.size ?? .zero
            XCTAssertLessThan(imageSize.width, 20,
                "arrow glyph should render small — got \(imageSize) inside a \(button.frame) tap target")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }

    // MARK: - Sticker header

    /// The selector view itself stays transparent — the round arrow discs
    /// and the name sit directly on `Theme.background`, with no pill around
    /// the whole group.
    func testSelectorHasNoBackgroundOrBorder() {
        let selector = makeSelector()
        XCTAssertEqual(selector.backgroundColor, .clear)
        XCTAssertEqual(selector.layer.borderWidth, 0)
    }

    /// The name is the header's title: heavy rounded type in the primary
    /// text colour.
    func testNameLabelUsesThePrimaryTextColourInDisplayType() throws {
        let selector = makeSelector()
        let label = try nameLabel(in: selector)
        XCTAssertEqual(label.textColor, Theme.textPrimary)
        XCTAssertEqual(label.font, Theme.display(22))
    }

    // MARK: - Long names (a future roster will exceed "Monk")

    /// "Monk" is six characters at most today. A future roster will have
    /// names like "Opera Singer" or "Fire Fighter" — this exercises one at
    /// the exact width `PluginView` hands the selector at the AUM strip
    /// (375×180), the narrowest realistic width and the one closest to
    /// `infoButton`. The label must truncate rather than force the view (or
    /// any of its subviews) wider than the frame it was given, and the
    /// arrows on either side must keep their full 44pt tap target
    /// regardless of how long the name is — the name never steals width
    /// from them; see `layoutSubviews`.
    func testLongNameTruncatesWithoutGrowingOrStealingTapTargetWidth() throws {
        let width = PluginView.layout(in: CGRect(x: 0, y: 0, width: 375, height: 180)).characterSelector.width
        let selector = makeSelector(width: width)
        selector.characterName = "Opera Singer"
        selector.setNeedsLayout()
        selector.layoutIfNeeded()

        XCTAssertEqual(selector.frame.width, width,
            "a long name must never grow the selector's own frame")

        let label = try nameLabel(in: selector)
        XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
        XCTAssertLessThanOrEqual(label.frame.maxX, selector.bounds.width,
            "the name label must stay clipped inside the selector's given width, not overflow it")

        let (left, right) = arrowButtons(in: selector)
        for button in [left, right] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44,
                "a long name must not shrink the arrow tap targets below 44pt")
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
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

    /// The task's requirement, verified end to end: with saved entries
    /// present, the arrows step through the FULL roster — every built-in
    /// AND every saved entry — not just `CharacterRegistry` (the bug the
    /// task calls out: "today they may only cycle CharacterRegistry").
    /// `PluginView.stepCharacter(by:)` consults
    /// `CharacterDropdownView.characters(from: presetStore)`, the exact same
    /// merged list the dropdown itself shows, so this proves the arrows and
    /// the dropdown can never silently disagree about what "the full
    /// roster" means.
    func testSelectorArrowsStepThroughSavedEntriesTooWithWraparound() throws {
        let store = FakePresetStore()
        store.seed("Sunrise", characterID: "unicorn")
        store.seed("Bubbles", characterID: "fish")

        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.presetStore = store
        view.setNeedsLayout(); view.layoutIfNeeded()
        XCTAssertEqual(view.stage.character.id, "monk")

        let roster = CharacterDropdownView.characters(from: store)
        XCTAssertEqual(roster.count, CharacterRegistry.all.count + 2,
            "sanity: the roster the arrows walk must include both saved entries")

        let (left, right) = arrowButtons(in: view.characterSelector)

        var forwardVisited = [view.stage.character.id]
        for _ in 0..<roster.count {
            right.sendActions(for: .touchUpInside)
            forwardVisited.append(view.stage.character.id)
        }
        XCTAssertEqual(forwardVisited, roster.map(\.id) + ["monk"],
            "stepping › through the whole roster (built-ins AND saved entries) must wrap back to monk")
        XCTAssertTrue(forwardVisited.contains("user:Sunrise"), "forward stepping never reached the saved \"Sunrise\" entry")
        XCTAssertTrue(forwardVisited.contains("user:Bubbles"), "forward stepping never reached the saved \"Bubbles\" entry")

        view.stage.select(CharacterRegistry.defaultCharacter)
        var backwardVisited = [view.stage.character.id]
        for _ in 0..<roster.count {
            left.sendActions(for: .touchUpInside)
            backwardVisited.append(view.stage.character.id)
        }
        let expectedBackward = [CharacterRegistry.defaultCharacter.id]
            + roster.dropFirst().reversed().map(\.id) + [CharacterRegistry.defaultCharacter.id]
        XCTAssertEqual(backwardVisited, expectedBackward,
            "stepping ‹ through the whole roster must wrap back around in reverse, saved entries included")
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

    // MARK: - Never collides with infoButton, even with a long name

    /// The specific risk the task calls out: because the selector is now
    /// centred rather than left-aligned, a naive "size the group to its
    /// content, then centre it" implementation would let a long name grow
    /// the frame outward on both sides — and at a narrow width the
    /// right-hand growth could walk into `infoButton`. Exercised end to end
    /// through a REAL `PluginView`, at the narrowest realistic width (the
    /// AUM strip, 375×180) where the two sit closest together, with a name
    /// well beyond anything in today's six-character roster ("Monk", "Fish",
    /// "Cow", ...) — standing in for a future roster entry like "Opera
    /// Singer" or "Fire Fighter".
    func testCharacterSelectorNeverCollidesWithInfoButtonWithALongNameAtTheAUMStripWidth() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 375, height: 180))
        view.characterSelector.characterName = "Opera Singer"
        view.setNeedsLayout(); view.layoutIfNeeded()

        let infoButton = PluginView.layout(in: view.bounds).infoButton
        XCTAssertFalse(view.characterSelector.frame.intersects(infoButton),
            "selector \(view.characterSelector.frame) collided with infoButton \(infoButton) for a long name")
    }

    /// Same collision guarantee at the standard portrait width, where there
    /// is normally ample room — confirms a long name doesn't quietly regress
    /// the roomy case either.
    func testCharacterSelectorNeverCollidesWithInfoButtonWithALongNameAtPortraitWidth() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.characterSelector.characterName = "Opera Singer"
        view.setNeedsLayout(); view.layoutIfNeeded()

        let infoButton = PluginView.layout(in: view.bounds).infoButton
        XCTAssertFalse(view.characterSelector.frame.intersects(infoButton),
            "selector \(view.characterSelector.frame) collided with infoButton \(infoButton) for a long name")
    }
}
