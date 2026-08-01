import AVFoundation

public final class MonkSynthAU: AUAudioUnit, PresetStoring {

    // param_shadow_new() returns `ParamShadow *`, which Swift imports as
    // `UnsafeMutablePointer<ParamShadow>!` because C allows NULL returns.
    // A calloc of ~88 bytes (kParamCount floats) failing means the process
    // is already out of memory and doomed regardless, so force-unwrapping
    // here (rather than threading an Optional through every call site) is
    // the right amount of defensiveness: it still traps loudly at the
    // actual allocation site instead of silently propagating a null
    // pointer into later atomic accesses.
    //
    // NOTE: the type is left to inference (`let shadow = ...!`) rather than
    // spelled out as `let shadow: UnsafeMutablePointer<ParamShadow> = ...`.
    // With Xcode's "emit module separately" fast path, the module-emission
    // frontend job runs with
    // `-experimental-skip-non-inlinable-function-bodies-without-types`,
    // which fails to resolve `ParamShadow` (an intentionally-incomplete,
    // forward-only-declared C struct — see ParameterShadow.h) when it
    // appears in an *explicit* generic type annotation on a stored
    // property ("cannot find type 'ParamShadow' in scope"), even though the
    // exact same reference inside any function body compiles fine. This
    // reproduces from a clean DerivedData build and is independent of
    // header search paths or module caching — it is a toolchain quirk with
    // opaque/incomplete C types at property-declaration scope under that
    // flag. Letting the type be inferred from param_shadow_new()'s return
    // avoids the annotation entirely and sidesteps the bug.
    let shadow = param_shadow_new()!
    // private(set) rather than private: fullState/currentPreset (below) need
    // to push loaded/preset values into the tree, not just the shadow, so
    // that host UI bound to AUParameter observers stays in sync.
    private(set) var _parameterTree: AUParameterTree!
    private var outputBusArray: AUAudioUnitBusArray!
    // Constructed eagerly, not lazily in allocateRenderResources: the render
    // block force-unwraps this, and a host that touches internalRenderBlock
    // before allocating would otherwise trap the whole process. Costs nothing —
    // `engine` starts nil and every method already guards on it.
    private lazy var renderContext = RenderContext(shadow: shadow)

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let bus = try AUAudioUnitBus(format: format)
        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [bus])

        buildParameterTree()
    }

    deinit { param_shadow_free(shadow) }

    public override var outputBusses: AUAudioUnitBusArray { outputBusArray }
    public override var parameterTree: AUParameterTree? {
        get { _parameterTree } set { _parameterTree = newValue }
    }

    private func buildParameterTree() {
        let params: [AUParameter] = Param.allCases.map { p in
            var flags: AudioUnitParameterOptions = [.flag_IsReadable, .flag_IsWritable]
            if !p.isHiddenFromUI { flags.insert(.flag_CanRamp) }
            let param = AUParameterTree.createParameter(
                withIdentifier: p.identifier,
                name: p.name,
                address: p.rawValue,
                min: 0.0, max: 1.0,
                unit: .generic,
                unitName: p.unit.isEmpty ? nil : p.unit,
                flags: flags,
                valueStrings: nil,
                dependentParameters: nil)
            param.value = p.defaultValue
            return param
        }

        let tree = AUParameterTree.createTree(withChildren: params)

        // Host / UI writes land in the shadow; the render thread reads only there.
        tree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }
            param_shadow_set(self.shadow, ParameterAddress(UInt32(param.address)), value)
        }
        tree.implementorValueProvider = { [weak self] param in
            guard let self else { return 0 }
            return param_shadow_get(self.shadow, ParameterAddress(UInt32(param.address)))
        }
        tree.implementorStringFromValueCallback = { param, valuePtr in
            let v = valuePtr?.pointee ?? param.value
            guard let p = Param(rawValue: param.address) else { return "" }
            return p.formatted(v)
        }

        _parameterTree = tree
        // Seed the shadow with defaults.
        for p in Param.allCases {
            param_shadow_set(shadow, p.address, p.defaultValue)
        }
    }

    // MARK: - Render resources

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        renderContext.createEngine(sampleRate: outputBusses[0].format.sampleRate)
    }

    public override func deallocateRenderResources() {
        renderContext.destroyEngine()
        super.deallocateRenderResources()
    }

    // MARK: - Render block

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Captured once — no ARC traffic or optional unwrapping per block.
        let ctx = renderContext
        let shadowPtr = shadow
        var wheelTargets = [(ParameterAddress, Float)]()
        wheelTargets.reserveCapacity(2)

        return { _, _, frameCount, _, outputData, eventListHead, _ in
            var event = eventListHead?.pointee
            while let e = event {
                if e.head.eventType == .MIDI {
                    // e.MIDI.data is a C `uint8_t data[3]`, imported as the
                    // Swift tuple (UInt8, UInt8, UInt8) — reading .0/.1/.2 is
                    // plain field access on a value type, no allocation
                    // (unlike `withUnsafeBytes(of:) { Array($0.prefix(3)) }`,
                    // which would heap-allocate an Array on every MIDI event).
                    let data = e.MIDI.data
                    let status = data.0 & 0xF0
                    let d1 = data.1
                    let d2 = data.2
                    switch status {
                    case 0x90 where d2 > 0:
                        ctx.noteOn(d1, velocity: Float(d2) / 127.0)
                    case 0x80, 0x90:
                        ctx.noteOff(d1)
                    case 0xB0:
                        if let addr = RenderContext.parameter(forCC: d1) {
                            param_shadow_set(shadowPtr, addr, Float(d2) / 127.0)
                        }
                    case 0xE0:
                        let raw = (Int(d2) << 7) | Int(d1)
                        let norm = Float(raw) / 16383.0
                        ctx.pitchWheelTargets(norm, into: &wheelTargets)
                        for (addr, v) in wheelTargets { param_shadow_set(shadowPtr, addr, v) }
                    default: break
                    }
                }
                event = e.head.next?.pointee
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            guard bufferList.count >= 2,
                  let l = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = bufferList[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }

            ctx.render(left: l, right: r, frames: frameCount)
            return noErr
        }
    }

    /// Live animation data for the editor. Main-thread reads of render-thread writes.
    var uiVowel: Float     { renderContext.uiVowel.pointee }
    var uiAmplitude: Float { renderContext.uiAmplitude.pointee }
    var uiNoteActive: Bool { renderContext.uiActive.pointee != 0 }

    // MARK: - Character selection
    //
    // Cosmetic only — deliberately NOT an `AUParameter` (see the characters
    // design doc: a host automating "which character" would be strange).
    // It still has to travel with sessions and presets, so it rides in
    // `fullState` under `"characterID"` alongside `"monkParams"` instead.

    /// The selected character's built-in FACE `id` — always one of
    /// `CharacterRegistry.all`'s own ids, never a saved user entry's own
    /// (non-built-in) id; see `setCharacterID`. Read by
    /// `AudioUnitViewController` at bind time to seed the visible
    /// `CharacterView`, and written by it whenever the user changes
    /// character — an arrow step or a dropdown selection (`setCharacterID`,
    /// always passed `Character.faceID`, never `Character.id`). Defaults to
    /// `CharacterRegistry.defaultCharacter` (monk) until a session restores
    /// something else.
    private(set) var characterID: String = CharacterRegistry.defaultCharacter.id

    /// Fired only when `characterID` changes because of a genuinely
    /// EXTERNAL restore — `fullState`'s setter, a host loading a saved
    /// session or reapplying a preset — reaching in while the editor may
    /// already be showing. Deliberately NOT fired by `setCharacterID` (the
    /// UI -> AU direction): that method is only ever called after
    /// `CharacterView.applyCharacter` has already updated the visible
    /// character itself (see `CharacterView.onCharacterSelected`'s doc
    /// comment), so re-notifying here would at best be a redundant echo
    /// (harmless for a built-in, since re-resolving its own id yields back
    /// the identical character) and at worst actively wrong: a saved user
    /// entry's on-screen NAME can't be reconstructed by resolving a bare
    /// built-in face id back through `CharacterRegistry` — that only ever
    /// yields a plain built-in character — so firing this from
    /// `setCharacterID` would silently revert e.g. "My Patch" back to
    /// whatever built-in face it was saved with, a moment after the user
    /// picked it (the observer hops to `DispatchQueue.main.async`, so the
    /// revert would land on the very next run-loop turn).
    var onCharacterIDChange: ((String) -> Void)?

    /// UI -> AU write: `AudioUnitViewController` calls this when the user
    /// changes the character — an arrow step, or a dropdown selection of
    /// either a built-in or a saved user entry — always passing
    /// `Character.faceID` (never `Character.id`), so `characterID` here
    /// stays a real built-in id in every case, exactly what
    /// `currentSnapshotForPresetStore()` needs when the user later saves
    /// the current patch under a new name. Deliberately does not fire
    /// `onCharacterIDChange` — see that property's doc comment.
    func setCharacterID(_ id: String) {
        characterID = id
    }

    // MARK: - State

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            var values = [AUValue](repeating: 0, count: Int(kParamCount.rawValue))
            for p in Param.allCases {
                values[Int(p.rawValue)] = param_shadow_get(shadow, p.address)
            }
            state["monkParams"] = values.withUnsafeBufferPointer { Data(buffer: $0) }
            state["characterID"] = characterID
            return state
        }
        set {
            super.fullState = newValue
            if let data = newValue?["monkParams"] as? Data {
                // Upstream processor.cpp:112-127 — a short blob means an older
                // save (or, for the shipped factory presets themselves, one
                // predating a parameter-count bump); leave the remaining
                // parameters at their already-seeded defaults rather than
                // guessing at them.
                let stored = data.withUnsafeBytes { Array($0.bindMemory(to: AUValue.self)) }
                for (i, v) in stored.enumerated() where i < Int(kParamCount.rawValue) {
                    param_shadow_set(shadow, Param.address(atIndex: i), v)
                    _parameterTree.parameter(withAddress: UInt64(i))?.setValue(v, originator: nil)
                }
            }
            // `CharacterRegistry.character(withID:)` falls back to the
            // default (monk) for a missing key (an older save) or an
            // unrecognised id (a character renamed/removed since), so this
            // always lands on a real character rather than a blank stage.
            // This IS a genuine external restore, so — unlike
            // `setCharacterID` — `onCharacterIDChange` fires when the
            // resolved id actually changed, mirroring the guard the old
            // `didSet` used to apply unconditionally.
            let resolved = CharacterRegistry.character(withID: newValue?["characterID"] as? String).id
            let changed = resolved != characterID
            characterID = resolved
            if changed { onCharacterIDChange?(resolved) }
        }
    }

    // MARK: - Factory presets
    //
    // Host-facing factory presets are the twelve characters, not upstream's
    // six Tibetan preset names: "no hosts will surface [those names], so
    // don't keep them in the factory presets list." A host that shows its
    // own preset menu sees exactly the list this app's own picker shows —
    // Monk, Fish, Unicorn, Little Girl, Old Man, Cow, Punk, Fire Fighter,
    // Dog, Cat, Pizza, Ghost — one list, not a parallel set of names nothing
    // else in the app references any more. Upstream's own six patches are
    // still reachable (see `FactoryVoiceTable`) — as the VOICES of six of
    // these twelve characters — just never surfaced by their original names.

    private lazy var _factoryPresets: [AUAudioUnitPreset] =
        CharacterRegistry.all.enumerated().map { i, character in
            let preset = AUAudioUnitPreset()
            preset.number = i
            preset.name = character.displayName
            return preset
        }

    private var _currentPreset: AUAudioUnitPreset?

    public override var factoryPresets: [AUAudioUnitPreset]? { _factoryPresets }

    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            _currentPreset = newValue
            // Negative numbers are user presets (the AUv3 convention) — the
            // host already applied that preset's saved state via `fullState`
            // before/around setting this property (see `presetState(for:)`),
            // so there is nothing further to apply here; this setter only
            // needs to record `_currentPreset` for the getter, which the
            // assignment above already did. Only a genuine factory-preset
            // number (0..<CharacterRegistry.all.count) triggers applying a
            // character below.
            guard let n = newValue?.number, n >= 0, n < CharacterRegistry.all.count else { return }
            applyFactoryPresetCharacter(CharacterRegistry.all[n])
        }
    }

    /// Applies `character`'s face AND voice for a HOST selecting one of
    /// `factoryPresets` by number — exactly what `AudioUnitViewController`/
    /// `RootViewController`'s `onCharacterSelected` wiring does for an
    /// in-app selection (arrow step or dropdown row): persist the character
    /// id, then load `character.savedParameters` (a factory-voiced
    /// character's own preset, verbatim — see `FactoryVoiceTable`) if it has
    /// one, otherwise `CharacterVoiceTable.voice(for:)`. Values are written
    /// through the parameter tree's `setValue(_:originator:)` — never
    /// straight into the shadow — so the host observes each changed
    /// parameter (the tree's own `implementorValueObserver`, set up in
    /// `buildParameterTree()`, mirrors every write into the shadow the
    /// render thread reads). This IS a genuine external restore (a host
    /// picking a preset while the editor may already be on screen), so —
    /// like `fullState`'s setter — `onCharacterIDChange` fires when the id
    /// actually changed, keeping any visible editor in sync.
    private func applyFactoryPresetCharacter(_ character: Character) {
        let changed = character.id != characterID
        characterID = character.id
        if changed { onCharacterIDChange?(character.id) }
        let values = character.savedParameters ?? CharacterVoiceTable.voice(for: character)
        for (param, value) in values {
            _parameterTree.parameter(withAddress: param.rawValue)?.setValue(value, originator: nil)
        }
    }

    // MARK: - User presets
    //
    // Canonical storage is the shared App Group store (`presetStore`, a
    // `SharedPresetStore` — see that type's doc comment): the standalone app
    // and this extension are separate sandboxes, and a preset saved from
    // one must be visible from the other. Every save/delete is ALSO
    // mirrored into `AUAudioUnit`'s own native user-preset machinery
    // (`userPresetBackend`, below) on a best-effort basis, so a host's own
    // preset UI (`AUAudioUnit.userPresets`) keeps listing them too —
    // `AUAudioUnit.userPresets` is host-visible and worth preserving
    // alongside cross-container sharing, not instead of it. If the native
    // mirror call fails (host declined, sandbox hiccup) that failure is
    // logged and swallowed: the canonical shared store already has the
    // preset, which is what makes it visible to the OTHER container, and
    // that is the save this method's caller actually needs to succeed.
    //
    // The native calls' actual disk-backed storage only works from inside a
    // real, installed AU extension process — confirmed empirically:
    // instantiated directly (the same way the real extension's own
    // `AudioUnitViewController.createAudioUnit(with:)` does) inside a plain
    // XCTest, `saveUserPreset` neither throws nor persists anything, with or
    // without `AUAudioUnit.registerSubclass`; going through
    // `AVAudioUnit.instantiate` instead just hands back an out-of-process XPC
    // proxy (`AUAudioUnit_XH`), not this class, so there is no way to drive
    // OUR `PresetStoring` methods through it either. So the native calls
    // themselves are routed through `userPresetBackend` — production always
    // uses `NativeUserPresetBackend` (this section, genuinely calling
    // `saveUserPreset`/`userPresets`/`presetState(for:)`/`deleteUserPreset`),
    // while `PresetTests` substitutes `FakeUserPresetBackend` (and, for the
    // canonical store, an isolated `presetStore`) so the LOGIC this class
    // adds on top of those calls — name trimming/validation, duplicate
    // detection, characterID/param packing and fallback, native mirroring —
    // stays fully and deterministically covered without depending on OS
    // mechanics a unit test can't reach or writing to real shared storage.

    /// `AUAudioUnit.supportsUserPresets` defaults to `false`; a host uses it
    /// to decide whether to offer save/delete UI of its own (see that
    /// property's own doc comment) — this AU always supports it.
    public override var supportsUserPresets: Bool { true }

    /// Test seam: defaults to the real native calls; `PresetTests`
    /// substitutes an in-memory fake. See the section doc comment above.
    lazy var userPresetBackend: UserPresetBackend = NativeUserPresetBackend(self)

    /// Test seam mirroring `userPresetBackend`: production always uses a
    /// real `SharedPresetStore` (backed by the App Group container, falling
    /// back to this extension's own sandboxed storage if the container is
    /// unavailable — see that type's doc comment); `PresetTests` substitutes
    /// an isolated in-memory-backed store so tests never touch real shared
    /// or per-container disk state. Building the real store here (rather
    /// than at `init` time) also runs the one-time native-preset migration
    /// (below) lazily, on first actual use, instead of on every AU
    /// instantiation.
    lazy var presetStore: PresetStoring = {
        let store = SharedPresetStore(currentSnapshot: { [weak self] in
            self?.currentSnapshotForPresetStore() ?? PresetSnapshot(
                params: Param.allCases.map(\.defaultValue), characterID: CharacterRegistry.defaultCharacter.id)
        })
        migrateNativeUserPresetsIfNeeded(into: store)
        return store
    }()

    /// What `saveCurrentAsUserPreset` captures right now — exactly the same
    /// params+characterID `fullState` packs, just not yet wrapped into the
    /// `Data`/`[String: Any]` shape `AUAudioUnit.fullState` needs.
    private func currentSnapshotForPresetStore() -> PresetSnapshot {
        PresetSnapshot(params: Param.allCases.map { param_shadow_get(shadow, $0.address) }, characterID: characterID)
    }

    private static let migratedNativeUserPresetsDefaultsKey = "monksynth.migratedNativeUserPresetsToSharedStore"

    /// "Existing presets must survive": anyone already running a build has
    /// presets sitting in native `AUAudioUnit.userPresets`. Reads every one
    /// out via `userPresetBackend` (so tests can substitute a fake and see
    /// zero — nothing to migrate — rather than touching real OS state) and
    /// folds them into `store` once; `SharedPresetStore` itself tracks the
    /// "once" via `markerKey` so repeated launches — or repeated AU
    /// instantiations within one host session — are cheap no-ops after the
    /// first successful run.
    private func migrateNativeUserPresetsIfNeeded(into store: SharedPresetStore) {
        let legacy: [SharedPresetStore.StoredPreset] = userPresetBackend.all.compactMap { preset in
            guard let state = try? userPresetBackend.state(for: preset) else { return nil }
            let snapshot = Self.snapshot(fromPresetState: state)
            return SharedPresetStore.StoredPreset(name: preset.name, characterID: snapshot.characterID, params: snapshot.params)
        }
        store.migrateLegacyPresetsIfNeeded(legacy, markerKey: Self.migratedNativeUserPresetsDefaultsKey)
    }

    // MARK: PresetStoring

    var savedUserPresets: [SavedPreset] { presetStore.savedUserPresets }

    func snapshot(forUserPresetNamed name: String) -> PresetSnapshot? {
        presetStore.snapshot(forUserPresetNamed: name)
    }

    @discardableResult
    func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult {
        let result = presetStore.saveCurrentAsUserPreset(named: name)
        if result == .success {
            mirrorSaveToNativeUserPresets(named: name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    func deleteUserPreset(named name: String) {
        presetStore.deleteUserPreset(named: name)
        mirrorDeleteToNativeUserPresets(named: name)
    }

    /// Best-effort mirror of a successful canonical save into `AUAudioUnit`'s
    /// own native user-preset storage, so a host's own preset UI
    /// (`userPresets`) lists it too. `userPresetBackend.save` captures
    /// `self.fullState` exactly as it stands right now (see
    /// `NativeUserPresetBackend`/`FakeUserPresetBackend`'s own doc comments)
    /// — the same live state `presetStore.saveCurrentAsUserPreset` (called
    /// moments earlier, same thread, nothing in between could have changed
    /// it) already captured into the canonical store, so the two stay in
    /// sync. A failure here is logged, not propagated: the caller already
    /// has `.success` from the store that actually makes the preset visible
    /// across containers, which is the save that matters most.
    private func mirrorSaveToNativeUserPresets(named name: String) {
        let preset = AUAudioUnitPreset()
        preset.name = name
        do {
            try userPresetBackend.save(preset)
        } catch {
            NSLog("MonkSynth: failed to mirror user preset '\(name)' into host-visible userPresets: \(error)")
        }
    }

    /// Best-effort mirror of a delete. A no-op if the native side never had
    /// this name (e.g. an earlier mirror-save failed) — matching
    /// `deleteUserPreset`'s own "deleting an unknown name is a no-op, not a
    /// crash" contract.
    private func mirrorDeleteToNativeUserPresets(named name: String) {
        guard let preset = userPresetBackend.all.first(where: { $0.name == name }) else { return }
        do {
            try userPresetBackend.delete(preset)
        } catch {
            NSLog("MonkSynth: failed to mirror delete of user preset '\(name)' from host-visible userPresets: \(error)")
        }
    }

    /// Unpacks a preset-state dictionary — whatever `presetState(for:)`
    /// hands back, the same `["monkParams": Data, "characterID": String]`
    /// shape `fullState` produces — into a plain `PresetSnapshot`,
    /// defaulting any parameter a short/old blob doesn't cover to
    /// `Param.defaultValue` and falling back an unrecognised/missing
    /// `characterID` to the registry default. Mirrors `fullState`'s own
    /// setter (see its "short blob" comment) so a preset saved before a
    /// parameter-count bump — or, once the roster changes, one saved under
    /// a character id that no longer exists — degrades exactly the same way
    /// a restored session already does.
    private static func snapshot(fromPresetState state: [String: Any]) -> PresetSnapshot {
        var values = Param.allCases.map(\.defaultValue)
        if let data = state["monkParams"] as? Data {
            let stored = data.withUnsafeBytes { Array($0.bindMemory(to: AUValue.self)) }
            for (i, v) in stored.enumerated() where i < values.count { values[i] = v }
        }
        let characterID = CharacterRegistry.character(withID: state["characterID"] as? String).id
        return PresetSnapshot(params: values, characterID: characterID)
    }
}

/// The seam `MonkSynthAU`'s user-preset logic calls through instead of
/// touching `AUAudioUnit`'s native save/list/read/delete API directly — see
/// the "User presets" section doc comment on `MonkSynthAU` for why this
/// exists (in short: that native storage is only reachable from inside a
/// real, installed AU extension process, which a unit test is not).
protocol UserPresetBackend: AnyObject {
    var all: [AUAudioUnitPreset] { get }
    func state(for preset: AUAudioUnitPreset) throws -> [String: Any]
    func save(_ preset: AUAudioUnitPreset) throws
    func delete(_ preset: AUAudioUnitPreset) throws
}

/// Production's only `UserPresetBackend`: a thin, direct pass-through to
/// `AUAudioUnit`'s own `userPresets`/`presetState(for:)`/`saveUserPreset`/
/// `deleteUserPreset`. `unowned`, not `weak`: `au` owns this object (via its
/// `lazy var userPresetBackend`), never the other way around, so there is no
/// retain cycle to break — `weak` would just add an unnecessary Optional at
/// every call site.
private final class NativeUserPresetBackend: UserPresetBackend {
    private unowned let au: MonkSynthAU
    init(_ au: MonkSynthAU) { self.au = au }

    var all: [AUAudioUnitPreset] { au.userPresets }
    func state(for preset: AUAudioUnitPreset) throws -> [String: Any] { try au.presetState(for: preset) }
    func save(_ preset: AUAudioUnitPreset) throws { try au.saveUserPreset(preset) }
    func delete(_ preset: AUAudioUnitPreset) throws { try au.deleteUserPreset(preset) }
}
