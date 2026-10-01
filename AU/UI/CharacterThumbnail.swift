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
            // Crop to head and shoulders: draw the figure larger than the
            // tile and shift it down so the head lands near the tile's
            // centre instead of the full body being squeezed in.
            let figure = side * 1.5
            let stage = CGRect(x: (side - figure) / 2, y: side - figure * 0.88, width: figure, height: figure)
            character.drawBackdrop(in: rect, stage: stage)
            character.drawBody(in: stage)
            character.drawFace(in: stage, expression: .rest)
            character.drawMouth(in: stage, vowel: 0.5, amplitudeBoost: 1)
            character.drawOverMouth(in: stage)
        }
    }
}
