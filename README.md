# Dialysis Helper

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
fallback. Use **Test camera + model** on the home screen to run detection without voice,
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

After rebuilding, tap **Test camera + model**. It starts the actual bundled
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
