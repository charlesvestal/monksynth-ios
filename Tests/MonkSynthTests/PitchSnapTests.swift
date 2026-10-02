import XCTest
@testable import MonkSynth

/// Pitch Snap pulls the scene's pitch (one octave, 12 semitones across) toward
/// the nearest semitone. 0 is free; 1 lands every position exactly on a note;
/// in between, a zone around each note holds that note and the pitch slides
/// smoothly between zones — it never jumps.
final class PitchSnapTests: XCTestCase {

    private func semis(_ v: Float) -> Float { v * 12 }

    func testZeroIsFree() {
        for v: Float in [0, 0.13, 0.37, 0.5, 0.99, 1] {
            XCTAssertEqual(PitchSnap.apply(v, strength: 0), v, accuracy: 1e-6)
        }
    }

    func testFullLandsOnTheNearestSemitone() {
        XCTAssertEqual(semis(PitchSnap.apply(0.37, strength: 1)), 4, accuracy: 1e-4)   // 4.44 → 4
        XCTAssertEqual(semis(PitchSnap.apply(0.40, strength: 1)), 5, accuracy: 1e-4)   // 4.80 → 5
        XCTAssertEqual(semis(PitchSnap.apply(1.00, strength: 1)), 12, accuracy: 1e-4)
        XCTAssertEqual(semis(PitchSnap.apply(0.00, strength: 1)), 0, accuracy: 1e-4)
    }

    func testHalfHoldsNearNotesAndSlidesBetween() {
        // Zone half-width is strength × 0.5 semitone = 0.25.
        XCTAssertEqual(semis(PitchSnap.apply(4.2 / 12, strength: 0.5)), 4, accuracy: 1e-4)
        let between = semis(PitchSnap.apply(4.4 / 12, strength: 0.5))
        XCTAssertGreaterThan(between, 4.0)
        XCTAssertLessThan(between, 4.5)
        // The midpoint between two notes stays the midpoint: continuous.
        XCTAssertEqual(semis(PitchSnap.apply(4.5 / 12, strength: 0.5)), 4.5, accuracy: 1e-4)
    }

    func testBelowFullItNeverJumpsAndNeverGoesBackwards() {
        for strength: Float in [0.25, 0.5, 0.9, 0.99] {
            var previous = PitchSnap.apply(0, strength: strength)
            for i in 1...1200 {
                let out = PitchSnap.apply(Float(i) / 1200, strength: strength)
                XCTAssertGreaterThanOrEqual(out, previous - 1e-6, "went backwards at strength \(strength)")
                // Continuous: the slide between zones is the steepest part, and
                // it moves 1/(1−strength) times as fast as the finger — never more.
                XCTAssertLessThanOrEqual(out - previous, (1.0 / 1200) / (1 - strength) + 1e-5,
                                         "jumped at strength \(strength)")
                previous = out
            }
        }
    }

    func testOutputStaysInRange() {
        for v: Float in [-0.2, 1.3] {
            let out = PitchSnap.apply(v, strength: 0.7)
            XCTAssertGreaterThanOrEqual(out, 0); XCTAssertLessThanOrEqual(out, 1)
        }
    }

    // MARK: - Through the engine

    private var shadow: OpaquePointer!
    private var ctx: RenderContext!
    private let l = UnsafeMutablePointer<Float>.allocate(capacity: 512)
    private let r = UnsafeMutablePointer<Float>.allocate(capacity: 512)

    override func setUp() {
        shadow = param_shadow_new()!
        for p in Param.allCases { param_shadow_set(shadow, p.address, p.defaultValue) }
        ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: 44100)
    }

    override func tearDown() {
        ctx = nil
        param_shadow_free(shadow)
        l.deallocate(); r.deallocate()
    }

    private func set(_ p: Param, _ v: Float) { param_shadow_set(shadow, p.address, v) }
    private func render(_ blocks: Int) { for _ in 0..<blocks { ctx.render(left: l, right: r, frames: 512) } }

    func testDefaultIsOff() {
        XCTAssertEqual(Param.pitchSnap.defaultValue, 0)
    }

    func testATapPlaysTheSnappedPitch() {
        set(.pitchSnap, 1)
        set(.xyPitchTarget, 0.37); set(.xyVowel, 0.5); set(.xyNoteOn, 1)
        render(1)
        XCTAssertEqual(monk_synth_get_pitch_normalized(ctx.engine!) * 12, 4, accuracy: 0.01)
    }

    func testTurningSnapUpWhileHeldRetunesTheNote() {
        set(.xyPitchTarget, 0.37); set(.xyVowel, 0.5); set(.xyNoteOn, 1)
        render(40)
        XCTAssertEqual(monk_synth_get_pitch_normalized(ctx.engine!) * 12, 4.44, accuracy: 0.02)
        set(.pitchSnap, 1)
        render(40)
        XCTAssertEqual(monk_synth_get_pitch_normalized(ctx.engine!) * 12, 4, accuracy: 0.02)
    }

    func testTheKnobIsOnThePitchPageNextToTune() {
        let page = ControlPages.pages.first { $0.title == "PITCH" }
        XCTAssertEqual(page?.params, [.pitchBend, .pitchSnap, .pitchBendRouting, .vibrato, .vibratoRate])
        XCTAssertEqual(Param.pitchBend.name, "Tune")
        XCTAssertEqual(Param.pitchSnap.name, "Snap")
        XCTAssertEqual(Param.pitchSnap.formatted(0.5), "50%")
    }
}
