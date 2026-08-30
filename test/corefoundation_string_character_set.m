#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

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

static void testStrings(void) {
    char noCopyBytes[] = "original";
    CFStringRef noCopy = CFStringCreateWithCStringNoCopy(
        kCFAllocatorDefault, noCopyBytes, kCFStringEncodingUTF8,
        kCFAllocatorNull);
    noCopyBytes[0] = 'X';
    check("string-cstring-no-copy-safe-copy",
        stringEquals(noCopy, @"original"));

    static const char fileSystemBytes[] = "caf\xc3\xa9";
    CFStringRef fileSystemString = CFStringCreateWithFileSystemRepresentation(
        kCFAllocatorDefault, fileSystemBytes);
    const CFIndex maximum = fileSystemString
        ? CFStringGetMaximumSizeOfFileSystemRepresentation(fileSystemString)
        : 0;
    char representation[16] = {};
    const Boolean represented = fileSystemString &&
        CFStringGetFileSystemRepresentation(fileSystemString,
            representation, sizeof(representation));
    CFStringRef representedString = represented
        ? CFStringCreateWithFileSystemRepresentation(
            kCFAllocatorDefault, representation)
        : NULL;
    char tooSmall[5] = {};
    check("string-filesystem-create",
        stringEquals(fileSystemString, @"caf\u00e9"));
    check("string-filesystem-maximum", maximum >= 10);
    check("string-filesystem-representation", represented &&
        representedString &&
        CFStringCompare(fileSystemString, representedString,
            kCFCompareNonliteral) == kCFCompareEqualTo);
    check("string-filesystem-capacity", fileSystemString &&
        !CFStringGetFileSystemRepresentation(
            fileSystemString, tooSmall, sizeof(tooSmall)));
    const UniChar embeddedNULCharacters[] = {'a', 0, 'b'};
    CFStringRef embeddedNUL = CFStringCreateWithCharacters(
        kCFAllocatorDefault, embeddedNULCharacters, 3);
    char embeddedNULBuffer[8] = {};
    check("string-filesystem-embedded-nul", embeddedNUL &&
        !CFStringGetFileSystemRepresentation(
            embeddedNUL, embeddedNULBuffer, sizeof(embeddedNULBuffer)));

    const void *parts[] = {CFSTR("one"), CFSTR("two"), CFSTR("three")};
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, parts, 3,
        &kCFTypeArrayCallBacks);
    CFStringRef combined = CFStringCreateByCombiningStrings(
        kCFAllocatorDefault, array, CFSTR("/"));
    CFRelease(array);
    check("string-combine-copy-ownership",
        stringEquals(combined, @"one/two/three"));

    CFMutableStringRef mutable = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR("alpha beta"));
    CFStringDelete(mutable, CFRangeMake(5, 1));
    CFStringInsert(mutable, 5, CFSTR("-"));
    CFStringReplace(mutable, CFRangeMake(6, 4), CFSTR("GAMMA"));
    check("string-delete-insert-replace",
        stringEquals(mutable, @"alpha-GAMMA"));
    CFStringReplaceAll(mutable, CFSTR("hello world"));
    CFLocaleRef locale = CFLocaleCopyCurrent();
    CFStringCapitalize(mutable, locale);
    check("string-replace-all-capitalize",
        stringEquals(mutable, @"Hello World"));

    CFTypeRef country = locale
        ? CFLocaleGetValue(locale, kCFLocaleCountryCode) : NULL;
    check("locale-get-value", !country ||
        CFGetTypeID(country) == CFStringGetTypeID());

    check("string-double-value", CFStringGetDoubleValue(
        CFSTR("-12.5 trailing")) == -12.5);
    const CFRange composed = CFStringGetRangeOfComposedCharactersAtIndex(
        CFSTR("Ae\u0301B"), 1);
    check("string-composed-range-abi",
        composed.location == 1 && composed.length == 2);

    if(locale) CFRelease(locale);
    if(mutable) CFRelease(mutable);
    if(combined) CFRelease(combined);
    if(representedString) CFRelease(representedString);
    if(fileSystemString) CFRelease(fileSystemString);
    if(embeddedNUL) CFRelease(embeddedNUL);
    if(noCopy) CFRelease(noCopy);
}

static void testCharacterSets(void) {
    CFCharacterSetRef digits = CFCharacterSetGetPredefined(
        kCFCharacterSetDecimalDigit);
    check("character-set-type-id", digits &&
        CFCharacterSetGetTypeID() != 0 &&
        CFGetTypeID(digits) == CFCharacterSetGetTypeID());
    check("character-set-predefined", digits &&
        CFCharacterSetIsCharacterMember(digits, '5') &&
        !CFCharacterSetIsCharacterMember(digits, 'A'));

    CFCharacterSetRef range = CFCharacterSetCreateWithCharactersInRange(
        kCFAllocatorDefault, CFRangeMake('A', 3));
    CFCharacterSetRef string = CFCharacterSetCreateWithCharactersInString(
        kCFAllocatorDefault, CFSTR("xz"));
    CFCharacterSetRef inverted = CFCharacterSetCreateInvertedSet(
        kCFAllocatorDefault, string);
    check("character-set-range", range &&
        CFCharacterSetIsCharacterMember(range, 'A') &&
        CFCharacterSetIsCharacterMember(range, 'C') &&
        !CFCharacterSetIsCharacterMember(range, 'D'));
    check("character-set-inverted", inverted &&
        !CFCharacterSetIsCharacterMember(inverted, 'x') &&
        CFCharacterSetIsCharacterMember(inverted, 'y'));

    CFMutableCharacterSetRef mutable = CFCharacterSetCreateMutable(
        kCFAllocatorDefault);
    CFCharacterSetAddCharactersInRange(mutable, CFRangeMake('A', 3));
    CFCharacterSetAddCharactersInString(mutable, CFSTR("xz"));
    CFCharacterSetRemoveCharactersInRange(mutable, CFRangeMake('B', 1));
    CFCharacterSetRemoveCharactersInString(mutable, CFSTR("z"));
    CFCharacterSetUnion(mutable, digits);
    check("character-set-mutation", mutable &&
        CFCharacterSetIsCharacterMember(mutable, 'A') &&
        !CFCharacterSetIsCharacterMember(mutable, 'B') &&
        CFCharacterSetIsCharacterMember(mutable, '5') &&
        CFCharacterSetIsCharacterMember(mutable, 'x') &&
        !CFCharacterSetIsCharacterMember(mutable, 'z'));
    CFCharacterSetIntersect(mutable, range);
    check("character-set-intersection", mutable &&
        CFCharacterSetIsCharacterMember(mutable, 'A') &&
        !CFCharacterSetIsCharacterMember(mutable, '5'));
    CFCharacterSetInvert(mutable);
    check("character-set-invert-mutable", mutable &&
        !CFCharacterSetIsCharacterMember(mutable, 'A') &&
        CFCharacterSetIsCharacterMember(mutable, 'B'));

    CFDataRef bitmap = range ? CFCharacterSetCreateBitmapRepresentation(
        kCFAllocatorDefault, range) : NULL;
    CFCharacterSetRef bitmapCopy = bitmap
        ? CFCharacterSetCreateWithBitmapRepresentation(
            kCFAllocatorDefault, bitmap) : NULL;
    CFCharacterSetRef survivingCopy = range
        ? CFCharacterSetCreateCopy(kCFAllocatorDefault, range) : NULL;
    CFMutableCharacterSetRef mutableCopy = range
        ? CFCharacterSetCreateMutableCopy(kCFAllocatorDefault, range) : NULL;
    if(range) CFRelease(range);
    check("character-set-bitmap-roundtrip", bitmapCopy &&
        CFCharacterSetIsCharacterMember(bitmapCopy, 'B'));
    check("character-set-copy-ownership", survivingCopy &&
        CFCharacterSetIsCharacterMember(survivingCopy, 'C'));
    check("character-set-mutable-copy", mutableCopy &&
        CFCharacterSetIsSupersetOfSet(mutableCopy, survivingCopy));

    CFCharacterSetRef emoji = CFCharacterSetCreateWithCharactersInString(
        kCFAllocatorDefault, CFSTR("\U0001f600"));
    check("character-set-long-character", emoji &&
        CFCharacterSetIsLongCharacterMember(emoji, 0x1f600) &&
        CFCharacterSetHasMemberInPlane(emoji, 1));

    if(emoji) CFRelease(emoji);
    if(mutableCopy) CFRelease(mutableCopy);
    if(survivingCopy) CFRelease(survivingCopy);
    if(bitmapCopy) CFRelease(bitmapCopy);
    if(bitmap) CFRelease(bitmap);
    if(mutable) CFRelease(mutable);
    if(inverted) CFRelease(inverted);
    if(string) CFRelease(string);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    testStrings();
    testCharacterSets();

    [pool drain];
    return failures != 0;
}
