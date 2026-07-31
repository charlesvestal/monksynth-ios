import AVFoundation
import XCTest
@testable import MonkSynth

/// Covers `FactoryPresetCharacter`/`FactoryPresetFaceTable` — bringing
/// upstream's six factory presets (`kFactoryPresets`) back into the single
/// in-app character list, each wearing a face borrowed from the six
/// built-ins (see `FactoryPresetCharacter.swift`'s doc comment: none of the
/// six shipped with art of their own, and this task deliberately draws none
/// new).
///
/// The first half is ordinary `Character`-conformance/shape coverage. The
/// second half (`testBakedFaceTableMatchesNearestMeasuredFaceForEveryPreset`)
/// is the one the task specifically asks for: an independent re-measurement
/// of spectral centroid for all twelve voices (six factory presets, six
/// built-in characters), rendered fresh through the vendored C DSP exactly
/// like `CharacterVoiceTests` already does for the six built-ins, asserting
/// the BAKED `FactoryPresetFaceTable` still names the nearest one. This is
/// what keeps the mapping honest rather than a one-off eyeballed guess: if a
/// character's voice (`CharacterVoiceTable`) or a factory preset's own
/// values (`kFactoryPresets`, upstream's own extracted data) are ever
/// retuned, and the nearest face silently shifts as a result, this test
/// fails instead of the app quietly shipping a mapping the numbers no longer
/// back up.
final class FactoryPresetFaceTests: XCTestCase {

    // MARK: - Rendering (mirrors CharacterVoiceTests.render exactly — see
    // that file's doc comment for why: a held MIDI note, full 15-voice-param
    // set applied over defaults for the character path, or a preset's own
    // raw values for the factory-preset path, rendered through the same
    // RenderContext/param_shadow production code path uses.)

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

    /// A built-in character's voice, expressed the same way a factory
    /// preset's raw values are: a full `Param.allCases`-length array with
    /// the voice's 15 characterising parameters overlaid on every other
    /// parameter's default — exactly what selecting that character in the
    /// app actually applies (`CharacterVoiceTable.voice(for:)`).
    private static func renderVoice(_ voice: [Param: AUValue]) -> [Float] {
        var values = Param.allCases.map(\.defaultValue)
        for (p, v) in voice { values[Int(p.rawValue)] = v }
        return render(values)
    }

    // MARK: - Spectral analysis (self-contained duplicate of
    // CharacterVoiceTests' own FFT/Welch-centroid helpers — that file's
    // versions are `private` to it, and this file measures a different set
    // of renders (factory presets, not just the six built-ins), so it
    // re-implements rather than reaches across files. Same algorithm, same
    // reasoning: see CharacterVoiceTests.spectralCentroid's doc comment for
    // why Welch-averaged Hann-windowed centroid, not a single raw-DFT
    // window.)

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

    /// Same 0.2s..1.0s analysis window `CharacterVoiceTests.centroid` uses —
    /// entirely before note-off, well after even the slowest attack among
    /// the twelve voices measured here has settled into sustain.
    private func centroid(_ samples: [Float]) -> Double {
        let start = Int(Self.sampleRate * 0.2)
        let span = Int(Self.sampleRate * 0.8)
        return spectralCentroid(samples, start: start, span: span, sampleRate: Self.sampleRate)
    }

    /// Every built-in character's measured centroid, keyed by id — computed
    /// once and shared by every test in this file, mirroring
    /// `CharacterVoiceTests.rendered`'s identical "render once, reuse"
    /// shape.
    private static let characterCentroids: [String: Double] = {
        let instance = FactoryPresetFaceTests()
        var result: [String: Double] = [:]
        for character in CharacterRegistry.all {
            let samples = renderVoice(CharacterVoiceTable.voice(for: character))
            result[character.id] = instance.centroid(samples)
        }
        return result
    }()

    /// Every factory preset's measured centroid, keyed by name — computed
    /// once, same reasoning as `characterCentroids`.
    private static let presetCentroids: [String: Double] = {
        let instance = FactoryPresetFaceTests()
        var result: [String: Double] = [:]
        for preset in kFactoryPresets {
            result[preset.name] = instance.centroid(render(preset.values))
        }
        return result
    }()

    /// The built-in id whose measured centroid is closest to `hz` — the
    /// actual "assign by measured sonic similarity" rule from the task,
    /// applied fresh against whatever `Self.characterCentroids` says right
    /// now.
    private func nearestFace(to hz: Double) -> String {
        Self.characterCentroids.min(by: { abs($0.value - hz) < abs($1.value - hz) })!.key
    }

    // MARK: - The measured mapping test

    /// The task's core requirement: "Bake the final mapping in as data ...
    /// with the measurement living in a test that asserts the mapping still
    /// matches what the audio says." For every one of the six factory
    /// presets, the face `FactoryPresetFaceTable` bakes in must equal the
    /// nearest built-in by a FRESH measurement, not a stale number copied
    /// into a comment. See `FactoryPresetFaceTable`'s own doc comment for
    /// the measured numbers and the two things worth knowing about the
    /// result: Dorje and Rabten both land on "monk" (Rabten's patch IS
    /// upstream's own all-defaults patch, byte-for-byte the same as
    /// `CharacterVoiceTable.monk`), and no preset lands on "cow".
    func testBakedFaceTableMatchesNearestMeasuredFaceForEveryPreset() {
        for preset in kFactoryPresets {
            let measured = Self.presetCentroids[preset.name]!
            let nearest = nearestFace(to: measured)
            let baked = FactoryPresetFaceTable.faceID(for: preset.name)
            XCTAssertEqual(baked, nearest,
                "\(preset.name)'s baked face (\"\(baked)\") no longer matches the measured nearest " +
                "face (\"\(nearest)\", preset centroid \(measured) Hz vs. character centroids " +
                "\(Self.characterCentroids)) — retune FactoryPresetFaceTable, or investigate why a " +
                "voice moved")
        }
    }

    /// Every one of the six factory presets actually has an entry in the
    /// baked table — a preset silently missing an entry would fall back to
    /// monk without the mapping test above ever catching it (there'd be
    /// nothing to compare against a "missing" baked value).
    func testEveryFactoryPresetHasABakedFaceEntry() {
        for preset in kFactoryPresets {
            XCTAssertNotNil(FactoryPresetFaceTable.faces[preset.name],
                "\(preset.name) has no entry in FactoryPresetFaceTable.faces")
        }
    }

    /// Unknown face id falls back to monk — the task's decision 5, exercised
    /// here the same way `CharacterRegistry.character(withID:)`'s own
    /// fallback is exercised elsewhere: a preset name the table was never
    /// taught about.
    func testUnknownPresetNameFallsBackToMonkFace() {
        XCTAssertEqual(FactoryPresetFaceTable.faceID(for: "Not A Real Preset"), "monk")
    }

    // MARK: - FactoryPresetCharacter shape

    func testEveryFactoryPresetCharacterHasANonNilFaceMatchingTheBakedTable() {
        for character in FactoryPresetCharacter.all {
            XCTAssertEqual(character.faceID, FactoryPresetFaceTable.faceID(for: character.displayName))
            XCTAssertTrue(CharacterRegistry.all.contains { $0.id == character.faceID },
                "\(character.displayName)'s faceID (\"\(character.faceID)\") must resolve to a real built-in")
        }
    }

    /// `FactoryPresetCharacter.all` lists all six, in `kFactoryPresets`' own
    /// order — the same order a host sees via `AUAudioUnit.factoryPresets`
    /// (`PresetTests.testSixFactoryPresetsInOrder`).
    func testFactoryPresetCharacterAllMatchesKFactoryPresetsNamesInOrder() {
        XCTAssertEqual(FactoryPresetCharacter.all.map(\.displayName), kFactoryPresets.map(\.name))
    }

    /// Every factory preset character's `id` is unique and distinct from
    /// every built-in id — no collision even if a preset happened to share
    /// a name with a built-in character (none of the six do, but the
    /// namespacing shouldn't rely on that).
    func testFactoryPresetCharacterIDsAreUniqueAndNamespaced() {
        let ids = FactoryPresetCharacter.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate factory preset ids: \(ids)")
        let builtinIDs = Set(CharacterRegistry.all.map(\.id))
        for id in ids {
            XCTAssertTrue(id.hasPrefix("factory:"), "\(id) is not namespaced with \"factory:\"")
            XCTAssertFalse(builtinIDs.contains(id), "\(id) collides with a built-in id")
        }
    }

    /// The core regression `UserCharacter` already guards for saved user
    /// presets, proven here for factory presets too: selecting one must
    /// apply ITS OWN parameters, never the borrowed face's built-in voice.
    func testFactoryPresetCharacterSavedParametersAreItsOwnNotTheFacesBuiltInVoice() {
        for character in FactoryPresetCharacter.all {
            let saved = character.savedParameters
            XCTAssertNotNil(saved, "\(character.displayName) must carry its own saved parameters")
            for p in Param.allCases where Int(p.rawValue) < character.preset.values.count {
                XCTAssertEqual(saved?[p], character.preset.values[Int(p.rawValue)],
                    "\(character.displayName)'s savedParameters must be exactly its own preset values, not the face's voice")
            }
            // Distinct from the borrowed face's own built-in voice for at
            // least one parameter — otherwise this test couldn't actually
            // tell "its own patch" apart from "the face's voice" for a
            // preset that happened to coincide with its face's defaults
            // (Rabten IS the monk/default voice — see the table's own doc
            // comment — so it's deliberately excluded from this specific
            // check, which is about DISTINCTNESS, not about every preset
            // sounding different from its face).
            guard character.displayName != "Rabten" else { continue }
            let faceVoice = CharacterVoiceTable.voice(for: CharacterRegistry.character(withID: character.faceID))
            let identical = faceVoice.allSatisfy { p, v in saved?[p] == v }
            XCTAssertFalse(identical,
                "\(character.displayName)'s saved parameters must not be identical to its face's built-in voice")
        }
    }
}
