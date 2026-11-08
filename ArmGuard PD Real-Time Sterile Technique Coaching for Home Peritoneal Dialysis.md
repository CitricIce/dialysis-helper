# Sterling: keep it clean

**Public brand:** Sterling · **Slogan:** keep it clean

**Description:** Your at-home dialysis companion, with voice guidance, camera support and wristband feedback.

**Mission:** Help people stay safely on home peritoneal dialysis by reducing hygiene-related infections and avoidable transitions to hemodialysis. This is the mission, not a demonstrated outcome. Longer term, extend that support to other home medical procedures.

Logo concept: [silver-ring wordmark](assets/branding/sterling-logo-v1.png).

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
  no tip/hand measurement or stale analysis produces no distance command. Default
  zones remain HIGH 10 mm and MEDIUM 30 mm with existing hysteresis. Voice names the
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

Validation: **55 portable checks, 16 gateway/setup tests, project validation and
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
[the editing guide and current diagrams](DESIGN.md#edit-the-voice-prompts-and-routine-flow).
Other agents can run `setup_agent.py` once to add the tool without replacing
unrelated tools/configuration. No account login or new agent ID is required.

38 portable checks, 15 gateway/setup tests, project validation and all 16 Swift
files type-checked against actual Catalyst frameworks passed. Phone microphone,
conversational behavior and iPhone SDK build still need full Xcode/the device.

Nov 7, 2026 · @e

> Current implementation, November 8, 2026: the foreground iPhone app runs camera,
> LiDAR, RF-DETR, Apple fingertip tracking, proximity rules and Bluetooth locally.
> Cartesia conversation connects directly from the phone using a key entered once
> and stored in Keychain. A laptop is needed for development/install, not operation.
> The low-accuracy connector-tip placeholder is included for diagnostics. Printed markers are not required.
> [DESIGN.md](DESIGN.md) contains the engineering details; [the app guide](ios/ArmGuardCaptureProbe/README.md)
> contains setup and verification steps. Clinical protocol, real-prop accuracy and
> physical iPhone warning latency remain unvalidated. Dashboard, scores and clips
> are future product ideas, not current functionality.

## Current testing flow

**Settings → Developer mode → Developer tools → Camera + model test** runs the bundled detector and Apple
fingertips without voice, routine checks or vibration. It shows confidence, boxes
on the exact analysed frame, fingertip dots, depth availability and timing/frame
age. No Cartesia key, internet or printed marker is needed. Stop/Done/background
stops capture. This tests detections; it does not declare a surface sterile.

For routine debugging, enable **Routine debug controls** in Developer tools to
jump/skip steps manually or say “skip this step”. Debug navigation is logged as
unverified, never completes a check or arms monitoring, and cannot clear contact
review. Explicit pause/resume/end/debug-skip commands are handled from real user
transcripts by native code without waiting for the agent's tool decision. Pause
interrupts playback. Recognition timing and conversation behavior still need phone
tests. See [the app testing guide](ios/ArmGuardCaptureProbe/README.md).

November 8 local verification passed 29 portable logic checks, 13 gateway/setup
tests, project validation and all 16 Swift files type-checked against Apple
Catalyst frameworks. This is not an iPhone build, real-prop accuracy result or
physical latency measurement; those still require the device and full Xcode.

## Summary

ArmGuard PD is a prototype for spoken guidance and proximity feedback during home peritoneal dialysis (PD) preparation. The current app guides a practice routine, watches fingertips near a detected protected connector tip, and sends variable vibration commands directly to an ESP32 band. Its goal is to help users keep exposed sterile surfaces untouched. It cannot establish sterility, confirm physical contact or certify a clean exchange. Nurse review and clinical benefit remain future validation goals.

Touch contamination is the leading cause of PD peritonitis. Peritonitis is a leading reason patients drop PD for in-center hemodialysis. The tools on the market today detect infection after it starts (effluent turbidity sensors) or train patients before they go home (VR, passive holders). Nothing we found coaches the patient live, during the step where contamination happens.

**Primary users:** older PD patients with vision loss, neuropathy, hearing loss or mild cognitive decline, and the caregivers and assisted-PD nurses who support them. **Buyer:** dialysis providers, whose revenue depends on keeping patients on PD.

## Problem

Peritonitis starts at the connector, and nobody is watching when it happens. In PD, a patient drains and refills their abdomen with dialysate through a catheter, several times a day (manual CAPD) or overnight on a cycler (APD). Every exchange means opening and joining sterile connectors by hand. One touch on a connector tip can bring bacteria into the abdomen.

- **Leading cause:** touch contamination is still the leading cause of peritonitis in PD patients ([DaVita / Clere, 2014](https://davitaclinicalresearch.com/wp-content/uploads/pdfs/ADC_2014/Clere_Protocol.pdf)).
- **How common:** peritonitis affects about 13% of PD patients each year ([Sci. Reports, 2022](https://www.proquest.com/docview/2703692767)).
- **What it costs the patient:** hospital stays, scarring of the peritoneum, and often a forced switch to hemodialysis.
- **What it costs the provider:** a patient who leaves PD costs the provider the patient, plus the training already spent. Poor technique training drives early dropout. Burnout and caregiver needs drive late dropout ([J. Nephrology review](https://link.springer.com/10.1007/s40620-023-01759-w)).
- **Technique slips over time:** patients pass training and then get comfortable. Mistakes stay invisible until an infection shows up.
- **The patients most at risk are the ones who struggle most:** CAPD patients with poor vision or poor eye-hand coordination are especially prone to touching the tubing during connection ([Helping Hands RCT](https://haconvention2023.dryfta.com/abstract-archive/abstract/public/743/randomized-controlled-trial-on-3d-printed-assistive-device-for-continuous-ambulatory-peritoneal-dialysis-can-helping-hands-reduce-peritonitis-episode)).
- **Caregivers are stretched:** 60% of PD caregivers report mild to moderate burnout and 13% moderate to severe ([ISPD assisted PD position paper](https://sapientia.ualg.pt/bitstreams/8cb9c694-ace3-4ba7-b430-a3c3be0f6332/download)). In a Colombian multicenter study, peritonitis rates differed significantly with caregiver overload (p = 0.034) ([WCN 2025](https://events.theisn.org/event/session/view/29359)).

## Existing solutions and the gap

Today's tools either detect infection after it starts or train patients before they go home. None we found coaches technique live, during the exchange.

| Solution | What it does | When it acts | Gap |
| --- | --- | --- | --- |
| [CloudCath](https://fda.innolitics.com/device/K212658) (FDA 510(k), Feb 2022) | Optical turbidity sensor on the cycler drain line, cloud alerts to clinicians | After infection starts | Detects cloudy fluid, doesn't prevent contamination; APD only |
| [Smartphone effluent and exit-site photo patents](https://patents.justia.com/patent/20190228526) | Image analysis of the drain bag or catheter site | After infection starts | Same as above; relies on the patient to take photos |
| [Low-cost microscopy screening](https://www.proquest.com/docview/2703692767) (research) | White blood cell classification across the drain tube, 94% accuracy | After infection starts | Research prototype |
| [Helping Hands](https://haconvention2023.dryfta.com/abstract-archive/abstract/public/743/randomized-controlled-trial-on-3d-printed-assistive-device-for-continuous-ambulatory-peritoneal-dialysis-can-helping-hands-reduce-peritonitis-episode) (Hong Kong RCT) | 3D-printed passive holder that keeps fingers off the tubing | During exchange | No sensing, no feedback, no data for the nurse |
| [VR training with Leap Motion](https://theses.lib.polyu.edu.hk/handle/200/12254) (PolyU RCT) | Hand-tracked practice of the exchange sequence | Before the patient goes home | Training only; nothing during real exchanges at home |
| [Fresenius hand-cleanliness scanning patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11410421) | Scans hands before treatment | Before exchange | Patent; no shipped product found; doesn't watch the connection |

**Takeaway:** the Helping Hands RCT shows that keeping hands off the tubing lowers peritonitis rates. The VR study shows hand tracking works for teaching PD steps. ArmGuard puts those two ideas into the real exchange at home, with feedback the patient feels and data the nurse can act on.

## Solution

The current prototype has two programmed parts and one external voice service:

- **iPhone app:** Swift/SwiftUI on an iPhone 15 Pro, mounted above the work surface.
  ARKit supplies paired RGB and LiDAR depth. The bundled RF-DETR Small model
  detects `Hand` and `Sterile_connector_tip`; Apple Vision supplies fingertips.
- **ESP32 band:** receives numeric intensity commands over Bluetooth and drives
  the Adafruit motor through the appropriate driver. One band is supported.
  Fit and test it before hand preparation; placement needs usability testing.
- **Cartesia conversation:** guides steps, accepts spoken replies and answers
  questions in the same call. Enter the authorized API key once in the phone's
  setup; it stays in Keychain. Voice/agent IDs are prefilled. Internet is needed
  for conversation; no laptop service needs to stay running.

Cached Cartesia clips or immediate phone speech handle urgent cues without a
network round trip. A hosted credential gateway remains an optional future
architecture for shared app distribution. A nurse dashboard, automatic uploads,
recorded contact clips, patient ranking and technique scores are not implemented.

### What a practice routine looks like

1. **Set up once.** Install with Xcode, enter the voice key, allow the requested
   permissions, position the camera and connect/test the optional band.
2. **Start practice.** Choose an exchange label and start before preparing hands.
   The labels do not prescribe a daily treatment schedule.
3. **Prepare through conversation.** Short prompts cover space, bag details, mask,
   hand preparation and protected openings. Follow the care team's instructions;
   the app does not verify hand cleanliness, room airflow or prescription values.
4. **Read back consequential details.** Bag details may arrive across several
   replies. The assistant keeps them, asks only for missing data and can advance
   ordinary practice checks conversationally. Questions keep the check open.
5. **Connect with monitoring.** Say ready. Monitoring starts only with fresh,
   clear observations, usable depth, the model and complete two-hand coverage.
   Near fingers increase vibration. Projected overlap asks the user to pause and
   review; it is not confirmed touch. A review flag cannot be cleared by resume.
6. **Continue and practise disconnecting.** The routine includes a second
   preparation/monitoring window. The bundled model has no cap-interior class;
   that surface is not covered by the current detector.
7. **Pause or finish by voice.** Say pause, resume, repeat, read the label or end
   session. If observations are unavailable, an explicit practice-only skip is
   recorded as unmonitored, never as a pass. No clean-exchange score is produced.

The bundled routine is a practice scaffold requiring clinical review, not a
patient-specific dialysis protocol.

## Hardware bill of materials

The runtime setup is an iPhone plus the optional band. The Mac is for build,
signing, installation and debugging. Original rough component allowances are
retained below as planning estimates; these have not been re-priced.

| Item | Qty | Purpose | Original rough allowance (USD) |
| --- | --- | --- | --- |
| iPhone 15 Pro | 1 | Runs the app, rear RGB/LiDAR, model, speaker and Bluetooth | have |
| Mac with full Xcode | development only | Build/sign/install; can be closed after installation | have |
| Stable overhead mount | 1 | Holds the phone in a repeatable view; validate working distance on props | 10–15 |
| Steady desk lighting | 1 | Reduce blur/glare on hands and connector | have / 10 |
| BLE-capable ESP32 | 1 | Receives commands directly from iPhone; ESP32-S2 has no Bluetooth | 6–10 |
| Adafruit Vibrating Mini Motor Disc | 1–2 | Variable intensity through PWM and a driver | 2–10 |
| Suitable motor driver/transistor and flyback diode | 1 | Keep motor current off the GPIO | 1 |
| Compatible battery/charger or USB power bank | 1 | Power the band; verify with the assembled hardware | 8 |
| Strap/housing | 1 | Mount the band clear of the work area | 5 |
| Matte work surface | 1 | Consistent background | have |
| Dry disconnected mock connectors, caps and mock bag label | 1 set | Prop and routine tests; never patient-connected | borrow / mock |
| Printed markers | optional alternative only | A separate calibrated marker demo; not used by the bundled detector | ~0 |

**Software:** Swift/SwiftUI, ARKit, Core ML, Vision, CoreBluetooth and AVFoundation
on the phone; Cartesia Managed Agents/TTS over HTTPS/WSS; Arduino firmware on the
ESP32. Python is used for development/export and the optional hosted gateway,
not for the phone's live camera loop.

**Camera setup:** use the app's rear RGB/LiDAR capture, portrait orientation, a
stable mount and a view of both hands plus the protected tip. Test depth quality,
lighting, motion and sustained heat on actual props. Continuity Camera and a
Record3D purchase are not required.

## System architecture

```text
iPhone ARKit RGB + depth
  -> RF-DETR protected tip/hand boxes + Apple Vision fingertips
  -> registered proximity + routine/readiness/review gates
  -> CoreBluetooth -> ESP32 -> motor PWM
  -> immediate local audio/display + local practice-event log

iPhone microphone <-> Cartesia conversation over internet
  -> native get-state / respond-to-check tools
  -> guarded routine progress
```

### Vision pipeline

- **Model:** bundled RF-DETR Small, 512 px, 300 queries. Class 0 is reserved,
  class 1 is `Hand`, class 2 is `Sterile_connector_tip`. The export explicitly
  records logits, normalized cxcywh boxes, output names and class roles.
- **Hands:** whole-hand boxes are shown, while Apple Vision tracks fingertips.
  Whole-hand centroids are not substituted for finger-to-opening clearance.
- **Preprocessing:** rotate to portrait, resize, convert RGB/ImageNet-normalized
  NCHW input, and reuse tensor storage. Decode logits with sigmoid, exclude the
  reserved slot and clip valid off-frame boxes at the image boundary.
- **Geometry:** compare fingertips with the nearest projected protected-region
  boundary, then unproject usable depth samples. Mixed/invalid depth is unknown.
  Overlap requests review; sampling the same overlapped depth pixel twice would
  not establish zero physical separation.
- **Coverage:** cap interiors, clothing, other body parts, floor/table collisions
  and valid mating-pair exceptions are not implemented by this model.
- **Image-scale method:** drives MEDIUM/HIGH warnings only after the user enters the
  measured tip size (see the November 8 camera-distance section). No size is assumed.

### Latency and evidence

The under-150-ms finger-to-buzz figure is a goal, not a measured result. Current
software requests 30 fps where available, accepts at most 15 inference frames/s
with one in flight, drops busy frames, and previews at up to 10 Hz. Observations
older than 250 ms are unusable; a 100 ms health check also detects stalls.

Model work, speech/network and logging do not block the camera delegate. Hazard
feedback does not wait for the conversational agent. Voice clips are preloaded;
phone speech is the immediate fallback. The parallel image-scale alert timer
was removed so it cannot restart vibration during pause or outside monitoring.

| Verification | Current evidence | Still needed |
| --- | --- | --- |
| Logic and API setup | 38 core + 15 gateway/setup checks pass | Device behavior |
| Swift source | 15 files type-check against Apple Catalyst frameworks | Full iPhone build/sign/install |
| Actual model | Mac compile/load, RGB/rotation/normalization, inference/decoding pass | Real-prop photo accuracy and phone performance |
| Processing timing | 187.4 ms warm Mac CPU on a generated pattern | Phone distributions, heat and physical end-to-end timing |
| Direct voice | Native HTTPS speech/session creation and WSS audio pass without laptop gateway | Phone microphone, echo, interruption and recovery tests |

Measure finger motion through motor/audio onset with an independent high-speed
recording. Report misses, false alerts, stale intervals and sustained-session
results, not just inference time or camera frame rate.

### Haptic protocol

The Adafruit motor supports variable intensity. The selected firmware must match
its actual installation; the app defaults to legacy compatibility.

- Device name `DialysisBand`, service `7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00`.
- Legacy command characteristic `...0002`: existing ASCII commands; app uses
  `W`, `E`, `S` for warning/review/off.
- Intensity-v2 characteristic `...0003`: `[mode, duty]`; mode 0 off, 1 proximity,
  2 review cue, duty 0–255. The app's test uses a short mode-1 command. No mode 3.
- Desired commands expire after 250 ms. V2 refreshes every 100 ms; firmware stops
  after 300 ms without refresh and on disconnect. Reconnect starts off and is explicit.
- Neither supplied sketch implements the original proposed two-pulse contact
  pattern. The alternate `vibration_band` sketch pulses mode 1 and drives mode 2
  continuously at the supplied duty; the original sketch applies duty directly.

### Event data model

Current local practice logs contain only these fields:

| Field | Meaning |
| --- | --- |
| `kind` | Start, recorded check, pause, monitoring state, skip, overlap review or finish |
| `checkID` | Associated practice check, if any |
| `timestamp` | Event time |
| `evidence` | Self-report, experimental observation, unavailable/unmonitored category |

No raw voice, read-back text, images, contact clips, patient ranking or clinical
technique score is saved in these logs. Export is manual. Cartesia processes
microphone audio during an opted-in call and may retain cloud call records under
the account's settings; camera/depth processing stays local.

## Software specification

The iPhone foreground app owns capture, inference, routine state, feedback and
local events. The ESP32 receives motor commands. A laptop server is optional,
not required for operation; a future hosted gateway could protect shared keys
when distributing beyond personal testing.

### Implemented files

```text
ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/
  CaptureController.swift       # ARKit RGB/depth and freshness
  CoachVisionPipeline.swift     # model + Apple hand pose + depth observations
  RFDETRDetector.swift          # input preparation and raw tensor adapter
  SterileParts.mlpackage/       # trained model, compiled by Xcode
  CoachViewModel.swift          # routine/vision/voice/band coordination
  RoutineCoachView.swift        # spoken-step UI and setup
  CoachSpeech.swift             # direct TTS, cached alerts, fallback, Keychain
  CartesiaConversation.swift    # streaming audio, interruptions and native tools
  BandClient.swift              # current expiring Bluetooth command
  Resources/RoutineTemplate.json
  Resources/VoiceInstructions.txt
Core/Sources/CaptureProbeCore/
  RoutineEngine.swift
  ProximityEngine.swift
  CartesiaProtocol.swift
firmware/wristband/wristband.ino
firmware/vibration_band/vibration_band.ino
scripts/check-ios-app.sh
scripts/check-rfdetr-model.swift
scripts/export_rfdetr_coreml.py
services/voice_gateway/          # optional hosted/dev route and agent creation
```

### Runtime rules

| Rule | Current implementation |
| --- | --- |
| Warning band | Experimental 50 mm depth-based boundary clearance; intensity rises as estimated gap falls |
| Contact | No contact-radius proof or clinical contamination classification; projected overlap requests sticky review |
| Depth validity | Reject mixed patches over 20 mm spread and regions smaller than two depth pixels |
| Arming | Loaded model, fresh clear observations, protected region, usable depth and complete two-hand coverage |
| Missing observations | Pause monitoring, stop/expire vibration, speak loss cue; no automatic rearm |
| Pause/review | No parallel alert source may bypass routine state or clear a review flag |
| Releases | Require 300 ms observed separation before releasing a near warning |
| Audio | Urgent cues interrupt conversation; repetition cooldown limits queued speech |
| Conversation tools | Get state or consume the actual latest user reply once for its current check |
| Clinical choices | Follow the care team's instructions; no configured prescription validation or recovery treatment |

### Routine structure

Room preparation → bag read-back → mask → hand preparation → protected-opening
read-back → connection monitoring → instructed exchange steps → new preparation
→ disconnection monitoring → review. Bag/opening checks require separate spoken
confirmation. Other completion replies are self-reports. Questions stay in the
same conversation. Four exchange labels are placeholders, not a prescribed schedule.

The app is foreground-only. Backgrounding pauses it; returning requires explicit
voice resumption, and monitoring must be rearmed with fresh observations.

## Build and validation plan

The model and voice integration are implemented, with no new commit made by the
integration work. The next milestones require the actual phone and band:

1. Build/install the updated app using the owner's existing Xcode team settings.
2. Enter the Cartesia key once on the phone, test natural replies, questions,
   interruptions and recovery, and verify operation after closing the Mac.
3. Check boxes/fingertips against real mock connectors and confirm the model
   detects exposed tips rather than nearby packaging or the whole connector.
4. Test depth and coverage at the intended mounting distance; label occlusions,
   hovering, fast approaches, rotation, skin tones/gloves, glare and dim light.
5. Verify the selected firmware, variable duty, stop/disconnect and watchdog on
   the actual band. Measure physical warning latency over sustained operation.
6. Review routine wording and surface definitions with PD clinicians before
   considering patient use. Dashboard, scores and automatic checks stay future work.

## Demo script (3 minutes)

Use disconnected training props and the current app; describe limitations directly.

1. **Setup:** show the phone on its mount and a connected/tested band. Close the
   development laptop to demonstrate standalone operation.
2. **Conversation:** start practice, answer a prompt, ask a question and confirm
   that the question does not advance the check. Demonstrate bag read-back.
3. **Approach:** at an armed connection step, show the detected tip and fingertips;
   approach slowly and retreat as vibration/audio warn. Describe the depth gap as
   experimental, not proof of safety.
4. **Uncertainty:** hide a hand or interrupt the camera; show monitoring pause and
   motor shutoff. Resume requires fresh readiness. A projected overlap requests
   review rather than claiming confirmed contact.
5. **Finish:** show the local practice-event log and distinguish it from a future
   nurse dashboard. Present only measured device results; do not display a
   cleanliness score or a fabricated contact count.

Keep a recorded rehearsal as a backup. Hardware demonstrations remain contingent
on passing the phone/prop/band tests above.

## Business case

The proposed buyer is a dialysis provider. The business hypothesis is that usable coaching and eventual clinician review could support home care. Nurse workload, clinical benefit, willingness to pay and outcome effects are not established by this prototype; the dashboard and technique-data product remain future work.

- **Customer:** home dialysis programs at dialysis providers and hospital-based PD units. Patients use it; the program buys it.
- **Value to the buyer:**
  - Hypothesized outcome to study: fewer peritonitis episodes would mean fewer hospital stays and fewer patients transferring to in-center hemodialysis.
  - Future nurse workflow: a technique audit and retraining check happens remotely, after every exchange, instead of only at a home or clinic visit.
  - Future hypothesis: it could widen the pool of patients who can do PD at all. Patients whose vision, dexterity or cognition is borderline, who would otherwise need a caregiver or a paid assisted-PD nurse, get a safety net. The ISPD position paper on assisted PD calls for expanding assisted PD internationally.
- **Who to start with:** new PD starts (first 90 days, while training is fresh and dropout risk is high), patients with a past peritonitis episode, and assisted-PD programs.
- **Pricing hypothesis:** a per-patient monthly subscription covering the station, the band and the dashboard. Price it against the cost of one avoided peritonitis admission per panel of patients. The actual numbers need validation with a provider.
- **Go-to-market:** a pilot at one PD unit (Duke's home dialysis program is an obvious first conversation), run as a technique-audit study, then pitch the results to large dialysis providers.
- **Regulatory:** launch as a training and adherence tool that coaches and logs, rather than a diagnostic. Any claim that it reduces peritonitis would likely make it a regulated medical device (software as a medical device), so get a regulatory consult before making outcome claims.

## Risks and judge objections

The biggest open question is unproven: does live coaching cut peritonitis more than good retraining does? Say that plainly and present ArmGuard as the tool that makes the study possible.

| Objection | Answer |
| --- | --- |
| "This is easy to do manually." | For a 45-year-old on day one, yes. Our users are 78, have retinopathy, and are 14 months in. Contamination is invisible until infection shows up. |
| "Patients take off watches and bracelets before washing their hands." | That's why the band goes on the upper arm, after washing and clear of the sterile area. Audio is the default for patients who don't want a band. |
| "A camera in someone's home is a privacy problem." | It runs only during an exchange and points down at the work surface. Camera/depth/model processing stays on the phone. Opted-in microphone audio goes to Cartesia. Practice events stay local unless manually exported; no automatic clips or uploads exist. |
| "False alarms will annoy patients until they turn it off." | False-alert rate and burden still need measurement. Usable near-risk observations warn immediately; cooldowns limit repeated speech. Unknown tracking pauses monitoring instead of claiming clearance. |
| "Big players already have patents." | Fresenius has a hand-cleanliness scanning patent. Before going past the hackathon, do a freedom-to-operate search on live connection monitoring. |
| "Lighting and camera angles break CV." | Use a fixed overhead mount, the bundled RF-DETR model and readiness checks for hands, protected region, depth and freshness. Printed markers are only an alternative demo path. |
| "Older patients won't charge another device." | The band is optional. Charging, enclosure and battery-state feedback still need hardware validation; a charging dock is not implemented. |

**Other risks:** a trained tip/hand model is bundled but real-exchange generalization has not been established (stage consented training-kit footage, then review with a PD unit); hand tracking may fail with gloves or tremor (test it); clinic contamination protocols vary (make the prompts configurable per clinic).

## Future work and validation

The next step after the hackathon is a usability and accuracy study with a PD unit, before any outcome claim.

1. **Bench accuracy:** compare detections, proximity warnings and overlap flags with independently labeled staged footage. Report misses, false alerts, unknown cases and physical warning latency; do not equate image overlap with contact.
2. **Usability with PD nurses and patients:** can patients over 70 set it up alone? Does the buzz help or startle? Use the hand-tracked VR training study as a model for the protocol.
3. **Broader protected surfaces:** validate the bundled marker-free connector-tip model on actual props, then add cap-interior or other collision classes only with appropriate training and evaluation.
4. **Pilot:** new PD starts at one unit, measuring technique scores over time, retraining visits needed and peritonitis rate against past rates.
5. **Product extensions:** an AR headset version that highlights the no-touch zone in view; integration with cycler remote-monitoring platforms; a version for home hemodialysis cannulation.

## Sources

- [CloudCath PD Drain Set Monitoring System, FDA K212658](https://fda.innolitics.com/device/K212658)
- [CATCH study of CloudCath, Kidney International Reports 2024](https://rcastoragev2.blob.core.windows.net/28e605ca32bc86021e5a7d512b27c50a/main.PMC11101817.pdf)
- [Method of detecting symptoms of peritonitis (smartphone patent application)](https://patents.justia.com/patent/20190228526)
- [Low-cost microscopy for peritonitis screening, Scientific Reports 2022](https://www.proquest.com/docview/2703692767)
- [Helping Hands RCT, HA Convention 2023](https://haconvention2023.dryfta.com/abstract-archive/abstract/public/743/randomized-controlled-trial-on-3d-printed-assistive-device-for-continuous-ambulatory-peritoneal-dialysis-can-helping-hands-reduce-peritonitis-episode)
- [VR PD exchange training with Leap Motion, PolyU thesis 2022](https://theses.lib.polyu.edu.hk/handle/200/12254)
- [Scanning test system for hand cleanliness, US patent 11410421](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11410421)
- [Alcavis protocol and touch contamination, DaVita 2014](https://davitaclinicalresearch.com/wp-content/uploads/pdfs/ADC_2014/Clere_Protocol.pdf)
- [Assisted PD position paper, ISPD](https://sapientia.ualg.pt/bitstreams/8cb9c694-ace3-4ba7-b430-a3c3be0f6332/download)
- [Risk factors for PD discontinuation, Journal of Nephrology](https://link.springer.com/10.1007/s40620-023-01759-w)
- [Caregiver overload in PD, WCN 2025](https://events.theisn.org/event/session/view/29359)
