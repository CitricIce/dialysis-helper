# ArmGuard PD: Real-Time Sterile Technique Coaching for Home Peritoneal Dialysis

Nov 7, 2026 · @e

> Implementation cross-reference (Nov 7, 2026): [DESIGN.md](DESIGN.md) reconciles
> this proposal with the original design and current firmware. Its current native
> iPhone plan moves capture, tracking, risk, BLE and audio onto the phone; the Mac
> pipeline below is an earlier option. It also covers props, collision rules,
> installation and latency. Monocular overlap is
> suspected contact rather than confirmed touch, and marker pose does not supply
> hand depth. The Adafruit motor supports PWM intensity; the current sketch needs
> intensity reception/PWM added to implement the binary protocol below. Read the
> implementation decisions alongside this original product proposal.

## Summary

ArmGuard PD warns a home peritoneal dialysis (PD) patient a fraction of a second before their finger touches a sterile connector, and logs every exchange for their PD nurse. A webcam tracks the hands with MediaPipe. An upper-arm band buzzes harder as a fingertip nears the sterile tip. A nurse dashboard scores each patient's technique over time.

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

ArmGuard has three parts: a camera that watches the hands, a band the patient feels, and a dashboard the nurse reads.

- **Vision station:** an iPhone used as the Mac's camera through Continuity Camera, mounted face-down above the work surface. It tracks 21 landmarks per hand and the position of each connector tip, and draws an invisible "no-touch zone" around every sterile tip.
- **Haptic armband:** worn on the upper arm, above the elbow, so it stays clear of hand washing and the sterile area. It buzzes harder as a fingertip nears a tip and gives a sharp double pulse on contact. One band per arm, so the buzz lands on the arm that's moving.
- **Audio fallback:** spoken prompts ("Stop. Replace the cap.") for patients who don't wear the band. Audio is the default; the band is an accessibility add-on for patients with hearing or vision loss.
- **Nurse dashboard:** each exchange gets a technique score, a near-miss count, contact events with a short clip, and steps done out of order. Patients are ranked so the nurse knows who needs retraining or a home visit.

### What a patient's exchange looks like

1. **Wash and arm up.** The patient washes their hands, the camera checks wash time, then the patient pulls the armband up over the sleeve.
2. **Set out supplies.** The camera spots the bag, the transfer set and the new cap, and the no-touch zones turn on.
3. **Uncap and connect.** As a finger drifts within about 3 cm of a tip, the band starts a light buzz that gets stronger closer in. If the patient pulls back, it's logged as a near-miss avoided.
4. **Contact.** If a finger reaches a tip, the band gives a strong double pulse and the speaker says to stop and follow the clinic's contamination protocol (usually: replace the part, call the PD unit). The event is flagged on the dashboard.
5. **Drain, flush, fill.** Coaching pauses. The station checks steps happen in order (for example, flush before fill).
6. **Disconnect and cap.** Zones turn back on for the new sterile cap.
7. **Summary.** The patient gets a simple score ("Clean exchange" or "1 contact"). The nurse sees the full record.

## Hardware bill of materials

The prototype runs on a Mac with an iPhone as the camera (Continuity Camera), plus about $25–45 in parts for the armband. Prices are approximate hobby-store prices. The product later moves to a dedicated embedded camera unit with a depth sensor.

| Item | Qty | Purpose | Approx. cost (USD) |
| --- | --- | --- | --- |
| Mac (macOS Ventura or later) | 1 | Runs tracking, zone engine, BLE link, audio prompts and the dashboard | have |
| iPhone (iOS 16 or later) via Continuity Camera | 1 | Overhead camera; shows up as a regular camera on the Mac, no app needed | have |
| Phone mount, face-down (gooseneck or tripod arm) | 1 | Holds the phone 40–60 cm above the work surface | 10–15 |
| LED desk lamp or ring light | 1 | Steady lighting, which helps tracking more than a better camera | have / 10 |
| ESP32 dev board (BLE built in) | 1 per band | Receives buzz commands from the Mac, drives the motor | 6–10 |
| Adafruit Vibrating Mini Motor Disc | 1–2 per band | The buzz. Not a stepper motor. | 2–10 |
| Logic-level MOSFET or 2N2222 + flyback diode | 1 per band | Drives the motor disc from a PWM pin; the motor draws more current than a pin can safely supply | 1 |
| 3.7 V LiPo (500 mAh) + TP4056 charger, or a small USB power bank | 1 per band | Battery power (a coin cell can't handle the ESP32's Bluetooth current spikes) | 8 |
| Elastic Velcro armband or 3D-printed housing | 1 per band | Mounts on the upper arm | 5 |
| ArUco marker stickers (printed) | 4–6 | Reliable tracking of each connector tip | \~0 |
| Plain matte mat | 1 | Plain background so hands stand out | have |
| PD training kit: mock transfer set, caps, water-filled bags | 1 set | Realistic props, never used on a person | borrow from a PD unit or mock with IV tubing |

**Software stack:** Python on the Mac with OpenCV (camera capture and ArUco), MediaPipe Hands, `bleak` for BLE to the ESP32, macOS `say` or pre-recorded clips for audio, SQLite for the event log, and Flask or FastAPI for the dashboard. The ESP32 runs Arduino with NimBLE and a PWM output to the motor.

**Camera setup:** turn on Continuity Camera, lock exposure and focus if the app allows it, use the 0.5× ultra-wide lens if the mount is close, and keep the phone plugged in, since it runs hot during long sessions.

## System architecture

Each camera frame runs through tracking and a zone engine on the Mac, which sets the buzz level live and writes events for the nurse.

&#91;embedded content: ArmGuard architecture · live loop and nurse log\]

The armband is the only part that needs to be fast; the dashboard can update after the exchange.

### Vision pipeline

- **Hands:** MediaPipe Hands gives 21 landmarks per hand. Use the fingertips (landmarks 4, 8, 12, 16, 20) plus the thumb and index pads, since those are what touch connectors.
- **Connector tips:** an ArUco marker on each prop gives its pose. The sterile tip is a fixed offset from the marker, measured once per prop. Later, swap the markers for a trained detector.
- **Depth:** a single camera gives 2D. Use the marker's known size to estimate scale and the hand's apparent size for rough depth. For the demo, a top-down camera makes 2D distance close enough. An Intel RealSense or an iPhone LiDAR feed is an upgrade.
- **Zones:** each sterile tip gets a warning radius (about 3 cm) and a contact radius (about 0.8 cm). Distance inside the warning radius maps to buzz intensity. Starting values; tune them on the props.
- **Debounce:** contact fires only after 3 frames in a row inside the contact radius, about 100 ms at 30 fps, to cut false alarms from tracking jitter.
- **Phase state machine:** idle → hands washed → supplies detected → connect (zones on) → drain/flush/fill (zones paused) → disconnect (zones on) → summary.

### Latency budget (target under 150 ms, finger to buzz)

These are estimates to check against measurements during the hackathon.

| Stage | Estimate |
| --- | --- |
| Camera frame capture at 30 fps | up to 33 ms |
| MediaPipe Hands + ArUco on the Mac | 15–30 ms |
| Zone math + debounce decision | under 2 ms (contact debounce adds about 66 ms) |
| BLE write to ESP32 (short connection interval) | 10–30 ms |
| Motor spin-up (ERM; an LRA is faster) | 20–50 ms |

Measure it end to end: film the finger and the band with a phone in slow motion and count the frames between them.

### Haptic protocol

- **Warning:** continuous buzz, PWM duty 20–100% scaled by distance, refreshed every frame.
- **Contact:** two 150 ms full-strength pulses, 100 ms apart.
- **Message:** one byte for the mode plus one byte for intensity, written to a BLE characteristic. The band stops on its own if no update arrives within 300 ms, so it never gets stuck buzzing.

### Event data model

| Field | Example |
| --- | --- |
| exchange\_id | uuid per exchange |
| patient\_id | pseudonymous id |
| t | ms since exchange start |
| type | near\_miss, contact, step\_out\_of\_order, wash\_short |
| tip | transfer\_set, new\_cap, bag\_port |
| min\_distance\_cm | 1.2 |
| hand | left / right |
| clip\_ref | file id of a 5 s clip (contact only) |

**Technique score per exchange:** start at 100, subtract 25 for each contact, 5 for each near-miss and 10 for each step out of order. The weights are placeholders for a PD nurse to set.

## Software specification

One Python process on the Mac runs the live loop. The ESP32 only obeys buzz commands and shuts itself off if commands stop. The dashboard reads the same SQLite file in a separate process.

### Repo layout

```text
armguard/
  main.py              # starts threads, runs the frame loop
  config.yaml          # all thresholds, marker offsets, BLE ids
  vision/capture.py    # OpenCV capture from Continuity Camera
  vision/hands.py      # MediaPipe wrapper -> fingertip pixels per hand
  vision/markers.py    # ArUco -> sterile tip pixels + px_per_cm
  engine/zones.py      # distance, buzz intensity, debounce, hysteresis
  engine/phases.py     # exchange state machine
  engine/events.py     # event objects + technique score
  haptics/ble.py       # bleak client, latest-command-wins queue
  audio/prompts.py     # macOS `say` or wav clips
  store/db.py          # SQLite writes on a background queue
  dashboard/app.py     # FastAPI + one HTML page
  overlay.py           # debug window: hands, tips, zones, fps, latency
firmware/armband/armband.ino
tests/                 # pytest, synthetic distance traces
```

### Frame loop (main thread, every frame)

1. **Capture:** a capture thread keeps only the newest frame (no backlog). Find the Continuity Camera's device index once at startup and save it in config.
2. **Hands:** MediaPipe Hands, `max_num_hands=2`, model complexity 0 for speed. Keep fingertip landmarks 4, 8, 12, 16, 20 per hand.
3. **Markers:** detect ArUco markers (`DICT_4X4_50`). For each marker id, the sterile tip = marker center + an offset in cm, rotated by the marker's angle (offsets in config). Scale: `px_per_cm = marker_side_px / marker_side_cm`, averaged over the visible markers.
4. **Distance:** for each active tip, `d_cm` = smallest fingertip-to-tip distance in pixels ÷ px\_per\_cm. Remember which hand it was.
5. **Zones:** turn `d_cm` into buzz mode + intensity (rules below).
6. **Outputs:** push the newest command to the BLE queue; trigger audio on a contact; queue events for the database.
7. **Overlay:** draw everything plus fps and per-stage timings (`time.perf_counter()`).

### Zone rules

| Rule | Starting value | Behavior |
| --- | --- | --- |
| Warning radius `warn_cm` | 3.0 cm | Outside it the motor is off |
| Contact radius `contact_cm` | 0.8 cm | Inside it for N frames = contact |
| Debounce `contact_frames` | 3 frames | Stops tracking jitter from causing false contacts |
| Contact exit hysteresis | +0.5 cm | Contact clears only once `d_cm > contact_cm + 0.5` |
| Intensity curve | linear | `i = (warn_cm - d) / (warn_cm - contact_cm)`, scaled to PWM 0–255, minimum 70 so the motor actually spins |
| Near-miss | min d < 1.5 cm | Finger entered the warning zone, got within 1.5 cm, and left without contact |
| Tracking lost | > 300 ms | Hand or tip disappears while inside the warning zone: show it on screen, no buzz, log `tracking_lost` |
| Command rate | at most every 33 ms | Send only when the mode changes or intensity moves by more than 10 |

All values live in `config.yaml` so they can be tuned without code changes.

### Exchange phases

For the hackathon, phases move forward with keyboard keys (space = next phase), so a detection bug can't stall the demo. Detecting phase changes automatically is a stretch goal.

| Phase | Zones | Advance on |
| --- | --- | --- |
| IDLE | off | space |
| WASH | off | space (stretch: hands-in-frame timer of at least 20 s) |
| SETUP | off | all required markers visible |
| CONNECT | on: transfer set tip, bag line tip | space |
| THERAPY (drain, flush, fill) | off | space |
| DISCONNECT | on: transfer set tip, new cap | space |
| SUMMARY | off | write score; press space to reset to IDLE |

### BLE protocol (Mac → ESP32)

- The ESP32 advertises as `ArmGuard-R` or `ArmGuard-L` with one custom service and one write-without-response characteristic. Generate your own UUIDs with `uuidgen` and put them in config and firmware.
- **Payload:** 2 bytes, `[mode, intensity]`. Mode 0 = off, 1 = warn (intensity 0–255), 2 = contact pattern (intensity ignored), 3 = test buzz.
- **Firmware:** mode 1 sets PWM duty with `ledcWrite`; mode 2 plays two 150 ms full pulses 100 ms apart, then waits for the next command. A watchdog turns the motor off if nothing arrives for 300 ms. The onboard LED mirrors the motor, which makes latency testing easier.
- **Mac side:** `bleak` runs in its own asyncio thread. The queue keeps one slot, and new commands overwrite old ones so stale buzzes never pile up. If the band disconnects, reconnect automatically and show "band offline" on the overlay.

### Storage and dashboard

- **Tables:** `exchanges(id, patient_id, started_at, ended_at, score)` and `events(id, exchange_id, t_ms, type, tip, min_distance_cm, hand, clip_ref)`. The event types match the data model above.
- **Clips:** keep a 5 s ring buffer of frames; on a contact, save the last 3 s plus 2 s after it as an mp4.
- **API:** `GET /api/patients`, `GET /api/exchanges?patient_id=`, `GET /api/exchanges/{id}` (events + clip links). The page polls every 2 s, so websockets aren't needed.
- **Demo data:** seed 3 fake patients with a week of exchanges so the patient list looks real next to the live one.

## Hackathon build plan

The plan assumes a 4-person team and a 24–36 hour event, and gets to a working end-to-end loop by hour 12 so the rest of the time goes to polish. Adjust the roles if the team is smaller.

| Role | Owns | Done when |
| --- | --- | --- |
| CV lead | MediaPipe Hands, ArUco tip tracking, zone math, event detection | Fingertip-to-tip distance is stable at 30 fps on the demo props |
| Hardware lead | ESP32 firmware, motor driver, BLE, armband housing | Band responds to intensity commands in under 50 ms |
| Backend / dashboard | Event log, technique score, nurse dashboard UI | A finished exchange shows up scored on the dashboard |
| Pitch + clinical | Research, demo script, slides, PD protocol accuracy, judge Q&A | Story is tight and the demo is rehearsed 5+ times |

### Milestones

- [ ] **Hours 0–4:** hand tracking on webcam; ArUco markers on the mock cap and transfer set; ESP32 buzzing over BLE from a Python script
- [ ] **Hours 4–12:** distance-to-zone mapped to buzz strength; contact event fires; events written to a local database. **First end-to-end loop.**
- [ ] **Hours 12–20:** dashboard with per-exchange score and near-miss timeline; audio prompts; step-order checks
- [ ] **Hours 20–28:** latency tuning and measurement; false-alarm tuning; armband housing; a short clip saved for each contact
- [ ] **Final hours:** rehearse demo, record a backup video, finish slides

**Cut list if behind:** step-order checks, clips, the second band. Never cut the live buzz, which is the whole demo.

## Testing stages

Test from the bottom up: pure logic first, then each part on its own, then the full loop with props. Don't move to the next stage until the current one passes. Thresholds are starting targets; write down what you actually measure.

| Stage | What to test | How | Pass when | Result |
| --- | --- | --- | --- | --- |
| 0. Logic | Intensity curve, debounce, hysteresis, near-miss, scoring, phase transitions | pytest feeding synthetic `d_cm` traces (approach then retreat, jitter around 0.8 cm, dropouts) | All tests pass; a jitter trace never fires a contact |  |
| 1a. Camera | Frame rate and delay from Continuity Camera | Log fps; point the camera at a phone stopwatch next to the Mac screen and compare | 25 fps or more at 1280×720 |  |
| 1b. Hands | Fingertip jitter | Hold a hand still for 10 s and log fingertip position | Std dev under 0.3 cm |  |
| 1c. Markers | Detection and scale | Props under demo lighting; measure a known distance with a ruler | Markers found in at least 95% of frames; scale error under 10% |  |
| 1d. Band | BLE link and firmware | Script that runs each mode; kill the script mid-buzz; power-cycle the band | Every mode works; motor stops within 300 ms of the script dying; reconnects in under 5 s |  |
| 2. Distance accuracy | Measured vs true fingertip-to-tip distance | Printed grid; fingertip at 0, 1, 2, 3 and 5 cm from the tip, 5 times each | Error under 0.5 cm inside 3 cm |  |
| 3. End-to-end latency | Finger enters the zone → motor starts | 240 fps phone slow-motion video of finger, overlay and band LED; count frames; 20 trials | Median under 150 ms; worst case under 250 ms |  |
| 4. Scripted trials | Detection accuracy | 20 clean exchanges, 20 deliberate near-misses, 20 deliberate contacts by 2+ teammates; label each from video | Contacts caught 18/20 or better; at most 1 false contact per 5 clean exchanges; near-misses logged 16/20 or better |  |
| 5. Robustness | Conditions that break CV | Repeat a short stage 4 run with dim light, bright window light, long sleeves, both hands crossing, fast movements, a marker half covered | No false contacts; any tracking loss is shown on screen |  |
| 6. Dashboard | Data comes through correctly | Compare stage 4 video labels against what the dashboard shows | Counts match; contact clips play |  |
| 7. Demo rehearsal | The whole script under stage conditions | Run the demo script 5 times on the presentation table; record a backup video | 5 clean runs in a row |  |

**Tune between stages:** if stage 2 or 4 fails, adjust `warn_cm`, `contact_cm`, `contact_frames` and the marker offsets in config, then rerun stage 0 so the logic tests still pass.

## Demo script (3 minutes)

The moment judges remember is a finger drifting toward the cap, the armband buzzing harder, the hand pulling back, and the dashboard logging "near-miss avoided."

1. **Hook (20 s).** "Meet a 78-year-old on home dialysis, 14 months in, with diabetic retinopathy. One touch on this connector tip can put her in the hospital and end home dialysis for good. Touch contamination is the leading cause."
2. **Clean run (40 s).** A teammate wearing the band does an exchange with the mock kit. The dashboard shows the no-touch zones live over the camera feed.
3. **Near-miss (30 s).** The teammate drifts a finger toward the cap. The buzz builds and they pull back. Point at the near-miss entry on the dashboard.
4. **Contact (30 s).** The teammate touches the tip. Double pulse, spoken prompt, red event with a clip on the dashboard.
5. **Nurse view (30 s).** Switch to the patient list: one patient flagged for retraining after three near-misses this week. "One nurse can supervise a whole panel this way, without driving to each house."
6. **Close (30 s).** Who pays and why (next section), what's next (a pilot with a PD unit), and the measured buzz latency.

**Backup:** a recorded video of the full run, in case the lighting or the BLE connection fails on stage.

## Business case

Dialysis providers pay because ArmGuard lets one nurse supervise many more home patients and keeps those patients on PD. The armband is an add-on; the moat is the technique data.

- **Customer:** home dialysis programs at dialysis providers and hospital-based PD units. Patients use it; the program buys it.
- **Value to the buyer:**
  - Fewer peritonitis episodes means fewer hospital stays and fewer patients transferring to in-center hemodialysis.
  - Nurse time: a technique audit and retraining check happens remotely, after every exchange, instead of only at a home or clinic visit.
  - It widens the pool of patients who can do PD at all. Patients whose vision, dexterity or cognition is borderline, who would otherwise need a caregiver or a paid assisted-PD nurse, get a safety net. The ISPD position paper on assisted PD calls for expanding assisted PD internationally.
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
| "A camera in someone's home is a privacy problem." | It runs only during an exchange and points down at the work surface. Processing happens on the device, and only events and short clips of contacts are uploaded, with consent. |
| "False alarms will annoy patients until they turn it off." | Zones are tuned per tip, a buzz needs several frames in a row to fire, and the near-miss buzz is gentle. Measure the false-alarm rate in testing and show it. |
| "Big players already have patents." | Fresenius has a hand-cleanliness scanning patent. Before going past the hackathon, do a freedom-to-operate search on live connection monitoring. |
| "Lighting and camera angles break CV." | Fixed overhead mount, ArUco markers on props for the prototype, and an on-screen check that the hands are tracked before the exchange starts. |
| "Older patients won't charge another device." | The band is optional; it charges on a dock beside the station, which flags a low battery. |

**Other risks:** we have no real exchange footage to train on (stage it with a training kit, then partner with a PD unit); hand tracking may fail with gloves or tremor (test it); clinic contamination protocols vary (make the prompts configurable per clinic).

## Future work and validation

The next step after the hackathon is a usability and accuracy study with a PD unit, before any outcome claim.

1. **Bench accuracy:** measure contact detection against labeled video of staged exchanges, reporting sensitivity, false alarms per exchange and buzz latency.
2. **Usability with PD nurses and patients:** can patients over 70 set it up alone? Does the buzz help or startle? Use the hand-tracked VR training study as a model for the protocol.
3. **Connector detection without markers:** train a small detector on real transfer sets and caps, using footage collected with consent.
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
