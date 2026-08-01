import AVFoundation

/// Which of upstream's six factory presets (`kFactoryPresets`, `AU/
/// FactoryPresets.swift` — never edited here) each of MonkSynth's six NEW
/// characters (`DogCharacter`, `GhostCharacter`, `FireFighterCharacter`,
/// `PunkCharacter`, `PizzaCharacter`, `CatCharacter`) sounds like.
///
/// These six don't get a hand-tuned entry in `CharacterVoiceTable` the way
/// the original six (monk, fish, unicorn, girl, old man, cow) do — per the
/// task, "give upstream's six factory sounds their own characters. Do not
/// invent voices for them." Each one's `Character.savedParameters` IS one
/// of the six factory presets, verbatim — the same mechanism
/// `UserCharacter`/the now-deleted `FactoryPresetCharacter` used to apply a
/// patch that bypasses `CharacterVoiceTable.voice(for:)` entirely (see
/// `Character.savedParameters`'s own doc comment).
///
/// Baked as plain data, not computed at runtime, so the mapping stays fixed
/// and inspectable even though it was DERIVED from a measurement: render a
/// held note for each of the six factory presets through the vendored C
/// DSP, take each one's Welch-averaged Hann-windowed spectral centroid (the
/// same method `CharacterVoiceTests`/the deleted `FactoryPresetFaceTests`
/// already used), and rank all six by brightness. That ranking, darkest to
/// brightest, is: Monastary (1175 Hz), Rabten (1344), Dorje (1369), Jamyang
/// (1490), Ngawang (1581), Tinley (1737) — re-measured fresh, not copied
/// from an old comment; see `FactoryVoiceCharacterTests`, which re-runs this
/// exact measurement and asserts the table below still lines up with it.
///
/// Matched to each character's own archetype brightness, per the task:
/// darker/bigger characters get the darker presets (dog gets the single
/// darkest, ghost the next-darkest), brighter/smaller ones get the
/// brighter presets (cat gets the single brightest), and pizza — having no
/// natural vocal pitch of its own, being a slice of food — absorbs
/// whatever's left over once the other five are placed. Fire fighter
/// (burly, deep-voiced) darker than punk (younger, sharper-edged) fills the
/// two remaining middle slots; that relative ordering is a judgement call,
/// not something the centroid measurement alone can decide between two
/// preset values that are already adjacent. See the task report for the one
/// pairing worth flagging as a little on-the-nose: ghost landing on Rabten,
/// which is bit-for-bit upstream's own all-defaults patch — the single most
/// vanilla-sounding of the six, for an ostensibly "spooky" character.
enum FactoryVoiceTable {
    static let presetForCharacter: [String: String] = [
        "dog": "Monastary",
        "ghost": "Rabten",
        "firefighter": "Dorje",
        "punk": "Jamyang",
        "pizza": "Ngawang",
        "cat": "Tinley",
    ]

    /// `characterID`'s assigned factory preset, expressed the same way
    /// `Character.savedParameters` already is elsewhere in this codebase
    /// (`UserCharacter.savedParameters`, the deleted `FactoryPresetCharacter.
    /// savedParameters` before it): every one of the preset's own raw
    /// values, indexed by `Param`. `nil` for a character this table doesn't
    /// recognise — the six original hand-tuned characters (monk, fish,
    /// unicorn, girl, old man, cow) correctly get `nil` here, so their
    /// `Character.savedParameters` default (also `nil`, from `Character`'s
    /// own protocol extension) sends them through
    /// `CharacterVoiceTable.voice(for:)` exactly as before this task.
    static func values(for characterID: String) -> [Param: AUValue]? {
        guard let presetName = presetForCharacter[characterID],
              let preset = kFactoryPresets.first(where: { $0.name == presetName })
        else { return nil }
        var values = [Param: AUValue]()
        for p in Param.allCases where Int(p.rawValue) < preset.values.count {
            values[p] = preset.values[Int(p.rawValue)]
        }
        return values
    }
}
