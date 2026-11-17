#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/lc32-classic-presentation.XXXXXX")
echo "Classic presentation geometry artifacts: $work"
xcrun --sdk macosx clang++ -std=c++17 -Wall -Wextra -Werror \
    -framework CoreGraphics "$repo/test/uikit_classic_presentation_geometry.cpp" \
    -o "$work/geometry"
"$work/geometry"
