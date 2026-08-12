#import <CoreFoundation/CoreFoundation+LC32.h>

CFPropertyListRef CFPreferencesCopyAppValue(CFStringRef key,
                                            CFStringRef applicationID) {
    if(!key || !applicationID) return NULL;
    return (CFPropertyListRef)LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesCopyAppValue,
        LC32_CF_HOST(key), LC32_CF_HOST(applicationID));
}

Boolean CFPreferencesGetAppBooleanValue(
        CFStringRef key, CFStringRef applicationID,
        Boolean *keyExistsAndHasValidFormat) {
    if(!key || !applicationID) {
        if(keyExistsAndHasValidFormat)
            *keyExistsAndHasValidFormat = false;
        return false;
    }
    return LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesGetAppBooleanValue,
        LC32_CF_HOST(key), LC32_CF_HOST(applicationID),
        LC32_CF_U32((uintptr_t)keyExistsAndHasValidFormat)) != 0;
}

CFIndex CFPreferencesGetAppIntegerValue(
        CFStringRef key, CFStringRef applicationID,
        Boolean *keyExistsAndHasValidFormat) {
    if(!key || !applicationID) {
        if(keyExistsAndHasValidFormat)
            *keyExistsAndHasValidFormat = false;
        return 0;
    }
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesGetAppIntegerValue,
        LC32_CF_HOST(key), LC32_CF_HOST(applicationID),
        LC32_CF_U32((uintptr_t)keyExistsAndHasValidFormat));
}
