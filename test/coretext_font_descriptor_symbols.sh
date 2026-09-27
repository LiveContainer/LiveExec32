#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/CoreText.framework/CoreText"}

if [ ! -f "$FRAMEWORK" ]; then
    echo "CoreText guest framework not found: $FRAMEWORK" >&2
    exit 1
fi

SYMBOLS=$(nm -gjU "$FRAMEWORK")
for SYMBOL in \
    _CTFontCreateUIFontForLanguage \
    _CTFontCreateWithFontDescriptor \
    _CTFontCreateWithGraphicsFont \
    _CTFontCopyGraphicsFont \
    _CTFontCopyFamilyName \
    _CTFontCopyFontDescriptor \
    _CTFontCreateCopyWithAttributes \
    _CTFontDrawGlyphs \
    _CTFontGetUnderlineThickness \
    _CTLineGetPenOffsetForFlush \
    _CTTypesetterSuggestLineBreak \
    _CTRunGetGlyphs \
    _CTRunGetPositions \
    _CTRunGetAdvances \
    _CTRunGetStringIndices \
    _CTFontGetAdvancesForGlyphs \
    _CTFontGetAscent \
    _CTFontGetBoundingRectsForGlyphs \
    _CTFontGetDescent \
    _CTFontGetGlyphCount \
    _CTFontGetGlyphsForCharacters \
    _CTFontGetLeading \
    _CTFontGetSize \
    _CTFontGetSlantAngle \
    _CTFontGetSymbolicTraits \
    _CTTypesetterCreateLine \
    _CTTypesetterCreateWithAttributedString \
    _CTLineGetGlyphCount \
    _CTLineGetImageBounds \
    _CTRunGetGlyphCount \
    _CTRunGetGlyphsPtr \
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
