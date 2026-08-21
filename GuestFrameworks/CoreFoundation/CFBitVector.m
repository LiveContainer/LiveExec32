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

CFMutableBitVectorRef CFBitVectorCreateMutableCopy(
        CFAllocatorRef allocator, CFIndex capacity, CFBitVectorRef bitVector) {
    (void)allocator;
    if(capacity < 0 || !bitVector) return NULL;
    return (CFMutableBitVectorRef)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorCreateMutableCopy,
        LC32_CF_U32(capacity), LC32_CF_HOST(bitVector));
}

CFBit CFBitVectorGetBitAtIndex(CFBitVectorRef bitVector, CFIndex index) {
    if(!bitVector || index < 0) return 0;
    return (CFBit)LC32_CF_CALL(
        LC32CoreFoundationOpBitVectorGetBitAtIndex,
        LC32_CF_HOST(bitVector), LC32_CF_U32(index));
}

void CFBitVectorSetBitAtIndex(CFMutableBitVectorRef bitVector,
                              CFIndex index, CFBit value) {
    if(!bitVector || index < 0) return;
    LC32_CF_CALL(LC32CoreFoundationOpBitVectorSetBitAtIndex,
        LC32_CF_HOST(bitVector), LC32_CF_U32(index),
        LC32_CF_U32(value != 0));
}
