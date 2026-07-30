import XCTest
import AVFoundation
@testable import MonkSynth

final class ParamsTests: XCTestCase {

    func testAddressOrderMatchesUpstream() {
        // Upstream cpp/src/plugin_cids.h declares the ParamID enum in this
        // exact order (kPortTime = 0 ... kPitchWheelRaw = 21, kNumParams =
        // 22); AU/ParameterAddresses.h mirrors it as the C ParameterAddress
        // enum. Pairing every named Swift case with its own named C constant
        // (rather than just checking Param.allCases[i].rawValue == i) is
        // deliberate: Swift's implicit rawValue increment would still
        // produce a structurally valid 0...21 sequence even if two case
        // *names* were accidentally transposed in the declaration, and Tasks
        // 5/6 index the shadow array by these values, so that kind of
        // mid-table swap would otherwise be silent and destructive.
        XCTAssertEqual(Param.allCases.count, Int(kParamCount.rawValue))

        let expected: [(Param, ParameterAddress)] = [
            (.portTime, kParamPortTime),
            (.vowel, kParamVowel),
            (.delay, kParamDelay),
            (.headSize, kParamHeadSize),
            (.vibrato, kParamVibrato),
            (.vibratoRate, kParamVibratoRate),
            (.aspiration, kParamAspiration),
            (.attack, kParamAttack),
            (.decay, kParamDecay),
            (.sustain, kParamSustain),
            (.release, kParamRelease),
            (.unison, kParamUnison),
            (.unisonDetune, kParamUnisonDetune),
            (.delayRate, kParamDelayRate),
            (.level, kParamLevel),
            (.unisonVoiceSpread, kParamUnisonVoiceSpread),
            (.xyNoteOn, kParamXYNoteOn),
            (.xyVowel, kParamXYVowel),
            (.xyPitchTarget, kParamXYPitchTarget),
            (.pitchBend, kParamPitchBend),
            (.pitchBendRouting, kParamPitchBendRouting),
            (.pitchWheelRaw, kParamPitchWheelRaw),
        ]
        XCTAssertEqual(expected.count, Param.allCases.count)

        for (i, entry) in expected.enumerated() {
            let (param, cAddress) = entry
            // Param.allCases[i] == param confirms Swift's declaration order
            // (and therefore Param.allCases[i].rawValue == UInt64(i)) lines
            // up with upstream's declared order at this position.
            XCTAssertEqual(Param.allCases[i], param,
                           "Param.allCases[\(i)] is \(Param.allCases[i].name), expected \(param.name)")
            XCTAssertEqual(param.rawValue, UInt64(cAddress.rawValue),
                           "\(param.name).rawValue does not match its upstream C address")
            // The `address` helper (used by Tasks 5/6 to key into the C
            // shadow array) must round-trip a Param's own rawValue exactly.
            XCTAssertEqual(param.address.rawValue, cAddress.rawValue,
                           "\(param.name).address does not match its upstream C address")
        }
    }

    func testDefaultsMatchUpstreamProcessorTable() {
        // Upstream cpp/src/processor.h paramValues_ initializer, in ID order.
        let expected: [AUValue] = [0.5, 0.5, 0.8, 0.5, 0.0, 0.5, 0.5, 0.0,
                                   0.0, 1.0, 0.0, 0.0, 0.0, 0.5, 1.0, 0.0,
                                   0.0, 0.5, 0.5, 0.5, 0.0, 0.5]
        for (i, p) in Param.allCases.enumerated() {
            XCTAssertEqual(p.defaultValue, expected[i], accuracy: 1e-6,
                           "default mismatch for \(p.name)")
        }
    }

    func testDisplayRoundTrips() {
        for p in Param.allCases {
            for v: AUValue in [0.0, 0.25, 0.5, 0.75, 1.0] {
                XCTAssertEqual(p.normalized(fromDisplay: p.display(v)), v,
                               accuracy: 1e-6, "round-trip failed for \(p.name)")
            }
        }
    }

    func testDisplayRangeMatchesUpstreamBounds() {
        // Round-tripping alone is near-tautological for any range: it only
        // proves display() and normalized(fromDisplay:) are inverses of each
        // other, not that the bounds themselves are the ones upstream ships.
        // These endpoints are transcribed from the literal RangeParameter
        // constructor arguments in upstream cpp/src/controller.cpp, not from
        // running AU/Params.swift and recording what it produced.

        // controller.cpp:566-568 — RangeParameter("PortTime", ..., "Hours", 0.0, 1000.0, 500.0, 0, ...)
        XCTAssertEqual(Param.portTime.display(0), 0, accuracy: 1e-6)
        XCTAssertEqual(Param.portTime.display(1), 1000, accuracy: 1e-6)
        XCTAssertEqual(Param.portTime.unit, "Hours")

        // controller.cpp:578-580 — RangeParameter("HeadSize", ..., "cm", 0.0, 30.0, 15.0, 0, ...)
        XCTAssertEqual(Param.headSize.display(0), 0, accuracy: 1e-6)
        XCTAssertEqual(Param.headSize.display(1), 30, accuracy: 1e-6)
        XCTAssertEqual(Param.headSize.unit, "cm")

        // controller.cpp:595-609 — Attack/Decay/Release: RangeParameter(..., "s", 0.0, 5.0, 0.0, 0, ...)
        for p in [Param.attack, .decay, .release] {
            XCTAssertEqual(p.display(0), 0, accuracy: 1e-6, "\(p.name)")
            XCTAssertEqual(p.display(1), 5, accuracy: 1e-6, "\(p.name)")
            XCTAssertEqual(p.unit, "s", "\(p.name)")
        }

        // controller.cpp:611-613 — RangeParameter("Unison", ..., "", 1.0, 10.0, 1.0, 9, ...)
        XCTAssertEqual(Param.unison.display(0), 1, accuracy: 1e-6)
        XCTAssertEqual(Param.unison.display(1), 10, accuracy: 1e-6)

        // controller.cpp:615-617 — RangeParameter("Detune", ..., "ct", 0.0, 50.0, 0.0, 0, ...)
        XCTAssertEqual(Param.unisonDetune.display(0), 0, accuracy: 1e-6)
        XCTAssertEqual(Param.unisonDetune.display(1), 50, accuracy: 1e-6)
        XCTAssertEqual(Param.unisonDetune.unit, "ct")

        // controller.cpp:639-641 — RangeParameter("Pitch Bend", ..., "st", -12.0, 12.0, 0.0, 0, ...)
        XCTAssertEqual(Param.pitchBend.display(0), -12, accuracy: 1e-6)
        XCTAssertEqual(Param.pitchBend.display(0.5), 0, accuracy: 1e-6)
        XCTAssertEqual(Param.pitchBend.display(1), 12, accuracy: 1e-6)
        XCTAssertEqual(Param.pitchBend.unit, "st")
    }

    func testUnisonFormatsAsIntegerVoiceCount() {
        // Matches upstream's (int)(v * 9 + 1.5) DSP mapping
        // (cpp/src/processor.cpp:58 / :165).
        XCTAssertEqual(Param.unison.formatted(0.0), "1")
        XCTAssertEqual(Param.unison.formatted(1.0), "10")
        XCTAssertEqual(Param.unison.formatted(0.55), "6")
    }

    func testUnisonFormattedClampsOutOfRangeInput() {
        // A host is entitled to hand us a value outside 0...1 (e.g. while
        // interpolating automation). Unclamped, formatted() would print "0"
        // or "11" voices — outside the upstream RangeParameter(1.0, 10.0,
        // ...) bounds and a nonsense display. Clamp so out-of-range input
        // still lands on a valid 1...10 voice count, consistent with
        // PitchBendMode(normalized:)'s existing clamp.
        XCTAssertEqual(Param.unison.formatted(-0.1), "1")
        XCTAssertEqual(Param.unison.formatted(1.1), "10")
    }

    func testFormattedCoversRemainingBranches() {
        // xyNoteOn: binary toggle, threshold at 0.5 (AU/Params.swift's own
        // `normalized > 0.5 ? "On" : "Off"` — strictly greater-than, so 0.5
        // itself still reads "Off").
        XCTAssertEqual(Param.xyNoteOn.formatted(0.0), "Off")
        XCTAssertEqual(Param.xyNoteOn.formatted(0.49), "Off")
        XCTAssertEqual(Param.xyNoteOn.formatted(0.5), "Off")
        XCTAssertEqual(Param.xyNoteOn.formatted(0.51), "On")
        XCTAssertEqual(Param.xyNoteOn.formatted(1.0), "On")

        // pitchBend: signed %+.2f of the display value, range -12...12
        // (controller.cpp:639-641). The 0-semitone midpoint (normalized 0.5)
        // must show a leading "+"; anything below center must show "-".
        XCTAssertEqual(Param.pitchBend.formatted(0.5), "+0.00")
        XCTAssertEqual(Param.pitchBend.formatted(0.0), "-12.00")
        XCTAssertTrue(Param.pitchBend.formatted(0.25).hasPrefix("-"))

        // attack: %.2f seconds of the display value, range 0...5
        // (controller.cpp:595-597). normalized 0.1 -> display 0.5s.
        XCTAssertEqual(Param.attack.formatted(0.1), "0.50")

        // portTime: %.0f of the display value, range 0...1000
        // (controller.cpp:566-568). normalized 0.5 -> display 500.
        XCTAssertEqual(Param.portTime.formatted(0.5), "500")
    }

    func testPitchBendModeMapping() {
        XCTAssertEqual(PitchBendMode(normalized: 0.0), .classic)
        XCTAssertEqual(PitchBendMode(normalized: 1.0), .pitch)
        XCTAssertEqual(PitchBendMode(normalized: 0.34), .both)
        XCTAssertEqual(PitchBendMode.bothInverted.normalized, 2.0 / 3.0,
                       accuracy: 1e-6)
    }
}
