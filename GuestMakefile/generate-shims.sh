#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
GENERATOR_DIR="$REPO_ROOT/Generator/GenerateShimAPI"
SIGNATURES="$REPO_ROOT/Generator/templates/generated.plist"
FRAMEWORK_MAP="$REPO_ROOT/Generator/templates/generated-framework-map.plist"
OUTPUT_ROOT="$REPO_ROOT/GuestFrameworks/.generated"

staging=$(mktemp -d "$REPO_ROOT/GuestFrameworks/.generated-stage.XXXXXX")
backup="$REPO_ROOT/GuestFrameworks/.generated-backup.$$"

cleanup() {
    [ ! -e "$staging" ] || rm -rf "$staging"
}
trap cleanup EXIT HUP INT TERM

"$GENERATOR_DIR/build.sh"
"$GENERATOR_DIR/GenerateShimObjC" \
    "$SIGNATURES" "$staging" \
    --framework-map "$FRAMEWORK_MAP" \
    --runtime-uikit

bad_file=$(find "$staging" -type f -name '*.m' \
    ! -exec sh -c 'IFS= read -r line < "$1"; [ "$line" = "// Generated file" ]' sh {} \; \
    -print | head -n 1)
if [ -n "$bad_file" ]; then
    echo "Generated source is missing its marker: $bad_file" >&2
    exit 1
fi

file_count=$(find "$staging" -type f -name '*.m' | wc -l | tr -d ' ')
framework_count=$(find "$staging" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$file_count" -eq 0 ] || [ "$framework_count" -eq 0 ]; then
    echo "Generator produced no guest framework sources" >&2
    exit 1
fi
printf 'files=%s\nframeworks=%s\n' "$file_count" "$framework_count" \
    > "$staging/.complete"

if [ -L "$OUTPUT_ROOT" ] || { [ -e "$OUTPUT_ROOT" ] && [ ! -d "$OUTPUT_ROOT" ]; }; then
    echo "Refusing to replace non-directory generated output: $OUTPUT_ROOT" >&2
    exit 1
fi
if [ -e "$backup" ]; then
    echo "Refusing to overwrite generation backup: $backup" >&2
    exit 1
fi

if [ -d "$OUTPUT_ROOT" ]; then
    mv "$OUTPUT_ROOT" "$backup"
fi
if mv "$staging" "$OUTPUT_ROOT"; then
    staging="$REPO_ROOT/GuestFrameworks/.generated-stage-consumed.$$"
    [ ! -d "$backup" ] || rm -rf "$backup"
else
    [ ! -d "$backup" ] || mv "$backup" "$OUTPUT_ROOT"
    exit 1
fi

echo "Generated $file_count shims for $framework_count guest frameworks"
