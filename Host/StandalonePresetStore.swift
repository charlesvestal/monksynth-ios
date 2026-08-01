import Foundation

/// The standalone app's own equivalent of `MonkSynthAU`'s
/// `PresetStoring` conformance: `RootViewController` has no `AUAudioUnit`/
/// host to lean on for `saveUserPreset`/`userPresets`/etc, so this
/// reimplements the same name+characterID+params contract (list, save,
/// delete) with its own storage instead — `UserDefaults`, `Codable`-encoded,
/// mirroring `RootViewController`'s existing `characterIDDefaultsKey`
/// pattern for "no host to ride along with, so persist it ourselves."
///
/// Unlike `MonkSynthAU` (which always has a live `fullState` to read at save
/// time), this store has no notion of "current" on its own — `currentSnapshot`
/// supplies it on demand, exactly the same "read whatever is live right now"
/// shape `AUAudioUnit.saveUserPreset(_:)` itself uses internally.
final class StandalonePresetStore: PresetStoring {

    private struct StoredPreset: Codable {
        var name: String
        var characterID: String
        var params: [Float]
    }

    private static let defaultsKey = "userPresets"

    private let defaults: UserDefaults
    private let currentSnapshot: () -> PresetSnapshot

    init(defaults: UserDefaults = .standard, currentSnapshot: @escaping () -> PresetSnapshot) {
        self.defaults = defaults
        self.currentSnapshot = currentSnapshot
    }

    // MARK: - PresetStoring

    /// Always true: unlike an AUv3 host (which can decline to support user
    /// presets — see `AUAudioUnit.supportsUserPresets`), the standalone owns
    /// its storage outright and can always write to it.
    var supportsUserPresets: Bool { true }

    var savedUserPresets: [SavedPreset] {
        loadAll()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SavedPreset(name: $0.name, characterID: CharacterRegistry.character(withID: $0.characterID).id) }
    }

    func snapshot(forUserPresetNamed name: String) -> PresetSnapshot? {
        guard let stored = loadAll().first(where: { $0.name == name }) else { return nil }
        // Mirrors `MonkSynthAU`'s own short/old-blob handling: any index the
        // stored array doesn't cover keeps `Param.defaultValue`.
        var values = Param.allCases.map(\.defaultValue)
        for (i, v) in stored.params.enumerated() where i < values.count { values[i] = v }
        return PresetSnapshot(params: values, characterID: CharacterRegistry.character(withID: stored.characterID).id)
    }

    @discardableResult
    func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        var all = loadAll()
        guard !all.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return .duplicateName }

        let snapshot = currentSnapshot()
        all.append(StoredPreset(name: trimmed, characterID: snapshot.characterID, params: snapshot.params))
        saveAll(all)
        return .success
    }

    func deleteUserPreset(named name: String) {
        var all = loadAll()
        all.removeAll { $0.name == name }
        saveAll(all)
    }

    // MARK: - Storage

    private func loadAll() -> [StoredPreset] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([StoredPreset].self, from: data)) ?? []
    }

    private func saveAll(_ presets: [StoredPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
