#import <CFNetwork/CFNetwork.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <arpa/inet.h>
#include <netdb.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef LC32_CFHOST_NATIVE_CHECK
_Static_assert(sizeof(CFStreamError) == 8, "guest CFStreamError must be 8 bytes");
_Static_assert(offsetof(CFStreamError, error) == 4, "guest error follows 32-bit domain");
#endif

typedef struct {
    uint64_t before;
    CFStreamError error;
    uint64_t after;
} ErrorGuard;
_Static_assert(offsetof(ErrorGuard, after) ==
    offsetof(ErrorGuard, error) + sizeof(CFStreamError), "canary must immediately follow error");

static const uint64_t beforeCanary = UINT64_C(0x13579bdf2468ace0);
static const uint64_t afterCanary = UINT64_C(0xfedcba9876543210);
static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL canariesIntact(const ErrorGuard *guard) {
    return guard->before == beforeCanary && guard->after == afterCanary;
}

static BOOL hasLoopbackAddress(CFArrayRef addresses) {
    if(!addresses || CFGetTypeID(addresses) != CFArrayGetTypeID()) return NO;
    for(CFIndex index = 0; index < CFArrayGetCount(addresses); ++index) {
        CFDataRef data = (CFDataRef)CFArrayGetValueAtIndex(addresses, index);
        if(!data || CFGetTypeID(data) != CFDataGetTypeID() ||
           CFDataGetLength(data) < (CFIndex)sizeof(struct sockaddr_in)) continue;
        struct sockaddr_in address = {0};
        CFDataGetBytes(data, CFRangeMake(0, sizeof(address)), (UInt8 *)&address);
        if(address.sin_len == sizeof(address) && address.sin_family == AF_INET &&
           address.sin_port == 0 && address.sin_addr.s_addr == htonl(INADDR_LOOPBACK)) {
            const UInt8 *bytes = (const UInt8 *)&address.sin_addr;
            return bytes[0] == 127 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 1;
        }
    }
    return NO;
}

static void testNumericLoopback(void) {
    CFHostRef host = CFHostCreateWithName(kCFAllocatorDefault, CFSTR("127.0.0.1"));
    check("cfhost-create-numeric-loopback", host != NULL);
    if(!host) return;
    Boolean resolved = true;
    check("cfhost-initial-addresses-unresolved",
        CFHostGetAddressing(host, &resolved) == NULL && !resolved);

    // No client/run-loop scheduling: resolution must finish synchronously.
    ErrorGuard guard = {beforeCanary, {-77, -12345}, afterCanary};
    Boolean success = CFHostStartInfoResolution(host, kCFHostAddresses, &guard.error);
    check("cfhost-sync-loopback-resolution", success);
    check("cfhost-success-error-canaries", canariesIntact(&guard));
    // CFHost documents error contents only on failure; success may leave the
    // sentinel alone or clear it, so do not assert either behavior here.

    struct { UInt8 before; Boolean resolved; UInt8 after; } flag = {0xa5, false, 0x5a};
    CFArrayRef addresses = CFHostGetAddressing(host, &flag.resolved);
    check("cfhost-addresses-resolved-flag", flag.resolved &&
        flag.before == 0xa5 && flag.after == 0x5a);
    check("cfhost-addresses-valid-ipv4-bytes", hasLoopbackAddress(addresses));
    check("cfhost-addresses-null-flag", hasLoopbackAddress(CFHostGetAddressing(host, NULL)));

    CFArrayRef retained = addresses ? CFRetain(addresses) : NULL;
    CFHostRef copy = CFHostCreateCopy(kCFAllocatorDefault, host);
    CFRelease(host);
    check("cfhost-retained-get-survives-host-release", hasLoopbackAddress(retained));
    resolved = false;
    CFArrayRef copiedAddresses = copy ? CFHostGetAddressing(copy, &resolved) : NULL;
    check("cfhost-copy-preserves-resolved-addresses", copy && resolved &&
        hasLoopbackAddress(copiedAddresses));
    if(copy) CFRelease(copy);
    check("cfhost-retained-get-survives-copy-release", hasLoopbackAddress(retained));
    if(retained) CFRelease(retained);

    host = CFHostCreateWithName(kCFAllocatorDefault, CFSTR("127.0.0.1"));
    check("cfhost-success-null-error", host &&
        CFHostStartInfoResolution(host, kCFHostAddresses, NULL));
    if(host) {
        check("cfhost-null-error-populates-addresses",
            hasLoopbackAddress(CFHostGetAddressing(host, NULL)));
        CFHostCancelInfoResolution(host, kCFHostAddresses);
        check("cfhost-cancel-idle-returned", YES);
        CFRelease(host);
    }
}

static void testInvalidHostname(void) {
    // A single 1024-byte label exceeds DNS name/label limits and is rejected
    // locally; unlike a nonexistent valid hostname it needs no external DNS.
    UInt8 invalidLabel[1024];
    memset(invalidLabel, 'a', sizeof(invalidLabel));
    CFStringRef name = CFStringCreateWithBytes(kCFAllocatorDefault, invalidLabel,
        sizeof(invalidLabel), kCFStringEncodingASCII, false);
    CFHostRef host = name ? CFHostCreateWithName(kCFAllocatorDefault, name) : NULL;
    if(name) CFRelease(name);
    check("cfhost-create-invalid-name-object", host != NULL);
    if(!host) return;

    ErrorGuard guard = {beforeCanary, {-77, -12345}, afterCanary};
    Boolean success = CFHostStartInfoResolution(host, kCFHostAddresses, &guard.error);
    check("cfhost-invalid-name-fails", !success);
    check("cfhost-failure-error-canaries", canariesIntact(&guard));
    if(!success) {
        printf("cfhost-invalid-name-error: domain=%ld error=%d\n",
            (long)guard.error.domain, (int)guard.error.error);
        check("cfhost-failure-domain", guard.error.domain == kCFStreamErrorDomainNetDB);
        // Darwin EAI_NONAME is positive. Exact comparison catches an offset,
        // truncation, or sign mistake when narrowing the host's 16-byte cell.
        check("cfhost-failure-signed-error-code", guard.error.error == EAI_NONAME);
    }
    check("cfhost-failure-null-error",
        !CFHostStartInfoResolution(host, kCFHostAddresses, NULL));
    CFHostCancelInfoResolution(host, kCFHostAddresses);
    check("cfhost-cancel-failed-idle-returned", YES);
    CFRelease(host);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    testNumericLoopback();
    testInvalidHostname();
    [pool drain];
    return failures != 0;
}
