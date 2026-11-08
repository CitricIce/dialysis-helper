# Optional hosted Cartesia gateway

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
Rebuild and tap **Test camera + model** on the home screen. It runs the actual
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
