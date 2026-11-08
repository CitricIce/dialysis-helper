#!/bin/bash
# Repeatable preflight. A phone, signing team and Cartesia credentials are not needed.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
require_ios=false
case "${1:-}" in
    "") ;;
    --require-ios-build) require_ios=true ;;
    *) echo "Usage: bash scripts/check-ios-app.sh [--require-ios-build]" >&2; exit 2 ;;
esac
check_root="${ARMGUARD_CHECK_DIR:-$repo_root/build/checks}"
mkdir -p "$check_root"

python3 "$repo_root/scripts/check-ios-project.py"
python3 -m unittest discover -s "$repo_root/services/voice_gateway" -v
CLANG_MODULE_CACHE_PATH="$check_root/host-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$check_root/host-module-cache" \
swift run --disable-sandbox --package-path "$repo_root/ios/ArmGuardCaptureProbe/Core" \
    --scratch-path "$check_root/swift-build" --cache-path "$check_root/swift-cache" \
    --config-path "$check_root/swift-config" --security-path "$check_root/swift-security" \
    --disable-index-store CaptureProbeChecks

sources=("$repo_root"/ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe/*.swift
         "$repo_root"/ios/ArmGuardCaptureProbe/Core/Sources/CaptureProbeCore/*.swift)
xcrun swiftc -frontend -parse "${sources[@]}"

if xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    bash "$repo_root/scripts/build-ios-probe.sh"
    echo "PASS: checks and unsigned iPhone app build. Device behavior still needs a physical-phone test."
else
    mac_sdk="$(xcrun --sdk macosx --show-sdk-path)"
    if [[ -d "$mac_sdk/System/iOSSupport/System/Library/Frameworks/UIKit.framework" ]]; then
        mkdir -p "$check_root/catalyst-module-cache"
        module_cache="$(cd "$check_root/catalyst-module-cache" && pwd -P)"
        # Use actual Apple frameworks, without stubbing services or changing the
        # app's supported platforms. This is a type check only, not a Catalyst app.
        xcrun swiftc -typecheck -swift-version 5 -strict-concurrency=minimal \
            -target "$(uname -m)-apple-ios17.0-macabi" -sdk "$mac_sdk" \
            -F "$mac_sdk/System/iOSSupport/System/Library/Frameworks" \
            -module-cache-path "$module_cache" "${sources[@]}"
        echo "PASS: all app sources type-checked against Mac Catalyst Apple frameworks."
    else
        echo "LIMITATION: native framework type-check skipped; this SDK has no Catalyst headers." >&2
    fi
    echo "LIMITATION: iPhone build NOT verified; install/select full Xcode with the iOS SDK." >&2
    if [[ "$require_ios" == true ]]; then exit 1; fi
fi
