#import <CoreFoundation/CoreFoundation+LC32.h>

#include <limits.h>
#include <stdarg.h>

CFStringRef CFStringCreateCopy(CFAllocatorRef allocator,
                               CFStringRef string) {
    (void)allocator;
    return string ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateCopy, LC32_CF_HOST(string)) : NULL;
}

CFMutableStringRef CFStringCreateMutable(CFAllocatorRef allocator,
                                         CFIndex maximumLength) {
    (void)allocator;
    if(maximumLength < 0) return NULL;
    return (CFMutableStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateMutable,
        LC32_CF_U32(maximumLength));
}

CFMutableStringRef CFStringCreateMutableCopy(CFAllocatorRef allocator,
                                             CFIndex maximumLength,
                                             CFStringRef string) {
    (void)allocator;
    if(maximumLength < 0 || !string) return NULL;
    return (CFMutableStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateMutableCopy,
        LC32_CF_U32(maximumLength), LC32_CF_HOST(string));
}

CFStringRef CFStringCreateWithCString(CFAllocatorRef allocator,
                                      const char *cString,
                                      CFStringEncoding encoding) {
    (void)allocator;
    if(!cString) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateWithCString,
        LC32_CF_U32((uintptr_t)cString), LC32_CF_U32(encoding));
}

CFStringRef CFStringCreateWithSubstring(CFAllocatorRef allocator,
                                        CFStringRef string,
                                        CFRange range) {
    (void)allocator;
    if(!string || range.location < 0 || range.length < 0) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateWithSubstring,
        LC32_CF_HOST(string), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length));
}

CFArrayRef CFStringCreateArrayBySeparatingStrings(
        CFAllocatorRef allocator, CFStringRef string,
        CFStringRef separatorString) {
    (void)allocator;
    if(!string || !separatorString) return NULL;
    return (CFArrayRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateArrayBySeparatingStrings,
        LC32_CF_HOST(string), LC32_CF_HOST(separatorString));
}

CFStringRef CFStringCreateWithFormatAndArguments(
        CFAllocatorRef allocator, CFDictionaryRef formatOptions,
        CFStringRef format, va_list arguments) {
    (void)allocator;
    (void)formatOptions;
    if(!format) return NULL;
    return (CFStringRef)[[NSString alloc]
        initWithFormat:(NSString *)format arguments:arguments];
}

CFStringRef CFStringCreateWithFormat(CFAllocatorRef allocator,
                                     CFDictionaryRef formatOptions,
                                     CFStringRef format, ...) {
    va_list arguments;
    va_start(arguments, format);
    CFStringRef result = CFStringCreateWithFormatAndArguments(
        allocator, formatOptions, format, arguments);
    va_end(arguments);
    return result;
}

void CFStringAppend(CFMutableStringRef string, CFStringRef appendedString) {
    [(NSMutableString *)string appendString:(NSString *)appendedString];
}

void CFStringAppendFormatAndArguments(CFMutableStringRef string,
                                      CFDictionaryRef formatOptions,
                                      CFStringRef format,
                                      va_list arguments) {
    (void)formatOptions;
    if(!string || !format) return;
    NSString *formatted = [[NSString alloc]
        initWithFormat:(NSString *)format arguments:arguments];
    [(NSMutableString *)string appendString:formatted];
    [formatted release];
}

void CFStringAppendFormat(CFMutableStringRef string,
                          CFDictionaryRef formatOptions,
                          CFStringRef format, ...) {
    va_list arguments;
    va_start(arguments, format);
    CFStringAppendFormatAndArguments(
        string, formatOptions, format, arguments);
    va_end(arguments);
}

CFComparisonResult CFStringCompare(CFStringRef string1,
                                   CFStringRef string2,
                                   CFStringCompareFlags compareOptions) {
    return (CFComparisonResult)[(NSString *)string1
        compare:(NSString *)string2 options:(NSStringCompareOptions)compareOptions];
}

Boolean CFStringHasPrefix(CFStringRef string, CFStringRef prefix) {
    return [(NSString *)string hasPrefix:(NSString *)prefix];
}

Boolean CFStringHasSuffix(CFStringRef string, CFStringRef suffix) {
    return [(NSString *)string hasSuffix:(NSString *)suffix];
}

CFIndex CFStringGetLength(CFStringRef string) {
    return (CFIndex)[(NSString *)string length];
}

Boolean CFStringGetCString(CFStringRef string, char *buffer,
                           CFIndex bufferSize,
                           CFStringEncoding encoding) {
    if(!string || !buffer || bufferSize <= 0) return false;
    return LC32_CF_CALL(LC32CoreFoundationOpStringGetCString,
        LC32_CF_HOST(string), LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(bufferSize), LC32_CF_U32(encoding)) != 0;
}

const char *CFStringGetCStringPtr(CFStringRef string,
                                  CFStringEncoding encoding) {
    if(!string) return NULL;
    const CFIndex length = CFStringGetLength(string);
    const CFIndex maximum =
        CFStringGetMaximumSizeForEncoding(length, encoding);
    if(maximum < 0 || maximum >= INT32_MAX) return NULL;
    const uint32_t capacity = (uint32_t)maximum + 1;
    char *buffer = LC32GetAssociatedGuestBuffer((id)string, capacity);
    return buffer && CFStringGetCString(string, buffer, capacity, encoding)
        ? buffer : NULL;
}

CFIndex CFStringGetMaximumSizeForEncoding(CFIndex length,
                                          CFStringEncoding encoding) {
    if(length < 0) return -1;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetMaximumSizeForEncoding,
        LC32_CF_U32(length), LC32_CF_U32(encoding));
}
