#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>

static NSRange LC32StringRange(NSString *source, NSString *needle,
                               NSStringCompareOptions options,
                               NSRange searchRange, NSLocale *locale,
                               LC32FoundationStringRangeVariant variant) {
    const uint64_t hostSource = source.host_self;
    const uint64_t hostNeedle = needle.host_self;
    const uint64_t hostLocale = locale.host_self;
    const LC32FoundationStringRangeRequest request = {
        .version = LC32FoundationStringRangeABIVersion,
        .byteSize = sizeof(request),
        .variant = (uint32_t)variant,
        .options = (uint32_t)options,
        .hostStringLow = (uint32_t)hostSource,
        .hostStringHigh = (uint32_t)(hostSource >> 32),
        .hostNeedleLow = (uint32_t)hostNeedle,
        .hostNeedleHigh = (uint32_t)(hostNeedle >> 32),
        .rangeLocation = (uint32_t)searchRange.location,
        .rangeLength = (uint32_t)searchRange.length,
        .hostLocaleLow = (uint32_t)hostLocale,
        .hostLocaleHigh = (uint32_t)(hostLocale >> 32),
    };
    const uint64_t packed = LC32HostStringRangeOfString(&request);
    return NSMakeRange((NSUInteger)(uint32_t)packed,
                       (NSUInteger)(uint32_t)(packed >> 32));
}

@implementation NSString (LC32Range)

- (NSRange)rangeOfString:(NSString *)searchString {
    return LC32StringRange(self, searchString, 0, NSMakeRange(0, 0), nil,
                           LC32FoundationStringRangePlain);
}

- (NSRange)rangeOfString:(NSString *)searchString
                 options:(NSStringCompareOptions)mask {
    return LC32StringRange(self, searchString, mask, NSMakeRange(0, 0), nil,
                           LC32FoundationStringRangeWithOptions);
}

- (NSRange)rangeOfString:(NSString *)searchString
                 options:(NSStringCompareOptions)mask
                   range:(NSRange)searchRange {
    return LC32StringRange(self, searchString, mask, searchRange, nil,
                           LC32FoundationStringRangeWithRange);
}

- (NSRange)rangeOfString:(NSString *)searchString
                 options:(NSStringCompareOptions)mask
                   range:(NSRange)searchRange
                  locale:(NSLocale *)locale {
    return LC32StringRange(self, searchString, mask, searchRange, locale,
                           LC32FoundationStringRangeWithLocale);
}

@end

@implementation NSString (LC32MutableRange)

typedef struct LC32HostNSRangeValue {
    uint64_t location;
    uint64_t length;
} LC32HostNSRangeValue;

static LC32HostNSRangeValue LC32HostNSRange(NSRange range) {
    const LC32HostNSRangeValue result = {
        (uint64_t)range.location,
        (uint64_t)range.length,
    };
    return result;
}

- (void)deleteCharactersInRange:(NSRange)range {
    /*
     * Widen the ARM32 range into native-width fields, but retain its identity
     * as one logical argument.  The host bridge recognizes native NSRange as
     * an integer composite and places its members in consecutive GPR slots.
     */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const LC32HostNSRangeValue hostRange = LC32HostNSRange(range);
    (void)LC32InvokeHostSelector(
        self.host_self, selector,
        LC32HostAggregateArgument(&hostRange), (uint64_t)0);
}

- (void)replaceCharactersInRange:(NSRange)range
                       withString:(NSString *)replacement {
    /*
     * Keep the following object in logical argument slot one.  Flattening the
     * range into two variadic slots here would make bridge preprocessing
     * mistake its length field for that object before the ABI call is built.
     */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const LC32HostNSRangeValue hostRange = LC32HostNSRange(range);
    (void)LC32InvokeHostSelector(
        self.host_self, selector,
        LC32HostAggregateArgument(&hostRange),
        replacement.host_self, (uint64_t)0);
}

- (NSUInteger)replaceOccurrencesOfString:(NSString *)target
                                withString:(NSString *)replacement
                                   options:(NSStringCompareOptions)options
                                     range:(NSRange)searchRange {
    /*
     * This is used by older Google clients while URL-encoding parameters.
     * Keep the range tagged as one logical argument so the two object
     * arguments and options value remain aligned during bridge preprocessing.
     */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const LC32HostNSRangeValue hostRange = LC32HostNSRange(searchRange);
    return (NSUInteger)LC32InvokeHostSelector(
        self.host_self, selector,
        target.host_self, replacement.host_self, (uint64_t)options,
        LC32HostAggregateArgument(&hostRange), (uint64_t)0);
}

@end
