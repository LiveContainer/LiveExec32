#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/debug/armv7s/CoreText.framework/CoreText"}

if [ ! -f "$FRAMEWORK" ]; then
    echo "CoreText guest framework not found: $FRAMEWORK" >&2
    exit 1
fi

SYMBOLS=$(nm -gjU "$FRAMEWORK")
for SYMBOL in \
    _CTFontCreateUIFontForLanguage \
    _CTFontCreateWithFontDescriptor \
    _CTFontDescriptorCreateWithAttributes \
    _CTFrameGetPath \
    _CTRunGetPositionsPtr \
    _CTRunGetStatus \
    _kCTFontFamilyNameAttribute \
    _kCTFontSizeAttribute
do
    if ! printf '%s\n' "$SYMBOLS" | grep -qx "$SYMBOL"; then
        echo "missing CoreText export: $SYMBOL" >&2
        exit 1
    fi
done

echo "coretext-font-descriptor-symbols: PASS"
