import XCTest
import UIKit
@testable import MonkSynth

/// Covers `CharacterRegistry` (the ordered, bundled roster — see the
/// characters design doc) and `CharacterView`'s arrow-stepping/picker
/// selection. `IdleAnimator` and the mouth's vowel quantisation (shared by
/// every character) are already covered by `IdleAnimatorTests`; this file is
/// about the parts that are genuinely new: six distinct `Character`
/// conformers and the machinery that selects between them.
final class CharacterTests: XCTestCase {

    // MARK: - Roster shape

    /// Monk first (the default), and every entry has a real, unique id and
    /// display name — a blank or duplicate id would be silently ambiguous
    /// for persistence/lookup. Deliberately doesn't assert an exact
    /// `all.count` — that would just be a magic number to bump every time a
    /// character is added or removed; the roster's *shape* invariants
    /// (non-empty, unique, monk-first) are what actually matter and are
    /// derived from the registry itself below.
    func testRegistryHasUniqueCharactersMonkFirst() {
        let all = CharacterRegistry.all
        XCTAssertFalse(all.isEmpty)
        XCTAssertEqual(all.first?.id, "monk")
        XCTAssertTrue(CharacterRegistry.defaultCharacter.id == "monk")

        let ids = all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "every character id must be unique: \(ids)")
        for character in all {
            XCTAssertFalse(character.id.isEmpty, "character id must not be empty")
            XCTAssertFalse(character.displayName.isEmpty, "character displayName must not be empty")
        }
    }

    // MARK: - One preset per character (mechanically enforced)

    /// The user's finalized model: "we want 1 preset per character." Every
    /// BUILT-IN character (`CharacterRegistry.all` — twelve now: the
    /// original six plus the six added to give upstream's factory presets
    /// their own faces, see `FactoryVoiceTable`) is its own face — never
    /// borrows another's, unlike the deleted `FactoryPresetCharacter`,
    /// which let monk end up wearing three presets at once — and has
    /// exactly one voice source: either a hand-tuned `CharacterVoiceTable`
    /// entry (the original six) or a factory-preset `savedParameters`
    /// override (the six new ones), never both, never neither.
    ///
    /// Deliberately scoped to the FIXED built-in roster, not the merged
    /// in-app list (`CharacterDropdownView.characters(from:)`): a user's
    /// own saved entries are explicitly exempt from this rule — saving two
    /// different patches under the same borrowed face is the whole point of
    /// "save a preset with a name, along with whatever the last face was,"
    /// and nothing in the task asks THAT to be restricted, only the fixed
    /// roster itself.
    func testEveryBuiltInCharacterHasExactlyOneFaceAndOneVoiceSource() {
        let all = CharacterRegistry.all
        let faceIDs = all.map(\.faceID)
        XCTAssertEqual(Set(faceIDs).count, faceIDs.count,
            "two built-in characters share a face: \(faceIDs)")

        for character in all {
            XCTAssertEqual(character.faceID, character.id,
                "\(character.id) borrows another built-in's face instead of being its own")

            let hasTunedVoice = CharacterVoiceTable.hasOwnVoice(for: character)
            let hasFactoryVoice = character.savedParameters != nil
            XCTAssertTrue(hasTunedVoice != hasFactoryVoice,
                "\(character.id) must have exactly one voice source (a CharacterVoiceTable entry XOR a " +
                "factory-preset savedParameters override), got tuned=\(hasTunedVoice) factory=\(hasFactoryVoice)")
        }
    }

    // MARK: - Lookup fallback

    func testLookupByKnownIDReturnsThatCharacter() {
        XCTAssertEqual(CharacterRegistry.character(withID: "fish").id, "fish")
        XCTAssertEqual(CharacterRegistry.character(withID: "unicorn").id, "unicorn")
    }

    func testLookupByUnknownOrNilOrEmptyIDFallsBackToMonk() {
        XCTAssertEqual(CharacterRegistry.character(withID: "not-a-real-character").id, "monk")
        XCTAssertEqual(CharacterRegistry.character(withID: nil).id, "monk")
        XCTAssertEqual(CharacterRegistry.character(withID: "").id, "monk")
    }

    // MARK: - Stepping (arrows)

    /// Walking `character(after:)` from monk must visit every character
    /// exactly once and land back on monk — i.e. it wraps, rather than
    /// running off the end of the array. This is the "next character" arrow's
    /// underlying lookup.
    func testCharacterAfterWrapsFromLastCharacterBackToFirst() {
        var current = CharacterRegistry.defaultCharacter
        var visited = [current.id]
        for _ in 0..<(CharacterRegistry.all.count - 1) {
            current = CharacterRegistry.character(after: current)
            visited.append(current.id)
        }
        XCTAssertEqual(visited, CharacterRegistry.all.map(\.id),
                       "stepping forward once through should visit every character in roster order")

        let wrapped = CharacterRegistry.character(after: current)
        XCTAssertEqual(wrapped.id, "monk", "stepping forward past the last character must wrap to the first")
    }

    /// Mirror of the above for `character(before:)` — the "previous
    /// character" arrow's underlying lookup. Walking backward from monk
    /// must visit the roster in reverse order and wrap from the first entry
    /// back to the last.
    func testCharacterBeforeWrapsFromFirstCharacterBackToLast() {
        var current = CharacterRegistry.defaultCharacter
        var visited = [current.id]
        for _ in 0..<(CharacterRegistry.all.count - 1) {
            current = CharacterRegistry.character(before: current)
            visited.append(current.id)
        }
        XCTAssertEqual(visited, [CharacterRegistry.all.first!.id] + CharacterRegistry.all.dropFirst().reversed().map(\.id),
                       "stepping backward once through should visit every character in reverse roster order")

        let wrapped = CharacterRegistry.character(before: current)
        XCTAssertEqual(wrapped.id, "monk", "stepping backward past the first character must wrap to the last")
    }

    /// `CharacterView.stepForward()` — the "next character" arrow's actual
    /// implementation — advances `character` and fires `onCharacterSelected`
    /// exactly once per step, with the same wrap-around behaviour as
    /// `CharacterRegistry.character(after:)`.
    func testStepForwardAdvancesThroughEntireRosterAndWraps() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var changes: [String] = []
        view.onCharacterSelected = { changes.append($0.id) }

        XCTAssertEqual(view.character.id, "monk", "monk is the default before any stepping")

        for _ in 0..<CharacterRegistry.all.count {
            view.stepForward()
        }

        XCTAssertEqual(changes, CharacterRegistry.all.dropFirst().map(\.id) + ["monk"])
        XCTAssertEqual(view.character.id, "monk", "a full forward cycle returns to the default")
    }

    /// Symmetric coverage for `stepBackward()` — the "previous character"
    /// arrow — stepping away from and back to the default in the opposite
    /// direction.
    func testStepBackwardRetreatsThroughEntireRosterAndWraps() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var changes: [String] = []
        view.onCharacterSelected = { changes.append($0.id) }

        for _ in 0..<CharacterRegistry.all.count {
            view.stepBackward()
        }

        let expected = CharacterRegistry.all.dropFirst().reversed().map(\.id) + ["monk"]
        XCTAssertEqual(changes, expected)
        XCTAssertEqual(view.character.id, "monk", "a full backward cycle returns to the default")
    }

    /// `select(_:)` — what the picker overlay calls — jumps straight to the
    /// given character (not just the adjacent one) and fires
    /// `onCharacterSelected` with it, exactly like the arrows do for their
    /// own step.
    func testSelectJumpsDirectlyToTheGivenCharacterAndFiresCallback() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var selected: [String] = []
        view.onCharacterSelected = { selected.append($0.id) }

        view.select(CowCharacter())

        XCTAssertEqual(view.character.id, "cow")
        XCTAssertEqual(selected, ["cow"])
    }

    /// Every route that changes the character — forward step, backward
    /// step, and a direct picker selection — must load the matching voice.
    /// `CharacterView` itself has no notion of voices (see its doc comment);
    /// this only proves all three routes go through the single
    /// `onCharacterSelected` callback an owner uses to do that, not that any
    /// two of them fire a different, inconsistent set of callbacks.
    func testEveryChangeRouteFiresTheSameSingleCallback() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var fired = 0
        view.onCharacterSelected = { _ in fired += 1 }

        view.stepForward()
        view.stepBackward()
        view.select(UnicornCharacter())

        XCTAssertEqual(fired, 3, "every one of stepForward/stepBackward/select must fire onCharacterSelected exactly once")
    }

    // MARK: - Distinct implementations, not five copies

    /// Distinct `mouthCentre`/`mouthBoxFraction` too — a copy-pasted
    /// implementation that only varied the anchor numbers would still be
    /// suspicious if every character centred the mouth at the identical
    /// point with the identical scale.
    func testNotEveryCharacterSharesTheSameMouthPlacement() {
        let placements = CharacterRegistry.all.map { ($0.mouthCentre.fx, $0.mouthCentre.fy, $0.mouthBoxFraction) }
        let allIdentical = placements.dropFirst().allSatisfy { $0 == placements[0] }
        XCTAssertFalse(allIdentical, "every character has the same mouth placement: \(placements)")
    }

    // MARK: - The character art never steals the pad's drags

    /// `stage` and `pad` are separate sibling `UIView`s (`PluginView.stage`,
    /// `PluginView.pad`). `stage` is non-interactive now (see
    /// `CharacterView.init`'s `isUserInteractionEnabled = false`) — it has
    /// no gesture of any kind — but this geometric guarantee is still worth
    /// keeping: it's what several other tests (and `CharacterSelector`'s own
    /// header-row placement) lean on to reason about touch/layout
    /// independently of whether any given zone happens to be interactive.
    /// `LayoutTests` already asserts pad-doesn't-overlap-stage for a couple
    /// of specific sizes; this sweeps a wider range, including the
    /// collapsed-stage case the design doc calls out as fine ("there is
    /// simply nothing to tap").
    func testStageAndPadNeverOverlapAcrossLayoutSizes() {
        let sizes: [CGSize] = [
            CGSize(width: 320, height: 480),
            CGSize(width: 390, height: 844),
            CGSize(width: 844, height: 390),
            CGSize(width: 1024, height: 768),
            CGSize(width: 375, height: 180),   // AUM strip — stage collapses
            CGSize(width: 480, height: 320),
        ]
        for size in sizes {
            let l = PluginView.layout(in: CGRect(origin: .zero, size: size))
            XCTAssertFalse(l.stage.intersects(l.pad),
                           "stage \(l.stage) overlaps pad \(l.pad) at size \(size)")
        }
    }

    /// End-to-end version of the same guarantee using real views: laying
    /// out a `PluginView` and tapping squarely inside `pad`'s frame must
    /// reach the pad, never `stage` — proven here by confirming UIKit's own
    /// hit-test resolves a point inside `pad` to `pad` (or one of its
    /// subviews), never to `stage`.
    func testHitTestInsidePadFrameNeverResolvesToStage() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let probe = CGPoint(x: view.pad.frame.midX, y: view.pad.frame.midY)
        let hit = view.hitTest(probe, with: nil)
        XCTAssertNotNil(hit)
        XCTAssertFalse(hit === view.stage, "a touch over the pad's centre must not hit-test to the stage")
        XCTAssertTrue(hit === view.pad || (hit?.isDescendant(of: view.pad) ?? false),
                     "a touch over the pad's centre should hit-test to the pad")
    }

    // MARK: - Accessibility

    /// The character art is purely decorative now — `CharacterSelector`
    /// (see `CharacterSelectorTests`) is the single accessible place that
    /// names the current character and lets it be changed. `CharacterView`
    /// itself must stay OUT of the accessibility tree so VoiceOver doesn't
    /// announce the same information twice.
    func testCharacterViewIsNotAnAccessibilityElement() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertFalse(view.isAccessibilityElement)

        view.character = FishCharacter()
        XCTAssertFalse(view.isAccessibilityElement,
                        "changing the character must not make the art accessible")
    }

    /// Every route that changes the character fires `onCharacterChanged`
    /// too — unconditionally, including a plain programmatic assignment
    /// (`view.character = ...`, the route `AudioUnitViewController`/
    /// `RootViewController` use to seed/restore the view) that does NOT go
    /// through `onCharacterSelected`. `PluginView.characterSelector` relies
    /// on exactly this to keep its name label in sync with every route, not
    /// just the two (`stepForward`/`stepBackward`) it triggers itself.
    func testOnCharacterChangedFiresForBothProgrammaticAndUserDrivenChanges() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var changed: [String] = []
        view.onCharacterChanged = { changed.append($0.id) }

        view.character = FishCharacter()          // programmatic — no onCharacterSelected
        view.stepForward()                         // user-driven — fires both callbacks
        view.select(CowCharacter())                 // user-driven — fires both callbacks

        XCTAssertEqual(changed, ["fish", "unicorn", "cow"])
    }
}
