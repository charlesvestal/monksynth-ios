import UIKit

/// Zone frames for one layout pass. Pure data so LayoutTests can assert on it.
struct ZoneLayout: Equatable {
    var stage: CGRect
    var pad: CGRect
    var controls: CGRect
    var isDrawer: Bool
}

/// The responsive three-zone container: Stage (the monk), Pad (the XY
/// performance surface), and Controls (the five-page knob strip).
///
/// Portrait stacks the three zones vertically, with Controls tucked into a
/// pull-up drawer so the pad gets most of the screen. Landscape splits Stage
/// and Pad side by side above a control strip that is always visible — no
/// drawer, since there is width to spare.
///
/// The split is chosen by aspect ratio (`inner.width >= inner.height`), not
/// device idiom, because an AUv3 host can hand this view any rect at all —
/// AUM in particular can give a wide, short strip on an iPhone. Below
/// `Theme.stageCollapseBelowHeight` of available height, the Stage yields so
/// the Pad stays playable; see `portraitLayout`/`landscapeLayout` for how
/// each orientation implements that.
final class PluginView: UIView {

    let stage = MonkView()
    let pad = XYPadView()
    let controls = ControlPages()

    /// The actual tap target for opening/closing the drawer. Deliberately
    /// much larger than the visible pill (`drawerHandleBar`) it contains: a
    /// 4pt-tall hit region is well under Apple's 44pt HIG minimum and is
    /// effectively unhittable. This view stays transparent and sized to at
    /// least 44pt in both dimensions; only `drawerHandleBar` draws anything.
    private let drawerHandle = UIView()
    private let drawerHandleBar = UIView()
    private var drawerOpen = false

    /// Minimum tap target per Apple's HIG (both dimensions >= 44pt). The
    /// visible pill stays small; only the invisible hit region around it
    /// grows to this size.
    static let drawerHitSize = CGSize(width: 60, height: 44)

    /// Test-only window into the hit region's actual size. Mirrors
    /// `ControlPages.visibleKnobViews`: the visible bar is intentionally
    /// tiny, so a test asserting the real tap target needs a seam past it.
    var drawerHitFrame: CGRect { drawerHandle.frame }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        for v in [stage, pad, controls] as [UIView] { addSubview(v) }
        addSubview(drawerHandle)
        drawerHandle.addSubview(drawerHandleBar)

        drawerHandle.backgroundColor = .clear
        drawerHandle.isUserInteractionEnabled = true
        drawerHandle.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(toggleDrawer)))

        drawerHandleBar.backgroundColor = Theme.panelBorder
        drawerHandleBar.layer.cornerRadius = 2
        drawerHandleBar.isUserInteractionEnabled = false
        drawerHandleBar.frame = CGRect(
            x: (Self.drawerHitSize.width - 34) / 2,
            y: (Self.drawerHitSize.height - 4) / 2,
            width: 34, height: 4)

        pad.layer.cornerRadius = Theme.cornerRadius
        pad.backgroundColor = Theme.panel
        pad.layer.borderWidth = 1
        pad.layer.borderColor = Theme.panelBorder.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func toggleDrawer() {
        drawerOpen.toggle()
        UIView.animate(withDuration: 0.25) { self.setNeedsLayout(); self.layoutIfNeeded() }
    }

    /// Portrait stacks (monk / pad / drawer); landscape splits (monk | pad)
    /// with the control strip always visible.
    ///
    /// Pure and static so `LayoutTests` can exercise every corner of the
    /// arithmetic without instantiating any UIKit views.
    static func layout(in bounds: CGRect, drawerOpen: Bool) -> ZoneLayout {
        let g = Theme.gutter
        let inner = bounds.insetBy(dx: g, dy: g)
        guard inner.width > 0, inner.height > 0 else {
            return ZoneLayout(stage: .zero, pad: .zero, controls: .zero, isDrawer: false)
        }

        let isWide = inner.width >= inner.height
        return isWide
            ? landscapeLayout(inner: inner, gutter: g)
            : portraitLayout(inner: inner, gutter: g, drawerOpen: drawerOpen)
    }

    /// Landscape: stage | pad side by side above an always-visible strip.
    ///
    /// Below `Theme.stageCollapseBelowHeight` the stage yields entirely.
    /// Unlike portrait, hiding it here buys the pad no extra *height* — both
    /// columns already share `topH` regardless of whether the stage draws
    /// anything into its column — so this is a flat "the monk isn't worth
    /// showing this short" cutoff, not a space reallocation.
    private static func landscapeLayout(inner: CGRect, gutter g: CGFloat) -> ZoneLayout {
        // Reserve at least minPadHeight *and* the gutter between the strip
        // and the row above it before letting the strip claim its full
        // preferred height. The first draft capped the strip at
        // `inner.height - minPadHeight` and forgot the gutter, which let
        // `topH` (and so the pad) fall `g` points short of `minPadHeight`.
        let stripH = min(Theme.stripHeight, max(0, inner.height - Theme.minPadHeight - g))
        let topH = max(0, inner.height - stripH - (stripH > 0 ? g : 0))
        let controlsFrame = CGRect(x: inner.minX, y: inner.maxY - stripH,
                                    width: inner.width, height: stripH)

        if inner.height < Theme.stageCollapseBelowHeight || topH < Theme.minPadHeight {
            return ZoneLayout(
                stage: .zero,
                pad: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: topH),
                controls: controlsFrame,
                isDrawer: false)
        }

        let stageW = max(0, (inner.width - g) * 0.40)
        let padW = max(0, inner.width - stageW - g)
        return ZoneLayout(
            stage: CGRect(x: inner.minX, y: inner.minY, width: stageW, height: topH),
            pad: CGRect(x: inner.minX + stageW + g, y: inner.minY, width: padW, height: topH),
            controls: controlsFrame,
            isDrawer: false)
    }

    /// Portrait: controls live in a drawer; only the handle shows when
    /// closed. Short heights make the stage yield its space to the pad
    /// gradually — the pad is topped up toward `minPadHeight` first and the
    /// stage gets whatever remains, down to zero.
    private static func portraitLayout(inner: CGRect, gutter g: CGFloat, drawerOpen: Bool) -> ZoneLayout {
        let drawerH = drawerOpen
            ? min(Theme.stripHeight + Theme.drawerHandleHeight,
                  max(0, inner.height - Theme.minPadHeight))
            : Theme.drawerHandleHeight
        let remaining = inner.height - drawerH - g
        var stageH = remaining * 0.48
        var padH = remaining - stageH - g

        // Short view: the stage yields first so the pad stays playable.
        //
        // `padH` is clamped to `max(0, remaining - g)` — never more than
        // what's left after reserving one gutter for the stage/pad divider.
        // That in turn guarantees `stageH = max(0, remaining - padH - g)`
        // can never go negative: since padH <= remaining - g whenever that
        // quantity is >= 0, `remaining - padH - g >= 0` always holds, so the
        // outer `max(0, ...)` never actually has to bite except when
        // `remaining` itself is negative (an overlong drawer eating more
        // than the available height) — a case that only arises well below
        // any size this view will realistically be given, but is still
        // handled without producing a negative frame.
        if inner.height < Theme.stageCollapseBelowHeight || padH < Theme.minPadHeight {
            padH = min(max(Theme.minPadHeight, padH), max(0, remaining - g))
            stageH = max(0, remaining - padH - g)
        }

        return ZoneLayout(
            stage: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: stageH),
            pad: CGRect(x: inner.minX, y: inner.minY + stageH + (stageH > 0 ? g : 0),
                        width: inner.width, height: padH),
            controls: CGRect(x: inner.minX, y: inner.maxY - drawerH,
                             width: inner.width, height: drawerH),
            isDrawer: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let l = Self.layout(in: bounds, drawerOpen: drawerOpen)
        pad.frame = l.pad
        controls.frame = l.controls

        // MonkView's own display link only stops once its `window` goes
        // nil (see `MonkView.updateDisplayLink`) — `isHidden` alone leaves
        // it attached to the hierarchy and ticking (idle animation advance
        // + setNeedsDisplay) every frame for a view nobody can see. Fully
        // detaching the stage when it collapses is the fix that's reachable
        // from here without touching MonkView.swift: removal triggers
        // `didMoveToWindow()`, which re-evaluates `updateDisplayLink()` and
        // tears the link down.
        let collapsed = l.stage.width < 1 || l.stage.height < 1
        if collapsed {
            if stage.superview != nil { stage.removeFromSuperview() }
        } else {
            if stage.superview == nil { insertSubview(stage, at: 0) }
            stage.frame = l.stage
        }

        if l.isDrawer {
            drawerHandle.isHidden = false
            // Centre the 44pt+ hit region on the same point the old 4pt-tall
            // visible bar used to occupy (controls.minY + 8, height 4 -> its
            // own centre is controls.minY + 10), so the tap target grows
            // without moving the pill it surrounds.
            let barCenterY = l.controls.minY + 10
            drawerHandle.frame = CGRect(
                x: l.controls.midX - Self.drawerHitSize.width / 2,
                y: barCenterY - Self.drawerHitSize.height / 2,
                width: Self.drawerHitSize.width, height: Self.drawerHitSize.height)
            controls.contentInsetTop = Theme.drawerHandleHeight
        } else {
            drawerHandle.isHidden = true
            controls.contentInsetTop = 0
        }
    }
}
