#import <CoreFoundation/CoreFoundation+LC32.h>

#include <limits.h>
#include <stdint.h>
#include <stdarg.h>

static Boolean LC32CFStringValidLength(CFIndex length) {
    return length >= 0 && (uint64_t)length <= INT32_MAX;
}

static Boolean LC32CFStringValidRange(CFRange range) {
    return LC32CFStringValidLength(range.location) &&
           LC32CFStringValidLength(range.length) &&
           (uint64_t)range.location + (uint64_t)range.length <= INT32_MAX;
}

static Boolean LC32CFStringRangeFitsString(CFStringRef string,
                                            CFRange range) {
    if(!string || !LC32CFStringValidRange(range)) return false;
    const CFIndex stringLength = CFStringGetLength(string);
    return range.location <= stringLength &&
           range.length <= stringLength - range.location;
}

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

CFStringRef CFStringCreateWithCStringNoCopy(
        CFAllocatorRef allocator, const char *cString,
        CFStringEncoding encoding, CFAllocatorRef contentsDeallocator) {
    /* Guest storage cannot be retained or freed by the arm64 peer. */
    (void)contentsDeallocator;
    return CFStringCreateWithCString(allocator, cString, encoding);
}

CFStringRef CFStringCreateWithFileSystemRepresentation(
        CFAllocatorRef allocator, const char *buffer) {
    return CFStringCreateWithCString(
        allocator, buffer, kCFStringEncodingUTF8);
}

CFStringRef CFStringCreateWithBytes(CFAllocatorRef allocator,
                                    const UInt8 *bytes, CFIndex numBytes,
                                    CFStringEncoding encoding,
                                    Boolean isExternalRepresentation) {
    (void)allocator;
    if(!LC32CFStringValidLength(numBytes) || (numBytes && !bytes))
        return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateWithBytes,
        LC32_CF_U32((uintptr_t)bytes), LC32_CF_U32(numBytes),
        LC32_CF_U32(encoding), LC32_CF_U32(isExternalRepresentation));
}

CFStringRef CFStringCreateWithBytesNoCopy(
        CFAllocatorRef allocator, const UInt8 *bytes, CFIndex numBytes,
        CFStringEncoding encoding, Boolean isExternalRepresentation,
        CFAllocatorRef contentsDeallocator) {
    /*
     * Native CoreFoundation cannot retain or deallocate an ARM32 address.
     * Copying is allowed by the CF contract even for the no-copy spelling,
     * and keeps guest pointers out of host object storage.  As with the
     * CFData shim, the guest-side deallocator is intentionally not invoked.
     */
    (void)contentsDeallocator;
    return CFStringCreateWithBytes(allocator, bytes, numBytes, encoding,
                                   isExternalRepresentation);
}

CFStringRef CFStringCreateWithPascalString(
        CFAllocatorRef allocator, ConstStr255Param pascalString,
        CFStringEncoding encoding) {
    if(!pascalString) return NULL;
    return CFStringCreateWithBytes(allocator, pascalString + 1,
        pascalString[0], encoding, false);
}

CFStringRef CFStringCreateWithPascalStringNoCopy(
        CFAllocatorRef allocator, ConstStr255Param pascalString,
        CFStringEncoding encoding, CFAllocatorRef contentsDeallocator) {
    /* Guest memory cannot be retained or deallocated by native CF. */
    (void)contentsDeallocator;
    return CFStringCreateWithPascalString(
        allocator, pascalString, encoding);
}

CFStringRef CFStringCreateWithCharacters(CFAllocatorRef allocator,
                                         const UniChar *characters,
                                         CFIndex numCharacters) {
    (void)allocator;
    if(!LC32CFStringValidLength(numCharacters) ||
       (numCharacters && !characters)) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateWithCharacters,
        LC32_CF_U32((uintptr_t)characters), LC32_CF_U32(numCharacters));
}

CFStringRef CFStringCreateWithCharactersNoCopy(
        CFAllocatorRef allocator, const UniChar *characters,
        CFIndex numCharacters, CFAllocatorRef contentsDeallocator) {
    (void)contentsDeallocator;
    return CFStringCreateWithCharacters(allocator, characters,
                                        numCharacters);
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

CFStringRef CFStringCreateByCombiningStrings(
        CFAllocatorRef allocator, CFArrayRef array,
        CFStringRef separatorString) {
    (void)allocator;
    if(!array || !separatorString) return NULL;
    return (CFStringRef)[[(NSArray *)array
        componentsJoinedByString:(NSString *)separatorString] copy];
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

void CFStringDelete(CFMutableStringRef string, CFRange range) {
    if(!string || !LC32CFStringValidRange(range)) return;
    [(NSMutableString *)string deleteCharactersInRange:
        NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length)];
}

void CFStringInsert(CFMutableStringRef string, CFIndex index,
                    CFStringRef insertedString) {
    if(!string || !insertedString || index < 0) return;
    [(NSMutableString *)string insertString:(NSString *)insertedString
                                    atIndex:(NSUInteger)index];
}

void CFStringReplace(CFMutableStringRef string, CFRange range,
                     CFStringRef replacement) {
    if(!string || !replacement || !LC32CFStringValidRange(range)) return;
    [(NSMutableString *)string
        replaceCharactersInRange:NSMakeRange(
            (NSUInteger)range.location, (NSUInteger)range.length)
        withString:(NSString *)replacement];
}

void CFStringReplaceAll(CFMutableStringRef string,
                        CFStringRef replacement) {
    if(string && replacement)
        [(NSMutableString *)string setString:(NSString *)replacement];
}

void CFStringAppendCString(CFMutableStringRef string, const char *cString,
                           CFStringEncoding encoding) {
    if(!string || !cString) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringAppendCString,
        LC32_CF_HOST(string), LC32_CF_U32((uintptr_t)cString),
        LC32_CF_U32(encoding));
}

void CFStringAppendPascalString(CFMutableStringRef string,
                                ConstStr255Param pascalString,
                                CFStringEncoding encoding) {
    if(!string || !pascalString) return;
    CFStringRef appendedString = CFStringCreateWithPascalString(
        kCFAllocatorDefault, pascalString, encoding);
    if(!appendedString) return;
    CFStringAppend(string, appendedString);
    CFRelease(appendedString);
}

void CFStringAppendCharacters(CFMutableStringRef string,
                              const UniChar *characters,
                              CFIndex numCharacters) {
    if(!string || !LC32CFStringValidLength(numCharacters) ||
       (numCharacters && !characters)) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringAppendCharacters,
        LC32_CF_HOST(string), LC32_CF_U32((uintptr_t)characters),
        LC32_CF_U32(numCharacters));
}

void CFStringLowercase(CFMutableStringRef string, CFLocaleRef locale) {
    if(!string) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringLowercase,
        LC32_CF_HOST(string), LC32_CF_HOST(locale));
}

void CFStringFold(CFMutableStringRef string,
                  CFStringCompareFlags flags,
                  CFLocaleRef locale) {
    if(!string) return;
    const CFStringCompareFlags foldingFlags = flags &
        (kCFCompareCaseInsensitive | kCFCompareDiacriticInsensitive |
         kCFCompareWidthInsensitive);
    NSString *folded = [(NSString *)string
        stringByFoldingWithOptions:(NSStringCompareOptions)foldingFlags
                            locale:(NSLocale *)locale];
    if(folded) [(NSMutableString *)string setString:folded];
}

void CFStringNormalize(CFMutableStringRef string,
                       CFStringNormalizationForm form) {
    if(!string) return;

    NSString *normalized = nil;
    switch(form) {
        case kCFStringNormalizationFormD:
            normalized = [(NSString *)string
                decomposedStringWithCanonicalMapping];
            break;
        case kCFStringNormalizationFormKD:
            normalized = [(NSString *)string
                decomposedStringWithCompatibilityMapping];
            break;
        case kCFStringNormalizationFormC:
            normalized = [(NSString *)string
                precomposedStringWithCanonicalMapping];
            break;
        case kCFStringNormalizationFormKC:
            normalized = [(NSString *)string
                precomposedStringWithCompatibilityMapping];
            break;
        default:
            return;
    }
    if(normalized) [(NSMutableString *)string setString:normalized];
}

Boolean CFStringTransform(CFMutableStringRef string, CFRange *range,
                          CFStringRef transform, Boolean reverse) {
    if(!string || !transform) return false;

    const CFRange inputRange = range
        ? *range : CFRangeMake(0, CFStringGetLength(string));
    if(!LC32CFStringRangeFitsString(string, inputRange)) return false;

    NSString *input = [(NSString *)string substringWithRange:NSMakeRange(
        (NSUInteger)inputRange.location, (NSUInteger)inputRange.length)];
    NSString *transformed = [input
        stringByApplyingTransform:(NSStringTransform)transform
                          reverse:reverse];
    if(!transformed || [transformed length] > INT32_MAX) return false;

    [(NSMutableString *)string replaceCharactersInRange:NSMakeRange(
        (NSUInteger)inputRange.location, (NSUInteger)inputRange.length)
                                               withString:transformed];
    if(range) {
        range->location = inputRange.location;
        range->length = (CFIndex)[transformed length];
    }
    return true;
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

CFComparisonResult CFStringCompareWithOptions(
        CFStringRef string1, CFStringRef string2, CFRange rangeToCompare,
        CFStringCompareFlags compareOptions) {
    if(!string1 || !string2 || !LC32CFStringValidRange(rangeToCompare))
        return kCFCompareEqualTo;
    return (CFComparisonResult)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringCompareWithOptions,
        LC32_CF_HOST(string1), LC32_CF_HOST(string2),
        LC32_CF_U32(rangeToCompare.location),
        LC32_CF_U32(rangeToCompare.length), LC32_CF_U32(compareOptions));
}

CFComparisonResult CFStringCompareWithOptionsAndLocale(
        CFStringRef string1, CFStringRef string2, CFRange rangeToCompare,
        CFStringCompareFlags compareOptions, CFLocaleRef locale) {
    if(!string1 || !string2 ||
       !LC32CFStringRangeFitsString(string1, rangeToCompare)) {
        return kCFCompareEqualTo;
    }
    return (CFComparisonResult)[(NSString *)string1
        compare:(NSString *)string2
        options:(NSStringCompareOptions)compareOptions
          range:NSMakeRange((NSUInteger)rangeToCompare.location,
                            (NSUInteger)rangeToCompare.length)
         locale:(NSLocale *)locale];
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

CFStringEncoding CFStringGetFastestEncoding(CFStringRef string) {
    if(!string) return kCFStringEncodingInvalidId;
    return CFStringConvertNSStringEncodingToEncoding(
        [(NSString *)string fastestEncoding]);
}

CFStringEncoding CFStringGetSmallestEncoding(CFStringRef string) {
    return string ? (CFStringEncoding)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetSmallestEncoding,
        LC32_CF_HOST(string)) : kCFStringEncodingInvalidId;
}

UniChar CFStringGetCharacterAtIndex(CFStringRef string, CFIndex index) {
    if(!string || index < 0 || index >= CFStringGetLength(string)) return 0;
    return (UniChar)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetCharacterAtIndex,
        LC32_CF_HOST(string), LC32_CF_U32(index));
}

void CFStringGetCharacters(CFStringRef string, CFRange range,
                           UniChar *buffer) {
    if(!string || !LC32CFStringValidRange(range) ||
       (range.length && !buffer)) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringGetCharacters,
        LC32_CF_HOST(string), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32((uintptr_t)buffer));
}

const UniChar *CFStringGetCharactersPtr(CFStringRef string) {
    if(!string) return NULL;
    const CFIndex length = CFStringGetLength(string);
    if(length <= 0 || length > INT32_MAX / (CFIndex)sizeof(UniChar))
        return NULL;
    UniChar *buffer = LC32GetAssociatedGuestBuffer(
        (id)string, (uint32_t)length * sizeof(UniChar));
    if(!buffer) return NULL;
    CFStringGetCharacters(string, CFRangeMake(0, length), buffer);
    return buffer;
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

CFIndex CFStringGetMaximumSizeOfFileSystemRepresentation(
        CFStringRef string) {
    return string ? (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetMaximumSizeOfFileSystemRepresentation,
        LC32_CF_HOST(string)) : 0;
}

Boolean CFStringGetFileSystemRepresentation(
        CFStringRef string, char *buffer, CFIndex maxBufferLength) {
    if(!string || !buffer || maxBufferLength <= 0) return false;
    return LC32_CF_CALL(
        LC32CoreFoundationOpStringGetFileSystemRepresentation,
        LC32_CF_HOST(string), LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(maxBufferLength));
}

CFIndex CFStringGetBytes(CFStringRef string, CFRange range,
                         CFStringEncoding encoding, UInt8 lossByte,
                         Boolean isExternalRepresentation, UInt8 *buffer,
                         CFIndex maxBufferLength,
                         CFIndex *usedBufferLength) {
    if(!string || !LC32CFStringValidRange(range) ||
       !LC32CFStringValidLength(maxBufferLength)) {
        if(usedBufferLength) *usedBufferLength = 0;
        return 0;
    }
    const uint32_t options = (uint32_t)lossByte |
        ((isExternalRepresentation != false) << 8);
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetBytes,
        LC32_CF_HOST(string), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32(encoding),
        LC32_CF_U32(options), LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(maxBufferLength),
        LC32_CF_U32((uintptr_t)usedBufferLength));
}

Boolean CFStringGetPascalString(CFStringRef string, StringPtr buffer,
                                CFIndex bufferSize,
                                CFStringEncoding encoding) {
    if(!string || !buffer || bufferSize <= 0) return false;

    const CFRange range = CFRangeMake(0, CFStringGetLength(string));
    CFIndex byteCount = 0;
    const CFIndex converted = CFStringGetBytes(string, range, encoding, 0,
        false, NULL, 0, &byteCount);
    if(converted != range.length || byteCount < 0 || byteCount > 255 ||
       byteCount >= bufferSize) {
        return false;
    }

    CFIndex written = 0;
    if(CFStringGetBytes(string, range, encoding, 0, false, buffer + 1,
            byteCount, &written) != range.length || written != byteCount) {
        return false;
    }
    buffer[0] = (UInt8)written;
    return true;
}

CFStringRef CFStringCreateFromExternalRepresentation(
        CFAllocatorRef allocator, CFDataRef data,
        CFStringEncoding encoding) {
    (void)allocator;
    if(!data) return NULL;
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateFromExternalRepresentation,
        LC32_CF_HOST(data), LC32_CF_U32(encoding));
}

CFDataRef CFStringCreateExternalRepresentation(
        CFAllocatorRef allocator, CFStringRef string,
        CFStringEncoding encoding, UInt8 lossByte) {
    (void)allocator;
    if(!string) return NULL;
    return (CFDataRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringCreateExternalRepresentation,
        LC32_CF_HOST(string), LC32_CF_U32(encoding),
        LC32_CF_U32(lossByte));
}

Boolean CFStringFindWithOptions(
        CFStringRef string, CFStringRef stringToFind, CFRange rangeToSearch,
        CFStringCompareFlags searchOptions, CFRange *result) {
    if(!string || !stringToFind || !LC32CFStringValidRange(rangeToSearch))
        return false;
    return LC32_CF_CALL(LC32CoreFoundationOpStringFindWithOptions,
        LC32_CF_HOST(string), LC32_CF_HOST(stringToFind),
        LC32_CF_U32(rangeToSearch.location),
        LC32_CF_U32(rangeToSearch.length), LC32_CF_U32(searchOptions),
        LC32_CF_U32((uintptr_t)result)) != 0;
}

Boolean CFStringFindWithOptionsAndLocale(
        CFStringRef string, CFStringRef stringToFind,
        CFRange rangeToSearch, CFStringCompareFlags searchOptions,
        CFLocaleRef locale, CFRange *result) {
    if(result) *result = CFRangeMake(kCFNotFound, 0);
    if(!string || !stringToFind || !CFStringGetLength(stringToFind) ||
       !LC32CFStringRangeFitsString(string, rangeToSearch)) {
        return false;
    }

    const NSRange found = [(NSString *)string
        rangeOfString:(NSString *)stringToFind
              options:(NSStringCompareOptions)searchOptions
                range:NSMakeRange((NSUInteger)rangeToSearch.location,
                                  (NSUInteger)rangeToSearch.length)
               locale:(NSLocale *)locale];
    if(found.location == NSNotFound) return false;
    if(result) {
        result->location = (CFIndex)found.location;
        result->length = (CFIndex)found.length;
    }
    return true;
}

CFRange CFStringFind(CFStringRef string, CFStringRef stringToFind,
                     CFStringCompareFlags compareOptions) {
    CFRange result = CFRangeMake(kCFNotFound, 0);
    if(!string) return result;
    CFStringFindWithOptions(string, stringToFind,
        CFRangeMake(0, CFStringGetLength(string)), compareOptions, &result);
    return result;
}

Boolean CFStringFindCharacterFromSet(
        CFStringRef string, CFCharacterSetRef characterSet,
        CFRange rangeToSearch, CFStringCompareFlags searchOptions,
        CFRange *result) {
    if(!string || !characterSet || !LC32CFStringValidRange(rangeToSearch))
        return false;
    return LC32_CF_CALL(LC32CoreFoundationOpStringFindCharacterFromSet,
        LC32_CF_HOST(string), LC32_CF_HOST(characterSet),
        LC32_CF_U32(rangeToSearch.location),
        LC32_CF_U32(rangeToSearch.length), LC32_CF_U32(searchOptions),
        LC32_CF_U32((uintptr_t)result)) != 0;
}

CFIndex CFStringFindAndReplace(
        CFMutableStringRef string, CFStringRef stringToFind,
        CFStringRef replacementString, CFRange rangeToSearch,
        CFStringCompareFlags compareOptions) {
    if(!string || !stringToFind || !replacementString ||
       !LC32CFStringValidRange(rangeToSearch)) return 0;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringFindAndReplace,
        LC32_CF_HOST(string), LC32_CF_HOST(stringToFind),
        LC32_CF_HOST(replacementString),
        LC32_CF_U32(rangeToSearch.location),
        LC32_CF_U32(rangeToSearch.length), LC32_CF_U32(compareOptions));
}

SInt32 CFStringGetIntValue(CFStringRef string) {
    return string ? (SInt32)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetIntValue,
        LC32_CF_HOST(string)) : 0;
}

double CFStringGetDoubleValue(CFStringRef string) {
    return string ? [(NSString *)string doubleValue] : 0.0;
}

CFRange CFStringGetRangeOfComposedCharactersAtIndex(
        CFStringRef string, CFIndex index) {
    if(!string || index < 0 || index >= CFStringGetLength(string))
        return CFRangeMake(kCFNotFound, 0);
    const NSRange range = [(NSString *)string
        rangeOfComposedCharacterSequenceAtIndex:(NSUInteger)index];
    return CFRangeMake((CFIndex)range.location, (CFIndex)range.length);
}

void CFStringGetLineBounds(CFStringRef string, CFRange range,
                           CFIndex *lineBeginIndex,
                           CFIndex *lineEndIndex,
                           CFIndex *contentsEndIndex) {
    if(!LC32CFStringRangeFitsString(string, range)) return;

    NSUInteger begin = 0;
    NSUInteger end = 0;
    NSUInteger contentsEnd = 0;
    [(NSString *)string getLineStart:&begin end:&end
                         contentsEnd:&contentsEnd
                            forRange:NSMakeRange(
                                (NSUInteger)range.location,
                                (NSUInteger)range.length)];
    if(lineBeginIndex) *lineBeginIndex = (CFIndex)begin;
    if(lineEndIndex) *lineEndIndex = (CFIndex)end;
    if(contentsEndIndex) *contentsEndIndex = (CFIndex)contentsEnd;
}

void CFStringGetParagraphBounds(CFStringRef string, CFRange range,
                                CFIndex *paragraphBeginIndex,
                                CFIndex *paragraphEndIndex,
                                CFIndex *contentsEndIndex) {
    if(!LC32CFStringRangeFitsString(string, range)) return;

    NSUInteger begin = 0;
    NSUInteger end = 0;
    NSUInteger contentsEnd = 0;
    [(NSString *)string getParagraphStart:&begin end:&end
                              contentsEnd:&contentsEnd
                                 forRange:NSMakeRange(
                                     (NSUInteger)range.location,
                                     (NSUInteger)range.length)];
    if(paragraphBeginIndex) *paragraphBeginIndex = (CFIndex)begin;
    if(paragraphEndIndex) *paragraphEndIndex = (CFIndex)end;
    if(contentsEndIndex) *contentsEndIndex = (CFIndex)contentsEnd;
}

void CFStringCapitalize(CFMutableStringRef string, CFLocaleRef locale) {
    if(!string) return;
    NSString *capitalized = locale
        ? [(NSString *)string capitalizedStringWithLocale:(NSLocale *)locale]
        : [(NSString *)string capitalizedString];
    [(NSMutableString *)string setString:capitalized];
}

void CFStringUppercase(CFMutableStringRef string, CFLocaleRef locale) {
    if(!string) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringUppercase,
        LC32_CF_HOST(string), LC32_CF_HOST(locale));
}

void CFStringTrimWhitespace(CFMutableStringRef string) {
    if(!string) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringTrimWhitespace,
        LC32_CF_HOST(string));
}

void CFStringPad(CFMutableStringRef string, CFStringRef padding,
                 CFIndex length, CFIndex indexIntoPadding) {
    if(!string || !padding || length < 0 || indexIntoPadding < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringPad,
        LC32_CF_HOST(string), LC32_CF_HOST(padding),
        LC32_CF_U32(length), LC32_CF_U32(indexIntoPadding));
}

void CFStringTrim(CFMutableStringRef string, CFStringRef trimString) {
    if(!string || !trimString) return;
    LC32_CF_CALL(LC32CoreFoundationOpStringTrim,
        LC32_CF_HOST(string), LC32_CF_HOST(trimString));
}

CFStringEncoding CFStringGetMostCompatibleMacStringEncoding(
        CFStringEncoding encoding) {
    return (CFStringEncoding)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetMostCompatibleMacStringEncoding,
        LC32_CF_U32(encoding));
}

Boolean CFStringIsHyphenationAvailableForLocale(CFLocaleRef locale) {
    return locale && LC32_CF_CALL(
        LC32CoreFoundationOpStringIsHyphenationAvailableForLocale,
        LC32_CF_HOST(locale));
}

CFIndex CFStringGetHyphenationLocationBeforeIndex(
        CFStringRef string, CFIndex location, CFRange limitRange,
        CFOptionFlags options, CFLocaleRef locale, UTF32Char *character) {
    if(!string || !locale || location < 0 || limitRange.location < 0 ||
       limitRange.length < 0) return kCFNotFound;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetHyphenationLocationBeforeIndex,
        LC32_CF_HOST(string), LC32_CF_U32(location),
        LC32_CF_U32(limitRange.location), LC32_CF_U32(limitRange.length),
        LC32_CF_U32(options), LC32_CF_HOST(locale),
        LC32_CF_U32((uintptr_t)character));
}

unsigned long CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding encoding) {
    return (unsigned long)LC32_CF_CALL(
        LC32CoreFoundationOpStringConvertEncodingToNSStringEncoding,
        LC32_CF_U32(encoding));
}

CFStringEncoding CFStringConvertNSStringEncodingToEncoding(
        unsigned long encoding) {
    return (CFStringEncoding)LC32_CF_CALL(
        LC32CoreFoundationOpStringConvertNSStringEncodingToEncoding,
        LC32_CF_U32(encoding));
}

CFStringEncoding CFStringGetSystemEncoding(void) {
    return (CFStringEncoding)LC32_CF_CALL0(
        LC32CoreFoundationOpStringGetSystemEncoding);
}

Boolean CFStringIsEncodingAvailable(CFStringEncoding encoding) {
    return LC32_CF_CALL(
        LC32CoreFoundationOpStringIsEncodingAvailable,
        LC32_CF_U32(encoding)) != 0;
}

CFStringRef CFStringGetNameOfEncoding(CFStringEncoding encoding) {
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringGetNameOfEncoding,
        LC32_CF_U32(encoding));
}

UInt32 CFStringConvertEncodingToWindowsCodepage(
        CFStringEncoding encoding) {
    return (UInt32)LC32_CF_CALL(
        LC32CoreFoundationOpStringConvertEncodingToWindowsCodepage,
        LC32_CF_U32(encoding));
}

CFStringEncoding CFStringConvertWindowsCodepageToEncoding(
        UInt32 codepage) {
    return (CFStringEncoding)LC32_CF_CALL(
        LC32CoreFoundationOpStringConvertWindowsCodepageToEncoding,
        LC32_CF_U32(codepage));
}

CFStringEncoding CFStringConvertIANACharSetNameToEncoding(
        CFStringRef string) {
    return string ? (CFStringEncoding)LC32_CF_CALL(
        LC32CoreFoundationOpStringConvertIANACharSetNameToEncoding,
        LC32_CF_HOST(string)) : kCFStringEncodingInvalidId;
}

CFStringRef CFStringConvertEncodingToIANACharSetName(
        CFStringEncoding encoding) {
    return (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringConvertEncodingToIANACharSetName,
        LC32_CF_U32(encoding));
}
