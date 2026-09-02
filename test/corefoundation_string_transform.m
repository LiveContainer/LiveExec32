#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

/* This legacy UIKit constant is supplied by the guest Foundation image. */
extern NSString * const NSFontAttributeName;

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL stringEquals(CFStringRef first, CFStringRef second) {
    return first && second && CFEqual(first, second);
}

static void testConstants(void) {
    check("transform-strip-combining-marks-payload",
        stringEquals(kCFStringTransformStripCombiningMarks,
            CFSTR(")kCFStringTransformStripCombiningMarks")));
    check("transform-to-latin-payload",
        stringEquals(kCFStringTransformToLatin,
            CFSTR(")kCFStringTransformToLatin")));

    check("font-attribute-payload",
        [NSFontAttributeName isEqualToString:@"NSFont"]);
    check("locale-currency-symbol-payload",
        [NSLocaleCurrencySymbol
            isEqualToString:@"kCFLocaleCurrencySymbolKey"]);
    check("memory-stream-data-payload",
        [NSStreamDataWrittenToMemoryStreamKey
            isEqualToString:@"kCFStreamPropertyDataWritten"]);
    check("stream-file-offset-payload",
        [NSStreamFileCurrentOffsetKey
            isEqualToString:@"kCFStreamPropertyFileCurrentOffset"]);
}

static void testFold(void) {
    CFMutableStringRef string = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR("ÉCOLE"));
    CFStringFold(string,
        kCFCompareCaseInsensitive | kCFCompareDiacriticInsensitive, NULL);
    check("fold-case-and-diacritic", stringEquals(string, CFSTR("ecole")));
    CFRelease(string);
}

static void testNormalize(void) {
    CFMutableStringRef string = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR("e\u0301"));
    CFStringNormalize(string, kCFStringNormalizationFormC);
    check("normalize-canonical-compose",
        stringEquals(string, CFSTR("é")) && CFStringGetLength(string) == 1);

    CFStringNormalize(string, kCFStringNormalizationFormD);
    check("normalize-canonical-decompose",
        stringEquals(string, CFSTR("e\u0301")) &&
        CFStringGetLength(string) == 2);
    CFRelease(string);
}

static void testTransform(void) {
    CFMutableStringRef whole = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR("Crème"));
    check("transform-whole-success", CFStringTransform(
        whole, NULL, kCFStringTransformStripCombiningMarks, false));
    check("transform-whole-result", stringEquals(whole, CFSTR("Creme")));
    CFRelease(whole);

    CFMutableStringRef partial = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR("pree\u0301post"));
    CFRange range = CFRangeMake(3, 2);
    check("transform-range-success", CFStringTransform(
        partial, &range, kCFStringTransformStripCombiningMarks, false));
    check("transform-range-result", stringEquals(partial, CFSTR("preepost")));
    check("transform-range-updated",
        range.location == 3 && range.length == 1);

    const CFRange invalidInput = CFRangeMake(
        CFStringGetLength(partial) + 1, 1);
    CFRange invalidRange = invalidInput;
    CFStringRef beforeInvalid = CFStringCreateCopy(
        kCFAllocatorDefault, partial);
    check("transform-invalid-range-rejected", !CFStringTransform(
        partial, &invalidRange,
        kCFStringTransformStripCombiningMarks, false));
    check("transform-invalid-range-preserved",
        invalidRange.location == invalidInput.location &&
        invalidRange.length == invalidInput.length &&
        stringEquals(partial, beforeInvalid));
    CFRelease(beforeInvalid);

    CFRange failedRange = CFRangeMake(0, CFStringGetLength(partial));
    const CFRange failedInput = failedRange;
    CFStringRef beforeFailure = CFStringCreateCopy(
        kCFAllocatorDefault, partial);
    check("transform-unknown-id-rejected", !CFStringTransform(
        partial, &failedRange, CFSTR("not-a-valid-transform"), false));
    check("transform-failure-preserved",
        failedRange.location == failedInput.location &&
        failedRange.length == failedInput.length &&
        stringEquals(partial, beforeFailure));
    CFRelease(beforeFailure);
    CFRelease(partial);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    testConstants();
    testFold();
    testNormalize();
    testTransform();
    [pool drain];
    return failures ? 1 : 0;
}
