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

    /// The selected character's `id`. Read by `AudioUnitViewController` at
    /// bind time to seed the visible `CharacterView`, and written by it
    /// whenever the user changes character — an arrow step or a picker
    /// selection (`setCharacterID`). Defaults to
    /// `CharacterRegistry.defaultCharacter` (monk) until a session restores
    /// something else.
    private(set) var characterID: String = CharacterRegistry.defaultCharacter.id {
        didSet {
            guard oldValue != characterID else { return }
            onCharacterIDChange?(characterID)
        }
    }

    /// Fired whenever `characterID` changes — including from `setCharacterID`
    /// itself. Unlike the `AUParameter` originator-token dance
    /// `AudioUnitViewController.bind()` uses to stop a UI write bouncing
    /// straight back into the control that made it, no such guard is needed
    /// here: re-applying the same character id the view just produced is
    /// idempotent (a redraw, not a fight with an in-progress drag), so a
    /// plain callback is enough.
    var onCharacterIDChange: ((String) -> Void)?

    /// UI -> AU write: `AudioUnitViewController` calls this when the user
    /// changes the character (an arrow step or a picker selection).
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
            characterID = CharacterRegistry.character(withID: newValue?["characterID"] as? String).id
        }
    }

    // MARK: - Factory presets

    private lazy var _factoryPresets: [AUAudioUnitPreset] =
        kFactoryPresets.enumerated().map { i, p in
            let preset = AUAudioUnitPreset()
            preset.number = i
            preset.name = p.name
            return preset
        }

    private var _currentPreset: AUAudioUnitPreset?

    public override var factoryPresets: [AUAudioUnitPreset]? { _factoryPresets }

    public override var currentPreset: AUAudioUnitPreset? {
        get { _currentPreset }
        set {
            _currentPreset = newValue
            guard let n = newValue?.number, n >= 0, n < kFactoryPresets.count else { return }
            for (i, v) in kFactoryPresets[n].values.enumerated() {
                param_shadow_set(shadow, Param.address(atIndex: i), v)
                _parameterTree.parameter(withAddress: UInt64(i))?.setValue(v, originator: nil)
            }
        }
    }

    // MARK: - User presets
    //
    // Uses `AUAudioUnit`'s own save/delete/list/read machinery
    // (`saveUserPreset`, `deleteUserPreset`, `userPresets`,
    // `presetState(for:)`) rather than hand-rolling a JSON file: a host can
    // already see, list, and manage these presets itself through the same
    // API, and they persist across launches for free — see the task's "use
    // AUAudioUnit's native user-preset API" instruction. Every preset's
    // state is exactly `fullState` (above), which already carries
    // `characterID` alongside `monkParams`, so the character rides along
    // with zero extra plumbing.
    //
    // The actual disk-backed storage those native calls hit only works from
    // inside a real, installed AU extension process — confirmed empirically:
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
    // while `PresetTests` substitutes `FakeUserPresetBackend` so the LOGIC
    // this class adds on top of those calls — name trimming/validation,
    // duplicate detection, characterID/param packing and fallback — stays
    // fully and deterministically covered without depending on OS mechanics
    // a unit test can't reach.

    /// `AUAudioUnit.supportsUserPresets` defaults to `false`; a host uses it
    /// to decide whether to offer save/delete UI of its own (see that
    /// property's own doc comment) — this AU always supports it.
    public override var supportsUserPresets: Bool { true }

    /// Test seam: defaults to the real native calls; `PresetTests`
    /// substitutes an in-memory fake. See the section doc comment above.
    lazy var userPresetBackend: UserPresetBackend = NativeUserPresetBackend(self)

    // MARK: PresetStoring

    var savedUserPresets: [SavedPreset] {
        userPresetBackend.all.map { preset in
            let characterID = (try? userPresetBackend.state(for: preset))?["characterID"] as? String
            return SavedPreset(name: preset.name, characterID: CharacterRegistry.character(withID: characterID).id)
        }
    }

    func snapshot(forUserPresetNamed name: String) -> PresetSnapshot? {
        guard let preset = userPresetBackend.all.first(where: { $0.name == name }),
              let state = try? userPresetBackend.state(for: preset)
        else { return nil }
        return Self.snapshot(fromPresetState: state)
    }

    @discardableResult
    func saveCurrentAsUserPreset(named name: String) -> PresetSaveResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }
        guard !userPresetBackend.all.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return .duplicateName }

        let preset = AUAudioUnitPreset()
        preset.name = trimmed
        do {
            // Saves `self.fullState` exactly as it stands right now —
            // `monkParams` AND `characterID` together, with no separate
            // "gather the current state" step of our own to keep in sync
            // with `fullState`'s own shape.
            try userPresetBackend.save(preset)
            return .success
        } catch {
            return .failed
        }
    }

    func deleteUserPreset(named name: String) {
        guard let preset = userPresetBackend.all.first(where: { $0.name == name }) else { return }
        try? userPresetBackend.delete(preset)
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
