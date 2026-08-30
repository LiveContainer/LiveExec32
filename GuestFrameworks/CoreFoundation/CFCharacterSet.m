#import <CoreFoundation/CoreFoundation+LC32.h>

static NSRange LC32CharacterSetRange(CFRange range) {
    _Static_assert(sizeof(CFRange) == sizeof(NSRange),
        "CFRange and NSRange must share their ARM32 ABI");
    return NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length);
}

CFTypeID CFCharacterSetGetTypeID(void) {
    return CFGetTypeID((CFTypeRef)[NSCharacterSet whitespaceCharacterSet]);
}

CFCharacterSetRef CFCharacterSetGetPredefined(
        CFCharacterSetPredefinedSet setIdentifier) {
    switch(setIdentifier) {
        case kCFCharacterSetControl:
            return (CFCharacterSetRef)[NSCharacterSet controlCharacterSet];
        case kCFCharacterSetWhitespace:
            return (CFCharacterSetRef)[NSCharacterSet whitespaceCharacterSet];
        case kCFCharacterSetWhitespaceAndNewline:
            return (CFCharacterSetRef)
                [NSCharacterSet whitespaceAndNewlineCharacterSet];
        case kCFCharacterSetDecimalDigit:
            return (CFCharacterSetRef)[NSCharacterSet decimalDigitCharacterSet];
        case kCFCharacterSetLetter:
            return (CFCharacterSetRef)[NSCharacterSet letterCharacterSet];
        case kCFCharacterSetLowercaseLetter:
            return (CFCharacterSetRef)
                [NSCharacterSet lowercaseLetterCharacterSet];
        case kCFCharacterSetUppercaseLetter:
            return (CFCharacterSetRef)
                [NSCharacterSet uppercaseLetterCharacterSet];
        case kCFCharacterSetNonBase:
            return (CFCharacterSetRef)[NSCharacterSet nonBaseCharacterSet];
        case kCFCharacterSetDecomposable:
            return (CFCharacterSetRef)[NSCharacterSet decomposableCharacterSet];
        case kCFCharacterSetAlphaNumeric:
            return (CFCharacterSetRef)[NSCharacterSet alphanumericCharacterSet];
        case kCFCharacterSetPunctuation:
            return (CFCharacterSetRef)[NSCharacterSet punctuationCharacterSet];
        case kCFCharacterSetCapitalizedLetter:
            return (CFCharacterSetRef)
                [NSCharacterSet capitalizedLetterCharacterSet];
        case kCFCharacterSetSymbol:
            return (CFCharacterSetRef)[NSCharacterSet symbolCharacterSet];
        case kCFCharacterSetNewline:
            return (CFCharacterSetRef)[NSCharacterSet newlineCharacterSet];
        case kCFCharacterSetIllegal:
            return (CFCharacterSetRef)[NSCharacterSet illegalCharacterSet];
    }
    return NULL;
}

CFCharacterSetRef CFCharacterSetCreateWithCharactersInRange(
        CFAllocatorRef allocator, CFRange range) {
    (void)allocator;
    if(range.location < 0 || range.length < 0) return NULL;
    return (CFCharacterSetRef)[[NSCharacterSet
        characterSetWithRange:LC32CharacterSetRange(range)] copy];
}

CFCharacterSetRef CFCharacterSetCreateWithCharactersInString(
        CFAllocatorRef allocator, CFStringRef string) {
    (void)allocator;
    return string ? (CFCharacterSetRef)[[NSCharacterSet
        characterSetWithCharactersInString:(NSString *)string] copy] : NULL;
}

CFCharacterSetRef CFCharacterSetCreateWithBitmapRepresentation(
        CFAllocatorRef allocator, CFDataRef data) {
    (void)allocator;
    return data ? (CFCharacterSetRef)[[NSCharacterSet
        characterSetWithBitmapRepresentation:(NSData *)data] copy] : NULL;
}

CFCharacterSetRef CFCharacterSetCreateInvertedSet(
        CFAllocatorRef allocator, CFCharacterSetRef set) {
    (void)allocator;
    return set ? (CFCharacterSetRef)[[(NSCharacterSet *)set invertedSet] copy]
               : NULL;
}

CFCharacterSetRef CFCharacterSetCreateCopy(
        CFAllocatorRef allocator, CFCharacterSetRef set) {
    (void)allocator;
    return set ? (CFCharacterSetRef)[(NSCharacterSet *)set copy] : NULL;
}

CFMutableCharacterSetRef CFCharacterSetCreateMutable(
        CFAllocatorRef allocator) {
    (void)allocator;
    return (CFMutableCharacterSetRef)[[NSMutableCharacterSet alloc] init];
}

CFMutableCharacterSetRef CFCharacterSetCreateMutableCopy(
        CFAllocatorRef allocator, CFCharacterSetRef set) {
    (void)allocator;
    return set ? (CFMutableCharacterSetRef)
        [(NSCharacterSet *)set mutableCopy] : NULL;
}

Boolean CFCharacterSetIsCharacterMember(CFCharacterSetRef set,
                                         UniChar character) {
    return set && [(NSCharacterSet *)set characterIsMember:character];
}

Boolean CFCharacterSetIsLongCharacterMember(CFCharacterSetRef set,
                                             UTF32Char character) {
    return set && [(NSCharacterSet *)set longCharacterIsMember:character];
}

Boolean CFCharacterSetHasMemberInPlane(CFCharacterSetRef set,
                                       CFIndex plane) {
    return set && plane >= 0 && plane <= UINT8_MAX &&
        [(NSCharacterSet *)set hasMemberInPlane:(uint8_t)plane];
}

CFDataRef CFCharacterSetCreateBitmapRepresentation(
        CFAllocatorRef allocator, CFCharacterSetRef set) {
    (void)allocator;
    return set ? (CFDataRef)[[(NSCharacterSet *)set bitmapRepresentation] copy]
               : NULL;
}

Boolean CFCharacterSetIsSupersetOfSet(CFCharacterSetRef set,
                                      CFCharacterSetRef otherSet) {
    return set && otherSet && [(NSCharacterSet *)set
        isSupersetOfSet:(NSCharacterSet *)otherSet];
}

void CFCharacterSetAddCharactersInRange(
        CFMutableCharacterSetRef set, CFRange range) {
    if(set && range.location >= 0 && range.length >= 0)
        [(NSMutableCharacterSet *)set
            addCharactersInRange:LC32CharacterSetRange(range)];
}

void CFCharacterSetRemoveCharactersInRange(
        CFMutableCharacterSetRef set, CFRange range) {
    if(set && range.location >= 0 && range.length >= 0)
        [(NSMutableCharacterSet *)set
            removeCharactersInRange:LC32CharacterSetRange(range)];
}

void CFCharacterSetAddCharactersInString(
        CFMutableCharacterSetRef set, CFStringRef string) {
    if(set && string) [(NSMutableCharacterSet *)set
        addCharactersInString:(NSString *)string];
}

void CFCharacterSetRemoveCharactersInString(
        CFMutableCharacterSetRef set, CFStringRef string) {
    if(set && string) [(NSMutableCharacterSet *)set
        removeCharactersInString:(NSString *)string];
}

void CFCharacterSetUnion(CFMutableCharacterSetRef set,
                         CFCharacterSetRef otherSet) {
    if(set && otherSet) [(NSMutableCharacterSet *)set
        formUnionWithCharacterSet:(NSCharacterSet *)otherSet];
}

void CFCharacterSetIntersect(CFMutableCharacterSetRef set,
                             CFCharacterSetRef otherSet) {
    if(set && otherSet) [(NSMutableCharacterSet *)set
        formIntersectionWithCharacterSet:(NSCharacterSet *)otherSet];
}

void CFCharacterSetInvert(CFMutableCharacterSetRef set) {
    if(set) [(NSMutableCharacterSet *)set invert];
}
