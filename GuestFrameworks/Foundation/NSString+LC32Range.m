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
