#!/bin/sh
# Opt-in native Simulator test; does not boot devices or touch other apps.
# --build-only preserves artifacts without installing or launching anything.
# --baseline additionally expects an unpatched SDK7 app to hit UIKit's assertion.
# The SDK matrix also calls the actual production compatibility-policy export;
# a separate SDK8 launch checks the launch-only force-off environment override.
# Policy-only cases keep the executable SDK11 and supply an earlier effective
# SDK before +load, without interposing UIKit or opening a test window.
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device=booted
build_only=0
baseline=0
keep=0
run_timeout=${LC32_SDK_LAYOUT_TIMEOUT:-30}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --device) device=$2; shift 2 ;;
        --build-only) build_only=1; keep=1; shift ;;
        --baseline) baseline=1; shift ;;
        --keep) keep=1; shift ;;
        *) echo "usage: $0 [--device UDID] [--build-only] [--baseline] [--keep]" >&2; exit 2 ;;
    esac
done
case "$run_timeout" in ''|*[!0-9]*) echo "invalid timeout" >&2; exit 2 ;; esac
[ "$run_timeout" -ge 1 ] && [ "$run_timeout" -le 60 ] || exit 2
temp_base=$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd -P)
workdir=$(mktemp -d "$temp_base/lc32-sdk-layout.XXXXXX")
run_id=$(basename "$workdir" | tr -cd '[:alnum:]')
installed_bundle=

bounded() {
    perl -e 'alarm shift; exec @ARGV; die "exec: $!\n"' "$@"
}
cleanup() {
    result=$?
    trap - EXIT INT TERM
    if [ -n "$installed_bundle" ]; then
        bounded 10 xcrun simctl terminate "$device" "$installed_bundle" >/dev/null 2>&1 || :
        bounded 10 xcrun simctl uninstall "$device" "$installed_bundle" >/dev/null 2>&1 || :
    fi
    if [ "$keep" -eq 1 ] || [ "$result" -ne 0 ]; then
        echo "SDK layout artifacts: $workdir"
    else
        case "$workdir" in "$temp_base"/lc32-sdk-layout.*) rm -rf -- "$workdir" ;; esac
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sdk_root=$(xcrun --sdk iphonesimulator --show-sdk-path)
compile() {
    output=$1
    shift
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator \
        -isysroot "$sdk_root" -fobjc-arc -g -O0 -Wall -Wextra \
        -Wl,-headerpad,0x1000 -framework UIKit -framework Foundation \
        -framework CoreGraphics -lc++ "$repo_root/test/uikit_legacy_sdk_layout.m" \
        "$@" -o "$output"
}
compile "$workdir/fixed" -DLC32_TEST_LINKED_COMPATIBILITY_POLICY=1 \
    "$repo_root/HostFrameworks/UIKit/LegacyAutoLayout.mm"
compile "$workdir/effective" -DLC32_TEST_LINKED_COMPATIBILITY_POLICY=1 \
    -DLC32_TEST_EFFECTIVE_SDK_PROVIDER=1 \
    -Ddyld_program_sdk_at_least=LC32TestEffectiveSDKAtLeast \
    -Ddyld_get_program_sdk_version=LC32TestEffectiveSDKVersion \
    "$repo_root/HostFrameworks/UIKit/LegacyAutoLayout.mm"
if [ "$baseline" -eq 1 ]; then compile "$workdir/unpatched"; fi

build_case() {
    variant=$1
    sdk_version=$2
    sdk_encoded=$3
    has_fix=$4
    binary=$5
    expected_compatibility=$6
    disable_compatibility=${7-}
    effective_sdk=${8-}
    app="$workdir/$variant.app"
    bundle="org.liveexec32.test.sdklayout.$run_id.$variant"
    mkdir "$app"
    plist="$app/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleExecutable -string SDKLayout "$plist"
    plutil -insert CFBundleIdentifier -string "$bundle" "$plist"
    plutil -insert CFBundleName -string "$variant" "$plist"
    plutil -insert CFBundlePackageType -string APPL "$plist"
    plutil -insert CFBundleVersion -string 1 "$plist"
    plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
    plutil -insert MinimumOSVersion -string 11.0 "$plist"
    plutil -insert LSRequiresIPhoneOS -bool YES "$plist"
    plutil -insert UIDeviceFamily -json '[1,2]' "$plist"
    plutil -insert CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$plist"
    # Landscape takes the legacy rotation path while creating text effects;
    # portrait alone misses the tracking-root engine-hosting assertion.
    plutil -insert UIInterfaceOrientation -string UIInterfaceOrientationLandscapeRight "$plist"
    plutil -insert UISupportedInterfaceOrientations -json '["UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight"]' "$plist"
    plutil -insert LC32ExpectedSDK -integer "$sdk_encoded" "$plist"
    plutil -insert LC32HasFix -bool "$has_fix" "$plist"
    plutil -insert LC32ExpectedCompatibility -bool "$expected_compatibility" "$plist"
    forced_off=NO
    if [ "$disable_compatibility" = 1 ]; then forced_off=YES; fi
    plutil -insert LC32ForcedCompatibilityOff -bool "$forced_off" "$plist"
    if [ -n "$effective_sdk" ]; then
        plutil -insert LC32ExpectedEffectiveSDK -integer "$effective_sdk" "$plist"
    fi
    xcrun vtool -set-build-version 7 11.0 "$sdk_version" -replace \
        -output "$app/SDKLayout" "$binary"
    codesign --force --sign - "$app" >/dev/null 2>&1
    codesign --verify --strict "$app"
    echo "Built $app ($bundle), SDK $sdk_version / minOS 11.0"
    [ "$build_only" -eq 0 ] || return 0

    installed_bundle=$bundle
    bounded "$run_timeout" xcrun simctl install "$device" "$app"
    status=0
    # Explicitly pass an empty value in ordinary cases so an inherited
    # SIMCTL_CHILD override cannot silently turn the default-policy test off.
    bounded "$run_timeout" env \
        SIMCTL_CHILD_LC32_DISABLE_UIKIT_COMPATIBILITY="$disable_compatibility" \
        SIMCTL_CHILD_LC32_TEST_EFFECTIVE_SDK="$effective_sdk" \
        xcrun simctl launch --console "$device" "$bundle" \
        >"$workdir/$variant.log" 2>&1 || status=$?
    echo "SDK layout launch status ($variant): $status"
    sed -n '1,160p' "$workdir/$variant.log"
    bounded 10 xcrun simctl terminate "$device" "$bundle" >/dev/null 2>&1 || :
    bounded 10 xcrun simctl uninstall "$device" "$bundle"
    installed_bundle=
    if [ "$has_fix" = YES ]; then
        [ "$status" -eq 0 ] && grep -q 'sdk-layout-regression: PASS' "$workdir/$variant.log"
    else
        # Some simctl versions return zero after an app's SIGABRT. Require
        # the probe's exact UIKit exception instead, but reject a timed-out
        # or signalled launcher (our alarm timeout exits with status 142).
        [ "$status" -lt 128 ] &&
            grep -Fq 'sdk-layout-uncaught: NSInternalInconsistencyException: Error in compatibility flow' "$workdir/$variant.log" &&
            ! grep -q 'sdk-layout-regression: PASS' "$workdir/$variant.log"
    fi
}

build_case sdk0 0.0 0 YES "$workdir/fixed" NO
build_case sdk7 7.0 458752 YES "$workdir/fixed" NO
build_case sdk8 8.0 524288 YES "$workdir/fixed" YES
build_case sdk10-3 10.3 656128 YES "$workdir/fixed" YES
build_case sdk11 11.0 720896 YES "$workdir/fixed" YES
build_case sdk8-disabled 8.0 524288 YES "$workdir/fixed" NO 1
build_case effective-sdk0 11.0 720896 YES "$workdir/effective" NO '' 0
build_case effective-sdk7 11.0 720896 YES "$workdir/effective" NO '' 458752
build_case effective-sdk8 11.0 720896 YES "$workdir/effective" YES '' 524288
build_case effective-sdk11 11.0 720896 YES "$workdir/effective" YES '' 720896
if [ "$baseline" -eq 1 ]; then
    build_case sdk7-baseline 7.0 458752 NO "$workdir/unpatched" NO
fi
