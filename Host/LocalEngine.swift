import AVFoundation
import os
import UIKit

/// Standalone audio path. Uses the same `RenderContext` as the AUv3 so the
/// standalone and the plugin cannot drift apart: the UI, the parameter
/// mapping, and the MIDI-CC/pitch-bend routing are all the exact same code
/// as `MonkSynthAU`, just driven by an `AVAudioEngine` source node instead
/// of a host's render block.
final class LocalEngine {

    enum StartError: LocalizedError {
        case formatUnavailable
        var errorDescription: String? {
            switch self {
            case .formatUnavailable:
                return NSLocalizedString(
                    "audio.error.format",
                    comment: "Could not build an audio format for the standalone engine")
            }
        }
    }

    /// Replaced wholesale after a media-services reset, when the old one is dead.
    private var engine = AVAudioEngine()
    private let shadow = param_shadow_new()!
    private let context: RenderContext
    private var sourceNode: AVAudioSourceNode?

    /// True between `start()` and `stop()`: the user wants sound. iOS stops
    /// the engine on its own — an interruption (call, Siri, alarm, another
    /// app taking the session), a route or format change, a media-services
    /// reset — and every one of those is likely over a long background. While
    /// this is set, each of them brings the engine back; before, the app
    /// stayed silent until it was killed.
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

    // MIDI note on/off cannot call straight into `RenderContext.noteOn`/
    // `noteOff` off the render thread — see `NoteEventQueue`'s doc comment.
    private let noteEvents = NoteEventQueue()

    // Reused across pitch-bend messages so `applyPitchBend` never allocates
    // on every wheel tick, mirroring `MonkSynthAU.internalRenderBlock`'s
    // `wheelTargets` buffer.
    private var wheelTargets = [(ParameterAddress, Float)]()

    init() {
        for p in Param.allCases { param_shadow_set(shadow, p.address, p.defaultValue) }
        context = RenderContext(shadow: shadow)
        wheelTargets.reserveCapacity(2)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        param_shadow_free(shadow)
    }

    // MARK: - Parameters (any thread — the shadow is lock-free)

    func setParameter(_ param: Param, _ value: Float) {
        param_shadow_set(shadow, param.address, value)
    }

    func value(of param: Param) -> Float { param_shadow_get(shadow, param.address) }

    /// Upstream controller.cpp:423-452 plus processor.cpp:208-245, replayed
    /// here exactly as `MonkSynthAU.internalRenderBlock` replays it for a
    /// hosted pitch wheel: `RenderContext.pitchWheelTargets` decides which
    /// parameter(s) a raw 0...1 wheel position fans out to (plain vowel,
    /// pitch bend, or both, depending on the routing mode) and this writes
    /// the result straight into the shadow — safe from any thread, same as
    /// `setParameter`.
    func applyPitchBend(_ normalized: Float) {
        context.pitchWheelTargets(normalized, into: &wheelTargets)
        for (addr, v) in wheelTargets { param_shadow_set(shadow, addr, v) }
    }

    // MARK: - MIDI notes (any thread — queued, applied on the render thread)

    func noteOn(_ note: UInt8, velocity: Float) { noteEvents.push(.on, note: note, velocity: velocity) }
    func noteOff(_ note: UInt8) { noteEvents.push(.off, note: note, velocity: 0) }

    // MARK: - UI animation (main thread — published by the render thread)

    var uiVowel: Float { context.uiVowel.pointee }
    var uiAmplitude: Float { context.uiAmplitude.pointee }
    var uiNoteActive: Bool { context.uiActive.pointee != 0 }

    // MARK: - Lifecycle

    func start() throws {
        wantsRunning = true
        installObservers()
        try activateSession()
        try buildGraph()
        try engine.start()
    }

    func stop() {
        wantsRunning = false
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var isRunning: Bool { engine.isRunning }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback + .mixWithOthers: a synth with no input, able to run
        // alongside AUM. An input-capable category would demand a microphone
        // usage string and prompt the user for no reason.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    /// (Re)builds the source node for the current hardware format and a fresh
    /// DSP engine at that rate. Called only while `engine` is stopped, so the
    /// render thread is not running. `createEngine` clears `RenderContext`'s
    /// diff cache, so every parameter in the shadow is re-applied on the
    /// first render — nothing the user set is lost.
    private func buildGraph() throws {
        if let old = sourceNode {
            engine.detach(old)
            sourceNode = nil
        }
        let session = AVAudioSession.sharedInstance()
        // `engine.outputNode.inputFormat(forBus:)` reflects the *engine's*
        // internal processing format for that bus, not the raw hardware
        // ASBD — AVAudioEngine nodes always talk to each other in canonical
        // deinterleaved Float32, so this can never come back interleaved.
        // Empirically probed on the iOS 26.2 simulator (iPhone 16e): even
        // queried before `engine.start()`, right after session activation,
        // it already reports a sane 2-channel/48kHz format here. But this is
        // a fresh `AVAudioEngine` queried pre-`start()`, and other
        // devices/OS versions are documented to occasionally report a
        // degenerate 0-channel or 0Hz format in that window (the graph
        // hasn't necessarily bound to the hardware route yet) — so rather
        // than trust its channel count blindly, only the *sample rate* is
        // taken from it (falling back to the session's, then to 44100), and
        // the channel count is always forced to 2 explicitly, matching
        // `MonkSynthAU`'s own fixed stereo output bus. That closes the
        // hazard completely: a degenerate `inputFormat` can never silently
        // turn the render callback's `abl.count >= 2` guard into permanent
        // silence by handing it a mono or zero-channel format.
        let hwFormat = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate
                        : (session.sampleRate > 0 ? session.sampleRate : 44100)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw StartError.formatUnavailable
        }

        context.createEngine(sampleRate: sampleRate)
        let ctx = context
        let events = noteEvents
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            // Drain queued MIDI note on/off onto THIS thread — the same
            // thread `ctx.render` runs on — before rendering, so they never
            // race with it. See `NoteEventQueue`.
            events.drain { kind, note, velocity in
                switch kind {
                case .on:  ctx.noteOn(note, velocity: velocity)
                case .off: ctx.noteOff(note)
                }
            }

            // `format` is always exactly the 2-channel deinterleaved Float32
            // this node was constructed with (see above), so `abl.count`
            // is guaranteed 2 here — the guard is defensive, not load-bearing.
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = abl[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            ctx.render(left: l, right: r, frames: frameCount)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Recovery (main thread)

    /// Brings sound back after the system stopped it. `rebuild` re-reads the
    /// hardware format (a route change can change the sample rate);
    /// `newEngine` replaces the engine outright (after a media-services reset
    /// the old one is unusable).
    private func recover(rebuild: Bool, newEngine: Bool = false) {
        guard wantsRunning else { return }
        engine.stop()
        if newEngine {
            sourceNode = nil
            engine = AVAudioEngine()
        }
        do {
            try activateSession()
            if rebuild || sourceNode == nil { try buildGraph() }
            try engine.start()
        } catch {
            Self.log.error("audio recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
                // A synth sits silent until played, so resuming is always
                // right — no need to honour `.shouldResume`.
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                self?.recover(rebuild: false)
            },
            nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                self?.recover(rebuild: true, newEngine: true)
            },
            // Posted by whichever engine is current, so match on identity.
            nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
                guard let self, (note.object as AnyObject?) === self.engine else { return }
                self.recover(rebuild: true)
            },
            // The catch-all: anything that stopped the engine while we were
            // away and didn't announce itself.
            nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, !self.engine.isRunning else { return }
                self.recover(rebuild: false)
            },
        ]
    }

    private static let log = Logger(subsystem: "com.vestal.monksynth", category: "audio")

    // MARK: - Testing seam

    /// Stops the engine the way the system does — without the user asking —
    /// so tests can check that each recovery path brings it back.
    func simulateSystemStop() { engine.stop() }

    /// Posts the configuration-change notification as the current engine.
    func postConfigurationChangeForTesting() {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }

    /// Lets tests capture actually-rendered audio via `AVAudioEngine`'s tap
    /// API without exposing the whole `AVAudioEngine` to production code —
    /// nothing outside this file needs it. Only meaningful after `start()`.
    func installTestTap(bufferSize: AVAudioFrameCount = 512,
                         _ block: @escaping (AVAudioPCMBuffer) -> Void) {
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            block(buffer)
        }
    }
}

/// A tiny single-producer/single-consumer queue that hands MIDI note on/off
/// events from CoreMIDI's own receive thread over to the audio render
/// thread.
///
/// Why this exists: `RenderContext`'s own header comment says "every method
/// here runs on the render thread: no allocation, no locks, no logging," and
/// `monk_synth_note_on`/`monk_synth_note_off` (dsp/synth.c) back that up —
/// they mutate `held[]`/`voices[]` with zero synchronization of their own.
/// In the AUv3 extension that contract is upheld for free: the host delivers
/// MIDI events through the *same* render-block invocation as the audio that
/// follows them, so `ctx.noteOn`/`noteOff` and `ctx.render` only ever run
/// serialized on one thread. The standalone has no such host — CoreMIDI
/// calls its receive block on a high-priority thread CoreMIDI owns, entirely
/// independent of `AVAudioSourceNode`'s render thread. Calling
/// `RenderContext.noteOn`/`noteOff` directly from that thread would race
/// with a concurrent `render()` call on shared, unsynchronized voice state.
///
/// This queue restores the AUv3's invariant instead of touching `RenderContext`
/// or `dsp/`: the MIDI thread only ever *enqueues* (never touches the
/// engine), and the render callback drains the queue immediately before
/// calling `ctx.render`, applying every event on the render thread — same
/// as the AUv3.
///
/// Parameter/CC/pitch-bend writes don't need this: they land in
/// `ParamShadow`, which is genuinely lock-free (`_Atomic float`, see
/// ParameterShadow.c) and safe to write from any thread — only note on/off
/// bypass the shadow and touch the engine directly.
private final class NoteEventQueue {
    enum Kind { case on, off }

    private struct Event { var kind: Kind; var note: UInt8; var velocity: Float }

    // Fixed capacity, never resized: growing this array on the MIDI thread
    // would be fine (not the render thread), but a bounded ring means a
    // pathological flood of MIDI just drops the oldest-not-yet-drained
    // events rather than growing without limit.
    private var buffer: [Event?]
    private var head = 0   // consumer-owned (render thread)
    private var tail = 0   // producer-owned (MIDI thread)

    // `os_unfair_lock` rather than `NSLock`/`DispatchSemaphore`: it's the
    // primitive Apple specifically recommends for brief, low-contention
    // critical sections on threads that care about priority inversion
    // (it donates priority to the lock holder, unlike the deprecated
    // `OSSpinLock`), which is exactly this queue's shape — a handful of
    // array/index writes, held only ever by one producer or one consumer at
    // a time. As a stored property of this class, its address is stable for
    // the object's lifetime, so `&lock` below is always valid.
    private var lock = os_unfair_lock()

    init(capacity: Int = 256) {
        buffer = [Event?](repeating: nil, count: capacity)
    }

    /// Called from CoreMIDI's receive thread.
    func push(_ kind: Kind, note: UInt8, velocity: Float) {
        os_unfair_lock_lock(&lock)
        let next = (tail + 1) % buffer.count
        if next != head {   // full: drop rather than block/allocate
            buffer[tail] = Event(kind: kind, note: note, velocity: velocity)
            tail = next
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Called from the render thread, immediately before rendering.
    func drain(_ apply: (Kind, UInt8, Float) -> Void) {
        while true {
            os_unfair_lock_lock(&lock)
            guard head != tail, let e = buffer[head] else {
                os_unfair_lock_unlock(&lock)
                return
            }
            buffer[head] = nil
            head = (head + 1) % buffer.count
            os_unfair_lock_unlock(&lock)
            apply(e.kind, e.note, e.velocity)
        }
    }
}
