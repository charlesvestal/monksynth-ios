import XCTest
import AVFoundation
@testable import MonkSynth

/// Covers `StandalonePresetStore` — the standalone app's own equivalent of
/// `MonkSynthAU`'s `PresetStoring` conformance, backed by `UserDefaults`
/// instead of `AUAudioUnit`'s native user-preset machinery (see that type's
/// doc comment). Unlike `MonkSynthAU`'s user-preset storage (only reachable
/// from inside a real, installed AU extension process — see `PresetTests`'s
/// doc comment), `UserDefaults` is a completely ordinary, always-functional
/// API, so these tests exercise the REAL store directly, no fake needed.
///
/// `StandalonePresetStore` lives in `Host/`, so it's only ever compiled into
/// the `MonkSynth` app module — this file reaches it only through
/// `@testable import MonkSynth`, and never also constructs a bare
/// `PresetSnapshot`/`SavedPreset` literal (this test TARGET directly
/// compiles its own second copy of `AU/PresetStore.swift` too — see
/// `LocalEngineTests`'s own doc comment on the same duplication — so an
/// unqualified `PresetSnapshot(...)` here would resolve to the wrong,
/// locally-compiled type). Where a `PresetSnapshot` literal genuinely has to
/// be constructed (feeding `StandalonePresetStore`'s `currentSnapshot`
/// closure), it's explicitly qualified as `MonkSynth.PresetSnapshot` to name
/// the imported module's type, not the local one.
final class StandalonePresetStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "StandalonePresetStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = nil
        try super.tearDownWithError()
    }

    private func makeStore(characterID: String = "monk", firstParam: Float = 0) -> StandalonePresetStore {
        StandalonePresetStore(defaults: defaults, currentSnapshot: {
            var params = Param.allCases.map(\.defaultValue)
            params[0] = firstParam
            return MonkSynth.PresetSnapshot(params: params, characterID: characterID)
        })
    }

    func testSupportsUserPresetsIsAlwaysTrue() {
        XCTAssertTrue(makeStore().supportsUserPresets)
    }

    /// "Saving captures the current parameters AND the current character."
    func testSaveCapturesCurrentSnapshot() {
        let store = makeStore(characterID: "fish", firstParam: 0.42)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Fishy"), .success)

        let snapshot = store.snapshot(forUserPresetNamed: "Fishy")
        XCTAssertEqual(snapshot?.characterID, "fish")
        XCTAssertEqual(snapshot?.params.first, 0.42)
    }

    func testSavedUserPresetsShowsNameAndCharacter() {
        let store = makeStore(characterID: "unicorn")
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Sparkly"), .success)

        XCTAssertEqual(store.savedUserPresets.map(\.name), ["Sparkly"])
        XCTAssertEqual(store.savedUserPresets.map(\.characterID), ["unicorn"])
    }

    /// "Loading restores both" — the returned snapshot carries everything
    /// needed to reapply params + character.
    func testSnapshotForNamedRestoresParamsAndCharacter() {
        let store = makeStore(characterID: "cow", firstParam: 0.77)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Moo"), .success)

        let snapshot = store.snapshot(forUserPresetNamed: "Moo")
        XCTAssertEqual(snapshot?.characterID, "cow")
        XCTAssertEqual(snapshot?.params.first, 0.77)
        XCTAssertEqual(snapshot?.params.count, Param.allCases.count)
    }

    /// "Delete removes it from userPresets."
    func testDeleteRemovesIt() {
        let store = makeStore()
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Temp"), .success)
        XCTAssertEqual(store.savedUserPresets.map(\.name), ["Temp"])

        store.deleteUserPreset(named: "Temp")

        XCTAssertTrue(store.savedUserPresets.isEmpty)
        XCTAssertNil(store.snapshot(forUserPresetNamed: "Temp"))
    }

    func testDeletingAnUnknownNameIsANoOp() {
        let store = makeStore()
        store.deleteUserPreset(named: "never existed")
        XCTAssertTrue(store.savedUserPresets.isEmpty)
    }

    /// "Saving with an empty name" — rejected, nothing saved.
    func testEmptyNameFails() {
        let store = makeStore()
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: ""), .emptyName)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "   "), .emptyName)
        XCTAssertTrue(store.savedUserPresets.isEmpty)
    }

    /// "...or a name that duplicates an existing preset" — rejected
    /// case-insensitively.
    func testDuplicateNameFails() {
        let store = makeStore()
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Dupe"), .success)

        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Dupe"), .duplicateName)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "DUPE"), .duplicateName)
        XCTAssertEqual(store.savedUserPresets.count, 1)
    }

    /// "An unknown characterID in a loaded preset falls back to monk" —
    /// simulated by seeding storage directly with a characterID the roster
    /// doesn't recognise (mirroring an old save from before a roster
    /// change), bypassing `currentSnapshot`, which — like a live
    /// `pluginView.stage.character` — can only ever name a real character.
    func testUnknownCharacterIDFallsBackToMonkOnRead() throws {
        let store = makeStore()
        // Seed storage directly (same on-disk shape `StandalonePresetStore`
        // itself writes) rather than going through `saveCurrentAsUserPreset`,
        // which can only ever capture a currently-real character id.
        let payload = """
        [{"name":"Ghost","characterID":"some-character-that-was-removed","params":[]}]
        """.data(using: .utf8)!
        defaults.set(payload, forKey: "userPresets")

        let snapshot = try XCTUnwrap(store.snapshot(forUserPresetNamed: "Ghost"))
        XCTAssertEqual(snapshot.characterID, CharacterRegistry.defaultCharacter.id)
        XCTAssertEqual(store.savedUserPresets.first?.characterID, CharacterRegistry.defaultCharacter.id)
    }

    /// A short/old params array (fewer than `Param.allCases.count` entries)
    /// leaves the remainder at `Param.defaultValue`, mirroring
    /// `MonkSynthAU.fullState`'s own short-blob handling.
    func testShortParamsArrayLeavesRemainderAtDefaults() throws {
        let store = makeStore()
        let payload = """
        [{"name":"Short","characterID":"monk","params":[0.11,0.22]}]
        """.data(using: .utf8)!
        defaults.set(payload, forKey: "userPresets")

        let snapshot = try XCTUnwrap(store.snapshot(forUserPresetNamed: "Short"))
        XCTAssertEqual(snapshot.params[0], 0.11, accuracy: 1e-6)
        XCTAssertEqual(snapshot.params[1], 0.22, accuracy: 1e-6)
        XCTAssertEqual(snapshot.params[2], Param.allCases[2].defaultValue, accuracy: 1e-6)
    }

    func testSnapshotForUnknownNameReturnsNil() {
        let store = makeStore()
        XCTAssertNil(store.snapshot(forUserPresetNamed: "nope"))
    }

    /// Independent `StandalonePresetStore` instances sharing the same
    /// `UserDefaults` see each other's writes — the whole point of using
    /// `UserDefaults` rather than in-memory state, mirroring how a real
    /// `RootViewController` session persists across relaunches.
    func testPersistsAcrossStoreInstancesSharingTheSameDefaults() {
        let first = makeStore(characterID: "girl")
        XCTAssertEqual(first.saveCurrentAsUserPreset(named: "Persisted"), .success)

        let second = StandalonePresetStore(defaults: defaults, currentSnapshot: {
            MonkSynth.PresetSnapshot(params: Param.allCases.map(\.defaultValue), characterID: "monk")
        })
        XCTAssertEqual(second.savedUserPresets.map(\.name), ["Persisted"])
        XCTAssertEqual(second.snapshot(forUserPresetNamed: "Persisted")?.characterID, "girl")
    }
}
