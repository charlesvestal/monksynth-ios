import UIKit
import CoreAudioKit

/// Standalone counterpart to `AU/AudioUnitViewController.swift`: the exact
/// same `PluginView` UI, but bound to a `LocalEngine` (its own
/// `AVAudioEngine` + `RenderContext`) instead of an `AUParameterTree` —
/// there is no host here to record automation to, so UI writes go straight
/// into the engine's parameter shadow, and there is no observer-token
/// dance to avoid a write bouncing back into the control that made it.
final class RootViewController: UIViewController {

    private let audio = LocalEngine()
    private let midi = MIDIInput()

    private var uiLink: CADisplayLink?

    /// Last vowel/amplitude actually pushed into the monk. `RenderContext`
    /// publishes these on every render callback — including silent ones —
    /// so most display-link ticks see no real change; skipping the write
    /// when nothing moved avoids re-triggering `MonkView`'s unconditional
    /// `setNeedsDisplay()` for no reason, up to 120 times a second on
    /// ProMotion. Mirrors `AudioUnitViewController.lastPulledVowel/Amplitude`.
    private var lastPulledVowel: Float?
    private var lastPulledAmplitude: Float?

    private var pluginView: PluginView { view as! PluginView }

    /// Set by `startAudio()` if `LocalEngine.start()` throws. Presenting the
    /// alert is deferred to `viewDidAppear` rather than done immediately in
    /// `viewDidLoad` (where `startAudio()` itself runs, so audio setup
    /// begins as early as possible) — at `viewDidLoad` time this controller
    /// is `window.rootViewController`, but `SceneDelegate` hasn't called
    /// `makeKeyAndVisible()` yet, so `view.window` is technically installed
    /// but not yet key; presenting there risks UIKit's
    /// "not in the window hierarchy" warning and a dropped/mistimed alert.
    private var pendingStartError: Error?

    override func loadView() {
        view = PluginView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
        wireMIDI()
        wireAboutScreen()
        startAudio()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startUILink()
        if let error = pendingStartError {
            pendingStartError = nil
            presentStartError(error)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        uiLink?.invalidate(); uiLink = nil
    }

    deinit { uiLink?.invalidate() }

    // MARK: - UI -> engine, engine -> UI

    private func bind() {
        pluginView.pad.onParameterChange = { [weak self] param, value in
            self?.audio.setParameter(param, value)
        }
        pluginView.controls.onParameterChange = { [weak self] param, value in
            self?.audio.setParameter(param, value)
        }
        // A page that has never been shown seeds its knobs from the
        // engine's live values instead of `Param.defaultValue`.
        pluginView.controls.valueProvider = { [weak self] param in
            self?.audio.value(of: param) ?? param.defaultValue
        }
        // The currently-visible page's knobs were already constructed
        // before `valueProvider` existed (in `ControlPages.init`), so push
        // the engine's current values into them explicitly, once.
        for p in Param.allCases where !p.isHiddenFromUI {
            pluginView.controls.setValue(audio.value(of: p), for: p)
        }
    }

    private func startAudio() {
        do {
            try audio.start()
        } catch {
            pendingStartError = error
        }
    }

    private func presentStartError(_ error: Error) {
        let alert = UIAlertController(
            title: NSLocalizedString("audio.start.failed.title", comment: "Audio engine failed to start"),
            message: error.localizedDescription,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("ok", comment: "Dismiss"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - MIDI -> engine, MIDI -> UI

    private func wireMIDI() {
        // Note on/off: straight through. `LocalEngine.noteOn`/`noteOff`
        // only ever queue (see `NoteEventQueue`), so this is safe to call
        // from CoreMIDI's own thread, which is what actually calls this
        // closure.
        midi.onNoteOn = { [weak self] note, velocity in
            self?.audio.noteOn(note, velocity: velocity)
        }
        midi.onNoteOff = { [weak self] note in
            self?.audio.noteOff(note)
        }
        // CC: map to the matching Param (upstream controller.cpp:454-458,
        // the same table `MonkSynthAU.internalRenderBlock`'s `0xB0` case
        // uses), write it into the engine, and mirror it onto the matching
        // on-screen knob. `setParameter` is shadow-safe from any thread;
        // touching `pluginView` is not, so that part hops to main.
        midi.onControlChange = { [weak self] cc, value in
            guard let self,
                  let addr = RenderContext.parameter(forCC: cc),
                  let param = Param(rawValue: UInt64(addr.rawValue))
            else { return }
            self.audio.setParameter(param, value)
            DispatchQueue.main.async {
                self.pluginView.controls.setValue(value, for: param)
            }
        }
        // Pitch bend: `LocalEngine.applyPitchBend` fans a raw wheel position
        // out to pitchBend and/or vowel depending on the routing mode (see
        // its doc comment) — rather than thread the touched-address list
        // back out, just re-pull both knobs afterward; cheap, and matches
        // how `AudioUnitViewController`'s host-automation observer already
        // updates knobs unconditionally on every delivered change.
        midi.onPitchBend = { [weak self] normalized in
            guard let self else { return }
            self.audio.applyPitchBend(normalized)
            DispatchQueue.main.async {
                self.pluginView.controls.setValue(self.audio.value(of: .pitchBend), for: .pitchBend)
                self.pluginView.controls.setValue(self.audio.value(of: .vowel), for: .vowel)
            }
        }
    }

    // MARK: - Monk animation

    private func startUILink() {
        guard uiLink == nil else { return }
        // CADisplayLink retains its target for as long as it stays added to
        // a run loop. Pointing it straight at `self` would leak this
        // controller (and the `LocalEngine`/`MIDIInput` it owns) if
        // viewDidDisappear is ever skipped. Routing through a weak-target
        // proxy — mirroring `AudioUnitViewController`'s own
        // `DisplayLinkProxy` (private to that file, so duplicated here
        // rather than reused across the AU/Host boundary) — means the link
        // can only keep the tiny proxy alive, never `self`.
        let proxy = DisplayLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        uiLink = link
    }

    /// Reads the render thread's published animation state. Never touches
    /// the engine or `dsp/` — plain main-thread loads of values
    /// `RenderContext.render` already wrote after the last block.
    fileprivate func pullAnimationState() {
        let vowel = audio.uiVowel
        let amplitude = audio.uiAmplitude
        if vowel != lastPulledVowel {
            pluginView.stage.vowel = vowel
            lastPulledVowel = vowel
        }
        if amplitude != lastPulledAmplitude {
            pluginView.stage.amplitude = amplitude
            lastPulledAmplitude = amplitude
        }
        // MonkView's own `noteActive` didSet already guards on change, so
        // no need to duplicate that check here.
        pluginView.stage.noteActive = audio.uiNoteActive
    }

    // MARK: - About screen / Bluetooth MIDI

    /// The standalone app is the real entry point for the about screen's
    /// "Source code" link and its Bluetooth MIDI shortcut — unlike the AUv3
    /// extension (`AudioUnitViewController.bind()`), this app has an actual
    /// `UIApplication` to hand a URL to, and it owns the Bluetooth MIDI
    /// picker outright rather than borrowing a host's. `showsBluetoothOption`
    /// is what makes `PluginView`'s about screen show that button at all —
    /// it defaults to false so the AUv3 editor never offers it when embedded
    /// in someone else's host. This replaces the small temporary corner
    /// button that used to be the only way to reach Bluetooth MIDI; the
    /// about screen's ⓘ button is the real, permanent entry point now.
    private func wireAboutScreen() {
        pluginView.showsBluetoothOption = true
        pluginView.onOpenURL = { url in UIApplication.shared.open(url) }
        pluginView.onBluetoothMIDI = { [weak self] in self?.presentBluetoothMIDI() }
    }

    func presentBluetoothMIDI() {
        let central = CABTMIDICentralViewController()
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissBluetoothMIDI))
        let nav = UINavigationController(rootViewController: central)
        present(nav, animated: true)
    }

    @objc private func dismissBluetoothMIDI() {
        dismiss(animated: true)
    }
}

/// Breaks the strong retain `CADisplayLink(target:selector:)` would
/// otherwise put on the view controller. See `startUILink`.
private final class DisplayLinkProxy: NSObject {
    private weak var owner: RootViewController?
    init(_ owner: RootViewController) { self.owner = owner }
    @objc func tick() { owner?.pullAnimationState() }
}
