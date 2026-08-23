#ifndef LC32_CORE_TEXT_BRIDGE_H
#define LC32_CORE_TEXT_BRIDGE_H

#include <stdint.h>

enum {
    LC32CoreTextABIVersion = 1,
    LC32CoreTextMaxSlots = 16,
    LC32CoreTextMaximumParagraphSettings = 64,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32CoreTextMaxSlots];
} LC32CoreTextCall;

/* Fixed-width representations used where CoreText's public ABI changes from
 * 32-bit CGFloat/CFIndex to their 64-bit native equivalents. */
typedef struct {
    uint32_t first;
    uint32_t second;
} LC32CoreTextPair32;

typedef struct {
    uint32_t valueLow;
    uint32_t valueHigh;
    uint32_t ascent;
    uint32_t descent;
    uint32_t leading;
} LC32CoreTextTypographicBounds32;

typedef enum : uint32_t {
    LC32CoreTextParagraphValueByte = 1,
    LC32CoreTextParagraphValueFloat = 2,
    LC32CoreTextParagraphValueObject = 3,
    LC32CoreTextParagraphValueUInt32 = 4,
} LC32CoreTextParagraphValueKind;

typedef struct {
    uint32_t specifier;
    uint32_t kind;
    uint64_t value;
} LC32CoreTextParagraphSetting;

typedef enum : uint32_t {
    LC32CoreTextOpFontCreateWithName = 1,
    LC32CoreTextOpFrameDraw = 2,
    LC32CoreTextOpFrameGetLineOrigins = 3,
    LC32CoreTextOpFrameGetLines = 4,
    LC32CoreTextOpFramesetterCreateFrame = 5,
    LC32CoreTextOpFramesetterCreateWithAttributedString = 6,
    LC32CoreTextOpFramesetterSuggestFrameSizeWithConstraints = 7,
    LC32CoreTextOpLineCreateTruncatedLine = 8,
    LC32CoreTextOpLineCreateWithAttributedString = 9,
    LC32CoreTextOpLineDraw = 10,
    LC32CoreTextOpLineGetGlyphRuns = 11,
    LC32CoreTextOpLineGetOffsetForStringIndex = 12,
    LC32CoreTextOpLineGetStringIndexForPosition = 13,
    LC32CoreTextOpLineGetStringRange = 14,
    LC32CoreTextOpLineGetTypographicBounds = 15,
    LC32CoreTextOpParagraphStyleCreate = 16,
    LC32CoreTextOpRunGetAttributes = 17,
    LC32CoreTextOpRunGetStringRange = 18,
    LC32CoreTextOpRunGetTypographicBounds = 19,
    LC32CoreTextOpFontDescriptorCreateWithAttributes = 20,
    LC32CoreTextOpFontCreateWithFontDescriptor = 21,
    LC32CoreTextOpFontCreateUIFontForLanguage = 22,
    LC32CoreTextOpFrameGetPath = 23,
    LC32CoreTextOpRunCopyPositions = 24,
    LC32CoreTextOpRunGetStatus = 25,
} LC32CoreTextOpcode;

#endif
