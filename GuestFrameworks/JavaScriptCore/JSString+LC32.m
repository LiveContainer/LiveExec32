#import <JavaScriptCore/JavaScriptCore.h>

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct OpaqueJSString {
    uint32_t referenceCount;
    size_t length;
    JSChar characters[];
};

static struct OpaqueJSString *LC32MutableJSString(JSStringRef string) {
    return (struct OpaqueJSString *)(uintptr_t)string;
}

static struct OpaqueJSString *LC32JSStringAllocate(size_t numChars) {
    if(numChars > (SIZE_MAX - sizeof(struct OpaqueJSString)) /
                      sizeof(JSChar)) {
        return NULL;
    }

    const size_t allocationSize = sizeof(struct OpaqueJSString) +
        numChars * sizeof(JSChar);
    struct OpaqueJSString *string = malloc(allocationSize);
    if(!string) return NULL;
    string->referenceCount = 1;
    string->length = numChars;
    return string;
}

JSStringRef JSStringCreateWithCharacters(const JSChar *characters,
                                         size_t numChars) {
    if(numChars && !characters) return NULL;
    struct OpaqueJSString *string = LC32JSStringAllocate(numChars);
    if(!string) return NULL;
    if(numChars) memcpy(string->characters, characters,
        numChars * sizeof(JSChar));
    return string;
}

JSStringRef JSStringCreateWithCFString(CFStringRef string) {
    if(!string) return NULL;
    const CFIndex length = CFStringGetLength(string);
    if(length < 0) return NULL;

    struct OpaqueJSString *result = LC32JSStringAllocate((size_t)length);
    if(!result) return NULL;
    if(length) CFStringGetCharacters(string, CFRangeMake(0, length),
        result->characters);
    return result;
}

JSStringRef JSStringCreateWithUTF8CString(const char *string) {
    if(!string) return NULL;
    CFStringRef converted = CFStringCreateWithCString(kCFAllocatorDefault,
        string, kCFStringEncodingUTF8);
    if(!converted) return NULL;
    JSStringRef result = JSStringCreateWithCFString(converted);
    CFRelease(converted);
    return result;
}

JSStringRef JSStringRetain(JSStringRef string) {
    if(string) __sync_add_and_fetch(
        &LC32MutableJSString(string)->referenceCount, 1);
    return string;
}

void JSStringRelease(JSStringRef string) {
    if(!string) return;
    struct OpaqueJSString *mutableString = LC32MutableJSString(string);
    if(__sync_sub_and_fetch(&mutableString->referenceCount, 1) == 0)
        free(mutableString);
}

size_t JSStringGetLength(JSStringRef string) {
    return string ? LC32MutableJSString(string)->length : 0;
}

const JSChar *JSStringGetCharactersPtr(JSStringRef string) {
    return string ? LC32MutableJSString(string)->characters : NULL;
}

size_t JSStringGetMaximumUTF8CStringSize(JSStringRef string) {
    const size_t length = JSStringGetLength(string);
    return length > (SIZE_MAX - 1) / 3 ? SIZE_MAX : length * 3 + 1;
}

CFStringRef JSStringCopyCFString(CFAllocatorRef allocator,
                                 JSStringRef string) {
    if(!string) return NULL;
    const size_t length = JSStringGetLength(string);
    if(length > (size_t)INT32_MAX) return NULL;
    return CFStringCreateWithCharacters(allocator,
        JSStringGetCharactersPtr(string), (CFIndex)length);
}

size_t JSStringGetUTF8CString(JSStringRef string, char *buffer,
                              size_t bufferSize) {
    if(!string || !buffer || !bufferSize || bufferSize > INT32_MAX)
        return 0;
    CFStringRef converted = JSStringCopyCFString(kCFAllocatorDefault, string);
    if(!converted) return 0;

    /* JavaScriptCore truncates at a complete UTF-8 character when the
     * caller supplies a short buffer, and still returns the trailing NUL. */
    CFIndex usedBytes = 0;
    CFStringGetBytes(converted,
        CFRangeMake(0, CFStringGetLength(converted)),
        kCFStringEncodingUTF8, '?', false, (UInt8 *)buffer,
        (CFIndex)bufferSize - 1, &usedBytes);
    CFRelease(converted);
    buffer[usedBytes] = '\0';
    return (size_t)usedBytes + 1;
}

bool JSStringIsEqual(JSStringRef left, JSStringRef right) {
    if(left == right) return true;
    if(!left || !right) return false;
    const size_t length = JSStringGetLength(left);
    return length == JSStringGetLength(right) &&
        (!length || memcmp(JSStringGetCharactersPtr(left),
            JSStringGetCharactersPtr(right), length * sizeof(JSChar)) == 0);
}

bool JSStringIsEqualToUTF8CString(JSStringRef left,
                                  const char *right) {
    if(!left || !right) return false;
    JSStringRef converted = JSStringCreateWithUTF8CString(right);
    const bool equal = converted && JSStringIsEqual(left, converted);
    JSStringRelease(converted);
    return equal;
}
