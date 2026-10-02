import AVFoundation
import XCTest
@testable import MonkSynth

/// MIDI into the AUv3 (and the shared RenderContext the standalone uses):
/// timing, wheels, stuck notes, and repeated notes.
final class MidiInputTests: XCTestCase {

    // MARK: - RenderContext

    private var shadow: OpaquePointer!
    private var ctx: RenderContext!
    private let l = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
    private let r = UnsafeMutablePointer<Float>.allocate(capacity: 4096)

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

    private func render(_ blocks: Int) { for _ in 0..<blocks { ctx.render(left: l, right: r, frames: 512) } }

    func testThePitchWheelBendsPitchTwoSemitonesOnTopOfTune() {
        param_shadow_set(shadow, kParamPitchBend, 0.75)          // Tune +6 st
        render(1)
        XCTAssertEqual(ctx.appliedBendSemitones, 6, accuracy: 1e-4)
        param_shadow_set(shadow, kParamPitchWheelRaw, 1.0)      // wheel fully up
        render(1)
        XCTAssertEqual(ctx.appliedBendSemitones, 8, accuracy: 1e-4)
        param_shadow_set(shadow, kParamPitchWheelRaw, 0.0)      // fully down
        render(1)
        XCTAssertEqual(ctx.appliedBendSemitones, 4, accuracy: 1e-4)
        XCTAssertEqual(param_shadow_get(shadow, kParamPitchBend), 0.75, "the wheel must not move Tune")
    }

    func testTheModWheelSetsTheVowel() {
        XCTAssertEqual(RenderContext.parameter(forCC: 1), kParamVowel)
    }

    func testTheSameNoteTwiceIsReleasedByOneNoteOff() {
        ctx.noteOn(60, velocity: 1); ctx.noteOn(60, velocity: 1)
        render(2)
        ctx.noteOff(60)
        render(1)
        XCTAssertFalse(ctx.isNoteActive)
    }

    func testAStrayNoteOffDoesNotReleaseAHeldPadNote() {
        param_shadow_set(shadow, kParamXYNoteOn, 1)
        render(2)
        ctx.noteOff(64)                                          // never pressed
        render(400)
        XCTAssertNotEqual(monk_synth_is_active(ctx.engine!), 0, "the pad note was released")
    }

    func testAllNotesOffReleasesEveryHeldNote() {
        ctx.noteOn(60, velocity: 1); ctx.noteOn(64, velocity: 1)
        render(2)
        ctx.allNotesOff()
        XCTAssertFalse(ctx.isNoteActive)
        render(1000)
        XCTAssertEqual(monk_synth_is_active(ctx.engine!), 0, "a note stuck")
    }

    // MARK: - Through the AU's render block

    private func makeAU() throws -> MonkSynthAU {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                             componentSubType: 0x4D6E6B73, componentManufacturer: 0x5673746C,
                                             componentFlags: 0, componentFlagsMask: 0)
        let au = try MonkSynthAU(componentDescription: desc)
        try au.allocateRenderResources()
        return au
    }

    /// Renders one block of `frames` with `events` (sample offset within the
    /// block, three MIDI bytes) and returns the left channel.
    private func renderBlock(_ au: MonkSynthAU, at sampleTime: Float64, frames: AUAudioFrameCount = 512,
                             events: [(offset: Int64, bytes: (UInt8, UInt8, UInt8))] = []) -> [Float] {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        var nodes = events.map { e in
            AURenderEvent(MIDI: AUMIDIEvent(next: nil, eventSampleTime: AUEventSampleTime(sampleTime) + e.offset,
                                            eventType: .MIDI, reserved: 0, length: 3, cable: 0, data: e.bytes))
        }
        var ts = AudioTimeStamp()
        ts.mSampleTime = sampleTime
        ts.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        let block = au.internalRenderBlock
        nodes.withUnsafeMutableBufferPointer { p in
            for i in 0..<p.count where i + 1 < p.count {
                p[i].MIDI.next = UnsafeMutablePointer(p.baseAddress! + i + 1)
            }
            _ = block(&flags, &ts, frames, 0, buffer.mutableAudioBufferList,
                      p.count > 0 ? UnsafePointer(p.baseAddress!) : nil, nil)
        }
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(frames)))
    }

    func testANoteStartsOnItsSampleNotAtTheStartOfTheBuffer() throws {
        let au = try makeAU()
        defer { au.deallocateRenderResources() }
        let out = renderBlock(au, at: 1000, events: [(256, (0x90, 60, 100))])
        XCTAssertEqual(out[0..<256].map(abs).max() ?? 0, 0, "sound before the note's sample")
        XCTAssertGreaterThan(out[256..<512].map(abs).max() ?? 0, 0, "no sound after the note's sample")
    }

    func testAllNotesOffCCSilencesAHeldNote() throws {
        let au = try makeAU()
        defer { au.deallocateRenderResources() }
        var t: Float64 = 0
        _ = renderBlock(au, at: t, events: [(0, (0x90, 60, 100))]); t += 512
        _ = renderBlock(au, at: t, events: [(0, (0xB0, 123, 0))]); t += 512
        for _ in 0..<1000 { _ = renderBlock(au, at: t); t += 512 }
        XCTAssertEqual(renderBlock(au, at: t).map(abs).max() ?? 1, 0, accuracy: 1e-6)
    }

    func testAHostResetSilencesAHeldNote() throws {
        let au = try makeAU()
        defer { au.deallocateRenderResources() }
        var t: Float64 = 0
        _ = renderBlock(au, at: t, events: [(0, (0x90, 60, 100))]); t += 512
        au.reset()
        for _ in 0..<1000 { _ = renderBlock(au, at: t); t += 512 }
        XCTAssertEqual(renderBlock(au, at: t).map(abs).max() ?? 1, 0, accuracy: 1e-6)
    }

    /// A CC must reach the host as an ordinary parameter change, so the host
    /// records it as automation and its own controls follow.
    func testACCIsReportedToTheHostAsAParameterChange() throws {
        let au = try makeAU()
        defer { au.deallocateRenderResources() }
        let tree = try XCTUnwrap(au.parameterTree)
        var heard: [(AUParameterAddress, AUValue)] = []
        let token = tree.token(byAddingParameterObserver: { address, value in heard.append((address, value)) })
        defer { tree.removeParameterObserver(token) }

        _ = renderBlock(au, at: 0, events: [(0, (0xB0, 7, 64))])        // Level
        au.publishMIDIParameterChanges()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))     // observers are delivered async

        XCTAssertEqual(tree.parameter(withAddress: Param.level.rawValue)?.value ?? -1, 64.0 / 127, accuracy: 1e-5)
        XCTAssertTrue(heard.contains { $0.0 == Param.level.rawValue && abs($0.1 - 64.0 / 127) < 1e-5 },
                      "the host was not told: \(heard)")
    }

    /// The pitch wheel too — it is a parameter the host can record and play back.
    func testThePitchWheelIsReportedToTheHost() throws {
        let au = try makeAU()
        defer { au.deallocateRenderResources() }
        _ = renderBlock(au, at: 0, events: [(0, (0xE0, 0x7F, 0x7F))])  // fully up
        au.publishMIDIParameterChanges()
        XCTAssertEqual(au.parameterTree?.parameter(withAddress: Param.pitchWheelRaw.rawValue)?.value ?? -1, 1, accuracy: 1e-4)
    }

    /// Only what MIDI changed is reported — publishing never re-sends a value
    /// the host or the UI set itself.
    func testNothingIsReportedWithoutMIDI() throws {
        let au = try makeAU()
        defer { au.deallocateRenderResources() }
        let tree = try XCTUnwrap(au.parameterTree)
        var heard = 0
        let token = tree.token(byAddingParameterObserver: { _, _ in heard += 1 })
        defer { tree.removeParameterObserver(token) }
        _ = renderBlock(au, at: 0)
        au.publishMIDIParameterChanges()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(heard, 0)
    }

    func testTheModWheelMovesTheVowelKnobInTheEditor() throws {
        let vc = AudioUnitViewController()
        let desc = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                             componentSubType: 0x4D6E6B73, componentManufacturer: 0x5673746C,
                                             componentFlags: 0, componentFlagsMask: 0)
        let au = try vc.createAudioUnit(with: desc) as! MonkSynthAU
        try au.allocateRenderResources()
        defer { au.deallocateRenderResources() }
        vc.loadViewIfNeeded()
        _ = renderBlock(au, at: 0, events: [(0, (0xB0, 1, 127))])
        au.publishMIDIParameterChanges()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))     // observer is async, then hops to main
        let knob = (vc.view as! PluginView).controls.knob(for: .vowel)
        XCTAssertEqual(knob?.value ?? -1, 1, accuracy: 1e-4)
    }
}
