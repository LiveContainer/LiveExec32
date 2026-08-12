#import <Foundation/Foundation.h>

#include <stdio.h>

static int CheckRange(const char *name, NSRange actual, NSRange expected) {
    const BOOL passed = NSEqualRanges(actual, expected);
    printf("%s: %s (%lu,%lu)\n", name, passed ? "PASS" : "FAIL",
           (unsigned long)actual.location, (unsigned long)actual.length);
    return passed ? 0 : 1;
}

int main(void) {
    @autoreleasepool {
        NSString *source = @"One fish, two FISH";
        int failed = 0;
        failed += CheckRange("plain", [source rangeOfString:@"fish"],
                             NSMakeRange(4, 4));
        failed += CheckRange(
            "options",
            [source rangeOfString:@"fish"
                          options:NSCaseInsensitiveSearch | NSBackwardsSearch],
            NSMakeRange(14, 4));
        failed += CheckRange(
            "range",
            [source rangeOfString:@"fish"
                          options:NSCaseInsensitiveSearch
                            range:NSMakeRange(5, 8)],
            NSMakeRange(NSNotFound, 0));
        failed += CheckRange(
            "locale",
            [source rangeOfString:@"FISH"
                          options:0
                            range:NSMakeRange(10, 8)
                           locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]],
            NSMakeRange(14, 4));
        return failed ? 1 : 0;
    }
}
