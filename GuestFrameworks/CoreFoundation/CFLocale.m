#import <CoreFoundation/CoreFoundation+LC32.h>

CFTypeID CFLocaleGetTypeID(void) {
    return CFGetTypeID((CFTypeRef)[NSLocale currentLocale]);
}

CFArrayRef CFLocaleCopyAvailableLocaleIdentifiers(void) {
    return (CFArrayRef)[[NSLocale availableLocaleIdentifiers] copy];
}

CFArrayRef CFLocaleCopyISOLanguageCodes(void) {
    return (CFArrayRef)[[NSLocale ISOLanguageCodes] copy];
}

CFArrayRef CFLocaleCopyISOCountryCodes(void) {
    return (CFArrayRef)[[NSLocale ISOCountryCodes] copy];
}

CFArrayRef CFLocaleCopyISOCurrencyCodes(void) {
    return (CFArrayRef)[[NSLocale ISOCurrencyCodes] copy];
}

CFArrayRef CFLocaleCopyCommonISOCurrencyCodes(void) {
    return (CFArrayRef)[[NSLocale commonISOCurrencyCodes] copy];
}

CFArrayRef CFLocaleCopyPreferredLanguages(void) {
    return (CFArrayRef)[[NSLocale preferredLanguages] copy];
}

CFLocaleIdentifier CFLocaleCreateCanonicalLanguageIdentifierFromString(
        CFAllocatorRef allocator, CFStringRef localeIdentifier) {
    (void)allocator;
    if(!localeIdentifier) return NULL;
    return (CFLocaleIdentifier)[[NSLocale
        canonicalLanguageIdentifierFromString:(NSString *)localeIdentifier]
        copy];
}

CFLocaleIdentifier CFLocaleCreateCanonicalLocaleIdentifierFromString(
        CFAllocatorRef allocator, CFStringRef localeIdentifier) {
    (void)allocator;
    if(!localeIdentifier) return NULL;
    return (CFLocaleIdentifier)[[NSLocale
        canonicalLocaleIdentifierFromString:(NSString *)localeIdentifier]
        copy];
}

CFLocaleIdentifier CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes(
        CFAllocatorRef allocator, LangCode languageCode,
        RegionCode regionCode) {
    (void)allocator;
    return (CFLocaleIdentifier)LC32_CF_CALL(
        LC32CoreFoundationOpLocaleCreateCanonicalIdentifierFromScriptCodes,
        LC32_CF_U32((uint16_t)languageCode),
        LC32_CF_U32((uint16_t)regionCode));
}

CFDictionaryRef CFLocaleCreateComponentsFromLocaleIdentifier(
        CFAllocatorRef allocator, CFLocaleIdentifier localeIdentifier) {
    (void)allocator;
    if(!localeIdentifier) return NULL;
    return (CFDictionaryRef)[[NSLocale componentsFromLocaleIdentifier:
        (NSString *)localeIdentifier] copy];
}

CFLocaleIdentifier CFLocaleCreateLocaleIdentifierFromComponents(
        CFAllocatorRef allocator, CFDictionaryRef dictionary) {
    (void)allocator;
    if(!dictionary) return NULL;
    return (CFLocaleIdentifier)[[NSLocale
        localeIdentifierFromComponents:(NSDictionary *)dictionary] copy];
}

CFLocaleIdentifier CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode(
        CFAllocatorRef allocator, uint32_t localeCode) {
    (void)allocator;
    NSString *identifier =
        [NSLocale localeIdentifierFromWindowsLocaleCode:localeCode];
    return (CFLocaleIdentifier)[identifier copy];
}

uint32_t CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier(
        CFLocaleIdentifier localeIdentifier) {
    return localeIdentifier ? [NSLocale
        windowsLocaleCodeFromLocaleIdentifier:(NSString *)localeIdentifier]
        : 0;
}

CFLocaleLanguageDirection CFLocaleGetLanguageCharacterDirection(
        CFStringRef languageCode) {
    return languageCode ? (CFLocaleLanguageDirection)[NSLocale
        characterDirectionForLanguage:(NSString *)languageCode]
        : kCFLocaleLanguageDirectionUnknown;
}

CFLocaleLanguageDirection CFLocaleGetLanguageLineDirection(
        CFStringRef languageCode) {
    return languageCode ? (CFLocaleLanguageDirection)[NSLocale
        lineDirectionForLanguage:(NSString *)languageCode]
        : kCFLocaleLanguageDirectionUnknown;
}

CFLocaleRef CFLocaleCreate(CFAllocatorRef allocator,
                           CFLocaleIdentifier localeIdentifier) {
    (void)allocator;
    if(!localeIdentifier) return NULL;
    return (CFLocaleRef)[[NSLocale alloc]
        initWithLocaleIdentifier:(NSString *)localeIdentifier];
}

CFLocaleRef CFLocaleCreateCopy(CFAllocatorRef allocator,
                               CFLocaleRef locale) {
    (void)allocator;
    return locale ? (CFLocaleRef)[(NSLocale *)locale copy] : NULL;
}

CFLocaleRef CFLocaleCopyCurrent(void) {
    return (CFLocaleRef)LC32_CF_CALL0(
        LC32CoreFoundationOpLocaleCopyCurrent);
}

CFLocaleRef CFLocaleGetSystem(void) {
    return (CFLocaleRef)LC32_CF_CALL0(
        LC32CoreFoundationOpLocaleGetSystem);
}

CFLocaleIdentifier CFLocaleGetIdentifier(CFLocaleRef locale) {
    return locale ? (CFLocaleIdentifier)[(NSLocale *)locale localeIdentifier]
                  : NULL;
}

CFStringRef CFLocaleCopyDisplayNameForPropertyValue(
        CFLocaleRef displayLocale, CFLocaleKey key, CFStringRef value) {
    if(!displayLocale || !key || !value) return NULL;
    return (CFStringRef)[[(NSLocale *)displayLocale
        displayNameForKey:(NSString *)key value:(NSString *)value] copy];
}

CFTypeRef CFLocaleGetValue(CFLocaleRef locale, CFLocaleKey key) {
    if(!locale || !key) return NULL;
    return (CFTypeRef)[(NSLocale *)locale objectForKey:(NSString *)key];
}
