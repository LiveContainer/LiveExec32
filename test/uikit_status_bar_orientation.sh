#!/bin/sh
# Compile the production guest adapters against a deterministic macOS host.
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workdir=$(mktemp -d "${TMPDIR:-/tmp}/lc32-status-orientation.XXXXXX")
trap 'rm -rf -- "$workdir"' EXIT
for mode in 0 1; do
    xcrun --sdk macosx clang -Wall -Wextra -Werror -fobjc-arc -fblocks \
        -DLC32_UIKIT_COMPATIBILITY="$mode" \
        -I"$repo_root/test/orientation-stubs" -framework Foundation \
        "$repo_root/test/uikit_status_bar_orientation_host.m" \
        "$repo_root/GuestFrameworks/UIKit/UIApplication+LC32LegacyOrientation.m" \
        -o "$workdir/orientation-$mode"
    for disabled in 0 1; do
        LC32_ORIENTATION_TEST_DISABLE_POLICY=$disabled "$workdir/orientation-$mode"
    done
done
