#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

_Static_assert(sizeof(CFRange) == 8,
               "the guest CFRange ABI must remain two 32-bit words");

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL stringEquals(CFStringRef string, NSString *expected) {
    return string && [(NSString *)string isEqualToString:expected];
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    NSDictionary *attributes = [NSDictionary
        dictionaryWithObject:@"primary" forKey:@"LC32Marker"];
    NSDictionary *otherAttributes = [NSDictionary
        dictionaryWithObject:@"other" forKey:@"LC32Marker"];
    CFAttributedStringRef source = CFAttributedStringCreate(
        kCFAllocatorDefault, CFSTR("abcdef"),
        (CFDictionaryRef)attributes);
    CFAttributedStringRef same = CFAttributedStringCreate(
        kCFAllocatorDefault, CFSTR("abcdef"),
        (CFDictionaryRef)attributes);
    CFAttributedStringRef different = CFAttributedStringCreate(
        kCFAllocatorDefault, CFSTR("abcdef"),
        (CFDictionaryRef)otherAttributes);

    check("attributed-create", source &&
        CFAttributedStringGetLength(source) == 6 &&
        [[(NSAttributedString *)source string] isEqualToString:@"abcdef"]);
    check("attributed-create-attributes", source && same && different &&
        [(NSAttributedString *)source
            isEqualToAttributedString:(NSAttributedString *)same] &&
        ![(NSAttributedString *)source
            isEqualToAttributedString:(NSAttributedString *)different]);

    CFAttributedStringRef substring =
        CFAttributedStringCreateWithSubstring(kCFAllocatorDefault, source,
                                               CFRangeMake(1, 3));
    check("attributed-substring", substring &&
        CFAttributedStringGetLength(substring) == 3 &&
        [[(NSAttributedString *)substring string]
            isEqualToString:@"bcd"]);

    CFMutableAttributedStringRef mutableString =
        CFAttributedStringCreateMutable(kCFAllocatorDefault, 32);
    check("attributed-create-mutable", mutableString &&
        CFAttributedStringGetLength(mutableString) == 0);
    CFAttributedStringReplaceAttributedString(
        mutableString, CFRangeMake(0, 0), source);
    check("attributed-replace-insert", mutableString &&
        CFAttributedStringGetLength(mutableString) == 6 &&
        [[(NSAttributedString *)mutableString string]
            isEqualToString:@"abcdef"]);

    CFAttributedStringRef replacement = CFAttributedStringCreate(
        kCFAllocatorDefault, CFSTR("XYZ"),
        (CFDictionaryRef)otherAttributes);
    CFAttributedStringReplaceAttributedString(
        mutableString, CFRangeMake(1, 3), replacement);
    check("attributed-replace-range", mutableString &&
        CFAttributedStringGetLength(mutableString) == 6 &&
        [[(NSAttributedString *)mutableString string]
            isEqualToString:@"aXYZef"]);

    CFAttributedStringRef copied = CFAttributedStringCreateCopy(
        kCFAllocatorDefault, source);
    CFMutableAttributedStringRef mutableCopy =
        CFAttributedStringCreateMutableCopy(
            kCFAllocatorDefault, 32, source);
    check("attributed-copy", copied && stringEquals(
        CFAttributedStringGetString(copied), @"abcdef"));
    check("attributed-mutable-copy", mutableCopy &&
        CFAttributedStringGetLength(mutableCopy) == 6);

    CFRange attributesRange = CFRangeMake(kCFNotFound, 0);
    CFDictionaryRef copiedAttributes = copied
        ? CFAttributedStringGetAttributes(copied, 2, &attributesRange)
        : NULL;
    const void *copiedMarker = copiedAttributes
        ? CFDictionaryGetValue(copiedAttributes, CFSTR("LC32Marker"))
        : NULL;
    check("attributed-get-attributes-range", copiedMarker &&
        CFEqual(copiedMarker, CFSTR("primary")) &&
        attributesRange.location == 0 && attributesRange.length == 6);

    CFRange attributeRange = CFRangeMake(kCFNotFound, 0);
    CFTypeRef copiedAttribute = copied
        ? CFAttributedStringGetAttribute(copied, 2,
            CFSTR("LC32Marker"), &attributeRange) : NULL;
    check("attributed-get-attribute-range", copiedAttribute &&
        CFEqual(copiedAttribute, CFSTR("primary")) &&
        attributeRange.location == 0 && attributeRange.length == 6);

    CFAttributedStringBeginEditing(mutableCopy);
    CFAttributedStringSetAttribute(mutableCopy, CFRangeMake(1, 3),
        CFSTR("LC32Secondary"), CFSTR("secondary"));
    CFRange longestRange = CFRangeMake(kCFNotFound, 0);
    CFTypeRef secondary = CFAttributedStringGetAttributeAndLongestEffectiveRange(
        mutableCopy, 2, CFSTR("LC32Secondary"), CFRangeMake(0, 6),
        &longestRange);
    check("attributed-longest-effective-range", secondary &&
        CFEqual(secondary, CFSTR("secondary")) &&
        longestRange.location == 1 && longestRange.length == 3);

    NSDictionary *replacementAttributes = [NSDictionary
        dictionaryWithObject:@"replacement" forKey:@"LC32Marker"];
    CFAttributedStringSetAttributes(mutableCopy, CFRangeMake(2, 1),
        (CFDictionaryRef)replacementAttributes, true);
    CFRange longestAttributesRange = CFRangeMake(kCFNotFound, 0);
    CFDictionaryRef longestAttributes =
        CFAttributedStringGetAttributesAndLongestEffectiveRange(
            mutableCopy, 2, CFRangeMake(0, 6),
            &longestAttributesRange);
    const void *replacementMarker = longestAttributes
        ? CFDictionaryGetValue(longestAttributes, CFSTR("LC32Marker"))
        : NULL;
    check("attributed-set-attributes-clear", replacementMarker &&
        CFEqual(replacementMarker, CFSTR("replacement")) &&
        !CFDictionaryContainsKey(
            longestAttributes, CFSTR("LC32Secondary")) &&
        longestAttributesRange.location == 2 &&
        longestAttributesRange.length == 1);

    CFAttributedStringRemoveAttribute(
        mutableCopy, CFRangeMake(2, 1), CFSTR("LC32Marker"));
    check("attributed-remove-attribute",
        !CFAttributedStringGetAttribute(
            mutableCopy, 2, CFSTR("LC32Marker"), NULL));

    CFAttributedStringReplaceString(
        mutableCopy, CFRangeMake(0, 1), CFSTR("ZZ"));
    CFMutableStringRef mutableContents =
        CFAttributedStringGetMutableString(mutableCopy);
    if(mutableContents) CFStringAppend(mutableContents, CFSTR("!"));
    CFAttributedStringEndEditing(mutableCopy);
    check("attributed-replace-and-mutable-string", stringEquals(
        CFAttributedStringGetString(mutableCopy), @"ZZbcdef!"));

    if(source) {
        CFRelease(source);
        source = NULL;
    }
    check("attributed-copy-ownership", copied && stringEquals(
        CFAttributedStringGetString(copied), @"abcdef"));

    if(source) CFRelease(source);
    if(same) CFRelease(same);
    if(different) CFRelease(different);
    if(substring) CFRelease(substring);
    if(replacement) CFRelease(replacement);
    if(mutableString) CFRelease(mutableString);
    if(mutableCopy) CFRelease(mutableCopy);
    if(copied) CFRelease(copied);

    [pool drain];
    return failures != 0;
}
