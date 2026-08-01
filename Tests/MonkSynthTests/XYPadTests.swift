import XCTest
import UIKit
@testable import MonkSynth

final class XYPadTests: XCTestCase {

    // MARK: - XYPadView.normalize

    func testYIsInvertedTopOfPadIsVowelOne() {
        let size = CGSize(width: 200, height: 100)
        let top = XYPadView.normalize(CGPoint(x: 0, y: 0), in: size)
        let bottom = XYPadView.normalize(CGPoint(x: 0, y: 100), in: size)
        XCTAssertEqual(top.vowel, 1.0, accuracy: 1e-6)
        XCTAssertEqual(bottom.vowel, 0.0, accuracy: 1e-6)
    }

    func testPitchTracksXAcrossWidth() {
        let size = CGSize(width: 200, height: 100)
        let mid = XYPadView.normalize(CGPoint(x: 100, y: 50), in: size)
        let right = XYPadView.normalize(CGPoint(x: 200, y: 50), in: size)
        let left = XYPadView.normalize(CGPoint(x: 0, y: 50), in: size)
        XCTAssertEqual(mid.pitch, 0.5, accuracy: 1e-6)
        XCTAssertEqual(right.pitch, 1.0, accuracy: 1e-6)
        XCTAssertEqual(left.pitch, 0.0, accuracy: 1e-6)
    }

    func testValuesClampOutsideBounds() {
        let size = CGSize(width: 200, height: 100)
        let beyondBottomRight = XYPadView.normalize(CGPoint(x: 400, y: 300), in: size)
        XCTAssertEqual(beyondBottomRight.pitch, 1.0, accuracy: 1e-6)
        XCTAssertEqual(beyondBottomRight.vowel, 0.0, accuracy: 1e-6)

        let beyondTopLeft = XYPadView.normalize(CGPoint(x: -50, y: -50), in: size)
        XCTAssertEqual(beyondTopLeft.pitch, 0.0, accuracy: 1e-6)
        XCTAssertEqual(beyondTopLeft.vowel, 1.0, accuracy: 1e-6)
    }

    func testDegenerateZeroSizeReturnsMidpointInsteadOfDividingByZero() {
        let result = XYPadView.normalize(CGPoint(x: 10, y: 10), in: .zero)
        XCTAssertEqual(result.pitch, 0.5, accuracy: 1e-6)
        XCTAssertEqual(result.vowel, 0.5, accuracy: 1e-6)
    }

    // MARK: - Touch-down write order

    /// The real bug this guards: the render block reads `xyPendingPitch` on
    /// the rising edge of `xyNoteOn`. If note-on were written before pitch
    /// and vowel, every touch-down would start the note at the *previous*
    /// pitch — an audible glitch.
    ///
    /// `UITouch` has no public initializer, so `touchesBegan` cannot be
    /// driven directly from a unit test. `XYPadView.beginTouch(at:in:)` is
    /// the pure, testable extraction of that override's body — this test
    /// drives it directly rather than trying (and failing) to synthesize a
    /// `UITouch`.
    func testTouchDownWritesPitchAndVowelBeforeNoteOn() {
        let pad = XYPadView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        var written: [(Param, Float)] = []
        pad.onParameterChange = { written.append(($0, $1)) }

        pad.beginTouch(at: CGPoint(x: 150, y: 25), in: pad.bounds.size)

        let params = written.map { $0.0 }
        guard let pitchIndex = params.firstIndex(of: .xyPitchTarget),
              let vowelIndex = params.firstIndex(of: .xyVowel),
              let noteOnIndex = params.firstIndex(of: .xyNoteOn) else {
            return XCTFail("expected xyPitchTarget, xyVowel, and xyNoteOn to all be written, got \(params)")
        }

        XCTAssertLessThan(pitchIndex, noteOnIndex,
                           "xyPitchTarget must be written before xyNoteOn")
        XCTAssertLessThan(vowelIndex, noteOnIndex,
                           "xyVowel must be written before xyNoteOn")

        // And the values themselves: x=150/200=0.75 pitch, y=25/100=0.25 ->
        // vowel 0.75 (inverted), note-on 1.0.
        XCTAssertEqual(written[pitchIndex].1, 0.75, accuracy: 1e-6)
        XCTAssertEqual(written[vowelIndex].1, 0.75, accuracy: 1e-6)
        XCTAssertEqual(written[noteOnIndex].1, 1.0, accuracy: 1e-6)
    }
}
