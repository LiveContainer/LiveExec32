#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>
#include <stdio.h>

@interface NSObject (LC32CFTypeOwnershipTest)
- (NSUInteger)LC32_retainCount;
@end

static unsigned deallocations;
static char probeKey;
static int failures;

@interface LC32CFTypeDeallocProbe : LC32GuestBuffer
@end
@implementation LC32CFTypeDeallocProbe
- (void)dealloc {
    ++deallocations;
    [super dealloc];
}
@end

static void check(const char *name, BOOL passed) {
    printf("cf-type-ownership-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static uint64_t rawSend(uint64_t host, SEL selector) {
    // Each call here has a real native owner independent of weak support.
    return LC32InvokeHostSelector(host,
        LC32HostSelectorAllowingUnmappedReceiver(LC32GetHostSelector(selector)),
        (uint64_t)0);
}

static CGColorSpaceRef createPattern(void) {
    // Unlike device RGB/Gray spaces, this is not a cached immortal object.
    CGColorSpaceRef space = CGColorSpaceCreatePattern(NULL);
    if(!space) return NULL;
    LC32CFTypeDeallocProbe *probe = [LC32CFTypeDeallocProbe new];
    objc_setAssociatedObject((id)space, &probeKey, probe,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [probe release];
    return space;
}

static void testOwnedReferences(unsigned mode) {
    const unsigned baseline = deallocations;
    CGColorSpaceRef space = createPattern();
    if(!space) { check("pattern-create", NO); return; }
    const uint32_t guest = (uint32_t)(uintptr_t)space;
    const uint64_t host = [(id)space host_self];
    check("create-owns-one-paired-reference",
        [(id)space LC32_retainCount] == 1 &&
        rawSend(host, @selector(retainCount)) == 1);

    check("retain-identity", CGColorSpaceRetain(space) == space &&
        CFRetain(space) == space && [(id)space retain] == (id)space);
    check("retains-reach-native",
        rawSend(host, @selector(retainCount)) == 4 &&
        [(id)space LC32_retainCount] == 4);
    CGColorSpaceRelease(space);
    CFRelease(space);
    [(id)space release];
    check("balanced-releases-preserve-final-owner",
        deallocations == baseline &&
        rawSend(host, @selector(retainCount)) == 1 &&
        [(id)space LC32_retainCount] == 1 &&
        CGColorSpaceGetModel(space) == kCGColorSpaceModelPattern);

    if(mode == 0) CGColorSpaceRelease(space);
    else if(mode == 1) CFRelease(space);
    else [(id)space release];
    static const char *names[] = {"cg-final-release", "cf-final-release",
        "objc-final-release"};
    check(names[mode], LC32LookupHostMapping(guest) == 0 &&
        deallocations == baseline + 1);
}

static void testNativeOnlyOwner(void) {
    CGColorSpaceRef space = createPattern();
    if(!space) { check("borrowed-create", NO); return; }
    const unsigned baseline = deallocations;
    const uint32_t guest = (uint32_t)(uintptr_t)space;
    const uint64_t host = [(id)space host_self];
    rawSend(host, @selector(retain));
    CGColorSpaceRelease(space);
    check("native-only-owner-outlives-proxy",
        LC32LookupHostMapping(guest) == 0 && deallocations == baseline + 1 &&
        rawSend(host, @selector(retainCount)) == 1);

    NSAutoreleasePool *reimportPool = [NSAutoreleasePool new];
    id reimported = LC32HostToGuestObject(host);
    const uint32_t newGuest = (uint32_t)(uintptr_t)reimported;
    check("reimport-cleared-reverse-mapping", reimported &&
        LC32LookupHostMapping(newGuest) == host &&
        [reimported LC32_retainCount] == 1 &&
        rawSend(host, @selector(retainCount)) == 2);
    rawSend(host, @selector(release));
    check("borrowed-proxy-keeps-native-live",
        CGColorSpaceGetModel((CGColorSpaceRef)reimported) == kCGColorSpaceModelPattern);
    [reimportPool drain];
    check("borrowed-proxy-expires-with-pool", LC32LookupHostMapping(newGuest) == 0);
}

static void testAutorelease(void) {
    const unsigned baseline = deallocations;
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CGColorSpaceRef space = createPattern();
    const uint32_t guest = (uint32_t)(uintptr_t)space;
    check("autorelease-identity", space && CFAutorelease(space) == space);
    [pool drain];
    check("autorelease-cleans-both-halves",
        LC32LookupHostMapping(guest) == 0 && deallocations == baseline + 1);
}

static void testSharedSpaces(void) {
    const unsigned baseline = deallocations;
    BOOL balanced = YES;
    for(unsigned i = 0; i < 8; ++i) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGColorSpaceRef second = CGColorSpaceCreateDeviceRGB();
        if(!space || !second) { balanced = NO; break; }
        const uint32_t guest = (uint32_t)(uintptr_t)space;
        LC32CFTypeDeallocProbe *probe = [LC32CFTypeDeallocProbe new];
        objc_setAssociatedObject((id)space, &probeKey, probe,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [probe release];
        balanced &= space == second && [(id)space LC32_retainCount] == 2;
        CGColorSpaceRelease(second);
        balanced &= CGColorSpaceGetNumberOfComponents(space) == 3;
        CFRelease(space);
        balanced &= LC32LookupHostMapping(guest) == 0 &&
            deallocations == baseline + i + 1;
    }
    check("shared-colorspace-repeated-create-release", balanced);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        for(unsigned mode = 0; mode < 3; ++mode) testOwnedReferences(mode);
        if(!failures) { testNativeOnlyOwner(); testAutorelease(); testSharedSpaces(); }
        CGColorSpaceRelease(NULL);
        check("null-retain", CGColorSpaceRetain(NULL) == NULL);
    }
    check("all-probes-destroyed-once", deallocations == 13);
    return failures != 0;
}
