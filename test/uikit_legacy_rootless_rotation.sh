#!/bin/sh
# Opt-in native simulator regression. Compiles the real production rotation
# unit without the guest bridge/emulator; --build-only never installs or runs.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device=booted
build_only=0
keep=0
run_timeout=${LC32_ROOTLESS_ROTATION_TIMEOUT:-30}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --device) [ "$#" -ge 2 ] || exit 2; device=$2; shift 2 ;;
        --build-only) build_only=1; keep=1; shift ;;
        --keep) keep=1; shift ;;
        *) echo "usage: $0 [--device UDID] [--build-only] [--keep]" >&2; exit 2 ;;
    esac
done
case "$run_timeout" in ''|*[!0-9]*) echo "invalid timeout" >&2; exit 2 ;; esac
[ "$run_timeout" -ge 1 ] && [ "$run_timeout" -le 60 ] || exit 2
temp_base=$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd -P)
workdir=$(mktemp -d "$temp_base/lc32-rootless-rotation.XXXXXX")
run_id=$(basename "$workdir" | tr -cd '[:alnum:]')
installed_bundle=
matrix_failed=0
bounded() { perl -e 'alarm shift; exec @ARGV; die "exec: $!\n"' "$@"; }
cleanup() {
    result=$?
    trap - EXIT INT TERM
    if [ -n "$installed_bundle" ]; then
        bounded 10 xcrun simctl terminate "$device" "$installed_bundle" >/dev/null 2>&1 || :
        bounded 10 xcrun simctl uninstall "$device" "$installed_bundle" >/dev/null 2>&1 || :
    fi
    if [ "$keep" -eq 1 ] || [ "$result" -ne 0 ]; then
        echo "Rootless rotation artifacts: $workdir"
    else
        case "$workdir" in "$temp_base"/lc32-rootless-rotation.*) rm -rf -- "$workdir" ;; esac
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sdk_root=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator \
    -isysroot "$sdk_root" -fobjc-arc -g -O0 -Wall -Wextra \
    -Wno-deprecated-declarations -Wl,-headerpad,0x1000 \
    -I"$repo_root/include" -I"$repo_root/HostFrameworks/UIKit" \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -lc++ \
    "$repo_root/test/uikit_legacy_rootless_rotation.m" \
    "$repo_root/HostFrameworks/UIKit/LegacyAutoLayout.mm" \
    "$repo_root/HostFrameworks/UIKit/LegacyRotation.mm" -o "$workdir/test"

for sdk in 5 7 8 11; do
    app="$workdir/sdk$sdk.app"
    bundle="org.liveexec32.test.rootlessrotation.$run_id.sdk$sdk"
    mkdir "$app"
    plist="$app/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleExecutable -string RootlessRotation "$plist"
    plutil -insert CFBundleIdentifier -string "$bundle" "$plist"
    plutil -insert CFBundleName -string "Rootless SDK$sdk" "$plist"
    plutil -insert CFBundlePackageType -string APPL "$plist"
    plutil -insert CFBundleVersion -string 1 "$plist"
    plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
    plutil -insert MinimumOSVersion -string 11.0 "$plist"
    plutil -insert LSRequiresIPhoneOS -bool YES "$plist"
    plutil -insert UIDeviceFamily -json '[1,2]' "$plist"
    plutil -insert CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$plist"
    plutil -insert UIStatusBarHidden -bool YES "$plist"
    plutil -insert UISupportedInterfaceOrientations -json \
        '["UIInterfaceOrientationLandscapeRight","UIInterfaceOrientationLandscapeLeft"]' "$plist"
    plutil -insert LC32ExpectedSDK -integer "$((sdk * 65536))" "$plist"
    xcrun vtool -set-build-version 7 11.0 "$sdk.0" -replace \
        -output "$app/RootlessRotation" "$workdir/test"
    codesign --force --sign - "$app" >/dev/null 2>&1
    codesign --verify --strict "$app"
    echo "Built $app ($bundle), SDK$sdk / minOS11"
    [ "$build_only" -eq 0 ] || continue

    installed_bundle=$bundle
    bounded "$run_timeout" xcrun simctl install "$device" "$app"
    for test_case in rootless explicit modern unregistered manual modal manual-disabled lifecycle ownership replacement; do
        log="$workdir/sdk$sdk-$test_case.log"
        status=0
        bounded "$run_timeout" xcrun simctl launch --console "$device" "$bundle" \
            --case "$test_case" >"$log" 2>&1 || status=$?
        echo "Rootless rotation SDK$sdk/$test_case status=$status"
        sed -n '1,160p' "$log"
        bounded 10 xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || :
        if [ "$status" -ne 0 ] || ! grep -q 'rootless-rotation-regression: PASS' "$log"; then
            matrix_failed=1
        fi
    done
    bounded 10 xcrun simctl uninstall "$device" "$bundle"
    installed_bundle=
done
exit "$matrix_failed"
