#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <stdio.h>
#include <string.h>

@interface LC32CapacityMutableData : NSMutableData
@end

@implementation LC32CapacityMutableData
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

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
    return !(constructorPassed && bytesPassed && wholePassed && rangePassed &&
             subdataPassed && mutableCapacityPassed &&
             mutableCopyCapacityPassed && objcCapacityPassed &&
             initializedCapacityPassed && subclassCapacityPassed &&
             boundedCapacityPassed);
}
