import UIKit

/// A single rotary control bound to one `Param`. Vertical drag changes the
/// normalized value; a second finger down engages "fine" mode (1/8
/// sensitivity) for precise adjustment; double-tap restores the default.
final class KnobView: UIView {

    let param: Param
    var value: Float { didSet { setNeedsDisplay(); updateAccessibility() } }
    var onChange: ((Float) -> Void)?
    /// The value arc's colour — the owning view's character accent.
    var accent: UIColor = Theme.defaultAccent { didSet { setNeedsDisplay() } }

    private var dragStart: CGPoint = .zero
    private var valueAtDragStart: Float = 0
    private var fine = false

    /// The touch driving the drag. Tracked explicitly (mirroring
    /// `XYPadView.activeTouch`) rather than reading `touches.first` on every
    /// callback: `touchesBegan`/`touchesMoved`/`touchesEnded` are each
    /// delivered only the touches that changed in that event, so a naive
    /// `touches.first` in `touchesBegan` would rebind `dragStart` to the
    /// SECOND finger's location the moment it touches down — producing a
    /// jump equal to the on-screen distance between the two fingers the
    /// instant fine mode engages. Rebasing from the primary touch's current
    /// location (not the new touch's location) keeps the transition smooth.
    private var primaryTouch: UITouch?

    /// Finger travel for the full 0…1 sweep. Deliberately shorter than a
    /// knob-diameter-proportional value: in an AUv3 strip the control row is
    /// ~92pt tall, so a long throw means running out of glass before running
    /// out of range. Fine mode covers the precision this trades away.
    static let fullTravel: CGFloat = 110
    static let fineFactor: CGFloat = 0.125

    init(param: Param, value: Float) {
        self.param = param
        self.value = value
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        // Without this, UIKit scales the previously drawn layer on a bounds
        // change instead of calling draw(_:) — an AUv3 host resizing its view
        // would stretch these circles into ellipses.
        contentMode = .redraw

        let double = UITapGestureRecognizer(target: self, action: #selector(resetToDefault))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)

        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateAccessibility() {
        accessibilityLabel = param.name
        accessibilityValue = param.formatted(value)
    }

    override func accessibilityIncrement() { commit(min(1, value + 0.05)) }
    override func accessibilityDecrement() { commit(max(0, value - 0.05)) }

    @objc private func resetToDefault() { commit(param.defaultValue) }

    private func commit(_ v: Float) {
        value = min(max(v, 0), 1)
        onChange?(value)
    }

    /// Pure value math so it is testable without touch plumbing.
    static func value(from start: Float, dragDelta: CGFloat, fine: Bool) -> Float {
        let travel = fine ? fullTravel / fineFactor : fullTravel
        let delta = Float(-dragDelta / travel)
        return min(max(start + delta, 0), 1)
    }

    private func rebase(from touch: UITouch) {
        dragStart = touch.location(in: self)
        valueAtDragStart = value
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let count = event?.allTouches?.count ?? touches.count
        if primaryTouch == nil {
            guard let t = touches.first else { return }
            primaryTouch = t
            rebase(from: t)
        } else if let p = primaryTouch {
            // A further finger touching down changes sensitivity. Rebase
            // from the PRIMARY touch's current location (not the new
            // touch's) so engaging fine mode doesn't jump the value.
            rebase(from: p)
        }
        fine = count > 1
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = primaryTouch, touches.contains(p) else { return }
        fine = (event?.allTouches?.count ?? 1) > 1
        let dy = p.location(in: self).y - dragStart.y
        commit(Self.value(from: valueAtDragStart, dragDelta: dy, fine: fine))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { releaseIfPrimary(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { releaseIfPrimary(touches) }

    private func releaseIfPrimary(_ touches: Set<UITouch>) {
        guard let p = primaryTouch, touches.contains(p) else { return }
        primaryTouch = nil
    }

    /// Height reserved beneath the dial for the name and value lines.
    static let captionHeight: CGFloat = 26

    /// Diameter the dial will actually be drawn at, for the current bounds.
    /// Exposed so tests can confirm the captions never squeeze it away.
    var dialSide: CGFloat { min(bounds.width, bounds.height - Self.captionHeight) }
    private static let nameFontSize: CGFloat = 8
    private static let valueFontSize: CGFloat = 11

    /// A sticker dial: a ring (dark track, `accent` value arc) with an
    /// ink rim and a hard ink shadow straight down, around a cream face with
    /// an ink outline and an ink pointer bar.
    override func draw(_ rect: CGRect) {
        // Reserve room for two caption lines (name + value) and keep the dial
        // a true circle — the smaller of the two axes, never stretched to fit.
        let side = min(rect.width, rect.height - Self.captionHeight)
        guard side > 4 else { return }
        let border: CGFloat = side >= 30 ? Theme.outline : 2
        let s = side - border                       // leave room for the drop shadow
        let c = CGPoint(x: rect.midX, y: rect.minY + s / 2)
        let outerR = s / 2
        let ringW = max(3, s * 0.15)
        // Sweeps 270° clockwise from the 7:30 position.
        let start = CGFloat(135) * .pi / 180
        let angle = start + CGFloat(270 * Double(value)) * .pi / 180

        Toon.fill(Toon.circle(c.x, c.y + border, outerR), Theme.ink)
        Toon.fill(Toon.circle(c.x, c.y, outerR), Theme.track)
        if value > 0.001 {
            let lit = UIBezierPath(arcCenter: c, radius: outerR - border - ringW / 2,
                                   startAngle: start, endAngle: angle, clockwise: true)
            lit.lineWidth = ringW + 1
            lit.lineCapStyle = .butt
            accent.setStroke()
            lit.stroke()
        }
        Toon.stroke(Toon.circle(c.x, c.y, outerR - border / 2), width: border)

        let faceR = outerR - border - ringW - border / 2
        Toon.shape(Toon.circle(c.x, c.y, faceR), fill: Theme.cream, lineWidth: border, shaded: false)
        let pointer = UIBezierPath()
        pointer.move(to: CGPoint(x: c.x + cos(angle) * faceR * 0.12, y: c.y + sin(angle) * faceR * 0.12))
        pointer.addLine(to: CGPoint(x: c.x + cos(angle) * faceR * 0.72, y: c.y + sin(angle) * faceR * 0.72))
        Toon.stroke(pointer, width: max(2.5, s * 0.075))

        // Two caption lines: the parameter NAME (so you can tell the knobs
        // apart — the whole row was previously unlabelled) then its value.
        // The name is truncated to the cell width rather than overlapping its
        // neighbours, since "Voice Spread" is far wider than a small dial.
        func centred(_ s: String, _ font: UIFont, _ colour: UIColor, _ y: CGFloat, kern: CGFloat = 0) {
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour,
                                                        .paragraphStyle: para, .kern: kern]
            (s as NSString).draw(in: CGRect(x: rect.minX, y: y,
                                            width: rect.width, height: font.lineHeight + 1),
                                 withAttributes: attrs)
        }

        let nameFont = Theme.label(Self.nameFontSize, weight: .heavy)
        let valueFont = Theme.display(Self.valueFontSize)
        let captionTop = rect.minY + side + 2
        centred(param.name.uppercased(), nameFont, Theme.textDim, captionTop, kern: 0.6)
        centred(param.formatted(value), valueFont, Theme.textPrimary, captionTop + nameFont.lineHeight)
    }
}
