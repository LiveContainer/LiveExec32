#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <LC32/LC32.h>

#include <stdint.h>
#include <string.h>

extern UInt8 *LC32GetMutableDataGuestBytes(NSMutableData *data);
extern BOOL LC32ReserveMutableDataGuestCapacity(NSMutableData *data,
                                                uint32_t capacity);
extern uint64_t LC32SynchronizeMutableDataGuestBytes(NSMutableData *data);

enum {
    LC32MaximumMutableDataCapacity = 256u * 1024u * 1024u,
};

@implementation NSMutableData (LC32MutableBytes)

+ (instancetype)dataWithCapacity:(NSUInteger)capacity {
    /* Use alloc/init so an inherited call on a concrete guest subclass keeps
     * that subclass instead of unconditionally manufacturing a Foundation
     * class-cluster object. */
    return [[[self alloc] initWithCapacity:capacity] autorelease];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    /* Guest-defined NSMutableData subclasses own their storage and primitive
     * methods.  As with the plain class-cluster initializer, do not attach a
     * native class-cluster peer to an inherited initializer on such an object. */
    if(object_getClass(self) != objc_getClass("NSMutableData")) return self;
    if(capacity > LC32MaximumMutableDataCapacity) {
        return LC32DisposeFailedInit(self);
    }

    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    const uint64_t hostResult = LC32InvokeHostSelector(
        [self host_self], selector, (uint64_t)capacity, (uint64_t)0);
    NSMutableData *result = LC32AdoptHostInitializerResult(self, hostResult);
    if(result && !LC32ReserveMutableDataGuestCapacity(
            result, (uint32_t)capacity)) {
        [result release];
        return nil;
    }
    return result;
}

- (uint64_t)host_self {
    return LC32SynchronizeMutableDataGuestBytes(self);
}

- (void *)mutableBytes {
    return LC32GetMutableDataGuestBytes(self);
}

- (void)appendData:(NSData *)other {
    if(!other) return;
    CFDataAppendBytes((CFMutableDataRef)self, other.bytes,
                      (CFIndex)other.length);
}

- (void)appendBytes:(const void *)bytes length:(NSUInteger)length {
    if(length > UINT32_MAX) return;
    CFDataAppendBytes((CFMutableDataRef)self, bytes, (CFIndex)length);
}

- (void)increaseLengthBy:(NSUInteger)extraLength {
    if(extraLength > UINT32_MAX) return;
    CFDataIncreaseLength((CFMutableDataRef)self, (CFIndex)extraLength);
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes {
    if(range.location > UINT32_MAX || range.length > UINT32_MAX) return;
    CFDataReplaceBytes((CFMutableDataRef)self,
        CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
        bytes, (CFIndex)range.length);
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes
                     length:(NSUInteger)length {
    if(range.location > UINT32_MAX || range.length > UINT32_MAX ||
       length > UINT32_MAX) return;
    CFDataReplaceBytes((CFMutableDataRef)self,
        CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
        bytes, (CFIndex)length);
}

- (void)resetBytesInRange:(NSRange)range {
    const NSUInteger dataLength = self.length;
    if(range.location > UINT32_MAX || range.length > UINT32_MAX ||
       range.location > dataLength ||
       range.length > dataLength - range.location) return;
    UInt8 *bytes = LC32GetMutableDataGuestBytes(self);
    if(bytes) memset(bytes + range.location, 0, range.length);
}

- (void)setData:(NSData *)other {
    if(!other) return;
    CFDataRef snapshot = CFDataCreateCopy(kCFAllocatorDefault,
                                          (CFDataRef)other);
    if(!snapshot) return;
    const CFIndex length = CFDataGetLength(snapshot);
    const UInt8 *bytes = CFDataGetBytePtr(snapshot);
    CFDataSetLength((CFMutableDataRef)self, 0);
    if(length) CFDataAppendBytes((CFMutableDataRef)self, bytes, length);
    CFRelease(snapshot);
}

- (void)setLength:(NSUInteger)length {
    if(length > UINT32_MAX) return;
    CFDataSetLength((CFMutableDataRef)self, (CFIndex)length);
}

@end
