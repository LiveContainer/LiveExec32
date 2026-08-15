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

        /*
         * A mutable class-cluster result is represented by a private host
         * string class.  Exercise the NSString bridge primitive inherited by
         * that proxy, including the 32-to-64-bit NSRange argument bridge.
         * Native Foundation still rejects truly immutable receivers.
         */
        NSMutableString *mutable =
            [NSMutableString stringWithString:@"abcdef"];
        [mutable deleteCharactersInRange:NSMakeRange(1, 3)];
        const BOOL deletionPassed = [mutable isEqualToString:@"aef"];
        printf("mutable-delete-range: %s (%s)\n",
               deletionPassed ? "PASS" : "FAIL", mutable.UTF8String);
        failed += deletionPassed ? 0 : 1;

        [mutable replaceCharactersInRange:NSMakeRange(1, 1)
                               withString:@"XYZ"];
        const BOOL replacementPassed = [mutable isEqualToString:@"aXYZf"];
        printf("mutable-replace-range: %s (%s)\n",
               replacementPassed ? "PASS" : "FAIL", mutable.UTF8String);
        failed += replacementPassed ? 0 : 1;

        NSMutableString *occurrences =
            [NSMutableString stringWithString:@"a-b-a"];
        const NSUInteger occurrenceCount =
            [occurrences replaceOccurrencesOfString:@"a"
                                         withString:@"xyz"
                                            options:0
                                              range:NSMakeRange(
                                                  0, occurrences.length)];
        const BOOL occurrencesPassed = occurrenceCount == 2 &&
            [occurrences isEqualToString:@"xyz-b-xyz"];
        printf("mutable-replace-occurrences-range: %s (%lu,%s)\n",
               occurrencesPassed ? "PASS" : "FAIL",
               (unsigned long)occurrenceCount, occurrences.UTF8String);
        failed += occurrencesPassed ? 0 : 1;
        return failed ? 1 : 0;
    }
}
