#import <Foundation/Foundation.h>

#include <stdint.h>
#include <string.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int Check(BOOL condition, int failure) {
    return condition ? 0 : failure;
}

int main(void) {
    @autoreleasepool {
        int failed = 0;

        failed |= Check(NSProtocolFromString(@"NSObject") ==
                            @protocol(NSObject), 1);
        failed |= Check(NSProtocolFromString(@"LC32MissingProtocol") == nil,
                        2);
        failed |= Check(NSRealMemoryAvailable() != 0, 4);

        NSZone *defaultZone = NSDefaultMallocZone();
        failed |= Check(defaultZone != NULL &&
                            defaultZone == NSDefaultMallocZone(), 8);

        NSZone *zone = NSCreateZone(4096, 64, YES);
        failed |= Check(zone != NULL && zone != defaultZone, 16);
        if(!zone) return failed ? failed : 16;

        NSSetZoneName(zone, @"LiveExec32 test zone");
        failed |= Check([NSZoneName(zone)
                            isEqualToString:@"LiveExec32 test zone"], 32);

        uint8_t *bytes = NSZoneMalloc(zone, 32);
        failed |= Check(bytes != NULL && NSZoneFromPointer(bytes) == zone,
                        64);
        if(bytes) {
            memset(bytes, 0x5a, 32);
            bytes = NSZoneRealloc(zone, bytes, 64);
            failed |= Check(bytes != NULL &&
                                NSZoneFromPointer(bytes) == zone, 128);
            if(bytes) {
                for(NSUInteger index = 0; index < 32; index++) {
                    if(bytes[index] != 0x5a) {
                        failed |= 256;
                        break;
                    }
                }
            }
        }

        uint32_t *zeroes = NSZoneCalloc(zone, 8, sizeof(*zeroes));
        failed |= Check(zeroes != NULL && NSZoneFromPointer(zeroes) == zone,
                        512);
        if(zeroes) {
            for(NSUInteger index = 0; index < 8; index++) {
                if(zeroes[index] != 0) {
                    failed |= 1024;
                    break;
                }
            }
        }

        if(bytes) NSZoneFree(zone, bytes);
        if(zeroes) NSZoneFree(zone, zeroes);
        NSRecycleZone(zone);

        void *defaultBytes = NSZoneMalloc(NULL, 8);
        failed |= Check(defaultBytes != NULL &&
                            NSZoneFromPointer(defaultBytes) == defaultZone,
                        2048);
        if(defaultBytes) NSZoneFree(NULL, defaultBytes);

        return failed;
    }
}
