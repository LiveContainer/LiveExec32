#import <CoreText/CoreText.h>
#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>
#import "LC32CoreTextBridge.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_once_t LC32CoreTextDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32CoreTextDispatcherAddress;

static void LC32CoreTextResolveDispatcher(void) {
    LC32CoreTextDispatcherAddress = LC32Dlsym("LC32_CoreText_Dispatch", YES);
}

static uint32_t LC32CoreTextDispatch(LC32CoreTextOpcode opcode,
                                     const uint64_t *slots,
                                     uint32_t slotCount) {
    if(slotCount > LC32CoreTextMaxSlots) return 0;
    pthread_once(&LC32CoreTextDispatcherOnce, LC32CoreTextResolveDispatcher);
    if(!LC32CoreTextDispatcherAddress) return 0;

    LC32CoreTextCall call = {
        .version = LC32CoreTextABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32CoreTextDispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}

static uint64_t LC32CoreTextHostObject(const void *object) {
    return object ? [(id)object host_self] : 0;
}

static uint64_t LC32CoreTextFloat(CGFloat value) {
    union {
        float value;
        uint32_t bits;
    } converted = {.value = (float)value};
    return converted.bits;
}

static uint64_t LC32CoreTextDouble(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static CGFloat LC32CoreTextResultFloat(uint32_t bits) {
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static double LC32CoreTextResultDouble(
        const LC32CoreTextTypographicBounds32 *response) {
    const uint64_t bits = (uint64_t)response->valueLow |
        ((uint64_t)response->valueHigh << 32);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

#define LC32_CT_CALL0(opcode) \
    LC32CoreTextDispatch((opcode), NULL, 0)
#define LC32_CT_CALL(opcode, ...) \
    LC32CoreTextDispatch((opcode), (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / sizeof(uint64_t)))
#define LC32_CT_U32(value) ((uint64_t)(uint32_t)(value))
#define LC32_CT_INDEX(value) ((uint64_t)(uint32_t)(int32_t)(value))
#define LC32_CT_F32(value) LC32CoreTextFloat((CGFloat)(value))
#define LC32_CT_HOST(value) LC32CoreTextHostObject((const void *)(value))

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size,
                               const CGAffineTransform *matrix) {
    if(!name) return NULL;
    return (CTFontRef)LC32_CT_CALL(LC32CoreTextOpFontCreateWithName,
        LC32_CT_HOST(name), LC32_CT_F32(size), LC32_CT_U32(matrix != NULL),
        matrix ? LC32_CT_F32(matrix->a) : 0,
        matrix ? LC32_CT_F32(matrix->b) : 0,
        matrix ? LC32_CT_F32(matrix->c) : 0,
        matrix ? LC32_CT_F32(matrix->d) : 0,
        matrix ? LC32_CT_F32(matrix->tx) : 0,
        matrix ? LC32_CT_F32(matrix->ty) : 0);
}

CTFontDescriptorRef CTFontDescriptorCreateWithAttributes(
        CFDictionaryRef attributes) {
    return attributes ? (CTFontDescriptorRef)LC32_CT_CALL(
        LC32CoreTextOpFontDescriptorCreateWithAttributes,
        LC32_CT_HOST(attributes)) : NULL;
}

CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor,
                                         CGFloat size,
                                         const CGAffineTransform *matrix) {
    if(!descriptor) return NULL;
    return (CTFontRef)LC32_CT_CALL(
        LC32CoreTextOpFontCreateWithFontDescriptor,
        LC32_CT_HOST(descriptor), LC32_CT_F32(size),
        LC32_CT_U32(matrix != NULL),
        matrix ? LC32_CT_F32(matrix->a) : 0,
        matrix ? LC32_CT_F32(matrix->b) : 0,
        matrix ? LC32_CT_F32(matrix->c) : 0,
        matrix ? LC32_CT_F32(matrix->d) : 0,
        matrix ? LC32_CT_F32(matrix->tx) : 0,
        matrix ? LC32_CT_F32(matrix->ty) : 0);
}

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType uiType,
                                        CGFloat size,
                                        CFStringRef language) {
    return (CTFontRef)LC32_CT_CALL(
        LC32CoreTextOpFontCreateUIFontForLanguage,
        LC32_CT_U32(uiType), LC32_CT_F32(size), LC32_CT_HOST(language));
}

void CTFrameDraw(CTFrameRef frame, CGContextRef context) {
    if(!frame || !context) return;
    (void)LC32_CT_CALL(LC32CoreTextOpFrameDraw,
        LC32_CT_HOST(frame), LC32_CT_HOST(context));
}

void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range,
                           CGPoint origins[]) {
    if(!frame || !origins) return;
    (void)LC32_CT_CALL(LC32CoreTextOpFrameGetLineOrigins,
        LC32_CT_HOST(frame), LC32_CT_INDEX(range.location),
        LC32_CT_INDEX(range.length), LC32_CT_U32((uintptr_t)origins));
}

CFArrayRef CTFrameGetLines(CTFrameRef frame) {
    return frame ? (CFArrayRef)LC32_CT_CALL(
        LC32CoreTextOpFrameGetLines, LC32_CT_HOST(frame)) : NULL;
}

CGPathRef CTFrameGetPath(CTFrameRef frame) {
    return frame ? (CGPathRef)LC32_CT_CALL(
        LC32CoreTextOpFrameGetPath, LC32_CT_HOST(frame)) : NULL;
}

CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef framesetter,
                                    CFRange stringRange, CGPathRef path,
                                    CFDictionaryRef frameAttributes) {
    if(!framesetter || !path) return NULL;
    return (CTFrameRef)LC32_CT_CALL(LC32CoreTextOpFramesetterCreateFrame,
        LC32_CT_HOST(framesetter), LC32_CT_INDEX(stringRange.location),
        LC32_CT_INDEX(stringRange.length), LC32_CT_HOST(path),
        LC32_CT_HOST(frameAttributes));
}

CTFramesetterRef CTFramesetterCreateWithAttributedString(
        CFAttributedStringRef string) {
    return string ? (CTFramesetterRef)LC32_CT_CALL(
        LC32CoreTextOpFramesetterCreateWithAttributedString,
        LC32_CT_HOST(string)) : NULL;
}

CGSize CTFramesetterSuggestFrameSizeWithConstraints(
        CTFramesetterRef framesetter, CFRange stringRange,
        CFDictionaryRef frameAttributes, CGSize constraints,
        CFRange *fitRange) {
    if(!framesetter) return CGSizeMake(0, 0);
    LC32CoreTextPair32 size = {};
    LC32CoreTextPair32 fit = {};
    const uint32_t ok = LC32_CT_CALL(
        LC32CoreTextOpFramesetterSuggestFrameSizeWithConstraints,
        LC32_CT_HOST(framesetter), LC32_CT_INDEX(stringRange.location),
        LC32_CT_INDEX(stringRange.length), LC32_CT_HOST(frameAttributes),
        LC32_CT_F32(constraints.width), LC32_CT_F32(constraints.height),
        LC32_CT_U32((uintptr_t)&size), LC32_CT_U32(fitRange != NULL),
        LC32_CT_U32((uintptr_t)&fit));
    if(!ok) return CGSizeMake(0, 0);
    if(fitRange) {
        fitRange->location = (CFIndex)(int32_t)fit.first;
        fitRange->length = (CFIndex)(int32_t)fit.second;
    }
    return CGSizeMake(LC32CoreTextResultFloat(size.first),
        LC32CoreTextResultFloat(size.second));
}

CTLineRef CTLineCreateTruncatedLine(CTLineRef line, double width,
                                    CTLineTruncationType truncationType,
                                    CTLineRef truncationToken) {
    if(!line) return NULL;
    return (CTLineRef)LC32_CT_CALL(LC32CoreTextOpLineCreateTruncatedLine,
        LC32_CT_HOST(line), LC32CoreTextDouble(width),
        LC32_CT_U32(truncationType), LC32_CT_HOST(truncationToken));
}

CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef string) {
    return string ? (CTLineRef)LC32_CT_CALL(
        LC32CoreTextOpLineCreateWithAttributedString,
        LC32_CT_HOST(string)) : NULL;
}

void CTLineDraw(CTLineRef line, CGContextRef context) {
    if(!line || !context) return;
    (void)LC32_CT_CALL(LC32CoreTextOpLineDraw,
        LC32_CT_HOST(line), LC32_CT_HOST(context));
}

CFArrayRef CTLineGetGlyphRuns(CTLineRef line) {
    return line ? (CFArrayRef)LC32_CT_CALL(
        LC32CoreTextOpLineGetGlyphRuns, LC32_CT_HOST(line)) : NULL;
}

CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex,
                                      CGFloat *secondaryOffset) {
    if(!line) return 0;
    uint32_t secondaryBits = 0;
    const uint32_t result = LC32_CT_CALL(
        LC32CoreTextOpLineGetOffsetForStringIndex, LC32_CT_HOST(line),
        LC32_CT_INDEX(charIndex), LC32_CT_U32(secondaryOffset != NULL),
        LC32_CT_U32((uintptr_t)&secondaryBits));
    if(secondaryOffset)
        *secondaryOffset = LC32CoreTextResultFloat(secondaryBits);
    return LC32CoreTextResultFloat(result);
}

CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position) {
    if(!line) return kCFNotFound;
    return (CFIndex)(int32_t)LC32_CT_CALL(
        LC32CoreTextOpLineGetStringIndexForPosition, LC32_CT_HOST(line),
        LC32_CT_F32(position.x), LC32_CT_F32(position.y));
}

CFRange CTLineGetStringRange(CTLineRef line) {
    LC32CoreTextPair32 range = {};
    if(!line || !LC32_CT_CALL(LC32CoreTextOpLineGetStringRange,
            LC32_CT_HOST(line), LC32_CT_U32((uintptr_t)&range))) {
        return CFRangeMake(0, 0);
    }
    return CFRangeMake((CFIndex)(int32_t)range.first,
        (CFIndex)(int32_t)range.second);
}

double CTLineGetTypographicBounds(CTLineRef line, CGFloat *ascent,
                                  CGFloat *descent, CGFloat *leading) {
    LC32CoreTextTypographicBounds32 response = {};
    if(!line || !LC32_CT_CALL(LC32CoreTextOpLineGetTypographicBounds,
            LC32_CT_HOST(line), LC32_CT_U32((uintptr_t)&response))) return 0;
    if(ascent) *ascent = LC32CoreTextResultFloat(response.ascent);
    if(descent) *descent = LC32CoreTextResultFloat(response.descent);
    if(leading) *leading = LC32CoreTextResultFloat(response.leading);
    return LC32CoreTextResultDouble(&response);
}

static BOOL LC32CoreTextSerializeParagraphSetting(
        const CTParagraphStyleSetting *source,
        LC32CoreTextParagraphSetting *destination) {
    if(!source || !destination || !source->value) return NO;
    destination->specifier = source->spec;

    switch(source->spec) {
        case kCTParagraphStyleSpecifierAlignment:
        case kCTParagraphStyleSpecifierLineBreakMode:
        case kCTParagraphStyleSpecifierBaseWritingDirection: {
            if(source->valueSize != sizeof(uint8_t)) return NO;
            uint8_t value;
            memcpy(&value, source->value, sizeof(value));
            destination->kind = LC32CoreTextParagraphValueByte;
            destination->value = value;
            return YES;
        }
        case kCTParagraphStyleSpecifierFirstLineHeadIndent:
        case kCTParagraphStyleSpecifierHeadIndent:
        case kCTParagraphStyleSpecifierTailIndent:
        case kCTParagraphStyleSpecifierDefaultTabInterval:
        case kCTParagraphStyleSpecifierLineHeightMultiple:
        case kCTParagraphStyleSpecifierMaximumLineHeight:
        case kCTParagraphStyleSpecifierMinimumLineHeight:
        case kCTParagraphStyleSpecifierLineSpacing:
        case kCTParagraphStyleSpecifierParagraphSpacing:
        case kCTParagraphStyleSpecifierParagraphSpacingBefore:
        case kCTParagraphStyleSpecifierMaximumLineSpacing:
        case kCTParagraphStyleSpecifierMinimumLineSpacing:
        case kCTParagraphStyleSpecifierLineSpacingAdjustment: {
            if(source->valueSize != sizeof(CGFloat)) return NO;
            CGFloat value;
            memcpy(&value, source->value, sizeof(value));
            destination->kind = LC32CoreTextParagraphValueFloat;
            destination->value = LC32CoreTextFloat(value);
            return YES;
        }
        case kCTParagraphStyleSpecifierTabStops: {
            if(source->valueSize != sizeof(CFArrayRef)) return NO;
            CFArrayRef value;
            memcpy(&value, source->value, sizeof(value));
            destination->kind = LC32CoreTextParagraphValueObject;
            destination->value = LC32_CT_HOST(value);
            return YES;
        }
        case kCTParagraphStyleSpecifierLineBoundsOptions: {
            if(source->valueSize != sizeof(CTLineBoundsOptions)) return NO;
            CTLineBoundsOptions value;
            memcpy(&value, source->value, sizeof(value));
            destination->kind = LC32CoreTextParagraphValueUInt32;
            destination->value = (uint32_t)value;
            return YES;
        }
        default:
            return NO;
    }
}

CTParagraphStyleRef CTParagraphStyleCreate(
        const CTParagraphStyleSetting *settings, size_t settingCount) {
    if(settingCount > LC32CoreTextMaximumParagraphSettings ||
       (settingCount && !settings)) return NULL;

    LC32CoreTextParagraphSetting *serialized = NULL;
    if(settingCount) {
        serialized = calloc(settingCount, sizeof(*serialized));
        if(!serialized) return NULL;
        for(size_t index = 0; index < settingCount; index++) {
            if(!LC32CoreTextSerializeParagraphSetting(
                    &settings[index], &serialized[index])) {
                free(serialized);
                return NULL;
            }
        }
    }

    CTParagraphStyleRef result = (CTParagraphStyleRef)LC32_CT_CALL(
        LC32CoreTextOpParagraphStyleCreate,
        LC32_CT_U32((uintptr_t)serialized), LC32_CT_U32(settingCount));
    free(serialized);
    return result;
}

CFDictionaryRef CTRunGetAttributes(CTRunRef run) {
    return run ? (CFDictionaryRef)LC32_CT_CALL(
        LC32CoreTextOpRunGetAttributes, LC32_CT_HOST(run)) : NULL;
}

const CGPoint *CTRunGetPositionsPtr(CTRunRef run) {
    if(!run) return NULL;
    const uint32_t count = LC32_CT_CALL(LC32CoreTextOpRunCopyPositions,
        LC32_CT_HOST(run), 0, 0);
    if(!count || count > UINT32_MAX / sizeof(CGPoint)) return NULL;

    CGPoint *positions = LC32GetAssociatedGuestBuffer(
        (id)run, count * (uint32_t)sizeof(*positions));
    if(!positions) return NULL;
    return LC32_CT_CALL(LC32CoreTextOpRunCopyPositions,
        LC32_CT_HOST(run), LC32_CT_U32((uintptr_t)positions),
        LC32_CT_U32(count)) ? positions : NULL;
}

CTRunStatus CTRunGetStatus(CTRunRef run) {
    return run ? (CTRunStatus)LC32_CT_CALL(
        LC32CoreTextOpRunGetStatus, LC32_CT_HOST(run))
        : kCTRunStatusNoStatus;
}

CFRange CTRunGetStringRange(CTRunRef run) {
    LC32CoreTextPair32 range = {};
    if(!run || !LC32_CT_CALL(LC32CoreTextOpRunGetStringRange,
            LC32_CT_HOST(run), LC32_CT_U32((uintptr_t)&range))) {
        return CFRangeMake(0, 0);
    }
    return CFRangeMake((CFIndex)(int32_t)range.first,
        (CFIndex)(int32_t)range.second);
}

double CTRunGetTypographicBounds(CTRunRef run, CFRange range,
                                 CGFloat *ascent, CGFloat *descent,
                                 CGFloat *leading) {
    LC32CoreTextTypographicBounds32 response = {};
    if(!run || !LC32_CT_CALL(LC32CoreTextOpRunGetTypographicBounds,
            LC32_CT_HOST(run), LC32_CT_INDEX(range.location),
            LC32_CT_INDEX(range.length),
            LC32_CT_U32((uintptr_t)&response))) return 0;
    if(ascent) *ascent = LC32CoreTextResultFloat(response.ascent);
    if(descent) *descent = LC32CoreTextResultFloat(response.descent);
    if(leading) *leading = LC32CoreTextResultFloat(response.leading);
    return LC32CoreTextResultDouble(&response);
}
