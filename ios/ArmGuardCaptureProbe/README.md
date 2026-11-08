# ArmGuard native practice coach and capture test

The existing Xcode project now has two tabs. **Capture test** preserves the original
RGB/LiDAR hardware milestone. **Practice coach** adds routine checks, Apple hand
tracking, optional custom fingertips/protected-part detection, label OCR, BLE,
a continuous Cartesia voice conversation and a phone-voice fallback. No printed markers are needed.
The app is foreground-only and practice-only. No trained model, prescription or
clinic protocol is bundled. No video is recorded or uploaded.

The iOS sources are syntax-checked here, but have not been compiled against an
iOS SDK: this workspace only has Command Line Tools. Portable logic tests and
mocked gateway tests passed; they do not validate native APIs, UI or hardware.

## Open and install

1. Install **full Xcode**, launch it and finish its initial setup/iOS platform
   downloads. The selected Xcode must support the iOS version on the phone.
   Command Line Tools alone are insufficient. No third-party dependencies,
   Record3D purchase or paid Apple Developer membership are required for a local
   development install.
2. Open **ArmGuardCaptureProbe.xcodeproj** in this directory. Use the shared
   **ArmGuardCaptureProbe** scheme.
3. In Xcode > Settings > Accounts, sign in with an Apple Account locally. Select
   the app target > Signing & Capabilities, keep **Automatically manage signing**
   enabled and choose your Personal Team (or existing development team). If the
   default bundle identifier is unavailable, change `org.armguard.captureprobe`
   to a unique identifier under your name/team. No credentials belong in Git.
4. Plug the **iPhone 15 Pro** into the Mac, unlock it and accept Trust/Pair prompts.
   Enable **Settings > Privacy & Security > Developer Mode** if prompted, then
   restart/confirm on the phone. Select the physical phone as the run destination.
5. Press **Run** (Command-R), allow Camera access, open **Capture test**, then tap **Start camera**.
   The app checks actual rear scene-depth support. A standard iPhone 16 is an
   expected unsupported-device case for this rear-LiDAR test; no simulated depth
   or automatic front-camera fallback is used.
6. After confirming the app works, unplug the cable and repeat. It runs on the
   phone without a computer/network connection. A free Personal Team profile
   expires after seven days; rebuild/reinstall from Xcode after expiration.

Apple documents [free local signing](https://developer.apple.com/help/account/basics/about-your-developer-account)
and [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
Keep signing certificates, provisioning profiles and account authentication local.

## Capture test: what to look for

- **Camera** pane: live RGB image with a center crosshair.
- **LiDAR depth** pane: a color map of medium/high-confidence depth. Near is red,
  far is blue, invalid is black, and unknown/low confidence is gray. The fixed
  visualization range is 0.15–2 m; values outside it clip in color, not in the
  numeric center reading.
- **Center depth**: median of usable values in a small center patch, expressed in
  centimeters from the camera (camera-space Z). It is not a finger-to-connector
  gap, physical-contact measurement, or promise of centimeter accuracy. The
  crosshair indicates patch center, not every pixel included in the median.
- **Diagnostics**: delivered frame counts/rates, source resolutions, confidence
  coverage, tracking status and preview-conversion duration. Preview refresh is
  capped at 10 fps. Depth-bearing frame rate counts AR frames with depth; it is
  not an independent measurement of the LiDAR sensor's scan rate.
- **Share diagnostics** opens the system share sheet with text only. The Capture
  test tab needs only camera permission. Practice coach separately requests
  Bluetooth on Connect and microphone/speech on voice input; local network access
  is needed only when using a local development voice gateway. The coach saves
  event metadata locally, without images, recordings or free-text responses.

## Capture test: first phone test

| Action | Expected result |
| --- | --- |
| Launch, allow Camera, press Start | Rear LiDAR supported; both panes become live; camera/depth frame counts increase |
| Point at a matte book/table at about 40–80 cm | Depth pane shows the surface and a usable center reading when confidence permits |
| Move phone nearer/farther from the surface | Center depth changes in the expected direction; compare with a ruler as a basic plausibility check |
| Move a hand across the image center | Corresponding foreground shape appears nearer in depth; center changes when the hand covers enough of the sample patch |
| Move a hand left/right across both panes | Both previews have matching portrait orientation; their fields of view may differ, and this is not a calibrated overlay test |
| Point at an edge or material with poor depth | Low/unknown values are visibly gray/black; unusable center shows Unavailable, not zero |
| Press Stop | Status says stopped; panes are visibly marked paused/stale; live numeric reading is unavailable |
| Background the app or lock the phone | Capture pauses; return and press Start to resume; old readings do not appear live |
| Deny Camera permission | App explains the problem and provides Open app settings |
| Run on standard iPhone 16 / simulator | App reports rear LiDAR unavailable; does not claim capture success |
| Disconnect the development cable | Capture continues independently on the phone |

Run for several minutes and note camera/depth rates and temperature. Hardware
success means RGB and depth are actually delivered, update with the scene, and
stop/recover correctly. It does not validate tiny-gap accuracy, contamination
detection, hand tracking or a latency target.

If capture stalls, the status marks it stale after 0.75 s. Old images are dimmed
and center depth is withheld. Preview conversion has a separate freshness check;
a healthy capture callback alone cannot make an old displayed result look live.
An interruption/error requires pressing Start again.

## Implementation and checks

For this narrow milestone, **ARKit sceneDepth** is simpler than wiring separate
AVFoundation outputs: a single `ARFrame` contains RGB and scene depth. The app uses
`sceneDepth`, not `smoothedSceneDepth`. The Capture test tab performs no model
inference, mesh reconstruction, networking or recording. Practice coach adds a
separate Vision worker to the same capture-controller implementation. ARKit depth is processed/fused data, not raw
LiDAR returns. See Apple's [scene-depth sample](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth).
The eventual application can keep ARKit or compare direct AVFoundation capture;
the earlier design's choice is not a prerequisite for this hardware test.

The AR session delegate does minimal bookkeeping. A separate worker renders at
most one frame at a time and drops incoming work while busy; no preview backlog
is built. RGB and depth are from the same AR frame. Portrait is fixed for this
test, and images are shown aspect-fit without applying independent crops.
Resolutions differ; registration and lens/distortion checks still belong to the
later geometry milestone. Receipt freshness and conversion duration do not
measure full sensor-to-screen latency.

The Xcode app target compiles the portable `DepthAnalysis`, `RoutineEngine` and
`ProximityEngine` source files directly. A small Swift package checks that same code without XCTest or an iOS SDK:

```sh
swift run --package-path ios/ArmGuardCaptureProbe/Core CaptureProbeChecks
```

Run that from the repository root. It tests row-stride handling, invalid depth,
confidence gating, center-patch selection, color classification, stale times,
routine transitions/read-backs/review flags, projected overlap and BLE encoding.
It cannot validate ARKit, UI rendering, signing or sensor behavior.

With full Xcode selected, an unsigned iOS compilation check is:

```sh
bash scripts/build-ios-probe.sh
```

This produces a device-target compile check, not an installable signed IPA. Use
the signing/Run steps above for the actual phone test. Simulator builds cannot
verify rear LiDAR. Build output is under the repository's ignored `build/` folder.

## Practice coach: test without a model or Cartesia

1. Open the gear menu and choose **Try phone voice**. It starts the practice and
   camera together. Allow camera, microphone and on-device speech permissions.
   Say done to report an action. Ask “Why is this needed?”: the explanation must
   leave the check open. Say pause, resume, or repeat without touching the screen.
2. Bag details and protected-opening read-backs need a separate confirmation.
   A bare yes cannot supply missing bag details. Say the details, compare them
   with your written instructions, then say they match. No supplied fluid values
   are clinically validated. Phone recognition needs on-device English support;
   **Type instead** is available as an accessibility fallback.
3. The bundled RF-DETR model detects hands and protected connector tips. Apple Vision supplies fingertips. Monitoring requires a fresh clear view, usable depth and both hands fully tracked. Say
   **continue without camera** to advance this practice explicitly unmonitored,
   or **finish setup** to stop after preparation. Neither records a clean exchange.
4. Say **read the label** with a mock label in view. Inspect the text yourself;
   it does not choose fluid strength, compare a prescription or complete a check.
5. Say **end session**, then start another practice through **New practice**.
   Backgrounding/locking pauses capture and voice; **Resume voice** is required
   on return. Monitoring never restarts automatically. Review flags stay latched.
6. Connect the wristband through setup before hand preparation. Choose the
   installed firmware and test a vibration. Variable intensity needs the updated
   sketch. Do not change firmware while monitoring.

The camera/depth hardware test and diagnostics are under the gear menu's
**Developer tools**. The four exchange labels are practice placeholders, not a
recommended daily schedule. The routine needs care-team review before real use.
See [DESIGN.md](../../DESIGN.md) for research and remaining detector limitations.

## Bundled protected-part model

`SterileParts.mlpackage` now contains the teammate's RF-DETR Small export (512 px,
300 queries, approximately 55 MB of weights), already registered in the Xcode
Sources phase. Xcode produces `SterileParts.mlmodelc`. Class 0 is the reserved
placeholder, class 1 is `Hand`, and class 2 is `Sterile_connector_tip`. Explicit
metadata identifies raw logits, normalized cxcywh boxes, output names, background
slot and app roles. Learned weights are unchanged by this integration.

The app applies sigmoid unconditionally to RF-DETR logits, excludes the reserved
slot, and reads outputs by name. It rejects unsupported tensor shapes/types and
nonfinite values. Whole-hand boxes are displayed; Apple Vision provides fingertip
coverage for proximity. The model contains no cap-interior or clothing/floor class.

The separate image-scale method has no default millimetre calibration and does
not drive the wristband. Current alerts use registered depth and the existing
experimental proximity gate. Camera arming requires a fresh clear observation,
protected surfaces, usable depth and both hands with all five confident Apple tips
each. Image overlap requests review; it cannot prove physical contact. Pause,
backgrounding, stale data and review flags do not allow a second alert loop to
restart the band.

Check boxes and fingertips against real mock props in portrait orientation. Test
approach/retreat, hovering, occlusion, loss, heat and frame age. The Mac model
smoke check verifies loading, input rotation/RGB/normalization and actual inference;
it does not establish real-photo accuracy or iPhone warning latency:

```sh
mkdir -p build/model-review
xcrun swiftc -swift-version 5 ios/ArmGuardCaptureProbe/Core/Sources/CaptureProbeCore/*.swift \
  ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/RFDETRDetector.swift \
  scripts/check-rfdetr-model.swift -o build/model-review/check-model
build/model-review/check-model
```

For a replacement export, supply the actual training class IDs and background slot;
do not infer them by alphabetically sorting project names. For this exact project:

```sh
python3 scripts/export_rfdetr_coreml.py --weights /path/to/weights.pt \
  --classes 'Hand,Sterile_connector_tip' --background-class-id 0 --image /path/to/photo.jpg
```

A training COCO annotations file or explicit index-to-name JSON can instead be
passed with `--class-map`. Any exported replacement needs photo parity and phone
bench tests before use. A Vision/NMS image-input model remains supported, using
exact protected-opening labels or explicit role metadata.

## Enable conversational Cartesia voice without a laptop

After installing, open the gear menu and enter the authorized **Cartesia API key**.
The voice and existing agent IDs are prefilled; they can be changed under Advanced
voice settings. Enable **Allow Cartesia voice conversation**, close setup and tap
**Start practice**. The key is saved in the device Keychain, never built into the
app or checked into Git. This is a personal prototype configuration: each test
phone gets its key through setup. There is no server address to enter and no Mac
process to keep running. The phone needs internet for Cartesia.

Questions, interruptions and check replies use one conversation. Native tools
control transitions and require actual unused user replies. Fixed warning clips
are fetched directly from Cartesia in advance and kept in memory. Phone speech
handles immediate alerts when a clip is unavailable. Camera/depth, model inference
and band commands remain on the phone. Backgrounding pauses the foreground app;
resuming monitoring still requires fresh observations.

A hosted gateway remains optional under Advanced voice settings for later shared
app distribution. See [gateway setup](../../services/voice_gateway/README.md). A
public release should use a hosted credential service rather than distributing a
shared long-lived API key with the app. The prototype does not embed that key.

Live account tests passed for the selected voice, streaming and a synthetic reply
through both tools. Direct native requests are included in the optional model smoke
check's `--direct-voice` mode (environment credentials, small paid API calls).
Phone microphone/playback, naturalness, interruptions, echo suppression and motor
latency still need physical-phone testing. Review cloud retention before patient data.

## Repeatable checks before installing

From the repository root, run:

```sh
bash scripts/check-ios-app.sh
```

This checks Xcode source membership, resource copying, the shared scheme and
permission declarations; rejects copying a reserved Resources folder into the
flat iPhone bundle; runs the Swift logic and mocked gateway tests; parses
all app Swift sources; then uses the strongest available native check. With a
selected full Xcode/iOS SDK it builds the actual iPhone app **without signing**,
then validates the built bundle's resource layout.
With Command Line Tools and Catalyst frameworks it instead type-checks the real
app sources against those Apple frameworks. That fallback cannot verify iPhone
linking, packaging, signing, iPhone-only API differences or hardware behavior.
The first compiler-cache build needs free disk space and can take several minutes.

To require the complete iPhone build and fail if the iOS SDK is missing:

```sh
bash scripts/check-ios-app.sh --require-ios-build
```

`.github/workflows/ios-checks.yml` runs the required iPhone build on a GitHub macOS
runner for relevant pushes/PRs, and can be run manually. This workflow is only
configured here; no remote CI run has been triggered or verified. It needs no
phone, developer-team secrets or Cartesia key. Building catches compiler errors
before phone installation; it does not prove camera, BLE, audio or model accuracy.

Keep your Xcode signing-team and unique bundle-ID changes when updating source.
The repository's generic project starts without a personal team. Replacing a
locally configured project file with that template can reset the selection. A
CodeSign failure is a separate installation/signing problem: inspect the failed
build's expanded CodeSign log for the underlying error instead of assuming every
failure is a missing team. The unsigned check deliberately leaves those personal
settings alone and does not install or publish anything.

### CodeSign mentions `embedded.mobileprovision`

If signing reports `code object is not signed at all` for
`embedded.mobileprovision`, inspect the built app's layout as well as signing
settings. This project previously copied a whole folder named `Resources` into
the app root, which can confuse bundle classification. The project now copies
`RoutineTemplate.json` individually to the root. The source folder can remain
named Resources; the build must not copy that folder wholesale. This follows
[Apple's resource placement rules](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).

On an existing checkout, preserve your selected development team and bundle ID,
apply the resource-reference change, then use **Product > Clean Build Folder**
(Shift-Command-K) and build/run again. Cleaning removes the old copied folder.
If applying the change manually in Xcode, remove the Resources folder entry from
**Build Phases > Copy Bundle Resources** and add only `RoutineTemplate.json`.
Keep the actual JSON file on disk. No manual signing of the embedded provisioning
profile or certificate deletion is part of this fix.

Local validation now includes a full 13-source Catalyst type-check with real Apple
frameworks (not an iPhone build). A synthetic flat-bundle ad-hoc signing experiment
also succeeded after removing the copied Resources directory; the invalid layout
failed. Actual development signing and phone installation still need the Xcode
Mac and its selected team/profile.
