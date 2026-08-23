#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static const void *RetainObject(CFAllocatorRef allocator, const void *value) {
    (void)allocator;
    return [(id)value retain];
}

static void ReleaseObject(CFAllocatorRef allocator, const void *value) {
    (void)allocator;
    [(id)value release];
}

static int report(const char *name, int passed) {
    printf("cfdictionary-callbacks-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    @autoreleasepool {
        static int firstKey;
        static int secondKey;
        const CFDictionaryValueCallBacks valueCallbacks = {
            0, RetainObject, ReleaseObject, NULL, NULL,
        };
        CFMutableDictionaryRef dictionary = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 0, NULL, &valueCallbacks);
        int passed = report("create", dictionary != NULL);

        NSMutableString *first =
            [[NSMutableString alloc] initWithString:@"first"];
        CFDictionarySetValue(dictionary, &firstKey, first);
        [first release];
        NSMutableString *borrowed = (NSMutableString *)
            CFDictionaryGetValue(dictionary, &firstKey);
        passed &= report("retained-identity",
            borrowed == first && [borrowed isEqualToString:@"first"]);
        [borrowed appendString:@"-alive"];
        passed &= report("retained-use",
            [(NSString *)CFDictionaryGetValue(dictionary, &firstKey)
                isEqualToString:@"first-alive"]);

        NSMutableString *second =
            [[NSMutableString alloc] initWithString:@"second"];
        CFDictionarySetValue(dictionary, &firstKey, second);
        CFDictionarySetValue(dictionary, &secondKey, second);
        [second release];
        passed &= report("replace-and-alias",
            CFDictionaryGetCount(dictionary) == 2 &&
            CFDictionaryGetValue(dictionary, &firstKey) == second &&
            CFDictionaryGetValue(dictionary, &secondKey) == second);

        CFDictionaryRef copy = CFDictionaryCreateCopy(
            kCFAllocatorDefault, dictionary);
        CFDictionaryRemoveValue(dictionary, &firstKey);
        CFRelease(dictionary);
        passed &= report("copy-lifetime",
            copy != NULL && CFDictionaryGetCount(copy) == 2 &&
            CFDictionaryGetValue(copy, &firstKey) == second &&
            [(NSString *)CFDictionaryGetValue(copy, &secondKey)
                isEqualToString:@"second"]);
        CFRelease(copy);

        printf("cfdictionary-callbacks-regression: %s\n",
            passed ? "PASS" : "FAIL");
        return !passed;
    }
}
