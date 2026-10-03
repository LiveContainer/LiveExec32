#!/bin/sh
# Native SDK 7/11 regression. --platform iphoneos builds signed device probes;
# copy them to a jailbreak-approved test directory and run the same arguments.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
platform=iphonesimulator
device=booted
build_only=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --device) device=$2; shift 2 ;;
        --platform) platform=$2; shift 2 ;;
        --build-only) build_only=1; shift ;;
        *) echo "usage: $0 [--device UDID] [--platform iphoneos] [--build-only]" >&2; exit 2 ;;
    esac
done
case "$platform" in
    iphonesimulator) target=arm64-apple-ios15.0-simulator; platform_id=7 ;;
    iphoneos) target=arm64-apple-ios15.0; platform_id=2; build_only=1 ;;
    *) echo "Unsupported platform: $platform" >&2; exit 2 ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-delayed-presentation.XXXXXX")
trap 'echo "Delayed presentation test artifacts: $work"' EXIT
sdk_root=$(xcrun --sdk "$platform" --show-sdk-path)
for variant in baseline fixed; do
    set -- "$repo/test/uikit_legacy_delayed_presentation.m"
    if [ "$variant" = fixed ]; then
        set -- "$@" "$repo/HostFrameworks/UIKit/LegacyAlerts.mm"
    fi
    xcrun --sdk "$platform" clang -target "$target" -isysroot "$sdk_root" \
        -fobjc-arc -Wall -Wextra -Werror -g -Wl,-headerpad,0x1000 \
        -framework UIKit -framework Foundation -lc++ "$@" -o "$work/$variant"
done
for variant in baseline-sdk7 fixed-sdk7 fixed-sdk11; do
    sdk=7.0
    source=fixed
    expectation=--expect-missing
    case "$variant" in
        baseline-*) source=baseline ;;
        fixed-sdk7) expectation=--expect-alias ;;
        fixed-sdk11) sdk=11.0 ;;
    esac
    binary="$work/$variant"
    xcrun vtool -set-build-version "$platform_id" 15.0 "$sdk" -replace \
        -output "$binary" "$work/$source"
    if [ "$platform" = iphoneos ]; then
        ldid -S "$binary"
    else
        codesign --force --sign - "$binary"
    fi
    echo "$binary $expectation"
    [ "$build_only" -eq 0 ] || continue
    log="$work/$variant.log"
    perl -e 'alarm shift; exec @ARGV; die "exec: $!\n"' 30 \
        xcrun simctl spawn "$device" "$binary" "$expectation" >"$log" 2>&1
    cat "$log"
    grep -q 'legacy-delayed-presentation: PASS' "$log"
done
