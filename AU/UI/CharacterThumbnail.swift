import UIKit

/// A small picture of a character singing AH in its own scene, for lists
/// (currently just `CharacterDropdownView`'s rows). Generated on demand —
/// cheap enough (a dozen-ish rows at a time) that no cache is needed.
enum CharacterThumbnail {
    static func image(for character: Character, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            // Crop to head and shoulders: a character's own geometry lives
            // in a 300-unit stage (see `Toon.inStage`). Show a 280-unit
            // window of it, with 20 units of headroom above the head, so
            // every row reads as "face plus a little scene" rather than a
            // chin-to-forehead close-up.
            let figure = side * (300.0 / 280.0)
            let stage = CGRect(x: (side - figure) / 2, y: figure * (20.0 / 300.0), width: figure, height: figure)
            character.drawBackdrop(in: rect, stage: stage)
            character.drawBody(in: stage)
            character.drawFace(in: stage, expression: .rest)
            character.drawMouth(in: stage, vowel: 0.5, amplitudeBoost: 1)
            character.drawOverMouth(in: stage)
        }
    }
}
