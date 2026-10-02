import CoreMIDI

/// CoreMIDI input for the standalone app: connects every available source —
/// at launch and as they're hot-plugged afterward — and decodes MIDI 1.0
/// UMP words into note/CC/pitch-bend callbacks.
///
/// All four callbacks fire on whatever thread CoreMIDI calls the receive
/// block on (its own high-priority thread, never the main thread and never
/// the audio render thread) — callers that touch UIKit must hop to main
/// themselves; callers that only write into a lock-free structure (like
/// `LocalEngine.setParameter`/`applyPitchBend`, or `LocalEngine.noteOn`/
/// `noteOff`, which queue rather than touch the engine directly — see
/// `NoteEventQueue`) can call straight through.
final class MIDIInput {

    var onNoteOn: ((UInt8, Float) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?
    var onControlChange: ((UInt8, Float) -> Void)?
    /// Raw 0...1 wheel position (0.5 == center) — the same normalization
    /// `MonkSynthAU.internalRenderBlock` computes for a hosted pitch wheel.
    var onPitchBend: ((Float) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()

    // Endpoints already connected to `inputPort`. `MIDIClientCreateWithBlock`'s
    // notify block fires for *any* setup change — not just "a source
    // appeared," and with no guarantee of firing exactly once per source —
    // so this set, not the notification's cardinality, is what makes
    // reconnecting on every notification idempotent: `connectAllSources()`
    // can be called any number of times and only ever calls
    // `MIDIPortConnectSource` once per still-present source.
    private var connectedSources = Set<MIDIEndpointRef>()

    init() {
        var midiClient = MIDIClientRef()
        MIDIClientCreateWithBlock("MonkSynth" as CFString, &midiClient) { [weak self] _ in
            // A device plugged in, removed, or renamed — cheap and safe to
            // handle uniformly by re-scanning every known source; see
            // `connectAllSources` for why that's safe to call repeatedly.
            self?.connectAllSources()
        }
        client = midiClient

        var port = MIDIPortRef()
        MIDIInputPortCreateWithProtocol(
            client, "MonkSynth Input" as CFString, ._1_0, &port
        ) { [weak self] evtList, _ in
            self?.handle(evtList)
        }
        inputPort = port

        connectAllSources()
    }

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Connects every currently-available source not already connected, and
    /// forgets bookkeeping for ones that disappeared — so if a *different*
    /// device later reuses the same `MIDIEndpointRef` value (CoreMIDI does
    /// recycle these), it's treated as new rather than skipped as
    /// "already connected." Idempotent: safe to call from `init` and from
    /// every subsequent notification.
    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        var present = Set<MIDIEndpointRef>()
        present.reserveCapacity(count)
        for i in 0..<count {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }
            present.insert(source)
            guard !connectedSources.contains(source) else { continue }
            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connectedSources.insert(source)
            }
        }
        connectedSources.formIntersection(present)
    }

    // MARK: - MIDI 1.0 UMP decode

    /// Walks the variable-length `MIDIEventList`/`MIDIEventPacket` chain
    /// without ever materializing a whole `MIDIEventPacket` value (its
    /// `words` field is declared as a fixed 64-element array/tuple; loading
    /// it wholesale would read past the packet's real, possibly much
    /// shorter, extent within CoreMIDI's buffer). Instead every access goes
    /// through `MemoryLayout.offset(of:)` plus raw-pointer loads of exactly
    /// as many words as `wordCount` says are actually present — mirroring
    /// the C macro `MIDIEventPacketNext` (`(MIDIEventPacket *)(&pkt->words[pkt->wordCount])`)
    /// by hand, since that macro isn't reliably callable from Swift.
    private func handle(_ evtList: UnsafePointer<MIDIEventList>) {
        let packetCount = Int(evtList.pointee.numPackets)
        guard packetCount > 0 else { return }
        let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words)!

        withUnsafePointer(to: evtList.pointee.packet) { firstPacket in
            var packetPtr = firstPacket
            for _ in 0..<packetCount {
                let wordCount = Int(packetPtr.pointee.wordCount)
                let wordsPtr = UnsafeRawPointer(packetPtr)
                    .advanced(by: wordsOffset)
                    .assumingMemoryBound(to: UInt32.self)
                for i in 0..<min(wordCount, 64) { decode(wordsPtr[i]) }

                packetPtr = UnsafeRawPointer(packetPtr)
                    .advanced(by: wordsOffset + wordCount * MemoryLayout<UInt32>.size)
                    .assumingMemoryBound(to: MIDIEventPacket.self)
            }
        }
    }

    /// A MIDI 1.0 Channel Voice UMP word (message type 0x2) packs a
    /// complete classic 3-byte MIDI message into 32 bits: byte0 = [type |
    /// group], byte1 = [status | channel], byte2 = data1, byte3 = data2 —
    /// so, unlike sysex, it's always exactly one word and needs no
    /// cross-word state. Every other message type (utility, sysex7, MIDI 2.0
    /// channel voice, data) is skipped: `MIDIInputPortCreateWithProtocol`
    /// was created with `._1_0`, so CoreMIDI converts everything to this
    /// protocol, and a synth listening for notes/CC/bend has no use for the
    /// others.
    private func decode(_ word: UInt32) {
        guard (word >> 28) & 0xF == 0x2 else { return }
        let status = UInt8((word >> 20) & 0xF)
        let data1 = UInt8((word >> 8) & 0x7F)
        let data2 = UInt8(word & 0x7F)
        switch status {
        case 0x9 where data2 > 0: onNoteOn?(data1, Float(data2) / 127.0)
        case 0x8, 0x9:             onNoteOff?(data1)
        case 0xB:                  onControlChange?(data1, Float(data2) / 127.0)
        case 0xE:
            // data1 = LSB (byte2), data2 = MSB (byte3) — same ordering as
            // MonkSynthAU.internalRenderBlock's `0xE0` case.
            let raw = (Int(data2) << 7) | Int(data1)
            onPitchBend?(Float(raw) / 16383.0)
        default: break
        }
    }
}
