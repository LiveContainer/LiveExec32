#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>

#import "LC32CoreFoundationBridge.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum {
    LC32MaximumDataGuestBufferBytes = 256u * 1024u * 1024u,
};

extern uint32_t LC32CoreFoundationDispatch(
    LC32CoreFoundationOpcode opcode, const uint64_t *slots,
    uint32_t slotCount);

@interface LC32DataGuestBuffer : LC32GuestBuffer {
@public
    UInt8 *_baseline;
    uint32_t _length;
    BOOL _valid;
    BOOL _mutableBytesExposed;
    BOOL _synchronizing;
}
@end

@implementation LC32DataGuestBuffer
- (void)dealloc {
    free(_baseline);
    [super dealloc];
}
@end

static const void *kLC32DataGuestBuffer = &kLC32DataGuestBuffer;

static LC32DataGuestBuffer *LC32GetDataGuestBuffer(NSData *data,
                                                    BOOL create) {
    LC32DataGuestBuffer *buffer =
        objc_getAssociatedObject(data, kLC32DataGuestBuffer);
    if(!buffer && create) {
        buffer = [LC32DataGuestBuffer new];
        objc_setAssociatedObject(data, kLC32DataGuestBuffer, buffer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [buffer release];
    }
    return buffer;
}

static BOOL LC32GrowDataGuestBuffer(LC32DataGuestBuffer *buffer,
                                    uint32_t length) {
    if(length > LC32MaximumDataGuestBufferBytes) return NO;
    /* Keep a stable, dereferenceable pointer for zero-length mutable data. */
    const uint32_t required = length ? length : 1;
    if(buffer->_capacity >= required) return YES;
    UInt8 *grown = realloc(buffer->_bytes, required);
    if(!grown) return NO;
    buffer->_bytes = grown;
    UInt8 *grownBaseline = realloc(buffer->_baseline, required);
    if(!grownBaseline) return NO;
    buffer->_baseline = grownBaseline;
    buffer->_capacity = required;
    return YES;
}

BOOL LC32ReserveMutableDataGuestCapacity(NSMutableData *data,
                                         uint32_t capacity) {
    if(!data || capacity > LC32MaximumDataGuestBufferBytes) return NO;

    /* CFDataCreateMutable's capacity is observable through the pointer
     * returned by CFDataGetMutableBytePtr even while logical length is zero.
     * Materialize the current contents first, then retain at least that
     * requested allocation capacity in guest memory. */
    (void)[data bytes];
    objc_sync_enter(data);
    LC32DataGuestBuffer *buffer = LC32GetDataGuestBuffer(data, NO);
    const BOOL reserved = buffer && buffer->_valid &&
        LC32GrowDataGuestBuffer(buffer, capacity);
    objc_sync_exit(data);
    return reserved;
}

void LC32InvalidateDataGuestBuffer(NSData *data) {
    if(!data) return;
    objc_sync_enter(data);
    LC32DataGuestBuffer *buffer = LC32GetDataGuestBuffer(data, NO);
    if(buffer) {
        buffer->_valid = NO;
        buffer->_mutableBytesExposed = NO;
        buffer->_length = 0;
    }
    objc_sync_exit(data);
}

UInt8 *LC32GetMutableDataGuestBytes(NSMutableData *data) {
    if(!data) return NULL;
    (void)[data bytes];
    objc_sync_enter(data);
    LC32DataGuestBuffer *buffer = LC32GetDataGuestBuffer(data, NO);
    UInt8 *bytes = NULL;
    if(buffer && buffer->_valid) {
        /*
         * Raw writes cannot be observed, so this remains set for the pointer's
         * lifetime. Every later guest-to-host conversion re-copies the current
         * bytes; clearing it after one sync would miss writes made afterward.
         */
        buffer->_mutableBytesExposed = YES;
        bytes = buffer->_bytes;
    }
    objc_sync_exit(data);
    return bytes;
}

uint64_t LC32SynchronizeMutableDataGuestBytes(NSMutableData *data) {
    const uint64_t rawHostSelf = [data LC32_rawHostSelf];
    objc_sync_enter(data);
    LC32DataGuestBuffer *buffer = LC32GetDataGuestBuffer(data, NO);
    if(buffer && buffer->_valid && buffer->_mutableBytesExposed &&
       !buffer->_synchronizing && buffer->_length != 0 &&
       memcmp(buffer->_bytes, buffer->_baseline, buffer->_length) != 0) {
        buffer->_synchronizing = YES;
        const uint64_t slots[] = {
            rawHostSelf,
            0,
            buffer->_length,
            (uint32_t)(uintptr_t)buffer->_bytes,
            buffer->_length,
        };
        const uint32_t synchronized = LC32CoreFoundationDispatch(
            LC32CoreFoundationOpDataReplaceBytes, slots,
            sizeof(slots) / sizeof(slots[0]));
        if(synchronized) {
            memcpy(buffer->_baseline, buffer->_bytes, buffer->_length);
        } else {
            CRSetCrashLogMessage(
                "LC32: could not synchronize mutable CFData bytes");
        }
        buffer->_synchronizing = NO;
    }
    objc_sync_exit(data);
    return rawHostSelf;
}

@implementation NSData (LC32Bytes)

+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length {
    if(length > LC32MaximumDataGuestBufferBytes || (length && !bytes))
        return nil;
    return [(id)CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)length)
        autorelease];
}

+ (instancetype)dataWithBytesNoCopy:(void *)bytes
                              length:(NSUInteger)length {
    return [self dataWithBytesNoCopy:bytes length:length freeWhenDone:YES];
}

+ (instancetype)dataWithBytesNoCopy:(void *)bytes
                              length:(NSUInteger)length
                        freeWhenDone:(BOOL)freeWhenDone {
    id data = [self dataWithBytes:bytes length:length];
    if(freeWhenDone) free(bytes);
    return data;
}

- (const void *)bytes {
    objc_sync_enter(self);
    LC32DataGuestBuffer *existing = LC32GetDataGuestBuffer(self, NO);
    const void *bytes = existing && existing->_valid ? existing->_bytes : NULL;
    objc_sync_exit(self);
    if(bytes) return bytes;

    const NSUInteger length = self.length;
    if(length > LC32MaximumDataGuestBufferBytes) return NULL;

    objc_sync_enter(self);
    LC32DataGuestBuffer *buffer = LC32GetDataGuestBuffer(self, YES);
    if(buffer && LC32GrowDataGuestBuffer(buffer, (uint32_t)length)) {
        const BOOL copied = !length || LC32CopyHostDataBytes(
            self.host_self, buffer->_bytes, (uint32_t)length, 0) ==
                (uint32_t)length;
        if(copied) {
            if(length) memcpy(buffer->_baseline, buffer->_bytes, length);
            buffer->_length = (uint32_t)length;
            buffer->_valid = YES;
            bytes = buffer->_bytes;
        }
    }
    objc_sync_exit(self);
    return bytes;
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

- (instancetype)initWithBytes:(const void *)bytes
                        length:(NSUInteger)length {
    /*
     * Native Foundation cannot dereference an ARM32 address.  NSData's
     * manual class constructor copies the bytes through the guest-memory
     * bridge; the generated initWithData: shim can then initialize this
     * exact class-cluster placeholder and adopt its native result safely.
     */
    NSData *data = [NSData dataWithBytes:bytes length:length];
    if(!data) return LC32DisposeFailedInit(self);
    return [self initWithData:data];
}

- (instancetype)initWithBytesNoCopy:(void *)bytes
                              length:(NSUInteger)length {
    return [self initWithBytesNoCopy:bytes length:length
                         freeWhenDone:YES];
}

- (instancetype)initWithBytesNoCopy:(void *)bytes
                              length:(NSUInteger)length
                        freeWhenDone:(BOOL)freeWhenDone {
    /*
     * A native NSData cannot retain an ARM32 allocation.  Copy the bytes
     * synchronously through the existing safe initializer, then honor the
     * ownership transfer in the guest address space.
     */
    id result = [self initWithBytes:bytes length:length];
    if(freeWhenDone) free(bytes);
    return result;
}

- (NSData *)subdataWithRange:(NSRange)range {
    /*
     * The generated shim cannot yet marshal aggregate arguments.  ARM64
     * passes the two NSUInteger members of NSRange in x2/x3, while the LC32
     * selector trampoline consumes one widened stack slot per host register.
     * Flatten the ARM32 range explicitly so NSMutableData inherits the same
     * implementation without exposing a guest pointer to native Foundation.
     */
    static uint64_t hostSelector __attribute__((aligned(8)));
    const uint64_t selector = LC32CachedHostSelector(
        &hostSelector, _cmd, NO);
    id result = LC32InvokeHostObjectSelector(
        self.host_self, selector,
        (uint64_t)range.location, (uint64_t)range.length, (uint64_t)0);
    return LC32ReturnBorrowedGuestObject(result);
}

@end
