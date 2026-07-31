import CoreAudioKit

/// Binds the responsive `PluginView` (Stage / Pad / Controls) to
/// `MonkSynthAU` in both directions.
///
/// - UI -> AU: pad drags and knob turns call `AUParameter.setValue(_:originator:)`
///   (never write straight into the shadow) so the host sees, and can
///   record, the change as automation.
/// - AU -> UI: host automation, preset loads, and state restoration move the
///   on-screen knobs through the parameter tree's observer, without feeding
///   the value back into the AU — see the originator-token discussion on
///   `bind()` below.
/// - Render thread -> character: the character's vowel/amplitude/active state
///   comes from `MonkSynthAU.uiVowel`/`uiAmplitude`/`uiNoteActive`, plain
///   main-thread reads of values the render block already published — never
///   by calling back into the DSP engine, which the render thread owns.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {

    // Not `private`: EditorBindingTests asserts the controller retains the
    // unit it creates. Read-only from outside this file regardless.
    private(set) var au: MonkSynthAU?

    private var observerToken: AUParameterObserverToken?

    /// The exact tree `observerToken` was registered on, captured once at
    /// bind time. `deinit` removes the observer from THIS reference rather
    /// than re-reading `au?.parameterTree` fresh: `AUAudioUnit.parameterTree`
    /// has a public setter (unused by any host here, but part of the API
    /// contract `MonkSynthAU` exposes), so re-deriving it at teardown could
    /// in principle point at a tree the token was never added to. `weak`
    /// because the tree is already owned by `au` — this is a read path,
    /// never a retain, so it can never keep the AU (or its shadow/engine)
    /// alive past the point everything else has let go of it.
    private weak var boundTree: AUParameterTree?

    private var uiLink: CADisplayLink?

    /// Last vowel/amplitude actually pushed into the character view. The
    /// render block publishes `uiVowel`/`uiAmplitude` on every buffer —
    /// including silent ones — so most display-link ticks see no real
    /// change; skipping the write when nothing moved avoids re-triggering
    /// `CharacterView`'s unconditional `setNeedsDisplay()` (and the full
    /// redraw that follows) for no reason, up to 120 times a second on
    /// ProMotion.
    private var lastPulledVowel: Float?
    private var lastPulledAmplitude: Float?

    private var pluginView: PluginView { view as! PluginView }

    public override func loadView() {
        view = PluginView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        preferredContentSize = CGSize(width: 480, height: 320)
    }

    public func createAudioUnit(with desc: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try MonkSynthAU(componentDescription: desc)
        au = unit
        // `createAudioUnit(with:)` is not guaranteed to run on the main
        // thread; `bind()` touches UIKit, so hop over before calling it.
        DispatchQueue.main.async { [weak self] in self?.bind() }
        return unit
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startUILink()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        uiLink?.invalidate(); uiLink = nil
    }

    deinit {
        if let token = observerToken { boundTree?.removeParameterObserver(token) }
        uiLink?.invalidate()
    }

    /// Idempotent: called once from `viewDidLoad` and once (asynchronously)
    /// from `createAudioUnit`, in either order, and only actually binds once
    /// both the view is loaded and the AU exists. See the task report for
    /// why the two guards together make every interleaving safe.
    private func bind() {
        guard isViewLoaded, let au, let tree = au.parameterTree else { return }
        guard observerToken == nil else { return }

        // AU -> UI, registered first so `observerToken`/`boundTree` exist
        // before any UI write below can reach them.
        //
        // Fires for host automation, preset loads, and state restoration.
        // It must NOT fire (redundantly, and potentially fighting an
        // in-progress drag) for writes this same controller just made. The
        // fix is `AUParameter.setValue(_:originator:)`: passing this
        // observer's own token as `originator` on a write makes
        // `AUParameterTree` skip re-delivering that specific change to the
        // observer registered under that token — every OTHER observer
        // (a real host's automation recorder, or a second registration in
        // a test) still sees it. That asymmetry is exactly what's needed
        // here: our own knob already shows the value it just produced;
        // everyone else still needs to hear about the change.
        let token = tree.token(byAddingParameterObserver: { [weak self] address, value in
            guard let self, let param = Param(rawValue: address) else { return }
            DispatchQueue.main.async {
                self.pluginView.controls.setValue(value, for: param)
            }
        })
        observerToken = token
        boundTree = tree

        // UI -> AU. `originator: token` marks the write as ours, per above.
        let write: (Param, Float) -> Void = { [weak self] param, value in
            self?.au?.parameterTree?
                .parameter(withAddress: param.rawValue)?
                .setValue(value, originator: token)
        }
        pluginView.pad.onParameterChange = write
        pluginView.controls.onParameterChange = write

        // A page that has never been shown seeds its knobs from live AU
        // values instead of `Param.defaultValue`.
        pluginView.controls.valueProvider = { [weak self] param in
            self?.au?.parameterTree?.parameter(withAddress: param.rawValue)?.value
                ?? param.defaultValue
        }

        // The currently-visible page's knobs were already constructed
        // before `valueProvider` existed (in `ControlPages.init`), so push
        // the AU's current values into them explicitly, once.
        for p in Param.allCases where !p.isHiddenFromUI {
            if let v = tree.parameter(withAddress: p.rawValue)?.value {
                pluginView.controls.setValue(v, for: p)
            }
        }

        // Character selection: seed the view from whatever the AU already
        // holds (its default, or a session restored before this controller
        // ever bound — `MonkSynthAU.characterID` starts at the registry
        // default and `fullState`'s setter can run before `bind()` does).
        pluginView.stage.character = CharacterRegistry.character(withID: au.characterID)
        // AU -> UI: a later `fullState` load (a session/preset restore)
        // reaching in while the editor is already showing.
        au.onCharacterIDChange = { [weak self] id in
            DispatchQueue.main.async {
                self?.pluginView.stage.character = CharacterRegistry.character(withID: id)
            }
        }
        // UI -> AU: the user changed the character — an arrow step or a
        // picker selection (see `CharacterView.onCharacterSelected`'s doc
        // comment for why there is only one callback now, not a
        // persist-the-id one and a separate load-the-voice one gated on
        // which gesture fired). Every change persists the id AND loads the
        // voice; writes go through the parameter tree with
        // `setValue(_:originator:)` — never straight into the shadow — so
        // the host sees and can undo each of the 15 parameter changes,
        // exactly like a knob edit or a preset load. `originator: nil` (not
        // `token`) is deliberate: this write isn't "the knob confirming the
        // value it just produced" (the one case `token` exists to silence —
        // see the comment on `token` above), it's a batch of values nothing
        // on screen currently reflects, so `bind()`'s own observer must fire
        // too and refresh every affected knob — the same reasoning
        // `MonkSynthAU.fullState`'s setter and `currentPreset`'s setter
        // already use for the identical "apply a whole configuration, then
        // resync the UI" situation.
        pluginView.stage.onCharacterSelected = { [weak self] character in
            guard let self else { return }
            self.au?.setCharacterID(character.id)
            guard let tree = self.au?.parameterTree else { return }
            for (param, value) in CharacterVoiceTable.voice(for: character) {
                tree.parameter(withAddress: param.rawValue)?.setValue(value, originator: nil)
            }
        }

        // The about screen's "Source code" link. An app extension cannot
        // call `UIApplication.shared.open` (there is no `UIApplication`
        // instance to call it on) — `extensionContext?.open` is the host-
        // mediated equivalent extensions use instead.
        // `showsBluetoothOption` stays at `PluginView`'s default `false`:
        // Bluetooth MIDI pairing belongs to the standalone host app, not to
        // an editor embedded inside someone else's host.
        pluginView.onOpenURL = { [weak self] url in
            self?.extensionContext?.open(url, completionHandler: nil)
        }
    }

    private func startUILink() {
        guard uiLink == nil else { return }
        // CADisplayLink retains its target for as long as it stays added to
        // a run loop, which is until something explicitly calls
        // `invalidate()`. Pointing it straight at `self` would mean a host
        // that tears this controller down without a matching
        // viewDidAppear/viewDidDisappear pair (nothing in AUv3 guarantees
        // one) leaks the whole editor — including the `MonkSynthAU` it
        // retains. Routing through a weak-target proxy means the link can
        // only keep the tiny proxy alive, never `self`; `deinit`'s own
        // `uiLink?.invalidate()` still runs the normal way once nothing
        // else is holding `self`.
        let proxy = DisplayLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        uiLink = link
    }

    /// Reads the render thread's published animation state. Never touches
    /// the engine or calls into `dsp/` — these are plain main-thread loads
    /// of values `RenderContext.render` already wrote after the last block.
    fileprivate func pullAnimationState() {
        guard let au else { return }
        let vowel = au.uiVowel
        let amplitude = au.uiAmplitude
        if vowel != lastPulledVowel {
            pluginView.stage.vowel = vowel
            lastPulledVowel = vowel
        }
        if amplitude != lastPulledAmplitude {
            pluginView.stage.amplitude = amplitude
            lastPulledAmplitude = amplitude
        }
        // CharacterView's own `noteActive` didSet already guards on change,
        // so no need to duplicate that check here.
        pluginView.stage.noteActive = au.uiNoteActive
    }
}

/// Breaks the strong retain `CADisplayLink(target:selector:)` would
/// otherwise put on the view controller. See `startUILink`.
private final class DisplayLinkProxy: NSObject {
    private weak var owner: AudioUnitViewController?
    init(_ owner: AudioUnitViewController) { self.owner = owner }
    @objc func tick() { owner?.pullAnimationState() }
}
