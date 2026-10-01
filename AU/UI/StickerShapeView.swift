import UIKit

/// A round or capsule sticker face — flat fill, ink outline, and optionally
/// the hard ink drop shadow — drawn as one `CAShapeLayer` path.
///
/// Not `layer.cornerRadius` + `borderWidth`: Core Animation antialiases the
/// rounded background and the rounded border as separate edges, so the fill
/// bleeds a jagged fringe outside the ring; and a shadow with no
/// `shadowPath` is traced from the rendered alpha, rough edge and all. Here
/// the stroke sits inside the bounds (the path is inset by half the line
/// width) and the shadow is the exact outer capsule.
///
/// The view is its own shape layer (`layerClass`), so it can stand in for
/// a plain `UIView` disc behind a button's glyph with no change to frames,
/// hit areas or subview order. Its path follows its bounds in
/// `layoutSubviews`.
final class StickerShapeView: UIView {

    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shape: CAShapeLayer { layer as! CAShapeLayer }

    var fillColor: UIColor { didSet { shape.fillColor = fillColor.cgColor } }

    /// - Parameters:
    ///   - fill: the face colour.
    ///   - dropShadow: adds the hard ink shadow 3pt below (the sticker
    ///     buttons' "lifted" look).
    init(fill: UIColor, dropShadow: Bool = false) {
        fillColor = fill
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        shape.fillColor = fill.cgColor
        shape.strokeColor = Theme.ink.cgColor
        shape.lineWidth = Theme.outline
        if dropShadow {
            shape.shadowColor = Theme.ink.cgColor
            shape.shadowOffset = CGSize(width: 0, height: 3)
            shape.shadowOpacity = 1
            shape.shadowRadius = 0
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The outline's centre line: the bounds' capsule inset by half the
    /// stroke, so the whole ring lies inside the bounds.
    static func outlinePath(in bounds: CGRect) -> UIBezierPath {
        let r = bounds.insetBy(dx: Theme.outline / 2, dy: Theme.outline / 2)
        guard r.width > 0, r.height > 0 else { return UIBezierPath() }
        return UIBezierPath(roundedRect: r, cornerRadius: min(r.width, r.height) / 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.path = Self.outlinePath(in: bounds).cgPath
        if shape.shadowOpacity > 0 {
            shape.shadowPath = UIBezierPath(roundedRect: bounds,
                                            cornerRadius: min(bounds.width, bounds.height) / 2).cgPath
        }
    }
}
