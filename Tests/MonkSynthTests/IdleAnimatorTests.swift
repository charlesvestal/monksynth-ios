import XCTest
import UIKit
@testable import MonkSynth

/// Covers `IdleAnimator` (upstream's idle state machine from
/// cpp/src/monk_view.h, retargeted onto the vector rig) and the continuity
/// of `MonkCharacter.mouthShape(vowel:)`, the piece that replaces upstream's
/// 24 discrete sprite frames with a smooth interpolation. `IdleAnimator` and
/// the quantisation (`CharacterView.quantisedVowel`/`vowelFrameCount`) are
/// shared by every character; only `mouthShape` itself is per-character —
/// see `CharacterTests` for the other four.
final class IdleAnimatorTests: XCTestCase {

    // MARK: - HOLD duration

    /// HOLD occupies exactly 48 ticks (tick values 0...47) before the phase
    /// flips to SHUFFLE, matching upstream's `kHoldTicks = 48`.
    func testHoldLasts48TicksBeforeSwitchingToShuffle() {
        var idle = IdleAnimator()
        XCTAssertEqual(idle.phase, .hold)

        for i in 0..<47 {
            idle.advance()
            XCTAssertEqual(idle.phase, .hold, "still HOLD after tick \(i + 1)")
        }
        idle.advance() // the 48th tick
        XCTAssertEqual(idle.phase, .shuffle, "should flip to SHUFFLE after 48 ticks")
    }

    // MARK: - Blink timing

    /// Blinks land on exactly ticks 14,15,16 and 31,32,33 within HOLD,
    /// matching upstream's kBlink1Start=14/kBlink1End=17 and
    /// kBlink2Start=31/kBlink2End=34 (half-open ranges: tick >= start && tick < end).
    func testBlinksAtExactTicksWithinHold() {
        var idle = IdleAnimator()
        var blinkingTicks: [Int] = []

        // Sample every HOLD tick state (0...47) before it rolls into SHUFFLE.
        for t in 0..<IdleAnimator.holdTicks {
            XCTAssertEqual(idle.tick, t)
            if idle.pose.blinking { blinkingTicks.append(t) }
            idle.advance()
        }

        XCTAssertEqual(blinkingTicks, [14, 15, 16, 31, 32, 33])
    }

    // MARK: - SHUFFLE timing

    /// Each of the 24 shuffle steps holds for exactly 2 ticks (upstream's
    /// kShuffleTicksPerStep), and the sequence wraps back to HOLD once all
    /// 24 steps have played.
    func testShuffleHoldsEachStepForTwoTicksAndWrapsToHold() {
        var idle = IdleAnimator()
        for _ in 0..<IdleAnimator.holdTicks { idle.advance() }
        XCTAssertEqual(idle.phase, .shuffle)
        XCTAssertEqual(idle.shufflePos, 0)

        for step in 0..<IdleAnimator.shuffleSequence.count {
            XCTAssertEqual(idle.phase, .shuffle, "still SHUFFLE at step \(step)")
            XCTAssertEqual(idle.shufflePos, step)
            let vowelAtStepStart = idle.pose.vowel

            idle.advance() // first of the two ticks for this step
            XCTAssertEqual(idle.shufflePos, step, "step \(step) should hold for a 2nd tick")
            XCTAssertEqual(idle.pose.vowel, vowelAtStepStart, accuracy: 1e-9,
                            "vowel must not change mid-step")

            idle.advance() // second tick: advances to the next step (or wraps)
        }

        XCTAssertEqual(idle.phase, .hold, "should wrap back to HOLD after all 24 steps")
        XCTAssertEqual(idle.shufflePos, 0)
    }

    // MARK: - Mouth continuity

    /// `mouthShape(vowel:)` is what replaces upstream's 24 discrete sprite
    /// frames — it must interpolate smoothly with no snap between anchors.
    /// The endpoints come from `ToonMouth.anchors` (OO and EE) scaled by the
    /// monk's `mouthStyle.scale` (0.8) and expressed as a stage fraction
    /// (`/ Toon.stageUnits`, 300).
    func testMouthShapeIsContinuousAcrossVowelRange() {
        let monk = MonkCharacter()
        let steps = 100
        let epsilon: CGFloat = 0.01 // real per-step delta is ~0.0032 at worst

        var previous = monk.mouthShape(vowel: 0)
        for i in 1...steps {
            let v = Float(i) / Float(steps)
            let current = monk.mouthShape(vowel: v)
            XCTAssertLessThanOrEqual(abs(current.w - previous.w), epsilon,
                                      "width jump at vowel \(v)")
            XCTAssertLessThanOrEqual(abs(current.h - previous.h), epsilon,
                                      "height jump at vowel \(v)")
            previous = current
        }

        let first = monk.mouthShape(vowel: 0)
        let last = monk.mouthShape(vowel: 1)
        XCTAssertEqual(first.w, 24 * 0.8 / 300, accuracy: 1e-9)
        XCTAssertEqual(first.h, 26 * 0.8 / 300, accuracy: 1e-9)
        XCTAssertEqual(last.w, 74 * 0.8 / 300, accuracy: 1e-9)
        XCTAssertEqual(last.h, 18 * 0.8 / 300, accuracy: 1e-9)
    }

    /// The user preferred the original's stepped, sprite-sheet motion to the
    /// smooth interpolation an earlier version of this port used: "the distinct
    /// frames of animation are more evocative than the smooth animations". The
    /// vowel input is therefore quantised to the same frame count upstream's
    /// sprite sheet used, while `mouthShape` itself stays continuous.
    func testVowelIsQuantisedIntoDiscreteFrames() {
        var distinct = Set<Float>()
        for i in 0...1000 {
            distinct.insert(CharacterView.quantisedVowel(Float(i) / 1000.0))
        }
        XCTAssertEqual(distinct.count, CharacterView.vowelFrameCount,
                       "vowel should land on exactly \(CharacterView.vowelFrameCount) positions")
        XCTAssertEqual(CharacterView.quantisedVowel(0), 0, accuracy: 1e-6)
        XCTAssertEqual(CharacterView.quantisedVowel(1), 1, accuracy: 1e-6)
    }

    /// Stepping must be visible: adjacent frames should differ by a real
    /// amount, otherwise quantising achieves nothing perceptually.
    func testAdjacentFramesProduceVisiblyDifferentMouthShapes() {
        let monk = MonkCharacter()
        let steps = Float(CharacterView.vowelFrameCount - 1)
        var maxDelta: CGFloat = 0
        for i in 0..<Int(steps) {
            let a = monk.mouthShape(vowel: CharacterView.quantisedVowel(Float(i) / steps))
            let b = monk.mouthShape(vowel: CharacterView.quantisedVowel(Float(i + 1) / steps))
            maxDelta = max(maxDelta, max(abs(a.w - b.w), abs(a.h - b.h)))
        }
        XCTAssertGreaterThan(maxDelta, 0.004,
                             "frames must be distinguishable, not a disguised glide")
    }
}
