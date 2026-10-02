import UIKit

/// The five-page parameter surface: one tab bar plus a row of knobs per
/// page, covering every non-hidden parameter (see `Param.isHiddenFromUI`).
final class ControlPages: UIView {

    struct Page {
        let title: String
        let params: [Param]
    }

    /// Every non-hidden parameter appears exactly once. Asserted in tests.
    static let pages: [Page] = [
        Page(title: "MAIN",   params: [.vowel, .headSize, .aspiration, .level]),
        Page(title: "ENV",    params: [.attack, .decay, .sustain, .release]),
        Page(title: "UNISON", params: [.unison, .unisonDetune, .unisonVoiceSpread]),
        Page(title: "DELAY",  params: [.delay, .delayRate]),
        Page(title: "PITCH",  params: [.pitchBend, .pitchSnap, .portTime, .vibrato, .vibratoRate]),
    ]

    var onParameterChange: ((Param, Float) -> Void)?

    /// Set by the owner so a newly-shown page seeds its knobs from the
    /// AU's current parameter values (e.g. host automation of a parameter
    /// on a page that wasn't visible yet) rather than always from
    /// `Param.defaultValue`. See `showPage` and the finding in the task
    /// report for why this closure lives here instead of a stored snapshot.
    var valueProvider: ((Param) -> Float)?

    private(set) var pageIndex = 0
    /// The segmented bar: one ink-outlined capsule (`tabTrack`) holding the
    /// five buttons in `tabBar`. The selected button is filled with
    /// `accent` and outlined in ink; the rest are transparent.
    private let tabTrack = UIView()
    private let tabBar = UIStackView()
    private var tabButtons: [UIButton] = []
    private let knobRow = UIStackView()
    private(set) var knobs: [KnobView] = []

    /// Test-only-ish window into the stack view's actual bookkeeping.
    /// `knobs.count` alone can't catch a stale-arranged-subview leak because
    /// `knobs` is always freshly reassigned in `showPage`; this exposes the
    /// live `arrangedSubviews` so a leak in `knobRow` itself is visible.
    var visibleKnobViews: [UIView] { knobRow.arrangedSubviews }

    /// The segmented tab bar's frame, in this view's coordinates.
    var tabBarFrame: CGRect { tabTrack.frame }

    /// The button for `pageIndex`.
    var selectedTabButton: UIButton? { tabButtons.first { $0.tag == pageIndex } }
    var tabButtonsForTesting: [UIButton] { tabButtons }

    /// The character's accent: fills the selected tab and every knob's
    /// value arc. Set by `PluginView.applyPalette(_:)`.
    var accent: UIColor = Theme.defaultAccent {
        didSet {
            colourTabs(animated: false)
            knobs.forEach { $0.accent = accent }
        }
    }

    /// Tabs and knobs start this far below the strip's top edge: the drawer
    /// handle's pill straddles that edge (see `PluginView.handlePillFrame`)
    /// and must never sit over a tab or a dial.
    static let topClearance: CGFloat = 12

    /// Space between the strip's outer edge and its content (the 3pt ink
    /// outline plus breathing room).
    private static let inset: CGFloat = 8

    /// The tabs become a column on the left when the strip's width is at
    /// least this many times its height (e.g. iPhone landscape, iPad
    /// landscape, the AUM strip); otherwise they are a row across the top.
    /// The column lets the knobs use the strip's whole height.
    static let sideTabsAspect: CGFloat = 3.5
    private static let sideTabsWidth: CGFloat = 72
    private static let maxKnobCellWidth: CGFloat = 110

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.panel
        layer.borderColor = Theme.ink.cgColor
        layer.borderWidth = Theme.outline

        tabTrack.backgroundColor = Theme.panelDeep
        tabTrack.layer.borderColor = Theme.ink.cgColor
        tabTrack.layer.borderWidth = Theme.outline
        tabBar.distribution = .fillEqually
        tabBar.spacing = 0
        knobRow.axis = .horizontal; knobRow.distribution = .fillEqually; knobRow.spacing = 6
        tabTrack.addSubview(tabBar)
        addSubview(tabTrack); addSubview(knobRow)

        for (i, page) in Self.pages.enumerated() {
            let b = UIButton(type: .custom)
            b.setTitle(page.title, for: .normal)
            b.titleLabel?.font = Theme.display(11)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.tag = i
            b.layer.borderColor = Theme.ink.cgColor
            b.addTarget(self, action: #selector(selectPage(_:)), for: .touchUpInside)
            tabBar.addArrangedSubview(b)
            tabButtons.append(b)
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

    /// Fills the selected tab with the accent. Crossfades when the user
    /// switches page on screen; instant under Reduce Motion or off-screen.
    private func colourTabs(animated: Bool) {
        let apply = {
            for b in self.tabButtons {
                let selected = b.tag == self.pageIndex
                b.backgroundColor = selected ? self.accent : .clear
                b.layer.borderWidth = selected ? Theme.outline : 0
                b.setTitleColor(selected ? Theme.ink : Theme.textDim, for: .normal)
            }
        }
        if animated && window != nil && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: tabTrack, duration: 0.18, options: [.transitionCrossDissolve, .allowUserInteraction],
                              animations: apply)
        } else {
            apply()
        }
    }

    /// Not private: exercised directly from tests (page switching leak,
    /// `valueProvider` seeding) since synthesizing a `UIButton` tap isn't
    /// necessary to prove the underlying logic works.
    func showPage(_ index: Int) {
        let animated = index != pageIndex
        pageIndex = index
        colourTabs(animated: animated)

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
            k.accent = accent
            k.onChange = { [weak self] v in self?.onParameterChange?(p, v) }
            knobRow.addArrangedSubview(k)
            return k
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(Theme.stripCornerRadius, bounds.height / 2)
        let p = Self.inset
        let top = Self.topClearance
        let o = Theme.outline
        if bounds.width >= bounds.height * Self.sideTabsAspect {
            // Side column: the tabs sit left of the knobs, clear of the
            // handle pill at the centre of the top edge, so they can use the
            // strip's full inner height.
            let colH = max(0, bounds.height - 12)
            tabTrack.frame = CGRect(x: p, y: 6, width: Self.sideTabsWidth, height: colH)
            tabTrack.layer.cornerRadius = 14
            tabBar.axis = .vertical
            // On a long strip the knobs stay a group (at most
            // `maxKnobCellWidth` each) centred in the space beside the tabs,
            // rather than spreading to the far ends.
            let x = p + Self.sideTabsWidth + p
            let room = max(0, bounds.width - x - p)
            let n = CGFloat(max(1, knobs.count))
            let w = min(room, n * Self.maxKnobCellWidth + (n - 1) * knobRow.spacing)
            knobRow.frame = CGRect(x: x + (room - w) / 2, y: top, width: w,
                                   height: max(0, bounds.height - top - p))
        } else {
            let tabH: CGFloat = bounds.height >= 120 ? 30 : 26
            tabTrack.frame = CGRect(x: p, y: top, width: max(0, bounds.width - 2 * p), height: tabH)
            tabTrack.layer.cornerRadius = tabH / 2
            tabBar.axis = .horizontal
            let y = top + tabH + 6
            knobRow.frame = CGRect(x: p, y: y, width: max(0, bounds.width - 2 * p),
                                   height: max(0, bounds.height - y - p))
        }
        tabBar.frame = tabTrack.bounds.insetBy(dx: o, dy: o)
        tabBar.layoutIfNeeded()
        let font = Theme.display(tabBar.axis == .vertical ? 9 : 11)
        for b in tabButtons {
            b.titleLabel?.font = font
            b.layer.cornerRadius = min(b.bounds.width, b.bounds.height) / 2
        }
    }
}
