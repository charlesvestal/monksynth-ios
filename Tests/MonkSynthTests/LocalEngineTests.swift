import AVFoundation
import XCTest
@testable import MonkSynth

/// Exercises `LocalEngine` through an actual `AVAudioEngine`/audio-session
/// stack — the strongest check available without real playback hardware:
/// start the real engine, trigger a note (or drive the XY pad exactly as
/// `RootViewController` wires it), and assert the tapped output is
/// genuinely non-silent. A bug in the MIDI-note queue drain, the forced
/// stereo format, or the render wiring would show up here as silence
/// (`maxAbs` staying at 0), not just as a successful-but-empty pipeline.
final class LocalEngineTests: XCTestCase {

    private func captureMaxAbsSample(
        from engine: LocalEngine, timeout: TimeInterval = 3.0, trigger: () -> Void
    ) -> Float {
        let exp = expectation(description: "captured audio buffer")
        exp.assertForOverFulfill = false   // the tap keeps firing after threshold is crossed

        var maxAbs: Float = 0
        engine.installTestTap { buffer in
            guard let data = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            for ch in 0..<Int(buffer.format.channelCount) {
                let channel = data[ch]
                for i in 0..<frameLength {
                    maxAbs = max(maxAbs, abs(channel[i]))
                }
            }
            if maxAbs > 0.01 { exp.fulfill() }
        }

        trigger()
        wait(for: [exp], timeout: timeout)
        return maxAbs
    }

    func testStartDoesNotThrow() throws {
        let engine = LocalEngine()
        try engine.start()
        engine.stop()
    }

    /// A MIDI-driven note (the path `MIDIInput.onNoteOn` -> `LocalEngine.noteOn`
    /// -> `NoteEventQueue` -> drained on the render thread -> `RenderContext.noteOn`
    /// takes) must reach the speaker.
    func testNoteOnProducesAudibleOutput() throws {
        let engine = LocalEngine()
        try engine.start()
        defer { engine.stop() }

        let maxAbs = captureMaxAbsSample(from: engine) {
            engine.noteOn(60, velocity: 0.9)
        }
        XCTAssertGreaterThan(maxAbs, 0.01,
            "expected audible output after noteOn, got max sample magnitude \(maxAbs)")
    }

    /// `RootViewController.bind()` wires `pluginView.pad.onParameterChange`
    /// straight into `LocalEngine.setParameter`, exactly like the AUv3's pad
    /// writes into its `AUParameterTree`. `XYPadView.beginTouch` itself
    /// (`AU/UI/XYPadView.swift`) is already covered by `XYPadTests.swift` —
    /// this test's job is only to prove that the resulting parameter
    /// writes, replayed in the same order `beginTouch` issues them (pitch
    /// and vowel before note-on — see that method's doc comment on why
    /// order matters), reach real audio through `LocalEngine`'s actual
    /// `AVAudioEngine` pipeline. Constructing this module's own `Param`
    /// directly (rather than a second `XYPadView` instance) sidesteps this
    /// test target's AU-sources duplication: `Tests/MonkSynthTests`
    /// compiles `AU/*.swift` a second time (see MonkSynthTests-CTests split
    /// in project.yml), so an `XYPadView` built here would be a distinct
    /// `MonkSynthTests.Param`-typed type from the `MonkSynth.Param`
    /// `@testable import`ed `LocalEngine.setParameter` expects.
    func testXYPadStyleWritesProduceAudibleOutputThroughRealEngine() throws {
        let engine = LocalEngine()
        try engine.start()
        defer { engine.stop() }

        let maxAbs = captureMaxAbsSample(from: engine) {
            engine.setParameter(.xyPitchTarget, 0.4)
            engine.setParameter(.xyVowel, 0.6)
            engine.setParameter(.xyNoteOn, 1.0)
        }
        XCTAssertGreaterThan(maxAbs, 0.01,
            "expected audible output after an XY-pad-style note-on, got max sample magnitude \(maxAbs)")
    }

    /// `noteOn`/`noteOff` are called from CoreMIDI's own thread in
    /// production (see `NoteEventQueue`'s doc comment on `LocalEngine`);
    /// firing a burst from a background queue while the engine renders is
    /// the closest a unit test can get to that without a real MIDI source,
    /// and must not crash or deadlock.
    func testConcurrentNoteEventsFromBackgroundThreadDoNotCrash() throws {
        let engine = LocalEngine()
        try engine.start()
        defer { engine.stop() }

        let done = expectation(description: "burst finished")
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<200 {
                let note = UInt8(60 + (i % 12))
                engine.noteOn(note, velocity: 0.8)
                engine.noteOff(note)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5.0)
    }
}
