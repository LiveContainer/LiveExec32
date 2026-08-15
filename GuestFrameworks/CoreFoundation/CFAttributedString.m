#import <CoreFoundation/CoreFoundation+LC32.h>

#include <limits.h>
#include <stdint.h>

static Boolean LC32CFAttributedStringValidRange(CFRange range) {
    return range.location >= 0 && range.length >= 0 &&
        (uint64_t)range.location + (uint64_t)range.length <= INT32_MAX;
}

CFAttributedStringRef CFAttributedStringCreate(
        CFAllocatorRef allocator, CFStringRef string,
        CFDictionaryRef attributes) {
    (void)allocator;
    if(!string) return NULL;
    return (CFAttributedStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringCreate,
        LC32_CF_HOST(string), LC32_CF_HOST(attributes));
}

CFMutableAttributedStringRef CFAttributedStringCreateMutable(
        CFAllocatorRef allocator, CFIndex maximumLength) {
    (void)allocator;
    if(maximumLength < 0 || (uint64_t)maximumLength > INT32_MAX) return NULL;
    return (CFMutableAttributedStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringCreateMutable,
        LC32_CF_U32(maximumLength));
}

CFAttributedStringRef CFAttributedStringCreateWithSubstring(
        CFAllocatorRef allocator, CFAttributedStringRef attributedString,
        CFRange range) {
    (void)allocator;
    if(!attributedString || !LC32CFAttributedStringValidRange(range))
        return NULL;
    return (CFAttributedStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringCreateWithSubstring,
        LC32_CF_HOST(attributedString), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length));
}

CFIndex CFAttributedStringGetLength(
        CFAttributedStringRef attributedString) {
    if(!attributedString) return 0;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringGetLength,
        LC32_CF_HOST(attributedString));
}

void CFAttributedStringReplaceAttributedString(
        CFMutableAttributedStringRef attributedString, CFRange range,
        CFAttributedStringRef replacement) {
    if(!attributedString || !replacement ||
       !LC32CFAttributedStringValidRange(range)) return;
    LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringReplaceAttributedString,
        LC32_CF_HOST(attributedString), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_HOST(replacement));
}
