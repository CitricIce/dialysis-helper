#!/usr/bin/env python3
"""Check the hand-authored Xcode project, resources, and declared source files."""
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "ios/ArmGuardCaptureProbe"
PROJECT = APP / "ArmGuardCaptureProbe.xcodeproj"


def require(condition, message):
    if not condition:
        raise SystemExit("Project check failed: " + message)


def main():
    xml = subprocess.check_output(["plutil", "-convert", "xml1", "-o", "-", str(PROJECT / "project.pbxproj")])
    project = plistlib.loads(xml)
    objects = project["objects"]
    targets = [(key, value) for key, value in objects.items() if value.get("isa") == "PBXNativeTarget"]
    require(len(targets) == 1, "expected one app target")
    target_id, target = targets[0]
    phases = [objects[key] for key in target["buildPhases"]]
    source_phase = next(p for p in phases if p["isa"] == "PBXSourcesBuildPhase")
    source_paths = [objects[objects[key]["fileRef"]]["path"] for key in source_phase["files"]]
    expected = {str(p.relative_to(APP)) for directory in [APP / "ArmGuardCaptureProbe", APP / "Core/Sources/CaptureProbeCore"]
                for p in directory.glob("*.swift")}
    require(len(source_paths) == len(set(source_paths)), "duplicate source in app target")
    require(set(source_paths) == expected, "source membership differs: " + str(set(source_paths) ^ expected))
    for reference in objects.values():
        if reference.get("isa") == "PBXFileReference" and reference.get("sourceTree") == "<group>":
            require((APP / reference["path"]).exists(), "missing file: " + reference["path"])
    resources = next(p for p in phases if p["isa"] == "PBXResourcesBuildPhase")
    resource_paths = {objects[objects[key]["fileRef"]]["path"] for key in resources["files"]}
    require("ArmGuardCaptureProbe/Resources/RoutineTemplate.json" in resource_paths,
            "routine JSON must be copied individually into the flat app bundle")
    for path in resource_paths:
        reference = next(o for o in objects.values() if o.get("isa") == "PBXFileReference" and o.get("path") == path)
        is_folder = reference.get("lastKnownFileType") == "folder" or reference.get("explicitFileType") == "folder"
        require(not (is_folder and Path(path).name in {"Resources", "Contents", "Versions"}),
                "reserved bundle directory copied wholesale: " + path)
    template = json.loads((APP / "ArmGuardCaptureProbe/Resources/RoutineTemplate.json").read_text())
    require(template["practiceOnly"] is True, "unreviewed template must stay practice-only")
    identifiers = [check["id"] for check in template["checks"]]
    require(len(identifiers) == len(set(identifiers)), "duplicate routine check IDs")
    info = plistlib.loads((APP / "ArmGuardCaptureProbe/Info.plist").read_bytes())
    for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                "NSBluetoothAlwaysUsageDescription", "NSLocalNetworkUsageDescription"]:
        require(bool(info.get(key)), "missing permission purpose: " + key)
    require(not info.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads", False), "blanket ATS bypass")
    scheme = ET.parse(PROJECT / "xcshareddata/xcschemes/ArmGuardCaptureProbe.xcscheme")
    for reference in scheme.iter("BuildableReference"):
        require(reference.attrib["BlueprintIdentifier"] == target_id, "scheme points to a nonexistent target")
    print(f"PASS: project membership ({len(expected)} sources), resources, scheme, permissions and practice template")


if __name__ == "__main__":
    main()
