import AVFoundation
import XCTest
@testable import MonkSynth

final class PresetTests: XCTestCase {

    private func makeDescription() -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73,          // 'Mnks'
            componentManufacturer: 0x5673746C,     // 'Vstl'
            componentFlags: 0, componentFlagsMask: 0)
    }

    private func makeAU() throws -> MonkSynthAU {
        try MonkSynthAU(componentDescription: makeDescription())
    }

    func testFullStateRoundTrips() throws {
        let source = try makeAU()
        let attack = source.parameterTree!.parameter(withAddress: Param.attack.rawValue)!
        let level = source.parameterTree!.parameter(withAddress: Param.level.rawValue)!
        attack.value = 0.73
        level.value = 0.21

        let state = source.fullState

        let destination = try makeAU()
        destination.fullState = state

        XCTAssertEqual(param_shadow_get(destination.shadow, kParamAttack), 0.73, accuracy: 1e-5)
        XCTAssertEqual(param_shadow_get(destination.shadow, kParamLevel), 0.21, accuracy: 1e-5)

        // The whole table round-trips, not just the two params that changed.
        for p in Param.allCases {
            XCTAssertEqual(param_shadow_get(destination.shadow, p.address),
                           param_shadow_get(source.shadow, p.address),
                           accuracy: 1e-6, "\(p.name) did not round-trip")
        }
    }

    func testSixFactoryPresetsInOrder() throws {
        let au = try makeAU()
        let names = au.factoryPresets?.map { $0.name }
        XCTAssertEqual(names, ["Dorje", "Jamyang", "Monastary", "Ngawang", "Rabten", "Tinley"])
    }

    func testSelectingPresetUpdatesShadowAndTree() throws {
        let au = try makeAU()
        let preset = try XCTUnwrap(au.factoryPresets?[2])
        XCTAssertEqual(preset.name, "Monastary")

        au.currentPreset = preset

        let expected = kFactoryPresets[2].values
        for (i, want) in expected.enumerated() {
            let addr = Param.address(atIndex: i)
            XCTAssertEqual(param_shadow_get(au.shadow, addr), want, accuracy: 1e-5,
                           "shadow mismatch at index \(i)")
            let treeValue = au.parameterTree!.parameter(withAddress: UInt64(i))!.value
            XCTAssertEqual(treeValue, want, accuracy: 1e-5,
                           "parameter tree mismatch at index \(i)")
        }
    }

    // MARK: - Character selection round-trip

    /// `characterID` rides in `fullState` alongside `monkParams` (see the
    /// characters design doc: cosmetic, not an `AUParameter`, but it must
    /// still travel with sessions and presets).
    func testFullStateRoundTripsCharacterID() throws {
        let source = try makeAU()
        source.setCharacterID(FishCharacter().id)

        let destination = try makeAU()
        destination.fullState = source.fullState

        XCTAssertEqual(destination.characterID, "fish")
    }

    /// A state saved before this task existed has no `"characterID"` key at
    /// all — it must degrade to the default (monk), not crash or leave the
    /// AU in some indeterminate state.
    func testFullStateWithoutCharacterIDYieldsMonk() throws {
        let au = try makeAU()
        au.setCharacterID(FishCharacter().id)

        au.fullState = ["monkParams": Data()]

        XCTAssertEqual(au.characterID, CharacterRegistry.defaultCharacter.id)
    }

    /// A state naming a character id `CharacterRegistry` no longer
    /// recognises (renamed/removed) must also degrade to monk rather than
    /// leaving the AU pointed at a ghost id nothing can render.
    func testFullStateWithUnknownCharacterIDYieldsMonk() throws {
        let au = try makeAU()
        au.fullState = ["characterID": "some-character-that-was-removed"]

        XCTAssertEqual(au.characterID, CharacterRegistry.defaultCharacter.id)
    }

    func testShortStateLeavesRemainingParametersAtDefaults() throws {
        let au = try makeAU()
        let shortValues: [AUValue] = [0.11, 0.22, 0.33]
        let data = shortValues.withUnsafeBufferPointer { Data(buffer: $0) }
        au.fullState = ["monkParams": data]

        XCTAssertEqual(param_shadow_get(au.shadow, kParamPortTime), 0.11, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamVowel), 0.22, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamDelay), 0.33, accuracy: 1e-6)

        // Everything from index 3 onward was never in the blob — still default.
        XCTAssertEqual(param_shadow_get(au.shadow, kParamHeadSize), Param.headSize.defaultValue, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamSustain), Param.sustain.defaultValue, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamLevel), Param.level.defaultValue, accuracy: 1e-6)
        XCTAssertEqual(param_shadow_get(au.shadow, kParamPitchWheelRaw), Param.pitchWheelRaw.defaultValue, accuracy: 1e-6)
    }

    // MARK: - User presets
    //
    // `MonkSynthAU`'s real `userPresetBackend` (`NativeUserPresetBackend`)
    // calls straight through to `AUAudioUnit`'s own native
    // `saveUserPreset`/`userPresets`/`presetState(for:)`/`deleteUserPreset`
    // — but that native machinery's actual disk-backed storage is only
    // reachable from inside a real, installed AU extension process (see the
    // doc comment on `MonkSynthAU`'s "User presets" section: confirmed
    // empirically — instantiated the same way the real extension's own
    // factory function does, `saveUserPreset` neither throws nor persists
    // anything inside a plain XCTest, hosted or not). These tests substitute
    // `FakeUserPresetBackend` — an in-memory stand-in for exactly that native
    // contract (list/read/save/delete `AUAudioUnitPreset`s, `save` capturing
    // whatever `au.fullState` is at that moment, precisely like the real
    // `AUAudioUnit.saveUserPreset(_:)` does) — so the LOGIC `MonkSynthAU`
    // layers on top (name trimming/validation, case-insensitive duplicate
    // detection, characterID/param packing and fallback) is still fully and
    // deterministically covered.

    /// Wires `au` up with two isolated test doubles so these tests never
    /// touch real shared/App-Group or per-container disk state:
    ///
    /// - `userPresetBackend` <- `FakeUserPresetBackend`, an in-memory stand-in
    ///   for `AUAudioUnit`'s native user-preset machinery (see that class's
    ///   own doc comment) — this is the host-visible MIRROR now, not the
    ///   canonical store.
    /// - `presetStore` <- a real `SharedPresetStore` pointed at a fresh
    ///   temp-directory file unique to this call, standing in for the
    ///   canonical shared-App-Group store. Using the real type (rather than
    ///   a hand-rolled fake) exercises its actual save/list/delete/migrate
    ///   logic through every test in this file, exactly like production —
    ///   just isolated to a throwaway file instead of the real container.
    private func makeAUWithFakeBackend() throws -> (au: MonkSynthAU, backend: FakeUserPresetBackend) {
        let au = try makeAU()
        let backend = FakeUserPresetBackend(au)
        au.userPresetBackend = backend
        au.presetStore = SharedPresetStore(fileURL: Self.uniqueTempPresetsFile(), isUsingSharedContainer: false,
                                            currentSnapshot: { [weak au] in Self.currentSnapshot(of: au) })
        return (au, backend)
    }

    private static func uniqueTempPresetsFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("userPresets.json")
    }

    private static func currentSnapshot(of au: MonkSynthAU?) -> PresetSnapshot {
        guard let au else {
            return PresetSnapshot(params: Param.allCases.map(\.defaultValue), characterID: CharacterRegistry.defaultCharacter.id)
        }
        return PresetSnapshot(params: Param.allCases.map { param_shadow_get(au.shadow, $0.address) }, characterID: au.characterID)
    }

    func testSupportsUserPresetsIsTrue() throws {
        let au = try makeAU()
        XCTAssertTrue(au.supportsUserPresets)
    }

    /// "Saving captures the current parameters AND the current character."
    func testSavingCapturesCurrentParametersAndCharacter() throws {
        let (au, _) = try makeAUWithFakeBackend()
        au.parameterTree!.parameter(withAddress: Param.headSize.rawValue)!.value = 0.81
        au.setCharacterID(FishCharacter().id)

        let result = au.saveCurrentAsUserPreset(named: "My Fish Patch")
        XCTAssertEqual(result, .success)

        let snapshot = try XCTUnwrap(au.snapshot(forUserPresetNamed: "My Fish Patch"))
        XCTAssertEqual(snapshot.characterID, "fish")
        XCTAssertEqual(snapshot.params[Int(Param.headSize.rawValue)], 0.81, accuracy: 1e-6)
    }

    /// "The user's saved presets, each showing its name and the character
    /// face it was saved with."
    func testSavedUserPresetsListsNameAndCharacter() throws {
        let (au, _) = try makeAUWithFakeBackend()
        au.setCharacterID(UnicornCharacter().id)
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Sparkly"), .success)

        let saved = au.savedUserPresets
        XCTAssertEqual(saved, [SavedPreset(name: "Sparkly", characterID: "unicorn")])
    }

    /// "Loading restores both" — applying a saved snapshot's params +
    /// character back into a fresh AU (mirroring how
    /// `AudioUnitViewController.onApplyUserPreset` applies one via
    /// `fullState`) reproduces exactly what was saved.
    func testLoadingRestoresParametersAndCharacter() throws {
        let (source, _) = try makeAUWithFakeBackend()
        source.parameterTree!.parameter(withAddress: Param.aspiration.rawValue)!.value = 0.37
        source.setCharacterID(CowCharacter().id)
        XCTAssertEqual(source.saveCurrentAsUserPreset(named: "Loadable"), .success)
        let snapshot = try XCTUnwrap(source.snapshot(forUserPresetNamed: "Loadable"))

        let destination = try makeAU()
        destination.fullState = [
            "monkParams": snapshot.params.withUnsafeBufferPointer { Data(buffer: $0) },
            "characterID": snapshot.characterID,
        ]

        XCTAssertEqual(destination.characterID, "cow")
        XCTAssertEqual(param_shadow_get(destination.shadow, kParamAspiration), 0.37, accuracy: 1e-6)
    }

    /// "Round-trip through fullState preserves characterID" — specifically
    /// through the user-preset path (`testFullStateRoundTripsCharacterID`
    /// above already covers the direct `fullState` case).
    func testRoundTripThroughUserPresetPreservesCharacterID() throws {
        let (au, _) = try makeAUWithFakeBackend()
        au.setCharacterID(GirlCharacter().id)
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Girl Patch"), .success)

        let snapshot = try XCTUnwrap(au.snapshot(forUserPresetNamed: "Girl Patch"))
        XCTAssertEqual(snapshot.characterID, "girl")
    }

    /// "Delete removes it from userPresets."
    func testDeleteRemovesFromSavedUserPresets() throws {
        let (au, _) = try makeAUWithFakeBackend()
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Temporary"), .success)
        XCTAssertEqual(au.savedUserPresets.map(\.name), ["Temporary"])

        au.deleteUserPreset(named: "Temporary")

        XCTAssertTrue(au.savedUserPresets.isEmpty)
    }

    /// Deleting a name that was never saved (or already deleted) is a no-op,
    /// not a crash.
    func testDeletingAnUnknownNameIsANoOp() throws {
        let (au, _) = try makeAUWithFakeBackend()
        au.deleteUserPreset(named: "never existed")
        XCTAssertTrue(au.savedUserPresets.isEmpty)
    }

    /// "Saving with an empty name" — rejected, and nothing is saved.
    func testSavingWithEmptyNameFails() throws {
        let (au, _) = try makeAUWithFakeBackend()
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: ""), .emptyName)
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "   "), .emptyName)
        XCTAssertTrue(au.savedUserPresets.isEmpty)
    }

    /// "...or a name that duplicates an existing preset" — rejected
    /// case-insensitively, and the original is untouched.
    func testSavingWithDuplicateNameFails() throws {
        let (au, _) = try makeAUWithFakeBackend()
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Dupe"), .success)

        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Dupe"), .duplicateName)
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "dupe"), .duplicateName)
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "DUPE"), .duplicateName)
        XCTAssertEqual(au.savedUserPresets.count, 1)
    }

    /// A name that happens to match a FACTORY preset is fine — factory and
    /// user presets are different namespaces.
    func testSavingWithAFactoryPresetsNameSucceeds() throws {
        let (au, _) = try makeAUWithFakeBackend()
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Dorje"), .success)
        XCTAssertEqual(au.savedUserPresets.map(\.name), ["Dorje"])
    }

    /// "An unknown characterID in a loaded preset falls back to monk" — a
    /// preset saved while `characterID` names a character the roster no
    /// longer recognises (simulated via `setCharacterID`, which — unlike
    /// `fullState`'s setter — does not itself validate) must still resolve
    /// to monk when read back.
    func testUnknownCharacterIDInSavedPresetFallsBackToMonk() throws {
        let (au, _) = try makeAUWithFakeBackend()
        au.setCharacterID("some-character-that-was-removed")
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Ghost"), .success)

        let snapshot = try XCTUnwrap(au.snapshot(forUserPresetNamed: "Ghost"))
        XCTAssertEqual(snapshot.characterID, CharacterRegistry.defaultCharacter.id)
        XCTAssertEqual(au.savedUserPresets.first?.characterID, CharacterRegistry.defaultCharacter.id)
    }

    /// `snapshot(forUserPresetNamed:)` for a name that doesn't exist (never
    /// saved, or deleted from under the caller) returns nil rather than
    /// crashing.
    func testSnapshotForUnknownNameReturnsNil() throws {
        let (au, _) = try makeAUWithFakeBackend()
        XCTAssertNil(au.snapshot(forUserPresetNamed: "nope"))
    }

    /// "Factory presets still work and are not clobbered by user presets."
    func testFactoryPresetsStillWorkAlongsideUserPresets() throws {
        let (au, _) = try makeAUWithFakeBackend()
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "One"), .success)
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Two"), .success)

        XCTAssertEqual(au.factoryPresets?.map(\.name), ["Dorje", "Jamyang", "Monastary", "Ngawang", "Rabten", "Tinley"])

        let monastary = try XCTUnwrap(au.factoryPresets?[2])
        au.currentPreset = monastary
        let expected = kFactoryPresets[2].values
        for (i, want) in expected.enumerated() {
            XCTAssertEqual(param_shadow_get(au.shadow, Param.address(atIndex: i)), want, accuracy: 1e-5)
        }
        XCTAssertEqual(au.savedUserPresets.map(\.name).sorted(), ["One", "Two"])
    }

    // MARK: - Host-visible mirroring
    //
    // `presetStore` (the shared App Group store, faked above to an isolated
    // temp file) is canonical; `userPresetBackend` is a best-effort MIRROR
    // so a host's own `AUAudioUnit.userPresets` UI keeps listing saves too.
    // These tests check the mirror actually happens, and that a mirror
    // failure never blocks or un-succeeds the canonical save/delete.

    /// A save lands in BOTH the canonical store and the native mirror.
    func testSaveMirrorsIntoNativeUserPresets() throws {
        let (au, backend) = try makeAUWithFakeBackend()
        au.setCharacterID(FishCharacter().id)

        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Mirrored"), .success)

        XCTAssertEqual(backend.all.map(\.name), ["Mirrored"])
        let mirroredState = try backend.state(for: XCTUnwrap(backend.all.first))
        XCTAssertEqual(mirroredState["characterID"] as? String, "fish")
    }

    /// A delete removes it from BOTH the canonical store and the native
    /// mirror — not just the canonical one.
    func testDeleteMirrorsIntoNativeUserPresets() throws {
        let (au, backend) = try makeAUWithFakeBackend()
        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "Temp"), .success)
        XCTAssertEqual(backend.all.map(\.name), ["Temp"])

        au.deleteUserPreset(named: "Temp")

        XCTAssertTrue(au.savedUserPresets.isEmpty)
        XCTAssertTrue(backend.all.isEmpty)
    }

    /// If the native mirror throws (a host that declines, a sandbox
    /// hiccup), the canonical save still reports `.success` — the shared
    /// store is what actually makes the preset visible across containers,
    /// and it already has it; a host-UI mirroring failure is logged, not
    /// surfaced as a save failure.
    func testMirrorFailureDoesNotFailTheCanonicalSave() throws {
        let au = try makeAU()
        au.userPresetBackend = AlwaysFailingUserPresetBackend()
        au.presetStore = SharedPresetStore(fileURL: Self.uniqueTempPresetsFile(), isUsingSharedContainer: false,
                                            currentSnapshot: { [weak au] in Self.currentSnapshot(of: au) })

        XCTAssertEqual(au.saveCurrentAsUserPreset(named: "StillSaved"), .success)
        XCTAssertEqual(au.savedUserPresets.map(\.name), ["StillSaved"])

        au.deleteUserPreset(named: "StillSaved")   // must not crash even though the mirror has nothing to delete
        XCTAssertTrue(au.savedUserPresets.isEmpty)
    }
}

/// In-memory stand-in for `NativeUserPresetBackend` — see `MonkSynthAU`'s
/// "User presets" section doc comment. Mirrors the real
/// `AUAudioUnit.saveUserPreset(_:)` contract exactly: `save` captures
/// whatever `au.fullState` is AT THE MOMENT it's called, not anything passed
/// in separately.
final class FakeUserPresetBackend: UserPresetBackend {
    private unowned let au: MonkSynthAU
    private var entries: [(preset: AUAudioUnitPreset, state: [String: Any])] = []

    init(_ au: MonkSynthAU) { self.au = au }

    var all: [AUAudioUnitPreset] { entries.map(\.preset) }

    func state(for preset: AUAudioUnitPreset) throws -> [String: Any] {
        guard let entry = entries.first(where: { $0.preset.name == preset.name }) else {
            throw NSError(domain: "FakeUserPresetBackend", code: 1)
        }
        return entry.state
    }

    func save(_ preset: AUAudioUnitPreset) throws {
        entries.removeAll { $0.preset.name == preset.name }
        entries.append((preset, au.fullState ?? [:]))
    }

    func delete(_ preset: AUAudioUnitPreset) throws {
        entries.removeAll { $0.preset.name == preset.name }
    }
}

/// A `UserPresetBackend` that always throws on save/delete and always lists
/// nothing — standing in for a host that declines native user-preset
/// mirroring (or a sandbox hiccup), for `testMirrorFailureDoesNotFailTheCanonicalSave`.
private final class AlwaysFailingUserPresetBackend: UserPresetBackend {
    private struct Failure: Error {}
    var all: [AUAudioUnitPreset] { [] }
    func state(for preset: AUAudioUnitPreset) throws -> [String: Any] { throw Failure() }
    func save(_ preset: AUAudioUnitPreset) throws { throw Failure() }
    func delete(_ preset: AUAudioUnitPreset) throws { throw Failure() }
}
