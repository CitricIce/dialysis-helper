# ArmGuard Capture Probe

First hardware milestone: install our own native app on the phone, display the
camera image and receive actual rear LiDAR scene depth. **No printed markers are
needed.** Use a book, tabletop and your hand. This test does not yet track hands,
detect connectors, judge contact, connect to a band or record video.

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
5. Press **Run** (Command-R), allow Camera access, then tap **Start camera**.
   The app checks actual rear scene-depth support. A standard iPhone 16 is an
   expected unsupported-device case for this rear-LiDAR test; no simulated depth
   or automatic front-camera fallback is used.
6. After confirming the app works, unplug the cable and repeat. It runs on the
   phone without a computer/network connection. A free Personal Team profile
   expires after seven days; rebuild/reinstall from Xcode after expiration.

Apple documents [free local signing](https://developer.apple.com/help/account/basics/about-your-developer-account)
and [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
Keep signing certificates, provisioning profiles and account authentication local.

## What to look for

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
- **Share diagnostics** opens the system share sheet with text only. Nothing is
  saved or uploaded automatically. Camera is the only privacy permission needed;
  this build does not request Bluetooth, microphone, Photos or local-network access.

## First phone test

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
`sceneDepth`, not `smoothedSceneDepth`, and never adds mesh reconstruction, model
inference, networking or recording. ARKit depth is processed/fused data, not raw
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

The Xcode app target compiles `Core/Sources/CaptureProbeCore/DepthAnalysis.swift`
directly. A small Swift package checks that same code without XCTest or an iOS SDK:

```sh
swift run --package-path ios/ArmGuardCaptureProbe/Core CaptureProbeChecks
```

Run that from the repository root. It tests row-stride handling, invalid depth,
confidence gating, center-patch selection, color classification and stale times.
It cannot validate ARKit, UI rendering, signing or sensor behavior.

With full Xcode selected, an unsigned iOS compilation check is:

```sh
bash scripts/build-ios-probe.sh
```

This produces a device-target compile check, not an installable signed IPA. Use
the signing/Run steps above for the actual phone test. Simulator builds cannot
verify rear LiDAR. Build output is under the repository's ignored `build/` folder.
