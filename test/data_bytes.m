#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdio.h>
#include <string.h>
#include <time.h>
#include "../GuestFrameworks/CoreFoundation/LC32CoreFoundationBridge.h"

extern uint32_t LC32CoreFoundationDispatch(LC32CoreFoundationOpcode,
    const uint64_t *, uint32_t);

static BOOL CheckNativeComparison(void) {
    unsigned char left[32775], right[32777];
    memset(left, 0x5a, sizeof(left));
    memset(right, 0x5a, sizeof(right));
    uint64_t slots[] = {(uintptr_t)(left + 1), (uintptr_t)(right + 3), 32773};
    BOOL passed = LC32CoreFoundationDispatch(
        LC32CoreFoundationOpDataCompareGuestBytes, slots, 3) == 1;
    const unsigned offsets[] = {0, 16383, 16384, 32772};
    for(unsigned i = 0; i < sizeof(offsets) / sizeof(*offsets); ++i) {
        right[3 + offsets[i]] ^= 1;
        passed &= LC32CoreFoundationDispatch(
            LC32CoreFoundationOpDataCompareGuestBytes, slots, 3) == 2;
        right[3 + offsets[i]] ^= 1;
    }
    slots[0] = slots[1] = slots[2] = 0;
    passed &= LC32CoreFoundationDispatch(
        LC32CoreFoundationOpDataCompareGuestBytes, slots, 3) == 1;
    slots[2] = 1;
    passed &= LC32CoreFoundationDispatch(
        LC32CoreFoundationOpDataCompareGuestBytes, slots, 3) == 0;
    slots[0] = slots[1] = UINT32_MAX;
    slots[2] = 2;
    passed &= LC32CoreFoundationDispatch(
        LC32CoreFoundationOpDataCompareGuestBytes, slots, 3) == 0;
    slots[2] = 256u * 1024u * 1024u + 1;
    passed &= LC32CoreFoundationDispatch(
        LC32CoreFoundationOpDataCompareGuestBytes, slots, 3) == 0;
    passed &= LC32CoreFoundationDispatch(
        LC32CoreFoundationOpDataCompareGuestBytes, slots, 2) == 0;
    printf("native-data-compare: %s\n", passed ? "PASS" : "FAIL");
    return passed;
}

static BOOL CheckMutableSynchronization(void) {
    const NSUInteger length = 4 * 1024 * 1024 + 3;
    NSMutableData *data = [[NSMutableData alloc] initWithLength:length];
    unsigned char *bytes = data.mutableBytes;
    BOOL passed = bytes != NULL;
    const NSUInteger offsets[] = {0, 4095, 4096, 16383, 16384, length - 1};
    for(unsigned pass = 1; pass <= 2 && passed; ++pass) {
        for(unsigned i = 0; i < sizeof(offsets) / sizeof(*offsets); ++i) {
            // Reuse the same exposed pointer after every synchronization.
            bytes[offsets[i]] = (unsigned char)(pass * 16 + i);
            unsigned char nativeByte = 0;
            [data getBytes:&nativeByte range:NSMakeRange(offsets[i], 1)];
            passed &= nativeByte == bytes[offsets[i]];
        }
    }
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for(unsigned i = 0; i < 64; ++i) passed &= data.length == length;
    clock_gettime(CLOCK_MONOTONIC, &end);
    printf("mutable-unchanged-4MiB-64-reads: %.3f seconds\n",
        end.tv_sec - start.tv_sec + (end.tv_nsec - start.tv_nsec) / 1e9);
    // No-op reads must not clear exposure and miss a subsequent raw write.
    bytes[length - 1] = 0xe7;
    unsigned char last = 0;
    [data getBytes:&last range:NSMakeRange(length - 1, 1)];
    passed &= last == 0xe7;
    [data setLength:0];
    passed &= data.length == 0 && data.mutableBytes != NULL;
    [data setLength:8193];
    bytes = data.mutableBytes;
    bytes[8192] = 0x72;
    [data getBytes:&last range:NSMakeRange(8192, 1)];
    passed &= last == 0x72;
    [data release];
    printf("mutable-repeated-raw-sync: %s\n", passed ? "PASS" : "FAIL");
    return passed;
}

@interface LC32CapacityMutableData : NSMutableData
@end

@implementation LC32CapacityMutableData
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    BOOL comparisonPassed = CheckNativeComparison();
    BOOL synchronizationPassed = CheckMutableSynchronization();

    const char constructorSource[] = "constructor";
    NSData *constructed = [NSData dataWithBytes:constructorSource
                                         length:sizeof(constructorSource) - 1];
    BOOL constructorPassed = constructed.length == 11 &&
        !memcmp(constructed.bytes, constructorSource, 11);
    printf("data-with-bytes: %s\n",
        constructorPassed ? "PASS" : "FAIL");

    NSData *data = [@"guest-data" dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = data.bytes;
    BOOL bytesPassed = data.length == 10 && bytes &&
        !memcmp(bytes, "guest-data", 10);
    printf("data-bytes: %s\n", bytesPassed ? "PASS" : "FAIL");

    char whole[10] = {0};
    [data getBytes:whole];
    BOOL wholePassed = !memcmp(whole, "guest-data", sizeof(whole));
    printf("data-get-bytes: %s\n", wholePassed ? "PASS" : "FAIL");

    char range[4] = {0};
    [data getBytes:range range:NSMakeRange(6, sizeof(range))];
    BOOL rangePassed = !memcmp(range, "data", sizeof(range));
    printf("data-get-range: %s\n", rangePassed ? "PASS" : "FAIL");

    const char mutableSource[] = "mutable-data";
    NSMutableData *mutable = [NSMutableData dataWithCapacity:16];
    [mutable appendBytes:mutableSource length:sizeof(mutableSource) - 1];
    NSData *subdata = [mutable subdataWithRange:NSMakeRange(2, 4)];
    BOOL subdataPassed = subdata.length == 4 && subdata.bytes &&
        !memcmp(subdata.bytes, "tabl", 4);
    printf("mutable-subdata-range: %s\n",
        subdataPassed ? "PASS" : "FAIL");

    /* JSONKit and other iOS-era clients use CFData's requested capacity as
     * writable storage before increasing its logical length. */
    CFMutableDataRef capacityData = CFDataCreateMutable(NULL, 513);
    BOOL mutableCapacityLengthBefore = capacityData &&
        CFDataGetLength(capacityData) == 0;
    UInt8 *capacityBytes = capacityData
        ? CFDataGetMutableBytePtr(capacityData) : NULL;
    if(capacityBytes) memset(capacityBytes, 0xa5, 513);
    BOOL mutableCapacityPassed = capacityBytes != NULL &&
        mutableCapacityLengthBefore && CFDataGetLength(capacityData) == 0;
    printf("mutable-capacity-bytes: %s\n",
        mutableCapacityPassed ? "PASS" : "FAIL");
    if(capacityData) CFRelease(capacityData);

    const UInt8 mutableCopySource[] = {0x11, 0x22, 0x33};
    CFDataRef immutableSource = CFDataCreate(NULL, mutableCopySource,
                                             sizeof(mutableCopySource));
    CFMutableDataRef capacityCopy = CFDataCreateMutableCopy(NULL, 513,
                                                            immutableSource);
    UInt8 *capacityCopyBytes = capacityCopy
        ? CFDataGetMutableBytePtr(capacityCopy) : NULL;
    BOOL mutableCopyCapacityPassed = capacityCopyBytes &&
        CFDataGetLength(capacityCopy) == sizeof(mutableCopySource) &&
        !memcmp(capacityCopyBytes, mutableCopySource,
                sizeof(mutableCopySource));
    if(capacityCopyBytes) capacityCopyBytes[512] = 0x5a;
    mutableCopyCapacityPassed = mutableCopyCapacityPassed &&
        CFDataGetLength(capacityCopy) == sizeof(mutableCopySource);
    printf("mutable-copy-capacity-bytes: %s\n",
        mutableCopyCapacityPassed ? "PASS" : "FAIL");
    if(capacityCopy) CFRelease(capacityCopy);
    if(immutableSource) CFRelease(immutableSource);

    NSMutableData *objcCapacity = [NSMutableData dataWithCapacity:515];
    UInt8 *objcCapacityBytes = objcCapacity.mutableBytes;
    if(objcCapacityBytes) memset(objcCapacityBytes, 0x3c, 515);
    BOOL objcCapacityPassed = objcCapacityBytes != NULL &&
        objcCapacity.length == 0;
    printf("mutable-objc-capacity-bytes: %s\n",
        objcCapacityPassed ? "PASS" : "FAIL");

    NSMutableData *initializedCapacity =
        [[NSMutableData alloc] initWithCapacity:517];
    UInt8 *initializedCapacityBytes = initializedCapacity.mutableBytes;
    if(initializedCapacityBytes) memset(initializedCapacityBytes, 0x69, 517);
    BOOL initializedCapacityPassed = initializedCapacityBytes != NULL &&
        initializedCapacity.length == 0;
    printf("mutable-init-capacity-bytes: %s\n",
        initializedCapacityPassed ? "PASS" : "FAIL");
    [initializedCapacity release];

    LC32CapacityMutableData *subclassCapacity =
        [LC32CapacityMutableData dataWithCapacity:521];
    BOOL subclassCapacityPassed = subclassCapacity != nil &&
        object_getClass(subclassCapacity) == [LC32CapacityMutableData class];
    printf("mutable-capacity-subclass: %s\n",
        subclassCapacityPassed ? "PASS" : "FAIL");

    BOOL boundedCapacityPassed =
        [NSMutableData dataWithCapacity:(256u * 1024u * 1024u) + 1u] == nil;
    printf("mutable-capacity-bound: %s\n",
        boundedCapacityPassed ? "PASS" : "FAIL");

    [pool drain];
    return !(comparisonPassed && synchronizationPassed && constructorPassed && bytesPassed && wholePassed && rangePassed &&
             subdataPassed && mutableCapacityPassed &&
             mutableCopyCapacityPassed && objcCapacityPassed &&
             initializedCapacityPassed && subclassCapacityPassed &&
             boundedCapacityPassed);
}
