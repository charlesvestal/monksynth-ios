import UIKit

/// A character drawn with the `Toon` kit in 300-unit stage space, singing
/// with the shared `ToonMouth`. Conformers implement only the `drawToon…`
/// methods and `mouthStyle`; every `Character` requirement that involves a
/// stage rect is supplied here by mapping into stage units.
///
/// Implement `drawToonFace` (never `drawEyes`): the default `drawEyes`
/// below routes through it.
protocol ToonCharacter: Character {
    var mouthStyle: ToonMouth.Style { get }
    func drawToonBody()
    func drawToonFace(_ e: Expression)
    func drawToonOverMouth()
}

extension ToonCharacter {
    func drawToonOverMouth() {}

    func drawBody(in stage: CGRect) { Toon.inStage(stage) { _ in drawToonBody() } }

    func drawFace(in stage: CGRect, expression: Expression) {
        Toon.inStage(stage) { _ in drawToonFace(expression) }
    }

    func drawEyes(in stage: CGRect, blinking: Bool) {
        var e = Expression.rest
        e.blinking = blinking
        drawFace(in: stage, expression: e)
    }

    func drawOverMouth(in stage: CGRect) { Toon.inStage(stage) { _ in drawToonOverMouth() } }

    /// Stage fractions, already scaled by `mouthStyle.scale` — so
    /// `mouthBoxFraction` is 1.
    func mouthShape(vowel: Float) -> (w: CGFloat, h: CGFloat) {
        let p = ToonMouth.params(vowel: vowel)
        return (p.w * mouthStyle.scale / Toon.stageUnits, p.h * mouthStyle.scale / Toon.stageUnits)
    }

    var mouthCentre: (fx: CGFloat, fy: CGFloat) {
        (mouthStyle.x / Toon.stageUnits, mouthStyle.y / Toon.stageUnits)
    }

    var mouthBoxFraction: CGFloat { 1 }

    func drawMouth(in stage: CGRect, vowel: Float, amplitudeBoost: CGFloat) {
        Toon.inStage(stage) { _ in ToonMouth.draw(mouthStyle, vowel: vowel, boost: amplitudeBoost) }
    }
}
