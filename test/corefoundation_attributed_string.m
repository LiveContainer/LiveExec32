#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
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

    if(source) CFRelease(source);
    if(same) CFRelease(same);
    if(different) CFRelease(different);
    if(substring) CFRelease(substring);
    if(replacement) CFRelease(replacement);
    if(mutableString) CFRelease(mutableString);

    [pool drain];
    return failures != 0;
}
