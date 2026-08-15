#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static bool finite_nonnegative(CGFloat value) {
    return isfinite((double)value) && value >= 0;
}

int main(void) {
    bool creationPassed = false;
    bool metricsPassed = false;
    bool framePassed = false;

    CTTextAlignment alignment = kCTTextAlignmentCenter;
    CTLineBreakMode lineBreakMode = kCTLineBreakByWordWrapping;
    CGFloat paragraphSpacingBefore = 3.5f;
    const CTParagraphStyleSetting paragraphSettings[] = {
        {kCTParagraphStyleSpecifierAlignment,
            sizeof(alignment), &alignment},
        {kCTParagraphStyleSpecifierLineBreakMode,
            sizeof(lineBreakMode), &lineBreakMode},
        {kCTParagraphStyleSpecifierParagraphSpacingBefore,
            sizeof(paragraphSpacingBefore), &paragraphSpacingBefore},
    };
    CTParagraphStyleRef paragraphStyle = CTParagraphStyleCreate(
        paragraphSettings,
        sizeof(paragraphSettings) / sizeof(paragraphSettings[0]));
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 18, NULL);
    CGAffineTransform fontTransform = CGAffineTransformMake(
        1, 0, 0, 1, 0.25f, 0.5f);
    CTFontRef transformedFont = CTFontCreateWithName(
        CFSTR("Helvetica"), 18, &fontTransform);

    CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if(attributes && font && paragraphStyle) {
        CFDictionarySetValue(attributes, kCTFontAttributeName, font);
        CFDictionarySetValue(attributes,
            kCTParagraphStyleAttributeName, paragraphStyle);
    }
    CFAttributedStringRef string = attributes
        ? CFAttributedStringCreate(NULL,
            CFSTR("CoreText bridge metrics and drawing"), attributes)
        : NULL;
    creationPassed = paragraphStyle && font && transformedFont && string;
    printf("coretext-creation: %s\n", creationPassed ? "PASS" : "FAIL");

    CTLineRef line = string
        ? CTLineCreateWithAttributedString(string) : NULL;
    CGFloat ascent = 0, descent = 0, leading = 0;
    const double lineWidth = line ? CTLineGetTypographicBounds(
        line, &ascent, &descent, &leading) : 0;
    const CFRange lineRange = line
        ? CTLineGetStringRange(line) : CFRangeMake(0, 0);
    CGFloat secondaryOffset = 0;
    const CGFloat offset = line
        ? CTLineGetOffsetForStringIndex(line, 4, &secondaryOffset) : 0;
    const CFIndex stringIndex = line
        ? CTLineGetStringIndexForPosition(line,
            CGPointMake(offset, 0)) : kCFNotFound;
    CFArrayRef runs = line ? CTLineGetGlyphRuns(line) : NULL;
    CTRunRef firstRun = runs && CFArrayGetCount(runs)
        ? (CTRunRef)CFArrayGetValueAtIndex(runs, 0) : NULL;
    CFDictionaryRef runAttributes = firstRun
        ? CTRunGetAttributes(firstRun) : NULL;
    const CFRange runRange = firstRun
        ? CTRunGetStringRange(firstRun) : CFRangeMake(0, 0);
    CGFloat runAscent = 0, runDescent = 0, runLeading = 0;
    const double runWidth = firstRun ? CTRunGetTypographicBounds(
        firstRun, CFRangeMake(0, 0),
        &runAscent, &runDescent, &runLeading) : 0;
    CTLineRef truncated = line
        ? CTLineCreateTruncatedLine(
            line, lineWidth * 0.5, kCTLineTruncationEnd, NULL)
        : NULL;
    metricsPassed = line && lineWidth > 0 && finite_nonnegative(ascent) &&
        finite_nonnegative(descent) && finite_nonnegative(leading) &&
        lineRange.location == 0 && lineRange.length > 0 &&
        finite_nonnegative(offset) && finite_nonnegative(secondaryOffset) &&
        stringIndex != kCFNotFound && runs && firstRun && runAttributes &&
        runRange.location >= 0 && runRange.length > 0 && runWidth > 0 &&
        finite_nonnegative(runAscent) && finite_nonnegative(runDescent) &&
        finite_nonnegative(runLeading) && truncated;
    printf("coretext-line-metrics: %s\n",
        metricsPassed ? "PASS" : "FAIL");

    CTFramesetterRef framesetter = string
        ? CTFramesetterCreateWithAttributedString(string) : NULL;
    CFRange fitRange = CFRangeMake(0, 0);
    const CGSize suggested = framesetter
        ? CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
            CFRangeMake(0, 0), NULL, CGSizeMake(180, 1000), &fitRange)
        : CGSizeZero;
    CGMutablePathRef path = CGPathCreateMutable();
    if(path) CGPathAddRect(path, NULL, CGRectMake(0, 0, 180, 200));
    CTFrameRef frame = framesetter && path
        ? CTFramesetterCreateFrame(framesetter,
            CFRangeMake(0, 0), path, NULL) : NULL;
    CFArrayRef lines = frame ? CTFrameGetLines(frame) : NULL;
    const CFIndex lineCount = lines ? CFArrayGetCount(lines) : 0;
    CGPoint *origins = lineCount > 0
        ? calloc((size_t)lineCount, sizeof(*origins)) : NULL;
    if(origins) CTFrameGetLineOrigins(
        frame, CFRangeMake(0, 0), origins);

    uint8_t pixels[180 * 200 * 4];
    memset(pixels, 0xa5, sizeof(pixels));
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = colorSpace ? CGBitmapContextCreate(
        pixels, 180, 200, 8, 180 * 4, colorSpace,
        kCGImageAlphaPremultipliedLast) : NULL;
    if(context && frame) CTFrameDraw(frame, context);
    if(context && line) {
        CGContextSetTextPosition(context, 0, 40);
        CTLineDraw(line, context);
    }
    bool pixelsChanged = false;
    for(size_t index = 0; index < sizeof(pixels); index++) {
        if(pixels[index] != 0xa5) {
            pixelsChanged = true;
            break;
        }
    }
    framePassed = framesetter && finite_nonnegative(suggested.width) &&
        finite_nonnegative(suggested.height) && fitRange.location == 0 &&
        fitRange.length > 0 && path && frame && lines && lineCount > 0 &&
        origins && isfinite((double)origins[0].x) &&
        isfinite((double)origins[0].y) && context && pixelsChanged;
    printf("coretext-frame-drawing: %s\n",
        framePassed ? "PASS" : "FAIL");

    free(origins);
    if(context) CGContextRelease(context);
    if(colorSpace) CGColorSpaceRelease(colorSpace);
    if(frame) CFRelease(frame);
    if(path) CGPathRelease(path);
    if(framesetter) CFRelease(framesetter);
    if(truncated) CFRelease(truncated);
    if(line) CFRelease(line);
    if(string) CFRelease(string);
    if(attributes) CFRelease(attributes);
    if(transformedFont) CFRelease(transformedFont);
    if(font) CFRelease(font);
    if(paragraphStyle) CFRelease(paragraphStyle);

    return !(creationPassed && metricsPassed && framePassed);
}
