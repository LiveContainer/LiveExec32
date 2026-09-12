#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#ifndef LC32_LOCALE_NATIVE_CHECK
_Static_assert(sizeof(void *) == 4, "locale constants must work in ARM32 guests");
#endif

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL checkLocaleKeyExports(void) {
    // Every NSLocaleKey in the iOS 10.3 public header has a CF counterpart.
    // These are value aliases; separate bridged proxies need not be identical.
    const struct {
        const char *name;
        NSString *nsKey;
        CFStringRef cfKey;
    } keys[] = {
        {"NSLocaleIdentifier", NSLocaleIdentifier, kCFLocaleIdentifier},
        {"NSLocaleLanguageCode", NSLocaleLanguageCode, kCFLocaleLanguageCode},
        {"NSLocaleCountryCode", NSLocaleCountryCode, kCFLocaleCountryCode},
        {"NSLocaleScriptCode", NSLocaleScriptCode, kCFLocaleScriptCode},
        {"NSLocaleVariantCode", NSLocaleVariantCode, kCFLocaleVariantCode},
        {"NSLocaleExemplarCharacterSet", NSLocaleExemplarCharacterSet,
            kCFLocaleExemplarCharacterSet},
        {"NSLocaleCalendar", NSLocaleCalendar, kCFLocaleCalendar},
        {"NSLocaleCollationIdentifier", NSLocaleCollationIdentifier,
            kCFLocaleCollationIdentifier},
        {"NSLocaleUsesMetricSystem", NSLocaleUsesMetricSystem,
            kCFLocaleUsesMetricSystem},
        {"NSLocaleMeasurementSystem", NSLocaleMeasurementSystem,
            kCFLocaleMeasurementSystem},
        {"NSLocaleDecimalSeparator", NSLocaleDecimalSeparator,
            kCFLocaleDecimalSeparator},
        {"NSLocaleGroupingSeparator", NSLocaleGroupingSeparator,
            kCFLocaleGroupingSeparator},
        {"NSLocaleCurrencySymbol", NSLocaleCurrencySymbol,
            kCFLocaleCurrencySymbol},
        {"NSLocaleCurrencyCode", NSLocaleCurrencyCode, kCFLocaleCurrencyCode},
        {"NSLocaleCollatorIdentifier", NSLocaleCollatorIdentifier,
            kCFLocaleCollatorIdentifier},
        {"NSLocaleQuotationBeginDelimiterKey", NSLocaleQuotationBeginDelimiterKey,
            kCFLocaleQuotationBeginDelimiterKey},
        {"NSLocaleQuotationEndDelimiterKey", NSLocaleQuotationEndDelimiterKey,
            kCFLocaleQuotationEndDelimiterKey},
        {"NSLocaleAlternateQuotationBeginDelimiterKey",
            NSLocaleAlternateQuotationBeginDelimiterKey,
            kCFLocaleAlternateQuotationBeginDelimiterKey},
        {"NSLocaleAlternateQuotationEndDelimiterKey",
            NSLocaleAlternateQuotationEndDelimiterKey,
            kCFLocaleAlternateQuotationEndDelimiterKey},
        {"NSCurrentLocaleDidChangeNotification", NSCurrentLocaleDidChangeNotification,
            kCFLocaleCurrentLocaleDidChangeNotification},
    };
    BOOL allPresent = YES;
    for(size_t index = 0; index < sizeof(keys) / sizeof(keys[0]); ++index) {
        NSString *nsKey = keys[index].nsKey;
        NSString *cfKey = (NSString *)keys[index].cfKey;
        const BOOL present = nsKey && cfKey &&
            [nsKey isKindOfClass:[NSString class]] &&
            [cfKey isKindOfClass:[NSString class]] && [nsKey length] != 0;
        check(keys[index].name, present && [nsKey isEqualToString:cfKey]);
        allPresent &= present;
        if(present) {
            NSDictionary *dictionary =
                [NSDictionary dictionaryWithObject:@"value" forKey:nsKey];
            check("locale-ns-cf-key-dictionary-equality",
                [[dictionary objectForKey:cfKey] isEqualToString:@"value"]);
        }
    }
    return allPresent;
}

static void checkPOSIXComponents(void) {
    NSDictionary *components =
        [NSLocale componentsFromLocaleIdentifier:@"en_US_POSIX"];
    check("locale-posix-components", components &&
        [[components objectForKey:NSLocaleLanguageCode] isEqualToString:@"en"] &&
        [[components objectForKey:NSLocaleCountryCode] isEqualToString:@"US"] &&
        [[components objectForKey:NSLocaleVariantCode] isEqualToString:@"POSIX"]);

    NSString *identifier = components
        ? [NSLocale localeIdentifierFromComponents:components] : nil;
    NSDictionary *roundtrip = identifier
        ? [NSLocale componentsFromLocaleIdentifier:identifier] : nil;
    check("locale-posix-variant-roundtrip", [identifier isEqualToString:@"en_US_POSIX"] &&
        [[roundtrip objectForKey:NSLocaleVariantCode] isEqualToString:@"POSIX"]);

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    check("locale-posix-variant-value",
        [[locale objectForKey:NSLocaleVariantCode] isEqualToString:@"POSIX"]);
    [locale release];
}

static void checkFormatting(NSLocale *locale, NSString *decimalSeparator,
                             NSString *currencyCode, NSString *currencySymbol,
                             NSString *decimalText, NSString *currencyDigits) {
    check("locale-decimal-separator",
        [[locale objectForKey:NSLocaleDecimalSeparator]
            isEqualToString:decimalSeparator]);
    check("locale-currency-code",
        [[locale objectForKey:NSLocaleCurrencyCode] isEqualToString:currencyCode]);
    check("locale-currency-symbol",
        [[locale objectForKey:NSLocaleCurrencySymbol] isEqualToString:currencySymbol]);

    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setLocale:locale];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setUsesGroupingSeparator:NO];
    [formatter setMinimumFractionDigits:2];
    [formatter setMaximumFractionDigits:2];
    check("locale-decimal-formatting",
        [[formatter stringFromNumber:[NSNumber numberWithDouble:1234.5]]
            isEqualToString:decimalText]);

    [formatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [formatter setUsesGroupingSeparator:NO];
    [formatter setMinimumFractionDigits:2];
    [formatter setMaximumFractionDigits:2];
    NSString *currencyText =
        [formatter stringFromNumber:[NSNumber numberWithDouble:12.5]];
    check("locale-currency-formatting", currencyText &&
        [[formatter currencyCode] isEqualToString:currencyCode] &&
        [currencyText rangeOfString:currencyDigits].location != NSNotFound &&
        [currencyText rangeOfString:currencySymbol].location != NSNotFound);
    // CLDR versions differ in French currency spacing; parsing avoids tying
    // this key-export regression to a particular nonbreaking-space spelling.
    NSNumber *parsed = currencyText ? [formatter numberFromString:currencyText] : nil;
    check("locale-currency-formatting-roundtrip", parsed &&
        fabs([parsed doubleValue] - 12.5) < 0.000001);
    [formatter release];
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    if(checkLocaleKeyExports()) {
        checkPOSIXComponents();

        NSLocale *france = [[NSLocale alloc] initWithLocaleIdentifier:@"fr_FR"];
        NSLocale *unitedStates = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        NSNumber *frMetric = [france objectForKey:NSLocaleUsesMetricSystem];
        NSNumber *usMetric = [unitedStates objectForKey:NSLocaleUsesMetricSystem];
        check("locale-france-uses-metric", frMetric &&
            [frMetric isKindOfClass:[NSNumber class]] && [frMetric boolValue]);
        check("locale-us-does-not-use-metric", usMetric &&
            [usMetric isKindOfClass:[NSNumber class]] && ![usMetric boolValue]);

        checkFormatting(france, @",", @"EUR", @"€", @"1234,50", @"12,50");
        checkFormatting(unitedStates, @".", @"USD", @"$", @"1234.50", @"12.50");
        [unitedStates release];
        [france release];
    }
    [pool drain];
    return failures != 0;
}
