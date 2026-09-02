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

static BOOL rangeEquals(CFRange range, CFIndex location, CFIndex length) {
    return range.location == location && range.length == length;
}

typedef struct {
    unsigned calls;
    const void *expectedContext;
} ComparatorContext;

static CFComparisonResult compareStrings(const void *first,
                                         const void *second,
                                         void *rawContext) {
    ComparatorContext *context = rawContext;
    if(context && context->expectedContext == context) ++context->calls;
    return CFStringCompare((CFStringRef)first, (CFStringRef)second, 0);
}

static BOOL arrayEqualsValues(CFArrayRef array, const void **values,
                              CFIndex count) {
    if(!array || CFArrayGetCount(array) != count) return NO;
    for(CFIndex index = 0; index < count; ++index) {
        if(!CFEqual(CFArrayGetValueAtIndex(array, index), values[index]))
            return NO;
    }
    return YES;
}

static void testAllocators(void) {
    void *defaultBytes = CFAllocatorAllocate(
        kCFAllocatorDefault, 32, 0);
    check("allocator-default-allocate", defaultBytes != NULL);
    if(defaultBytes) {
        memset(defaultBytes, 0xa5, 32);
        CFAllocatorDeallocate(kCFAllocatorDefault, defaultBytes);
    }

    void *systemBytes = CFAllocatorAllocate(
        kCFAllocatorSystemDefault, 16, 0);
    check("allocator-system-allocate", systemBytes != NULL);
    CFAllocatorDeallocate(kCFAllocatorSystemDefault, systemBytes);

    check("allocator-null-rejects-allocation",
        CFAllocatorAllocate(kCFAllocatorNull, 16, 0) == NULL);
    CFAllocatorDeallocate(kCFAllocatorNull, NULL);
}

static void testArrays(void) {
    CFMutableArrayRef array = CFArrayCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFArrayAppendValue(array, CFSTR("a"));
    CFArrayAppendValue(array, CFSTR("b"));
    CFArrayAppendValue(array, CFSTR("a"));
    CFArrayAppendValue(array, CFSTR("d"));

    check("array-count-of-value", CFArrayGetCountOfValue(
        array, CFRangeMake(0, 4), CFSTR("a")) == 2);
    check("array-first-index", CFArrayGetFirstIndexOfValue(
        array, CFRangeMake(1, 3), CFSTR("a")) == 2);
    check("array-last-index", CFArrayGetLastIndexOfValue(
        array, CFRangeMake(0, 4), CFSTR("a")) == 2);
    check("array-index-not-found", CFArrayGetFirstIndexOfValue(
        array, CFRangeMake(0, 4), CFSTR("missing")) == kCFNotFound);

    CFArrayExchangeValuesAtIndices(array, 0, 3);
    const void *exchanged[] = {
        CFSTR("d"), CFSTR("b"), CFSTR("a"), CFSTR("a"),
    };
    check("array-exchange", arrayEqualsValues(array, exchanged, 4));

    const void *replacement[] = {
        CFSTR("b"), CFSTR("c"), CFSTR("e"),
    };
    CFArrayReplaceValues(array, CFRangeMake(1, 2), replacement, 3);
    const void *replaced[] = {
        CFSTR("d"), CFSTR("b"), CFSTR("c"), CFSTR("e"), CFSTR("a"),
    };
    check("array-replace-grow", arrayEqualsValues(array, replaced, 5));

    const void *sortedValues[] = {
        CFSTR("a"), CFSTR("c"), CFSTR("e"), CFSTR("g"),
    };
    CFArrayRef sorted = CFArrayCreate(kCFAllocatorDefault, sortedValues,
        4, &kCFTypeArrayCallBacks);
    ComparatorContext context = {0};
    context.expectedContext = &context;
    const CFIndex exact = CFArrayBSearchValues(sorted, CFRangeMake(0, 4),
        CFSTR("e"), compareStrings, &context);
    const CFIndex insertion = CFArrayBSearchValues(sorted,
        CFRangeMake(0, 4), CFSTR("d"), compareStrings, &context);
    const CFIndex afterEnd = CFArrayBSearchValues(sorted,
        CFRangeMake(1, 3), CFSTR("z"), compareStrings, &context);
    check("array-bsearch-exact", exact == 2);
    check("array-bsearch-insertion", insertion == 2);
    check("array-bsearch-range-end", afterEnd == 4);
    check("array-bsearch-guest-callback", context.calls != 0);

    CFArrayRef survivingCopy = CFArrayCreateCopy(
        kCFAllocatorDefault, array);
    CFRelease(array);
    check("array-copy-ownership",
        arrayEqualsValues(survivingCopy, replaced, 5));

    CFRelease(survivingCopy);
    CFRelease(sorted);
}

static void testDictionaries(void) {
    CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(dictionary, CFSTR("one"), CFSTR("shared"));
    CFDictionarySetValue(dictionary, CFSTR("two"), CFSTR("shared"));
    CFDictionarySetValue(dictionary, CFSTR("three"), CFSTR("other"));

    check("dictionary-contains-value",
        CFDictionaryContainsValue(dictionary, CFSTR("shared")));
    check("dictionary-count-of-key", CFDictionaryGetCountOfKey(
        dictionary, CFSTR("one")) == 1);
    check("dictionary-count-of-missing-key", CFDictionaryGetCountOfKey(
        dictionary, CFSTR("missing")) == 0);
    check("dictionary-count-of-value", CFDictionaryGetCountOfValue(
        dictionary, CFSTR("shared")) == 2);

    CFDictionaryReplaceValue(dictionary, CFSTR("one"), CFSTR("new"));
    const void *replacedValue = CFDictionaryGetValue(
        dictionary, CFSTR("one"));
    check("dictionary-replace-value", replacedValue &&
        CFEqual(replacedValue, CFSTR("new")));
    const CFIndex countBeforeMissingReplace =
        CFDictionaryGetCount(dictionary);
    CFDictionaryReplaceValue(
        dictionary, CFSTR("missing"), CFSTR("not-inserted"));
    check("dictionary-replace-does-not-insert",
        CFDictionaryGetCount(dictionary) == countBeforeMissingReplace &&
        !CFDictionaryContainsKey(dictionary, CFSTR("missing")));

    CFRelease(dictionary);
}

static void testSets(void) {
    NSMutableString *original =
        [[NSMutableString alloc] initWithString:@"equal-value"];
    NSMutableString *replacement =
        [[NSMutableString alloc] initWithString:@"equal-value"];
    CFMutableSetRef set = CFSetCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
    CFSetAddValue(set, original);
    CFSetReplaceValue(set, replacement);

    const void *stored = CFSetGetValue(set, CFSTR("equal-value"));
    check("set-replace-count", CFSetGetCount(set) == 1);
    check("set-replace-canonical-object", stored == replacement);

    CFRelease(set);
    [replacement release];
    [original release];
}

static void testData(void) {
    static const UInt8 haystackBytes[] = {'a', 'b', 'c', 'a', 'b', 'c'};
    static const UInt8 needleBytes[] = {'a', 'b', 'c'};
    static const UInt8 missingBytes[] = {'z'};
    CFDataRef haystack = CFDataCreate(
        kCFAllocatorDefault, haystackBytes, sizeof(haystackBytes));
    CFDataRef needle = CFDataCreate(
        kCFAllocatorDefault, needleBytes, sizeof(needleBytes));
    CFDataRef missing = CFDataCreate(
        kCFAllocatorDefault, missingBytes, sizeof(missingBytes));
    CFDataRef empty = CFDataCreate(kCFAllocatorDefault, NULL, 0);

    const CFRange forward = CFDataFind(haystack, needle,
        CFRangeMake(0, sizeof(haystackBytes)), 0);
    const CFRange backward = CFDataFind(haystack, needle,
        CFRangeMake(0, sizeof(haystackBytes)), kCFDataSearchBackwards);
    const CFRange forwardAnchored = CFDataFind(haystack, needle,
        CFRangeMake(0, sizeof(haystackBytes)), kCFDataSearchAnchored);
    const CFRange backwardAnchored = CFDataFind(haystack, needle,
        CFRangeMake(0, sizeof(haystackBytes)),
        kCFDataSearchBackwards | kCFDataSearchAnchored);
    const CFRange restricted = CFDataFind(haystack, needle,
        CFRangeMake(1, 5), 0);
    const CFRange notFound = CFDataFind(haystack, missing,
        CFRangeMake(0, sizeof(haystackBytes)), 0);
    const CFRange emptyNeedle = CFDataFind(haystack, empty,
        CFRangeMake(0, sizeof(haystackBytes)), 0);

    check("data-find-forward-range-abi", rangeEquals(forward, 0, 3));
    check("data-find-backward-range-abi", rangeEquals(backward, 3, 3));
    check("data-find-forward-anchored",
        rangeEquals(forwardAnchored, 0, 3));
    check("data-find-backward-anchored",
        rangeEquals(backwardAnchored, 3, 3));
    check("data-find-restricted-range", rangeEquals(restricted, 3, 3));
    check("data-find-not-found",
        rangeEquals(notFound, kCFNotFound, 0));
    check("data-find-empty-needle",
        rangeEquals(emptyNeedle, kCFNotFound, 0));

    CFRelease(empty);
    CFRelease(missing);
    CFRelease(needle);
    CFRelease(haystack);
}

static void testNumbersAndOwnership(void) {
    SInt32 integerValue = 123;
    Float64 floatingValue = 1.5;
    CFNumberRef integer = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt32Type, &integerValue);
    CFNumberRef floating = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberFloat64Type, &floatingValue);

    check("number-byte-size-integer", CFNumberGetByteSize(integer) == 4);
    check("number-byte-size-floating", CFNumberGetByteSize(floating) == 8);
    check("number-is-float-integer", !CFNumberIsFloatType(integer));
    check("number-is-float-floating", CFNumberIsFloatType(floating));

    CFMutableStringRef owned = CFStringCreateMutableCopy(
        kCFAllocatorDefault, 0, CFSTR("owned"));
    const CFIndex initialRetainCount = CFGetRetainCount(owned);
    CFRetain(owned);
    const CFIndex retainedCount = CFGetRetainCount(owned);
    CFRelease(owned);
    check("get-retain-count", initialRetainCount > 0 &&
        retainedCount == initialRetainCount + 1);
    check("cf-autorelease-return", CFAutorelease(owned) == owned);

    CFRelease(floating);
    CFRelease(integer);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    testAllocators();
    testArrays();
    testDictionaries();
    testSets();
    testData();
    testNumbersAndOwnership();

    [pool drain];
    return failures != 0;
}
