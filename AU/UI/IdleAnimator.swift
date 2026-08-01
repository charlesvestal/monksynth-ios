import Foundation

/// Upstream's idle state machine (cpp/src/monk_view.h), retargeted from
/// sprite-frame indices onto the vector rig: it emits a vowel position and an
/// eyes-closed flag rather than a frame number.
struct IdleAnimator {

    enum Phase: Equatable { case hold, shuffle }

    private(set) var phase: Phase = .hold
    private(set) var tick = 0
    private(set) var shufflePos = 0

    static let tickMs = 100
    static let holdTicks = 48
    static let blink1 = 14..<17
    static let blink2 = 31..<34
    static let shuffleTicksPerStep = 2

    /// Upstream kShuffleSeq, as frame indices 0…5.
    static let shuffleSequence: [Int] = [
        5, 3, 4, 3, 2, 1, 0, 1,
        5, 3, 4, 3, 5, 1, 0, 1,
        2, 3, 4, 3, 5, 1, 0, 1,
    ]

    static func vowel(forFrame f: Int) -> Float { Float(f) / 5.0 }

    /// Current pose: vowel position and whether the eyes are shut.
    var pose: (vowel: Float, blinking: Bool) {
        switch phase {
        case .hold:
            let blinking = Self.blink1.contains(tick) || Self.blink2.contains(tick)
            return (Self.vowel(forFrame: 5), blinking)
        case .shuffle:
            let f = Self.shuffleSequence[shufflePos % Self.shuffleSequence.count]
            return (Self.vowel(forFrame: f), false)
        }
    }

    mutating func advance() {
        tick += 1
        switch phase {
        case .hold:
            if tick >= Self.holdTicks {
                phase = .shuffle
                tick = 0
                shufflePos = 0
            }
        case .shuffle:
            if tick >= Self.shuffleTicksPerStep {
                tick = 0
                shufflePos += 1
                if shufflePos >= Self.shuffleSequence.count {
                    phase = .hold
                    shufflePos = 0
                }
            }
        }
    }

    mutating func reset() { phase = .hold; tick = 0; shufflePos = 0 }
}
