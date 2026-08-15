#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

#include <stdio.h>

@interface NSIndexSet (LC32NSRangeBridgeTest)
- (NSRange)rangeAtIndex:(NSUInteger)index;
@end

static int CheckRange(const char *name, NSRange actual, NSRange expected) {
    const BOOL passed = NSEqualRanges(actual, expected);
    printf("%s: %s (%lu,%lu)\n", name, passed ? "PASS" : "FAIL",
           (unsigned long)actual.location, (unsigned long)actual.length);
    return passed ? 0 : 1;
}

static int Check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}

int main(void) {
    @autoreleasepool {
        int failed = 0;
        NSString *source = @"abc 123 def 45";

        NSString *substring = [source substringWithRange:NSMakeRange(4, 3)];
        failed += Check("substring-with-range",
                        [substring isEqualToString:@"123"]);

        NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
        failed += CheckRange("range-of-character",
            [source rangeOfCharacterFromSet:digits], NSMakeRange(4, 1));
        failed += CheckRange("range-of-character-options-range",
            [source rangeOfCharacterFromSet:digits
                                    options:NSBackwardsSearch
                                      range:NSMakeRange(0, source.length)],
            NSMakeRange(13, 1));
        failed += CheckRange("range-not-found",
            [@"abcdef" rangeOfCharacterFromSet:digits],
            NSMakeRange(NSNotFound, 0));

        NSCharacterSet *letters =
            [NSCharacterSet characterSetWithRange:NSMakeRange('m', 3)];
        failed += Check("character-set-with-range",
            [letters characterIsMember:'m'] &&
            [letters characterIsMember:'n'] &&
            [letters characterIsMember:'o'] &&
            ![letters characterIsMember:'l'] &&
            ![letters characterIsMember:'p']);

        NSIndexSet *indexes =
            [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(40, 5)];
        failed += Check("index-set-with-range",
            indexes.count == 5 && [indexes containsIndex:42] &&
            ![indexes containsIndex:39] && ![indexes containsIndex:45]);
        failed += CheckRange("index-set-range-at-index",
            [indexes rangeAtIndex:0], NSMakeRange(40, 5));

        NSRegularExpression *expression =
            [NSRegularExpression regularExpressionWithPattern:@"[0-9]+"
                                                       options:0
                                                         error:NULL];
        failed += Check("regular-expression-create", expression != nil);
        failed += CheckRange("regular-expression-range",
            [expression rangeOfFirstMatchInString:source
                                          options:0
                                            range:NSMakeRange(5,
                                                source.length - 5)],
            NSMakeRange(5, 2));

        const LC32NSRange64 widened =
            LC32WidenNSRange(NSMakeRange(NSNotFound, 7));
        failed += Check("range-not-found-guest-to-host",
            widened.location == UINT64_C(0x7fffffffffffffff) &&
            widened.length == 7);
        const LC32NSRange64 nativeNotFound = {
            UINT64_C(0x7fffffffffffffff), 9
        };
        failed += CheckRange("range-not-found-host-to-guest",
            LC32NarrowNSRange(nativeNotFound), NSMakeRange(NSNotFound, 9));
        const LC32NSRange64 overflowing = {UINT64_C(0x100000000), 1};
        failed += CheckRange("range-overflow-host-to-guest",
            LC32NarrowNSRange(overflowing), NSMakeRange(NSNotFound, 0));

        return failed ? 1 : 0;
    }
}
