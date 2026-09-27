#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>

int main(void) {
    CFStringRef string = CFSTR("hello world");
    CFLocaleRef locale = CFLocaleCreate(NULL, CFSTR("en"));
    CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, string,
        CFRangeMake(0, CFStringGetLength(string)), kCFStringTokenizerUnitWord, locale);
    if(locale) CFRelease(locale);
    if(!tokenizer) return 1;
    int passed = CFStringTokenizerAdvanceToNextToken(tokenizer) != kCFStringTokenizerTokenNone;
    struct { CFRange range; uintptr_t guard; } value = {.guard = 0x12345678};
    value.range = CFStringTokenizerGetCurrentTokenRange(tokenizer);
    passed &= value.range.location == 0 && value.range.length == 5 && value.guard == 0x12345678;
    passed &= CFStringTokenizerAdvanceToNextToken(tokenizer) != kCFStringTokenizerTokenNone;
    value.range = CFStringTokenizerGetCurrentTokenRange(tokenizer);
    passed &= value.range.location == 6 && value.range.length == 5;
    passed &= CFStringTokenizerAdvanceToNextToken(tokenizer) == kCFStringTokenizerTokenNone;
    CFRelease(tokenizer);
    CFStringRef english = CFSTR("This is a sentence written in English about a little green frog.");
    CFStringRef language = CFStringTokenizerCopyBestStringLanguage(english,
        CFRangeMake(0, CFStringGetLength(english)));
    passed &= language && CFEqual(language, CFSTR("en"));
    if(language) CFRelease(language);
    printf("cfstring-tokenizer-ranges-language: %s\n", passed ? "PASS" : "FAIL");
    return !passed;
}
