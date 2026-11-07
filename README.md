# Dialysis Helper

Prototype only, not a medical device. A camera watches a user's hands during
home peritoneal dialysis setup, and a wristband buzzes to warn them before a
mistake.

The updated [ArmGuard PD product design](<ArmGuard PD Real-Time Sterile Technique Coaching for Home Peritoneal Dialysis.md>)
sets the product direction. See [DESIGN.md](DESIGN.md) for the native iPhone plan,
installation steps, demo props, collision coverage, and latency approach. The
current preferred architecture runs capture, tracking, risk, BLE and audio on
the iPhone; the earlier Mac/Continuity Camera stack remains an alternative.

The iPhone and Mac applications are planned, not implemented. The Adafruit motor supports
variable intensity through PWM; the current firmware below uses fixed on/off
patterns. Receiving an intensity value and driving PWM is a firmware update,
not a motor replacement.

## Piece 1: Wristband

### Commands

| Send | Meaning | Vibration |
|---|---|---|
| `O` | Step OK | One short tap |
| `W` | Warning | Two medium pulses |
| `E` | Error | Two long pulses |
| `T` | Test | One long pulse |
| `S` | Stop | Motor off |

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
