import AVFoundation
import XCTest
@testable import MonkSynth

/// Covers `FactoryVoiceTable` and the six characters built on top of it
/// (`DogCharacter`, `GhostCharacter`, `FireFighterCharacter`,
/// `PunkCharacter`, `PizzaCharacter`, `CatCharacter`) — see the task: "give
/// upstream's six factory sounds their own characters," replacing the
/// earlier, now-deleted `FactoryPresetCharacter` (which borrowed a face from
/// one of the original six instead of drawing its own, and broke "one
/// preset per character" in the process).
///
/// The first half is shape coverage: every new character's `savedParameters`
/// is exactly its assigned preset's own raw values, and the mapping is a
/// true bijection onto all six presets. The second half
/// (`testBrightnessOrderingMatchesTheBakedCharacterMapping`) is what the
/// task specifically asks for: an independent re-measurement of spectral
/// centroid for all six factory presets, rendered fresh through the
/// vendored C DSP exactly like `CharacterVoiceTests` already does for the
/// original six, asserting the declared darkest-to-brightest character
/// ordering the mapping was built against still holds. This is what keeps
/// the mapping honest rather than a one-off eyeballed guess: if a preset's
/// own values (`kFactoryPresets`, upstream's own extracted data) are ever
/// retuned and the brightness ordering silently shifts as a result, this
/// test fails instead of the app quietly shipping a mapping the numbers no
/// longer back up.
final class FactoryVoiceCharacterTests: XCTestCase {

    /// The six new characters, darkest to brightest by DESIGN (see
    /// `FactoryVoiceTable`'s doc comment for the archetype reasoning) — the
    /// order `testBrightnessOrderingMatchesTheBakedCharacterMapping` asserts
    /// the fresh measurement still produces.
    private static let byDesignedBrightness = ["dog", "ghost", "firefighter", "punk", "pizza", "cat"]

    // MARK: - Rendering (mirrors CharacterVoiceTests.render exactly — see
    // that file's doc comment for why: a held MIDI note, a preset's own raw
    // values rendered through the same RenderContext/param_shadow production
    // code path uses.)

    private static let sampleRate: Double = 44100
    private static let block = 512
    private static let noteOffFrame = Int(sampleRate * 1.0)
    private static let totalFrames = Int(sampleRate * 2.5)

    private static func render(_ values: [AUValue]) -> [Float] {
        let shadow = param_shadow_new()!
        defer { param_shadow_free(shadow) }
        for p in Param.allCases { param_shadow_set(shadow, p.address, p.defaultValue) }
        for (i, v) in values.enumerated() where i < Param.allCases.count {
            param_shadow_set(shadow, Param.address(atIndex: i), v)
        }

        let ctx = RenderContext(shadow: shadow)
        ctx.createEngine(sampleRate: sampleRate)
        defer { ctx.destroyEngine() }

        var output = [Float](repeating: 0, count: totalFrames)
        var l = [Float](repeating: 0, count: block)
        var r = [Float](repeating: 0, count: block)
        var pos = 0
        var notedOn = false
        var notedOff = false
        while pos < totalFrames {
            if !notedOn { ctx.noteOn(60, velocity: 0.8); notedOn = true }
            if !notedOff && pos >= noteOffFrame { ctx.noteOff(60); notedOff = true }
            let n = min(block, totalFrames - pos)
            l.withUnsafeMutableBufferPointer { lb in
                r.withUnsafeMutableBufferPointer { rb in
                    ctx.render(left: lb.baseAddress!, right: rb.baseAddress!, frames: UInt32(n))
                }
            }
            for i in 0..<n { output[pos + i] = l[i] }
            pos += n
        }
        return output
    }

    // MARK: - Spectral analysis (self-contained duplicate of
    // CharacterVoiceTests' own FFT/Welch-centroid helpers — that file's
    // versions are `private` to it, so this re-implements rather than
    // reaches across files. Same algorithm, same reasoning: see
    // CharacterVoiceTests.spectralCentroid's doc comment for why
    // Welch-averaged Hann-windowed centroid, not a single raw-DFT window.)

    private struct Complex { var re: Double; var im: Double }

    private func fft(_ a: inout [Complex]) {
        let n = a.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while bit > 0 && j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { a.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2.0 * Double.pi / Double(len)
            let wlen = Complex(re: cos(ang), im: sin(ang))
            var i = 0
            while i < n {
                var w = Complex(re: 1, im: 0)
                for k in 0..<(len / 2) {
                    let u = a[i + k]
                    let t = a[i + k + len / 2]
                    let v = Complex(re: t.re * w.re - t.im * w.im, im: t.re * w.im + t.im * w.re)
                    a[i + k] = Complex(re: u.re + v.re, im: u.im + v.im)
                    a[i + k + len / 2] = Complex(re: u.re - v.re, im: u.im - v.im)
                    w = Complex(re: w.re * wlen.re - w.im * wlen.im, im: w.re * wlen.im + w.im * wlen.re)
                }
                i += len
            }
            len <<= 1
        }
    }

    private func spectralCentroid(_ samples: [Float], start: Int, span: Int,
                                   windowSize: Int = 4096, sampleRate: Double) -> Double {
        let hop = windowSize / 2
        let nsegs = max(1, (span - windowSize) / hop + 1)
        var avgPower = [Double](repeating: 0, count: windowSize / 2)
        for s in 0..<nsegs {
            let off = start + s * hop
            var a = [Complex](repeating: Complex(re: 0, im: 0), count: windowSize)
            for i in 0..<windowSize {
                let w = 0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(windowSize - 1))
                a[i] = Complex(re: Double(samples[off + i]) * w, im: 0)
            }
            fft(&a)
            for k in 0..<(windowSize / 2) {
                let mag = (a[k].re * a[k].re + a[k].im * a[k].im).squareRoot()
                avgPower[k] += mag * mag
            }
        }
        var weighted = 0.0
        var magSum = 0.0
        for k in 1..<(windowSize / 2) {   // skip DC
            let p = avgPower[k] / Double(nsegs)
            let freq = Double(k) * sampleRate / Double(windowSize)
            weighted += freq * p
            magSum += p
        }
        return magSum > 0 ? weighted / magSum : 0
    }

    /// Same 0.2s..1.0s analysis window `CharacterVoiceTests.centroid`/the
    /// deleted `FactoryPresetFaceTests.centroid` used — entirely before
    /// note-off, well after attack has settled into sustain for any of the
    /// six presets.
    private func centroid(_ samples: [Float]) -> Double {
        let start = Int(Self.sampleRate * 0.2)
        let span = Int(Self.sampleRate * 0.8)
        return spectralCentroid(samples, start: start, span: span, sampleRate: Self.sampleRate)
    }

    /// Every factory preset's measured centroid, keyed by name — computed
    /// once and shared by every test in this file.
    private static let presetCentroids: [String: Double] = {
        let instance = FactoryVoiceCharacterTests()
        var result: [String: Double] = [:]
        for preset in kFactoryPresets {
            result[preset.name] = instance.centroid(render(preset.values))
        }
        return result
    }()

    // MARK: - The measured mapping test

    /// The task's core requirement: re-measure and assert the mapping still
    /// holds. `FactoryVoiceTable.presetForCharacter` was built by ranking
    /// the six factory presets darkest-to-brightest by measured centroid and
    /// assigning them, in that order, to `byDesignedBrightness` — this test
    /// re-runs the measurement fresh and asserts each character's assigned
    /// preset is still strictly brighter than the previous character's, the
    /// same "declared order + strictly increasing" pattern
    /// `CharacterVoiceTests.testFullBrightnessOrderingAcrossAllSixCharacters`
    /// already uses for the original six. If `kFactoryPresets` (upstream's
    /// own extracted data) is ever regenerated with different values and the
    /// ordering shifts, this fails instead of the app quietly shipping a
    /// mapping the numbers no longer back up.
    func testBrightnessOrderingMatchesTheBakedCharacterMapping() throws {
        let entries = try Self.byDesignedBrightness.map { characterID -> (String, Double) in
            let presetName = try XCTUnwrap(FactoryVoiceTable.presetForCharacter[characterID],
                                            "\(characterID) has no entry in FactoryVoiceTable.presetForCharacter")
            let measured = try XCTUnwrap(Self.presetCentroids[presetName],
                                          "no measured centroid for preset \(presetName)")
            return (characterID, measured)
        }
        for i in 0..<(entries.count - 1) {
            XCTAssertLessThan(entries[i].1, entries[i + 1].1,
                "expected \(entries[i].0) (\(entries[i].1) Hz) < \(entries[i + 1].0) (\(entries[i + 1].1) Hz) — " +
                "full designed brightness ordering: \(entries)")
        }
    }

    // MARK: - FactoryVoiceTable shape

    /// The mapping is a true BIJECTION: exactly the six new characters,
    /// exactly the six factory presets, no repeats on either side — the
    /// mechanical form of "one preset per character" for this table
    /// specifically (the broader roster-wide invariant, covering the built-
    /// in/user-entry split too, lives in `CharacterTests`).
    func testMappingIsABijectionOntoAllSixFactoryPresets() {
        let characterIDs = Set(FactoryVoiceTable.presetForCharacter.keys)
        XCTAssertEqual(characterIDs, Set(Self.byDesignedBrightness),
            "FactoryVoiceTable.presetForCharacter's keys don't match the six new character ids")

        let presetNames = Array(FactoryVoiceTable.presetForCharacter.values)
        XCTAssertEqual(Set(presetNames).count, presetNames.count,
            "two new characters share the same factory preset: \(presetNames)")
        XCTAssertEqual(Set(presetNames), Set(kFactoryPresets.map(\.name)),
            "FactoryVoiceTable.presetForCharacter's values don't cover exactly the six factory presets")
    }

    func testValuesForUnknownCharacterIDReturnsNil() {
        XCTAssertNil(FactoryVoiceTable.values(for: "not-a-real-character"))
    }

    /// The six ORIGINAL characters must never gain a factory-preset voice —
    /// they stay hand-tuned via `CharacterVoiceTable`, untouched by this
    /// task per its own constraints.
    func testOriginalSixCharactersHaveNoFactoryVoiceTableEntry() {
        for id in ["monk", "fish", "unicorn", "girl", "oldman", "cow"] {
            XCTAssertNil(FactoryVoiceTable.values(for: id),
                "\(id) must not have a FactoryVoiceTable entry — it keeps its hand-tuned CharacterVoiceTable voice")
        }
    }

    // MARK: - The six new characters' shape

    private static let newCharacters: [Character] = [
        DogCharacter(), GhostCharacter(), FireFighterCharacter(),
        PunkCharacter(), PizzaCharacter(), CatCharacter(),
    ]

    /// Selecting one of the six new characters applies ITS OWN preset,
    /// never a `CharacterVoiceTable` voice — the same regression
    /// `UserCharacter`/the deleted `FactoryPresetCharacter` already guarded
    /// for a saved/borrowed patch, proven here for these six's own
    /// first-class `savedParameters`.
    func testEveryNewCharactersSavedParametersMatchItsAssignedPresetExactly() throws {
        for character in Self.newCharacters {
            let presetName = try XCTUnwrap(FactoryVoiceTable.presetForCharacter[character.id])
            let preset = try XCTUnwrap(kFactoryPresets.first(where: { $0.name == presetName }))
            let saved = try XCTUnwrap(character.savedParameters,
                "\(character.id) must carry its own saved parameters")
            for p in Param.allCases where Int(p.rawValue) < preset.values.count {
                XCTAssertEqual(saved[p], preset.values[Int(p.rawValue)],
                    "\(character.id)'s savedParameters must be exactly \(presetName)'s own values")
            }
        }
    }

    /// Every new character is its own face — never borrows another built-in's
    /// look, unlike the deleted `FactoryPresetCharacter`. `faceID` defaults
    /// to `id` (see `Character`'s own protocol extension); this is what
    /// keeps that default in force for all six.
    func testEveryNewCharacterIsItsOwnFace() {
        for character in Self.newCharacters {
            XCTAssertEqual(character.faceID, character.id, "\(character.id) must be its own face")
        }
    }

    func testAllSixNewCharactersAreInTheRegistry() {
        let registryIDs = Set(CharacterRegistry.all.map(\.id))
        for character in Self.newCharacters {
            XCTAssertTrue(registryIDs.contains(character.id), "\(character.id) is missing from CharacterRegistry.all")
        }
    }
}
