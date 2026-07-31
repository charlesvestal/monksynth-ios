import AVFoundation

/// Owns the DSP engine and translates parameters + MIDI into `monk_synth_*`
/// calls. Every method here runs on the render thread: no allocation, no locks,
/// no logging.
///
/// The mapping is upstream's, verbatim — cpp/src/processor.cpp:45-64,153-195.
/// Tests/ParityHarness/render_golden.c implements the same mapping in C and any
/// divergence fails ParityTests.
///
/// `engine` and `shadow` are both pointers to C structs that are only
/// forward-declared in their headers (`typedef struct MonkSynthEngine
/// MonkSynthEngine;`, `typedef struct ParamShadow ParamShadow;` — see
/// synth.h / ParameterShadow.h) with no complete definition visible anywhere
/// Swift can see. Confirmed empirically with a throwaway `-typecheck` probe
/// against the bridging header: for a type that incomplete, the Clang
/// importer does not synthesize a placeholder Swift nominal type for it at
/// all — `monk_synth_new(...)`/`param_shadow_new()` return plain
/// `OpaquePointer!`, and every `monk_synth_*`/`param_shadow_*` function
/// (mutable or const-qualified pointee alike) takes `OpaquePointer!`
/// directly. So `MonkSynthEngine`/`ParamShadow` are never valid Swift type
/// names anywhere in this file — there's nothing to convert to and no
/// annotation to avoid; `OpaquePointer` is simply the correct, exact type,
/// passed straight through to every C call.
final class RenderContext {

    private(set) var engine: OpaquePointer?
    private let shadow: OpaquePointer

    private let paramCount = Int(kParamCount.rawValue)
    private var lastValues: [Float]
    private var xyNoteActive = false
    private var xyPendingPitch: Float = 0.5
    private var midiNoteCount: Int32 = 0

    /// Published to the UI after each render. Read on the main thread.
    let uiVowel     = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let uiAmplitude = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let uiActive    = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    init(shadow: OpaquePointer) {
        self.shadow = shadow
        lastValues = [Float](repeating: .nan, count: Int(kParamCount.rawValue))
        uiVowel.initialize(to: 0.5)
        uiAmplitude.initialize(to: 0)
        uiActive.initialize(to: 0)
    }

    deinit {
        destroyEngine()
        uiVowel.deallocate(); uiAmplitude.deallocate(); uiActive.deallocate()
    }

    // MARK: - Lifecycle (main thread only)

    func createEngine(sampleRate: Double) {
        destroyEngine()
        engine = monk_synth_new(Float(sampleRate))
        for i in 0..<paramCount { lastValues[i] = .nan }
        xyNoteActive = false
        xyPendingPitch = 0.5
        midiNoteCount = 0
    }

    func destroyEngine() {
        if let e = engine { monk_synth_free(e) }
        engine = nil
    }

    // MARK: - Render thread

    private static func xyHz(_ v: Float) -> Float { 130.81 * powf(2.0, v) }

    /// Push any changed shadow values into the DSP. Only diffs are applied.
    private func applyChangedParameters(_ s: OpaquePointer) {
        for i in 0..<paramCount {
            let addr = ParameterAddress(UInt32(i))
            let v = param_shadow_get(shadow, addr)
            // Drop non-finite values rather than feeding them to the DSP. A NaN
            // would also defeat the diff below (NaN != NaN), so it would be
            // re-applied every block while poisoning voice and delay state.
            if !v.isFinite { continue }
            if v == lastValues[i] { continue }
            lastValues[i] = v
            apply(s, addr, v)
        }
    }

    private func apply(_ s: OpaquePointer, _ addr: ParameterAddress, _ v: Float) {
        switch addr {
        case kParamPortTime:          monk_synth_set_glide(s, v)
        case kParamVowel:             monk_synth_set_vowel(s, v)
        case kParamDelay:             monk_synth_set_delay_mix(s, v)
        case kParamHeadSize:          monk_synth_set_voice(s, v)
        case kParamVibrato:           monk_synth_set_vibrato(s, v)
        case kParamVibratoRate:       monk_synth_set_vibrato_rate(s, v)
        case kParamAspiration:        monk_synth_set_aspiration(s, v)
        case kParamAttack:            monk_synth_set_attack(s, v * 5.0)
        case kParamDecay:             monk_synth_set_decay(s, v * 5.0)
        case kParamSustain:           monk_synth_set_sustain(s, v)
        case kParamRelease:           monk_synth_set_release(s, v * 5.0)
        case kParamUnison:            monk_synth_set_unison(s, Int32(v * 9.0 + 1.5))
        case kParamUnisonDetune:      monk_synth_set_unison_detune(s, v * 50.0)
        case kParamDelayRate:         monk_synth_set_delay_rate(s, v)
        case kParamLevel:             monk_synth_set_level(s, v)
        case kParamUnisonVoiceSpread: monk_synth_set_unison_voice_spread(s, v * 0.5)
        case kParamPitchBend:         monk_synth_set_pitch_bend(s, (v - 0.5) * 24.0)
        case kParamXYVowel:           monk_synth_set_vowel(s, v)
        case kParamXYPitchTarget:
            xyPendingPitch = v
            if xyNoteActive { monk_synth_set_pitch_hz(s, Self.xyHz(v)) }
        case kParamXYNoteOn:
            if v > 0.5 {
                xyNoteActive = true
                monk_synth_set_pitch_hz(s, Self.xyHz(xyPendingPitch))
            } else if xyNoteActive {
                // Gated on xyNoteActive rather than firing on every read of
                // "currently off": lastValues starts at .nan, so the very
                // first applyChangedParameters pass after createEngine()
                // sees every shadow slot as "changed" — including
                // kParamXYNoteOn's resting default of 0.0. An unconditional
                // note_off there would fire on a voice that was never on;
                // since attack/decay/sustain/release (lower indices) are
                // already applied earlier in that same pass, has_env is
                // true, so monk_voice_note_off forces env_stage = RELEASE
                // on an idle voice — which makes monk_voice_process's Pass 1
                // spuriously run for a full block (silently, masked by
                // envelope) but still advances vibrato_phase, desyncing
                // vibrato for the rest of the render and breaking bit parity
                // with the C golden. Only a genuine falling edge (we were
                // actually active) should reach the DSP.
                xyNoteActive = false
                if midiNoteCount > 0 { monk_synth_restore_note_stack(s) }
                else                 { monk_synth_note_off(s, 60) }
            }
        default: break   // pitchBendRouting / pitchWheelRaw handled in MIDI
        }
    }

    // MARK: - MIDI (render thread)

    func noteOn(_ note: UInt8, velocity: Float) {
        guard let s = engine else { return }
        monk_synth_note_on(s, note, velocity)
        midiNoteCount += 1
    }

    func noteOff(_ note: UInt8) {
        guard let s = engine else { return }
        if midiNoteCount > 0 { midiNoteCount -= 1 }
        monk_synth_note_off(s, note)
        // Upstream processor.cpp:268-276 — the emptied note stack would trigger
        // release, so re-assert the pad's pitch while it is still held.
        if xyNoteActive && midiNoteCount == 0 {
            monk_synth_set_pitch_hz(s, Self.xyHz(xyPendingPitch))
        }
    }

    /// Upstream controller.cpp:454-458.
    static func parameter(forCC cc: UInt8) -> ParameterAddress? {
        switch cc {
        case 1:  return kParamVibrato
        case 5:  return kParamPortTime
        case 7:  return kParamLevel
        case 12: return kParamDelay
        case 13: return kParamHeadSize
        default: return nil
        }
    }

    /// Upstream controller.cpp:423-452 plus the processor.cpp:208-245 fan-out.
    /// `out` is caller-owned and pre-reserved so this never allocates.
    func pitchWheelTargets(_ normalized: Float,
                            into out: inout [(ParameterAddress, Float)]) {
        out.removeAll(keepingCapacity: true)
        let mode = PitchBendMode(normalized: param_shadow_get(shadow, kParamPitchBendRouting))
        switch mode {
        case .classic:
            out.append((kParamVowel, normalized))
        case .pitch:
            out.append((kParamPitchBend, normalized))
        case .both, .bothInverted:
            out.append((kParamPitchBend, normalized))
            if !xyNoteActive {
                let vowel = mode == .bothInverted ? 1.0 - normalized : normalized
                out.append((kParamVowel, vowel))
            }
        }
    }

    // MARK: - Audio

    func render(left: UnsafeMutablePointer<Float>,
                right: UnsafeMutablePointer<Float>,
                frames: UInt32) {
        guard let s = engine else { return }
        applyChangedParameters(s)
        monk_synth_process(s, left, right, frames)
        uiVowel.pointee     = monk_synth_get_vowel(s)
        uiAmplitude.pointee = monk_synth_amplitude(s)
        uiActive.pointee    = (midiNoteCount > 0 || xyNoteActive) ? 1 : 0
    }

    var isNoteActive: Bool { midiNoteCount > 0 || xyNoteActive }
}
