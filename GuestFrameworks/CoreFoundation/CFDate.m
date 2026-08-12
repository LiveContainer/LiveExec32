#import <CoreFoundation/CoreFoundation+LC32.h>

static uint64_t LC32CFDoubleBits(double value) {
    union {
        double value;
        uint64_t bits;
    } representation = { .value = value };
    return representation.bits;
}

CFDateRef CFDateCreate(CFAllocatorRef allocator, CFAbsoluteTime at) {
    (void)allocator;
    return (CFDateRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateCreate, LC32CFDoubleBits(at));
}

CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef date) {
    if(!date) return 0.0;
    CFAbsoluteTime result = 0.0;
    if(!LC32_CF_CALL(LC32CoreFoundationOpDateGetAbsoluteTime,
            LC32_CF_HOST(date), LC32_CF_U32((uintptr_t)&result))) {
        return 0.0;
    }
    return result;
}

CFTimeInterval CFDateGetTimeIntervalSinceDate(CFDateRef date,
                                               CFDateRef otherDate) {
    if(!date || !otherDate) return 0.0;
    CFTimeInterval result = 0.0;
    if(!LC32_CF_CALL(LC32CoreFoundationOpDateGetTimeIntervalSinceDate,
            LC32_CF_HOST(date), LC32_CF_HOST(otherDate),
            LC32_CF_U32((uintptr_t)&result))) {
        return 0.0;
    }
    return result;
}

CFComparisonResult CFDateCompare(CFDateRef date, CFDateRef otherDate,
                                 void *context) {
    (void)context;
    if(!date || !otherDate) return kCFCompareEqualTo;
    return (CFComparisonResult)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpDateCompare,
        LC32_CF_HOST(date), LC32_CF_HOST(otherDate));
}

CFDateFormatterRef CFDateFormatterCreate(CFAllocatorRef allocator,
        CFLocaleRef locale, CFDateFormatterStyle dateStyle,
        CFDateFormatterStyle timeStyle) {
    (void)allocator;
    return (CFDateFormatterRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterCreate,
        LC32_CF_HOST(locale), LC32_CF_U32(dateStyle),
        LC32_CF_U32(timeStyle));
}

void CFDateFormatterSetFormat(CFDateFormatterRef formatter,
                              CFStringRef formatString) {
    if(!formatter || !formatString) return;
    LC32_CF_CALL(LC32CoreFoundationOpDateFormatterSetFormat,
        LC32_CF_HOST(formatter), LC32_CF_HOST(formatString));
}

CFStringRef CFDateFormatterCreateStringWithAbsoluteTime(
        CFAllocatorRef allocator, CFDateFormatterRef formatter,
        CFAbsoluteTime at) {
    (void)allocator;
    if(!formatter) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpDateFormatterCreateStringWithAbsoluteTime,
        LC32_CF_HOST(formatter), LC32CFDoubleBits(at));
}
