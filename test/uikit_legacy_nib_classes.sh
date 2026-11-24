#!/bin/sh
# Native UIKit decoding regression; does not install or foreground an app.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
device=${1:-booted}
workdir=$(mktemp -d /private/tmp/lc32-nib-classes.XXXXXX)
echo "Legacy nib class artifacts: $workdir"
sdk_root=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios15.0-simulator \
    -isysroot "$sdk_root" -fobjc-arc -g -O0 -Wall -Wextra \
    -Wno-deprecated-declarations -framework UIKit -framework Foundation -framework CoreGraphics \
    "$repo_root/test/uikit_legacy_nib_classes.m" \
    "$repo_root/HostFrameworks/UIKit/LegacyNibClasses.mm" -o "$workdir/test"
codesign --force --sign - "$workdir/test"
xcrun simctl spawn "$device" "$workdir/test"
