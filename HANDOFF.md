# Handoff: hand-to-sterile-tip proximity warnings (RF-DETR + vibration band)

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

## Camera-only debugging, November 8, 2026

The home screen now has **Test camera + model** without voice setup. It runs the
bundled RF-DETR + Apple fingertips + sceneDepth in `ModelDebugController`, with
paired analysed-frame boxes, class confidence, threshold control, fingertip dots,
model status, result rate, processing duration and frame age/depth diagnostics.
It has no speech, routine or band client; parent voice/monitoring pauses on entry.
Stop/Done/background cancels capture. Permission callbacks are cancelled logically
on Stop, preventing a late grant from reopening a closed test. Debug gaps expire
at 250 ms; boxes dim/mark stale at one second or Stop. Production confidence stays
45%; debug settings are separate. Preview rendering adds debug-only work beyond
the reported inference pipeline time; source-frame age includes delivery/rendering.

Developer tools > **Routine debug controls** enables manual jump/skip on the main
screen and explicit spoken skip phrases. Moves log unverified debug evidence,
clear pending read-backs and never complete checks or arm monitoring. Review
flags stay latched. Voice reconnects after debug navigation only if already on.
Pause/resume/end/debug-skip commands dispatch natively on a real received user
transcript; late matching tool calls acknowledge state without repeating them.
Pause now interrupts the speaking agent. Instructions/state expose debug mode.
No server or account/agent reconfiguration is needed for camera-only testing.

Checks passed: 29 portable logic checks, 13 gateway/setup tests, project/source
membership and all 16 Swift files type-checked against actual Catalyst frameworks.
No iPhone SDK build or physical phone test was possible here. Rebuild and follow
[the camera/model test matrix](ios/ArmGuardCaptureProbe/README.md#camera--model-first-phone-test),
including denied permissions, stopping/backgrounding, overlay alignment on real
props and sustained frame age. Voice command/microphone latency still needs testing.
Model weights, signing settings and firmware are unchanged by this update.

## Integration review, November 7, 2026

The newer working tree integrates commit `60595b5` with the hands-free Cartesia
routine. The notes below describe the original teammate implementation; this
section supersedes its decoder, warning-loop and voice-setup details.

- Model is bundled in the target. Learned weights are unchanged. Added explicit
  metadata for logits, normalized boxes, reserved slot 0 and exact class roles.
- RFDETRDetector now lives in its own Swift file. It validates tensor contracts,
  names outputs explicitly, applies sigmoid without heuristics and reuses input
  storage. Hand boxes are diagnostic; Apple Vision supplies fingertip coverage.
- Removed the parallel timer that could send band commands while paused. Banner,
  phone feedback, speech and band follow the native armed routine. The uncalibrated
  10 mm image-scale assumption no longer drives alerts or presents millimetres.
- Kept the conversational UI and natural spoken check replies. Direct iPhone-to-
  Cartesia access is now default, with the user-entered API key in Keychain. Voice
  and agent IDs are prefilled. The laptop gateway is stopped and optional.
- The alternate vibration sketch now honors zero/variable v2 duty, cancels test
  buzzes on stop/disconnect and bounds legacy warnings. Firmware still needs the
  actual Arduino compiler/board test.
- Regression checks cover decoder/background/class roles, paused/stale gating,
  calibration loss, direct HTTPS request construction and WAV finalization.
- Validation passed: 26 portable logic checks, 13 gateway/setup checks, all 15
  Swift sources type-checked with Apple Catalyst frameworks, and actual Mac Core ML
  compile/load, RGB/portrait/normalization/input-reuse and prediction/decoding tests.
  Warm Mac CPU processing was 187.4 ms on the generated test pattern; this is not
  a phone or end-to-end latency result. Boxes may validly extend outside the image
  and are clipped rather than guessed to be pixel coordinates.
- Direct native Cartesia speech, streaming WAV finalization, session creation,
  WebSocket readiness and agent audio passed with the laptop gateway stopped.
- Full Xcode/iPhone compilation, actual-prop detection accuracy, microphone/echo
  behavior and physical warning latency remain unverified in this workspace.


## Historical teammate notes (superseded by the integration reviews above)

The remaining notes preserve the original implementation/export history. Their
uncalibrated 2D warning method, UI description, uncommitted status and build status
are historical; do not use them as current setup or verification instructions.

Paste into Claude Code: "Read HANDOFF.md and continue from Open work."

Landed on `main` in commits `6a2f2ba` and `4411fcc` (2026-11-07). **Nothing here has been compiled or run yet**:
the session that wrote it had no Xcode/Swift toolchain and no hardware. First job: build it.

## Goal
The iOS app (`ios/ArmGuardCaptureProbe`) watches a home peritoneal-dialysis exchange with the rear camera.
A Roboflow RF-DETR model (`d-s-workspace/dialysis-connector-tip-safety-1-rfdetr-small-t1`) detects
hands and the sterile catheter/connector tips. The app measures hand-to-tip distance, shows a
**MEDIUM** or **HIGH** risk warning, and tells the ESP32 wristband over BLE to vibrate.

## Distance method (ported from the user's SPINOSAURUS.py tumor/nerve script)
1. mm-per-pixel = known sterile-tip size / tip size in pixels (largest tip box), EMA alpha 0.20.
2. Distance = pixels from each fingertip to the nearest edge of each tip box (like
   `cv2.pointPolygonTest`), times mm/px, EMA alpha 0.25. A fingertip inside a box = 0 mm, reported
   immediately (no smoothing). If no fingertip is visible, it falls back to box-to-box distance from the
   model's whole-hand boxes.
3. HIGH <= 30 mm, MEDIUM <= 80 mm. The user didn't choose these; they are defaults.
This is a 2D image measurement. The older LiDAR path (`ProximityEngine.evaluate`, single 50 mm warning,
used by the "monitoring" routine phase) is unchanged and still runs alongside it.

## Files
| File | What changed |
|---|---|
| `Core/Sources/CaptureProbeCore/ProximityEngine.swift` | Appended `RiskLevel`, `ScaleProximity.measure`, `ScaleRiskTracker` (constants: `sterileTipSizeMM`, thresholds, alphas) |
| `ArmGuardCaptureProbe/CoachVisionPipeline.swift` | `RFDETRDetector` class (bottom of file); loader picks RF-DETR vs Vision/NMS model; loose class-name matching `classify(_:)`; hand boxes; fills `scaleRisk`, `distanceMM`, `mmPerPixel`, `closestHand/Surface` on `CoachVisionSnapshot`. Confidence threshold lowered 0.6 -> 0.45 (affects LiDAR path too). |
| `ArmGuardCaptureProbe/CoachViewModel.swift` | `riskLevel` (valid for 0.5 s after a result), `scaleText`, `driveRiskAlerts()` called per result (via `defer`) and every 100 ms: drives the band, haptics, spoken HIGH alert (4 s cooldown) |
| `ArmGuardCaptureProbe/RoutineCoachView.swift` | Banner pinned via `.safeAreaInset(edge: .top)`; green hand boxes + cyan closest-gap line + mm label on the camera preview; debug line |
| `firmware/vibration_band/vibration_band.ino` | New sketch (old `firmware/wristband/` untouched). Pin 4, `analogWrite`. MEDIUM = 250/250 ms pulses at 200, HIGH = continuous 255 |
| `scripts/export_rfdetr_coreml.py` | Downloads weights from Roboflow, exports Core ML fp16 to `ArmGuardCaptureProbe/SterileParts.mlpackage`, writes class names + output names into model metadata, and with `--image` compares on-device-style decoding against `rfdetr.predict` |

No new Swift files were added, so `project.pbxproj` needed no edits (`scripts/check-ios-project.py`
requires every .swift file to be in the target).

## Model integration details (RFDETRDetector)
- Loaded from `Bundle.main` as `SterileParts.mlmodelc` (Xcode compiles `SterileParts.mlpackage`).
- Input: the first MultiArray input, shape (1,3,R,R). Frame -> `CIImage.oriented(.right)` (upright portrait)
  -> stretched to R x R -> RGB /255 -> ImageNet mean/std -> NCHW. Handles float32/float16/double.
- Outputs: dets (1,Q,4) normalized cx,cy,w,h; labels (1,Q,C). A sigmoid is applied if values fall outside
  [0,1]. Argmax per query, threshold 0.45, no NMS. Output names come from metadata
  (`dets_output`/`labels_output`); fallback: the output whose last dim is 4.
- Class names come from metadata `classes` (JSON {"index": "name"}); else `class_<i>`.
- Boxes: portrait top-left -> converted to Vision bottom-left -> the existing sensor-space conversion.
  Sensor<->display mapping used throughout: display x = 1 - sensor.y, display y = sensor.x.
- Unverified assumptions (Roboflow docs don't state them): input is MultiArray, not image; no
  normalization baked into the model; dets normalized cxcywh; labels are logits; class index has no
  offset. The export script's `--image` check is how to confirm.

## BLE protocol (unchanged in `BandClient.swift`)
Service `7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00`, device name `DialysisBand`.
- Legacy (app picker "Existing fixed patterns", default), char `...0002`: `W` medium, `E` high, `S` stop,
  `T` test. Phone writes only on change, then `S` once `set()` expires (250 ms).
- v2 (picker "PWM intensity v2"), char `...0003`: `[mode, duty]`, 0 off / 1 medium / 2 high, resent
  every 100 ms. The firmware watchdog turns it off after 300 ms of silence.
- App mapping: MEDIUM -> `band.set(intensity: 160)`, HIGH -> `band.set(intensity: 255, suspected: true)`.
- Works on ESP32 / S3 / C3. **The ESP32-S2 has no Bluetooth.** The user hasn't confirmed which board they have.

## Model checkpoint facts (inspected from weights.pt, 132 MB)
- RF-DETR Small: 512 px input, 300 queries (3900 = 13 groups x 300), DINOv2-style backbone.
- **3 class slots, and `args.class_names` is None.** Confirmed by the user: id 1 = `Hand`, id 2 =
  `Sterile_connector_tip`; id 0 is Roboflow's reserved slot (`_roboflow_placeholder`).
- Re-export (Python 3.12 venv at `.venv`, gitignored; system Python 3.9 is too old for rfdetr):
  `.venv/bin/python scripts/export_rfdetr_coreml.py --weights <weights.pt> --classes 'Hand,Sterile_connector_tip' --image <photo>`

## Done (2026-11-07, second session)
- **Build:** compiled clean with Xcode 27.2; `bash scripts/check-ios-app.sh` passes. No fixes were needed.
- **Export:** `SterileParts.mlpackage` (fp16, 55 MB) is in `ArmGuardCaptureProbe/`. Input `tensors` MultiArray
  (1,3,512,512); outputs `concat_2` (1,300,4) boxes normalized 0..1 and `linear_112` (1,300,3) raw logits
  (so the app's sigmoid path applies). Class names and output names are in the metadata.
  Mapping: Hand -> HAND, Sterile_connector_tip -> STERILE SURFACE.
- **Verified vs PyTorch** on a random input: the same top boxes come out (median L1 0.008), in a
  different query order (fp16 changes the top-300 selection; harmless, since the app uses no NMS or ordering).
  rfdetr 1.12 / torch 2.15 / coremltools 9 (coremltools warns torch 2.15 is untested; the outputs matched).
  **Not yet checked on a real photo:** run the `--image` check above.
- **Xcode:** the model is in the target's Sources phase (builds to `SterileParts.mlmodelc` in the app).
  `scripts/check-ios-project.py` now accepts `*.mlpackage` in Sources.
- **Not committed yet:** the model package and the pbxproj/check edits. CI fails the "missing file" check if
  the pbxproj references the model but the model isn't committed. 55 MB fits under GitHub's 100 MB limit.

## Open work (in order)
1. Run the `--image` check on a real exchange photo; confirm the reference and app-decoding lists match.
2. On a phone, confirm the debug line shows `512px · classes: ...` (not "metadata missing").
3. Measure the real catheter-tip size and set `ScaleRiskTracker.sterileTipSizeMM` (currently a 10 mm placeholder).
4. Flash `firmware/vibration_band/vibration_band.ino` (ESP32 Arduino core 2.x+ for `analogWrite`). Test
   over serial (`W`/`E`/`S`/`T` at 115200), then from the app: Connect, then trigger warnings.
5. Tune the thresholds with the user. Consider hysteresis if the banner flickers at boundaries.
6. Optional: add `ScaleProximity` / `ScaleRiskTracker` cases to `Core/Checks/main.swift`.

## Notes
- `SPINOSAURUS.py` (not in the repo) contains a plaintext Roboflow API key. The user should rotate it if it was shared.
- The user had uncommitted edits to `project.pbxproj` and an untracked `project.xcworkspace/` before
  this work. Those are theirs; they weren't part of this commit.
