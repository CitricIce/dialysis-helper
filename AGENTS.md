# ALWAYS READ THIS FIRST

Read this file before changing code, architecture, models, hardware interfaces,
or project documentation in this repository.
lol
## Mandatory: update all design docs after a major change

After **any significant update**, review and update **all** of the design,
handoff, and setup documents below as part of the same task. Documentation is
part of completing the change. Do not stop after updating code or only one doc.

A significant update includes changes to architecture, camera/depth capture,
models or class mappings, proximity rules, voice behavior, routine flow, Bluetooth
or firmware, installation, credentials/data flow, or latency/failure handling.

Documents that must stay synchronized:

- [Product design](<ArmGuard PD Real-Time Sterile Technique Coaching for Home Peritoneal Dialysis.md>)
- [Software and feedback design](DESIGN.md)
- [Implementation handoff](HANDOFF.md)
- [Project overview](README.md)
- [iPhone app and testing guide](ios/ArmGuardCaptureProbe/README.md)
- [Optional voice gateway guide](services/voice_gateway/README.md)

Update the current architecture, implemented behavior, setup instructions,
limitations, and validation status wherever they appear. If a document's main
subject is unaffected, update its current-status/cross-reference section so it
still agrees with the rest. Clearly label retained historical designs as
alternatives or superseded proposals. Remove contradictory instructions from
current sections. Include any future design documents in this synchronization
rule and add their paths to this list.

Before finishing, check the documents against each other and the actual code.
Summarize which documents changed and which verification remains outstanding.
Distinguish targets from measured results, source/type checks from iPhone builds,
and model smoke tests from real-prop accuracy or physical latency tests.

## Brand

The company, app and system are called **Sterling**. The slogan is **keep it clean**.
Use Sterling in user-facing copy. Legacy ArmGuard project/target/bundle filenames
remain technical identifiers; preserve working signing settings. The logo concept
is `assets/branding/sterling-logo-v1.png`; the standalone vector is
`assets/branding/sterling-ring.svg`. The app draws a native vector companion and
bundles the full wordmark for launch. Describe the system as voice guidance,
camera support and wristband feedback (audio, visual and haptic). Describe infection reduction as the
mission, not a proven prototype outcome.

## Current implementation reference

- The confirmed test phone is iPhone 15 Pro. Its foreground app runs RGB/LiDAR,
  RF-DETR and Apple fingertips locally. The current model is a low-accuracy
  placeholder: show experimental previews but run connection steps as unmonitored
  rehearsal. Existing image-scale distance warnings can still drive cues when fresh;
  do not describe those estimates as protection or sterility verification. `detectorStatus` in RoutineTemplate.json controls deliberate
  experimental monitoring; a compiled model is not evidence of usable accuracy.
  The voice agent receives derived native observations, not camera images.
- Cartesia connects directly from the phone by default. The user enters an
  authorized key once; it is stored in the device Keychain. Voice needs internet,
  but no laptop server must remain running. A hosted gateway is optional.
- Never put API keys in source, model metadata, documentation, or Git. Local
  configuration and generated phone setup files must remain ignored.
- The practice routine does not validate prescriptions, confirm physical contact,
  establish sterility, or produce a clinical cleanliness score. State remaining
  coverage and validation limits accurately.

## Preserve the user's work

Preserve existing local edits and signing settings when integrating teammates'
changes. Leave changes unstaged and uncommitted unless the user explicitly asks
for a commit. Do not push unless requested.

## Everyday UI and developer access

Keep the normal interface focused on My routines and voice-led practice. Four
editable/deletable defaults and Add routine are intentional. Names, times, notes
and reminders are personal metadata; all routines currently share the practice
template. Keep exampleResponses beside each check in RoutineTemplate.json and show
them in the routine editor. Technical panels, model/depth tests and measurement
summaries remain accessible through Settings → Developer mode. Preserve this access
when changing the consumer UI. Do not turn practice counts into adherence claims.

## Voice and warning integration

After the routine starts, ordinary progression must work through speech. Do not
send the user to Developer mode to say next step. Keep pause/resume listening and
handle phone audio-route/engine recovery without silently dropping output. Audio
packet receipt and text generation are not proof of speaker playback. Native
image-scale cues remain active independently of the stricter depth-monitoring
phase; do not say warnings are off merely because the model is a placeholder or
the internal routine phase is unmonitoredPractice. Missing/stale estimates mean
warnings are unavailable, not that distance is safe. Reuse saved preview confidence
between debug and routine. Preserve the 250 ms freshness rule, warning zones and
BLE command expiry. Band writes are not motor acknowledgements. Pair/authorize
before hands-free use; an explicit band disconnect stops automatic retries.
