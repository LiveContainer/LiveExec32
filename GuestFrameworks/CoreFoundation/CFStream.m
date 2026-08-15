#import <CoreFoundation/CoreFoundation+LC32.h>

#include <limits.h>
#include <stdint.h>

enum {
    LC32CFStreamMaximumTransferLength = 64 * 1024 * 1024,
};

Boolean CFReadStreamOpen(CFReadStreamRef stream) {
    return stream && LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamOpen, LC32_CF_HOST(stream));
}

void CFReadStreamClose(CFReadStreamRef stream) {
    if(stream) LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamClose, LC32_CF_HOST(stream));
}

CFStreamStatus CFReadStreamGetStatus(CFReadStreamRef stream) {
    return stream ? (CFStreamStatus)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamGetStatus,
        LC32_CF_HOST(stream)) : kCFStreamStatusError;
}

Boolean CFReadStreamHasBytesAvailable(CFReadStreamRef stream) {
    return stream && LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamHasBytesAvailable,
        LC32_CF_HOST(stream));
}

CFIndex CFReadStreamRead(CFReadStreamRef stream, UInt8 *buffer,
                         CFIndex bufferLength) {
    if(!stream || bufferLength < 0 ||
       bufferLength > LC32CFStreamMaximumTransferLength ||
       (bufferLength && !buffer)) {
        return -1;
    }
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamRead,
        LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(bufferLength));
}

CFErrorRef CFReadStreamCopyError(CFReadStreamRef stream) {
    return stream ? (CFErrorRef)LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamCopyError,
        LC32_CF_HOST(stream)) : NULL;
}

CFTypeRef CFReadStreamCopyProperty(CFReadStreamRef stream,
                                   CFStreamPropertyKey propertyName) {
    return stream && propertyName ? (CFTypeRef)LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamCopyProperty,
        LC32_CF_HOST(stream), LC32_CF_HOST(propertyName)) : NULL;
}

Boolean CFReadStreamSetProperty(CFReadStreamRef stream,
                                CFStreamPropertyKey propertyName,
                                CFTypeRef propertyValue) {
    return stream && propertyName && propertyValue && LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamSetProperty,
        LC32_CF_HOST(stream), LC32_CF_HOST(propertyName),
        LC32_CF_HOST(propertyValue));
}

void CFReadStreamScheduleWithRunLoop(CFReadStreamRef stream,
                                     CFRunLoopRef runLoop,
                                     CFRunLoopMode runLoopMode) {
    if(stream && runLoop && runLoopMode) LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamScheduleWithRunLoop,
        LC32_CF_HOST(stream), LC32_CF_HOST(runLoop),
        LC32_CF_HOST(runLoopMode));
}

void CFReadStreamUnscheduleFromRunLoop(CFReadStreamRef stream,
                                       CFRunLoopRef runLoop,
                                       CFRunLoopMode runLoopMode) {
    if(stream && runLoop && runLoopMode) LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamUnscheduleFromRunLoop,
        LC32_CF_HOST(stream), LC32_CF_HOST(runLoop),
        LC32_CF_HOST(runLoopMode));
}

CFStreamError CFReadStreamGetError(CFReadStreamRef stream) {
    CFStreamError error = {0, 0};
    if(stream) LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamGetError,
        LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)&error));
    return error;
}

Boolean CFReadStreamSetClient(CFReadStreamRef stream,
                              CFOptionFlags streamEvents,
                              CFReadStreamClientCallBack clientCB,
                              CFStreamClientContext *clientContext) {
    if(!stream || (streamEvents & ~(CFOptionFlags)UINT32_MAX)) return false;

    /* CFStream is unusual here: either a NULL callback or a NULL context
     * removes the current client. */
    if(!clientCB || !clientContext) {
        return LC32_CF_CALL(
            LC32CoreFoundationOpReadStreamSetClient,
            LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)stream),
            LC32_CF_U32(streamEvents), 0, 0, 0, 0);
    }

    /* Copy every field before invoking retain: the callback may mutate or
     * release storage containing the caller-owned context structure. */
    const CFStreamClientContext context = *clientContext;
    if(context.version != 0) return false;

    const void *retainedInfo = context.retain
        ? context.retain(context.info)
        : context.info;
    const Boolean installed = LC32_CF_CALL(
        LC32CoreFoundationOpReadStreamSetClient,
        LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)stream),
        LC32_CF_U32(streamEvents), LC32_CF_U32((uintptr_t)clientCB),
        LC32_CF_U32((uintptr_t)retainedInfo),
        LC32_CF_U32((uintptr_t)context.release),
        LC32_CF_U32((uintptr_t)context.copyDescription));
    /* The host dispatcher consumes this retained context even when native
     * CFReadStreamSetClient rejects the registration. */
    return installed;
}

Boolean CFWriteStreamOpen(CFWriteStreamRef stream) {
    return stream && LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamOpen, LC32_CF_HOST(stream));
}

void CFWriteStreamClose(CFWriteStreamRef stream) {
    if(stream) LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamClose, LC32_CF_HOST(stream));
}

CFStreamStatus CFWriteStreamGetStatus(CFWriteStreamRef stream) {
    return stream ? (CFStreamStatus)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamGetStatus,
        LC32_CF_HOST(stream)) : kCFStreamStatusError;
}

Boolean CFWriteStreamCanAcceptBytes(CFWriteStreamRef stream) {
    return stream && LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamCanAcceptBytes,
        LC32_CF_HOST(stream));
}

CFIndex CFWriteStreamWrite(CFWriteStreamRef stream, const UInt8 *buffer,
                           CFIndex bufferLength) {
    if(!stream || bufferLength < 0 ||
       bufferLength > LC32CFStreamMaximumTransferLength ||
       (bufferLength && !buffer)) {
        return -1;
    }
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamWrite,
        LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(bufferLength));
}

CFErrorRef CFWriteStreamCopyError(CFWriteStreamRef stream) {
    return stream ? (CFErrorRef)LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamCopyError,
        LC32_CF_HOST(stream)) : NULL;
}

CFTypeRef CFWriteStreamCopyProperty(CFWriteStreamRef stream,
                                    CFStreamPropertyKey propertyName) {
    return stream && propertyName ? (CFTypeRef)LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamCopyProperty,
        LC32_CF_HOST(stream), LC32_CF_HOST(propertyName)) : NULL;
}

Boolean CFWriteStreamSetProperty(CFWriteStreamRef stream,
                                 CFStreamPropertyKey propertyName,
                                 CFTypeRef propertyValue) {
    return stream && propertyName && propertyValue && LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamSetProperty,
        LC32_CF_HOST(stream), LC32_CF_HOST(propertyName),
        LC32_CF_HOST(propertyValue));
}

void CFWriteStreamScheduleWithRunLoop(CFWriteStreamRef stream,
                                      CFRunLoopRef runLoop,
                                      CFRunLoopMode runLoopMode) {
    if(stream && runLoop && runLoopMode) LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamScheduleWithRunLoop,
        LC32_CF_HOST(stream), LC32_CF_HOST(runLoop),
        LC32_CF_HOST(runLoopMode));
}

void CFWriteStreamUnscheduleFromRunLoop(CFWriteStreamRef stream,
                                        CFRunLoopRef runLoop,
                                        CFRunLoopMode runLoopMode) {
    if(stream && runLoop && runLoopMode) LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamUnscheduleFromRunLoop,
        LC32_CF_HOST(stream), LC32_CF_HOST(runLoop),
        LC32_CF_HOST(runLoopMode));
}

CFStreamError CFWriteStreamGetError(CFWriteStreamRef stream) {
    CFStreamError error = {0, 0};
    if(stream) LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamGetError,
        LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)&error));
    return error;
}

Boolean CFWriteStreamSetClient(CFWriteStreamRef stream,
                               CFOptionFlags streamEvents,
                               CFWriteStreamClientCallBack clientCB,
                               CFStreamClientContext *clientContext) {
    if(!stream || (streamEvents & ~(CFOptionFlags)UINT32_MAX)) return false;

    /* CFStream is unusual here: either a NULL callback or a NULL context
     * removes the current client. */
    if(!clientCB || !clientContext) {
        return LC32_CF_CALL(
            LC32CoreFoundationOpWriteStreamSetClient,
            LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)stream),
            LC32_CF_U32(streamEvents), 0, 0, 0, 0);
    }

    /* Snapshot caller-owned storage before retain invokes arbitrary code. */
    const CFStreamClientContext context = *clientContext;
    if(context.version != 0) return false;

    const void *retainedInfo = context.retain
        ? context.retain(context.info)
        : context.info;
    return LC32_CF_CALL(
        LC32CoreFoundationOpWriteStreamSetClient,
        LC32_CF_HOST(stream), LC32_CF_U32((uintptr_t)stream),
        LC32_CF_U32(streamEvents), LC32_CF_U32((uintptr_t)clientCB),
        LC32_CF_U32((uintptr_t)retainedInfo),
        LC32_CF_U32((uintptr_t)context.release),
        LC32_CF_U32((uintptr_t)context.copyDescription));
}

void CFStreamCreatePairWithSocket(CFAllocatorRef allocator,
                                  CFSocketNativeHandle socket,
                                  CFReadStreamRef *readStream,
                                  CFWriteStreamRef *writeStream) {
    (void)allocator;
    if(readStream) *readStream = NULL;
    if(writeStream) *writeStream = NULL;
    if(!readStream && !writeStream) return;

    LC32_CF_CALL(
        LC32CoreFoundationOpStreamCreatePairWithSocket,
        LC32_CF_U32((int32_t)socket),
        LC32_CF_U32((uintptr_t)readStream),
        LC32_CF_U32((uintptr_t)writeStream));
}
