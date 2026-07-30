import XCTest
import AVFoundation
@testable import MonkSynth

final class ParamsTests: XCTestCase {

    func testAddressOrderMatchesUpstream() {
        XCTAssertEqual(Param.allCases.count, Int(kParamCount.rawValue))
        XCTAssertEqual(Param.portTime.rawValue, UInt64(kParamPortTime.rawValue))
        XCTAssertEqual(Param.pitchWheelRaw.rawValue, UInt64(kParamPitchWheelRaw.rawValue))
        XCTAssertEqual(Param.xyPitchTarget.rawValue, 18)
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

    func testUnisonFormatsAsIntegerVoiceCount() {
        // Matches upstream's (int)(v * 9 + 1.5) DSP mapping.
        XCTAssertEqual(Param.unison.formatted(0.0), "1")
        XCTAssertEqual(Param.unison.formatted(1.0), "10")
        XCTAssertEqual(Param.unison.formatted(0.55), "6")
    }

    func testPitchBendModeMapping() {
        XCTAssertEqual(PitchBendMode(normalized: 0.0), .classic)
        XCTAssertEqual(PitchBendMode(normalized: 1.0), .pitch)
        XCTAssertEqual(PitchBendMode(normalized: 0.34), .both)
        XCTAssertEqual(PitchBendMode.bothInverted.normalized, 2.0 / 3.0,
                       accuracy: 1e-6)
    }
}
