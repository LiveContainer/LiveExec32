#!/bin/sh
# Opt-in native iPhone/iPad simulator regression; no Mac UI automation.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device=${1:?usage: uikit_screen_metrics.sh SIMULATOR_UDID}
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-screen-metrics.XXXXXX")
run_id=$(basename "$work" | tr -cd '[:alnum:]')
installed=
bounded() { perl -e 'alarm shift; exec @ARGV; die "exec: $!\n"' "$@"; }
cleanup() {
    result=$?
    trap - EXIT INT TERM
    if [ -n "$installed" ]; then
        bounded 10 xcrun simctl terminate "$device" "$installed" >/dev/null 2>&1 || :
        bounded 10 xcrun simctl uninstall "$device" "$installed" >/dev/null 2>&1 || :
    fi
    echo "Screen-metrics artifacts: $work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
compile() {
    xcrun --sdk iphonesimulator clang++ -target arm64-apple-ios15.0-simulator \
        -std=c++17 -fobjc-arc -O2 -g -Wall -Wextra -Werror \
        -Wno-deprecated-declarations -framework UIKit -framework Foundation "$@"
}
compile -Wl,-headerpad,0x1000 -Wl,-export_dynamic \
    "$repo/test/uikit_screen_metrics.mm" \
    "$repo/HostFrameworks/UIKit/LegacyAutoLayout.mm" -o "$work/fixture"
for hooks in 0 1; do
    compile -dynamiclib -Wl,-undefined,dynamic_lookup \
        -DLC32_SCREEN_METRICS_PROBE=1 -DLC32_UIKIT_COMPATIBILITY="$hooks" \
        "$repo/test/uikit_screen_metrics.mm" \
        "$repo/HostFrameworks/UIKit/GuestScreenMetrics.mm" \
        "$repo/HostFrameworks/LC32/host_selector_hooks.mm" -o "$work/probe$hooks.dylib"
    codesign -f -s - "$work/probe$hooks.dylib"
    for sdk in 7 11; do
        app="$work/sdk$sdk-hooks$hooks.app"
        bundle="org.liveexec32.test.screenmetrics.$run_id.sdk$sdk.hooks$hooks"
        mkdir "$app"
        plist="$app/Info.plist"
        plutil -create xml1 "$plist"
        plutil -insert CFBundleIdentifier -string "$bundle" "$plist"
        plutil -insert CFBundleExecutable -string ScreenMetrics "$plist"
        plutil -insert CFBundleName -string ScreenMetrics "$plist"
        plutil -insert CFBundlePackageType -string APPL "$plist"
        plutil -insert CFBundleVersion -string 1 "$plist"
        plutil -insert CFBundleShortVersionString -string 1.0 "$plist"
        plutil -insert MinimumOSVersion -string 11.0 "$plist"
        plutil -insert LSRequiresIPhoneOS -bool YES "$plist"
        plutil -insert CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' "$plist"
        plutil -insert UIDeviceFamily -json '[1,2]' "$plist"
        plutil -insert UISupportedInterfaceOrientations -json '["UIInterfaceOrientationPortrait"]' "$plist"
        plutil -insert LC32Probe -string "$work/probe$hooks.dylib" "$plist"
        plutil -insert LC32Hooks -integer "$hooks" "$plist"
        plutil -insert LC32ExpectedSDK -integer "$((sdk * 65536))" "$plist"
        xcrun vtool -set-build-version 7 11.0 "$sdk.0" -replace -output "$app/ScreenMetrics" "$work/fixture"
        codesign -f -s - "$app"
        installed=$bundle
        bounded 20 xcrun simctl install "$device" "$app"
        for disabled in 0 1; do
            log="$work/sdk$sdk-hooks$hooks-disabled$disabled.log"
            bounded 30 env SIMCTL_CHILD_LC32_DISABLE_UIKIT_COMPATIBILITY="$disabled" \
                xcrun simctl launch --console "$device" "$bundle" >"$log" 2>&1
            cat "$log"
            rg -q 'screen-metrics-regression: PASS' "$log"
        done
        bounded 10 xcrun simctl uninstall "$device" "$bundle"
        installed=
    done
done
