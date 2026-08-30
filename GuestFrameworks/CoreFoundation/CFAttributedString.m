#import <CoreFoundation/CoreFoundation+LC32.h>

#include <limits.h>
#include <stdint.h>

static Boolean LC32CFAttributedStringValidRange(CFRange range) {
    return range.location >= 0 && range.length >= 0 &&
        (uint64_t)range.location + (uint64_t)range.length <= INT32_MAX;
}

static NSRange LC32CFAttributedStringRange(CFRange range) {
    _Static_assert(sizeof(CFRange) == sizeof(NSRange),
        "CFRange and NSRange must share their ARM32 ABI");
    return NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length);
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

CFAttributedStringRef CFAttributedStringCreateCopy(
        CFAllocatorRef allocator, CFAttributedStringRef attributedString) {
    (void)allocator;
    return attributedString
        ? (CFAttributedStringRef)[(NSAttributedString *)attributedString copy]
        : NULL;
}

CFMutableAttributedStringRef CFAttributedStringCreateMutableCopy(
        CFAllocatorRef allocator, CFIndex maximumLength,
        CFAttributedStringRef attributedString) {
    (void)allocator;
    if(maximumLength < 0 || !attributedString) return NULL;
    return (CFMutableAttributedStringRef)
        [(NSAttributedString *)attributedString mutableCopy];
}

CFStringRef CFAttributedStringGetString(
        CFAttributedStringRef attributedString) {
    return attributedString
        ? (CFStringRef)[(NSAttributedString *)attributedString string]
        : NULL;
}

CFDictionaryRef CFAttributedStringGetAttributes(
        CFAttributedStringRef attributedString, CFIndex location,
        CFRange *effectiveRange) {
    if(!attributedString || location < 0) return NULL;
    return (CFDictionaryRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringGetAttributes,
        LC32_CF_HOST(attributedString), LC32_CF_U32(location),
        LC32_CF_U32((uintptr_t)effectiveRange));
}

CFTypeRef CFAttributedStringGetAttribute(
        CFAttributedStringRef attributedString, CFIndex location,
        CFStringRef attributeName, CFRange *effectiveRange) {
    if(!attributedString || !attributeName || location < 0) return NULL;
    return (CFTypeRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringGetAttribute,
        LC32_CF_HOST(attributedString), LC32_CF_U32(location),
        LC32_CF_HOST(attributeName),
        LC32_CF_U32((uintptr_t)effectiveRange));
}

CFDictionaryRef CFAttributedStringGetAttributesAndLongestEffectiveRange(
        CFAttributedStringRef attributedString, CFIndex location,
        CFRange rangeLimit, CFRange *longestEffectiveRange) {
    if(!attributedString || location < 0 ||
       !LC32CFAttributedStringValidRange(rangeLimit)) return NULL;
    return (CFDictionaryRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringGetAttributesLongest,
        LC32_CF_HOST(attributedString), LC32_CF_U32(location),
        LC32_CF_U32(rangeLimit.location), LC32_CF_U32(rangeLimit.length),
        LC32_CF_U32((uintptr_t)longestEffectiveRange));
}

CFTypeRef CFAttributedStringGetAttributeAndLongestEffectiveRange(
        CFAttributedStringRef attributedString, CFIndex location,
        CFStringRef attributeName, CFRange rangeLimit,
        CFRange *longestEffectiveRange) {
    if(!attributedString || !attributeName || location < 0 ||
       !LC32CFAttributedStringValidRange(rangeLimit)) return NULL;
    return (CFTypeRef)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringGetAttributeLongest,
        LC32_CF_HOST(attributedString), LC32_CF_U32(location),
        LC32_CF_HOST(attributeName), LC32_CF_U32(rangeLimit.location),
        LC32_CF_U32(rangeLimit.length),
        LC32_CF_U32((uintptr_t)longestEffectiveRange));
}

CFIndex CFAttributedStringGetLength(
        CFAttributedStringRef attributedString) {
    if(!attributedString) return 0;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpAttributedStringGetLength,
        LC32_CF_HOST(attributedString));
}

CFMutableStringRef CFAttributedStringGetMutableString(
        CFMutableAttributedStringRef attributedString) {
    return attributedString
        ? (CFMutableStringRef)
            [(NSMutableAttributedString *)attributedString mutableString]
        : NULL;
}

void CFAttributedStringReplaceString(
        CFMutableAttributedStringRef attributedString, CFRange range,
        CFStringRef replacement) {
    if(!attributedString || !replacement ||
       !LC32CFAttributedStringValidRange(range)) return;
    [(NSMutableAttributedString *)attributedString
        replaceCharactersInRange:LC32CFAttributedStringRange(range)
        withString:(NSString *)replacement];
}

void CFAttributedStringSetAttributes(
        CFMutableAttributedStringRef attributedString, CFRange range,
        CFDictionaryRef replacement, Boolean clearOtherAttributes) {
    if(!attributedString || !replacement ||
       !LC32CFAttributedStringValidRange(range)) return;
    NSMutableAttributedString *string =
        (NSMutableAttributedString *)attributedString;
    const NSRange nativeRange = LC32CFAttributedStringRange(range);
    if(clearOtherAttributes) {
        [string setAttributes:(NSDictionary *)replacement range:nativeRange];
    } else {
        [string addAttributes:(NSDictionary *)replacement range:nativeRange];
    }
}

void CFAttributedStringSetAttribute(
        CFMutableAttributedStringRef attributedString, CFRange range,
        CFStringRef attributeName, CFTypeRef value) {
    if(!attributedString || !attributeName || !value ||
       !LC32CFAttributedStringValidRange(range)) return;
    [(NSMutableAttributedString *)attributedString
        addAttribute:(NSString *)attributeName value:(id)value
        range:LC32CFAttributedStringRange(range)];
}

void CFAttributedStringRemoveAttribute(
        CFMutableAttributedStringRef attributedString, CFRange range,
        CFStringRef attributeName) {
    if(!attributedString || !attributeName ||
       !LC32CFAttributedStringValidRange(range)) return;
    [(NSMutableAttributedString *)attributedString
        removeAttribute:(NSString *)attributeName
        range:LC32CFAttributedStringRange(range)];
}

void CFAttributedStringBeginEditing(
        CFMutableAttributedStringRef attributedString) {
    if(attributedString)
        [(NSMutableAttributedString *)attributedString beginEditing];
}

void CFAttributedStringEndEditing(
        CFMutableAttributedStringRef attributedString) {
    if(attributedString)
        [(NSMutableAttributedString *)attributedString endEditing];
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
