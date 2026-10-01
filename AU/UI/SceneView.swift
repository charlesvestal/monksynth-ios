import UIKit

/// The playable stage: the character's scene, the character standing in it,
/// and the XY pad stretched transparently over all of it — touch anywhere
/// in the scene and it sings (X pitch, Y vowel, exactly as the pad always
/// has). The character itself never takes touches.
final class SceneView: UIView {
    let backdrop = BackdropView()
    let stage: CharacterView
    let pad: XYPadView

    /// Below this the figure is too small to read; the scene stays playable.
    static let minCharacterSide: CGFloat = 72

    init(stage: CharacterView, pad: XYPadView) {
        self.stage = stage
        self.pad = pad
        super.init(frame: .zero)
        clipsToBounds = true
        layer.borderColor = Toon.ink.cgColor
        layer.borderWidth = 3
        addSubview(backdrop)
        addSubview(stage)
        addSubview(pad)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Bottom-centred square; the figure stands on the scene's bottom edge.
    static func characterRect(in bounds: CGRect) -> CGRect {
        let side = floor(min(bounds.height * 0.94, bounds.width * 0.8))
        guard side >= minCharacterSide else { return .zero }
        return CGRect(x: bounds.midX - side / 2, y: bounds.maxY - side, width: side, height: side)
    }

    var character: Character = MonkCharacter() {
        didSet { backdrop.character = character; pad.accent = character.palette.accent }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(18, bounds.height * 0.14)
        backdrop.frame = bounds
        pad.frame = bounds
        let r = Self.characterRect(in: bounds)
        backdrop.characterRect = r
        // Detach, don't hide: CharacterView's display link only stops once
        // its window goes nil (see CharacterView.updateDisplayLink).
        if r == .zero {
            if stage.superview != nil { stage.removeFromSuperview() }
        } else {
            if stage.superview == nil { insertSubview(stage, aboveSubview: backdrop) }
            stage.frame = r
        }
    }
}

/// Draws `character.drawBackdrop`. Redraws only when the character or the
/// size changes — never per animation frame.
final class BackdropView: UIView {
    var character: Character = MonkCharacter() { didSet { setNeedsDisplay() } }
    var characterRect: CGRect = .zero { didSet { if characterRect != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentMode = .redraw
        isOpaque = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ rect: CGRect) {
        // A hidden figure still sets the scene's scale: use the square it would have had.
        let side = min(bounds.height * 0.94, bounds.width * 0.8)
        let stage = characterRect == .zero
            ? CGRect(x: bounds.midX - side / 2, y: bounds.maxY - side, width: side, height: side)
            : characterRect
        character.drawBackdrop(in: bounds, stage: stage)
    }
}
