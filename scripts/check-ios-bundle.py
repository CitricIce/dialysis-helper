#!/usr/bin/env python3
"""Validate the unsigned iPhone bundle's layout before attempting installation."""
import json
import plistlib
import sys
from pathlib import Path


def check_bundle(app):
    if not app.is_dir():
        raise ValueError("app product not found: " + str(app))
    # Reserved names can make codesign classify a flat iOS app as another bundle type.
    for name in ("Resources", "Contents", "Versions"):
        if (app / name).exists():
            raise ValueError(f"unexpected {name}/ at iPhone app root; copy data files individually")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("CFBundlePackageType") != "APPL":
        raise ValueError("product is not an application bundle")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or not (app / executable).is_file():
        raise ValueError("missing or invalid main executable")
    template = json.loads((app / "RoutineTemplate.json").read_text())
    if template.get("practiceOnly") is not True:
        raise ValueError("missing practice-only routine at bundle root")
    if not (app / "VoiceInstructions.txt").is_file():
        raise ValueError("direct phone voice instructions are missing")
    if not (app / "SterileParts.mlmodelc").is_dir():
        raise ValueError("protected-opening model was not compiled into the app")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check-ios-bundle.py /path/to/ArmGuardCaptureProbe.app")
    try:
        check_bundle(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        raise SystemExit("Bundle check failed: " + str(error))
    print("PASS: flat iPhone bundle, main executable and root routine resource")
