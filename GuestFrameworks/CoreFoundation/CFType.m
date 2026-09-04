#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>
#include <stdlib.h>

static CFTypeID LC32KnownTypeID(LC32CoreFoundationKnownType type) {
    return (CFTypeID)LC32_CF_CALL(
        LC32CoreFoundationOpGetKnownTypeID, LC32_CF_U32(type));
}

CFTypeID CFGetTypeID(CFTypeRef object) {
    return object ? (CFTypeID)LC32_CF_CALL(
        LC32CoreFoundationOpGetTypeID, LC32_CF_HOST(object)) : 0;
}

CFTypeRef CFAutorelease(CFTypeRef object) {
    return [(id)object autorelease];
}

CFIndex CFGetRetainCount(CFTypeRef object) {
    return object ? (CFIndex)[(id)object retainCount] : 0;
}

CFTypeID CFArrayGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeArray);
}

CFTypeID CFBooleanGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeBoolean);
}

CFTypeID CFDataGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeData);
}

CFTypeID CFDateGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeDate);
}

CFTypeID CFDictionaryGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeDictionary);
}

CFTypeID CFNullGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeNull);
}

CFTypeID CFNumberGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeNumber);
}

CFTypeID CFSetGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeSet);
}

CFTypeID CFStringGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeString);
}

CFTypeID CFAttributedStringGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeAttributedString);
}

CFTypeID CFBitVectorGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeBitVector);
}

CFTypeID CFBundleGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeBundle);
}

CFTypeID CFNotificationCenterGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeNotificationCenter);
}

CFTypeID CFReadStreamGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeReadStream);
}

CFTypeID CFWriteStreamGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeWriteStream);
}

CFTypeID CFRunLoopGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeRunLoop);
}

CFTypeID CFRunLoopSourceGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeRunLoopSource);
}

CFTypeID CFRunLoopTimerGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeRunLoopTimer);
}

CFTypeID CFSocketGetTypeID(void) {
    return LC32KnownTypeID(LC32CoreFoundationTypeSocket);
}

CFHashCode CFHash(CFTypeRef object) {
    return object ? (CFHashCode)[(id)object hash] : 0;
}

CFAllocatorRef CFGetAllocator(CFTypeRef object) {
    (void)object;
    return kCFAllocatorSystemDefault;
}

void *CFAllocatorAllocate(CFAllocatorRef allocator, CFIndex size,
                          CFOptionFlags hint) {
    (void)hint;
    if(allocator == kCFAllocatorNull || size <= 0) return NULL;

    /*
     * The shim's built-in allocator constants are guest-side identities.
     * Their storage must likewise come from the guest heap: returning a host
     * allocation here would expose an unusable 64-bit pointer to ARM32 code.
     * Custom CFAllocator objects are not currently constructible by this
     * shim, so any non-null, non-null-allocator value uses the same heap.
     */
    return malloc((size_t)size);
}

void CFAllocatorDeallocate(CFAllocatorRef allocator, void *ptr) {
    if(!ptr || allocator == kCFAllocatorNull) return;
    free(ptr);
}

Boolean CFBooleanGetValue(CFBooleanRef boolean) {
    return boolean ? [(NSNumber *)boolean boolValue] : false;
}

CFNumberRef CFNumberCreate(CFAllocatorRef allocator, CFNumberType type,
                           const void *valuePtr) {
    (void)allocator;
    if(!valuePtr) return NULL;
    return (CFNumberRef)LC32_CF_CALL(LC32CoreFoundationOpNumberCreate,
        LC32_CF_U32(type), LC32_CF_U32((uintptr_t)valuePtr));
}

CFComparisonResult CFNumberCompare(CFNumberRef number,
                                   CFNumberRef otherNumber,
                                   void *context) {
    (void)context;
    if(!number || !otherNumber) return kCFCompareEqualTo;
    return (CFComparisonResult)[(NSNumber *)number
        compare:(NSNumber *)otherNumber];
}

CFNumberType CFNumberGetType(CFNumberRef number) {
    return number ? (CFNumberType)LC32_CF_CALL(
        LC32CoreFoundationOpNumberGetType, LC32_CF_HOST(number)) : 0;
}

CFIndex CFNumberGetByteSize(CFNumberRef number) {
    switch(CFNumberGetType(number)) {
        case kCFNumberSInt8Type:
        case kCFNumberCharType:
            return sizeof(int8_t);
        case kCFNumberSInt16Type:
        case kCFNumberShortType:
            return sizeof(int16_t);
        case kCFNumberSInt32Type:
        case kCFNumberIntType:
        case kCFNumberLongType:
        case kCFNumberCFIndexType:
        case kCFNumberNSIntegerType:
            return sizeof(int32_t);
        case kCFNumberFloat32Type:
        case kCFNumberFloatType:
        case kCFNumberCGFloatType:
            return sizeof(float);
        case kCFNumberSInt64Type:
        case kCFNumberLongLongType:
            return sizeof(int64_t);
        case kCFNumberFloat64Type:
        case kCFNumberDoubleType:
            return sizeof(double);
    }
    return 0;
}

Boolean CFNumberIsFloatType(CFNumberRef number) {
    switch(CFNumberGetType(number)) {
        case kCFNumberFloat32Type:
        case kCFNumberFloat64Type:
        case kCFNumberFloatType:
        case kCFNumberDoubleType:
        case kCFNumberCGFloatType:
            return true;
        default:
            return false;
    }
}

CFTypeRef CFMakeCollectable(CFTypeRef object) {
    return object;
}

CFStringRef CFCopyTypeIDDescription(CFTypeID typeID) {
    const char *name = "CFType";
    if(typeID == CFArrayGetTypeID()) name = "CFArray";
    else if(typeID == CFBooleanGetTypeID()) name = "CFBoolean";
    else if(typeID == CFDataGetTypeID()) name = "CFData";
    else if(typeID == CFDateGetTypeID()) name = "CFDate";
    else if(typeID == CFDictionaryGetTypeID()) name = "CFDictionary";
    else if(typeID == CFNullGetTypeID()) name = "CFNull";
    else if(typeID == CFNumberGetTypeID()) name = "CFNumber";
    else if(typeID == CFSetGetTypeID()) name = "CFSet";
    else if(typeID == CFStringGetTypeID()) name = "CFString";
    return CFStringCreateWithCString(
        kCFAllocatorDefault, name, kCFStringEncodingUTF8);
}
