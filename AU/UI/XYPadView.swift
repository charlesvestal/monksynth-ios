import UIKit

/// The primary performance surface: X sets pitch, Y sets vowel. Dragging
/// writes the upstream xyPitchTarget/xyVowel/xyNoteOn parameters (indices
/// 18/17/16) rather than calling the audio engine directly, so a host
/// recording automation captures the whole performance and can replay it.
final class XYPadView: UIView {

    /// Set by the view controller: writes a normalized value to a parameter.
    var onParameterChange: ((Param, Float) -> Void)?

    private(set) var pitch: Float = 0.5
    private(set) var vowel: Float = 0.5
    private(set) var isPlaying = false
    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // See KnobView: without .redraw, a host resizing the AUv3 view scales
        // the stale drawing instead of re-running draw(_:), skewing the
        // crosshair and the position dot.
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("pad.label", comment: "XY pad")
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Converts a point to normalized (pitch, vowel). Y is inverted so the
    /// top of the pad is vowel 1.0. Pure and static so it is testable
    /// without a view or a touch.
    static func normalize(_ point: CGPoint, in size: CGSize) -> (pitch: Float, vowel: Float) {
        guard size.width > 0, size.height > 0 else { return (0.5, 0.5) }
        let x = min(max(point.x / size.width, 0), 1)
        let y = min(max(point.y / size.height, 0), 1)
        return (Float(x), Float(1.0 - y))
    }

    /// Touch-down core. Factored out of `touchesBegan` so the write ORDER is
    /// unit-testable: `UITouch` has no public initializer, so a test cannot
    /// synthesize one to drive `touchesBegan` directly, and that inability is
    /// itself a sign this logic belongs in a plain method rather than only
    /// inside the UIResponder override.
    ///
    /// Order matters: pitch and vowel MUST be written before note-on. The
    /// render block reads `xyPendingPitch` on the rising edge of `xyNoteOn`;
    /// if note-on arrives first, the note starts at the previous pitch — an
    /// audible glitch on every touch-down.
    ///
    /// `isPlaying` gates the note-on write (not the pitch/vowel writes) so a
    /// second finger touching down while the first is still held retargets
    /// the pad — last-touch-wins — instead of re-triggering a second note.
    func beginTouch(at point: CGPoint, in size: CGSize) {
        let (p, v) = Self.normalize(point, in: size)
        pitch = p; vowel = v
        onParameterChange?(.xyPitchTarget, p)
        onParameterChange?(.xyVowel, v)
        if !isPlaying {
            isPlaying = true
            onParameterChange?(.xyNoteOn, 1.0)
        }
        setNeedsDisplay()
    }

    func moveTouch(at point: CGPoint, in size: CGSize) {
        let (p, v) = Self.normalize(point, in: size)
        pitch = p; vowel = v
        onParameterChange?(.xyPitchTarget, p)
        onParameterChange?(.xyVowel, v)
        setNeedsDisplay()
    }

    func endTouch() {
        isPlaying = false
        onParameterChange?(.xyNoteOn, 0.0)
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        activeTouch = touch                      // last touch wins
        beginTouch(at: touch.location(in: self), in: bounds.size)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        moveTouch(at: touch.location(in: self), in: bounds.size)
    }

    private func end(_ touches: Set<UITouch>) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        endTouch()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        Theme.panelBorder.setStroke()
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.midY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        ctx.move(to: CGPoint(x: rect.midX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        ctx.strokePath()

        let cx = rect.minX + CGFloat(pitch) * rect.width
        let cy = rect.minY + CGFloat(1 - vowel) * rect.height
        let r: CGFloat = isPlaying ? 22 : 14
        let dot = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        Theme.accent.withAlphaComponent(isPlaying ? 0.35 : 0.18).setFill()
        ctx.fillEllipse(in: dot)
        Theme.accent.setStroke()
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: dot)
    }
}
