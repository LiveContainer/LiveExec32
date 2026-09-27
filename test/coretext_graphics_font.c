#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static int check(const char *name, int passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return !passed;
}

static int test_layout(CTFontRef font) {
    int failures = 0;
    const UniChar chars[] = {'A', 'b', 'j'};
    struct { uint16_t before; CGGlyph values[3]; uint16_t after; } glyphs =
        {0x1234, {0}, 0x5678};
    bool mapped = CTFontGetGlyphsForCharacters(font, chars, glyphs.values, 3);
    failures += check("font-glyph-map", mapped && glyphs.values[0] &&
        glyphs.values[1] && glyphs.values[2] && glyphs.before == 0x1234 && glyphs.after == 0x5678);
    const UniChar missing = 0xffff;
    CGGlyph absent = 123;
    failures += check("font-missing-glyph-output",
        !CTFontGetGlyphsForCharacters(font, &missing, &absent, 1) && absent == 0);

    struct { uintptr_t before; CGSize values[3]; uintptr_t after; } advances =
        {.before = 0x12345678, .after = 0x76543210};
    const double total = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
        glyphs.values, advances.values, 3);
    const double noOutput = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal,
        glyphs.values, NULL, 3);
    failures += check("font-advances-float-array-and-double-total", total > 0 &&
        fabs(total - noOutput) < 0.001 && fabs(total - advances.values[0].width -
        advances.values[1].width - advances.values[2].width) < 0.001 &&
        advances.before == 0x12345678 && advances.after == 0x76543210);
    struct { uintptr_t before; CGRect values[3]; uintptr_t after; } rects =
        {.before = 0x12345678, .after = 0x76543210};
    CGRect box = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal,
        glyphs.values, rects.values, 3);
    CGRect noRects = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal,
        glyphs.values, NULL, 3);
    failures += check("font-bounding-rects-float-abi", box.size.width > 0 &&
        box.size.height > 0 && fabs(box.size.width - noRects.size.width) < 0.001 &&
        rects.values[0].size.height > 0 && rects.values[1].size.width > 0 &&
        rects.before == 0x12345678 && rects.after == 0x76543210);
    failures += check("font-metrics", CTFontGetAscent(font) > 0 &&
        CTFontGetDescent(font) > 0 && isfinite(CTFontGetLeading(font)) &&
        fabs(CTFontGetSize(font) - 18.25) < 0.001 && isfinite(CTFontGetSlantAngle(font)) &&
        CTFontGetGlyphCount(font) > glyphs.values[2] &&
        !(CTFontGetSymbolicTraits(font) & kCTFontItalicTrait));
    CFStringRef family = CTFontCopyFamilyName(font);
    CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(font);
    CTFontRef resized = CTFontCreateCopyWithAttributes(font, 36.5, NULL, descriptor);
    failures += check("font-family-descriptor-copy", family && CFStringGetLength(family) &&
        descriptor && resized && fabs(CTFontGetSize(resized) - 36.5) < 0.001 &&
        CTFontGetUnderlineThickness(font) > 0);
    if(family) CFRelease(family);
    if(descriptor) CFRelease(descriptor);
    if(resized) CFRelease(resized);

    const void *keys[] = {kCTFontAttributeName};
    const void *values[] = {font};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef string = CFAttributedStringCreate(NULL, CFSTR("Abj"), attributes);
    CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString(string);
    CFRelease(string);
    CFRelease(attributes);
    CTLineRef line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0));
    CTLineRef partial = CTTypesetterCreateLine(typesetter, CFRangeMake(1, 2));
    failures += check("typesetter-line-break-double-width",
        CTTypesetterSuggestLineBreak(typesetter, 0, 10000.25) == 3 &&
        CTTypesetterSuggestLineBreak(typesetter, 1, 10000.25) == 2);
    CFRelease(typesetter);
    failures += check("typesetter-owned-lines-and-ranges", line && partial &&
        CTLineGetGlyphCount(line) == 3 && CTLineGetGlyphCount(partial) == 2 &&
        CTLineGetStringRange(partial).location == 1);
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
    struct { CGPoint values[3]; uintptr_t guard; } copiedPositions = {.guard = 0x12345678};
    struct { CGSize values[3]; uintptr_t guard; } copiedAdvances = {.guard = 0x12345678};
    struct { CFIndex values[3]; uintptr_t guard; } indices = {.guard = 0x12345678};
    struct { CGGlyph values[3]; uint16_t guard; } copiedGlyphs = {.guard = 0x1234};
    CTRunGetGlyphs(run, CFRangeMake(0, 0), copiedGlyphs.values);
    CTRunGetPositions(run, CFRangeMake(0, 0), copiedPositions.values);
    CTRunGetAdvances(run, CFRangeMake(0, 0), copiedAdvances.values);
    CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.values);
    failures += check("run-copy-arrays-32-bit-layout", copiedGlyphs.guard == 0x1234 &&
        copiedPositions.guard == 0x12345678 && copiedAdvances.guard == 0x12345678 &&
        indices.guard == 0x12345678 && indices.values[0] == 0 && indices.values[2] == 2 &&
        !memcmp(copiedGlyphs.values, glyphs.values, sizeof(glyphs.values)) &&
        copiedPositions.values[1].x > copiedPositions.values[0].x &&
        copiedAdvances.values[0].width > 0);
    CTRunGetStringIndices(run, CFRangeMake(1, 1), indices.values);
    failures += check("run-partial-copy-range", indices.values[0] == 1 &&
        indices.values[1] == 1 && indices.guard == 0x12345678);
    double lineWidth = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    failures += check("line-pen-offset-double-return",
        fabs(CTLineGetPenOffsetForFlush(line, 0.5, lineWidth + 100.25) - 50.125) < 0.001);
    const CGPoint *positions = CTRunGetPositionsPtr(run);
    CGPoint saved[3] = {};
    if(positions) memcpy(saved, positions, sizeof(saved));
    const CGGlyph *runGlyphs = CTRunGetGlyphsPtr(run);
    failures += check("run-glyph-position-pointers-independent", CTRunGetGlyphCount(run) == 3 &&
        positions && runGlyphs && memcmp(runGlyphs, glyphs.values, sizeof(glyphs.values)) == 0 &&
        memcmp(positions, saved, sizeof(saved)) == 0 &&
        CTRunGetPositionsPtr(run) == positions &&
        memcmp(runGlyphs, glyphs.values, sizeof(glyphs.values)) == 0);

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    uint8_t bitmap[64 * 256] = {};
    CGContextRef context = CGBitmapContextCreate(bitmap, 64, 64, 8, 256, space,
        kCGImageAlphaPremultipliedLast);
    CGRect image = CTLineGetImageBounds(line, context);
    failures += check("line-image-bounds", isfinite(image.origin.x) &&
        isfinite(image.origin.y) && image.size.width > 0 && image.size.height > 0);
    CGFontRef graphics = CTFontCopyGraphicsFont(font, NULL);
    CGFontRef named = CGFontCreateWithFontName(CFSTR("ArialMT"));
    struct { uintptr_t before; CGRect values[3]; uintptr_t after; } boxes =
        {.before = 0x12345678, .after = 0x76543210};
    failures += check("cgfont-name-metrics-and-bounds", graphics && named &&
        CGFontGetNumberOfGlyphs(graphics) == (size_t)CTFontGetGlyphCount(font) &&
        isfinite(CGFontGetItalicAngle(graphics)) && CGFontGetLeading(graphics) >= 0 &&
        CGFontGetGlyphBBoxes(graphics, glyphs.values, 3, boxes.values) &&
        boxes.values[0].size.height > 0 && boxes.values[2].size.width > 0 &&
        boxes.before == 0x12345678 && boxes.after == 0x76543210);
    CGContextSetFont(context, graphics);
    CGContextSetFontSize(context, 18.25);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextSetAllowsFontSmoothing(context, true);
    CGContextSetShouldSmoothFonts(context, true);
    CGContextSetAllowsFontSubpixelQuantization(context, false);
    CGContextSetShouldSubpixelPositionFonts(context, true);
    const CGPoint locations[] = {{1.25, 24.5}, {18.5, 24.5}, {40.25, 24.5}};
    CGContextShowGlyphsAtPositions(context, glyphs.values, locations, 3);
    CGContextFlush(context);
    const uint8_t *pixels = CGBitmapContextGetData(context);
    int ink[3] = {};
    const size_t stride = CGBitmapContextGetBytesPerRow(context);
    if(pixels) for(size_t y = 0; y < 64; ++y) {
        for(size_t x = 0; x < 64; ++x) if(pixels[y * stride + x * 4 + 3]) {
            ink[x < 16 ? 0 : x < 36 ? 1 : 2]++;
        }
    }
    failures += check("positioned-glyphs-and-bitmap-size", pixels &&
        CGBitmapContextGetWidth(context) == 64 && CGBitmapContextGetHeight(context) == 64 &&
        ink[0] > 0 && ink[1] > 0 && ink[2] > 0);
    CGContextClearRect(context, CGRectMake(0, 0, 64, 64));
    CTFontDrawGlyphs(font, glyphs.values, locations, 3, context);
    unsigned drawn = 0;
    for(size_t i = 3; i < sizeof(bitmap); i += 4) drawn += bitmap[i] != 0;
    failures += check("coretext-draw-glyphs-sync-bitmap", drawn > 0);
    if(graphics) CGFontRelease(graphics);
    if(named) CGFontRelease(named);
    printf("layout-values: %.5f %.5f %.5f %.5f %.5f %.5f %.5f\n", total,
        (double)box.size.width, (double)box.size.height, (double)CTFontGetAscent(font),
        (double)CTFontGetDescent(font), (double)image.size.width, (double)image.size.height);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    CFRelease(partial);
    CFRelease(line);
    return failures;
}

static double width(CTFontRef font) {
    if(!font) return 0;
    const void *keys[] = {kCTFontAttributeName};
    const void *values[] = {font};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFAttributedStringRef text = CFAttributedStringCreate(NULL,
        CFSTR("Graphics font bridge"), attributes);
    CTLineRef line = CTLineCreateWithAttributedString(text);
    double result = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CFRelease(line);
    CFRelease(text);
    CFRelease(attributes);
    return result;
}

int main(int argc, char **argv) {
    if(argc != 2) {
        fprintf(stderr, "usage: %s <font-file>\n", argv[0]);
        return 2;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithFilename(argv[1]);
    CGFontRef graphicsFont = provider ? CGFontCreateWithDataProvider(provider) : NULL;
    if(provider) CGDataProviderRelease(provider);
    if(!graphicsFont) return 3;

    CFDictionaryRef attributes = CFDictionaryCreate(NULL, NULL, NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
    CFRelease(attributes);
    const CGAffineTransform matrix = {1.5f, 0, 0, 1, 2.25f, -0.5f};
    CTFontRef plain = CTFontCreateWithGraphicsFont(graphicsFont, 18.25f, NULL, NULL);
    CTFontRef doubled = CTFontCreateWithGraphicsFont(graphicsFont, 36.5f, NULL, NULL);
    CTFontRef transformed = CTFontCreateWithGraphicsFont(graphicsFont, 18.25f,
        &matrix, descriptor);
    CGFontRelease(graphicsFont);
    if(descriptor) CFRelease(descriptor);

    double a = width(plain), b = width(doubled), c = width(transformed);
    int passed = a > 0 && isfinite(a) && fabs(b / a - 2) < 0.001 &&
        isfinite(c) && fabs(c / a - 1.5) < 0.001;
    printf("coretext-graphics-font: %s (widths %.4f %.4f %.4f)\n",
        passed ? "PASS" : "FAIL", a, b, c);
    int layoutFailures = plain ? test_layout(plain) : 1;
    struct {
        uintptr_t before;
        CTFontDescriptorRef descriptor;
        uintptr_t after;
    } output = {0x12345678, NULL, 0x76543210};
    CGFontRef copied = plain ? CTFontCopyGraphicsFont(plain, &output.descriptor) : NULL;
    CGFontRef copiedWithoutAttributes = plain ? CTFontCopyGraphicsFont(plain, NULL) : NULL;
    if(plain) CFRelease(plain);
    CTFontRef roundTrip = copied ? CTFontCreateWithGraphicsFont(copied, 18.25f,
        NULL, output.descriptor) : NULL;
    int copyPassed = copied && copiedWithoutAttributes &&
        CGFontGetUnitsPerEm(copied) > 0 &&
        CGFontGetUnitsPerEm(copiedWithoutAttributes) == CGFontGetUnitsPerEm(copied) &&
        output.before == 0x12345678 && output.after == 0x76543210;
    if(copied) CGFontRelease(copied);
    if(copiedWithoutAttributes) CGFontRelease(copiedWithoutAttributes);
    if(output.descriptor) CFRelease(output.descriptor);
    copyPassed = copyPassed && roundTrip && fabs(width(roundTrip) - a) < 0.001;
    printf("coretext-copy-graphics-font: %s\n", copyPassed ? "PASS" : "FAIL");
    if(roundTrip) CFRelease(roundTrip);
    if(doubled) CFRelease(doubled);
    if(transformed) CFRelease(transformed);
    return !passed || !copyPassed || layoutFailures;
}
