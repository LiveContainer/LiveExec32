#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/LiveExec32-GenerateShimAPI-Test.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

"$SCRIPT_DIR/build.sh"
"$SCRIPT_DIR/GenerateShimObjC" \
    "$SCRIPT_DIR/Tests/scalar-pointers.plist" "$TEMP_ROOT"

FIXTURE_SOURCE="$TEMP_ROOT/UIKit/LC32ScalarPointerFixture.m"
NSSTRING_SOURCE="$TEMP_ROOT/UIKit/NSString.m"

require_line() {
    needle=$1
    file=$2
    if ! grep -Fq "$needle" "$file"; then
        echo "Missing generated source in $file: $needle" >&2
        exit 1
    fi
}

require_line \
    'double host_arg0 = guest_arg0 ? (double)*guest_arg0 : 0.0;' \
    "$FIXTURE_SOURCE"
require_line \
    'uint64_t host_arg0 = guest_arg0 ? (uint64_t)*guest_arg0 : 0;' \
    "$FIXTURE_SOURCE"
require_line \
    'double host_arg0 = 0.0;' \
    "$FIXTURE_SOURCE"
require_line \
    'LC32HostFloatingIndirectArgument(guest_arg0 ? &host_arg0 : NULL)' \
    "$FIXTURE_SOURCE"
require_line \
    'LC32HostIndirectArgument(guest_arg0 ? &host_arg0 : NULL)' \
    "$FIXTURE_SOURCE"
require_line \
    'if(guest_arg0) *guest_arg0 = (float)host_arg0;' \
    "$FIXTURE_SOURCE"
require_line \
    'if(guest_arg0) *guest_arg0 = (double)host_arg0;' \
    "$FIXTURE_SOURCE"
require_line \
    'if(guest_arg0) *guest_arg0 = (int)host_arg0;' \
    "$FIXTURE_SOURCE"
require_line \
    '// Input-only scalar pointer guest_arg0 needs no copyback' \
    "$FIXTURE_SOURCE"

require_line \
    'double host_arg2 = guest_arg2 ? (double)*guest_arg2 : 0.0;' \
    "$NSSTRING_SOURCE"
require_line \
    'LC32HostFloatingIndirectArgument(guest_arg2 ? &host_arg2 : NULL)' \
    "$NSSTRING_SOURCE"
require_line \
    'if(guest_arg2) *guest_arg2 = (float)host_arg2;' \
    "$NSSTRING_SOURCE"

if grep -Fq 'FIXME: has unhandled types' "$FIXTURE_SOURCE" ||
   grep -Fq 'FIXME: has unhandled types' "$NSSTRING_SOURCE"; then
    echo "Scalar-pointer fixture was still disabled as unhandled" >&2
    exit 1
fi

echo "GenerateShimAPI scalar pointer fixture: PASS"
