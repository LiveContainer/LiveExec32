#import <CoreFoundation/CoreFoundation+LC32.h>

CFBitVectorRef CFBitVectorCreate(CFAllocatorRef allocator,
                                 const UInt8 *bytes,
                                 CFIndex numBits) {
    (void)allocator;
    if(numBits < 0 || (numBits && !bytes)) return NULL;
    return (CFBitVectorRef)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorCreate,
        LC32_CF_U32((uintptr_t)bytes), LC32_CF_U32(numBits));
}

CFBitVectorRef CFBitVectorCreateCopy(CFAllocatorRef allocator,
                                     CFBitVectorRef bitVector) {
    (void)allocator;
    return bitVector ? (CFBitVectorRef)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorCreateCopy,
        LC32_CF_HOST(bitVector)) : NULL;
}

CFMutableBitVectorRef CFBitVectorCreateMutable(
        CFAllocatorRef allocator, CFIndex capacity) {
    (void)allocator;
    if(capacity < 0) return NULL;
    return (CFMutableBitVectorRef)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorCreateMutable,
        LC32_CF_U32(capacity));
}

CFMutableBitVectorRef CFBitVectorCreateMutableCopy(
        CFAllocatorRef allocator, CFIndex capacity, CFBitVectorRef bitVector) {
    (void)allocator;
    if(capacity < 0 || !bitVector) return NULL;
    return (CFMutableBitVectorRef)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorCreateMutableCopy,
        LC32_CF_U32(capacity), LC32_CF_HOST(bitVector));
}

CFIndex CFBitVectorGetCount(CFBitVectorRef bitVector) {
    return bitVector ? (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorGetCount,
        LC32_CF_HOST(bitVector)) : 0;
}

CFIndex CFBitVectorGetCountOfBit(CFBitVectorRef bitVector,
                                 CFRange range, CFBit value) {
    if(!bitVector || range.location < 0 || range.length < 0) return 0;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorGetCountOfBit,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32(value != 0));
}

Boolean CFBitVectorContainsBit(CFBitVectorRef bitVector,
                               CFRange range, CFBit value) {
    if(!bitVector || range.location < 0 || range.length < 0) return false;
    return LC32_CF_CALL(LC32CoreFoundationOpBitVectorContainsBit,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32(value != 0)) != 0;
}

CFBit CFBitVectorGetBitAtIndex(CFBitVectorRef bitVector, CFIndex index) {
    if(!bitVector || index < 0) return 0;
    return (CFBit)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorGetBitAtIndex,
        LC32_CF_HOST(bitVector), LC32_CF_U32(index));
}

void CFBitVectorGetBits(CFBitVectorRef bitVector, CFRange range,
                        UInt8 *bytes) {
    if(!bitVector || range.location < 0 || range.length < 0 ||
       (range.length && !bytes)) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorGetBits,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32((uintptr_t)bytes));
}

CFIndex CFBitVectorGetFirstIndexOfBit(CFBitVectorRef bitVector,
                                      CFRange range, CFBit value) {
    if(!bitVector || range.location < 0 || range.length < 0)
        return kCFNotFound;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorGetFirstIndexOfBit,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32(value != 0));
}

CFIndex CFBitVectorGetLastIndexOfBit(CFBitVectorRef bitVector,
                                     CFRange range, CFBit value) {
    if(!bitVector || range.location < 0 || range.length < 0)
        return kCFNotFound;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorGetLastIndexOfBit,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32(value != 0));
}

void CFBitVectorSetCount(CFMutableBitVectorRef bitVector, CFIndex count) {
    if(!bitVector || count < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorSetCount,
        LC32_CF_HOST(bitVector), LC32_CF_U32(count));
}

void CFBitVectorFlipBitAtIndex(CFMutableBitVectorRef bitVector,
                               CFIndex index) {
    if(!bitVector || index < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorFlipBitAtIndex,
        LC32_CF_HOST(bitVector), LC32_CF_U32(index));
}

void CFBitVectorFlipBits(CFMutableBitVectorRef bitVector, CFRange range) {
    if(!bitVector || range.location < 0 || range.length < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorFlipBits,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length));
}

void CFBitVectorSetBitAtIndex(CFMutableBitVectorRef bitVector,
                              CFIndex index, CFBit value) {
    if(!bitVector || index < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorSetBitAtIndex,
        LC32_CF_HOST(bitVector), LC32_CF_U32(index),
        LC32_CF_U32(value != 0));
}

void CFBitVectorSetBits(CFMutableBitVectorRef bitVector, CFRange range,
                        CFBit value) {
    if(!bitVector || range.location < 0 || range.length < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorSetBits,
        LC32_CF_HOST(bitVector), LC32_CF_U32(range.location),
        LC32_CF_U32(range.length), LC32_CF_U32(value != 0));
}

void CFBitVectorSetAllBits(CFMutableBitVectorRef bitVector, CFBit value) {
    if(!bitVector) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorSetAllBits,
        LC32_CF_HOST(bitVector), LC32_CF_U32(value != 0));
}
