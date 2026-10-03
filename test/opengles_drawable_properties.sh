#!/bin/sh
# Builds a native probe that loads the supplied host framework. No GPU required.
# For iphoneos, copy the printed executable and framework to the device first.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
platform=iphonesimulator
device=booted
while [ "$#" -gt 0 ]; do
    case "$1" in
        --platform) platform=$2; shift 2 ;;
        --device) device=$2; shift 2 ;;
        *) break ;;
    esac
done
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 [--platform iphoneos|iphonesimulator] [--device UDID] framework-binary [--expect-stale]" >&2
    exit 2
fi
case "$platform" in
    iphonesimulator) target=arm64-apple-ios15.0-simulator ;;
    iphoneos) target=arm64-apple-ios15.0 ;;
    *) echo "Unsupported platform: $platform" >&2; exit 2 ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-drawable-properties.XXXXXX")
trap 'echo "Drawable property test artifacts: $work"' EXIT
sdk_root=$(xcrun --sdk "$platform" --show-sdk-path)
xcrun --sdk "$platform" clang -target "$target" -isysroot "$sdk_root" \
    -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework QuartzCore \
    -framework OpenGLES "$repo/test/opengles_drawable_properties.m" -o "$work/probe"
if [ "$platform" = iphoneos ]; then
    ldid -S "$work/probe"
    echo "Device probe: $work/probe $*"
else
    codesign --force --sign - "$work/probe"
    perl -e 'alarm shift; exec @ARGV; die "exec: $!\n"' 30 \
        xcrun simctl spawn "$device" "$work/probe" "$@"
fi
