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
    private var touches = TouchStack<ObjectIdentifier>()

    /// The touch marker — two white ripple rings around an accent dot with
    /// an ink edge — on its own small layer. Touch begin/move only moves
    /// this layer: the pad covers the whole scene, so repainting it at touch
    /// rate would redraw a full-scene bitmap for a 64pt mark. Hidden while
    /// no note is playing.
    let touchMarker = CALayer()
    private let markerDot = CAShapeLayer()
    /// Outer ring radius 30 + half its 3pt stroke, rounded up.
    private static let markerSize: CGFloat = 64

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        // See KnobView: without .redraw, a host resizing the AUv3 view scales
        // the stale drawing instead of re-running draw(_:), skewing the
        // ticks and vowel scale.
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("pad.label", comment: "XY pad")
        accessibilityTraits = .allowsDirectInteraction
        installTouchMarker()
    }

    private func installTouchMarker() {
        let size = Self.markerSize
        touchMarker.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        touchMarker.isHidden = true
        let c = size / 2
        let rings: [(radius: CGFloat, alpha: CGFloat)] = [(30, 0.45), (20, 0.8)]
        for ring in rings {
            let l = CAShapeLayer()
            l.path = Toon.circle(c, c, ring.radius).cgPath
            l.fillColor = nil
            l.strokeColor = UIColor.white.withAlphaComponent(ring.alpha).cgColor
            l.lineWidth = 3
            touchMarker.addSublayer(l)
        }
        markerDot.path = Toon.circle(c, c, 10).cgPath
        markerDot.fillColor = accent.cgColor
        markerDot.strokeColor = Toon.ink.cgColor
        markerDot.lineWidth = 4
        touchMarker.addSublayer(markerDot)
        layer.addSublayer(touchMarker)
    }

    /// Shows the marker at the current (pitch, vowel), or hides it when no
    /// note is playing. Implicit animations are off so it tracks the finger
    /// instead of easing after it.
    private func updateTouchMarker() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        touchMarker.isHidden = !isPlaying
        if isPlaying {
            touchMarker.position = CGPoint(x: bounds.minX + CGFloat(pitch) * bounds.width,
                                           y: bounds.minY + CGFloat(1 - vowel) * bounds.height)
        }
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTouchMarker()
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
    /// (Fingers arrive here through `TouchStack`, which routes a second
    /// finger to `moveTouch`; this guard covers direct callers.)
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
                setNeedsDisplay()
            }
        }
        updateTouchMarker()
    }

    func moveTouch(at point: CGPoint, in size: CGSize) {
        let (p, v) = Self.normalize(point, in: size)
        pitch = p; vowel = v
        onParameterChange?(.xyPitchTarget, p)
        onParameterChange?(.xyVowel, v)
        updateTouchMarker()
    }

    func endTouch() {
        isPlaying = false
        onParameterChange?(.xyNoteOn, 0.0)
        updateTouchMarker()
    }

    // Several fingers play like a mono keyboard: the newest sings, and
    // lifting it hands back to the one still down (see `TouchStack`).
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { perform(self.touches.press(ObjectIdentifier(t), at: t.location(in: self))) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { perform(self.touches.move(ObjectIdentifier(t), to: t.location(in: self))) }
    }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches { perform(self.touches.lift(ObjectIdentifier(t))) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func perform(_ action: TouchStack<ObjectIdentifier>.Action?) {
        switch action {
        case .begin(let p)?: beginTouch(at: p, in: bounds.size)
        case .move(let p)?:  moveTouch(at: p, in: bounds.size)
        case .end?:          endTouch()
        case nil:            break
        }
    }

    /// The touch marker's dot colour — the current character's accent, set
    /// by `SceneView` on character change.
    var accent: UIColor = Theme.defaultAccent {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            markerDot.fillColor = accent.cgColor
            CATransaction.commit()
        }
    }

    /// UserDefaults key: set once the scene has been touched; until then a
    /// small "touch to sing" hint shows (the scene no longer looks like a pad).
    static let hintDismissedKey = "scene.hintDismissed"
    private var showsHint = !UserDefaults.standard.bool(forKey: XYPadView.hintDismissedKey)

    /// Transparent overlay over the scene: pitch ticks along the bottom, a
    /// vowel scale up the right edge, and the first-touch hint. No box, no
    /// crosshair. The touch marker is `touchMarker`, not drawn here, so this
    /// reruns only on a resize (`contentMode = .redraw`) or hint dismissal.
    override func draw(_ rect: CGRect) {
        let rect = bounds
        guard rect.width > 0, rect.height > 0 else { return }
        let ink = Toon.ink
        // Pitch ticks along the bottom: one per semitone of the pad's octave
        // (C3 at the left edge, C4 at the right), at the exact x a touch
        // plays — so a snapped note lands on a tick. Natural notes taller,
        // like a keyboard. The two C's sit on the edges, under the border.
        for i in 1...11 {
            let x = rect.width * CGFloat(i) / 12
            let h: CGFloat = [1, 3, 6, 8, 10].contains(i) ? 7 : 12
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: rect.maxY - 4)); p.addLine(to: CGPoint(x: x, y: rect.maxY - h))
            Toon.stroke(p, width: 2, color: UIColor.white.withAlphaComponent(0.75))
        }
        // Vowel scale up the right edge, OO at the bottom: ink type on small
        // cream pills, so the labels read on every sky, light or dark.
        if rect.height >= 90 {
            let font = Theme.display(10)
            for (i, v) in ["OO", "OH", "AH", "EH", "EE"].enumerated() {
                let y = 14 + (rect.height - 50) * (1 - CGFloat(i) / 4)
                let s = NSAttributedString(string: v, attributes: [.font: font, .foregroundColor: ink])
                let size = s.size()
                let pill = CGRect(x: rect.maxX - 8 - size.width - 12, y: y - 1,
                                  width: size.width + 12, height: size.height + 4)
                Toon.shape(UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2),
                           fill: Theme.cream, lineWidth: 2, shaded: false)
                s.draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2))
            }
        }
        if showsHint && rect.height >= 90 {
            // Sticker lettering: a thick ink outline drawn first, white fill
            // over it, so the hint reads over any sky and over scene props
            // (a single-pass negative strokeWidth gives only a hairline).
            let text = NSLocalizedString("pad.hint", comment: "first-touch hint")
            let font = Theme.display(15)
            let outline = NSAttributedString(string: text, attributes: [.font: font, .strokeColor: ink, .strokeWidth: 24])
            let fill = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white])
            let size = fill.size()
            let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY + 12)
            outline.draw(at: origin)
            fill.draw(at: origin)
        }
    }
}
