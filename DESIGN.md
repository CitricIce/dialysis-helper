# ArmGuard PD: software and feedback design

Status: prototype source updated November 7, 2026. The
[native iPhone app](ios/ArmGuardCaptureProbe/README.md) now has practice routines,
hand tracking, OCR, a Core ML detector adapter, BLE and voice integrations.
Monitoring requires a trained protected-part model, which is not included.
The firmware has legacy and PWM-v2 interfaces. Portable logic and mocked gateway
checks run here; full Xcode, iOS compilation, live Cartesia and hardware validation
remain outstanding. The earlier Mac application remains unimplemented.

The updated [ArmGuard PD product design](<ArmGuard PD Real-Time Sterile Technique Coaching for Home Peritoneal Dialysis.md>)
sets the product direction. The current preferred implementation runs capture,
tracking, risk, BLE and audio on the iPhone. The native plan below supersedes the
earlier Mac-primary execution/stack sections, which are retained as alternatives.
Prop geometry, exposure rules and bench-validation requirements apply to either
implementation. [README.md](README.md) documents existing firmware and wiring.

## Current iteration: routines and dynamic voice

This section supersedes the marker-first and prerecorded-only choices in the
earlier native-stack table below. The user now prefers Roboflow/YOLOv8 protected
surface detection, optionally custom hand/fingertip labels, with Apple hand tracking
as fallback. The existing ARKit capture path remains in use. ArUco is an alternative
for a constrained prop demo, not a required dependency of this iteration.

| Component | Implemented direction | Limits / configuration |
| --- | --- | --- |
| Routine engine | Versioned JSON checks, practice slots, self-reports, selective read-back + confirmation, pause/rearm/review states | Four slot names are examples, not a prescribed daily schedule; no fluid prescription or clinic protocol configured |
| Capture | Rear RGB + sceneDepth from the same ARFrame; portrait only | iPhone 15 Pro target; depth at small edges still needs validation |
| Hands | Custom fingertip boxes when present; Apple Vision adds missing candidates and supplies fallback | Whole-hand centroids cannot substitute for nearest fingers. Two hands with all five confident Apple tips each are a conservative arming/clearance gate |
| Protected objects | Optional `SterileParts.mlmodelc` via Vision/Core ML | Exact exposed-surface labels, NMS object outputs; no trained model supplied and no fabricated detections |
| Proximity | Fingertip-to-nearest-projected-region boundary, then depth unprojection | Experimental point-to-box-boundary estimate, not a true 3D surface minimum or physical-contact measurement |
| Wristband | CoreBluetooth; legacy patterns or PWM-v2 duty | Matching firmware required. One connected band, no left/right routing yet |
| Immediate warnings | Local AVSpeechSynthesizer, BLE and display | No cloud round trip in hazard path; voice repetition limited to once per five seconds |
| Routine speech | Local speech by default; optional gateway Cartesia TTS | Generated per prompt; not fixed clips. Eight-second network timeout then local fallback |
| Questions | Opt-in streaming Cartesia Managed Agent through server-created session | Needs configured agent/voice/API access; generated explanations are not clinically verified. No app-state tools; remote transcripts never enter the routine engine |
| Other visual support | One-shot Apple text recognition for visible bag labels | Suggestions only; no automatic prescription match, color-based strength inference or automatic check completion |
| Events | Local timestamp/type/evidence JSON; export by user | No audio, images, free-text read-backs or automatic nurse upload. No cleanliness score |

### Checks that encourage attention

Use one short action at a time, ask for a concrete action report, and use read-back
at consequential decision points such as supply selection and protected surfaces.
Offer Explain, Repeat, Pause and questions without shaming the user. Phrase
teach-back as checking the explanation, rather than testing the patient. This is
consistent with [AHRQ teach-back guidance](https://www.ahrq.gov/health-literacy/improve/precautions/tool5.html).
A specific PD voice-agent flow has not been established as the single most
psychologically effective design, and no interaction can force attention or prove
an action was performed. The current response-length/uncertainty rules are simple
interaction gates, not semantic or clinical verification.

Avoid a string of yes/no prompts, mandatory long quizzes, arbitrary repeated
confirmations and rewards for speed. The practice engine rejects bare yes/done,
common uncertainty phrases and common question forms. Questions use their own
mode and leave the current check open. Supply/protected-surface read-backs require
an additional exact confirmation; they are still self-reported. Test this design
against yes/no prompts on props: measure omissions, recall after interruptions,
false completion, response time, requests for help, warning frequency and perceived
burden. Include PD nurses and intended users before choosing the final flow.

The bundled order is room → supplies → mask → hands → protected-surface read-back
→ practice connection monitoring → clinic-directed exchange steps → disconnection
preparation → practice disconnection monitoring → review. It is a UI scaffold,
not an approved technique sequence. Handwashing/drying/sanitizer timing, mask use,
exit-site care, treatment timing and fluid selection must come from the actual
clinic/equipment instructions. Do not turn examples such as “skip sanitizer after
washing” or “bar soap is wrong” into universal rules. For example, one
[NHS manual-exchange guide](https://www.hey.nhs.uk/patient-leaflet/peritoneal-dialysis-information-booklet/)
includes later hand disinfection and permits positioning the drain bag on the
floor. Protect exposed openings; a floor rule for every bag or tube would be wrong.
The phone view also cannot verify that the room's fan/AC is off, hands are clean,
or a mask is worn. No such visual check is claimed.

### Other checks and useful haptics

Label OCR and fingertip-coverage checks work without training a new model. A future
barcode/QR-to-product catalog could aid identification, but needs the actual
manufacturer codes and a prescribed order to compare against. Mask detection,
fan state and hand cleanliness must not be inferred from an overhead hand view.
A future camera-quality check could prompt repositioning for blur or glare, with
its own validation rather than claiming it verifies technique.

Use the band for a deliberate connectivity/perception test before preparation,
proximity intensity and an experimentally distinct loss-of-monitoring cue after
usability testing. The current build implements the test pulse, proximity and
local spoken loss cue; no separate loss haptic is implemented. Wrist vibration
alone cannot measure handwashing, rubbing coverage or cleanliness. An IMU-based
hand-motion check would require additional sensing/validation and would still be
a timing/motion observation, not a cleanliness test. Avoid buzzing for every
routine acknowledgment until users can distinguish cues and tolerate the burden.

### Props, labels and model handoff

Use dry, disconnected practice connectors/caps, a mock bag with legible product,
strength, volume and expiry, a matte work surface, a rigid overhead mount and a
ruler. Do not use a patient-connected set. Print markers only if choosing the
separate marker-based geometry approach; this Core ML path does not need them.
Start with generously visible mock protected openings for a bench demonstration,
then measure performance on actual-size props before claiming it generalizes.

Annotate the **exposed opening/interior**, not the whole cap or connector body:
`sterile_tip`, `cap_interior`, `connector_opening`. Optional labels are `fingertip`,
`thumb_tip`, `index_tip`, `middle_tip`, `ring_tip`, `little_tip`. If annotating whole
hands too, those boxes may support coarse alerts later, but their centroids are
ignored for fine proximity. Custom fingertip candidates are merged with confident
Apple tips so a single custom detection cannot hide missing fingers. Unknown
protected objects have no Apple fallback: lack of detections is unavailable.

Train/export the chosen YOLOv8 variant in your Roboflow/Ultralytics workflow, check
Core ML export availability for that model/account, and export with NMS so Vision
returns `VNRecognizedObjectObservation`. Add the model to the Xcode app target and
name it `SterileParts` (Xcode compiles it to `.mlmodelc`). See the
[official Core ML export guide](https://docs.ultralytics.com/integrations/coreml/).
Validate the exact export, input preprocessing, class names, orientation and boxes
on device. Training and conversion are not implemented by the adapter. Split
validation by recording/session and include occlusion, sleeves, skin tones,
lighting, clutter, rotation, capped vs exposed parts and negative examples.
Measure protected-surface recall and fingertip localization, not only mAP.

### Experimental timing and failure behavior

Capture requests 30 fps where available. Vision accepts at most 15 fresh frames
per second, one inference in flight including main-queue delivery; busy frames are
dropped. Preview rendering has its own worker at at most 10 Hz. A result older
than 250 ms by ARFrame capture timestamp is unusable. A 100 ms timer also checks
stalls while armed. Model loading, OCR, audio, disk and network never wait in the
camera delegate; OCR is requested only while checks are open. Avoid scanning during
critical movements because it still shares the vision worker.

The initial warning band is 50 mm and mixed-depth rejection threshold is 20 mm;
these are configurable-in-code experimental defaults, not measured precision.
Reject invalid/low-confidence or mixed-edge patches and protected regions under
two depth pixels wide/high. These filters cannot eliminate all depth leakage.
Warn immediately on a usable near pair, increase duty as estimated distance
shrinks, and require 300 ms of observed separation before releasing a warning.
Missing coverage/depth or stale frames pause monitoring and send off. A projected
overlap becomes a sticky review state; it is not a zero-gap measurement. No
velocity prediction, contamination classification or validated mating-pair
exception exists yet. Other body parts, clothing, tip-to-table/floor and untracked
object collisions remain uncovered. The app must not be presented as protecting
against all of them.

Measured pipeline duration is displayed, but it excludes some sensor delivery,
BLE scheduling and motor mechanics. Before setting a latency claim, bench-measure
capture-to-decision age distributions and physical motor/audio onset under motion,
loss/recovery and sustained thermal load. The prior under-150-ms goal is a target,
not a result. PWM-v2 host commands expire after 250 ms; firmware receives a 100 ms
heartbeat and shuts off after 300 ms without one. Lost observation is a distinct
pause message; silence never proves clearance.

Dynamic Q&A uses streaming audio and can be interrupted. The current UI permits
starting it only in checking/paused phases, so conversation cannot distract from
an actively monitored connection. It cannot advance checks or clear review flags.
Cloud speech may fail; offline Explain and local warning speech remain available.
See [gateway setup](services/voice_gateway/README.md). No real API calls or model
inferences have been verified here, and prompts alone cannot guarantee safe LLM
answers. Clinical content and agent behavior require review before patient use.

## Scope and reconciliation

There are two programs:

1. **Native iPhone app:** capture RGB/depth, locate protected surfaces and nearby
   hazards, estimate risk, transmit vibration intensity directly to the band,
   and speak a relevant prompt. A Mac is for development and optional later logs.
2. **ESP32:** receive commands and drive the motor. Vision and rules stay on phone.

Current work focuses on the first program. Its central rule is **protect an
exposed sterile surface from an inappropriate collision**, whether the hand or
connector is moving. Entering a tray zone is supporting evidence, not proof of an
exchange step or contamination. The table records the earlier Mac design
reconciliation; see the native implementation decision immediately below it.

| Topic | Earlier DESIGN / README | Updated product design | Implementation decision |
| --- | --- | --- | --- |
| Camera | Overhead USB webcam | iPhone Continuity Camera on Mac | iPhone primary; USB webcam as a measured fallback |
| Target | Hands in fixed tray zones | Fingertips near moving sterile tips | Track protected surfaces on props; retain fixed zones for visible environmental hazards |
| Sequence | Sanitizer / supplies / connector | Connect and disconnect phases | Manual phase/exposure controls first; hand presence does not verify washing or connection |
| Contact | Entering a forbidden zone | 0.8 cm radius for three frames | Report projected proximity / suspected contact; monocular overlap cannot confirm touch |
| Geometry | Clicked image regions | Marker offset and averaged pixels/cm | Calibrated planar geometry for constrained demo; calibrated marker pose for tilted props, with hand-depth limits |
| Model | MediaPipe, unspecified API | Legacy Hands with model complexity 0 | MediaPipe Tasks Hand Landmarker; legacy options are not Tasks options |
| Band | Wristband, fixed patterns | Upper-arm band, variable intensity | Neutral band interface; mounting is a hardware/usability decision |
| BLE | DialysisBand, ASCII commands | ArmGuard-L/R, binary commands | Adafruit motor supports PWM; updated sketch adds intensity-v2 alongside legacy patterns |
| Timing | No budget | Under 150 ms, contact debounce | Warn immediately on usable risk; event confirmation must not delay warning |
| Tracking loss | Unspecified | No buzz after 300 ms | Protection unavailable, distinct pause prompt, expire commands; missing detection is not clearance |
| Dashboard | Future | Scores, clips, patient ranking | After the live loop works; keep outside the decision path |

The product document's clinical sequence, infection-reduction claims and scoring
weights require validation. Geometry does not establish sterility or prove a
clean exchange.

## Preferred implementation: native iPhone, no live computer link

The first capture milestone is now in `ios/ArmGuardCaptureProbe/`: an ARKit
scene-depth test with live RGB, a depth visualization and diagnostics. No markers,
inference model or band are needed for this milestone. It uses ARKit's paired
camera/depth frames rather than the proposed direct AVFoundation pipeline below;
the eventual app can compare the two after hardware capture is established.

The user proposes building the app and running inference locally. Adopt this
direction for the next implementation, targeting an iPhone 15 Pro if available.
Its rear LiDAR/main-camera combination is a capture candidate, not evidence of
contact-detection accuracy. The standard iPhone 16 can separately test front
TrueDepth; do not silently substitute RGB-only operation for validated depth.

```text
iPhone RGB + depth
  → on-device hand and prop observations
  → registered geometry + exposure/risk rules
  → CoreBluetooth → ESP32 → PWM vibration
  → phone speaker + local event log

Mac: build/install/debug; optional later event export or dashboard
```

This removes RGB/depth encoding, transport and host decoding from the live loop.
It does not establish a latency result: measure phone inference, depth validity,
BLE, motor onset and sustained thermal performance on the actual device. No
Record3D purchase, Apple-hosted inference or live Mac receiver is required for the
local vision/alert path. Optional dynamic voice uses the gateway described above.

| Layer | Native choice | Design consequence |
| --- | --- | --- |
| App/UI | Swift + SwiftUI, native camera preview/overlay | One foreground screen with readiness, arm/stop, calibration and manual phase controls |
| Earlier RGB/depth option | AVFoundation video/depth outputs and AVCaptureDataOutputSynchronizer | Process paired frames with timestamps and calibration; begin from Apple's capture sample |
| Hand model | Vision VNDetectHumanHandPoseRequest, maximumHandCount=2 | Built-in hand-pose detection; no custom training or Python runtime; validate this detector rather than assuming MediaPipe results transfer |
| Alternative prop markers | ArUco via OpenCV iOS and a thin Objective-C++ bridge | Preserve existing marker IDs and measured prop profiles; native integration is work but requires no model training |
| Marker simplification, optional | Native Vision QR detection on rigid flags | Alternative if avoiding OpenCV is important; requires different printed tags and validated corner/pose handling, not an ArUco-compatible drop-in |
| Coordinates/risk | Swift geometry with calibrated depth and marker transforms | Same boundary-clearance, exposure, uncertainty, loss and review semantics as this document |
| Band | CoreBluetooth central directly to ESP32 characteristic | Preserve explicit legacy versus intensity-v2 modes, freshness, heartbeat and watchdog contract |
| Earlier audio option | AVAudioPlayer preloaded clips; AVSpeechSynthesizer fallback | Priority/cooldown worker; speech must not block vision |
| Log | Small local Codable event records on a background writer | Export summaries later; no dashboard/network dependency for alerts |

Apple documents [hand-pose detection](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest),
[synchronized LiDAR capture](https://developer.apple.com/documentation/avfoundation/capturing-depth-using-the-lidar-camera),
and [BLE central communication](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/PerformingCommonCentralRoleTasks/PerformingCommonCentralRoleTasks.html).
Vision hand joints are image observations, not automatically metric 3D coordinates.
Register RGB, depth and marker geometry into a common coordinate space. Reject
invalid/edge-mixed/background depth samples rather than treating them as safe.

Use a latest-only synchronized frame slot and one inference worker, with UI, BLE,
audio and disk I/O scheduled independently. Initial capture target is 30 fps;
infer as quickly as validated, discarding backlog. Keep depth filtering under
measurement because smoothing can add delay at moving boundaries. Log capture
presentation times, inference time, decision age and output dispatch. Camera
permission, Bluetooth permission/state and required calibration are explicit
readiness gates. No microphone permission is required merely to speak a prompt.

The first app is foreground-only. Keep it awake while explicitly armed; on
backgrounding, capture interruption or loss of valid observations, disarm, clear
pending intensity, send OFF if possible and retain review flags. On resume require
readiness/rearming. Do not assume background Bluetooth keeps camera tracking alive.

### Development install on the teammate's phone

The user confirmed the phone and development Mac will be together. Use **direct
Xcode installation by cable**:

1. Install full Xcode with an iOS SDK/device support compatible with the phone's
   installed iOS. This workspace currently has only Command Line Tools selected;
   no Xcode app was found in the usual application folders. An iOS build and
   hardware validation cannot be performed with that setup alone.
2. Open the project, sign into an Apple Account in Xcode and select the appropriate
   team with automatic signing and a unique bundle identifier. The account owner
   completes account authentication locally.
3. Connect/unlock the phone, trust/pair it with the Mac and select it as the run
   destination. Enable Developer Mode when prompted; this includes a restart and
   confirmation by the phone owner.
4. Build and run. Grant camera/Bluetooth access. Verify actual capture, marker
   geometry and the selected BLE protocol before enabling warnings.
5. Disconnect the development cable and verify standalone operation. Rebuild and
   reinstall when the development provisioning profile expires.

A free Personal Team supports local testing; its provisioning profiles expire
after seven days. This does not require buying a Developer Program membership
for the local prototype. See Apple's [account/signing limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
and [Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
Do not describe sending an arbitrary unsigned app file as a working iPhone install.

If the phone is remote, either send the source/project to someone with Xcode who
can sign and install locally, or use an established signed distribution route.
TestFlight requires Developer Program access; Apple's listed membership is
[$99 USD/year](https://developer.apple.com/programs/). External testing includes
a first-build review step; see [TestFlight distribution](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
Use direct installation when available rather than depending on that review for
an imminent demo. No time estimate assumes successful signing or existing Xcode.

### Complexity and implementation sequence

Installation is a contained setup task when the phone and development Mac are
together. The difficult engineering is reliable geometry/depth at moving finger
boundaries, occlusion handling, and end-to-end timing. On-device execution avoids
building a streaming protocol but adds native capture, UI and app lifecycle work.

1. Establish a signed empty app on the actual phone, then verify RGB/depth capture.
2. Add Vision hands and a debug depth display; measure hovering separation and
   invalid depth at the intended working distance before promising contact precision.
3. Add marker registration and the shared risk state machine; display numeric risk
   with mock output, including safe grip and loss cases.
4. Add audio and direct BLE legacy commands; add intensity-v2 only with compatible
   firmware. Verify command expiry, app interruption and reconnect behavior.
5. Profile sustained operation and record physical warning-to-motor trials. Local
   logs and optional export follow; defer dashboard, clips and automatic step checks.

Suggested native modules: CaptureSession, HandTracker, MarkerTracker,
DepthRegistration, RiskEngine, BandClient, PromptPlayer, EventStore and a single
SessionViewModel. Implement pure Swift geometry/state tests and recorded-frame
replay; real camera/depth/BLE/motor tests need the device. These are proposed
modules, not files already present in this repository.

## First demo and collision coverage

Use mock connectors held near a calibrated horizontal working plane. Demonstrate:

1. Finger approaches an exposed tip: intensity rises; audio says “Move your hand
   away from the exposed tip.”
2. Moving exposed connector approaches a stationary hand: the same rule fires.
3. Exposed tip approaches a marked nonsterile patch: warn “Keep the exposed tip
   away from that surface.” This tests protection beyond fingertip tracking.
4. Hand retreats: warning clears with hysteresis and one near-miss is logged.
5. Projected overlap persists: log one **suspected contact**, speak a configured
   stop prompt and latch that prop for operator review/reset.
6. Marker is covered or camera stops: show **protection unavailable** and speak
   “Pause. Move the connector into view.”

The patch represents a nonsterile surface under the planar demo constraint, not a
verified floor strike. Leaving camera view means lost coverage, not proof of a
fall. Use independently labeled video as physical-contact ground truth.

Each prop has **safe grip geometry** and **protected surface geometry**: an exposed
end, opening or inner cap surface. Do not label the complete bag/tube exterior as
sterile. Use disks, capsules or polygons in the prop's local coordinates so the
protected surface follows its movement and rotation.

| Collision / condition | First-demo treatment | Evidence / limitation |
| --- | --- | --- |
| Exposed surface ↔ fingertip / finger pad | Implement | All five fingertips plus padded distal finger segments; overlap is a contact candidate |
| Exposed surface ↔ palm / back of hand | Conservative approximation | Padded palm polygon from hand landmarks; validate separately from fingertips |
| Exposed surface ↔ marked nonsterile patch / boundary | Implement projected warning | Fixed calibrated polygons; meaningful metric distance only near the working plane |
| Exposed surface ↔ another prop's nonsterile exterior | Next increment | Register geometry of both objects; test protected surface against exterior |
| Intended connector ↔ intended mating partner | Explicit exception | Allow only that configured pair in CONNECT with operator confirmation; retain hand protection |
| Covered connector / safe grip ↔ hand | Allowed by demo geometry | Gripping the body should not trigger the tip rule; does not validate clinical handling |
| Exposed surface ↔ sleeve, forearm, torso, hair | Later | Hand landmarks do not cover these; require validated additional detection/segmentation |
| Exposed surface ↔ floor | Later | Need a view covering the floor and calibrated geometry/depth or another sensor; disappearance is UNKNOWN |
| Droplets, dirty hands, package damage | Outside geometric MVP | Distance cannot establish these hazards |

The engine accepts geometry from any hazard detector rather than assuming every
hazard is a fingertip. For one band, transmit the maximum active risk across both
hands and all props. Two-band attribution comes later; uncertain hand identity
must remain visible.

### Exposure, phase and visibility

```text
COVERED --operator uncaps--> EXPOSED --operator confirms mating--> CONNECTED
                               |
                               +--suspected contact--> REVIEW_REQUIRED

Any state --observation invalid--> visibility UNKNOWN (underlying state retained)
REVIEW_REQUIRED --operator replaces/resets demo prop--> COVERED or EXPOSED
```

Visibility is independent of exposure. Losing a marker must not reset a contact
flag or imply a cap was fitted. Start with manual phase/exposure controls; camera
presence in a sanitizer region is not verified handwashing. Advancing phase alone
must not clear REVIEW_REQUIRED. Only an explicit operator action acknowledges
replacement/reset in this demo.

## Props and adapting the software

Prefer a PD training kit from a teaching program. Otherwise use clearly labeled
mock tubing/connectors with identifiable ends. Substitutes demonstrate the sensing
mechanism, not an accurate clinical exchange procedure.

| Item | Setup | Software adaptation |
| --- | --- | --- |
| Mac, compatible iPhone, USB cable | Stable overhead arm; start around 40–60 cm and check framing | Select actual camera each session; verify delivered resolution/freshness |
| Matte mat, even lamp | Work area around 40 × 30 cm as a starting layout | Define operating area; check motion blur and marker contrast |
| Mock transfer set and bag-line connector | Two rigid ends, tubing, height-controlled holders | Register IDs, marker-to-tip transforms, protected surfaces and safe grips |
| Mock cap on rigid carrier | One | Register its inner protected surface; manual exposure state |
| Printed ArUco tags on rigid flags | Unique IDs; initially 25–35 mm square if practical | DICT_4X4_50; measure black square excluding white margin; verify visibility in camera pixels |
| Reference board/grid and ruler | Known dimensions around work area | Lens calibration, plane mapping, drift detection, independent distance checks |
| Contrasting nonsterile patch | Fixed polygon on mat | Mark corners in calibrated coordinates; planar environmental hazard |
| Safe-grip sleeves/handles | One per connector | Keep fingers/tags visible without enlarging protected surface |
| Mock bag/container | Optional context | Whole-bag detection is unnecessary for first loop |
| Band, Mac speaker, optional serial cable | One band initially | Mock intensity, legacy commands, then intensity adapter after firmware update |
| Separate high-speed recording device | Borrow for measurement | Record physical zone crossing and band indicator/motor onset independently |

Put tags on flat rigid flags attached to the **nonsterile exterior**, away from
the grip/opening. Do not wrap tags around curved tubing. A tag on flexible tubing
does not define a fixed transform to a freely moving tip. Additional tags can
reduce occlusion if their transforms to the same rigid prop are registered. A
larger tag improves visibility; it does not enlarge the protected surface.

### Calibration and changing props

1. Fix camera mode, framing and mount. Disable automatic reframing/visual effects.
   Calibrate lens intrinsics/distortion with a calibration board; save camera,
   resolution and crop metadata.
2. Register the horizontal working plane in centimeters from reference points.
   Hold protected surfaces at that plane's height. Check distances across the
   usable area with a ruler.
3. Measure each marker's size, marker-to-surface transform, tip shape, safe grip,
   mating partner and initial exposure. Overlay the projected surface and check
   multiple positions and rotations against the real prop.
4. Test gaps of 0, 1, 2, 3 and 5 cm. Also deliberately lift a finger above the tip
   to expose 2D overlap ambiguity. Reject configurations that cannot resolve the demo.
5. Save a named prop profile and calibration ID. Swapping props means updating
   measured geometry and repeating these checks, not retraining a model.
6. Camera movement requires plane registration again; changes in optics/image
   mode require checking/replacing intrinsics. Reference markers detect drift
   and invalidate affected measurements.

In constrained planar mode, map marker corners and hand image points through the
calibrated plane transform, then apply the prop's planar transform. Do not average
pixel scales from markers at different heights. Departure from the working height
introduces parallax and invalidates metric hand-to-tip distances.

For tilted rigid props, estimate marker pose and transform protected geometry:
`p_camera = R_marker * p_local + t_marker`. Project this for an overlay / projected
warning. OpenCV documents calibrated marker pose via `solvePnP` and known marker
dimensions in its [ArUco guide](https://docs.opencv.org/4.x/d5/dae/tutorial_aruco_detection.html).
This supplies marker pose, not hand depth.

MediaPipe's hand-relative z and hand-centered world landmarks do not share the
marker's camera-space origin; do not subtract them directly from marker coordinates.
See the [Hand Landmarker coordinate definitions](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker?tab=Python).
Continuity Camera RGB is not calibrated hand depth. Free-space contact requires
validated depth/stereo or another calibrated view. An iPhone having LiDAR does not
itself make depth available to this capture pipeline.

### Available phone: standard iPhone 16

The user has an iPhone 16. It has rear main/ultra-wide cameras and front TrueDepth,
but no rear LiDAR. It supports spatial video at 1080p/30 fps; see Apple's
[iPhone 16 specifications](https://support.apple.com/en-us/121029). Spatial video
support is not proof of an accessible low-latency stereo stream through our
OpenCV/Continuity Camera path.

Before selecting a free-space depth implementation, run a **front TrueDepth
feasibility test**. Mount the phone with the front camera/screen facing the props.
Try an existing depth-streaming app first, as described below. A small native
iPhone capture app is a fallback for capture control/transport needs; Apple
provides a [TrueDepth streaming sample](https://developer.apple.com/documentation/avfoundation/streaming-depth-data-from-the-truedepth-camera).
This uses camera depth output, not face-mesh tracking, and needs no custom depth
model training. It is an additional iPhone capture component, beyond the original
Mac-plus-band architecture. Standard rear Continuity Camera capture stays the
baseline until the experiment passes.

Measure fingertip/prop separation at 0, 1, 2, 3 and 5 cm, including vertical
hovering, motion, boundaries, occlusion and actual prop materials. Record bias,
variation, invalid depth and latency at the intended working distance. Register
RGB/depth and marker geometry into the same camera coordinates; do not use depth
from background pixels or interpret missing depth as clearance. Passing broad
hovering separation does not establish physical-contact precision.

If useful, add a timestamped RGB/depth transport to Mac, keeping latest-frame
expiry and measuring added transport delay; on-phone processing with smaller
observation messages is another option to benchmark. Rear stereo is a second
experiment: inspect supported simultaneous camera combinations, synchronization
and calibration on this device before committing. The phone's existing rear
lenses offer a stereo opportunity, not a drop-in depth stream for the current app.

### Depth transport without building an iPhone app

An iPhone 15 Pro is also being considered. It has rear LiDAR; see Apple's
[15 Pro specifications](https://support.apple.com/en-gb/111829). If available,
test its main-camera/LiDAR feed before implementing custom rear-camera stereo.

First try **Record3D USB streaming**: its
[developer library](https://github.com/marek-simonik/record3d) supports receiving
RGB/depth on macOS from LiDAR or TrueDepth, with a Python demo. Install the existing
iPhone app, enable USB streaming, and integrate its Mac receiver behind our
capture interface. This replaces Continuity Camera as the source for the depth
experiment. Our hand tracking, prop geometry, risk, audio and BLE remain Mac code.

Record3D is a third-party paid app with in-app purchases; consult its
[listing](https://apps.apple.com/us/app/record3d-3d-videos/id1477716895) and
[USB instructions](https://record3d.app/features) for feature access. Do not assume
free downloads include streaming. Its Python integration may require a native
build; package/app compatibility, per-frame metadata and end-to-end latency have
not been verified on this Mac/phone. Keep the streaming callback short: copy a
coherent RGB/depth/calibration snapshot into a latest-only slot and process it in
our worker. Measure depth validity/accuracy and total delay before selecting it.
Build a custom iPhone capture app only if the existing streamer is unsuitable.

## Mac software stack

Start with local Python on Apple silicon. Python 3.11 is an environment candidate
to verify against selected releases; pin dependencies and model asset/checksum
after a camera/model/BLE smoke test. No package versions have been verified here.

| Layer | Choice | Responsibility |
| --- | --- | --- |
| Capture | OpenCV VideoCapture with CAP_AVFOUNDATION | Dedicated reader; latest-frame mailbox |
| Targeted capture fallback | Native AVFoundation adapter, if measurements require it | Stable device identity, sample timestamps and explicit late-frame discard |
| Hands | MediaPipe Tasks HandLandmarker, VIDEO, num_hands=2, CPU initially | Landmarks and temporal tracking without custom training |
| Props | OpenCV ArUco + NumPy + calibration/pose utilities | Known identities and protected geometry |
| Risk engine | Pure Python + NumPy | Surface clearance, relative motion, exposure, hysteresis and events |
| BLE | bleak on its own asyncio loop | Persistent connection, bounded writes, expiry and reconnect state |
| Audio | Preloaded local clips in a worker | Predictable onset; macOS say only as development fallback |
| Debug UI | OpenCV overlay and keyboard controls | Show surfaces, hazards, intensity, evidence state, age and timings |
| Configuration | YAML + saved calibration arrays | Named prop profiles, camera settings and thresholds |
| Event log | SQLite background writer | Local records; no disk I/O on decision path |
| Dashboard, later | FastAPI + simple page in another process | Read events; browser polling never drives haptics |
| Verification | pytest + recorded frames/observation traces | Geometry/state tests and repeatable detector evaluation |

Use one OpenCV distribution with ArUco and GUI support, not competing cv2 wheels.
Load the model locally before enabling protection; no cloud calls or model
fetching during the live session. A general object detector, full-body pose model
or language model is unnecessary for the first three demo cases.

Use Tasks deliberately: `detect_for_video(image, timestamp_ms)` blocks the inference
worker while capture continues separately. Supply strictly increasing timestamps.
The alternative LIVE_STREAM / detect_async skips inputs when busy; if adopted,
join callbacks to marker results by the same frame ID. The
[Python implementation](https://raw.githubusercontent.com/google-ai-edge/mediapipe/master/mediapipe/tasks/python/vision/hand_landmarker.py)
defines these modes. Start with the simpler same-frame worker. Benchmark CPU
before trying a GPU delegate or rewriting in Swift.

## Execution and data contracts

```mermaid
flowchart LR
    C[iPhone feed] --> R[Capture worker]
    R --> M[Latest frame only]
    M --> V[Hands + markers on same frame]
    V --> G[Geometry + exposure + risk]
    G --> B[Latest command + expiry]
    B --> BLE[BLE worker]
    BLE --> ESP[ESP32 motor]
    G --> A[Priority audio worker]
    G --> E[Bounded event queue]
    E --> DB[(SQLite)]
    DB --> UI[Later dashboard]
    G --> O[Latest overlay snapshot]
```

- **Capture worker:** continually drain source into one immutable frame slot.
  Inference takes the newest frame after finishing its previous one, not a FIFO.
- **Inference/decision worker:** process hands and tags from the same source frame,
  transform to the configured space, evaluate relevant surface/hazard pairs.
  Never combine a fresh hand and old moving connector as a current observation.
- **Main/UI thread:** display a copied latest snapshot at a capped rate; rendering
  and key handling do not pace inference.
- **Output workers:** BLE, audio and storage have separate scheduling. Haptic
  state is replaceable; discrete events are not. Bound event queues, surface
  overflow and mark the session incomplete if persistence cannot keep up.
- **Health monitor:** continues even when capture/inference stalls, expires
  observations/commands and publishes protection-unavailable status.

```text
Frame: frame_id, receipt_monotonic_ns, source_timestamp_if_available, image
Observation: frame_id, space_id, hands, prop_surfaces, validity, geometry_error
Risk: prop_id, hazard_id, clearance, distance_kind, closing_speed, severity,
      exposure_state, evidence_state, frame_id, valid_until
HapticState: mode, intensity_0_255, created_at, valid_until, reason
Event: event_id, session_id, monotonic_time, type, prop_id, hazard_id,
       frame_id, evidence_state, distance_kind, calibration_id, config_hash
```

Distance kind distinguishes calibrated planar centimeters from image pixels or
projected overlap. Do not label an image estimate as physical 3D distance. Retain
raw and filtered estimates for tuning; use monotonic time for deadlines and wall
time for human logs.

## Risk, warnings and events

Measure clearance between **surface boundaries**, not landmark-to-marker centers.
Inflate finger segments/palm by a validated pad/error margin and include the
protected surface shape. With planar boundary clearance d and uncertainty u,
use `d_effective = max(0, d - u)` for conservative warnings.

1. Evaluate exposed surfaces against applicable hazards and allowed-pair rules.
   Covered/connected surfaces are inactive only when explicitly established.
2. Warn on the first usable estimate inside the warning region. Map proximity
   monotonically to intensity. Measure minimum motor duty; do not assume PWM 70
   works on every motor.
3. Use an exit margin (initial candidate 0.5 cm) against chatter. Keep filtering
   light and measure its delay; long averages can hide fast approaches.
4. Estimate **relative** closing velocity with timestamps, covering a moving prop
   approaching a still hand as well as the reverse.
5. Projected overlap / uncertainty-band entry raises immediate suspicion. A
   short elapsed-time dwell can stabilize logging (initial candidate 50 ms),
   without delaying initial warning. Invalid observations reset/pause dwell;
   repeated stale frames are not evidence.
6. Log one near-miss for a qualifying approach-and-retreat without suspected
   contact. Log one suspected-contact event per episode and latch REVIEW_REQUIRED.
   Do not count each frame as another event.

Initial intensity curve, with urgent clearance smaller than warning clearance:

```text
q = clamp((d_warn - d_effective) / (d_warn - d_urgent), 0, 1)
outside warning region: OFF
inside warning region: intensity = pwm_min + q * (255 - pwm_min)
```

These are tuning parameters, not clinical contamination thresholds. The product
doc's 3 cm warning radius is an experiment; its 0.8 cm contact radius is not
contact ground truth. Center-distance thresholds must be reinterpreted when
switching to boundary clearance.

### Warning lead time

At 20 cm/s, a hand closes 3 cm in 150 ms: a 150 ms system delay leaves no time to
respond. At 50 cm/s, that delay consumes 7.5 cm before vibration starts.
After measuring latency/motion error, test a speed-aware envelope:

```text
d_warn = max(base_clearance,
             closing_speed * (measured_latency_p95 + response_allowance) + u)
```

For example, 20 cm/s × (0.15 s + 0.25 s) + 0.5 cm = 8.5 cm. The 0.25 s response
allowance is illustrative, not a validated patient reaction time. Clamp noisy
velocities, label predictions and report when the required envelope exceeds the
observed area. With poor velocity confidence, use a conservative fixed envelope
and show reduced capability. Prediction supports warning, not contact confirmation.

### Loss and recovery

Start with a configurable **100 ms receipt-to-decision freshness ceiling** and
validate it against timings. A missing active prop/hazard observation is invalid
immediately; persistent loss produces a cooldown-limited pause prompt. No hand
found does not prove no hand exists. Calibration drift, implausible pose jumps
and camera freezes also invalidate measurements.

Retain last-known context to explain loss, not to declare clearance. Stop stale
geometric intensity, send OFF if possible and rely on the band's watchdog
otherwise, while explicitly showing/speaking protection unavailable. On recovery,
require several fresh consistent observations; retain exposure/review state.
BLE reconnection must not replay stale commands. Band loss leaves audio/overlay
available with a separate band fault.

## Camera and latency

Request 1280 × 720 at 30 fps, then verify actual delivery. Use USB first and
compare transport delay against wireless. Apple documents camera selection,
compatibility and USB trust in its
[Continuity Camera guide](https://support.apple.com/en-us/102546).
Use a fixed direct view; disable Center Stage, Desk View and other image transforms
for calibration. Do not assume the app can select a 0.5× lens or lock all settings.

Receipt time is when a frame reaches the app, not sensor exposure time. The
one-frame mailbox removes application backlog, not camera/transport/backend delay.
OpenCV states that property support depends on backend in its
[Video I/O overview](https://docs.opencv.org/4.x/d0/da7/videoio_overview.html);
setting CAP_PROP_BUFFERSIZE=1 does not prove macOS buffering is controlled.
Use source timestamps where available; receipt timestamps cannot detect a backend
repeatedly returning an old image.

If capture latency or enumeration blocks progress, use a native AVFoundation
adapter behind the same frame interface. Apple's
[alwaysDiscardsLateVideoFrames](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput/alwaysdiscardslatevideoframes)
provides an explicit late-frame policy. Improve this measured bottleneck before
considering a complete application rewrite.

### Provisional budget

These are engineering allocations, not measurements. At 30 fps sensor phase alone
can cost about 33 ms; transport/processing delay is additional.

| Stage | Initial allocation / treatment |
| --- | --- |
| Motion → frame delivered | Unknown; includes sensor phase, camera processing, transport and backend buffering |
| Receipt → inference start | Aim 0–10 ms steady state; discard beyond freshness ceiling |
| Hand inference + markers + conversion | Aim 15–30 ms; benchmark two hands and reacquisition |
| Geometry + dispatch | Aim under 2 ms |
| BLE scheduling/delivery | Initially allocate 10–30 ms; measure actual OS/link behavior |
| Motor mechanical onset | Initially allocate 20–50 ms; measure actual motor/driver |
| Contact event dwell | Separate logging path; no delay added to first warning |
| Audio onset | Separate measurement; preloaded priority playback |

Non-camera allocations total about 47–122 ms; camera delay can make 150 ms fail.
Initial objective: end-to-end p95 ≤150 ms and no observed trial above 250 ms under
defined demo conditions. Report actual median, p95, maximum and sample count. If
it fails, revise hardware/operating envelope; FPS is not latency. Three-frame
contact debounce adds roughly 67 ms after the first qualifying sample at 30 fps,
and more with dropped frames.

### Scheduling and verification

- One latest frame and one latest haptic state. Allow one BLE write in flight;
  replace pending state rather than building a write backlog.
- Start with full work-area tracking. Crop/resize only after validating marker
  readability and coordinate mapping; do not crop away approaching hazards.
  Reduce overlay frequency before sacrificing observation quality.
- Preconnect BLE and preload/warm models and audio before enabling protection.
  Show camera/calibration/BLE readiness explicitly.
- Instrument receipt, inference start/end, decision, write submit/return and audio
  dispatch with monotonic timestamps. A completed write does not prove vibration.
- Record a physical crossing of a marked warning boundary and band response with
  an independent high-speed camera. LED onset is an electrical proxy; mechanical
  onset needs visible motor motion or an accelerometer. Do not assume the iPhone
  streaming Continuity Camera can simultaneously make this reference recording.
- Run at least 100 crossings across slow/fast and two-hand motion, plus a sustained
  session with logging to expose heat/drift. Measure camera delay independently
  with a physical timer in view. Report freezes and deadline misses as well as FPS.

## Band interface and audio

Existing [firmware](firmware/wristband/wristband.ino):

BLE carries a numeric motor-intensity command. Increasing urgency changes that
value and the motor PWM duty, not Bluetooth radio transmit power or signal strength.

```text
name:           DialysisBand
service:        7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00
characteristic: 7a1e0002-3c5d-4b8a-9f21-6d2c8e4b1a00
payload:        ASCII O / W / E / T / S
```

The Adafruit motor supports variable intensity through the existing driver or
transistor. The updated sketch retains the ASCII characteristic above and adds
`7a1e0003-3c5d-4b8a-9f21-6d2c8e4b1a00` for two-byte `[mode, duty]` writes.
Mode 0 is off, 1 is experimental proximity, and 2 is a review cue. Nonzero modes
apply the supplied 0–255 PWM duty; mode 2 does not implement the original proposed
double pulse. The app exposes explicit legacy/v2 selection and defaults to legacy
for boards with the older sketch. There is no mode 3 in the implemented protocol;
the app's test pulse uses mode 1 with a short expiry.

The phone sends v2 changes and a 100 ms heartbeat, expires desired intensity after
250 ms, and reconnects with off. The updated sketch turns PWM off after 300 ms
without a valid v2 packet and on disconnect. Invalid modes/packet sizes do not
refresh the watchdog. Existing ASCII/USB patterns remain finite, and repeated W
is avoided by the legacy app adapter. Compilation, useful duty range, heartbeat
behavior and physical shutoff still require the actual board/toolchain. See
[firmware setup and tests](README.md#optional-variable-intensity-protocol).

The current native implementation uses CoreBluetooth discovery by service and
writes without response only to a supporting characteristic. It keeps only the
current unexpired command and requires an explicit reconnect after loss. One
band is connected; left/right routing and an in-app mock band are future work.
For the earlier Mac alternative, Bleak's
[client API](https://bleak.readthedocs.io/en/latest/api/client.html) explains
macOS device identifiers and GATT writes. USB is for legacy command debugging.

Audio follows the hazard reason, not the intensity number. Use the first-demo
phrases above and “Pause. Possible contact. Follow the configured training
instructions.” for suspected contact. Higher-severity prompts interrupt lower
ones; coalesce duplicates and apply cooldowns so speech never queues behind the
action. Any instructions about replacing supplies or continuing a real exchange
must come from the clinic's approved protocol, not a generic inferred response.

## Earlier Mac alternative: planned files and build order

```text
main.py                   # lifecycle, readiness, keyboard/UI
config.yaml               # camera, profile, protocol, thresholds
profiles/demo_props.yaml  # measured geometry, IDs, allowed pairs
calibration/              # intrinsics, working plane, metadata
models/                   # local model and checksum/license metadata
vision/capture.py         # camera/replay adapters, latest-frame mailbox
vision/hands.py            # Tasks wrapper, timestamped observations
vision/markers.py         # identity and transforms
engine/geometry.py        # boundaries, clearance, validity
engine/risk.py            # relative motion, intensity, hysteresis
engine/state.py           # phase, exposure, review state
engine/events.py          # one event per episode
haptics/link.py           # mock / legacy / intensity v2
audio/prompts.py          # preloaded priority playback
store/db.py               # background writer
overlay.py                # geometry, evidence, age and timings
dashboard/app.py          # later, separate process
firmware/wristband/wristband.ino  # shared firmware; legacy and PWM-v2 now implemented as source
tests/                    # geometry/state/replay verification
```

| Order | Deliverable | Evidence |
| --- | --- | --- |
| 1 | Capture, health and readiness | Actual source delay/FPS; no growing backlog; freeze/loss behavior |
| 2 | Calibrated props and fixed hazard | Overlay alignment across area; ruler checks; height limitation demonstrated |
| 3 | Hands, clearance and mock intensity | Moving hand and moving tip both trigger; safe gripping does not systematically alarm |
| 4 | Events and audio | Trace tests; no event spam; review state survives loss/phase changes |
| 5 | Band adapter | Legacy works now; claim variable intensity only after PWM/heartbeat/watchdog firmware tests |
| 6 | Latency/robustness and rehearsal | Full latency distribution and detection errors under stated conditions |
| 7 | Optional dashboard/clips | Counts match labeled trials; enabling storage/UI preserves latency |

Test transforms/rotations, allowed mating pairs, exposure versus visibility,
variable frame intervals, fast approaches, dropouts, expiry and reconnects with
synthetic traces. Assess detector accuracy with independently labeled staged
video, including raised-hand overlaps; logic tests alone cannot establish it.
Keep the product doc's under-0.5-cm error inside 3 cm as a bench goal **only for
the defined planar setup**. Report misses, false alerts and unobservable cases.

Keep clips out of the critical path. Five seconds of raw 720p RGB at 30 fps is
about 415 MB before object overhead; use a bounded lower-rate/resolution or
encoded worker-side ring buffer if added. Log uncertainty, loss intervals,
protocol mode and timings alongside events. Defer the proposed technique score
and patient ranking until their meaning is agreed and validated.

Remaining bench decisions: exact training props and protected surfaces; camera
mode and transport delay; usable speed/height range; motor response and v2 timing;
clinically reviewed surface definitions/prompts before real-exchange use.
