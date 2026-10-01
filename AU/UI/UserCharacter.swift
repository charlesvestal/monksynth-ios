import AVFoundation
import UIKit

/// A saved user preset, promoted to a first-class `Character` — the heart of
/// "collapse characters and presets into one list": the user asked "I want
/// only the characters as presets," and this type is what makes a saved
/// preset actually BE one, rather than a second, parallel `{name, face,
/// parameters}` concept living in its own overlay.
///
/// Backed by two independent things, matching `Character`'s own "look vs.
/// sound" split (see that protocol's doc comment): `faceID` (a built-in
/// character, resolved through `CharacterRegistry.character(withID:)` —
/// falling back to monk for a face id the roster no longer recognises,
/// exactly like every other lookup in this codebase) supplies everything
/// about how this looks, and `params` supplies everything about how it
/// sounds via `savedParameters`. `CharacterView`/`CharacterDropdownView`
/// never need to know this is anything other than a `Character` — that
/// uniformity is the entire point (see the task's decision 4).
struct UserCharacter: Character {
    /// The name it was saved under. Shown as `displayName`, and what
    /// `PresetStoring.deleteUserPreset(named:)`/`snapshot(forUserPresetNamed:)`
    /// use to find this entry again in the store.
    let name: String
    /// The built-in face id it was saved with — `SavedPreset.characterID`'s
    /// own meaning, already resolved through `CharacterRegistry` by
    /// whichever `PresetStoring` conformer produced it, so this is always a
    /// real built-in id by the time it lands here.
    let faceID: String
    /// Every one of the 15 voice parameters, indexed by `Param.rawValue` —
    /// the exact shape `PresetSnapshot.params` already uses.
    let params: [AUValue]

    /// Namespaced so a preset named e.g. "Cow" can never collide with the
    /// built-in character of the same name — the dropdown's "isCurrent"
    /// check, and every other place that compares `Character.id`, needs
    /// every entry in the merged list to have a genuinely unique id.
    var id: String { "user:" + name }
    var displayName: String { name }

    /// Everything about how this looks comes from the saved face — falls
    /// back to monk automatically via `CharacterRegistry.character(withID:)`
    /// if the roster no longer has `faceID` (the task's "unknown face id
    /// falls back to monk" requirement).
    private var face: Character { CharacterRegistry.character(withID: faceID) }

    func drawBody(in stage: CGRect) { face.drawBody(in: stage) }
    func drawEyes(in stage: CGRect, blinking: Bool) { face.drawEyes(in: stage, blinking: blinking) }
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat) { face.mouthShape(vowel: vowel) }
    var mouthCentre: (fx: CGFloat, fy: CGFloat) { face.mouthCentre }
    var mouthBoxFraction: CGFloat { face.mouthBoxFraction }
    // Forwarded explicitly rather than left to `Character`'s default
    // extension implementation: that default only knows how to draw a plain
    // oval from `mouthShape`/`mouthCentre`/`mouthBoxFraction`, which would
    // silently lose an image-backed face's own composited mouth (see
    // `SpriteCharacter`) if `faceID` ever names one. Forwarding to `face`
    // means this always draws exactly what selecting that face directly
    // would.
    func drawMouth(in stage: CGRect, vowel: Float, amplitudeBoost: CGFloat) {
        face.drawMouth(in: stage, vowel: vowel, amplitudeBoost: amplitudeBoost)
    }
    var palette: Palette { face.palette }
    func drawFace(in stage: CGRect, expression: Expression) { face.drawFace(in: stage, expression: expression) }
    func drawOverMouth(in stage: CGRect) { face.drawOverMouth(in: stage) }
    func drawBackdrop(in rect: CGRect, stage: CGRect) { face.drawBackdrop(in: rect, stage: stage) }

    /// The saved sound — selecting this character applies THIS, never
    /// `CharacterVoiceTable.voice(for:)` (which would stomp the saved patch
    /// with the face's own built-in voice; see the task's decision 5 and
    /// `AudioUnitViewController`/`RootViewController`'s `onCharacterSelected`
    /// wiring, which branches on exactly this property).
    var savedParameters: [Param: AUValue]? {
        var values = [Param: AUValue]()
        for p in Param.allCases where Int(p.rawValue) < params.count {
            values[p] = params[Int(p.rawValue)]
        }
        return values
    }

    /// Builds every user character currently in `store`, in the store's own
    /// stable display order (alphabetical — see `PresetStoring.
    /// savedUserPresets`). A `snapshot(forUserPresetNamed:)` miss (deleted
    /// from under an in-progress read — see that method's own doc comment)
    /// is simply skipped rather than surfaced as an error.
    static func all(from store: PresetStoring) -> [UserCharacter] {
        store.savedUserPresets.compactMap { saved in
            guard let snapshot = store.snapshot(forUserPresetNamed: saved.name) else { return nil }
            return UserCharacter(name: saved.name, faceID: snapshot.characterID, params: snapshot.params)
        }
    }
}
