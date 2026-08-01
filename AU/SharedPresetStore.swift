import Foundation

/// User presets, canonically stored in the `group.com.vestal.monksynth` App
/// Group container so the standalone app and the AUv3 extension — two
/// separate iOS sandboxes, never the same process, and both potentially
/// alive at once (a host with the AUv3 loaded while the standalone is also
/// open) — see and can edit the exact same preset bank. Mirrors NuSaw's own
/// `userPresetDir()` (`nusaw-plugin/source/PluginProcessor.cpp`): "The
/// Standalone app and the AUv3 extension run in separate iOS sandboxes; a
/// shared App Group container is the only place both can see the same
/// presets."
///
/// **Falls back exactly like NuSaw does.** An app-group entitlement with no
/// consumer previously broke `xcodebuild archive` outright in this project
/// (provisioning profile doesn't include the App Groups capability) — see
/// the design doc's "add one back only when a task actually needs a shared
/// container" note. Now there is a real consumer, but provisioning can still
/// misbehave (entitlement not yet propagated to a provisioning profile,
/// unsigned/simulator build, etc). Rather than trust that away, this store
/// asks `FileManager` for the group container and, if that comes back nil,
/// falls back to this process's own per-container Documents directory —
/// exactly NuSaw's `legacyDocsPresetDir()` fallback. Either way presets keep
/// working; only cross-container sharing is lost until the container is
/// available. `isUsingSharedContainer` reports which path is live, and the
/// choice is logged once at init.
final class SharedPresetStore: PresetStoring {

    /// On-disk shape of one preset — the same name+characterID+params
    /// contract every `PresetStoring` conformer in this app uses (see
    /// `StandalonePresetStore`'s identical private `StoredPreset`), but
    /// `internal` here (not `private`) rather than `private`: both
    /// `MonkSynthAU`'s native-preset migration and any legacy-JSON migration
    /// need to construct these directly from data another store already
    /// produced, without re-deriving this exact shape a third time.
    struct StoredPreset: Codable, Equatable {
        var name: String
        var characterID: String
        var params: [Float]
    }

    static let appGroupIdentifier = "group.com.vestal.monksynth"

    /// `true` when this instance is actually backed by the shared App Group
    /// container; `false` when it fell back to this process's own sandboxed
    /// Documents directory because the container was unavailable. Never
    /// changes after init — logged there, and exposed for callers/tests that
    /// want to confirm which path is live without re-deriving it.
    let isUsingSharedContainer: Bool

    private let fileURL: URL
    private let currentSnapshot: () -> PresetSnapshot
    // A fresh coordinator per store rather than a shared singleton: cheap to
    // construct, and keeps this type free of any shared mutable state beyond
    // the file itself (which is exactly what coordination protects).
    private let coordinator = NSFileCoordinator()

    /// Production entry point: resolves the App Group container via
    /// `FileManager`, falling back to this container's own Documents
    /// directory if the group is unavailable. See the type doc comment.
    convenience init(fileManager: FileManager = .default,
                      currentSnapshot: @escaping () -> PresetSnapshot) {
        let resolved = Self.resolveFileURL(fileManager: fileManager)
        self.init(fileURL: resolved.url, isUsingSharedContainer: resolved.isShared,
                  currentSnapshot: currentSnapshot)
        NSLog("MonkSynth: user presets store using %@ (%@)",
              isUsingSharedContainer ? "the shared App Group container" : "this app's own local storage (App Group unavailable — fallback)",
              fileURL.path)
    }

    /// Test/advanced seam: point directly at a known file. Two instances
    /// constructed with the same `fileURL` behave exactly like the
    /// standalone app and the AUv3 extension sharing one App Group
    /// container — this is how the cross-container-visibility tests
    /// simulate that without needing two real processes.
    init(fileURL: URL, isUsingSharedContainer: Bool, currentSnapshot: @escaping () -> PresetSnapshot) {
        self.fileURL = fileURL
        self.isUsingSharedContainer = isUsingSharedContainer
        self.currentSnapshot = currentSnapshot
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func resolveFileURL(fileManager: FileManager) -> (url: URL, isShared: Bool) {
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let dir = group.appendingPathComponent("Presets", isDirectory: true)
            return (dir.appendingPathComponent("userPresets.json"), true)
        }
        // Fallback: this process's own sandboxed Documents — no TCC prompt
        // there (unlike macOS), and it always exists. Mirrors NuSaw's
        // `legacyDocsPresetDir()` fallback exactly.
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Presets", isDirectory: true)
        return (dir.appendingPathComponent("userPresets.json"), false)
    }

    // MARK: - PresetStoring

    var supportsUserPresets: Bool { true }

    var savedUserPresets: [SavedPreset] {
        readAll()
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SavedPreset(name: $0.name, characterID: CharacterRegistry.character(withID: $0.characterID).id) }
    }

    func snapshot(forUserPresetNamed name: String) -> PresetSnapshot? {
        guard let stored = readAll().first(where: { $0.name == name }) else { return nil }
        // Mirrors `MonkSynthAU.fullState`/`StandalonePresetStore`'s own
        // short/old-blob handling: any index the stored array doesn't cover
        // keeps `Param.defaultValue`.
        var values = Param.allCases.map(\.defaultValue)
        for (i, v) in stored.params.enumerated() where i < values.count { values[i] = v }
        return PresetSnapshot(params: values, characterID: CharacterRegistry.character(withID: stored.characterID).id)
    }

    @discardableResult
    func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }

        // Captured before entering the coordinated section: this is "what
        // THIS process currently has loaded," not shared state, so there is
        // nothing to race against by reading it early.
        let snapshot = currentSnapshot()
        var result = PresetSaveResult.success
        mutate { all in
            guard !all.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                result = .duplicateName
                return all
            }
            var copy = all
            copy.append(StoredPreset(name: trimmed, characterID: snapshot.characterID, params: snapshot.params))
            return copy
        }
        return result
    }

    func deleteUserPreset(named name: String) {
        mutate { all in
            var copy = all
            copy.removeAll { $0.name == name }
            return copy
        }
    }

    // MARK: - Migration
    //
    // "Existing presets must survive" — anyone already running a build has
    // presets in `UserDefaults` (standalone, see `StandalonePresetStore`) or
    // native `AUAudioUnit.userPresets` (AUv3, see `MonkSynthAU`). Each side
    // calls this once, at its own store-construction time, with its own
    // legacy presets already read out of its own old storage — this type
    // has no idea `UserDefaults`/`AUAudioUnit` even exist, it only knows how
    // to fold a list of `StoredPreset` into itself without duplicating.
    //
    // Guarded by a `UserDefaults` marker (per `markerKey`, so the standalone
    // and AUv3 migrations — reading from two different legacy sources — each
    // get their own one-time flag and never re-run or trip over each other)
    // rather than by "does the shared store already have a preset with this
    // name": a user who legitimately deletes an imported preset after
    // migration should not see it reappear on the next launch just because
    // the shared store no longer has that name. The per-name duplicate
    // check below exists only to protect a single migration run against
    // whatever's already in the shared store at that moment (e.g. a preset
    // of the same name saved from the other container in between).

    /// Runs at most once (across all launches, tracked via `markerKey` in
    /// `defaults`): folds every entry in `legacy` that doesn't already exist
    /// (case-insensitive name match) into this store. Safe to call every
    /// launch — after the first successful run it is an immediate no-op.
    @discardableResult
    func migrateLegacyPresetsIfNeeded(
        _ legacy: [StoredPreset], markerKey: String, defaults: UserDefaults = .standard
    ) -> Int {
        guard !defaults.bool(forKey: markerKey) else { return 0 }
        guard !legacy.isEmpty else {
            defaults.set(true, forKey: markerKey)
            return 0
        }

        var imported = 0
        mutate { all in
            var copy = all
            for preset in legacy
            where !copy.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
                copy.append(preset)
                imported += 1
            }
            return copy
        }
        defaults.set(true, forKey: markerKey)
        return imported
    }

    // MARK: - Storage (coordinated + atomic)
    //
    // Both processes coordinate every read and write through
    // `NSFileCoordinator` — Apple's own mechanism for exactly this
    // situation (an app and its extension sharing one App Group file), not
    // limited to iCloud-backed files. A `.forReplacing` write acquires
    // exclusive access to `fileURL` for the duration of the accessor block,
    // system-wide, across processes; any other coordinated reader/writer for
    // the same URL waits. Read-modify-write happens entirely inside that one
    // locked block (fresh read of whatever is on disk RIGHT NOW, not
    // whatever an earlier uncoordinated read saw), so two saves racing from
    // the standalone and the AUv3 extension serialize instead of one
    // clobbering the other. The write itself is additionally atomic
    // (`Data.write(options: .atomic)`, write-to-temp-then-rename under the
    // hood) so a reader can never observe a half-written file even outside
    // coordination (e.g. a process that isn't cooperating, or a crash
    // mid-write).

    private func readAll() -> [StoredPreset] {
        var result: [StoredPreset] = []
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            result = (try? JSONDecoder().decode([StoredPreset].self, from: data)) ?? []
        }
        if let coordError { NSLog("MonkSynth: user presets read coordination failed: \(coordError)") }
        return result
    }

    private func mutate(_ transform: ([StoredPreset]) -> [StoredPreset]) {
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: [.forReplacing], error: &coordError) { url in
            let current = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode([StoredPreset].self, from: $0) } ?? []
            let updated = transform(current)
            guard let data = try? JSONEncoder().encode(updated) else { return }
            try? data.write(to: url, options: .atomic)
        }
        if let coordError { NSLog("MonkSynth: user presets write coordination failed: \(coordError)") }
    }
}
