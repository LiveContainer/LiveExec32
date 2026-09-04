#import <CoreFoundation/CoreFoundation+LC32.h>

#include <limits.h>
#include <stdint.h>

_Static_assert(sizeof(SInt32) == sizeof(uint32_t),
    "SInt32 must retain its ARM32 ABI");
_Static_assert(sizeof(CFSocketNativeHandle) == sizeof(int32_t),
    "CFSocketNativeHandle must retain its ARM32 ABI");
_Static_assert(sizeof(CFSocketError) == sizeof(int32_t),
    "CFSocketError must retain its ARM32 ABI");
_Static_assert(sizeof(CFIndex) == sizeof(int32_t),
    "CFIndex must retain its ARM32 ABI");
_Static_assert(sizeof(CFOptionFlags) == sizeof(uint32_t),
    "CFOptionFlags must retain its ARM32 ABI");
_Static_assert(sizeof(CFSocketContext) == 5 * sizeof(uint32_t),
    "CFSocketContext must retain its ARM32 layout");

static uint64_t LC32CFSocketDoubleBits(double value) {
    union {
        double value;
        uint64_t bits;
    } representation = { .value = value };
    return representation.bits;
}

static Boolean LC32CFSocketSupportsCallbackTypes(
        CFOptionFlags callbackTypes) {
    /* kCFSocketDataCallBack has the numeric value 3 rather than a unique
     * bit, so validate the supported combinations explicitly. */
    return callbackTypes == kCFSocketNoCallBack ||
           callbackTypes == kCFSocketDataCallBack ||
           callbackTypes == kCFSocketConnectCallBack ||
           callbackTypes ==
               (kCFSocketDataCallBack | kCFSocketConnectCallBack);
}

CFSocketRef CFSocketCreate(CFAllocatorRef allocator,
                           SInt32 protocolFamily,
                           SInt32 socketType,
                           SInt32 protocol,
                           CFOptionFlags callbackTypes,
                           CFSocketCallBack callout,
                           const CFSocketContext *context) {
    /* A native allocator cannot own guest context storage or callbacks. */
    (void)allocator;
    if(!LC32CFSocketSupportsCallbackTypes(callbackTypes) ||
       (callbackTypes != kCFSocketNoCallBack && !callout)) {
        return NULL;
    }

    /* Retain is arbitrary guest code and may mutate/free the caller's
     * context. Snapshot every field before invoking it. */
    CFSocketContext snapshot = {};
    if(context) {
        snapshot = *context;
        if(snapshot.version != 0) return NULL;
    }
    const void *retainedInfo = snapshot.retain
        ? snapshot.retain(snapshot.info)
        : snapshot.info;

    /* The host consumes this retained context even when native creation
     * fails, matching the Create ownership transfer used by run-loop shims. */
    return (CFSocketRef)LC32_CF_CALL(
        LC32CoreFoundationOpSocketCreate,
        LC32_CF_U32(protocolFamily), LC32_CF_U32(socketType),
        LC32_CF_U32(protocol), LC32_CF_U32(callbackTypes),
        LC32_CF_U32((uintptr_t)callout),
        LC32_CF_U32((uintptr_t)retainedInfo),
        LC32_CF_U32((uintptr_t)snapshot.release),
        LC32_CF_U32((uintptr_t)snapshot.copyDescription));
}

CFSocketError CFSocketConnectToAddress(CFSocketRef socket,
                                       CFDataRef address,
                                       CFTimeInterval timeout) {
    if(!socket || !address) return kCFSocketError;
    return (CFSocketError)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpSocketConnectToAddress,
        LC32_CF_HOST(socket), LC32_CF_HOST(address),
        LC32CFSocketDoubleBits(timeout));
}

CFSocketError CFSocketSetAddress(CFSocketRef socket, CFDataRef address) {
    if(!socket || !address) return kCFSocketError;
    return (CFSocketError)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpSocketSetAddress,
        LC32_CF_HOST(socket), LC32_CF_HOST(address));
}

Boolean CFSocketIsValid(CFSocketRef socket) {
    return socket && LC32_CF_CALL(
        LC32CoreFoundationOpSocketIsValid, LC32_CF_HOST(socket));
}

CFDataRef CFSocketCopyAddress(CFSocketRef socket) {
    return socket ? (CFDataRef)LC32_CF_CALL(
        LC32CoreFoundationOpSocketCopyAddress,
        LC32_CF_HOST(socket)) : NULL;
}

CFDataRef CFSocketCopyPeerAddress(CFSocketRef socket) {
    return socket ? (CFDataRef)LC32_CF_CALL(
        LC32CoreFoundationOpSocketCopyPeerAddress,
        LC32_CF_HOST(socket)) : NULL;
}

CFRunLoopSourceRef CFSocketCreateRunLoopSource(CFAllocatorRef allocator,
                                               CFSocketRef socket,
                                               CFIndex order) {
    (void)allocator;
    if(!socket) return NULL;
    return (CFRunLoopSourceRef)LC32_CF_CALL(
        LC32CoreFoundationOpSocketCreateRunLoopSource,
        LC32_CF_HOST(socket), LC32_CF_U32(order));
}

CFSocketNativeHandle CFSocketGetNative(CFSocketRef socket) {
    if(!socket) return (CFSocketNativeHandle)-1;
    return (CFSocketNativeHandle)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpSocketGetNative, LC32_CF_HOST(socket));
}

void CFSocketInvalidate(CFSocketRef socket) {
    if(!socket) return;
    LC32_CF_CALL(LC32CoreFoundationOpSocketInvalidate,
        LC32_CF_HOST(socket));
}

CFOptionFlags CFSocketGetSocketFlags(CFSocketRef socket) {
    return socket ? (CFOptionFlags)LC32_CF_CALL(
        LC32CoreFoundationOpSocketGetSocketFlags,
        LC32_CF_HOST(socket)) : 0;
}

void CFSocketSetSocketFlags(CFSocketRef socket, CFOptionFlags flags) {
    if(!socket) return;
    LC32_CF_CALL(LC32CoreFoundationOpSocketSetSocketFlags,
        LC32_CF_HOST(socket), LC32_CF_U32(flags));
}

void CFSocketDisableCallBacks(CFSocketRef socket,
                              CFOptionFlags callbackTypes) {
    if(!socket) return;
    LC32_CF_CALL(LC32CoreFoundationOpSocketDisableCallbacks,
        LC32_CF_HOST(socket), LC32_CF_U32(callbackTypes));
}

void CFSocketEnableCallBacks(CFSocketRef socket,
                             CFOptionFlags callbackTypes) {
    if(!socket) return;
    LC32_CF_CALL(LC32CoreFoundationOpSocketEnableCallbacks,
        LC32_CF_HOST(socket), LC32_CF_U32(callbackTypes));
}

CFSocketError CFSocketSendData(CFSocketRef socket, CFDataRef address,
                               CFDataRef data, CFTimeInterval timeout) {
    if(!socket || !data) return kCFSocketError;
    return (CFSocketError)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpSocketSendData,
        LC32_CF_HOST(socket), LC32_CF_HOST(address), LC32_CF_HOST(data),
        LC32CFSocketDoubleBits(timeout));
}

void CFSocketSetDefaultNameRegistryPortNumber(UInt16 port) {
    LC32_CF_CALL(LC32CoreFoundationOpSocketSetDefaultNameRegistryPortNumber,
        LC32_CF_U32(port));
}

UInt16 CFSocketGetDefaultNameRegistryPortNumber(void) {
    return (UInt16)LC32_CF_CALL0(
        LC32CoreFoundationOpSocketGetDefaultNameRegistryPortNumber);
}
