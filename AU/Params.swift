import AVFoundation

/// The parameter table. Normalized 0…1 internally, exactly as upstream stores
/// it; `display` is what the host and UI show. Ranges lifted from
/// upstream cpp/src/controller.cpp:566-661.
enum Param: UInt64, CaseIterable {
    case portTime = 0, vowel, delay, headSize, vibrato, vibratoRate, aspiration
    case attack, decay, sustain, release, unison, unisonDetune, delayRate
    case level, unisonVoiceSpread, xyNoteOn, xyVowel, xyPitchTarget
    case pitchBend, pitchBendRouting, pitchWheelRaw

    var identifier: String {
        switch self {
        case .portTime: return "portTime"
        case .vowel: return "vowel"
        case .delay: return "delay"
        case .headSize: return "headSize"
        case .vibrato: return "vibrato"
        case .vibratoRate: return "vibratoRate"
        case .aspiration: return "aspiration"
        case .attack: return "attack"
        case .decay: return "decay"
        case .sustain: return "sustain"
        case .release: return "release"
        case .unison: return "unison"
        case .unisonDetune: return "unisonDetune"
        case .delayRate: return "delayRate"
        case .level: return "level"
        case .unisonVoiceSpread: return "unisonVoiceSpread"
        case .xyNoteOn: return "xyNoteOn"
        case .xyVowel: return "xyVowel"
        case .xyPitchTarget: return "xyPitchTarget"
        case .pitchBend: return "pitchBend"
        case .pitchBendRouting: return "pitchBendRouting"
        case .pitchWheelRaw: return "pitchWheelRaw"
        }
    }

    /// Host-facing name. Matches upstream's STR16 names so presets read the same.
    var name: String {
        switch self {
        case .portTime: return "PortTime"
        case .vowel: return "Vowel"
        case .delay: return "Delay"
        case .headSize: return "HeadSize"
        case .vibrato: return "Vibrato"
        case .vibratoRate: return "Vib Rate"
        case .aspiration: return "Breath"
        case .attack: return "Attack"
        case .decay: return "Decay"
        case .sustain: return "Sustain"
        case .release: return "Release"
        case .unison: return "Unison"
        case .unisonDetune: return "Detune"
        case .delayRate: return "Delay Rate"
        case .level: return "Level"
        case .unisonVoiceSpread: return "Voice Spread"
        case .xyNoteOn: return "XY Note"
        case .xyVowel: return "XY Vowel"
        case .xyPitchTarget: return "XY Pitch"
        case .pitchBend: return "Pitch Bend"
        case .pitchBendRouting: return "PB Routing"
        case .pitchWheelRaw: return "PW Raw"
        }
    }

    var unit: String {
        switch self {
        case .portTime: return "Hours"
        case .delay: return "dB"
        case .headSize: return "cm"
        case .attack, .decay, .release: return "s"
        case .unisonDetune: return "ct"
        case .pitchBend: return "st"
        default: return ""
        }
    }

    /// Normalized default, from upstream cpp/src/processor.h.
    var defaultValue: AUValue {
        switch self {
        case .delay: return 0.8
        case .sustain, .level: return 1.0
        case .vibrato, .attack, .decay, .release,
             .unison, .unisonDetune, .unisonVoiceSpread,
             .xyNoteOn, .pitchBendRouting: return 0.0
        default: return 0.5   // portTime, vowel, headSize, vibratoRate,
                              // aspiration, delayRate, xyVowel,
                              // xyPitchTarget, pitchBend, pitchWheelRaw
        }
    }

    /// Display range for the host's value string.
    var displayRange: ClosedRange<AUValue> {
        switch self {
        case .portTime: return 0...1000
        case .headSize: return 0...30
        case .attack, .decay, .release: return 0...5
        case .unison: return 1...10
        case .unisonDetune: return 0...50
        case .pitchBend: return -12...12
        default: return 0...1
        }
    }

    /// Number of discrete steps, or 0 for continuous.
    var stepCount: Int {
        switch self {
        case .unison: return 9            // 10 values, 9 intervals
        case .pitchBendRouting: return 3  // 4 modes
        case .xyNoteOn: return 1          // toggle
        default: return 0
        }
    }

    /// Hidden from the on-screen control pages (still host-automatable).
    var isHiddenFromUI: Bool {
        switch self {
        case .xyNoteOn, .xyVowel, .xyPitchTarget, .pitchWheelRaw: return true
        default: return false
        }
    }

    func display(_ normalized: AUValue) -> AUValue {
        let r = displayRange
        return r.lowerBound + normalized * (r.upperBound - r.lowerBound)
    }

    func normalized(fromDisplay d: AUValue) -> AUValue {
        let r = displayRange
        return (d - r.lowerBound) / (r.upperBound - r.lowerBound)
    }

    func formatted(_ normalized: AUValue) -> String {
        switch self {
        case .unison:
            return String(Int((normalized * 9.0 + 1.5).rounded(.down)))
        case .pitchBendRouting:
            return PitchBendMode(normalized: normalized).name
        case .xyNoteOn:
            return normalized > 0.5 ? "On" : "Off"
        case .portTime, .headSize, .unisonDetune:
            return String(format: "%.0f", display(normalized))
        case .pitchBend:
            return String(format: "%+.2f", display(normalized))
        case .attack, .decay, .release:
            return String(format: "%.2f", display(normalized))
        default:
            return String(format: "%.2f", normalized)
        }
    }
}

extension Param {
    /// The C-side address. A plain C `typedef enum` imports into Swift as a
    /// RawRepresentable struct with a NON-failable init, so never write
    /// `ParameterAddress(rawValue:)!` — it will not compile.
    var address: ParameterAddress { ParameterAddress(UInt32(rawValue)) }

    static func address(atIndex i: Int) -> ParameterAddress {
        ParameterAddress(UInt32(i))
    }
}

/// Where the hardware pitch wheel is routed. Upstream cpp/src/plugin_cids.h:51.
enum PitchBendMode: Int, CaseIterable {
    case classic = 0, both, bothInverted, pitch

    init(normalized v: AUValue) {
        let i = Int((v * 3.0 + 0.5).rounded(.down))
        self = PitchBendMode(rawValue: max(0, min(3, i))) ?? .classic
    }

    var normalized: AUValue { AUValue(rawValue) / 3.0 }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .both: return "Both"
        case .bothInverted: return "Both Inv"
        case .pitch: return "Pitch"
        }
    }
}
