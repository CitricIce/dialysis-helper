#!/bin/bash
# Compile check only. Use Xcode with your signing team for installation on a phone.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    cat >&2 <<'EOF'
An iOS SDK is not available in the selected developer toolchain.
Install full Xcode, launch it to finish setup, then choose that Xcode in
Xcode > Settings > Locations > Command Line Tools (or set DEVELOPER_DIR).
Command Line Tools alone cannot build an iPhone app.
EOF
    exit 1
fi
xcodebuild \
    -project "$repo_root/ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe.xcodeproj" \
    -scheme ArmGuardCaptureProbe \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$repo_root/build/ios-probe" \
    CODE_SIGNING_ALLOWED=NO \
    build

python3 "$repo_root/scripts/check-ios-bundle.py" \
    "$repo_root/build/ios-probe/Build/Products/Debug-iphoneos/ArmGuardCaptureProbe.app"
