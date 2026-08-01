import UIKit

/// A single rotary control bound to one `Param`. Vertical drag changes the
/// normalized value; a second finger down engages "fine" mode (1/8
/// sensitivity) for precise adjustment; double-tap restores the default.
final class KnobView: UIView {

    let param: Param
    var value: Float { didSet { setNeedsDisplay(); updateAccessibility() } }
    var onChange: ((Float) -> Void)?

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
    static let captionHeight: CGFloat = 24

    /// Diameter the dial will actually be drawn at, for the current bounds.
    /// Exposed so tests can confirm the captions never squeeze it away.
    var dialSide: CGFloat { min(bounds.width, bounds.height - Self.captionHeight) }
    private static let nameFontSize: CGFloat = 8
    private static let valueFontSize: CGFloat = 9

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // Reserve room for two caption lines (name + value) and keep the dial
        // a true circle — the smaller of the two axes, never stretched to fit.
        let side = min(rect.width, rect.height - Self.captionHeight)
        guard side > 4 else { return }
        let dial = CGRect(x: rect.midX - side / 2, y: rect.minY, width: side, height: side)

        Theme.panel.setFill(); UIBezierPath(ovalIn: dial).fill()
        Theme.panelBorder.setStroke()
        let ring = UIBezierPath(ovalIn: dial.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 1.5; ring.stroke()

        // Indicator sweeps 270°, from -225° to +45°.
        let angle = CGFloat(-225 + 270 * Double(value)) * .pi / 180
        let r = side / 2 - 4
        let c = CGPoint(x: dial.midX, y: dial.midY)
        ctx.setStrokeColor(Theme.accent.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: c.x + cos(angle) * r * 0.35,
                             y: c.y + sin(angle) * r * 0.35))
        ctx.addLine(to: CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r))
        ctx.strokePath()

        // Two caption lines: the parameter NAME (so you can tell the knobs
        // apart — the whole row was previously unlabelled) then its value.
        // The name is truncated to the cell width rather than overlapping its
        // neighbours, since "Voice Spread" is far wider than a small dial.
        func centred(_ s: String, _ font: UIFont, _ colour: UIColor, _ y: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            var a = attrs
            a[.paragraphStyle] = para
            (s as NSString).draw(in: CGRect(x: rect.minX, y: y,
                                            width: rect.width, height: font.lineHeight + 1),
                                 withAttributes: a)
        }

        let nameFont = Theme.label(Self.nameFontSize, weight: .semibold)
        let valueFont = Theme.label(Self.valueFontSize)
        centred(param.name.uppercased(), nameFont, Theme.textDim, dial.maxY + 2)
        centred(param.formatted(value), valueFont, Theme.textPrimary,
                dial.maxY + 2 + nameFont.lineHeight)
    }
}
