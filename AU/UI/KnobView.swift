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

    static let fullTravel: CGFloat = 180
    static let fineFactor: CGFloat = 0.125

    init(param: Param, value: Float) {
        self.param = param
        self.value = value
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

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

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let side = min(rect.width, rect.height - 16)
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

        let text = param.formatted(value) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.label(9), .foregroundColor: Theme.textDim]
        text.draw(at: CGPoint(x: rect.midX - text.size(withAttributes: attrs).width / 2,
                              y: dial.maxY + 3), withAttributes: attrs)
    }
}
