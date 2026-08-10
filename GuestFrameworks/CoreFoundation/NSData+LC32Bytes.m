#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

#include <stdint.h>

@implementation NSData (LC32Bytes)

- (const void *)bytes {
    NSUInteger length = self.length;
    if(!length || length > UINT32_MAX) return NULL;

    void *bytes = LC32GetAssociatedGuestBuffer(self, (uint32_t)length);
    if(!bytes) return NULL;
    return LC32CopyHostDataBytes(self.host_self, bytes, (uint32_t)length, 0)
            == (uint32_t)length
        ? bytes : NULL;
}

- (void)getBytes:(void *)buffer {
    [self getBytes:buffer length:self.length];
}

- (void)getBytes:(void *)buffer length:(NSUInteger)length {
    if(length > UINT32_MAX || LC32CopyHostDataBytes(
            self.host_self, buffer, (uint32_t)length, 0) != length) {
        CRSetCrashLogMessage(
            "NSData getBytes:length: range exceeds data length");
    }
}

- (void)getBytes:(void *)buffer range:(NSRange)range {
    if(range.location > UINT32_MAX || range.length > UINT32_MAX ||
            LC32CopyHostDataBytes(self.host_self, buffer,
                (uint32_t)range.length, (uint32_t)range.location) !=
                    range.length) {
        CRSetCrashLogMessage(
            "NSData getBytes:range: range exceeds data length");
    }
}

@end
