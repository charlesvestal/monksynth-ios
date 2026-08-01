import AVFoundation
import XCTest
@testable import MonkSynth

/// Covers `SharedPresetStore` — the canonical, App-Group-backed preset
/// store both `MonkSynthAU` and `RootViewController` delegate to (see that
/// type's doc comment). Every test here uses a throwaway temp-directory file
/// (or a fake `FileManager`) instead of the real App Group container, so
/// these never depend on — or pollute — real device/simulator shared state.
final class SharedPresetStoreTests: XCTestCase {

    private func uniqueFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedPresetStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("userPresets.json")
    }

    private func makeStore(fileURL: URL, characterID: String = "monk", firstParam: Float = 0) -> SharedPresetStore {
        SharedPresetStore(fileURL: fileURL, isUsingSharedContainer: false, currentSnapshot: {
            var params = Param.allCases.map(\.defaultValue)
            params[0] = firstParam
            return PresetSnapshot(params: params, characterID: characterID)
        })
    }

    // MARK: - Basic contract (mirrors StandalonePresetStoreTests / PresetTests
    // for commit 45ac936's edge cases, applied to the new canonical store)

    func testSupportsUserPresetsIsAlwaysTrue() {
        XCTAssertTrue(makeStore(fileURL: uniqueFileURL()).supportsUserPresets)
    }

    func testSaveCapturesCurrentSnapshot() {
        let store = makeStore(fileURL: uniqueFileURL(), characterID: "fish", firstParam: 0.42)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Fishy"), .success)

        let snapshot = store.snapshot(forUserPresetNamed: "Fishy")
        XCTAssertEqual(snapshot?.characterID, "fish")
        XCTAssertEqual(snapshot?.params.first, 0.42)
    }

    func testEmptyNameFails() {
        let store = makeStore(fileURL: uniqueFileURL())
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: ""), .emptyName)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "   "), .emptyName)
        XCTAssertTrue(store.savedUserPresets.isEmpty)
    }

    func testDuplicateNameFailsCaseInsensitively() {
        let store = makeStore(fileURL: uniqueFileURL())
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Dupe"), .success)

        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Dupe"), .duplicateName)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "DUPE"), .duplicateName)
        XCTAssertEqual(store.savedUserPresets.count, 1)
    }

    func testDeleteRemovesItAndUnknownNameIsANoOp() {
        let store = makeStore(fileURL: uniqueFileURL())
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Temp"), .success)

        store.deleteUserPreset(named: "Temp")
        XCTAssertTrue(store.savedUserPresets.isEmpty)

        store.deleteUserPreset(named: "never existed")   // must not crash
        XCTAssertTrue(store.savedUserPresets.isEmpty)
    }

    func testUnknownCharacterIDFallsBackToMonkOnRead() throws {
        let url = uniqueFileURL()
        let store = makeStore(fileURL: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = """
        [{"name":"Ghost","characterID":"some-character-that-was-removed","params":[]}]
        """.data(using: .utf8)!
        try payload.write(to: url)

        let snapshot = try XCTUnwrap(store.snapshot(forUserPresetNamed: "Ghost"))
        XCTAssertEqual(snapshot.characterID, CharacterRegistry.defaultCharacter.id)
        XCTAssertEqual(store.savedUserPresets.first?.characterID, CharacterRegistry.defaultCharacter.id)
    }

    func testShortParamsArrayLeavesRemainderAtDefaults() throws {
        let url = uniqueFileURL()
        let store = makeStore(fileURL: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = """
        [{"name":"Short","characterID":"monk","params":[0.11,0.22]}]
        """.data(using: .utf8)!
        try payload.write(to: url)

        let snapshot = try XCTUnwrap(store.snapshot(forUserPresetNamed: "Short"))
        XCTAssertEqual(snapshot.params[0], 0.11, accuracy: 1e-6)
        XCTAssertEqual(snapshot.params[1], 0.22, accuracy: 1e-6)
        XCTAssertEqual(snapshot.params[2], Param.allCases[2].defaultValue, accuracy: 1e-6)
    }

    // MARK: - Cross-container visibility
    //
    // "Saving in one container is visible from the other" — simulated
    // exactly as the task suggests: two independent `SharedPresetStore`
    // instances pointed at the same file, standing in for the standalone
    // app and the AUv3 extension sharing one App Group container.

    func testSavingInOneInstanceIsVisibleFromAnotherPointedAtTheSameFile() {
        let url = uniqueFileURL()
        let standaloneSide = makeStore(fileURL: url, characterID: "unicorn", firstParam: 0.9)
        let auSide = makeStore(fileURL: url, characterID: "cow", firstParam: 0.1)

        XCTAssertEqual(standaloneSide.saveCurrentAsUserPreset(named: "FromStandalone"), .success)

        // The AUv3 side sees it without ever having saved it itself.
        XCTAssertEqual(auSide.savedUserPresets.map(\.name), ["FromStandalone"])
        XCTAssertEqual(auSide.snapshot(forUserPresetNamed: "FromStandalone")?.characterID, "unicorn")

        // And the reverse direction.
        XCTAssertEqual(auSide.saveCurrentAsUserPreset(named: "FromAU"), .success)
        XCTAssertEqual(standaloneSide.savedUserPresets.map(\.name).sorted(), ["FromAU", "FromStandalone"])
        XCTAssertEqual(standaloneSide.snapshot(forUserPresetNamed: "FromAU")?.characterID, "cow")

        // A delete from one side is seen by the other too.
        auSide.deleteUserPreset(named: "FromStandalone")
        XCTAssertEqual(standaloneSide.savedUserPresets.map(\.name), ["FromAU"])
    }

    // MARK: - Fallback when the App Group container is unavailable
    //
    // "The app must never lose the ability to save a preset because
    // provisioning misbehaved." A `FileManager` subclass stands in for
    // `containerURL(forSecurityApplicationGroupIdentifier:)` returning nil
    // — entitlement missing, unsigned build, simulator quirk — exactly the
    // condition the production initializer branches on.

    func testFallsBackToLocalStorageWhenAppGroupContainerIsUnavailable() {
        let fileManager = NilGroupContainerFileManager()
        let store = SharedPresetStore(fileManager: fileManager, currentSnapshot: {
            PresetSnapshot(params: Param.allCases.map(\.defaultValue), characterID: "monk")
        })

        XCTAssertFalse(store.isUsingSharedContainer)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "StillWorks"), .success)
        XCTAssertEqual(store.savedUserPresets.map(\.name), ["StillWorks"])
    }

    func testUsesTheSharedContainerWhenAvailable() {
        let groupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeAppGroup-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FixedGroupContainerFileManager(containerURL: groupDir)
        let store = SharedPresetStore(fileManager: fileManager, currentSnapshot: {
            PresetSnapshot(params: Param.allCases.map(\.defaultValue), characterID: "monk")
        })

        XCTAssertTrue(store.isUsingSharedContainer)
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Shared"), .success)
        // Actually landed under the fake group container, not somewhere else.
        XCTAssertTrue(FileManager.default.fileExists(atPath: groupDir.appendingPathComponent("Presets/userPresets.json").path))
    }

    // MARK: - Migration
    //
    // "Migrate them into the shared store on first run, once, without
    // duplicating on subsequent launches."

    func testMigrationImportsLegacyPresetsOnce() {
        let store = makeStore(fileURL: uniqueFileURL())
        let defaults = UserDefaults(suiteName: "SharedPresetStoreTests-migration-\(UUID().uuidString)")!
        let legacy = [
            SharedPresetStore.StoredPreset(name: "Old One", characterID: "girl", params: [0.5]),
            SharedPresetStore.StoredPreset(name: "Old Two", characterID: "fish", params: [0.25]),
        ]

        let firstRunImported = store.migrateLegacyPresetsIfNeeded(legacy, markerKey: "migrated", defaults: defaults)
        XCTAssertEqual(firstRunImported, 2)
        XCTAssertEqual(store.savedUserPresets.map(\.name).sorted(), ["Old One", "Old Two"])

        // A second run (e.g. the next launch) is a no-op — nothing imported
        // again, nothing duplicated.
        let secondRunImported = store.migrateLegacyPresetsIfNeeded(legacy, markerKey: "migrated", defaults: defaults)
        XCTAssertEqual(secondRunImported, 0)
        XCTAssertEqual(store.savedUserPresets.count, 2)
    }

    /// A legacy entry whose name already exists in the shared store (saved
    /// from the other container in between) is skipped, not duplicated.
    func testMigrationSkipsNamesAlreadyPresentInTheSharedStore() {
        let store = makeStore(fileURL: uniqueFileURL())
        XCTAssertEqual(store.saveCurrentAsUserPreset(named: "Existing"), .success)
        let defaults = UserDefaults(suiteName: "SharedPresetStoreTests-migration-\(UUID().uuidString)")!

        let legacy = [SharedPresetStore.StoredPreset(name: "existing", characterID: "cow", params: [])]
        let imported = store.migrateLegacyPresetsIfNeeded(legacy, markerKey: "migrated", defaults: defaults)

        XCTAssertEqual(imported, 0)
        XCTAssertEqual(store.savedUserPresets.count, 1)
    }

    /// Two DIFFERENT legacy sources (standalone's old `UserDefaults` store,
    /// the AUv3's old native `userPresets`) each get their own marker key,
    /// so migrating one never blocks the other.
    func testDistinctMarkerKeysMigrateIndependently() {
        let store = makeStore(fileURL: uniqueFileURL())
        let defaults = UserDefaults(suiteName: "SharedPresetStoreTests-migration-\(UUID().uuidString)")!

        let standaloneLegacy = [SharedPresetStore.StoredPreset(name: "FromStandalone", characterID: "monk", params: [])]
        let auLegacy = [SharedPresetStore.StoredPreset(name: "FromAU", characterID: "monk", params: [])]

        XCTAssertEqual(store.migrateLegacyPresetsIfNeeded(standaloneLegacy, markerKey: "migratedStandalone", defaults: defaults), 1)
        XCTAssertEqual(store.migrateLegacyPresetsIfNeeded(auLegacy, markerKey: "migratedAU", defaults: defaults), 1)

        XCTAssertEqual(store.savedUserPresets.map(\.name).sorted(), ["FromAU", "FromStandalone"])
    }

    // MARK: - Concurrency
    //
    // "Concurrent writes do not corrupt the file." Multiple `SharedPresetStore`
    // instances (standing in for separate processes) all pointed at the same
    // file, writing at once from concurrent queues.

    func testConcurrentSavesFromDistinctNamesAllSucceedWithoutCorruption() {
        let url = uniqueFileURL()
        let count = 20
        let stores = (0..<count).map { _ in makeStore(fileURL: url) }

        DispatchQueue.concurrentPerform(iterations: count) { i in
            XCTAssertEqual(stores[i].saveCurrentAsUserPreset(named: "Concurrent\(i)"), .success)
        }

        // A fresh instance reads back exactly what was written — every save
        // landed, and the file is valid JSON (a corrupted file would decode
        // to fewer entries or fail to decode at all, both caught here).
        let verifier = makeStore(fileURL: url)
        XCTAssertEqual(verifier.savedUserPresets.count, count)
        XCTAssertEqual(Set(verifier.savedUserPresets.map(\.name)), Set((0..<count).map { "Concurrent\($0)" }))
    }

    /// The harder case: many writers race to save under the SAME name.
    /// Coordinated read-modify-write means exactly one wins; every other
    /// caller observes `.duplicateName` rather than silently overwriting or
    /// double-inserting.
    func testConcurrentSavesUnderTheSameNameProduceExactlyOneWinner() {
        let url = uniqueFileURL()
        let count = 20
        let stores = (0..<count).map { _ in makeStore(fileURL: url) }
        let resultsLock = NSLock()
        var results: [PresetSaveResult] = []

        DispatchQueue.concurrentPerform(iterations: count) { i in
            let result = stores[i].saveCurrentAsUserPreset(named: "Racer")
            resultsLock.lock()
            results.append(result)
            resultsLock.unlock()
        }

        XCTAssertEqual(results.filter { $0 == .success }.count, 1)
        XCTAssertEqual(results.filter { $0 == .duplicateName }.count, count - 1)

        let verifier = makeStore(fileURL: url)
        XCTAssertEqual(verifier.savedUserPresets.map(\.name), ["Racer"])
    }
}

/// Stands in for `containerURL(forSecurityApplicationGroupIdentifier:)`
/// returning nil — entitlement missing, unsigned build, simulator quirk —
/// so `SharedPresetStoreTests` can exercise the fallback branch of
/// `SharedPresetStore`'s production initializer deterministically.
///
/// Also redirects `.documentDirectory` to a fresh per-instance temp
/// directory rather than letting it fall through to the REAL one:
/// `SharedPresetStoreTests` runs hosted inside the real `MonkSynth.app`
/// (same as every other test in this bundle), so the real Documents
/// directory is a single physical location shared not just across test
/// methods but across repeated `xcodebuild test` invocations on the same
/// simulator — without this override, the very first save here ("StillWorks")
/// would persist for good, and every subsequent run would see it already
/// there and fail with `.duplicateName` instead of `.success`.
private final class NilGroupContainerFileManager: FileManager {
    private let fallbackDocumentsURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("NilGroupContainerFileManagerDocuments-\(UUID().uuidString)", isDirectory: true)

    override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? { nil }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        guard directory == .documentDirectory else { return super.urls(for: directory, in: domainMask) }
        try? FileManager.default.createDirectory(at: fallbackDocumentsURL, withIntermediateDirectories: true)
        return [fallbackDocumentsURL]
    }
}

/// Stands in for a working App Group container at a known (fake) location,
/// so tests can confirm `SharedPresetStore` actually uses it — and only it —
/// when available.
private final class FixedGroupContainerFileManager: FileManager {
    private let fixedContainerURL: URL
    init(containerURL: URL) {
        self.fixedContainerURL = containerURL
        super.init()
    }
    override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        fixedContainerURL
    }
}
