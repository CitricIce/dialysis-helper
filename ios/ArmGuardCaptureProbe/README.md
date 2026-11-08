# Sterling iPhone app

**Public brand:** Sterling · **Slogan:** keep it clean

**Description:** Your at-home dialysis companion, with voice guidance, camera support and wristband feedback.

**Mission:** Help people stay safely on home peritoneal dialysis by reducing hygiene-related infections and avoidable transitions to hemodialysis. This is the mission, not a demonstrated outcome. Longer term, extend that support to other home medical procedures.

Logo concept: [silver-ring wordmark](../../assets/branding/sterling-logo-v1.png).

## Current warning smoothing and timed demo (November 8, 2026)

- **Wider default zones:** HIGH within **15 mm**, MEDIUM within **40 mm** (previously
  10/30). The existing 5 mm release margin remains. An installed previous-default
  pair migrates once; other custom settings are preserved. Reset uses 15/40.
- **Audio without a wristband:** regular and demo voice warnings have no BLE-connected
  gate. The band is optional throughout setup and practice; it only adds vibration.
  UI copy and agent instructions must not treat a missing band as a problem. Cached Cartesia clips are used when available, with immediate local phone
  speech otherwise. The camera/model-only test intentionally has no audio/BLE client;
  use the main routine/Live Guard to test real cues. Developer tools also offer
  **Play medium-risk test warning** and **Play high-risk test warning** speaker tests
  that need neither a model detection nor a wristband.
- **Smoother output:** decreasing distance or scale takes effect immediately, while
  increasing clearance is smoothed and warning release uses hysteresis. An already
  detected hazard may survive a missed measurement for at most 200 ms; a missing
  initial detection or missing clear reading is never replaced with a fabricated
  gap. The held estimate keeps its original source timestamp. Audio, visual risk
  and band routing still reject distance data older than **250 ms including inference
  time**. Strict depth-monitoring uses the current raw frame, not retained regions.
- **Voice confirmation across model gaps:** a short interval with no usable estimate
  no longer restarts the pending 0.3-second warning confirmation on every frame.
  A cue can only fire on an available fresh estimate. After a loss longer than one
  second it needs fresh confirmation again. Existing HIGH repeats and escalation
  rules remain, so the assistant does not continuously repeat the same short warning.
  Smoothing reduces flicker; it cannot make missed or wrong detections reliable.
- **Settings → Demo mode:** off by default and saved on the phone. On each connection
  and disconnection step, saying **ready** starts an 8-second countdown. One scheduled
  **“High risk. Hands back.”** cue then plays, independently of model results and
  network TTS generation. If the band is connected, the matching HIGH command is
  refreshed for about **2 seconds** (legacy E or intensity-v2 [2,255]); otherwise the
  Bluetooth send is skipped. No wristband is required and no routine step waits for
  one. Demo ready also bypasses the detector-dependent strict-arming gate, entering
  explicitly unmonitored practice rather than falsely arming real monitoring.
- **Pause/disable/exit:** pause freezes a countdown and stops an active demo vibration;
  done, leaving the step, ending the routine or disabling Demo mode cancels its output.
  Each active connection/disconnection step fires once. A visible demo badge and
  **DEMO · HIGH RISK** banner distinguish the scheduled cue. Real detections, distance
  estimates and statistics are unchanged; scheduled warnings are not recorded as
  camera-detected hazards. The existing BLE expiry still applies. The simulation
  bypasses detection, not the need for working phone audio or a connected powered band
  when vibration is desired. The ordinary speaker-only test buttons send no BLE.

Validation: **62 portable checks, 16 gateway/setup tests, Xcode project validation,
and all 22 Swift sources type-checked with Apple Mac Catalyst frameworks**. New
checks cover zone migration, band-free cues across inference gaps, immediate
approach/gradual release, bounded held timestamps, timed demo once per step,
pause/cancellation, and detector-independent demo entry. Full Xcode/iPhone build,
physical speaker/vibration timing and accuracy on real props are not verified here.
Use demo props to distinguish deterministic output testing from detector testing.

## Current voice playback and routine warnings (November 8, 2026)

The user reported sound stopping after the first spoken reply while text continued,
and missing cues in the connection screen. These reports are not physically
reproduced on this Mac. Code review found missing audio-engine recovery, separate
debug/routine confidence settings, misleading “warnings off” prompts, and a BLE
firmware selection that did not persist. The following changes address those gaps:

- **Audio:** `CartesiaConversation` rebuilds its input converter and player connection
  after stopped-engine/configuration/route changes, observes interruptions and media
  service resets, and defaults a built-in receiver route back to the speaker while
  preserving selected headphones. Normal recovery keeps the same WebSocket, agent
  conversation and native routine state. Cleared/stopped playback invalidates old
  completion callbacks before they can consume a later reply's queue.
- **Failure handling:** bounded recovery (two attempts within 15 seconds), a stalled
  playback watchdog, a 3-second microphone-delivery check and an 8-second
  text-without-audio check prevent indefinitely
  silent connected calls. Interrupted/cancelled/empty turns and a new user turn do
  not trigger the missing-audio check. If recovery/streaming fails, the existing
  phone-voice fallback announces the problem and continues listening. If iOS denies
  audio resumption or local audio cannot start, the routine pauses instead of
  pretending it is speaking. Permissions/other apps/system audio focus can still
  require user action; normal routine steps do not require screen interaction.
- **Native fallback:** local audio configuration failures are surfaced, failed clip
  playback falls back to phone speech, and a late completion from an old synthesized
  utterance cannot restart listening during a newer reply. Unexpected cancellation
  of the current phone utterance is surfaced instead of leaving listening stuck.
- **Hands-free progress:** ordinary spoken “next step” works without Developer mode
  and records unverified practice progression. Pause keeps a working Cartesia call
  listening for “resume”. Ready/done still control connection/disconnection practice;
  contact-review and deliberate strict-depth arming rules are unchanged. Repeated
  native cues retain the pending automatic return to Cartesia.
- **Warning behavior:** image-scale MEDIUM/HIGH cues were not removed by the UI
  redesign. They remain independent of strict depth-monitoring and rehearsal phase.
  Fresh usable estimates (source age at most 250 ms) drive the main banner and BLE;
  missing initial measurements or stale analysis produce no distance command;
  brief retention of a previous hazard is described above. Default
  zones are now HIGH 15 mm and MEDIUM 40 mm with existing hysteresis. Voice names the
  level: **“Medium risk. Move back.” / “High risk. Hands back.”** Existing 0.3-second
  voice dwell, escalation-only cues and 8-second sustained-HIGH repeat remain.
- **Accurate prompts:** the template, native fallback wording, agent instructions and
  optional gateway now distinguish experimental image-scale cues from stricter depth
  monitoring. They no longer claim camera warnings are switched off in rehearsal.
  Native state exposes actual warning availability/level and band connectivity to
  the agent. A low-accuracy model still cannot verify sterility or physical contact.
- **Debug/routine parity:** the confidence selected in the model test is saved and
  reused by the routine's experimental preview (default 45%). It no longer silently
  resets to another threshold. Deliberate strict experimental monitoring retains its
  fixed default threshold. The main camera status says whether the tip, hand or a
  sufficiently recent analysis is missing; model test shows the image-scale gap too.
  It remains a camera-only test with no voice or Bluetooth client.
- **Wristband:** selected firmware persists. Starting/resuming a routine reconnects
  a previously authorized band, and lost connections retry at most once every ten
  seconds during voice-enabled practice. No new permission dialog is launched by
  this automatic reconnect. Explicit disconnect stops retries. HIGH submits E in
  legacy mode or [2,255] in v2; MEDIUM submits W or [1,200]. Expired commands still
  stop after 250 ms; reconnect never replays an old hazard.
- **Diagnostics:** Settings → Developer mode → Developer tools → Voice audio
  diagnostics distinguishes packets received, buffers completed, queue length,
  engine/player state, clears, recoveries, output route and output volume. Shared
  diagnostics include detection confidence/frame age and BLE writes submitted/last
  command/protocol. A completed buffer is not proof of audible sound, and a submitted
  BLE write has no motor acknowledgement. No audio bytes, keys or transcripts are
  included in these diagnostic counters.

Validation at that update (superseded by the smoothing/demo checks above): **55 portable checks, 16 gateway/setup tests, project validation and
all 21 Swift sources type-checked against Apple Mac Catalyst frameworks**. This is
not an iPhone SDK build or a physical reproduction. On iPhone 15 Pro, test several
spoken replies, pause/resume, a near approach during connection and disconnection,
route/interruption recovery, and actual band vibration. If a failure persists,
share the audio/BLE diagnostics captured immediately after it; do not lower the
freshness requirement to make old camera frames generate cues.

## Current Sterling interface (November 8, 2026)

The three supplied sketches (`IMG_2638`, `IMG_2637`, `IMG_2636`) and
`dialysis-routine-demo.html` inform the current native SwiftUI interface: a routine
list, editable session cards, daily practice progress, and voice-led checks with
camera support during connection/disconnection. Example treatment strengths,
volumes, dwell times and clinical advice from the HTML were not adopted.

- **My routines:** four defaults, Exchange 1–4, appear on first launch. Each can be
  renamed, edited or deleted; **Add routine** creates another. Deleting all routines
  leaves the plan empty, including after relaunch. Names, optional personal times,
  notes and opt-in daily reminders persist on the phone. Times start unset so the
  app does not invent a prescribed schedule. Timed cards sort before untimed cards.
- **Edit routine → What to say at each check:** expand any of the ten checks to see
  its actual prompt and example spoken responses. The bag examples explain reading
  real label details over multiple replies, adding just a missing detail, correcting
  the read-back, and confirming against the user's own instructions. Examples use
  bracketed spaces rather than sample prescriptions. `exampleResponses` lives beside
  each check in `Resources/RoutineTemplate.json`; edit it with the prompts and rebuild.
- Every routine currently runs the **same practice template**. Editor notes and
  reminder times are personal planning metadata, not agent instructions, checked
  prescriptions, individualized treatment flows or adherence records.
- **During practice:** large step title, progress, the current spoken response and
  reply guidance. Existing pause/resume/next-step voice commands remain available;
  typing and on-screen controls are optional fallbacks. Camera preview and overlays
  appear at connection/disconnection. Opening the full-screen camera no longer uses
  the root view's disappearance as a reason to pause voice; actual app backgrounding
  still pauses it. No new mandatory tap was added to progression.
- **Developer mode:** gear → Settings → Developer mode (off by default, persisted).
  Enables home tiles for Live Guard, camera/model testing without voice, LiDAR testing
  and connector/zone controls. Live Guard's model panel, confidence slider, raw frame
  diagnostics, measurement summaries and routine debug controls are retained behind
  this switch. Voice setup and wristband connection/test remain available normally.
- **Brand:** silver ring mark in the home header and active routine toolbar, full
  Sterling wordmark in the native launch screen, slogan **keep it clean**. Standalone
  transparent vector: `assets/branding/sterling-ring.svg`. SwiftUI draws a native
  vector companion; the full PNG is bundled in `BrandAssets.xcassets`. Signing team,
  bundle identifier and legacy technical filenames are preserved.
- **Progress and reminders:** only the routine engine's completed phase marks a
  practice finished today; ending, pausing or preparation-only exit does not. Counts
  roll over at local midnight. This includes unverified practice progression, so the
  count is not treatment adherence or a cleanliness score. Reminder edits/deletions
  replace/cancel only Sterling's pending notifications. Delivery depends on iPhone
  notification permission and system settings; reminders do not run treatment steps.
- **Camera limits:** the low-accuracy placeholder remains. The teammate's existing
  image-scale distance cues and BLE/audio feedback are preserved when fresh estimates
  exist, including outside explicitly armed monitoring. Placeholder routine steps
  still progress as unmonitored rehearsal. No visual sterility/contact verification
  or infection reduction is claimed; the LLM receives derived observations, not images.
- **Verification:** 49 portable checks and 16 gateway/setup tests pass; project
  membership, reply-example coverage and launch asset references pass. All 20 Swift
  sources type-check against actual Apple Mac Catalyst frameworks. An iPhone SDK
  build, launch-screen layout, Dynamic Type/VoiceOver, notification delivery, and the
  combined camera/voice/band flow on iPhone 15 Pro still require full Xcode/the phone.
  This UI-only validation was superseded by the audio/warning verification above;
  other earlier validation counts describe their respective historical changes.

## Earlier short spoken warnings (policy retained; wording superseded above)

The old cues took 4–5 seconds to say but repeated every 4 seconds and cut each other off,
so a hand near a boundary produced a stream of half-sentences. Now the **band and screen
alert continuously** and the **voice only marks the danger getting worse**
(`WarningCuePolicy` in `ProximityEngine.swift`, cues in `CoachSpeech.swift`):

| | Before | Now |
|---|---|---|
| MEDIUM cue | "Medium risk. Your fingers are getting close to the sterile tip. Slow down and keep a gap." | **"Careful, too close."** |
| HIGH cue | "High risk. Stop. Move your fingers away from the sterile tip now." | **"Stop. Hands back."** |
| When it speaks | On any rise, and HIGH every 4 s | Once when the level rises and holds **0.3 s** (flickers stay quiet) |
| HIGH while it lasts | Repeated every 4 s | Repeated every **8 s** |
| HIGH back to MEDIUM | Could speak | **Silent** |
| New episode | Immediately after any clear frame | Only after the hand has been clear for **1 s** |

- Band patterns, banners, phone haptics and the red border are unchanged.
- The cues are still pre-recorded with Cartesia Sonic when voice is configured (keyed by
  text, so the new lines are recorded automatically) and fall back to the built-in voice.
- Fewer cues also means fewer interruptions of an active Cartesia conversation.
- The LiDAR monitoring cue (experimental mode only) uses the same short MEDIUM line.
- Earlier sections quoting the long cues or the 4 s repeat are superseded by this one.
- **Verified:** 45 portable checks (new check: dwell, flicker, drop, 8 s repeat, clear
  reset, reset), 16 gateway tests, project membership, and all app sources type-checked
  against Mac Catalyst frameworks. **Not verified:** iPhone SDK build and how the cues
  sound and feel during a real practice.

## Smaller, editable warning zones: HIGH 10 mm, MEDIUM 30 mm (November 8)

The red high-risk circle was far too big. **The old high-risk distance is now the
medium-risk distance**, and both are editable in the app (`WarningDistances` in
`ProximityEngine.swift`, the Connectors sheet in `LiveGuardView.swift`):

| Level | Was | Now (default) | Feedback (unchanged) |
|---|---|---|---|
| HIGH RISK | within 30 mm | **within 10 mm** | red banner, continuous band, repeated voice cue |
| MEDIUM RISK | within 80 mm | **within 30 mm** | orange banner, pulsing band, short voice cue (see above) |

- **Where to change them:** enable **Developer mode** in Settings, then use the home
  **Connectors** tile, the ruler chip in Live Guard, or Settings → Connector tips →
  **Warning zones**. Each level has a
  − / + stepper in 5 mm steps. **Reset to 10 mm and 30 mm** appears once either differs.
- **Rules:** HIGH is 5–145 mm. MEDIUM always stays at least 5 mm outside HIGH (raising
  HIGH pushes MEDIUM out), up to 150 mm. The 5 mm release margin (hysteresis) is unchanged.
- Values are saved on the phone (`UserDefaults`, keys `warningDistanceMM.high` /
  `warningDistanceMM.medium`). The vision pipeline applies them to the risk tracker on
  every frame, so changes take effect immediately in the warnings, the drawn circles,
  the gauge (scale now 0 to twice the MEDIUM distance, at least 60 mm), the safety
  summary and the shared care-team text.
- **Connector tip sizes are unchanged:** blue 8 mm, clear 13 mm, fixed.
- **Bundled model:** `SterileParts.mlpackage` was replaced with newly trained RF-DETR
  Small weights (512 px, same class IDs: 0 placeholder, 1 `Hand`, 2
  `Sterile_connector_tip`). `detectorStatus` is still `placeholder`.
- Earlier sections that describe 30 mm / 80 mm zones are superseded by this one.
- **Verified:** 44 portable checks (hysteresis check updated for 10/30 mm; new check for
  defaults, editing, overlap rules, caps and reset), 16 gateway tests, project
  membership, and all app sources type-checked against Mac Catalyst frameworks.
  **Not verified:** iPhone SDK build, the steppers on a phone, and zone size against a ruler.

## Detection tools retained in Developer mode (November 8)

The Roboflow model code (`RFDETRDetector.swift`, pipeline detection) remains in place.
Enable Settings → Developer mode to access the team's technical controls:

- **Detection labels:** Live Guard and the practice camera preview draw every RF-DETR
  detection again, with class name and confidence (orange tip, green hand, gray other).
  These sit on top of the zones, tip-type labels and gap line.
- **Model panel in Live Guard:** a "Roboflow RF-DETR · N tip · N hand · N fingertips"
  strip with a live/stale dot. Tap it for the model status, box count, frame age,
  processing time and the **detection sensitivity slider** (the placeholder often scores
  below the default 45%).
- **Practice camera details** (capture status, model status, counts, frame age, stale
  warning, preview-confidence slider) appear when Developer mode is enabled.
- **Home in Developer mode:** the **Model test** tile opens the original camera/model
  screen without voice. Live Guard, depth testing and connectors are alongside it.
  Voice setup remains in the ordinary Settings screen.
- The manual tip-size field stays removed by request; tip sizes are fixed (8 mm / 13 mm).

## Fixed connector tip sizes and real-app home screen (November 8)

**Tip sizes are now fixed in code and cannot be changed in the app** (`ConnectorTip` in
`ProximityEngine.swift`):

| Connector | Size used as the scale |
|---|---|
| Blue tip | **8 mm**, measured at its tip |
| Clear tip with red tubing | **13 mm**, measured at the very top |

- The model has one `Sterile_connector_tip` class, so the app identifies each detected
  tip by **colour**: mean chroma over the inner 60% of the box in the camera's YCbCr
  frame. Strongly blue → blue 8 mm; otherwise (clear plastic, red tubing, background)
  → clear 13 mm. If no colour is available it assumes 8 mm, which errs toward warning
  earlier. The largest tip in view is the scale reference.
- Distance warnings are **always on**; the manual tip-size field and the "set tip size"
  step were removed. This replaces the earlier "on after calibration" behaviour below,
  and the old stored value is cleared.
- Live Guard labels each tip on screen ("Blue tip · 8 mm" / "Clear tip · 13 mm"). The
  gear → Settings → Connector tips and the home **Connectors** tile open a read-only
  connector sheet.
- **Home screen:** superseded by **My routines** and the optional Developer mode
  described at the top of this document. Measurement statistics remain available to
  developers; the normal screen shows daily practice progress instead.
- **Limits:** colour identification is a heuristic. A blue drape, coloured light or a
  strong white-balance cast could mislabel a clear tip, so check the on-screen label.
- **Verified:** portable checks (new fixed-size/colour/reference check) and the unsigned
  iPhone build. **Not verified:** colour identification on the real connectors.

## Earlier consumer UI and measurement summary (historical, November 8)

This section records the earlier interface. The current Sterling routine screen
and Developer-mode visibility are described above; current defaults are 10/30 mm.
The underlying Live Guard and `SafetyStats` code is retained.

- **Home:** (since replaced by the real-app home above) a setup checklist, a **Live Guard**
  card, and one **Start guided practice** button. It uses
  Cartesia if configured, otherwise the phone voice. Developer tools, including the
  camera + model test, moved to the gear → **Settings → Developer tools**.
- **Live Guard:** a full-screen live camera view (works with or without a routine) with
  an overlay on the analysed frame: the sterile tip box and its centre, safe zones
  drawn at the real 30 mm (red) and 80 mm (orange) distances from the tip's edge,
  fingertips, hand boxes, and the closest gap line with its mm reading. A status card
  shows **SAFE / MEDIUM RISK / HIGH RISK**, the distance, a 0–120 mm gauge, and step
  guidance (set tip size → looking for tip → show your hand). A risk-coloured border
  pulses on HIGH RISK. Chips show the band connection and tip size.
- **Distance metric:** fingertip to the tip's **nearest edge**, not its centre.
  Contamination happens at any part of the tip, and centre distance would overstate
  the gap by half the tip's size. The centre is only marked for orientation.
- **Explicit warnings:** the banner reads "HIGH RISK · 18 mm" or "MEDIUM RISK · 52 mm" with
  advice. Spoken cues start with "High risk." / "Medium risk."
- **Safety summary:** per session, it counts medium/high warnings (escalations), the
  closest approach, measured time, time outside warning zones and the longest stretch
  without a warning. It's shown in Live Guard and on the finished-practice screen,
  with **Share with my care team** (plain text). It's practice feedback, not a sterility
  or cleanliness score. Stats reset at each practice start, on New practice, or manually.
- **Verified:** portable checks (new `SafetyStats` check) and the unsigned iPhone build.
  **Not verified:** the look on a real iPhone, overlay alignment on live frames,
  zone-size accuracy against a ruler.

## Camera-distance warnings: on after tip calibration (November 8, superseded by fixed tip sizes above)

Changed at the user's request. The SPINOSAURUS-style image-scale method now drives
warnings again, but **only after the user enters the measured sterile connector tip
size** (Settings → Camera distance warnings, in mm, stored on the phone). With no size
entered it stays off, as before. No default size is assumed.

- **Method:** mm/px = tip size ÷ largest `Sterile_connector_tip` box (EMA 0.20).
  Distance = closest fingertip (Apple Vision, or the model's `Hand` box as fallback)
  to the tip box edge × mm/px (EMA 0.25); a fingertip on the box = 0 mm, immediately.
- **Levels:** MEDIUM ≤ 80 mm, HIGH ≤ 30 mm, with 5 mm hysteresis on release.
  Thresholds are defaults, not clinically chosen. 2D estimate only; it cannot
  confirm contact or sterility.
- **Feedback:** MEDIUM = orange banner + mm, warning haptic, "getting close" cue, band
  pulsing (`W` / v2 mode 1, duty 200). HIGH = red banner + mm, error haptic, "move them
  away now" cue repeated every 4 s, band continuous (`E` / v2 mode 2, duty 255). The
  preview draws the closest gap line with its mm label.
- **Scope:** runs in every phase, including placeholder-model rehearsal, independent of
  `detectorStatus`. The armed LiDAR path is unchanged; the higher level wins. Band
  commands expire after 250 ms, so it stops when observations stop.
- **Firmware:** unchanged, `firmware/vibration_band/vibration_band.ino`.
- **Verified:** portable checks (new hysteresis/level check) and the unsigned iPhone
  build. **Not verified:** iPhone run, real tip calibration, distance accuracy against
  a ruler, band latency, Arduino compile/flash.

## Current low-accuracy model and camera/voice integration (November 8)

The confirmed phone is **iPhone 15 Pro only**. Its camera image works; the reported
failure is missing detections and a blocked connection step, not lack of LiDAR.
The bundled export is a **low-accuracy placeholder**, per the team. Loading or
compiling it does not establish usable detection. `detectorStatus: "placeholder"`
in RoutineTemplate.json keeps predictions visible for debugging but disables
proximity warnings and real monitoring arming. Model weights are unchanged.

The routine now draws boxes, labels/confidence and Apple fingertips on the exact
analysed frame. Display freshness (one second, then dimmed/marked stale) is separate
from protection freshness (250 ms). Previously the routine hid all overlays at
250 ms, so a slower result could never appear. Counts, model errors, frame age,
a confidence slider for placeholder preview, camera status and restart controls
are visible at the connection/disconnection steps. A model prediction error no
longer suppresses independent Apple hand tracking. Camera startup no longer waits
for voice readiness; permission setup defers safely until the app becomes active.

With the placeholder, “ready” starts `unmonitoredPractice` and “done” finishes it;
no detections, depth clearance or vibration are required to rehearse. The assistant
can also finish that rehearsal conversationally. Events explicitly say unmonitored,
and real contact-review flags stay latched. A real experimental detector still
requires readiness before arming; merely replacing weights does not change mode.

The voice agent gets derived native observations through `get_routine_state`:
camera/model status, labels/confidence, opening/hand/fingertip counts, source-frame
age, display/protection freshness, proximity status and visual mode. Images stay
on the phone. Instructions explain the entire on-device pipeline, distinguish
“camera live but no detections” from camera failure, and prohibit blocking this
rehearsal on `camera_ready` or saying “personally I can't see the camera”. It must
not claim to visually verify technique or provide protection from this model.

When the improved model arrives, replace SterileParts.mlpackage, preserve/verify
the raw export contract and class IDs, and test actual props. Change
`detectorStatus` to `experimental` only for deliberate monitoring tests; rebuild
and start a new call. This mode remains an unvalidated prototype.

Validation: 40 portable checks, 16 gateway/setup tests, project membership and
all 16 Swift files type-checked against actual Catalyst frameworks passed. Phone
overlay behavior, model accuracy, voice/camera timing and an iPhone SDK build still
need the device/full Xcode. This update does not claim a successful physical test.


## Voice memory and natural progression (November 8, 2026)

The phone now keeps bag details across replies, including a short final answer
such as “2027”. New fragments append rather than replace earlier details; later
corrections stay in the draft, and questions/pause/reconnect preserve it. Rejecting
a summary keeps the history for correction; “start the bag over” explicitly clears
it. Draft text stays in session memory, outside event logs. The assistant receives
the whole draft and is instructed to ask only for genuinely missing information.
This is raw reported text, not a verified four-field record or prescription check.

The assistant can use `advance_practice_step(check_id)` to advance an ordinary
practice check conversationally, without exact-phrase or repeated-confirmation
loops. The phone binds it to the latest actual user turn and original check,
allows one advance, and logs unverified assistant progression. It cannot arm/skip
monitoring, resume a pause or clear contact review. The existing Cartesia agent
has the third tool attached, with a check-ID-only schema; rebuild the iPhone app
and start a new call to use it. The older installed build will not gain this logic.

Edit `ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/Resources/RoutineTemplate.json`
for step order, prompts/help, `exampleResponses` and shared `voice` messages. Edit the adjacent
`VoiceInstructions.txt` for conversational policy. Rebuild after edits. See
[the editing guide and current diagrams](../../DESIGN.md#edit-the-voice-prompts-and-routine-flow).
Other agents can run `setup_agent.py` once to add the tool without replacing
unrelated tools/configuration. No account login or new agent ID is required.

38 portable checks, 15 gateway/setup tests, project validation and all 16 Swift
files type-checked against actual Catalyst frameworks passed. Phone microphone,
conversational behavior and iPhone SDK build still need full Xcode/the device.

The home screen offers a setup checklist, **Live Guard** and guided practice coaching.
**Settings → Developer mode → Developer tools → Camera + model test** is a separate camera-only
detector test that needs no voice setup. The bundled RF-DETR Small
model detects hands and protected connector tips; Apple Vision supplies fingertips.
The original RGB/LiDAR hardware test remains under the gear menu > Developer tools.
Practice coaching adds label OCR, BLE and Cartesia conversation with phone-voice
fallback. No printed markers are needed. The app is foreground-only and practice-
only; no prescription or clinic protocol is bundled. No video is recorded/uploaded.

November 8, 2026 verification: project membership, 29 portable logic checks,
13 mocked gateway/setup tests and all 16 Swift files type-checked against actual
Apple Catalyst frameworks passed. This workspace has Command Line Tools, without
an iPhone SDK; iPhone compilation, UI/camera behavior, real-prop accuracy and
physical warning latency still need full Xcode and a phone.

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
5. Press **Run** (Command-R), open **Settings → Developer mode → Developer tools → Camera + model test**
   (or **Live Guard** on the home screen), and allow Camera access.
   Capture and actual model inference start automatically. For the original
   two-pane RGB/depth test, open the gear menu > Developer tools >
   **Camera and depth test**, then tap **Start camera**.
   The app checks actual rear scene-depth support. A standard iPhone 16 is an
   expected unsupported-device case for this rear-LiDAR test; no simulated depth
   or automatic front-camera fallback is used.
6. After confirming the app works, unplug the cable and repeat. The camera/model
   test runs on the phone without a computer/network connection.
   Cartesia conversation separately needs internet. A free Personal Team profile
   expires after seven days; rebuild/reinstall from Xcode after expiration.

Apple documents [free local signing](https://developer.apple.com/help/account/basics/about-your-developer-account)
and [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
Keep signing certificates, provisioning profiles and account authentication local.

## Camera + model: first phone test

1. Open **Settings → Developer mode → Developer tools → Camera + model test**. No key, microphone access,
   routine answers or wristband connection is required. Opening it pauses any
   active coach session and stops voice/vibration; it does not resume them on exit.
2. Mount the phone in portrait over disconnected training props. Put a real-looking
   mock connector tip and hand in view. Check **Model loaded** and the model status.
   Orange boxes are protected tips, green boxes are learned hands, and cyan dots
   are Apple fingertips. Class labels and confidence appear below the image.
3. Check boxes/dots stay aligned on the **Analysed frame**. The image and detections
   come from the same source frame, so the preview follows inference delivery.
   This is not a full-camera-rate preview. Move one prop at a time to assess it.
4. Adjust **Minimum confidence** (default 45%) to inspect weaker detections; hide
   hand boxes or fingertip dots if needed. These settings do not alter the coach.
   No detection is not evidence of a clear/sterile surface.
5. Inspect camera rate, completed model results/s, pipeline duration, analysed-frame
   age, depth source and estimated gap/unavailability reason. Gap output is withheld
   above 250 ms source-frame age. Boxes dim and are marked stale above one second
   or when stopped. Pipeline timing excludes the extra debug preview rendering;
   frame age includes that work and delivery. Neither measures physical warning latency.
6. Stop/restart, press Done, background/lock, and deny camera access in separate
   trials. Capture must stop; accepting a pending permission prompt after closing
   the view must not start it again. Return and press Start after an interruption.
   This screen generates no speech, routine completion or vibration warnings.

The same production detector/depth worker is used, with one in-flight inference
and no backlog. A paired RGB preview is generated only for this debug mode.
The current capture controller requires rear LiDAR; it has no RGB-only fallback.
Model accuracy, tiny-tip depth and sustained performance still require real props.

## Skip/jump while testing a routine

Open gear menu > enable **Developer mode** > **Developer tools**, enable **Routine debug controls**, close setup.
Use the main screen's **Jump to step** picker and **Jump to selected step** or
**Skip current step**. This works independently of Cartesia; jumping from idle
starts at the selected check silently. If voice is active, a jump reconnects the
conversation at the new check. With debug controls enabled, “skip this step”,
“skip ahead” and “next step” also work by voice. The toggle is off on each app launch.

Debug moves clear pending read-backs, stop the band and log `debug_step_jump` or
`debug_step_skipped`, with unverified evidence. A debug finish uses `debug_finished`.
They never log a completed check or arm monitoring. Camera readiness still applies;
possible-contact review cannot be skipped. Use the separate camera-only screen to
inspect detection independently of routine gates. Pause/resume/end/debug-skip
commands are dispatched from actual user transcripts by native code, without
waiting for an LLM tool call; a late duplicate tool call does not apply them twice.
“Please pause” and “Can we pause?” are supported; negated phrases are not substring
matched. Pause interrupts playback. Speech recognition and turn-end latency remain.

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
  hardware test needs only camera permission. Practice coach separately requests
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
`sceneDepth`, not `smoothedSceneDepth`. The original **Camera and depth test** performs no model
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

## Practice coach: test without Cartesia

1. Open the gear menu and choose **Try phone voice**. It starts the practice and
   camera together. Allow camera, microphone and on-device speech permissions.
   Say done to report an action. Ask “Why is this needed?”: the explanation must
   leave the check open. Say pause, resume, or repeat without touching the screen.
2. In phone-voice fallback, read-backs use a confirmation. In Cartesia mode, the
   assistant can advance ordinary checks conversationally. Bag details can be given
   in several replies; try giving just the expiry year last and check prior details
   remain in the summary. Corrections and pause/reconnect should preserve the draft.
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

The separate image-scale method has no default millimetre calibration. Once you
enter the measured tip size in Settings, it drives MEDIUM/HIGH banner, voice,
haptic and wristband warnings in every phase. The registered-depth path keeps its
existing experimental proximity gate. Camera arming requires a fresh clear observation,
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
A teammate may have a different
signing team in their checkout; replacing a locally configured project can change
the selection. Keep your own working settings when integrating updates. A
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
