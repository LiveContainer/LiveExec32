#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>
#include <string.h>

extern UInt8 *LC32GetMutableDataGuestBytes(NSMutableData *data);
extern BOOL LC32ReserveMutableDataGuestCapacity(NSMutableData *data,
                                                uint32_t capacity);
extern void LC32InvalidateDataGuestBuffer(NSData *data);

enum {
    LC32MaximumDataBytes = 256u * 1024u * 1024u,
};

static Boolean LC32CFDataValidLength(CFIndex length) {
    return length >= 0 && (uint64_t)length <= LC32MaximumDataBytes;
}

static Boolean LC32CFDataValidRange(CFRange range) {
    return LC32CFDataValidLength(range.location) &&
           LC32CFDataValidLength(range.length) &&
           (uint64_t)range.location + (uint64_t)range.length <= UINT32_MAX;
}

CFDataRef CFDataCreate(CFAllocatorRef allocator, const UInt8 *bytes,
                       CFIndex length) {
    (void)allocator;
    if(!LC32CFDataValidLength(length) || (length && !bytes)) return NULL;
    return (CFDataRef)LC32_CF_CALL(LC32CoreFoundationOpDataCreate,
        LC32_CF_U32((uintptr_t)bytes), LC32_CF_U32(length));
}

CFDataRef CFDataCreateWithBytesNoCopy(CFAllocatorRef allocator,
                                      const UInt8 *bytes, CFIndex length,
                                      CFAllocatorRef bytesDeallocator) {
    /*
     * A host CFData cannot own an ARM address.  Copying here preserves the
     * bytes and, importantly, never lets a native deallocator free guest
     * memory.  The only observable difference is the documented no-copy
     * optimization.
     */
    (void)bytesDeallocator;
    return CFDataCreate(allocator, bytes, length);
}

CFDataRef CFDataCreateCopy(CFAllocatorRef allocator, CFDataRef data) {
    (void)allocator;
    return data ? (CFDataRef)LC32_CF_CALL(
        LC32CoreFoundationOpDataCreateCopy, LC32_CF_HOST(data)) : NULL;
}

CFMutableDataRef CFDataCreateMutable(CFAllocatorRef allocator,
                                     CFIndex capacity) {
    (void)allocator;
    if(!LC32CFDataValidLength(capacity)) return NULL;
    CFMutableDataRef data = (CFMutableDataRef)LC32_CF_CALL(
        LC32CoreFoundationOpDataCreateMutable, LC32_CF_U32(capacity));
    if(data && !LC32ReserveMutableDataGuestCapacity(
            (NSMutableData *)data, (uint32_t)capacity)) {
        CFRelease(data);
        return NULL;
    }
    return data;
}

CFMutableDataRef CFDataCreateMutableCopy(CFAllocatorRef allocator,
                                         CFIndex capacity,
                                         CFDataRef data) {
    (void)allocator;
    if(!data || !LC32CFDataValidLength(capacity)) return NULL;
    CFMutableDataRef copy = (CFMutableDataRef)LC32_CF_CALL(
        LC32CoreFoundationOpDataCreateMutableCopy,
        LC32_CF_U32(capacity), LC32_CF_HOST(data));
    if(copy && !LC32ReserveMutableDataGuestCapacity(
            (NSMutableData *)copy, (uint32_t)capacity)) {
        CFRelease(copy);
        return NULL;
    }
    return copy;
}

CFIndex CFDataGetLength(CFDataRef data) {
    return data ? (CFIndex)[(NSData *)data length] : 0;
}

const UInt8 *CFDataGetBytePtr(CFDataRef data) {
    return data ? (const UInt8 *)[(NSData *)data bytes] : NULL;
}

UInt8 *CFDataGetMutableBytePtr(CFMutableDataRef data) {
    return data
        ? LC32GetMutableDataGuestBytes((NSMutableData *)data)
        : NULL;
}

void CFDataGetBytes(CFDataRef data, CFRange range, UInt8 *buffer) {
    if(!data || !buffer || !LC32CFDataValidRange(range)) return;
    const CFIndex length = CFDataGetLength(data);
    if(range.location > length || range.length > length - range.location)
        return;
    static_assert(sizeof(CFRange) == sizeof(NSRange));
    [(NSData *)data getBytes:buffer range:*(NSRange *)&range];
}

void CFDataAppendBytes(CFMutableDataRef data, const UInt8 *bytes,
                       CFIndex length) {
    if(!data || !LC32CFDataValidLength(length) || (length && !bytes)) return;
    LC32_CF_CALL(LC32CoreFoundationOpDataAppendBytes,
        LC32_CF_HOST(data), LC32_CF_U32((uintptr_t)bytes),
        LC32_CF_U32(length));
    LC32InvalidateDataGuestBuffer((NSData *)data);
}

void CFDataDeleteBytes(CFMutableDataRef data, CFRange range) {
    if(!data || !LC32CFDataValidRange(range)) return;
    LC32_CF_CALL(LC32CoreFoundationOpDataDeleteBytes,
        LC32_CF_HOST(data), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length));
    LC32InvalidateDataGuestBuffer((NSData *)data);
}

void CFDataIncreaseLength(CFMutableDataRef data, CFIndex extraLength) {
    if(!data || !LC32CFDataValidLength(extraLength)) return;
    LC32_CF_CALL(LC32CoreFoundationOpDataIncreaseLength,
        LC32_CF_HOST(data), LC32_CF_U32(extraLength));
    LC32InvalidateDataGuestBuffer((NSData *)data);
}

void CFDataReplaceBytes(CFMutableDataRef data, CFRange range,
                        const UInt8 *newBytes, CFIndex newLength) {
    if(!data || !LC32CFDataValidRange(range) ||
       !LC32CFDataValidLength(newLength) || (newLength && !newBytes)) return;
    LC32_CF_CALL(LC32CoreFoundationOpDataReplaceBytes,
        LC32_CF_HOST(data), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32((uintptr_t)newBytes),
        LC32_CF_U32(newLength));
    LC32InvalidateDataGuestBuffer((NSData *)data);
}

void CFDataSetLength(CFMutableDataRef data, CFIndex length) {
    if(!data || !LC32CFDataValidLength(length)) return;
    LC32_CF_CALL(LC32CoreFoundationOpDataSetLength,
        LC32_CF_HOST(data), LC32_CF_U32(length));
    LC32InvalidateDataGuestBuffer((NSData *)data);
}

CFRange CFDataFind(CFDataRef data, CFDataRef dataToFind,
                   CFRange searchRange,
                   CFDataSearchFlags compareOptions) {
    const CFRange notFound = CFRangeMake(kCFNotFound, 0);
    if(!data || !dataToFind || !LC32CFDataValidRange(searchRange))
        return notFound;

    const CFIndex dataLength = CFDataGetLength(data);
    const CFIndex needleLength = CFDataGetLength(dataToFind);
    if(searchRange.location > dataLength ||
       searchRange.length > dataLength - searchRange.location ||
       needleLength < 0 || needleLength > searchRange.length) {
        return notFound;
    }

    const Boolean backwards =
        (compareOptions & kCFDataSearchBackwards) != 0;
    const Boolean anchored =
        (compareOptions & kCFDataSearchAnchored) != 0;
    if(needleLength == 0) return notFound;

    const UInt8 *haystack = CFDataGetBytePtr(data);
    const UInt8 *needle = CFDataGetBytePtr(dataToFind);
    if(!haystack || !needle) return notFound;

    const CFIndex lastStart = searchRange.location +
        searchRange.length - needleLength;
    if(anchored) {
        const CFIndex location = backwards
            ? lastStart : searchRange.location;
        return memcmp(haystack + location, needle,
                      (size_t)needleLength) == 0
            ? CFRangeMake(location, needleLength) : notFound;
    }

    if(backwards) {
        for(CFIndex location = lastStart;
                location >= searchRange.location; --location) {
            if(memcmp(haystack + location, needle,
                      (size_t)needleLength) == 0) {
                return CFRangeMake(location, needleLength);
            }
        }
    } else {
        for(CFIndex location = searchRange.location;
                location <= lastStart; ++location) {
            if(memcmp(haystack + location, needle,
                      (size_t)needleLength) == 0) {
                return CFRangeMake(location, needleLength);
            }
        }
    }
    return notFound;
}
