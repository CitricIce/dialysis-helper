# ArmGuard native practice coach and capture test

The existing Xcode project now has two tabs. **Capture test** preserves the original
RGB/LiDAR hardware milestone. **Practice coach** adds routine checks, Apple hand
tracking, optional custom fingertips/protected-part detection, label OCR, BLE,
local speech and optional dynamic Cartesia Q&A. No printed markers are needed.
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

1. Select a practice slot and **Start practice**. Try a bare yes: it must leave the
   check open. Describe an action: it is recorded as a self-report. Try asking
   “Why is this needed?”: the check must stay open. Explain and Repeat work locally.
2. Supplies and protected-surface read-backs need a separate confirmation. No
   supplied fluid values are clinically checked. Listen requires on-device English
   recognition support; otherwise use typed responses. Voice commands are exact
   phrases such as pause, help, repeat, confirm, ask a question and start monitoring.
   Configure cloud voice and enable prompt listening before hand preparation to
   enter Q&A by voice without touching the phone at each check.
3. Start camera with both hands visible. Cyan points show fingertips. Diagnostics
   show the provider, model status and pipeline time. Without `SterileParts`, the
   app explicitly reports unavailable proximity and cannot arm monitoring.
4. Put a mock label in view and tap **Read visible label text** while checking.
   Inspect the OCR yourself. It cannot choose strength, compare a prescription,
   verify packaging/fluid quality or complete the check.
5. At the connection check, choose **Finish preparation practice only** while the
   model is absent. It must not report a monitored/clean exchange. Use New practice
   to start another test; previous event logs remain on the phone.
6. Test Pause, app background/lock and tab switching. Camera/voice pause; band
   intensity expires/off is sent. Resume never automatically restores monitoring.
7. Flash the updated ESP32 sketch, choose the matching firmware mode, Connect and
   Test pulse. Compare fixed patterns vs PWM v2 on the actual band. Never change
   firmware mode while armed. No band is needed for preparation practice.

The four exchange labels are placeholders, not a recommended four-exchange daily
schedule. The bundled check order needs PD-team review before any real-exchange
use. Source and research decisions are in [DESIGN.md](../../DESIGN.md).

## Add the trained protected-part model

Export a Vision-compatible detector with NMS, named **SterileParts**, and add its
`.mlpackage`/`.mlmodel` to the app target's Sources build phase in Xcode. The build
must produce `SterileParts.mlmodelc` in the bundle. Required exact class names:
`sterile_tip`, `cap_interior`, `connector_opening`. Label exposed openings, not
entire connector bodies. Optional fingertip labels: `fingertip`, `thumb_tip`,
`index_tip`, `middle_tip`, `ring_tip`, `little_tip`. Whole-hand boxes are ignored
for fine geometry; Apple tips fill custom coverage gaps.

On device, verify boxes against known props and portrait orientation. Start with
a matte, dry bench and disconnected mock connectors. For arming, the latest
observation must be under 250 ms old, have a loaded model, protected surfaces,
usably registered depth, both hands with all five confident Apple tips each, and
no current proximity flag. This strict gate may need ergonomic revision after
measurement; it must not be relaxed into silently accepting an unobserved hand.

Test a known approach/retreat, hovering above a cap, occlusion, lost hands, model
failure, camera interruption and CPU/thermal load. A projected overlap flags
review; it does not claim physical contact. Review remains latched across pause
and resume. No real mating-pair exceptions or body/clothing/floor detectors are
implemented. Thresholds are experimental, and a model file existing does not
establish accuracy. Measure warning latency at the physical motor.

## Enable dynamic questions

Follow [voice gateway setup](../../services/voice_gateway/README.md). Enter its
base URL and separate gateway token in the app's Cartesia connection fields.
These fields stay in memory. Enable cloud questions, then tap **Ask a question**
while checking/paused. Streaming microphone audio goes to Cartesia; camera images
stay on the phone. End Q&A before answering or confirming the app check. No agent
text can complete a check. Account-specific session/audio retention must be
reviewed before using patient information.

Optional Cartesia routine speech is a separate switch. Built-in speech works
without it, and urgent proximity/loss warnings always use local speech. Test loss
of the gateway/network: Explain stays available and routine state stays unchanged.
Managed-Agent access, voice ID, live audio round trips, barge-in/echo behavior and
account credits have not been verified in this workspace.
