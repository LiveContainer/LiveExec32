#import <CoreFoundation/CoreFoundation+LC32.h>

CFLocaleRef CFLocaleCopyCurrent(void) {
    return (CFLocaleRef)LC32_CF_CALL0(
        LC32CoreFoundationOpLocaleCopyCurrent);
}

CFLocaleRef CFLocaleGetSystem(void) {
    return (CFLocaleRef)LC32_CF_CALL0(
        LC32CoreFoundationOpLocaleGetSystem);
}

CFTypeRef CFLocaleGetValue(CFLocaleRef locale, CFLocaleKey key) {
    if(!locale || !key) return NULL;
    return (CFTypeRef)[(NSLocale *)locale objectForKey:(NSString *)key];
}
