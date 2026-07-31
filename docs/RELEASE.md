# Releasing MonkSynth

## Before every release

1. All green:
   ```bash
   Tests/CTests/run.sh            # upstream's C DSP unit tests
   Tests/ParityHarness/run.sh     # golden matches (352800 samples)
   scripts/test.sh                # 62 XCTest cases
   ```
   `Tests/ParityHarness/run.sh` is the one that matters most: it proves the
   Swift parameter mapping still renders bit-identical audio to the vendored C
   engine. If it fails, something changed how the synth *sounds* — find the bug,
   do not recapture the golden.

2. Bump `MARKETING_VERSION` in `project.yml` if this is a user-visible release.
   The build number comes from `git rev-list --count HEAD` automatically, so it
   is always unique without anyone remembering to bump it.

3. Verify on hardware — `scripts/run_device.sh`, then by hand:
   - the standalone sounds when you drag the pad
   - the AUv3 loads its **custom UI** (not a generic parameter list) in AUM
   - MIDI from AUM plays it and the monk animates
   - portrait and landscape both reflow without clipping
   - save and reload the AUM session; parameters come back

4. `scripts/deploy_testflight.sh`

5. Work `../schwung-parent/ambiotica-plugin/docs/PLUGIN-RELEASE-PITFALLS.md`
   before submitting for review — especially #14 (verify every responsive
   layout) and #17 (version trains).

## Privacy usage strings — check this whenever a new API is added

**No test can catch a missing one.** iOS terminates the process at the OS level
(SIGABRT, uncatchable, no error to handle) the instant an app touches
privacy-sensitive data without the matching `Info.plist` usage string. A unit
test cannot exercise it because the crash kills the test runner, and the app
builds, installs and launches perfectly — it only dies when a user taps the
feature.

This has now bitten this codebase and its sibling:

| API | Required key | How it failed |
|---|---|---|
| `CABTMIDICentralViewController` (Bluetooth MIDI) | `NSBluetoothAlwaysUsageDescription` | Shipped in builds 45–56; "Connect Bluetooth MIDI" crashed instantly. Fixed in `1ebcee1`. |
| Audio input (JUCE standalone) | `NSMicrophoneUsageDescription` | `ambiotica-plugin` — standalone aborted on launch with signal 6. |

**So: when you add any API that touches the microphone, Bluetooth, camera,
location, contacts, photos, local network or motion — add its usage string in
the same commit**, add the localized value to every `*.lproj/InfoPlist.strings`,
and verify it reached the built product rather than trusting the source edit:

```bash
plutil -p "$(xcodebuild -project MonkSynth.xcodeproj -scheme MonkSynth \
  -sdk iphonesimulator -configuration Debug -showBuildSettings \
  | grep -m1 ' BUILT_PRODUCTS_DIR' | sed 's/.*= //')/MonkSynth.app/Info.plist" \
  | grep -iE 'UsageDescription'
```

Then **actually tap the feature on a device**. This is the class of bug the
250-test suite and the bit-exact parity gate say nothing whatsoever about.

## One-time setup

- **App IDs** `com.vestal.monksynth` and `com.vestal.monksynth.AU` — created
  automatically by the first `xcodebuild archive -allowProvisioningUpdates`.
- **App Store Connect record** for `com.vestal.monksynth` — must be created by
  hand at appstoreconnect.apple.com. The build cannot create it, and without it
  export fails with `Error Downloading App Information` /
  `missingApp(bundleId:)`.
- **`scripts/.deploy.local`** (gitignored) holding `ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `DEVELOPMENT_TEAM`. The key must be **Admin** role — an App
  Manager key fails with "No signing certificate iOS Distribution".

## Store copy

**Never use "Delay Lama" in the app name, subtitle, or keywords.** The artwork
and the product name belong to AudioNerdz. The single factual "inspired by the
classic Delay Lama VST plug-in by AudioNerdz (2002)" line lives in the about
screen and may also appear in the long description. `LocalizationTests` enforces
that it appears exactly once.

**Credit Jonathan Taylor in the description.** MonkSynth is his MIT-licensed
project and this is a port, not an original work. The MIT notice ships in the
about screen; the description should say so too.

## What ships

- `MonkSynth.app` — standalone instrument, iOS 16+, universal (iPhone + iPad)
- `MonkSynthAU.appex` — the AUv3 instrument (`aumu` / `Mnks` / `Vstl`),
  embedded in the app; installing the app registers the plug-in
- Localized en / ja / ko
