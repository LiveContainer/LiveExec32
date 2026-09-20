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
UIDEVICE_SOURCE="$TEMP_ROOT/UIKit/UIDevice.m"
UICOLOR_SOURCE="$TEMP_ROOT/UIKit/UIColor.m"
CGIMAGE_SOURCE="$TEMP_ROOT/UIKit/LC32CGImageFixture.m"
APPLICATION_SOURCE="$TEMP_ROOT/UIKit/UIApplication.m"

require_line() {
    needle=$1
    file=$2
    if ! grep -Fq -- "$needle" "$file"; then
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
    '(void)LC32InvokeHostSelector(self.host_self, host_cmd' \
    "$FIXTURE_SOURCE"

if grep -Fq 'uint64_t host_ret =' "$FIXTURE_SOURCE"; then
    echo "Void scalar-pointer shims still emit an unused host_ret" >&2
    exit 1
fi

require_line \
    'double host_arg2 = guest_arg2 ? (double)*guest_arg2 : 0.0;' \
    "$NSSTRING_SOURCE"
require_line \
    'LC32HostFloatingIndirectArgument(guest_arg2 ? &host_arg2 : NULL)' \
    "$NSSTRING_SOURCE"
require_line \
    'if(guest_arg2) *guest_arg2 = (float)host_arg2;' \
    "$NSSTRING_SOURCE"

require_line '@dynamic userInterfaceIdiom;' "$UIDEVICE_SOURCE"
if grep -Fq -- '- (int)userInterfaceIdiom' "$UIDEVICE_SOURCE"; then
    echo "Manual UIDevice property adapter still has a generated method" >&2
    exit 1
fi

if grep -Eq '^[-+] .*setStatusBarOrientation:' "$APPLICATION_SOURCE"; then
    echo "Manual UIApplication orientation adapters still have generated methods" >&2
    exit 1
fi
require_line '- (int)statusBarOrientation {' "$APPLICATION_SOURCE"
require_line '- (void)setStatusBarHidden:' "$APPLICATION_SOURCE"

require_line '- (CGColorRef)CGColor {' "$UICOLOR_SOURCE"
require_line \
    'id guest_ret = LC32InvokeHostObjectSelector(self.host_self, host_cmd' \
    "$UICOLOR_SOURCE"
require_line 'return (__bridge CGColorRef)guest_ret;' "$UICOLOR_SOURCE"
require_line \
    '+ (id)colorWithCGColor:(CGColorRef)guest_arg0 {' \
    "$UICOLOR_SOURCE"
require_line \
    'uint64_t host_arg0 = [(__bridge id)guest_arg0 host_self];' \
    "$UICOLOR_SOURCE"
require_line \
    '- (void)setCGColor:(CGColorRef)guest_arg0 {' \
    "$UICOLOR_SOURCE"

if grep -Fq '@dynamic CGColor;' "$UICOLOR_SOURCE"; then
    echo "Generated UIColor still suppresses its CGColor accessor" >&2
    exit 1
fi

require_line '- (CGImageRef)CGImage {' "$CGIMAGE_SOURCE"
require_line 'return (__bridge CGImageRef)guest_ret;' "$CGIMAGE_SOURCE"
require_line '- (id)initWithCGImage:(CGImageRef)guest_arg0 {' "$CGIMAGE_SOURCE"
require_line \
    '- (id)initWithCGImage:(CGImageRef)guest_arg0 scale:(float)guest_arg1 orientation:(int)guest_arg2 {' \
    "$CGIMAGE_SOURCE"
require_line 'uint64_t host_arg0 = [(__bridge id)guest_arg0 host_self];' "$CGIMAGE_SOURCE"
require_line 'double host_arg1 = (double)guest_arg1;' "$CGIMAGE_SOURCE"
require_line 'return LC32AdoptHostInitializerResult(self, host_ret);' "$CGIMAGE_SOURCE"

if grep -Fq 'FIXME: has unhandled types' "$FIXTURE_SOURCE" ||
   grep -Fq 'FIXME: has unhandled types' "$NSSTRING_SOURCE" ||
   grep -Fq 'FIXME: has unhandled types' "$UICOLOR_SOURCE" ||
   grep -Fq 'FIXME: has unhandled types' "$CGIMAGE_SOURCE"; then
    echo "Scalar-pointer fixture was still disabled as unhandled" >&2
    exit 1
fi

echo "GenerateShimAPI scalar pointer fixture: PASS"
