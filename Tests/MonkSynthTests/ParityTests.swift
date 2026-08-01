import AVFoundation
import XCTest
@testable import MonkSynth

/// Replays the exact fixed event script from Tests/ParityHarness/script.h
/// through RenderContext (Swift) and asserts the output is bit-for-bit
/// identical to golden_44k.f32 (rendered by Tests/ParityHarness/render_golden.c
/// from the same script). Any divergence means the Swift parameter mapping in
/// AU/RenderContext.swift has drifted from upstream cpp/src/processor.cpp — see
/// that file's header comment for the reference mapping. Do not weaken this
/// test to make it pass; find and fix the mapping bug instead.
final class ParityTests: XCTestCase {

    /// One event from the fixed parity script. Kind: 0=param set (normalized,
    /// by shadow index), 1=note on, 2=note off, 3=xy note on, 4=xy note off,
    /// 5=xy pitch, 6=xy vowel.
    private struct ScriptEvent {
        let at: Int
        let kind: Int
        let index: Int
        let value: Float
    }

    // Transcribed verbatim from Tests/ParityHarness/script.h's kParityScript.
    // Must stay in the exact same order — see that file's comment about the
    // dispatch loop walking it with a single forward-only pointer.
    private static let script: [ScriptEvent] = [
        ScriptEvent(at: 0, kind: 0, index: 0, value: 0.25),      // portTime
        ScriptEvent(at: 0, kind: 0, index: 2, value: 0.60),      // delay
        ScriptEvent(at: 0, kind: 0, index: 3, value: 0.70),      // headSize
        ScriptEvent(at: 0, kind: 0, index: 4, value: 0.35),      // vibrato
        ScriptEvent(at: 0, kind: 0, index: 5, value: 0.80),      // vibratoRate
        ScriptEvent(at: 0, kind: 0, index: 6, value: 0.20),      // aspiration
        ScriptEvent(at: 0, kind: 0, index: 7, value: 0.10),      // attack -> 0.5s
        ScriptEvent(at: 0, kind: 0, index: 8, value: 0.30),      // decay -> 1.5s
        ScriptEvent(at: 0, kind: 0, index: 9, value: 0.70),      // sustain
        ScriptEvent(at: 0, kind: 0, index: 10, value: 0.40),     // release -> 2.0s
        ScriptEvent(at: 0, kind: 0, index: 11, value: 0.55),     // unison -> 6
        ScriptEvent(at: 0, kind: 0, index: 12, value: 0.40),     // detune -> 20ct
        ScriptEvent(at: 0, kind: 0, index: 13, value: 0.65),     // delayRate
        ScriptEvent(at: 0, kind: 0, index: 14, value: 0.90),     // level
        ScriptEvent(at: 0, kind: 0, index: 15, value: 0.50),     // voiceSpread
        ScriptEvent(at: 4410, kind: 1, index: 60, value: 0.80),  // note on C4
        ScriptEvent(at: 22050, kind: 0, index: 19, value: 0.75), // pitchBend +6st
        ScriptEvent(at: 30870, kind: 0, index: 1, value: 0.20),  // vowel
        ScriptEvent(at: 44100, kind: 2, index: 60, value: 0.00), // note off
        ScriptEvent(at: 61740, kind: 5, index: 0, value: 0.30),  // xy pitch
        ScriptEvent(at: 61740, kind: 3, index: 0, value: 1.00),  // xy note on
        ScriptEvent(at: 79380, kind: 6, index: 0, value: 0.85),  // xy vowel
        ScriptEvent(at: 96030, kind: 5, index: 0, value: 0.75),  // xy pitch glide
        ScriptEvent(at: 114660, kind: 4, index: 0, value: 0.00), // xy note off
        ScriptEvent(at: 132300, kind: 0, index: 19, value: 0.50) // pitchBend back
    ]

    private static let sampleRate = 44100.0
    private static let frames = 176400
    private static let block = 512

    func testRendersBitIdenticalToGoldenC() throws {
        let shadow = param_shadow_new()!
        defer { param_shadow_free(shadow) }
        for p in Param.allCases { param_shadow_set(shadow, p.address, p.defaultValue) }

        let ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: Self.sampleRate)
        defer { ctx.destroyEngine() }

        var output = [Float](repeating: 0, count: Self.frames * 2)
        var nextEvent = 0
        var pos = 0
        var l = [Float](repeating: 0, count: Self.block)
        var r = [Float](repeating: 0, count: Self.block)

        // Same block-boundary quantization as render_golden.c: events are
        // only dispatched at pos = 0, 512, 1024, ... (see script.h's comment).
        while pos < Self.frames {
            while nextEvent < Self.script.count && Self.script[nextEvent].at <= pos {
                let e = Self.script[nextEvent]
                nextEvent += 1
                switch e.kind {
                case 0: param_shadow_set(shadow, ParameterAddress(UInt32(e.index)), e.value)
                case 1: ctx.noteOn(UInt8(e.index), velocity: e.value)
                case 2: ctx.noteOff(UInt8(e.index))
                case 3: param_shadow_set(shadow, kParamXYNoteOn, 1.0)
                case 4: param_shadow_set(shadow, kParamXYNoteOn, 0.0)
                case 5: param_shadow_set(shadow, kParamXYPitchTarget, e.value)
                case 6: param_shadow_set(shadow, kParamXYVowel, e.value)
                default: break
                }
            }

            let n = min(Self.block, Self.frames - pos)
            l.withUnsafeMutableBufferPointer { lb in
                r.withUnsafeMutableBufferPointer { rb in
                    ctx.render(left: lb.baseAddress!, right: rb.baseAddress!, frames: UInt32(n))
                }
            }
            for i in 0..<n {
                output[(pos + i) * 2]     = l[i]
                output[(pos + i) * 2 + 1] = r[i]
            }
            pos += Self.block
        }

        let goldenURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "golden_44k", withExtension: "f32"),
            "golden_44k.f32 missing from test bundle resources")
        let goldenData = try Data(contentsOf: goldenURL)
        let golden: [Float] = goldenData.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }

        XCTAssertEqual(golden.count, output.count,
                        "golden has \(golden.count) samples, Swift render produced \(output.count)")

        var firstDivergence: Int?
        for i in 0..<min(golden.count, output.count) {
            // Compare bit patterns, not `==`, so +0.0/-0.0 count as a
            // mismatch too — the acceptance criterion is byte-for-byte.
            if golden[i].bitPattern != output[i].bitPattern {
                firstDivergence = i
                break
            }
        }
        if let idx = firstDivergence {
            XCTFail("""
                render diverges from golden_44k.f32 at sample index \(idx) \
                (frame \(idx / 2), channel \(idx % 2 == 0 ? "L" : "R")): \
                got \(output[idx]), expected \(golden[idx])
                """)
        }
    }

    /// Upstream processor.cpp:268-276 — releasing the last MIDI note while
    /// the XY pad is still held must not silence the voice: the pad's pitch
    /// is re-asserted so the note keeps sounding for as long as the pad is
    /// down, instead of falling through to the (now-empty) note stack and
    /// triggering release.
    func testNoteOffWhileXYHeldReassertsPadPitch() throws {
        let shadow = param_shadow_new()!
        defer { param_shadow_free(shadow) }
        for p in Param.allCases { param_shadow_set(shadow, p.address, p.defaultValue) }

        let ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: 44100)
        defer { ctx.destroyEngine() }

        param_shadow_set(shadow, kParamXYPitchTarget, 0.3)
        param_shadow_set(shadow, kParamXYNoteOn, 1.0)

        var l = [Float](repeating: 0, count: 512)
        var r = [Float](repeating: 0, count: 512)
        l.withUnsafeMutableBufferPointer { lb in
            r.withUnsafeMutableBufferPointer { rb in
                ctx.render(left: lb.baseAddress!, right: rb.baseAddress!, frames: 512)
            }
        }
        XCTAssertTrue(ctx.isNoteActive, "XY pad hold alone should count as an active note")

        ctx.noteOn(60, velocity: 0.8)
        XCTAssertTrue(ctx.isNoteActive)

        ctx.noteOff(60)
        XCTAssertTrue(ctx.isNoteActive,
                       "releasing the only MIDI note while the XY pad is held must not deactivate")
    }
}
