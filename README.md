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
BLE feedback, local voice and optional dynamic Cartesia voice Q&A. The original
camera/LiDAR test remains a separate tab. A trained protected-part model is **not
included**; monitoring stays unavailable without one. No printed markers are
needed for these tests.

Full Xcode and a physical LiDAR phone are needed to compile/install and verify the
iOS app. This workspace has only Command Line Tools; app source has been syntax
checked, not built against an iOS SDK. The routine is practice-only until the PD
team's specific protocol and prescription are supplied and reviewed.

The Adafruit motor supports variable intensity through PWM. The updated firmware
retains the original ASCII patterns and adds a separate intensity-v2 characteristic
with a 300 ms receive watchdog. Select the installed firmware protocol in the app;
flash the update before selecting v2. Firmware compilation and motor behavior
still require the actual Arduino toolchain/board.

Vision, alerts and BLE run locally. Dynamic questions optionally use a
[Cartesia gateway](services/voice_gateway/README.md); it keeps the API key off the
phone. Cartesia TTS alone does not answer questions: live Q&A also needs a
configured, published Managed Agent. No live API calls have been made.

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
