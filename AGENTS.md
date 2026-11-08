# ALWAYS READ THIS FIRST

Read this file before changing code, architecture, models, hardware interfaces,
or project documentation in this repository.

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

## Current implementation reference

- The foreground iPhone app runs RGB/LiDAR capture, the bundled RF-DETR model,
  Apple fingertip tracking, proximity/routine rules, and Bluetooth band output.
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
