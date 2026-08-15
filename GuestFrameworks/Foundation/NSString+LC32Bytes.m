#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <LC32/LC32.h>

#include <limits.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>

#import "LC32FoundationBridge.h"

static pthread_once_t LC32StringGetBytesOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32StringGetBytesHostFunction;

static void LC32ResolveStringGetBytesHostFunction(void) {
    LC32StringGetBytesHostFunction =
        LC32Dlsym("LC32_Foundation_StringGetBytes", YES);
}

@implementation NSString (LC32Bytes)

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    /*
     * The generated selector bridge cannot pass an ARM32 output pointer to
     * native Foundation. CoreFoundation already stages this exact operation
     * and copies the UTF-16 result back into guest memory.
     */
    if((range.length && !buffer) || range.location > INT32_MAX ||
       range.length > INT32_MAX ||
       range.location > (NSUInteger)INT32_MAX - range.length) {
        CRSetCrashLogMessage("NSString getCharacters:range: invalid range");
        return;
    }
    CFStringGetCharacters(
        (CFStringRef)self,
        CFRangeMake((CFIndex)range.location, (CFIndex)range.length), buffer);
}

- (void)getCharacters:(unichar *)buffer {
    [self getCharacters:buffer range:NSMakeRange(0, self.length)];
}

- (BOOL)getBytes:(void *)buffer
        maxLength:(NSUInteger)maximumLength
       usedLength:(NSUInteger *)usedLength
         encoding:(NSStringEncoding)encoding
          options:(NSStringEncodingConversionOptions)options
            range:(NSRange)range
   remainingRange:(NSRangePointer)remainingRange {
    pthread_once(&LC32StringGetBytesOnce,
                 LC32ResolveStringGetBytesHostFunction);
    if(!LC32StringGetBytesHostFunction ||
       range.location > UINT32_MAX || range.length > UINT32_MAX ||
       range.location > UINT32_MAX - range.length ||
       maximumLength > UINT32_MAX) {
        if(usedLength) *usedLength = 0;
        if(remainingRange) *remainingRange = range;
        return NO;
    }

    const uint64_t hostString = self.host_self;
    const LC32FoundationStringGetBytesRequest request = {
        .version = LC32FoundationStringGetBytesABIVersion,
        .byteSize = sizeof(request),
        .hostStringLow = (uint32_t)hostString,
        .hostStringHigh = (uint32_t)(hostString >> 32),
        .guestBuffer = (uint32_t)(uintptr_t)buffer,
        .maximumLength = (uint32_t)maximumLength,
        .guestUsedLength = (uint32_t)(uintptr_t)usedLength,
        .encoding = (uint32_t)encoding,
        .options = (uint32_t)options,
        .rangeLocation = (uint32_t)range.location,
        .rangeLength = (uint32_t)range.length,
        .guestRemainingRange = (uint32_t)(uintptr_t)remainingRange,
    };
    return (BOOL)LC32InvokeHostCRet32(
        LC32StringGetBytesHostFunction, (uint32_t)(uintptr_t)&request,
        0, 0);
}

- (BOOL)getBytes:(char *)buffer
        maxLength:(NSUInteger)maximumLength
      filledLength:(NSUInteger *)filledLength
         encoding:(NSStringEncoding)encoding
allowLossyConversion:(BOOL)allowLossyConversion
            range:(NSRange)range
   remainingRange:(NSRangePointer)remainingRange {
    const NSStringEncodingConversionOptions options = allowLossyConversion
        ? NSStringEncodingConversionAllowLossy : 0;
    return [self getBytes:buffer
                maxLength:maximumLength
               usedLength:filledLength
                 encoding:encoding
                  options:options
                    range:range
           remainingRange:remainingRange];
}

- (instancetype)initWithBytes:(const void *)bytes
                        length:(NSUInteger)length
                      encoding:(NSStringEncoding)encoding {
    /*
     * Native Foundation cannot dereference an ARM32 address.  NSData's
     * manual constructor copies the bytes through the guest-memory bridge;
     * the generated initWithData:encoding: shim can then initialize this
     * exact class-cluster placeholder and adopt its native result safely.
     */
    NSData *data = [NSData dataWithBytes:bytes length:length];
    if(!data) return LC32DisposeFailedInit(self);
    return [self initWithData:data encoding:encoding];
}

- (instancetype)initWithBytesNoCopy:(void *)bytes
                              length:(NSUInteger)length
                            encoding:(NSStringEncoding)encoding
                        freeWhenDone:(BOOL)freeWhenDone {
    /*
     * A native NSString cannot retain an ARM32 allocation.  Copy the bytes
     * synchronously through the existing safe initializer, then honor the
     * ownership transfer in the guest address space.
     */
    id result = [self initWithBytes:bytes length:length encoding:encoding];
    if(freeWhenDone) free(bytes);
    return result;
}

+ (instancetype)stringWithBytes:(const void *)bytes
                         length:(NSUInteger)length
                       encoding:(NSStringEncoding)encoding {
    return [[[self alloc] initWithBytes:bytes
                                 length:length
                               encoding:encoding] autorelease];
}

@end
