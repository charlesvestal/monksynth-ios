import AVFoundation
import XCTest
@testable import MonkSynth

final class EditorBindingTests: XCTestCase {

    private func makeDescription() -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0x4D6E6B73,          // 'Mnks'
            componentManufacturer: 0x5673746C,     // 'Vstl'
            componentFlags: 0, componentFlagsMask: 0)
    }

    /// `AUParameterTree`'s token-based observer notifications are delivered
    /// asynchronously on a background thread and coalesced (confirmed
    /// empirically: on the order of tens of milliseconds even for a single
    /// write, versus `implementorValueObserver`, which fires synchronously
    /// and is what `ShadowTests`/`PresetTests` rely on). Anything that
    /// asserts on an observer having fired must poll the run loop rather
    /// than check once immediately after the write.
    private func pollUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - preferredContentSize / host-supplied rect

    func testPreferredContentSizeIs480x320() {
        let vc = AudioUnitViewController()
        vc.loadViewIfNeeded()
        XCTAssertEqual(vc.preferredContentSize, CGSize(width: 480, height: 320))
    }

    /// An AUv3 host can hand the view any rect at all (see `PluginView`'s
    /// own doc comment). This isn't a layout test — `LayoutTests` already
    /// covers the zone arithmetic — it's just confirming the view controller
    /// doesn't crash under an extreme host-supplied frame and doesn't let
    /// that frame leak into its own stated preference.
    func testViewSurvivesHostSuppliedRect() {
        let vc = AudioUnitViewController()
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 40, height: 4000)
        vc.view.layoutIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 4000, height: 40)
        vc.view.layoutIfNeeded()
        XCTAssertEqual(vc.preferredContentSize, CGSize(width: 480, height: 320))
    }

    // MARK: - createAudioUnit

    func testCreateAudioUnitReturnsMonkSynthAUAndRetainsIt() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription())
        XCTAssertTrue(unit is MonkSynthAU)
        XCTAssertTrue(vc.au === (unit as! MonkSynthAU))
    }

    // MARK: - UI -> AU

    func testKnobWriteReachesParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()   // drives viewDidLoad -> bind()

        let pluginView = vc.view as! PluginView
        pluginView.controls.onParameterChange?(.vowel, 0.73)

        let value = unit.parameterTree?.parameter(withAddress: Param.vowel.rawValue)?.value
        XCTAssertEqual(value ?? -1, 0.73, accuracy: 1e-6)
    }

    func testPadWriteReachesParameterTree() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        pluginView.pad.onParameterChange?(.xyPitchTarget, 0.2)
        pluginView.pad.onParameterChange?(.xyNoteOn, 1.0)

        let pitch = unit.parameterTree?.parameter(withAddress: Param.xyPitchTarget.rawValue)?.value
        let noteOn = unit.parameterTree?.parameter(withAddress: Param.xyNoteOn.rawValue)?.value
        XCTAssertEqual(pitch ?? -1, 0.2, accuracy: 1e-6)
        XCTAssertEqual(noteOn ?? -1, 1.0, accuracy: 1e-6)
    }

    // MARK: - Character selection

    /// `bind()` seeds the visible `CharacterView` from whatever the AU
    /// already holds — covers a session restored (`fullState` set) before
    /// the editor was ever bound.
    func testBindSeedsCharacterViewFromAUsCharacterID() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        unit.setCharacterID("fish")

        vc.loadViewIfNeeded()   // drives viewDidLoad -> bind()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(pluginView.stage.character.id, "fish")
    }

    /// UI -> AU: tapping the character to cycle it must write the new
    /// selection back into the AU (so it round-trips via `fullState`).
    func testCyclingCharacterWritesCharacterIDBackToAU() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(unit.characterID, "monk")

        pluginView.stage.cycleCharacter()

        XCTAssertEqual(unit.characterID, "fish")
        XCTAssertEqual(pluginView.stage.character.id, "fish")
    }

    /// AU -> UI: a `fullState` load reaching in *after* the editor is
    /// already bound and showing (e.g. a host applying a saved session to
    /// an already-open editor) must still update the visible character.
    func testLaterFullStateLoadUpdatesTheVisibleCharacter() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertEqual(pluginView.stage.character.id, "monk")

        unit.fullState = ["characterID": "unicorn"]

        // `onCharacterIDChange`'s handler hops to main via `DispatchQueue.
        // main.async` (defensive: `fullState` isn't guaranteed to be set
        // from the main thread), so — like the AUParameter observer tests
        // above — poll rather than asserting immediately.
        pollUntil { pluginView.stage.character.id == "unicorn" }
        XCTAssertEqual(pluginView.stage.character.id, "unicorn")
    }

    // MARK: - AU -> UI

    /// Host automation (an observer-token-less write) must reach the
    /// matching on-screen knob. `.vowel` lives on the MAIN page, which is
    /// shown by default, so no page switch is needed to see it update.
    func testHostAutomationUpdatesMatchingKnob() throws {
        let vc = AudioUnitViewController()
        let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
        vc.loadViewIfNeeded()

        let pluginView = vc.view as! PluginView
        XCTAssertNotNil(pluginView.controls.knob(for: .vowel))

        let param = unit.parameterTree!.parameter(withAddress: Param.vowel.rawValue)!
        param.setValue(0.11, originator: nil)   // simulate host-side automation

        // The observer fires on a background thread after a short coalescing
        // delay, then hops to main before touching the knob; poll for both.
        pollUntil { abs((pluginView.controls.knob(for: .vowel)?.value ?? -1) - 0.11) < 1e-6 }

        XCTAssertEqual(pluginView.controls.knob(for: .vowel)?.value ?? -1, 0.11, accuracy: 1e-6)
    }

    // MARK: - Originator-token self-filtering

    /// This is the mechanism `bind()` relies on to avoid a write this
    /// controller just made bouncing straight back into the knob that
    /// produced it: `AUParameterTree` skips re-delivering a change to the
    /// observer whose own token was passed as `originator`, while still
    /// notifying every other observer (a real host's automation recorder,
    /// or — here — a second, independent registration standing in for one).
    /// Verified empirically: the observer with a matching `originator`
    /// token never fires for that write, even after a generous poll; a
    /// differently-tokened (or nil-originator) write reaches every
    /// registered observer.
    func testWriteWithMatchingOriginatorDoesNotBounceBackToThatObserver() throws {
        let au = try MonkSynthAU(componentDescription: makeDescription())
        let tree = try XCTUnwrap(au.parameterTree)
        let param = try XCTUnwrap(tree.parameter(withAddress: Param.headSize.rawValue))

        var selfCallCount = 0
        let selfToken = tree.token(byAddingParameterObserver: { _, _ in selfCallCount += 1 })
        var otherCallCount = 0
        let otherToken = tree.token(byAddingParameterObserver: { _, _ in otherCallCount += 1 })
        defer {
            tree.removeParameterObserver(selfToken)
            tree.removeParameterObserver(otherToken)
        }

        param.setValue(0.42, originator: selfToken)
        pollUntil { otherCallCount > 0 }
        XCTAssertEqual(selfCallCount, 0,
                        "the observer whose own token originated the write must not be re-notified")
        XCTAssertEqual(otherCallCount, 1,
                        "a different observer (e.g. the host) must still see the change")

        param.setValue(0.77, originator: nil)
        pollUntil { selfCallCount > 0 }
        XCTAssertEqual(selfCallCount, 1, "a write with no originator must reach every observer")
        XCTAssertEqual(otherCallCount, 2)
    }

    // MARK: - Safe before allocateRenderResources

    func testUIAnimationAccessorsAreSafeBeforeAllocateRenderResources() throws {
        let au = try MonkSynthAU(componentDescription: makeDescription())
        XCTAssertEqual(au.uiVowel, 0.5, accuracy: 1e-6)
        XCTAssertEqual(au.uiAmplitude, 0, accuracy: 1e-6)
        XCTAssertFalse(au.uiNoteActive)
    }

    // MARK: - Teardown

    func testControllerDeallocatesWithoutCrashEvenIfNeverAppeared() throws {
        weak var weakVC: AudioUnitViewController?
        try autoreleasepool {
            let vc = AudioUnitViewController()
            _ = try vc.createAudioUnit(with: makeDescription())
            vc.loadViewIfNeeded()
            weakVC = vc
        }
        XCTAssertNil(weakVC, "nothing should be left holding the controller")
    }

    /// Regression test for the `CADisplayLink` retain-cycle fix: starting
    /// the UI link (via `viewDidAppear`) and then dropping the controller
    /// WITHOUT a matching `viewDidDisappear` — a host is not guaranteed to
    /// call it in every teardown path — must not leak the controller. With
    /// `CADisplayLink(target: self, ...)` instead of the weak-target proxy,
    /// this would fail: the link stays attached to the run loop and keeps
    /// the whole editor (including the `MonkSynthAU` it retains) alive.
    func testControllerDeallocatesEvenWithDisplayLinkRunningAndNoDisappear() throws {
        weak var weakVC: AudioUnitViewController?
        try autoreleasepool {
            let vc = AudioUnitViewController()
            _ = try vc.createAudioUnit(with: makeDescription())
            vc.loadViewIfNeeded()
            vc.viewDidAppear(false)   // starts the display link
            weakVC = vc
        }
        XCTAssertNil(weakVC, "a running CADisplayLink must not keep the view controller alive")
    }

    /// The observer token is meant to be removed in `deinit`. There's no
    /// public way to ask an `AUParameterTree` how many observers are
    /// registered, so this proves the cleanup path is safe the way it's
    /// actually exercised: the AU (and its tree) outlive the controller,
    /// and a later automation write against that tree — after the
    /// controller, and its token, are long gone — must not crash.
    func testObserverTokenCleanupDoesNotCrashLaterWrites() throws {
        var capturedUnit: MonkSynthAU!
        weak var weakVC: AudioUnitViewController?
        try autoreleasepool {
            let vc = AudioUnitViewController()
            let unit = try vc.createAudioUnit(with: makeDescription()) as! MonkSynthAU
            vc.loadViewIfNeeded()
            capturedUnit = unit
            weakVC = vc
        }
        XCTAssertNil(weakVC)

        let param = try XCTUnwrap(capturedUnit.parameterTree?.parameter(withAddress: Param.vowel.rawValue))
        param.setValue(0.5, originator: nil)   // must not crash
    }
}
