import UIKit

/// Zone frames for one layout pass. Pure data so LayoutTests can assert on it.
struct ZoneLayout: Equatable {
    var stage: CGRect
    var pad: CGRect
    var controls: CGRect

    /// The drawer handle's tap target. Always derived from `controls.minY`
    /// — see `PluginView.handleFrame(for:)` — never from `controls.maxY`,
    /// which is pinned to the bottom of the view and identical whether the
    /// drawer is open or closed.
    var handle: CGRect
}

/// The responsive three-zone container: Stage (the selected character), Pad
/// (the XY performance surface), and Controls (the five-page knob strip).
///
/// The control strip is a collapsible drawer, in both orientations,
/// defaulting to OPEN — the user asked for controls to be visible by
/// default; collapsing is something they reach for, not the starting state.
/// Portrait stacks the three zones vertically (stage / pad / strip);
/// landscape splits Stage and Pad side by side above the strip. Either way
/// the strip is pinned to the bottom of the view, so closing it grows the
/// Pad (and, at short heights, the Stage) into the reclaimed space.
///
/// A drawer shipped here once before and was reported as unreachable/dead:
/// the handle's hit region was anchored to `controls.maxY`, which — because
/// the strip is bottom-pinned — never changes between open and closed, so
/// the handle never visibly moved and nothing signalled it could be
/// dragged. This version anchors the handle to `controls.minY`, the edge
/// that actually travels; see `handleFrame(for:)`.
///
/// The strip gets `Theme.stripHeight` when open and there's room. When
/// there isn't, it shrinks, but never below `Theme.minUsableStripHeight` —
/// the height below which `ControlPages` can no longer draw an actual
/// knob — as long as there is at least that much room to give it; only a
/// truly degenerate host rect (smaller than the floor itself) forces it any
/// shorter. Closed, the strip is zero-height; only the handle draws. The
/// Stage yields space first (see `portraitLayout`/`landscapeLayout`), then
/// the Pad takes whatever is left; the Pad can end up below
/// `Theme.minPadHeight` at extreme sizes, which is an acceptable trade
/// against ever hiding the controls entirely when the drawer is open.
///
/// The split is chosen by aspect ratio (`inner.width >= inner.height`), not
/// device idiom, because an AUv3 host can hand this view any rect at all —
/// AUM in particular can give a wide, short strip on an iPhone. Below
/// `Theme.stageCollapseBelowHeight` of available height, the Stage yields so
/// the Pad stays playable; see `portraitLayout`/`landscapeLayout` for how
/// each orientation implements that.
final class PluginView: UIView {

    let stage = CharacterView()
    let pad = XYPadView()
    let controls = ControlPages()

    /// Fired when the about screen's "Source code" link is tapped. Left to
    /// the owning view controller to handle because the two containers this
    /// view runs in need two different APIs: the standalone app can call
    /// `UIApplication.shared.open`, but an AUv3 extension cannot — it must
    /// route through `extensionContext?.open(_:completionHandler:)` instead
    /// (see `AudioUnitViewController.bind()`).
    var onOpenURL: ((URL) -> Void)?

    /// Fired when the about screen's "Connect Bluetooth MIDI" button is
    /// tapped. Only reachable when `showsBluetoothOption` is true.
    var onBluetoothMIDI: (() -> Void)?

    /// Bluetooth MIDI pairing is a host-app concern, not something an AUv3
    /// editor embedded in someone else's host should offer — off by
    /// default; `RootViewController` (the standalone app) turns it on.
    var showsBluetoothOption = false

    /// Header ⓘ button that opens `AboutView`. Visually a small glyph, but
    /// sized to the full 44pt HIG minimum in both dimensions (see
    /// `layoutSubviews`) — a button's own frame already IS its hit area, so
    /// a single `UIButton` gets a big tap target for free.
    private let infoButton = UIButton(type: .system)
    private var aboutView: AboutView?
    private var moreAppsView: MoreAppsView?

    /// Minimum tap target per Apple's HIG.
    static let infoButtonSize: CGFloat = 44

    /// Whether the control drawer is expanded. Defaults to `true`: the user
    /// asked for controls visible by default, with collapsing as something
    /// they opt into, not the starting state.
    private(set) var drawerOpen = true

    /// The actual tap target for opening/closing the drawer. Deliberately
    /// much larger than the visible pill (`drawerHandleBar`) it contains: a
    /// tap target has to clear Apple's 44pt HIG minimum in both dimensions,
    /// which a thin bar alone cannot. This view stays transparent; only
    /// `drawerHandleBar` (and the chevron inside it) draws anything.
    private let drawerHandle = UIView()

    /// The small visible pill inside `drawerHandle`. Non-interactive — the
    /// tap gesture lives on `drawerHandle` itself — this view exists only
    /// so there's something to look at where the much-larger invisible hit
    /// region actually is.
    private let drawerHandleBar = UIView()

    /// A chevron, not a featureless dash: the fact that a control can
    /// move only shows up once you've already found it and dragged it, but
    /// a glyph that flips direction with state (▾ open / ▴ closed) reads as
    /// "tap here to move this" before the first tap. That was the actual
    /// gap in the original report — the handle merely not moving was a
    /// symptom, the deeper problem was nothing signalled it *could* move.
    /// Purely decorative (`isUserInteractionEnabled = false`); no text
    /// label per the design constraint — space at AUM strip sizes doesn't
    /// have room for one anyway.
    private let drawerHandleChevron = UIImageView()

    /// Minimum tap target per Apple's HIG (both dimensions >= 44pt). The
    /// visible pill stays small; only the invisible hit region around it
    /// grows to this size.
    static let drawerHitSize = CGSize(width: 60, height: 44)

    /// The visible pill's own size, centred inside `drawerHitSize`.
    private static let handlePillSize = CGSize(width: 44, height: 20)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        for v in [stage, pad, controls] as [UIView] { addSubview(v) }

        pad.layer.cornerRadius = Theme.cornerRadius
        pad.backgroundColor = Theme.panel
        pad.layer.borderWidth = 1
        pad.layer.borderColor = Theme.panelBorder.cgColor

        // Belt-and-suspenders: `controls`'s frame is always sized so
        // `ControlPages`'s own layout fits inside it (see
        // `controlStripHeight`), but clipping guards against it bleeding
        // into the pad above when the drawer is closed (zero height) or at
        // the smallest degenerate host rects a test might throw at it.
        controls.clipsToBounds = true

        installDrawerHandle()
        installInfoButton()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Drawer

    private func installDrawerHandle() {
        drawerHandle.backgroundColor = .clear
        drawerHandle.isUserInteractionEnabled = true
        drawerHandle.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(toggleDrawer)))
        addSubview(drawerHandle)

        drawerHandleBar.backgroundColor = Theme.panel
        drawerHandleBar.layer.cornerRadius = Self.handlePillSize.height / 2
        drawerHandleBar.layer.borderWidth = 1
        drawerHandleBar.layer.borderColor = Theme.panelBorder.cgColor
        drawerHandleBar.isUserInteractionEnabled = false
        drawerHandle.addSubview(drawerHandleBar)

        drawerHandleChevron.tintColor = Theme.textDim
        drawerHandleChevron.contentMode = .center
        drawerHandleChevron.isUserInteractionEnabled = false
        drawerHandleBar.addSubview(drawerHandleChevron)
        updateDrawerChevron()
    }

    @objc private func toggleDrawer() {
        drawerOpen.toggle()
        updateDrawerChevron()
        UIView.animate(withDuration: 0.25) { self.setNeedsLayout(); self.layoutIfNeeded() }
    }

    /// Points down (▾, "tap to collapse") while open, up (▴, "tap to
    /// expand") while closed — the chevron always points the direction the
    /// handle itself is about to travel, mirroring how the system's own
    /// pull-down/pull-up sheets signal direction.
    private func updateDrawerChevron() {
        let symbolName = drawerOpen ? "chevron.down" : "chevron.up"
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        drawerHandleChevron.image = UIImage(systemName: symbolName, withConfiguration: config)
    }

    // MARK: - About screen

    private func installInfoButton() {
        // An SF Symbol rather than the Unicode "ⓘ" (U+24D8 CIRCLED LATIN
        // SMALL LETTER I) character: verified on-device that glyph simply
        // does not render in the system font at any weight — the button
        // came up completely blank, title and all. `info.circle` is exactly
        // the mark this button represents anyway, and (unlike a Unicode
        // character) is guaranteed to render.
        infoButton.setImage(UIImage(systemName: "info.circle"), for: .normal)
        infoButton.tintColor = Theme.textDim
        infoButton.accessibilityLabel = NSLocalizedString("about.info", comment: "Open the about screen")
        infoButton.addTarget(self, action: #selector(showAbout), for: .touchUpInside)
        addSubview(infoButton)
    }

    @objc private func showAbout() {
        guard aboutView == nil else { return }
        let a = AboutView(frame: bounds)
        a.showsBluetoothButton = showsBluetoothOption
        a.onClose = { [weak self] in self?.hideAbout() }
        a.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        a.onBluetoothMIDI = { [weak self] in self?.onBluetoothMIDI?() }
        a.onMoreApps = { [weak self] in
            self?.hideAbout()
            self?.showMoreApps()
        }
        addSubview(a)
        aboutView = a
        setNeedsLayout()
    }

    private func hideAbout() {
        aboutView?.removeFromSuperview()
        aboutView = nil
    }

    private func showMoreApps() {
        guard moreAppsView == nil else { return }
        let m = MoreAppsView(frame: bounds)
        m.onClose = { [weak self] in self?.hideMoreApps() }
        m.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
        addSubview(m)
        moreAppsView = m
        setNeedsLayout()
    }

    private func hideMoreApps() {
        moreAppsView?.removeFromSuperview()
        moreAppsView = nil
    }

    /// Portrait stacks (stage / pad / strip); landscape splits (stage | pad)
    /// above the strip. The strip is a drawer in both orientations — see
    /// the class doc comment for the open/closed contract.
    ///
    /// Pure and static so `LayoutTests` can exercise every corner of the
    /// arithmetic without instantiating any UIKit views.
    /// - Parameter drawerOpen: whether the control strip is expanded.
    ///   Defaults to `true` — controls are visible unless the caller
    ///   explicitly asks for the collapsed layout.
    /// - Parameter safeArea: the view's `safeAreaInsets`. Critically this
    ///   includes the BOTTOM inset: on a device with a home indicator, the
    ///   bottom ~34pt is a system gesture region, and controls (or a handle)
    ///   placed there are unreachable — the system claims the touch before
    ///   the app sees it. Reported from a device, back when the strip lived
    ///   in a pull-up drawer: "control drawer can't be reached in portrait
    ///   because of the home indicator". Defaults to `.zero` so pure layout
    ///   tests can exercise the geometry without a real view.
    static func layout(in bounds: CGRect,
                        drawerOpen: Bool = true,
                        safeArea: UIEdgeInsets = .zero) -> ZoneLayout {
        let g = Theme.gutter
        let safe = bounds.inset(by: safeArea)
        let inner = safe.insetBy(dx: g, dy: g)
        guard inner.width > 0, inner.height > 0 else {
            return ZoneLayout(stage: .zero, pad: .zero, controls: .zero, handle: .zero)
        }

        let isWide = inner.width >= inner.height
        return isWide
            ? landscapeLayout(inner: inner, gutter: g, drawerOpen: drawerOpen)
            : portraitLayout(inner: inner, gutter: g, drawerOpen: drawerOpen)
    }

    /// The control strip's height for `available` total vertical space (the
    /// zone the strip shares with whatever sits above it, so `available - g`
    /// is what's left over once the strip's own top gutter is reserved),
    /// while the drawer is OPEN.
    ///
    /// Prefers `Theme.stripHeight`. When the available space doesn't stretch
    /// that far, the strip still won't drop below `Theme.minUsableStripHeight`
    /// — the height below which `ControlPages` can no longer draw an actual
    /// knob, only a tab bar over an invisible dial (its tab row plus
    /// `KnobView.captionHeight` eat the whole thing) — as long as `available`
    /// itself is at least that floor; whatever sits above the strip yields
    /// first. Only when `available` itself is smaller than the floor does the
    /// strip shrink further, because there is nothing left to give it. Never
    /// exceeds `available` and never goes negative.
    private static func controlStripHeight(available: CGFloat, gutter g: CGFloat) -> CGFloat {
        let roomAboveTheGutter = max(0, available - g)
        let preferred = min(Theme.stripHeight, roomAboveTheGutter)
        let floored = max(preferred, min(Theme.minUsableStripHeight, available))
        return max(0, min(floored, available))
    }

    /// The strip's height for this layout pass: `controlStripHeight` while
    /// the drawer is open, zero while it's closed. Zero rather than some
    /// small "collapsed" height so closing the drawer actually gives the
    /// reclaimed space back to the Pad (and, at short heights, the Stage)
    /// — the whole point of being able to collapse it — and so `controls`,
    /// which stays `clipsToBounds`, draws nothing at all when closed. Only
    /// the handle (a sibling view, not a subview of `controls`) remains
    /// visible.
    private static func stripHeight(available: CGFloat, gutter g: CGFloat, drawerOpen: Bool) -> CGFloat {
        drawerOpen ? controlStripHeight(available: available, gutter: g) : 0
    }

    /// The drawer handle's hit region, derived from the just-computed
    /// `controls` frame.
    ///
    /// Anchored to `controls.minY` — the drawer panel's MOVING edge — and
    /// grown UPWARD from there, rather than anchored to `controls.maxY` and
    /// grown upward from THAT. The panel is pinned to the bottom of the
    /// view in both orientations, so `controls.maxY` is the same in the
    /// open and closed layouts; only `controls.minY` moves as the strip's
    /// height changes. A handle built from `maxY` therefore never visibly
    /// moves between states — that was the original bug, and the report
    /// that a "control drawer... seemed like it wasn't possible to
    /// collapse" because "it didn't move". Building it from `minY` instead
    /// makes the handle travel the full distance the strip does (see
    /// `testHandleFrameDiffersMeaningfullyBetweenOpenAndClosed`), while
    /// still never dropping below `controls.minY` — which, since `controls`
    /// itself never extends past `inner.maxY` (itself already inset by the
    /// bottom safe area, see `layout`), keeps the handle clear of the home
    /// indicator's gesture strip in both states.
    private static func handleFrame(for controls: CGRect) -> CGRect {
        CGRect(x: controls.midX - drawerHitSize.width / 2,
               y: controls.minY - drawerHitSize.height,
               width: drawerHitSize.width,
               height: drawerHitSize.height)
    }

    /// Landscape: stage | pad side by side above the strip.
    ///
    /// Below `Theme.stageCollapseBelowHeight` the stage yields entirely.
    /// Unlike portrait, hiding it here buys the pad no extra *height* — both
    /// columns already share `topH` regardless of whether the stage draws
    /// anything into its column — so this is a flat "the character isn't
    /// worth showing this short" cutoff, not a space reallocation.
    private static func landscapeLayout(inner: CGRect, gutter g: CGFloat, drawerOpen: Bool) -> ZoneLayout {
        let stripH = stripHeight(available: inner.height, gutter: g, drawerOpen: drawerOpen)
        let topH = max(0, inner.height - stripH - g)
        let controlsFrame = CGRect(x: inner.minX, y: inner.maxY - stripH,
                                    width: inner.width, height: stripH)
        let handle = handleFrame(for: controlsFrame)

        if inner.height < Theme.stageCollapseBelowHeight || topH < Theme.minPadHeight {
            return ZoneLayout(
                stage: .zero,
                pad: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: topH),
                controls: controlsFrame,
                handle: handle)
        }

        let stageW = max(0, (inner.width - g) * 0.40)
        let padW = max(0, inner.width - stageW - g)
        return ZoneLayout(
            stage: CGRect(x: inner.minX, y: inner.minY, width: stageW, height: topH),
            pad: CGRect(x: inner.minX + stageW + g, y: inner.minY, width: padW, height: topH),
            controls: controlsFrame,
            handle: handle)
    }

    /// Portrait: stage over pad over the strip. Short heights make the stage
    /// yield its space to the pad gradually — the pad is topped up toward
    /// `minPadHeight` first and the stage gets whatever remains, down to
    /// zero.
    private static func portraitLayout(inner: CGRect, gutter g: CGFloat, drawerOpen: Bool) -> ZoneLayout {
        let stripH = stripHeight(available: inner.height, gutter: g, drawerOpen: drawerOpen)
        let remaining = max(0, inner.height - stripH - g)
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
        // `remaining` itself is negative — a case that only arises well
        // below any size this view will realistically be given, but is
        // still handled without producing a negative frame. At extreme
        // sizes `padH` itself can land below `minPadHeight` (the min/max
        // pair above doesn't force it up past what `remaining` can actually
        // supply) — acceptable, since the alternative would be hiding the
        // strip while it's meant to be open, which is exactly what this
        // contract rules out.
        if inner.height < Theme.stageCollapseBelowHeight || padH < Theme.minPadHeight {
            padH = min(max(Theme.minPadHeight, padH), max(0, remaining - g))
            stageH = max(0, remaining - padH - g)
        }

        let controlsFrame = CGRect(x: inner.minX, y: inner.maxY - stripH,
                                    width: inner.width, height: stripH)
        return ZoneLayout(
            stage: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: stageH),
            pad: CGRect(x: inner.minX, y: inner.minY + stageH + (stageH > 0 ? g : 0),
                        width: inner.width, height: padH),
            controls: controlsFrame,
            handle: handleFrame(for: controlsFrame))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let l = Self.layout(in: bounds, drawerOpen: drawerOpen, safeArea: safeAreaInsets)
        pad.frame = l.pad
        controls.frame = l.controls

        drawerHandle.frame = l.handle
        drawerHandleBar.frame = CGRect(
            x: (l.handle.width - Self.handlePillSize.width) / 2,
            y: (l.handle.height - Self.handlePillSize.height) / 2,
            width: Self.handlePillSize.width, height: Self.handlePillSize.height)
        drawerHandleChevron.frame = drawerHandleBar.bounds
        bringSubviewToFront(drawerHandle)

        // CharacterView's own display link only stops once its `window`
        // goes nil (see `CharacterView.updateDisplayLink`) — `isHidden`
        // alone leaves it attached to the hierarchy and ticking (idle
        // animation advance + setNeedsDisplay) every frame for a view
        // nobody can see. Fully detaching the stage when it collapses is
        // the fix that's reachable from here without touching
        // CharacterView.swift: removal triggers
        // `didMoveToWindow()`, which re-evaluates `updateDisplayLink()` and
        // tears the link down.
        let collapsed = l.stage.width < 1 || l.stage.height < 1
        if collapsed {
            if stage.superview != nil { stage.removeFromSuperview() }
        } else {
            if stage.superview == nil { insertSubview(stage, at: 0) }
            stage.frame = l.stage
        }

        // Top-right corner, flush with the header, but pulled in by
        // `safeAreaInsets` so it clears the status bar / Dynamic Island in
        // the standalone app (and whatever chrome a host reserves in the
        // AUv3 case) rather than fighting the system clock/battery icons
        // for the same few points. This necessarily overlaps the top-right
        // corner of `pad` in layouts where the pad reaches the very top of
        // the view (landscape's side-by-side split, or a portrait height
        // short enough to collapse the stage) — but the overlap is confined
        // to exactly this button's 44x44 frame. `bringSubviewToFront` below
        // means UIKit's hit-testing hands any touch that starts inside that
        // small square to `infoButton` instead of `pad` (hit-testing walks
        // subviews front-to-back and returns the first view whose bounds
        // contain the point), so the button "steals" only its own square
        // corner and nothing more — the rest of the pad's drag surface is
        // completely unaffected.
        let topInset = max(4, safeAreaInsets.top + 4)
        let rightInset = safeAreaInsets.right + 4
        infoButton.frame = CGRect(
            x: bounds.maxX - Self.infoButtonSize - rightInset, y: topInset,
            width: Self.infoButtonSize, height: Self.infoButtonSize)
        bringSubviewToFront(infoButton)

        if let aboutView {
            aboutView.frame = bounds
            bringSubviewToFront(aboutView)
        }
        if let moreAppsView {
            moreAppsView.frame = bounds
            bringSubviewToFront(moreAppsView)
        }
    }
}
