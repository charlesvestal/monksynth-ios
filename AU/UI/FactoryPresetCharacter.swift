import AVFoundation
import UIKit

/// Which built-in face each of upstream's six factory presets (`AU/
/// FactoryPresets.swift`'s `kFactoryPresets` — upstream's own extracted
/// `.vstpreset` data, never edited here) borrows for its look, since none of
/// them shipped with art of their own and this task deliberately doesn't draw
/// any (all six are Tibetan-monk-flavoured patches; six near-identical new
/// monks would add nothing, and the whole art style is being replaced by
/// hand-made art regardless — see the task report).
///
/// Baked as plain data, not computed at runtime, so the mapping stays fixed
/// and inspectable even though it was DERIVED from a measurement: render a
/// fixed held note for each of the six factory presets and each of the six
/// built-in character voices (`CharacterVoiceTable`) through the vendored C
/// DSP, take each one's Welch-averaged Hann-windowed spectral centroid (the
/// same method `CharacterVoiceTests` already uses to reason about the six
/// characters' own brightness), and assign each preset the built-in whose
/// voice's centroid is nearest. `FactoryPresetFaceTests` re-runs that exact
/// measurement and asserts this table still matches its result — so if a
/// character's voice or a preset's own values are ever retuned, a silent
/// mismatch here fails loudly instead of drifting unnoticed.
///
/// The measurement produced two things worth calling out explicitly (see the
/// task report for the full numbers): Dorje and Rabten both land on "monk"
/// (Rabten's centroid is in fact bit-for-bit identical to monk's — Rabten
/// *is* upstream's own all-defaults patch, and `CharacterVoiceTable.monk` is
/// itself defined as `Param.defaultValue` for every voice parameter, so this
/// isn't a coincidence). That collision is accepted per the task rather than
/// forced apart, and no preset lands on "cow" at all — nothing in the six
/// factory presets is dark/breathy enough to be its nearest neighbour.
enum FactoryPresetFaceTable {
    static let faces: [String: String] = [
        "Dorje": "monk",
        "Jamyang": "unicorn",
        "Monastary": "oldman",
        "Ngawang": "fish",
        "Rabten": "monk",
        "Tinley": "girl",
    ]

    /// Falls back to the default face (monk) for a preset name this table
    /// doesn't recognise — shouldn't happen for any of the shipped six, but
    /// degrades the same way every other id lookup in this codebase does
    /// (`CharacterRegistry.character(withID:)`) rather than trapping.
    static func faceID(for presetName: String) -> String {
        faces[presetName] ?? CharacterRegistry.defaultCharacter.id
    }
}

/// One of upstream's six factory presets, promoted to a first-class
/// `Character` — the same move `UserCharacter` makes for a saved user
/// preset (see that type's doc comment for the shared "look vs. sound"
/// split this mirrors almost exactly): `faceID` supplies everything about
/// how this looks (via `FactoryPresetFaceTable`, measured sonic similarity —
/// never hand-picked), and `savedParameters` supplies everything about how
/// it sounds, straight from the preset's own stored values, so selecting one
/// loads its own patch rather than the borrowed face's built-in voice.
struct FactoryPresetCharacter: Character {
    let preset: Preset

    /// Namespaced like `UserCharacter.id` ("user:" + name) so a factory
    /// preset can never collide with a built-in or a user entry that
    /// happens to share its name — `PresetTests.
    /// testSavingWithAFactoryPresetsNameSucceeds` already establishes that
    /// user and factory names are different namespaces at the storage
    /// layer; this keeps that true for `Character.id` too.
    var id: String { "factory:" + preset.name }
    var displayName: String { preset.name }
    var faceID: String { FactoryPresetFaceTable.faceID(for: preset.name) }

    /// Everything about how this looks comes from the mapped face — falls
    /// back to monk automatically via `CharacterRegistry.character(withID:)`
    /// if `faceID` ever named a face the roster doesn't recognise (the
    /// task's "unknown face id falls back to monk" requirement), exactly
    /// like `UserCharacter.face`.
    private var face: Character { CharacterRegistry.character(withID: faceID) }

    func drawBody(in stage: CGRect) { face.drawBody(in: stage) }
    func drawEyes(in stage: CGRect, blinking: Bool) { face.drawEyes(in: stage, blinking: blinking) }
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat) { face.mouthShape(vowel: vowel) }
    var mouthCentre: (fx: CGFloat, fy: CGFloat) { face.mouthCentre }
    var mouthBoxFraction: CGFloat { face.mouthBoxFraction }
    // Forwarded explicitly, not left to `Character`'s default oval — see
    // `UserCharacter.drawMouth`'s identical reasoning: the default would
    // silently lose an image-backed face's own composited mouth if `faceID`
    // ever named one.
    func drawMouth(in stage: CGRect, vowel: Float, amplitudeBoost: CGFloat) {
        face.drawMouth(in: stage, vowel: vowel, amplitudeBoost: amplitudeBoost)
    }

    /// The preset's own sound — selecting this character applies THIS,
    /// never `CharacterVoiceTable.voice(for:)`, exactly like
    /// `UserCharacter.savedParameters`. `preset.values` is already indexed
    /// by `Param.rawValue` (see `FactoryPresets.swift`'s own doc comment:
    /// "component state = kNumParams float32s"), the same shape
    /// `PresetSnapshot.params`/`UserCharacter.params` already use.
    var savedParameters: [Param: AUValue]? {
        var values = [Param: AUValue]()
        for p in Param.allCases where Int(p.rawValue) < preset.values.count {
            values[p] = preset.values[Int(p.rawValue)]
        }
        return values
    }

    /// Every factory preset, in `kFactoryPresets`' own order — the same
    /// order `AUAudioUnit.factoryPresets` already lists them in for a host
    /// (`PresetTests.testSixFactoryPresetsInOrder`), so a host's numbering
    /// and this app's own list agree on ordering without either having to
    /// know about the other.
    static let all: [FactoryPresetCharacter] = kFactoryPresets.map { FactoryPresetCharacter(preset: $0) }
}
