# Dialysis Helper

## Earlier features restored and Roboflow model visible again (November 8)

The consumer redesigns had hidden or moved features the team relied on. The Roboflow
model code (`RFDETRDetector.swift`, pipeline detection) never changed and still runs on
every frame, but its output was no longer visible. Restored:

- **Detection labels:** Live Guard and the practice camera preview draw every RF-DETR
  detection again, with class name and confidence (orange tip, green hand, gray other).
  These sit on top of the zones, tip-type labels and gap line.
- **Model panel in Live Guard:** a "Roboflow RF-DETR · N tip · N hand · N fingertips"
  strip with a live/stale dot. Tap it for the model status, box count, frame age,
  processing time and the **detection sensitivity slider** (the placeholder often scores
  below the default 45%).
- **Practice camera details** (capture status, model status, counts, frame age, stale
  warning, preview-confidence slider) are shown openly again, not collapsed.
- **Home:** the **Model test** tile (the original "Test camera + model" screen) is back next
  to Live Guard, and "Set up Cartesia voice for open questions" shows when voice isn't
  configured. Both are also in Settings → Developer tools.
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
- **Home screen:** a greeting and date, a gradient "Ready for your exchange" status card
  with status pills (on-device camera, band, voice) and the **Start exchange practice**
  button, quick-action tiles (Live Guard, Wristband, Connectors), a **Your connectors**
  card, a **Last session** card from real session stats, and a "How ArmGuard works" strip.
- **Limits:** colour identification is a heuristic. A blue drape, coloured light or a
  strong white-balance cast could mislabel a clear tip, so check the on-screen label.
- **Verified:** portable checks (new fixed-size/colour/reference check) and the unsigned
  iPhone build. **Not verified:** colour identification on the real connectors.

## Consumer UI, Live Guard and safety summary (November 8)

The app was redesigned for patients rather than developers (code: `LiveGuardView.swift`,
`RoutineCoachView.swift`, `SafetyStats` in `ProximityEngine.swift`).

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
for step order, prompts/help and shared `voice` messages. Edit the adjacent
`VoiceInstructions.txt` for conversational policy. Rebuild after edits. See
[the editing guide and current diagrams](DESIGN.md#edit-the-voice-prompts-and-routine-flow).
Other agents can run `setup_agent.py` once to add the tool without replacing
unrelated tools/configuration. No account login or new agent ID is required.

38 portable checks, 15 gateway/setup tests, project validation and all 16 Swift
files type-checked against actual Catalyst frameworks passed. Phone microphone,
conversational behavior and iPhone SDK build still need full Xcode/the device.

Prototype only, not a medical device. A camera watches a user's hands during
home peritoneal dialysis setup, and a wristband buzzes to warn them before a
mistake.

The updated [ArmGuard PD product design](<ArmGuard PD Real-Time Sterile Technique Coaching for Home Peritoneal Dialysis.md>)
sets the product direction. See [DESIGN.md](DESIGN.md) for the native iPhone plan,
installation steps, demo props, collision coverage, and latency approach. The
current preferred architecture runs capture, tracking, risk, BLE and audio on
the iPhone; the earlier Mac/Continuity Camera stack remains an alternative.

The [native iPhone prototype](ios/ArmGuardCaptureProbe/README.md) now includes
practice routines, on-device hand tracking, label OCR, a Core ML detector adapter,
BLE feedback and a continuous Cartesia voice conversation with a phone-voice
fallback. Use **Settings → Developer tools → Camera + model test** to run detection without voice,
routine checks or vibration. It needs no Cartesia key or internet. The original
camera/LiDAR hardware test is under Developer tools in setup. The teammate's
RF-DETR Small protected-tip model is included and compiled by Xcode. Its detection
accuracy and usable latency still need testing on actual props. No printed markers
are needed for these tests.

Full Xcode and a physical LiDAR phone are needed to compile/install and verify the
iOS app. This workspace has only Command Line Tools; app sources are type-checked
against Mac Catalyst frameworks, but not built against an iPhone SDK. The routine is practice-only until the PD
team's specific protocol and prescription are supplied and reviewed.

The Adafruit motor supports variable intensity through PWM. The updated firmware
retains the original ASCII patterns and adds a separate intensity-v2 characteristic
with a 300 ms receive watchdog. Select the installed firmware protocol in the app;
flash the update before selecting v2. Firmware compilation and motor behavior
still require the actual Arduino toolchain/board.

Vision, alerts and BLE run locally. Conversational voice connects directly from
the phone to Cartesia by default: enter the authorized API key once in Voice setup;
it stays in the iPhone Keychain. No laptop or local server needs to remain running.
Internet is required for Cartesia. The [gateway](services/voice_gateway/README.md)
is optional for a future hosted setup that keeps a shared provider key off devices.
Conversation also needs Managed Agents access. The included setup command creates
the dedicated agent and tools through the API without the account owner's login. Live agent creation, voice generation, streaming audio and a synthetic spoken-reply/tool loop have passed. Physical iPhone audio and latency still need testing.

## Camera-only debugging (November 8, 2026)

After rebuilding, open **Settings → Developer tools → Camera + model test**. It starts the actual bundled
RF-DETR detector and Apple fingertips, showing boxes, class confidence, LiDAR
status, completed-result rate and frame age. Boxes use the exact analysed frame.
A confidence slider affects only this test; stale results are marked and dimmed.
Stop/Done/backgrounding stops capture, and returning does not restart voice.

For routine testing, open the gear menu > **Developer tools** > **Routine debug
controls**. The main screen then offers a step picker, jump and skip. You can say
“skip this step” in voice practice with that toggle on. Debug moves are logged as
unverified; they never complete checks, arm monitoring or clear contact review.
Pause/resume/end/debug-skip phrases are handled by native code on the received
user transcript rather than waiting for an agent tool call. Pausing interrupts
assistant playback. Physical microphone timing still needs testing.

Local checks passed: 29 portable logic checks, 13 gateway/setup tests, project
validation and all 16 Swift files type-checked against Apple Catalyst frameworks.
An iPhone SDK build and this screen's physical-phone behavior remain unverified.

## Check before installing

Run `bash scripts/check-ios-app.sh` for project validation, logic/gateway tests and
native compilation/type-checking where supported. With full Xcode it builds the
unsigned iPhone app; the Command Line Tools fallback is explicitly partial.
GitHub Actions is configured to require the full iPhone build on relevant
pushes/PRs. See the [test guide](ios/ArmGuardCaptureProbe/README.md#repeatable-checks-before-installing).
No phone or signing account is needed to catch ordinary compile errors.

## Piece 1: Wristband

### Commands

| Send | Meaning | Vibration |
|---|---|---|
| `O` | Step OK | One short tap |
| `W` | Warning | Two medium pulses |
| `E` | Error | Two long pulses |
| `T` | Test | One long pulse |
| `S` | Stop | Motor off |

### Optional variable intensity protocol

The existing ASCII characteristic is `7a1e0002-3c5d-4b8a-9f21-6d2c8e4b1a00`.
The updated sketch also exposes `7a1e0003-3c5d-4b8a-9f21-6d2c8e4b1a00` on the
same service. Send **two bytes**: `[mode, duty]`, where mode is 0 (off), 1
(proximity), or 2 (review cue), and duty is 0–255. Mode 2 uses the supplied duty;
it does not diagnose contact. The phone refreshes at 100 ms intervals and expires
its desired command after 250 ms. Firmware shuts PWM off after 300 ms without a
valid v2 packet, and on BLE disconnect. Reconnection starts off.

Bench-test duty values 80, 150, 220 and 255 for perceptible differences on the
assembled band; perceived intensity is not linear in duty. Stop writes and verify
the watchdog, then disconnect and verify shutoff. The 200 Hz/8-bit PWM setup uses
[ESP32 LEDC](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/ledc.html).
The sketch includes Arduino ESP32 2.x/3.x API branches; neither has been compiled
in this workspace. Existing Serial Monitor tests below still apply.

### Wire the motor

Power the board over USB for now, and leave the battery disconnected.
A GPIO pin can't supply enough current for the motor, so the transistor switches it.

```
3V3 ───────┬───────────────┐
           │               │
        (motor +)      diode cathode (striped end)
        (motor -)      diode anode
           │               │
           └───────┬───────┘
                   │
               collector
GPIO4 ── 1kΩ ── base         NPN transistor (such as 2N2222)
               emitter
                   │
GND ───────────────┘
```

Before powering on, check these three things:

1. **Transistor pins:** Check the datasheet, because the order differs even
   between similar parts. For example, the 2N2222A and PN2222A differ.
2. **Diode direction:** The striped end goes to 3V3. If it's backwards, it
   shorts the supply whenever the transistor turns on.
3. **Shared ground:** The emitter must connect to the board's GND.

If your board labels pins differently, find the one that maps to GPIO4 on its
pinout. For example, GPIO4 is `D2` on a XIAO ESP32C3. To use another pin, change
`MOTOR_PIN`, but avoid GPIO 2, 8 and 9.

### Upload the firmware

1. In Arduino IDE, open **Settings** and add this to **Additional Boards Manager URLs**:
   `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
2. In **Boards Manager**, install **esp32 by Espressif Systems**.
3. Open `firmware/wristband/wristband.ino`.
4. Select your board: **XIAO_ESP32C3**, or **ESP32C3 Dev Module** for most other boards.
5. If your board's USB port connects directly to the chip, set
   **Tools > USB CDC On Boot > Enabled**. Otherwise the Serial Monitor stays blank.
6. Click **Upload**. If it can't connect, hold **BOOT**, tap **RESET**, release
   **BOOT**, then try again.

### Test it

| # | Test | Expected result |
|---|---|---|
| 1 | Press **RESET** | One short buzz |
| 2 | In Serial Monitor at 115200 baud, send `W`, `E`, `O` and `T` one at a time | Each pattern feels different, and the monitor prints `cmd W` and so on |
| 3 | In nRF Connect on your phone, scan and connect to `DialysisBand` | The Serial Monitor prints `ble connected` |
| 4 | Find the characteristic starting `7a1e0002`, tap the write arrow, and send `W` as text | Two medium pulses |
| 5 | Disconnect, then reconnect | `DialysisBand` reappears and commands still work |

If your app only offers hex, send `57` for `W`.

### If something fails

| Symptom | Likely cause |
|---|---|
| No buzz, and Serial Monitor works | Transistor pins, wrong GPIO or missing shared ground |
| Motor runs constantly | Transistor pins are wrong, or collector and emitter are swapped |
| Board resets when the motor starts | Check the diode direction, and check that the motor isn't drawing too much |
| Serial Monitor is blank | USB CDC On Boot is off, or the baud rate is wrong |
| `DialysisBand` doesn't appear | Press **RESET**, and disconnect it from any other device |

### Add the battery after these tests pass

- Only connect a LiPo if your board has a battery connector or pads with a
  charging circuit, such as the XIAO ESP32C3.
- Don't connect a LiPo to the `3V3` pin. A charged cell reaches 4.2V, which can
  damage the chip.
- Check the polarity first, because connector colors aren't standardized.
- If your board has no battery input, use a USB power bank for the demo.
