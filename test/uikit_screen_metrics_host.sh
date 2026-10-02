#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-screen-metrics-host.XXXXXX")
echo "Screen-metrics host artifacts: $work"
for mode in 0 1; do
    for spi in 0 1; do
        xcrun --sdk macosx clang++ -std=c++17 -fobjc-arc -Wall -Wextra -Werror \
            -DLC32_UIKIT_COMPATIBILITY="$mode" -DLC32_TEST_MODE_SPI="$spi" \
            -I"$repo/test/screen-metrics-stubs" -framework Foundation -framework CoreGraphics \
            "$repo/test/uikit_screen_metrics_host.mm" \
            "$repo/HostFrameworks/UIKit/GuestScreenMetrics.mm" \
            "$repo/HostFrameworks/LC32/host_selector_hooks.mm" -o "$work/test"
        for legacy in 0 1; do
            echo "Screen-metrics host: compatibility=$mode private-api=$spi legacy=$legacy"
            LC32_TEST_LEGACY=$legacy "$work/test"
        done
    done
done
