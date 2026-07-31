import UIKit

/// Everything appearance-specific about a MonkSynth character: body, eyes,
/// and mouth geometry. `CharacterView` owns everything else — animation,
/// the 24-frame vowel quantisation, the stepped amplitude swell,
/// display-link gating, Reduce Motion — so a `Character` conformer only has
/// to answer "what does this look like", never "when does it move".
///
/// All drawing happens in a unit-square "stage" (0...1 on both axes — see
/// `point(_:_:in:)` below) so a character's rig never distorts under the
/// odd aspect ratios an AUv3 host can hand `CharacterView` (an iPhone SE
/// portrait strip up to an iPad Pro).
protocol Character {
    /// Stable and persisted in `MonkSynthAU.fullState["characterID"]` —
    /// never change an existing character's `id` once shipped, or old
    /// sessions silently fall back to the default instead of restoring the
    /// intended selection (still gracefully, via `CharacterRegistry`, but
    /// better to just not change it).
    var id: String { get }

    /// Shown briefly in `CharacterView`'s tap-to-cycle overlay when the user
    /// switches to this character.
    var displayName: String { get }

    /// Everything except the eyes and the mouth aperture: body, head, and
    /// any props (a horn, a beard, a tail...). Drawn first, so eyes/mouth
    /// composite on top of it.
    func drawBody(in stage: CGRect)

    /// Drawn after `drawBody`, before the mouth. `blinking` is driven by
    /// `IdleAnimator` and is the only piece of per-frame state a
    /// character's drawing ever sees directly — the rest of the pose is
    /// folded into what `CharacterView` passes to `mouthShape`.
    func drawEyes(in stage: CGRect, blinking: Bool)

    /// The mouth aperture's (width, height) in stage-fraction-ish units for
    /// a given vowel position, 0...1. `CharacterView` always calls this
    /// with an already-`quantisedVowel`-stepped input — see that function's
    /// doc comment for why the stepping happens there and not here. This
    /// function itself should stay a smooth/continuous definition of the
    /// shape at any vowel, so the anchor geometry can be reasoned about and
    /// tested independently of the stepping.
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat)

    /// Where `mouthShape`'s aperture is centred, in stage fractions.
    var mouthCentre: (fx: CGFloat, fy: CGFloat) { get }

    /// Scales `mouthShape`'s values up to the stage: the mouth's own local
    /// reference frame, sized so an aperture at its widest anchor can't
    /// poke past the character's own jawline/muzzle/beard.
    var mouthBoxFraction: CGFloat { get }
}

extension Character {
    /// Maps a stage-relative unit-square fraction to an absolute point.
    /// Every character composes its drawing from this so nothing distorts
    /// under extreme aspect ratios — the same helper style `CharacterView`
    /// itself uses for the mouth it draws on every character's behalf.
    func point(_ fx: CGFloat, _ fy: CGFloat, in stage: CGRect) -> CGPoint {
        CGPoint(x: stage.minX + fx * stage.width, y: stage.minY + fy * stage.height)
    }
}

/// The ordered, bundled roster — no custom import (see the design doc's "why
/// no import" section: that would need an app-group entitlement that was
/// deliberately removed after it broke archiving). Monk is first, and is the
/// default; the rest follow in the order they were added.
///
/// Order here is what tap-to-cycle walks (`CharacterView.cycleCharacter()`)
/// — it is independent of `id`, so re-ordering this array changes cycling
/// order without touching anything persisted.
enum CharacterRegistry {
    static let all: [Character] = [
        MonkCharacter(),
        FishCharacter(),
        UnicornCharacter(),
        GirlCharacter(),
        OldManCharacter(),
        CowCharacter(),
    ]

    static var defaultCharacter: Character { all[0] }

    /// Looks up a character by its persisted `id`. Falls back to the
    /// default (monk) for `nil`, empty, or unrecognised ids, so an old
    /// session — or one saved after a character was renamed or removed —
    /// degrades to the default rather than rendering nothing.
    static func character(withID id: String?) -> Character {
        guard let id, let match = all.first(where: { $0.id == id }) else { return defaultCharacter }
        return match
    }

    /// The character after `current` in roster order, wrapping from the
    /// last entry back to the first. Falls back to the default if `current`
    /// somehow isn't in the roster (shouldn't happen, but degrades safely
    /// rather than crashing on a force-unwrap).
    static func character(after current: Character) -> Character {
        guard let index = all.firstIndex(where: { $0.id == current.id }) else { return defaultCharacter }
        return all[(index + 1) % all.count]
    }
}
