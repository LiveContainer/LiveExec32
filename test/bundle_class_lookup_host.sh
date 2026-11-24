#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-bundle-classes.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/stubs/LC32"
printf '\n' > "$work/stubs/LC32/LC32.h"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror \
    -Wno-incomplete-implementation -Wno-objc-protocol-method-implementation \
    -I"$work/stubs" \
    -framework Foundation "$repo/test/bundle_class_lookup_host.m" -o "$work/test"
"$work/test"

guest_sdk=${ISYSROOT:-"$repo/tmp/iPhoneOS10.3.sdk"}
if [ -d "$guest_sdk" ]; then
    xcrun clang -target armv7s-apple-ios10.0 -isysroot "$guest_sdk" \
        -fno-objc-arc -fmodules -fmodules-cache-path="$work/modules" \
        -fsyntax-only -Wall -Wextra -Werror -Wno-deprecated-module-dot-map \
        -I"$repo/GuestFrameworks" -I"$repo/include" \
        -Wno-objc-protocol-method-implementation \
        "$repo/GuestFrameworks/Foundation/NSBundle+LC32Classes.m"
    echo 'bundle guest class lookup (ARM32 syntax): PASS'
fi
