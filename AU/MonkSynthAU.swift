import AVFoundation

public final class MonkSynthAU: AUAudioUnit {

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

    // MARK: - State

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            var values = [AUValue](repeating: 0, count: Int(kParamCount.rawValue))
            for p in Param.allCases {
                values[Int(p.rawValue)] = param_shadow_get(shadow, p.address)
            }
            state["monkParams"] = values.withUnsafeBufferPointer { Data(buffer: $0) }
            return state
        }
        set {
            super.fullState = newValue
            guard let data = newValue?["monkParams"] as? Data else { return }
            // Upstream processor.cpp:112-127 — a short blob means an older save
            // (or, for the shipped factory presets themselves, one predating a
            // parameter-count bump); leave the remaining parameters at their
            // already-seeded defaults rather than guessing at them.
            let stored = data.withUnsafeBytes { Array($0.bindMemory(to: AUValue.self)) }
            for (i, v) in stored.enumerated() where i < Int(kParamCount.rawValue) {
                param_shadow_set(shadow, Param.address(atIndex: i), v)
                _parameterTree.parameter(withAddress: UInt64(i))?.setValue(v, originator: nil)
            }
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
}
