import AVFoundation

/// The sound that goes with a `Character`'s look — see the "give each
/// character its own voice" task. A parallel table keyed by `Character.id`,
/// not a requirement bolted onto the `Character` protocol itself:
/// `Character` (see that protocol's own doc comment) answers only "what does
/// this look like" — `CharacterView` separately owns "when does it move",
/// and `Param`/`RenderContext` own "what does the engine actually do with a
/// number". Folding sound into `Character` would blur a boundary this
/// codebase already draws on purpose. Keeping it a parallel table means this
/// file can be tuned and tested (see `CharacterVoiceTests`) in complete
/// isolation from the art, and a future character that borrows another's
/// sound doesn't have to fight the protocol to do it.
///
/// Every voice sets exactly the same 15 parameters — the ones that actually
/// characterise a sound in this formant/FOF engine (vocal-tract size,
/// vibrato, breath, glide, unison, the envelope, and the delay send/rate;
/// see the task's "Designing the six voices" section). Deliberately absent
/// from every entry, and never written by `voice(for:)`'s caller:
/// `.vowel` (a live pad/performance position, not a voice trait),
/// the three `.xy*` parameters, `.pitchBend`, `.pitchBendRouting`, and
/// `.pitchWheelRaw` — all live performance/routing state that a character
/// tap must never stomp on.
enum CharacterVoiceTable {

    /// `character`'s voice. Falls back to the default character's voice for
    /// an id this table doesn't recognise, mirroring
    /// `CharacterRegistry.character(withID:)`'s own fallback-to-monk
    /// philosophy — looking up a voice should degrade safely, never trap.
    static func voice(for character: Character) -> [Param: AUValue] {
        voices[character.id] ?? voices[CharacterRegistry.defaultCharacter.id] ?? [:]
    }

    private static let voices: [String: [Param: AUValue]] = [
        "monk": monk,
        "fish": fish,
        "unicorn": unicorn,
        "girl": girl,
        "oldman": oldMan,
        "cow": cow,
    ]

    // MARK: - The six voices
    //
    // Values are raw normalized 0...1 numbers, the same space
    // `Param.defaultValue` and the shadow array already work in — NOT the
    // display units `Param.display(_:)` shows the host (e.g. `headSize` here
    // is a 0...1 fraction, not the 0...30 "cm" a host would display it as).
    // See the task report for the measured spectral centroid / RMS these
    // numbers were tuned against, and dsp/voice.c's `compute_grain` for why
    // headSize (upstream's "voice" parameter) works the direction it does:
    // formant_scale = headSize * 0.5 + 0.75, so a HIGHER headSize value
    // scales formants UP (brighter/smaller-sounding), not down — the
    // opposite of what the cm-labelled knob might suggest at a glance.

    /// The reference: `Param.defaultValue` for every one of the 15 voice
    /// parameters, i.e. upstream's own "Rabten" defaults. Tapping the monk
    /// resets a session back to this — same as tapping any other character
    /// resets it to theirs.
    static let monk: [Param: AUValue] = [
        .portTime: 0.5, .headSize: 0.5, .vibrato: 0.0, .vibratoRate: 0.5,
        .aspiration: 0.5, .attack: 0.0, .decay: 0.0, .sustain: 1.0, .release: 0.0,
        .unison: 0.0, .unisonDetune: 0.0, .unisonVoiceSpread: 0.0,
        .delay: 0.8, .delayRate: 0.5, .level: 1.0,
    ]

    /// Comedic blips: snappy envelope, a lot of delay to turn one blip into
    /// several, almost no breath. `sustain` is higher than "low sustain"
    /// alone would suggest (0.70, not something like 0.15) — a much lower
    /// value read as authentically blippy in isolation but made fish read as
    /// noticeably quieter than the other five once actually measured (see
    /// the RMS-parity requirement); 0.70 is the compromise that keeps fish
    /// clearly the most percussive envelope of the six while staying inside
    /// the loudness band.
    static let fish: [Param: AUValue] = [
        .portTime: 0.5, .headSize: 0.70, .vibrato: 0.0, .vibratoRate: 0.5,
        .aspiration: 0.05, .attack: 0.0, .decay: 0.05, .sustain: 0.70, .release: 0.02,
        .unison: 0.0, .unisonDetune: 0.0, .unisonVoiceSpread: 0.0,
        .delay: 0.95, .delayRate: 0.75, .level: 1.0,
    ]

    /// Shimmery/magical: a big (9-voice) detuned, spread unison choir, a
    /// slow gentle vibrato, a long tail, and a generous delay send.
    static let unicorn: [Param: AUValue] = [
        .portTime: 0.5, .headSize: 0.60, .vibrato: 0.35, .vibratoRate: 0.20,
        .aspiration: 0.40, .attack: 0.05, .decay: 0.10, .sustain: 0.80, .release: 0.55,
        .unison: 0.90, .unisonDetune: 0.60, .unisonVoiceSpread: 0.70,
        .delay: 0.90, .delayRate: 0.60, .level: 1.0,
    ]

    /// Small headSize (the brightest of the six — see the formant_scale note
    /// above), light breath, a quick shallow vibrato.
    static let girl: [Param: AUValue] = [
        .portTime: 0.5, .headSize: 0.92, .vibrato: 0.15, .vibratoRate: 0.85,
        .aspiration: 0.25, .attack: 0.0, .decay: 0.0, .sustain: 1.0, .release: 0.05,
        .unison: 0.0, .unisonDetune: 0.0, .unisonVoiceSpread: 0.0,
        .delay: 0.8, .delayRate: 0.5, .level: 1.0,
    ]

    /// Large headSize (dark/chesty), a slow deep vibrato, heavy aspiration,
    /// a slower attack and a slower glide (`portTime`).
    static let oldMan: [Param: AUValue] = [
        .portTime: 0.75, .headSize: 0.12, .vibrato: 0.55, .vibratoRate: 0.12,
        .aspiration: 0.85, .attack: 0.12, .decay: 0.10, .sustain: 0.85, .release: 0.30,
        .unison: 0.0, .unisonDetune: 0.0, .unisonVoiceSpread: 0.0,
        .delay: 0.8, .delayRate: 0.5, .level: 1.0,
    ]

    /// The largest/darkest headSize of the six, a slow glide so notes slide
    /// into one another, almost no vibrato, a long release.
    static let cow: [Param: AUValue] = [
        .portTime: 0.90, .headSize: 0.08, .vibrato: 0.0, .vibratoRate: 0.5,
        .aspiration: 0.30, .attack: 0.08, .decay: 0.10, .sustain: 0.90, .release: 0.60,
        .unison: 0.0, .unisonDetune: 0.0, .unisonVoiceSpread: 0.0,
        .delay: 0.5, .delayRate: 0.5, .level: 1.0,
    ]
}
