/// Pulls the scene's pitch (normalized 0…1 = one octave, 12 semitones)
/// toward the nearest semitone.
///
/// Around each note sits a zone `strength × ½` semitone wide on either side
/// that plays exactly that note; between zones the pitch slides linearly to
/// the next zone's edge, so the output is continuous and never runs
/// backwards. At 0 there are no zones (free pitch); at 1 the zones meet and
/// every position lands on a note. Pure arithmetic — safe on the render thread.
enum PitchSnap {
    static func apply(_ v: Float, strength: Float) -> Float {
        let k = min(max(strength, 0), 1)
        let s = min(max(v, 0), 1) * 12
        guard k > 0 else { return s / 12 }
        let note = s.rounded()
        let d = s - note                                // −0.5 … 0.5
        let zone = k * 0.5
        guard abs(d) > zone, zone < 0.5 else { return note / 12 }
        let slid = (abs(d) - zone) / (0.5 - zone) * 0.5 // 0 … 0.5 outside the zone
        return (note + (d < 0 ? -slid : slid)) / 12
    }
}
