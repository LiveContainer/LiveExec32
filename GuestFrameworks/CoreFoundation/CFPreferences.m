#import <CoreFoundation/CoreFoundation+LC32.h>

#pragma clang diagnostic ignored "-Wnonnull"

void CFPreferencesAddSuitePreferencesToApp(
        CFStringRef applicationID, CFStringRef suiteID) {
    if(!applicationID || !suiteID) return;
    LC32_CF_CALL(LC32CoreFoundationOpPreferencesAddSuitePreferencesToApp,
        LC32_CF_HOST(applicationID), LC32_CF_HOST(suiteID));
}

void CFPreferencesRemoveSuitePreferencesFromApp(
        CFStringRef applicationID, CFStringRef suiteID) {
    if(!applicationID || !suiteID) return;
    LC32_CF_CALL(LC32CoreFoundationOpPreferencesRemoveSuitePreferencesFromApp,
        LC32_CF_HOST(applicationID), LC32_CF_HOST(suiteID));
}

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

void CFPreferencesSetAppValue(CFStringRef key, CFPropertyListRef value,
                              CFStringRef applicationID) {
    if(!key || !applicationID) return;
    LC32_CF_CALL(LC32CoreFoundationOpPreferencesSetAppValue,
        LC32_CF_HOST(key), LC32_CF_HOST(value),
        LC32_CF_HOST(applicationID));
}

Boolean CFPreferencesAppSynchronize(CFStringRef applicationID) {
    return applicationID && LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesAppSynchronize,
        LC32_CF_HOST(applicationID));
}

CFPropertyListRef CFPreferencesCopyValue(
        CFStringRef key, CFStringRef applicationID,
        CFStringRef userName, CFStringRef hostName) {
    if(!key || !applicationID || !userName || !hostName) return NULL;
    return (CFPropertyListRef)LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesCopyValue,
        LC32_CF_HOST(key), LC32_CF_HOST(applicationID),
        LC32_CF_HOST(userName), LC32_CF_HOST(hostName));
}

CFDictionaryRef CFPreferencesCopyMultiple(
        CFArrayRef keysToFetch, CFStringRef applicationID,
        CFStringRef userName, CFStringRef hostName) {
    if(!applicationID || !userName || !hostName) return NULL;
    return (CFDictionaryRef)LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesCopyMultiple,
        LC32_CF_HOST(keysToFetch), LC32_CF_HOST(applicationID),
        LC32_CF_HOST(userName), LC32_CF_HOST(hostName));
}

void CFPreferencesSetValue(
        CFStringRef key, CFPropertyListRef value,
        CFStringRef applicationID, CFStringRef userName,
        CFStringRef hostName) {
    if(!key || !applicationID || !userName || !hostName) return;
    LC32_CF_CALL(LC32CoreFoundationOpPreferencesSetValue,
        LC32_CF_HOST(key), LC32_CF_HOST(value),
        LC32_CF_HOST(applicationID), LC32_CF_HOST(userName),
        LC32_CF_HOST(hostName));
}

void CFPreferencesSetMultiple(
        CFDictionaryRef keysToSet, CFArrayRef keysToRemove,
        CFStringRef applicationID, CFStringRef userName,
        CFStringRef hostName) {
    if(!applicationID || !userName || !hostName) return;
    LC32_CF_CALL(LC32CoreFoundationOpPreferencesSetMultiple,
        LC32_CF_HOST(keysToSet), LC32_CF_HOST(keysToRemove),
        LC32_CF_HOST(applicationID), LC32_CF_HOST(userName),
        LC32_CF_HOST(hostName));
}

Boolean CFPreferencesSynchronize(
        CFStringRef applicationID, CFStringRef userName,
        CFStringRef hostName) {
    return applicationID && userName && hostName && LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesSynchronize,
        LC32_CF_HOST(applicationID), LC32_CF_HOST(userName),
        LC32_CF_HOST(hostName));
}

CFArrayRef CFPreferencesCopyApplicationList(
        CFStringRef userName, CFStringRef hostName) {
    if(!userName || !hostName) return NULL;
    return (CFArrayRef)LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesCopyApplicationList,
        LC32_CF_HOST(userName), LC32_CF_HOST(hostName));
}

CFArrayRef CFPreferencesCopyKeyList(
        CFStringRef applicationID, CFStringRef userName,
        CFStringRef hostName) {
    if(!applicationID || !userName || !hostName) return NULL;
    return (CFArrayRef)LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesCopyKeyList,
        LC32_CF_HOST(applicationID), LC32_CF_HOST(userName),
        LC32_CF_HOST(hostName));
}

Boolean CFPreferencesAppValueIsForced(
        CFStringRef key, CFStringRef applicationID) {
    return key && applicationID && LC32_CF_CALL(
        LC32CoreFoundationOpPreferencesAppValueIsForced,
        LC32_CF_HOST(key), LC32_CF_HOST(applicationID));
}
