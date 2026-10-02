import XCTest
@testable import MonkSynth

/// A tap on the scene writes pitch, vowel and note-on together. Wherever the
/// previous tap left off, the new note must START at the new tap's pitch and
/// vowel — not sing the last one's formant and then morph across.
final class TapStartTests: XCTestCase {

    private var shadow: OpaquePointer!
    private var ctx: RenderContext!
    private let left = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    private let right = UnsafeMutablePointer<Float>.allocate(capacity: 512)

    override func setUp() {
        shadow = param_shadow_new()!
        for p in Param.allCases { param_shadow_set(shadow, p.address, p.defaultValue) }
        ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: 44100)
    }

    override func tearDown() {
        ctx = nil
        param_shadow_free(shadow)
        left.deallocate(); right.deallocate()
    }

    private func set(_ p: Param, _ v: Float) { param_shadow_set(shadow, p.address, v) }
    private func render(blocks: Int, frames: UInt32 = 512) {
        for _ in 0..<blocks { ctx.render(left: left, right: right, frames: frames) }
    }

    /// Plays a tap at (pitch, vowel), lets it settle, releases it and renders
    /// until the voice has gone silent.
    private func tapAndRelease(pitch: Float, vowel: Float) {
        set(.xyPitchTarget, pitch); set(.xyVowel, vowel); set(.xyNoteOn, 1)
        render(blocks: 40)
        set(.xyNoteOn, 0)
        for _ in 0..<400 where monk_synth_is_active(ctx.engine!) != 0 { render(blocks: 1) }
        XCTAssertEqual(monk_synth_is_active(ctx.engine!), 0, "precondition: the first tap has gone silent")
    }

    func testANewTapStartsOnItsOwnVowel() {
        tapAndRelease(pitch: 0.2, vowel: 0.1)
        set(.xyPitchTarget, 0.8); set(.xyVowel, 0.9); set(.xyNoteOn, 1)
        render(blocks: 1, frames: 64)
        XCTAssertEqual(monk_synth_get_vowel(ctx.engine!), 0.9, accuracy: 0.01,
                       "the tap began on the previous tap's vowel instead of its own")
    }

    func testANewTapStartsOnItsOwnPitch() {
        tapAndRelease(pitch: 0.2, vowel: 0.1)
        set(.xyPitchTarget, 0.8); set(.xyVowel, 0.9); set(.xyNoteOn, 1)
        render(blocks: 1, frames: 64)
        // xyHz(v) = 130.81·2^v Hz → MIDI note 48 + 12v → normalized (note−48)/12 = v.
        XCTAssertEqual(monk_synth_get_pitch_normalized(ctx.engine!), 0.8, accuracy: 0.01,
                       "the tap began on the previous tap's pitch instead of its own")
    }

    /// Dragging while a note sounds must still glide — the snap is only for
    /// a voice starting from silence.
    func testMovingWhileHeldStillGlides() {
        set(.xyPitchTarget, 0.2); set(.xyVowel, 0.1); set(.xyNoteOn, 1)
        render(blocks: 40)
        set(.xyVowel, 0.9)
        render(blocks: 1, frames: 64)
        XCTAssertLessThan(monk_synth_get_vowel(ctx.engine!), 0.5, "a held drag should glide, not jump")
    }

    /// A tap while the previous note is still releasing must start a new note
    /// that sustains while held. It used to only retune the dying note, which
    /// faded to silence under the finger — then a drag started it again.
    func testATapDuringTheReleaseSustainsWhileHeld() {
        set(.release, 0.6)                       // 3 s, the Cow's
        set(.xyPitchTarget, 0.5); set(.xyVowel, 0.5); set(.xyNoteOn, 1)
        render(blocks: 40)
        set(.xyNoteOn, 0)
        render(blocks: 50)                       // ~0.6 s into the release
        set(.xyPitchTarget, 0.3); set(.xyNoteOn, 1)
        render(blocks: 260)                      // hold ~3 s
        XCTAssertNotEqual(monk_synth_is_active(ctx.engine!), 0, "the held note died")
        var peak: Float = 0
        ctx.render(left: left, right: right, frames: 512)
        for i in 0..<512 { peak = max(peak, abs(left[i])) }
        XCTAssertGreaterThan(peak, 0.02, "the held note faded out")
    }
}
