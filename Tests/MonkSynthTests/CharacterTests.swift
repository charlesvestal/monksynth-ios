import XCTest
import UIKit
@testable import MonkSynth

/// Covers `CharacterRegistry` (the ordered, bundled roster — see the
/// characters design doc) and `CharacterView`'s tap-to-cycle. `IdleAnimator`
/// and the mouth's vowel quantisation (shared by every character) are
/// already covered by `IdleAnimatorTests`; this file is about the parts
/// that are genuinely new: five distinct `Character` conformers and the
/// machinery that selects between them.
final class CharacterTests: XCTestCase {

    // MARK: - Roster shape

    /// Monk first (the default), and every entry has a real, unique id and
    /// display name — a blank or duplicate id would be silently ambiguous
    /// for persistence/lookup.
    func testRegistryHasFiveUniqueCharactersMonkFirst() {
        let all = CharacterRegistry.all
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.first?.id, "monk")
        XCTAssertTrue(CharacterRegistry.defaultCharacter.id == "monk")

        let ids = all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "every character id must be unique: \(ids)")
        for character in all {
            XCTAssertFalse(character.id.isEmpty, "character id must not be empty")
            XCTAssertFalse(character.displayName.isEmpty, "character displayName must not be empty")
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

    // MARK: - Cycling

    /// Walking `character(after:)` from monk must visit every character
    /// exactly once and land back on monk — i.e. it wraps, rather than
    /// running off the end of the array.
    func testCyclingWrapsFromLastCharacterBackToFirst() {
        var current = CharacterRegistry.defaultCharacter
        var visited = [current.id]
        for _ in 0..<(CharacterRegistry.all.count - 1) {
            current = CharacterRegistry.character(after: current)
            visited.append(current.id)
        }
        XCTAssertEqual(visited, CharacterRegistry.all.map(\.id),
                       "cycling once through should visit every character in roster order")

        let wrapped = CharacterRegistry.character(after: current)
        XCTAssertEqual(wrapped.id, "monk", "cycling past the last character must wrap to the first")
    }

    /// `CharacterView.cycleCharacter()` — the tap handler's actual
    /// implementation — advances `character` and fires `onCharacterChange`
    /// exactly once per tap, with the same wrap-around behaviour.
    func testCharacterViewCyclesThroughEntireRosterAndWraps() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        var changes: [String] = []
        view.onCharacterChange = { changes.append($0.id) }

        XCTAssertEqual(view.character.id, "monk", "monk is the default before any cycling")

        for _ in 0..<CharacterRegistry.all.count {
            view.cycleCharacter()
        }

        XCTAssertEqual(changes, CharacterRegistry.all.dropFirst().map(\.id) + ["monk"])
        XCTAssertEqual(view.character.id, "monk", "a full cycle returns to the default")
    }

    // MARK: - Distinct implementations, not five copies

    /// Each character's `mouthShape` sweep must differ from every other's —
    /// otherwise "five characters" would really be one rig re-skinned with
    /// identical mouth geometry. Sample a few vowel positions and assert
    /// not every character produces the same shape at each.
    func testEachCharacterProducesADifferentMouthShapeSweep() {
        let characters = CharacterRegistry.all
        let vowels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]

        for vowel in vowels {
            let shapes = characters.map { $0.mouthShape(vowel: vowel) }
            let widths = Set(shapes.map { $0.w })
            let heights = Set(shapes.map { $0.h })
            XCTAssertFalse(widths.count == 1 && heights.count == 1,
                           "all five characters produced an identical mouth shape at vowel \(vowel): \(shapes)")
        }

        // Stronger check: no two characters share the exact same sweep
        // across every sampled vowel (a real, if unlikely, way five
        // "different" implementations could still be copies of one another).
        for i in 0..<characters.count {
            for j in (i + 1)..<characters.count {
                let a = vowels.map { characters[i].mouthShape(vowel: $0) }
                let b = vowels.map { characters[j].mouthShape(vowel: $0) }
                let identical = zip(a, b).allSatisfy { abs($0.w - $1.w) < 1e-9 && abs($0.h - $1.h) < 1e-9 }
                XCTAssertFalse(identical,
                               "\(characters[i].id) and \(characters[j].id) have identical mouth-shape sweeps")
            }
        }
    }

    /// Distinct `mouthCentre`/`mouthBoxFraction` too — a copy-pasted
    /// implementation that only varied the anchor numbers would still be
    /// suspicious if every character centred the mouth at the identical
    /// point with the identical scale.
    func testNotEveryCharacterSharesTheSameMouthPlacement() {
        let placements = CharacterRegistry.all.map { ($0.mouthCentre.fx, $0.mouthCentre.fy, $0.mouthBoxFraction) }
        let allIdentical = placements.dropFirst().allSatisfy { $0 == placements[0] }
        XCTAssertFalse(allIdentical, "every character has the same mouth placement: \(placements)")
    }

    // MARK: - Tap-to-cycle does not steal the pad's drags

    /// `stage` and `pad` are separate sibling `UIView`s (`PluginView.stage`,
    /// `PluginView.pad`) — `CharacterView`'s tap gesture is attached to
    /// `stage` alone, and UIKit only ever delivers a touch to the (single)
    /// subview whose frame contains it. So the tap-to-cycle gesture can
    /// only ever "steal" a touch that was already going to `stage`, never
    /// one over `pad` — geometric non-overlap is the whole guarantee.
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
            for drawerOpen in [false, true] {
                let l = PluginView.layout(in: CGRect(origin: .zero, size: size), drawerOpen: drawerOpen)
                XCTAssertFalse(l.stage.intersects(l.pad),
                               "stage \(l.stage) overlaps pad \(l.pad) at size \(size), drawerOpen=\(drawerOpen)")
            }
        }
    }

    /// End-to-end version of the same guarantee using real views: laying
    /// out a `PluginView` and tapping squarely inside `pad`'s frame must
    /// reach the pad, not `stage`'s tap-to-cycle gesture — proven here by
    /// confirming UIKit's own hit-test resolves a point inside `pad` to
    /// `pad` (or one of its subviews), never to `stage`.
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

    func testCharacterViewIsAButtonTraitedAccessibilityElementNamingTheCurrentCharacter() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityTraits.contains(.button))
        XCTAssertTrue(view.accessibilityLabel?.contains("Monk") ?? false,
                     "accessibility label should name the current character: \(view.accessibilityLabel ?? "nil")")

        view.character = FishCharacter()
        XCTAssertTrue(view.accessibilityLabel?.contains("Fish") ?? false,
                     "accessibility label should update when the character changes: \(view.accessibilityLabel ?? "nil")")
    }

    /// VoiceOver's double-tap invokes `accessibilityActivate()` on a
    /// non-`UIControl` accessibility element rather than synthesizing a
    /// touch — this is the "expose an accessibility action" half of the
    /// tap-to-cycle requirement.
    func testAccessibilityActivateCyclesTheCharacter() {
        let view = CharacterView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(view.character.id, "monk")

        let handled = view.accessibilityActivate()

        XCTAssertTrue(handled)
        XCTAssertEqual(view.character.id, "fish")
    }
}
