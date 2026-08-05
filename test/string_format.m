#import <Foundation/Foundation.h>

#include <stdarg.h>
#include <stdio.h>

@interface NSString (LC32PrivateVariadicTest)
+ (instancetype)stringWithFormat:(NSString *)format locale:(id)locale, ...;
@end

@interface LC32FormatDescription : NSObject
@end

@implementation LC32FormatDescription
- (NSString *)description {
    return @"guest-description";
}
@end

static int check(const char *name, NSString *actual, NSString *expected) {
    BOOL passed = [actual isEqualToString:expected];
    printf("%s: %s (length=%u)\n", name, passed ? "PASS" : "FAIL",
           (unsigned)[actual length]);
    return !passed;
}

static NSString *formatWithArguments(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *result = [[NSString alloc] initWithFormat:format
                                              arguments:arguments];
    va_end(arguments);
    return result;
}

static NSString *formatWithLocaleArguments(NSString *format,
                                           id locale,
                                           ...) {
    va_list arguments;
    va_start(arguments, locale);
    NSString *result = [[NSString alloc] initWithFormat:format
                                                  locale:locale
                                               arguments:arguments];
    va_end(arguments);
    return result;
}

int main(void) {
    int failed = 0;
    failed += check("none", [NSString stringWithFormat:@"literal"],
                    @"literal");
    failed += check("object-r3", [NSString stringWithFormat:@"<%@>", @"object"],
                    @"<object>");
    LC32FormatDescription *guestObject = [LC32FormatDescription new];
    failed += check("object-guest-reentry",
                    [NSString stringWithFormat:@"<%@>", guestObject],
                    @"<guest-description>");
    failed += check("integer-spill",
                    [NSString stringWithFormat:@"%d/%u/%x", -7, 9u, 0x2au],
                    @"-7/9/2a");
    failed += check("mixed",
                    [NSString stringWithFormat:@"%@ %.2f %s", @"mix", 3.5,
                                               "tail"],
                    @"mix 3.50 tail");
    // CoreFoundation renders unknown %b/%B conversions literally and does
    // not consume an argument for them.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat"
    failed += check("unknown-non-consuming",
                    [NSString stringWithFormat:@"%b/%@", @"after"],
                    @"b/after");
#pragma clang diagnostic pop

    NSString *embeddedNUL =
        [[NSString stringWithFormat:@"%C", 0]
            stringByAppendingString:@"%@"];
    NSString *embeddedNULExpected =
        [[NSString stringWithFormat:@"%C", 0]
            stringByAppendingString:@"after"];
    failed += check("embedded-nul",
                    [NSString stringWithFormat:embeddedNUL, @"after"],
                    embeddedNULExpected);

    failed += check("width-precision",
                    [NSString stringWithFormat:@"%*.*f", 7, 2, 3.5],
                    @"   3.50");

    long signedLong = -42;
    unsigned long unsignedLong = 0xfedcba98UL;
    failed += check("guest-long-widening",
                    [NSString stringWithFormat:@"%ld/%lu", signedLong,
                                               unsignedLong],
                    @"-42/4275878552");
    failed += check("int64",
                    [NSString stringWithFormat:@"%llx",
                                               0x1122334455667788ULL],
                    @"1122334455667788");
    failed += check("positional",
                    [NSString stringWithFormat:@"%2$@/%1$d", 7, @"pos"],
                    @"pos/7");
    failed += check("localized",
                    [NSString localizedStringWithFormat:@"%@", @"localized"],
                    @"localized");
    failed += check("private-format-locale",
                    [NSString stringWithFormat:@"%@/%d"
                                       locale:nil, @"private", 10],
                    @"private/10");
    failed += check("arguments-list",
                    formatWithArguments(@"%@/%d", @"arguments", 11),
                    @"arguments/11");
    failed += check("locale-arguments-list",
                    formatWithLocaleArguments(@"%@/%d", nil, @"locale", 12),
                    @"locale/12");

    NSString *base = @"prefix";
    failed += check("append-format",
                    [base stringByAppendingFormat:@"/%@/%d", @"suffix", 13],
                    @"prefix/suffix/13");

    NSMutableString *mutable = [NSMutableString stringWithString:@"mutable"];
    [mutable appendFormat:@"/%@/%d", @"append", 14];
    failed += check("mutable-append-format", mutable,
                    @"mutable/append/14");
    return failed;
}
