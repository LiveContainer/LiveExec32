#include <CoreFoundation/CoreFoundation.h>

#include <stddef.h>
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

int main(void) {
    const UUIDBytes expected = {.rawBytes = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    }};
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(
        kCFAllocatorDefault, expected.bytes);
    check("uuid-create-from-bytes", uuid != NULL);

    const CFUUIDBytes actual = CFUUIDGetUUIDBytes(uuid);
    check("uuid-get-bytes", memcmp(
        &actual, &expected.bytes, sizeof(actual)) == 0);

    CFStringRef string = uuid
        ? CFUUIDCreateString(kCFAllocatorDefault, uuid)
        : NULL;
    char text[37] = {0};
    const Boolean copied = string && CFStringGetCString(
        string, text, sizeof(text), kCFStringEncodingASCII);
    check("uuid-byte-order", copied && strcasecmp(
        text, "00112233-4455-6677-8899-AABBCCDDEEFF") == 0);

    if(string) CFRelease(string);
    if(uuid) CFRelease(uuid);
    return failures != 0;
}
