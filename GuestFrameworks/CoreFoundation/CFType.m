#import <CoreFoundation/CoreFoundation+LC32.h>

static CFTypeID LC32KnownTypeID(LC32CoreFoundationKnownType type) {
    return (CFTypeID)LC32_CF_CALL(
        LC32CoreFoundationOpGetKnownTypeID, LC32_CF_U32(type));
}

CFTypeID CFGetTypeID(CFTypeRef object) {
    return object ? (CFTypeID)LC32_CF_CALL(
        LC32CoreFoundationOpGetTypeID, LC32_CF_HOST(object)) : 0;
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

CFHashCode CFHash(CFTypeRef object) {
    return object ? (CFHashCode)[(id)object hash] : 0;
}

CFAllocatorRef CFGetAllocator(CFTypeRef object) {
    (void)object;
    return kCFAllocatorSystemDefault;
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
