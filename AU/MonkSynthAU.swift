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
    private var _parameterTree: AUParameterTree!
    private var outputBusArray: AUAudioUnitBusArray!

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
}
