#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <stdio.h>
#include <unistd.h>

enum { LC32ErrSecMissingEntitlement = -34018 };

static int report(const char *name, BOOL passed, OSStatus status) {
    printf("%s: %s (%d)\n", name, passed ? "PASS" : "FAIL",
        (int)status);
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int passed = 1;

    @autoreleasepool {
        const BOOL constantsValid =
            CFEqual(kSecAttrAccessGroup, CFSTR("agrp")) &&
            CFEqual(kSecValuePersistentRef,
                    CFSTR("v_PersistentRef")) &&
            CFEqual(kSecValueRef, CFSTR("v_Ref")) &&
            CFEqual(kSecReturnAttributes, CFSTR("r_Attributes"));
        passed &= report("security-constants", constantsValid, noErr);

        CFTypeRef invalidResult = (CFTypeRef)(uintptr_t)1;
        const OSStatus invalidStatus =
            SecItemCopyMatching(NULL, &invalidResult);
        passed &= report("security-native-invalid-query",
            invalidStatus == errSecParam && invalidResult == NULL,
            invalidStatus);

        NSString *service = [NSString stringWithFormat:
            @"org.liveexec32.security-test.%d", getpid()];
        NSString *account = @"guest-account";
        NSData *firstData = [@"guest-secret-one"
            dataUsingEncoding:NSUTF8StringEncoding];
        NSData *secondData = [@"guest-secret-two"
            dataUsingEncoding:NSUTF8StringEncoding];

        NSDictionary *identity = @{
            (id)kSecClass: (id)kSecClassGenericPassword,
            (id)kSecAttrService: service,
            (id)kSecAttrAccount: account,
        };
        const OSStatus predeleteStatus = SecItemDelete(
            (CFDictionaryRef)identity);
        if(predeleteStatus == errSecNotAvailable ||
           predeleteStatus == LC32ErrSecMissingEntitlement) {
            CFTypeRef unavailableResult = (CFTypeRef)(uintptr_t)1;
            NSMutableDictionary *unavailableAdd =
                [identity mutableCopy];
            unavailableAdd[(id)kSecValueData] = firstData;
            const OSStatus unavailableStatus = SecItemAdd(
                (CFDictionaryRef)unavailableAdd, &unavailableResult);
            passed &= report("security-host-keychain-unavailable",
                unavailableStatus == predeleteStatus &&
                    unavailableResult == NULL,
                unavailableStatus);
            printf("security-keychain-cycle: SKIP (host keychain unavailable)\n");
            [unavailableAdd release];
            return !passed;
        }
        passed &= report("security-predelete",
            predeleteStatus == errSecSuccess ||
                predeleteStatus == errSecItemNotFound,
            predeleteStatus);

        NSMutableDictionary *add = [identity mutableCopy];
        add[(id)kSecValueData] = firstData;
        add[(id)kSecReturnPersistentRef] = (id)kCFBooleanTrue;
        CFTypeRef persistentReference = NULL;
        const OSStatus addStatus = SecItemAdd(
            (CFDictionaryRef)add, &persistentReference);
        const BOOL addValid = addStatus == errSecSuccess &&
            persistentReference != NULL &&
            CFGetTypeID(persistentReference) == CFDataGetTypeID();
        passed &= report("security-add-persistent-ref", addValid,
            addStatus);

        CFTypeRef duplicateResult = (CFTypeRef)(uintptr_t)1;
        const OSStatus duplicateStatus = SecItemAdd(
            (CFDictionaryRef)add, &duplicateResult);
        passed &= report("security-duplicate-result-zeroed",
            duplicateStatus == errSecDuplicateItem &&
                duplicateResult == NULL,
            duplicateStatus);

        NSDictionary *updatedAttributes = @{
            (id)kSecValueData: secondData,
        };
        const OSStatus updateStatus = SecItemUpdate(
            (CFDictionaryRef)identity,
            (CFDictionaryRef)updatedAttributes);
        passed &= report("security-update", updateStatus == errSecSuccess,
            updateStatus);

        NSMutableDictionary *dataQuery = [identity mutableCopy];
        dataQuery[(id)kSecReturnData] = (id)kCFBooleanTrue;
        dataQuery[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
        CFTypeRef copiedData = NULL;
        const OSStatus copyStatus = SecItemCopyMatching(
            (CFDictionaryRef)dataQuery, &copiedData);
        const BOOL copyValid = copyStatus == errSecSuccess &&
            copiedData && CFEqual(copiedData, (CFDataRef)secondData);
        passed &= report("security-copy-updated-data", copyValid,
            copyStatus);
        if(copiedData) CFRelease(copiedData);

        if(persistentReference) {
            NSDictionary *persistentQuery = @{
                (id)kSecValuePersistentRef: (id)persistentReference,
                (id)kSecReturnData: (id)kCFBooleanTrue,
            };
            CFTypeRef persistentData = NULL;
            const OSStatus persistentStatus = SecItemCopyMatching(
                (CFDictionaryRef)persistentQuery, &persistentData);
            const BOOL persistentValid =
                persistentStatus == errSecSuccess && persistentData &&
                CFEqual(persistentData, (CFDataRef)secondData);
            passed &= report("security-persistent-ref-roundtrip",
                persistentValid, persistentStatus);
            if(persistentData) CFRelease(persistentData);
            CFRelease(persistentReference);
        }

        const OSStatus deleteStatus = SecItemDelete(
            (CFDictionaryRef)identity);
        passed &= report("security-delete", deleteStatus == errSecSuccess,
            deleteStatus);

        CFTypeRef missingResult = (CFTypeRef)(uintptr_t)1;
        const OSStatus missingStatus = SecItemCopyMatching(
            (CFDictionaryRef)dataQuery, &missingResult);
        passed &= report("security-missing-result-zeroed",
            missingStatus == errSecItemNotFound && missingResult == NULL,
            missingStatus);

        [add release];
        [dataQuery release];
    }

    return !passed;
}
