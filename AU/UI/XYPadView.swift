import UIKit

/// The primary performance surface: X sets pitch, Y sets vowel. Lives
/// inside `SceneView`, stretched transparently over the character's scene. Dragging
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
        isOpaque = false
        backgroundColor = .clear
        // See KnobView: without .redraw, a host resizing the AUv3 view scales
        // the stale drawing instead of re-running draw(_:), skewing the
        // ticks, vowel scale and touch marker.
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
            if showsHint {
                showsHint = false
                UserDefaults.standard.set(true, forKey: Self.hintDismissedKey)
            }
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

    /// The touch marker's dot colour — the current character's accent, set
    /// by `SceneView` on character change.
    var accent: UIColor = Theme.accent { didSet { setNeedsDisplay() } }

    /// UserDefaults key: set once the scene has been touched; until then a
    /// small "touch to sing" hint shows (the scene no longer looks like a pad).
    static let hintDismissedKey = "scene.hintDismissed"
    private var showsHint = !UserDefaults.standard.bool(forKey: XYPadView.hintDismissedKey)

    /// Transparent overlay over the scene: pitch ticks along the bottom, a
    /// vowel scale up the right edge, the first-touch hint, and — while
    /// touching — ripple rings around an accent dot. No box, no crosshair.
    override func draw(_ rect: CGRect) {
        let rect = bounds
        guard rect.width > 0, rect.height > 0 else { return }
        let ink = Toon.ink
        // Pitch ticks along the bottom: 25 marks, octaves tallest.
        for i in 0...24 {
            let x = 12 + (rect.width - 24) * CGFloat(i) / 24
            let h: CGFloat = i % 12 == 0 ? 16 : (i % 2 == 1 ? 7 : 11)
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: rect.maxY - 4)); p.addLine(to: CGPoint(x: x, y: rect.maxY - h))
            Toon.stroke(p, width: 2, color: UIColor.white.withAlphaComponent(0.75))
        }
        // Vowel scale up the right edge, OO at the bottom.
        if rect.height >= 90 {
            let font = Theme.display(11)
            for (i, v) in ["OO", "OH", "AH", "EH", "EE"].enumerated() {
                let y = 14 + (rect.height - 50) * (1 - CGFloat(i) / 4)
                let s = NSAttributedString(string: v, attributes: [
                    .font: font, .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                    .strokeColor: ink, .strokeWidth: -3])
                let size = s.size()
                s.draw(at: CGPoint(x: rect.maxX - 8 - size.width, y: y))
            }
        }
        if showsHint && !isPlaying && rect.height >= 90 {
            let s = NSAttributedString(string: NSLocalizedString("pad.hint", comment: "first-touch hint"),
                                       attributes: [.font: Theme.display(15), .foregroundColor: UIColor.white,
                                                    .strokeColor: ink, .strokeWidth: -4])
            let size = s.size()
            s.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.minY + 12))
        }
        guard isPlaying else { return }
        let c = CGPoint(x: rect.minX + CGFloat(pitch) * rect.width, y: rect.minY + CGFloat(1 - vowel) * rect.height)
        Toon.stroke(Toon.circle(c.x, c.y, 30), width: 3, color: UIColor.white.withAlphaComponent(0.45))
        Toon.stroke(Toon.circle(c.x, c.y, 20), width: 3, color: UIColor.white.withAlphaComponent(0.8))
        Toon.shape(Toon.circle(c.x, c.y, 10), fill: accent, lineWidth: 4, shaded: false)
    }
}
