import AVFoundation

/// A saved user preset's identity as shown in the character dropdown's
/// list: its name and the character it was saved with — "a name and the
/// current character as its face", per the task. `characterID` here is
/// always already resolved through `CharacterRegistry.character(withID:)`
/// by whichever `PresetStoring` conformer produced it, so it never names a
/// character the roster doesn't currently recognise (see that function's
/// fallback-to-monk doc comment) — `UserCharacter` (which wraps exactly
/// this data as a first-class `Character`) can hand it straight to
/// `CharacterRegistry.character(withID:)` without checking first.
struct SavedPreset: Equatable {
    let name: String
    let characterID: String
}

/// Everything needed to reapply a saved preset: the same shape
/// `MonkSynthAU.fullState` already carries (`monkParams` + `characterID`),
/// generalized so the standalone app's own store — which has no
/// `AUAudioUnit`/`fullState` to lean on, see `StandalonePresetStore` — can
/// produce and consume the identical data without any `Data`/AU plumbing of
/// its own.
struct PresetSnapshot {
    /// One value per `Param`, indexed by `Param.rawValue` — always exactly
    /// `Param.allCases.count` long; a conformer reading a short/old blob
    /// pads the remainder with `Param.defaultValue`, mirroring
    /// `MonkSynthAU.fullState`'s own setter (see its "short blob" comment).
    var params: [AUValue]
    var characterID: String
}

/// What a save attempt reports back, driving the character dropdown's
/// inline feedback — see the task's "empty name" / "duplicate name" edge
/// cases.
enum PresetSaveResult: Equatable {
    case success
    case emptyName
    case duplicateName
    case unsupported
    case failed
}

/// Abstracts "where do user presets actually live" over the AUv3 host's own
/// `AUAudioUnit` user-preset machinery (`MonkSynthAU`, backed by
/// `saveUserPreset`/`deleteUserPreset`/`userPresets`/`presetState(for:)` —
/// see that conformance) and the standalone app's own storage
/// (`StandalonePresetStore`, which has no `AUAudioUnit` to lean on) — so
/// `CharacterDropdownView` and its owner (`PluginView`) never need to know
/// which container they're running in. Mirrors the split
/// `PluginView.onOpenURL`/`AudioUnitViewController`/`RootViewController`
/// already draw for "how do I open a URL".
protocol PresetStoring: AnyObject {
    /// Whether saving/deleting user presets is available at all. An AUv3
    /// host can report this false — see `AUAudioUnit.supportsUserPresets`'s
    /// own doc comment, "host applications can use this property to
    /// determine whether to enable UI for saving/deleting user presets" —
    /// and `CharacterDropdownView` must hide its save/delete controls
    /// rather than offer a button that cannot work. The standalone always
    /// supports it: it owns its storage outright.
    var supportsUserPresets: Bool { get }

    /// Every currently saved user preset's name + characterID, in a stable
    /// display order.
    var savedUserPresets: [SavedPreset] { get }

    /// The full params+character for a saved preset, looked up by name —
    /// what `UserCharacter.all(from:)` resolves for every saved entry
    /// before handing it to `CharacterDropdownView` as a row. Nil if `name`
    /// no longer exists (e.g. deleted from under the overlay).
    func snapshot(forUserPresetNamed name: String) -> PresetSnapshot?

    /// Saves whatever is currently loaded — sound and character — as a new
    /// user preset called `name`. Trims surrounding whitespace; empty
    /// (post-trim) or already-taken (case-insensitively, among EXISTING
    /// user presets only — a name that happens to match a factory preset is
    /// fine, factory and user presets are different namespaces) names are
    /// rejected rather than silently saving blank or overwriting.
    @discardableResult
    func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult

    /// Deletes the named user preset, if it still exists. A no-op — not a
    /// crash — if it doesn't (already deleted, or never existed). Deleting
    /// the preset that happens to be currently loaded is fine: whatever
    /// sound/character is already live is untouched, it just stops being
    /// listed.
    func deleteUserPreset(named name: String)
}
