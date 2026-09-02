#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}

TEMP_FILES=
trap 'rm -f $TEMP_FILES' EXIT HUP INT TERM

audit_image() {
    image=$1
    shift
    if [ ! -f "$image" ]; then
        echo "Guest framework not found: $image" >&2
        exit 1
    fi

    symbols=$(mktemp "${TMPDIR:-/private/tmp}/lc32-graphics-symbols.XXXXXX")
    TEMP_FILES="$TEMP_FILES $symbols"
    xcrun nm -gjU "$image" > "$symbols"
    for symbol in "$@"; do
        if ! grep -qx "_$symbol" "$symbols"; then
            echo "$(basename "$image") is missing export: $symbol" >&2
            exit 1
        fi
    done
}

audit_image "$FRAMEWORK_DIR/CoreGraphics.framework/CoreGraphics" \
    CGContextAddLines \
    CGContextSetGrayStrokeColor \
    CGContextSetLineJoin \
    CGContextSetShadow \
    CGContextSetTextMatrix \
    CGDataProviderCreateWithCFData \
    CGImageCreateCopy \
    CGImageCreate \
    CGImageGetDataProvider \
    CGPathGetBoundingBox

audit_image "$FRAMEWORK_DIR/QuartzCore.framework/QuartzCore" \
    CATransform3DMakeAffineTransform

audit_image "$FRAMEWORK_DIR/UIKit.framework/UIKit" \
    UIAccessibilityPostNotification \
    UIRectFill

echo "Graphics compatibility symbol audit: PASS"
