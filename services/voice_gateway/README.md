# Sterling optional Cartesia gateway

**Public brand:** Sterling · **Slogan:** keep it clean

**Description:** Your at-home dialysis companion, with voice guidance, camera support and wristband feedback.

**Mission:** Help people stay safely on home peritoneal dialysis by reducing hygiene-related infections and avoidable transitions to hemodialysis. This is the mission, not a demonstrated outcome. Longer term, extend that support to other home medical procedures.

Logo concept: [silver-ring wordmark](../../assets/branding/sterling-logo-v1.png).

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
[the editing guide and current diagrams](../../DESIGN.md#edit-the-voice-prompts-and-routine-flow).
Other agents can run `setup_agent.py` once to add the tool without replacing
unrelated tools/configuration. No account login or new agent ID is required.

38 portable checks, 15 gateway/setup tests, project validation and all 16 Swift
files type-checked against actual Catalyst frameworks passed. Phone microphone,
conversational behavior and iPhone SDK build still need full Xcode/the device.

The iPhone prototype now connects directly to Cartesia by default. Enter an
authorized API key once in the phone's Voice setup; it is stored in Keychain.
No laptop server is needed. Voice and agent IDs are prefilled. Camera, model and
wristband processing remain local; Cartesia conversation needs internet.

The service below is an optional hosted alternative for future shared app builds.
Choose **Hosted voice server** under Advanced voice settings to use it. A deployed
HTTPS gateway can keep a shared provider key off phones without requiring a laptop.


The phone uses one Cartesia conversation to guide a practice routine, accept spoken
replies, and answer questions along the way. You do not need the account owner's
login. You need their authorized API key, a voice ID they like, and access/credits
for Managed Agents as well as speech. Account or billing changes may still need
the owner. Live API tests passed on November 7, 2026: authorized key/voice lookup, tool and agent creation, generated speech, WebSocket audio, and a synthetic spoken reply through both client tools. Phone microphone, echo suppression, interruptions and physical latency remain unverified.

## Camera and routine debugging (November 8, 2026)

Camera-only testing needs no gateway, Cartesia credentials or voice session.
Rebuild and open **Settings → Developer mode → Developer tools → Camera + model test**. It runs the actual
bundled detector, fingertip tracking and depth with boxes/confidence/timing; it
pauses the parent coach and produces no voice or vibration warnings.

Enable **Routine debug controls** under Developer tools to jump/skip manually
without agent approval, or say “skip this step” during voice practice. Native code
handles pause/resume/end/debug-skip directly from actual user transcripts. Late
tool calls acknowledge the resulting state without applying commands twice.
`get_routine_state` exposes `debug_controls_enabled` and `debug_navigation_used`.
Debug skips are logged as unverified, do not complete checks/arm monitoring and
cannot bypass contact review. The bundled `VoiceInstructions.txt` is updated;
no new agent ID or account login is needed; the third tool has been attached to
the project agent. Optional deployed gateways
must use the updated instructions file; direct phone mode gets it with the build.

Local validation: 29 portable checks, 13 gateway/setup tests, project validation
and 16 Swift files type-checked against Catalyst frameworks passed. Camera UI,
physical speech/interruptions and iPhone SDK compilation remain unverified here.
See the [phone test instructions](../../ios/ArmGuardCaptureProbe/README.md).

## One-time setup on the Mac

Copy `.env.example` to `.env` in this directory. Fill in `CARTESIA_API_KEY`,
`CARTESIA_VOICE_ID`, and a separate `ARMGUARD_GATEWAY_TOKEN`. Generate that access
code with `python3 -c 'import secrets; print(secrets.token_urlsafe(32))'`.
Do not put the Cartesia key in the app, chat, or Git. The filled-in `.env` and
local agent setup state are ignored by Git. Environment variables override `.env`.
This reader treats values literally; it does not execute shell commands.

From the repository root:

```sh
python3 services/voice_gateway/setup_agent.py
python3 services/voice_gateway/server.py
```

The first command creates three client tools and a dedicated agent, or adds
the missing advance tool to an existing agent recorded in local setup state.
Existing unrelated tools/configuration are preserved. Confirmed resource IDs are
saved locally and reused on reruns;
no key is stored in that state file. If a request times out after creating a
resource, its result is unknown and a retry could create a duplicate. An existing
agent can instead be selected with `CARTESIA_AGENT_ID`, but it must already have
the three compatible tools described below. The project's existing agent has been
migrated. For another existing agent, use matching local setup state to migrate it
or attach the compatible tools explicitly.

Both phone and Mac must be on the same trusted network. `.env.example` binds this
development service to `0.0.0.0`; omit that setting to use loopback only. Find the
Mac's name with `scutil --get LocalHostName`. In the app's gear menu, enter
`http://that-name.local:8765` as the **Voice server address** and the separate
gateway token as the **Access code**. Allow local-network access and the Mac
firewall connection if prompted. `localhost` on the phone refers to the phone.

Enable **Allow Cartesia voice conversation**, close setup, and tap **Start
practice** before preparing your hands. Thereafter, say done, ask a question,
pause, resume, repeat, read the label, or end session. Bag details are kept across replies. The agent can summarize and advance ordinary
checks conversationally through the new advance tool. The app records
self-reports; it does not verify a prescription or clean technique. Readiness for
camera monitoring stays under native control. The model is bundled, but when
monitoring is unavailable, explicitly saying **continue without camera** advances an unmonitored practice step; it never
records that step as monitored. A possible-contact review flag cannot be bypassed
this way.

The server address is saved on the phone; the access code is saved in its keychain.
Only microphone audio goes to Cartesia. Camera/depth, hand tracking, proximity,
and wristband commands run locally. The gateway creates a short-lived WebSocket
session token; the phone then streams directly to Cartesia. Account-specific call
retention still needs review before using patient information.

## Voice and latency

The selected Cartesia voice handles the ongoing conversation, including questions,
turn-taking and interruptions. Three fixed warning clips are generated and cached
in memory after connection so alerts do not wait for the network. If a clip is not
ready, immediate phone speech is the fallback. A local alert interrupts the cloud
call; after its audio finishes the app opens a new call with current native state.
A cloud failure falls back to phone speech and on-device recognition. Phone voice
can guide checks, but arbitrary questions need a Cartesia connection.

This is a foreground prototype. Backgrounding pauses capture, monitoring and
voice. **Resume voice** is required on return. Paused monitoring must be rearmed
with fresh observations. Neither speech latency nor motor latency has been
measured on hardware here.

## Interfaces and boundaries

- `POST /speak`, Bearer access code, JSON `{"text":"..."}` returns WAV audio.
- `POST /agent-session`, same authentication, JSON
  `{"check_id":"hands","phase":"checking"}` returns a WebSocket URL and one-use token.
- `get_routine_state`: native client tool, no arguments, returns current state and the complete in-session read-back draft.
- `advance_practice_step`: native client tool, `check_id` only; uses the actual captured
  user turn to advance one ordinary check by assistant judgment. This cannot arm/skip
  monitoring, resume a pause or clear review; it records unverified progression.
- `respond_to_check`: native client tool, `check_id` and verbatim `user_words`.
  The app requires a matching unused user transcript for the current check.
  Assistant speech, invented consent and stale replies are rejected. A matching
  late native-command tool call returns current state without repeating the action.

No tool clears review flags, configures prescriptions, or changes clinical
instructions. Generated explanations remain unvalidated. Event logs omit spoken
text, audio and images. Transcripts/read-backs exist in session memory, while
Cartesia may retain cloud call records according to the account configuration.

The service authenticates requests, limits body/response size, serializes upstream
requests, limits them to 20/minute, and suppresses request/provider-error logs.
The `.local` HTTP path is unencrypted and for practice data on a trusted LAN only.
For independent use, deploy an authenticated HTTPS gateway; this Python development
server is not production hosting.

The integration uses Cartesia API version `2026-08-14`, `sonic-3.6` standalone
speech, and 16 kHz mono PCM16 agent audio in 40 ms input chunks. See the official
[agent creation](https://docs.cartesia.ai/api-reference/agents/create),
[client tools](https://docs.cartesia.ai/agents/client-tools), and
[WebSocket protocol](https://docs.cartesia.ai/api-reference/agents/agent-websocket).

Run tests without keys, network access, or paid requests:

```sh
python3 -m unittest discover -s services/voice_gateway -v
```

Tests exercise HTTP parsing, authentication, trusted routine context, sanitized
failures, tool attachment, setup checkpoints and literal local configuration.
The authorized-account smoke test passed for creation, WAV speech, PCM streaming and a synthetic reply/tool exchange. A live phone is still needed to assess voice quality, microphone audio, echo cancellation, interruptions and network recovery. The returned `api-us.cartesia.ai` session host is accepted alongside `api.cartesia.ai`; unrelated hosts remain rejected. Complete speech clips have their streaming WAV lengths finalized before iOS playback.
