# Optional hosted Cartesia gateway

## Consumer UI, Live Guard and safety summary (November 8)

The app was redesigned for patients rather than developers (code: `LiveGuardView.swift`,
`RoutineCoachView.swift`, `SafetyStats` in `ProximityEngine.swift`).

- **Home:** a setup checklist (tip size, wristband, voice coach; each row opens its
  setup step), a **Live Guard** card, and one **Start guided practice** button. It uses
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

## Camera-distance warnings: on after tip calibration (November 8)

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
for step order, prompts/help and shared `voice` messages. Edit the adjacent
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
Rebuild and open **Settings → Developer tools → Camera + model test**. It runs the actual
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
