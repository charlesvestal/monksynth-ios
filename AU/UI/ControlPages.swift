import UIKit

/// The five-page parameter surface: one tab bar plus a row of knobs per
/// page, covering all 18 non-hidden parameters (see `Param.isHiddenFromUI`).
final class ControlPages: UIView {

    struct Page {
        let title: String
        let params: [Param]
    }

    /// Every non-hidden parameter appears exactly once. Asserted in tests.
    static let pages: [Page] = [
        Page(title: "MAIN",   params: [.vowel, .headSize, .level, .portTime, .aspiration]),
        Page(title: "ENV",    params: [.attack, .decay, .sustain, .release]),
        Page(title: "UNISON", params: [.unison, .unisonDetune, .unisonVoiceSpread]),
        Page(title: "DELAY",  params: [.delay, .delayRate]),
        Page(title: "BEND",   params: [.pitchBend, .pitchBendRouting, .vibrato, .vibratoRate]),
    ]

    var onParameterChange: ((Param, Float) -> Void)?
    var contentInsetTop: CGFloat = 0 { didSet { setNeedsLayout() } }

    /// Set by the owner so a newly-shown page seeds its knobs from the
    /// AU's current parameter values (e.g. host automation of a parameter
    /// on a page that wasn't visible yet) rather than always from
    /// `Param.defaultValue`. See `showPage` and the finding in the task
    /// report for why this closure lives here instead of a stored snapshot.
    var valueProvider: ((Param) -> Float)?

    private(set) var pageIndex = 0
    private let tabBar = UIStackView()
    private let knobRow = UIStackView()
    private(set) var knobs: [KnobView] = []

    /// Test-only-ish window into the stack view's actual bookkeeping.
    /// `knobs.count` alone can't catch a stale-arranged-subview leak because
    /// `knobs` is always freshly reassigned in `showPage`; this exposes the
    /// live `arrangedSubviews` so a leak in `knobRow` itself is visible.
    var visibleKnobViews: [UIView] { knobRow.arrangedSubviews }

    override init(frame: CGRect) {
        super.init(frame: frame)
        tabBar.axis = .horizontal; tabBar.distribution = .fillEqually; tabBar.spacing = 3
        knobRow.axis = .horizontal; knobRow.distribution = .fillEqually; knobRow.spacing = 6
        addSubview(tabBar); addSubview(knobRow)

        for (i, page) in Self.pages.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(page.title, for: .normal)
            b.titleLabel?.font = Theme.label(9)
            b.tag = i
            b.layer.cornerRadius = 5
            b.addTarget(self, action: #selector(selectPage(_:)), for: .touchUpInside)
            tabBar.addArrangedSubview(b)
        }
        showPage(0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func selectPage(_ sender: UIButton) { showPage(sender.tag) }

    /// Values pushed in from the AU so the knobs reflect host automation.
    func setValue(_ v: Float, for param: Param) {
        knobs.first { $0.param == param }?.value = v
    }

    func knob(for param: Param) -> KnobView? {
        knobs.first { $0.param == param }
    }

    /// Not private: exercised directly from tests (page switching leak,
    /// `valueProvider` seeding) since synthesizing a `UIButton` tap isn't
    /// necessary to prove the underlying logic works.
    func showPage(_ index: Int) {
        pageIndex = index
        for (i, view) in tabBar.arrangedSubviews.enumerated() {
            guard let b = view as? UIButton else { continue }
            b.backgroundColor = i == index ? Theme.accent : Theme.panel
            b.setTitleColor(i == index ? Theme.background : Theme.textDim, for: .normal)
        }

        // Explicitly remove every arranged subview rather than relying on
        // `removeFromSuperview()` alone to also detach it from
        // `arrangedSubviews`. Empirically the two stay in sync for a plain
        // UIStackView (verified in ControlPagesTests), but doing both steps
        // by hand makes the invariant hold by construction instead of by an
        // undocumented side effect, and costs nothing.
        knobRow.arrangedSubviews.forEach { view in
            knobRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        knobs = Self.pages[index].params.map { p in
            let initial = valueProvider?(p) ?? p.defaultValue
            let k = KnobView(param: p, value: initial)
            k.onChange = { [weak self] v in self?.onParameterChange?(p, v) }
            knobRow.addArrangedSubview(k)
            return k
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top = contentInsetTop
        let tabH: CGFloat = 20
        tabBar.frame = CGRect(x: 4, y: top, width: bounds.width - 8, height: tabH)
        knobRow.frame = CGRect(x: 4, y: top + tabH + 4,
                               width: bounds.width - 8,
                               height: max(0, bounds.height - top - tabH - 8))
    }
}
