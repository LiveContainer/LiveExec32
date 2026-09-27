#import <CoreFoundation/CoreFoundation+LC32.h>

CFStringTokenizerRef CFStringTokenizerCreate(CFAllocatorRef allocator,
        CFStringRef string, CFRange range, CFOptionFlags options, CFLocaleRef locale) {
    (void)allocator;
    return string ? (CFStringTokenizerRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringTokenizerCreate, LC32_CF_HOST(string),
        LC32_CF_U32(range.location), LC32_CF_U32(range.length),
        LC32_CF_U32(options), LC32_CF_HOST(locale)) : NULL;
}

CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer) {
    return tokenizer ? (CFStringTokenizerTokenType)LC32_CF_CALL(
        LC32CoreFoundationOpStringTokenizerAdvanceToNextToken,
        LC32_CF_HOST(tokenizer)) : kCFStringTokenizerTokenNone;
}

CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer) {
    CFRange range = CFRangeMake(kCFNotFound, 0);
    if(tokenizer) LC32_CF_CALL(LC32CoreFoundationOpStringTokenizerGetCurrentTokenRange,
        LC32_CF_HOST(tokenizer), LC32_CF_U32((uintptr_t)&range));
    return range;
}

CFStringRef CFStringTokenizerCopyBestStringLanguage(CFStringRef string, CFRange range) {
    return string ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpStringTokenizerCopyBestStringLanguage,
        LC32_CF_HOST(string), LC32_CF_U32(range.location), LC32_CF_U32(range.length)) : NULL;
}
