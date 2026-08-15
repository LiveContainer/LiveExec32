#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
SDKROOT=${SDKROOT:-"$REPO_ROOT/../SDKs/iPhoneOS10.3.sdk"}
OUTPUT=${1:-/private/tmp/lc32-arc-proxy-lifetime}
ARC_OBJECT=${OUTPUT}.arc.o
SUPPORT_OBJECT=${OUTPUT}.support.o
FRAMEWORK_DIR="$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s"

clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fobjc-arc -fblocks -c "$SCRIPT_DIR/arc_proxy_lifetime.m" \
    -o "$ARC_OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fno-objc-arc -fblocks -c "$SCRIPT_DIR/arc_proxy_lifetime_support.m" \
    -o "$SUPPORT_OBJECT"
clang -arch armv7s -isysroot "$SDKROOT" -miphoneos-version-min=10.3 \
    -fobjc-arc -fblocks "$ARC_OBJECT" "$SUPPORT_OBJECT" \
    -F"$FRAMEWORK_DIR" \
    -framework Foundation -framework UIKit -fno-autolink -o "$OUTPUT"

file "$OUTPUT"
otool -L "$OUTPUT"
