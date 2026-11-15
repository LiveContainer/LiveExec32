#include <CoreFoundation/CoreFoundation.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

typedef union {
    CFUUIDBytes bytes;
    UInt8 rawBytes[16];
} UUIDBytes;

_Static_assert(sizeof(CFUUIDBytes) == 16,
               "CFUUIDBytes must contain exactly 16 bytes");
_Static_assert(offsetof(CFUUIDBytes, byte0) == 0,
               "CFUUIDBytes byte0 must be first");
_Static_assert(offsetof(CFUUIDBytes, byte15) == 15,
               "CFUUIDBytes byte15 must be last");

static int failures;

static void check(const char *name, int condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void test_file_security(const UUIDBytes *ownerBytes) {
    UUIDBytes groupBytes = *ownerBytes;
    groupBytes.rawBytes[0] ^= 0xff;
    CFUUIDRef owner = CFUUIDCreateFromUUIDBytes(NULL, ownerBytes->bytes);
    CFUUIDRef group = CFUUIDCreateFromUUIDBytes(NULL, groupBytes.bytes);
    CFFileSecurityRef security = CFFileSecurityCreate(NULL);
    const Boolean setOwner = security && owner &&
        CFFileSecuritySetOwnerUUID(security, owner);
    const Boolean setGroup = security && group &&
        CFFileSecuritySetGroupUUID(security, group);
    check("uuid-file-security-set-native-types", setOwner && setGroup);
    if(owner) CFRelease(owner);
    if(group) CFRelease(group);

    CFFileSecurityRef copy = security ? CFFileSecurityCreateCopy(NULL, security) : NULL;
    if(security) CFRelease(security);
    struct { CFUUIDRef value; uint32_t guard; } copiedOwner = {NULL, 0x11223344};
    struct { CFUUIDRef value; uint32_t guard; } copiedGroup = {NULL, 0xaabbccdd};
    const Boolean gotOwner = copy && CFFileSecurityCopyOwnerUUID(copy, &copiedOwner.value);
    const Boolean gotGroup = copy && CFFileSecurityCopyGroupUUID(copy, &copiedGroup.value);
    check("uuid-file-security-copy-output-width", gotOwner && gotGroup &&
        copiedOwner.guard == 0x11223344 && copiedGroup.guard == 0xaabbccdd);
    check("uuid-file-security-copied-value-as-input", copy && copiedGroup.value &&
        CFFileSecuritySetOwnerUUID(copy, copiedGroup.value));
    if(copy) CFRelease(copy);

    CFUUIDBytes actualOwner = {0}, actualGroup = {0};
    if(copiedOwner.value) actualOwner = CFUUIDGetUUIDBytes(copiedOwner.value);
    if(copiedGroup.value) actualGroup = CFUUIDGetUUIDBytes(copiedGroup.value);
    check("uuid-file-security-copy-content-and-lifetime", gotOwner && gotGroup &&
        !memcmp(&actualOwner, &ownerBytes->bytes, sizeof(actualOwner)) &&
        !memcmp(&actualGroup, &groupBytes.bytes, sizeof(actualGroup)) &&
        CFGetTypeID(copiedOwner.value) == CFUUIDGetTypeID() &&
        CFGetTypeID(copiedGroup.value) == CFUUIDGetTypeID());
    CFStringRef string = copiedOwner.value ? CFUUIDCreateString(NULL, copiedOwner.value) : NULL;
    CFUUIDRef roundtrip = string ? CFUUIDCreateFromString(NULL, string) : NULL;
    check("uuid-file-security-copy-string-roundtrip", roundtrip && copiedOwner.value &&
        CFEqual(roundtrip, copiedOwner.value) && !CFEqual(roundtrip, copiedGroup.value));
    if(roundtrip) CFRelease(roundtrip);
    if(string) CFRelease(string);
    if(copiedOwner.value) CFRelease(copiedOwner.value);
    if(copiedGroup.value) CFRelease(copiedGroup.value);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    const UUIDBytes expected = {.rawBytes = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    }};
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(
        kCFAllocatorDefault, expected.bytes);
    check("uuid-create-from-bytes", uuid != NULL);

    CFUUIDRef scalarUUID = CFUUIDCreateWithBytes(kCFAllocatorDefault,
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff);
    check("uuid-create-with-scalar-bytes", scalarUUID &&
        CFEqual(scalarUUID, uuid));

    struct { uint32_t before; CFUUIDBytes bytes; uint32_t after; } actual = {
        .before = 0x12345678, .after = 0x87654321,
    };
    actual.bytes = CFUUIDGetUUIDBytes(uuid);
    check("uuid-get-bytes", memcmp(
        &actual.bytes, &expected.bytes, sizeof(actual.bytes)) == 0);
    check("uuid-get-bytes-return-width", actual.before == 0x12345678 &&
        actual.after == 0x87654321);

    CFStringRef string = uuid
        ? CFUUIDCreateString(kCFAllocatorDefault, uuid)
        : NULL;
    char text[37] = {0};
    const Boolean copied = string && CFStringGetCString(
        string, text, sizeof(text), kCFStringEncodingASCII);
    check("uuid-byte-order", copied && strcasecmp(
        text, "00112233-4455-6677-8899-AABBCCDDEEFF") == 0);

    CFUUIDRef parsed = CFUUIDCreateFromString(kCFAllocatorDefault,
        CFSTR("00112233-4455-6677-8899-aabbccddeeff"));
    // Native CFUUID parsing is more permissive than NSUUID. An empty string
    // is rejected; arbitrary malformed nonempty strings need not be.
    CFUUIDRef invalid = CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR(""));
    check("uuid-create-from-string", parsed && CFEqual(parsed, uuid));
    check("uuid-create-from-empty-string", invalid == NULL);
    if(invalid) CFRelease(invalid);
    check("uuid-type-id", uuid && CFUUIDGetTypeID() != 0 &&
        CFGetTypeID(uuid) == CFUUIDGetTypeID());
    CFUUIDRef random = CFUUIDCreate(kCFAllocatorDefault);
    check("uuid-random-create-native-type", random &&
        CFGetTypeID(random) == CFUUIDGetTypeID());
    if(random) CFRelease(random);

    UUIDBytes differentBytes = expected;
    differentBytes.rawBytes[15] ^= 0xff;
    CFUUIDRef different = CFUUIDCreateFromUUIDBytes(NULL, differentBytes.bytes);
    check("uuid-not-equal", uuid && different && !CFEqual(uuid, different) &&
        !CFEqual(uuid, CFSTR("not-a-uuid")));
    check("uuid-hash", uuid && parsed && CFHash(uuid) != 0 &&
        CFHash(uuid) == CFHash(parsed));
    CFStringRef description = uuid ? CFCopyDescription(uuid) : NULL;
    check("uuid-copy-description", description &&
        CFStringFind(description, CFSTR("00112233-4455-6677-8899-AABBCCDDEEFF"),
            kCFCompareCaseInsensitive).location != kCFNotFound);
    if(description) CFRelease(description);
    if(different) CFRelease(different);

    test_file_security(&expected);

    CFUUIDRef constant1 = CFUUIDGetConstantUUIDWithBytes(
        kCFAllocatorDefault,
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff);
    CFUUIDRef constant2 = CFUUIDGetConstantUUIDWithBytes(
        kCFAllocatorDefault,
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff);
    check("uuid-constant-content", constant1 && CFEqual(constant1, uuid));
    check("uuid-constant-identity", constant1 == constant2);

    if(parsed) CFRelease(parsed);
    if(scalarUUID) CFRelease(scalarUUID);
    if(string) CFRelease(string);
    if(uuid) CFRelease(uuid);
    CFUUIDBytes constantBytes = {0};
    if(constant1) constantBytes = CFUUIDGetUUIDBytes(constant1);
    check("uuid-constant-outlives-created-values", constant1 &&
        !memcmp(&constantBytes, &expected.bytes, sizeof(constantBytes)));
    return failures != 0;
}
