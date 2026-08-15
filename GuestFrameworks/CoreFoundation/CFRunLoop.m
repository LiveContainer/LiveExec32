#import <CoreFoundation/CoreFoundation+LC32.h>

#include <stdint.h>

_Static_assert(sizeof(CFTimeInterval) == sizeof(uint64_t),
    "CFTimeInterval must retain its 64-bit ARM ABI");
_Static_assert(sizeof(CFAbsoluteTime) == sizeof(uint64_t),
    "CFAbsoluteTime must retain its 64-bit ARM ABI");
_Static_assert(sizeof(CFRunLoopRunResult) == sizeof(int32_t),
    "CFRunLoopRunResult must retain its 32-bit ARM ABI");
_Static_assert(sizeof(CFOptionFlags) == sizeof(uint32_t),
    "CFOptionFlags must retain its 32-bit ARM ABI");
_Static_assert(sizeof(CFIndex) == sizeof(int32_t),
    "CFIndex must retain its 32-bit ARM ABI");
_Static_assert(sizeof(CFRunLoopTimerContext) == 5 * sizeof(uint32_t),
    "CFRunLoopTimerContext must retain its ARM32 layout");
_Static_assert(sizeof(CFRunLoopSourceContext) == 10 * sizeof(uint32_t),
    "CFRunLoopSourceContext must retain its ARM32 layout");

static uint64_t LC32CFRunLoopDoubleBits(double value) {
    union {
        double value;
        uint64_t bits;
    } representation = { .value = value };
    return representation.bits;
}

void CFRunLoopAddSource(CFRunLoopRef runLoop, CFRunLoopSourceRef source,
                        CFRunLoopMode mode) {
    if(!runLoop || !source || !mode) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopAddSource,
        LC32_CF_HOST(runLoop), LC32_CF_HOST(source), LC32_CF_HOST(mode));
}

void CFRunLoopAddTimer(CFRunLoopRef runLoop, CFRunLoopTimerRef timer,
                       CFRunLoopMode mode) {
    if(!runLoop || !timer || !mode) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopAddTimer,
        LC32_CF_HOST(runLoop), LC32_CF_HOST(timer), LC32_CF_HOST(mode));
}

CFArrayRef CFRunLoopCopyAllModes(CFRunLoopRef runLoop) {
    if(!runLoop) return NULL;
    return (CFArrayRef)LC32_CF_CALL(
        LC32CoreFoundationOpRunLoopCopyAllModes,
        LC32_CF_HOST(runLoop));
}

void CFRunLoopRemoveSource(CFRunLoopRef runLoop, CFRunLoopSourceRef source,
                           CFRunLoopMode mode) {
    if(!runLoop || !source || !mode) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopRemoveSource,
        LC32_CF_HOST(runLoop), LC32_CF_HOST(source), LC32_CF_HOST(mode));
}

void CFRunLoopRemoveTimer(CFRunLoopRef runLoop, CFRunLoopTimerRef timer,
                          CFRunLoopMode mode) {
    if(!runLoop || !timer || !mode) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopRemoveTimer,
        LC32_CF_HOST(runLoop), LC32_CF_HOST(timer), LC32_CF_HOST(mode));
}

void CFRunLoopRun(void) {
    LC32_CF_CALL0(LC32CoreFoundationOpRunLoopRun);
}

CFRunLoopRunResult CFRunLoopRunInMode(CFRunLoopMode mode,
                                      CFTimeInterval seconds,
                                      Boolean returnAfterSourceHandled) {
    if(!mode) return kCFRunLoopRunFinished;
    return (CFRunLoopRunResult)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpRunLoopRunInMode,
        LC32_CF_HOST(mode), LC32CFRunLoopDoubleBits(seconds),
        LC32_CF_U32(returnAfterSourceHandled != false));
}

void CFRunLoopSourceInvalidate(CFRunLoopSourceRef source) {
    if(!source) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopSourceInvalidate,
        LC32_CF_HOST(source));
}

CFRunLoopSourceRef CFRunLoopSourceCreate(
        CFAllocatorRef allocator, CFIndex order,
        CFRunLoopSourceContext *context) {
    /* Host allocators and guest callback addresses cannot be passed directly
     * to native CoreFoundation. */
    (void)allocator;
    if(!context) return NULL;

    /* Retain is arbitrary guest code: snapshot the caller-owned structure
     * before invoking it. YouTube uses all-zero and perform-only contexts;
     * reject the callback shapes we cannot faithfully marshal. */
    const CFRunLoopSourceContext snapshot = *context;
    if(snapshot.version != 0 || snapshot.equal || snapshot.hash ||
       snapshot.schedule || snapshot.cancel) {
        return NULL;
    }
    const void *retainedInfo = snapshot.retain
        ? snapshot.retain(snapshot.info)
        : snapshot.info;

    /* The host consumes this retained context even if native creation fails. */
    return (CFRunLoopSourceRef)LC32_CF_CALL(
        LC32CoreFoundationOpRunLoopSourceCreate,
        LC32_CF_U32(order), LC32_CF_U32((uintptr_t)snapshot.perform),
        LC32_CF_U32((uintptr_t)retainedInfo),
        LC32_CF_U32((uintptr_t)snapshot.release),
        LC32_CF_U32((uintptr_t)snapshot.copyDescription));
}

void CFRunLoopSourceSignal(CFRunLoopSourceRef source) {
    if(!source) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopSourceSignal,
        LC32_CF_HOST(source));
}

void CFRunLoopStop(CFRunLoopRef runLoop) {
    if(!runLoop) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopStop,
        LC32_CF_HOST(runLoop));
}

void CFRunLoopTimerInvalidate(CFRunLoopTimerRef timer) {
    if(!timer) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopTimerInvalidate,
        LC32_CF_HOST(timer));
}

CFRunLoopTimerRef CFRunLoopTimerCreate(
        CFAllocatorRef allocator, CFAbsoluteTime fireDate,
        CFTimeInterval interval, CFOptionFlags flags, CFIndex order,
        CFRunLoopTimerCallBack callout, CFRunLoopTimerContext *context) {
    /* Host allocators cannot be used with guest context storage. */
    (void)allocator;
    if(!callout) return NULL;

    /* The retain callback is arbitrary guest code and may mutate or free the
     * caller's context storage, so snapshot every field before invoking it. */
    CFRunLoopTimerContext snapshot = {};
    if(context) {
        snapshot = *context;
        if(snapshot.version != 0) return NULL;
    }
    const void *retainedInfo = snapshot.retain
        ? snapshot.retain(snapshot.info)
        : snapshot.info;

    /* This call transfers the retained context to the host dispatcher even
     * when native CFRunLoopTimerCreate rejects the timer. */
    return (CFRunLoopTimerRef)LC32_CF_CALL(
        LC32CoreFoundationOpRunLoopTimerCreate,
        LC32CFRunLoopDoubleBits(fireDate),
        LC32CFRunLoopDoubleBits(interval), LC32_CF_U32(flags),
        LC32_CF_U32(order), LC32_CF_U32((uintptr_t)callout),
        LC32_CF_U32((uintptr_t)retainedInfo),
        LC32_CF_U32((uintptr_t)snapshot.release),
        LC32_CF_U32((uintptr_t)snapshot.copyDescription));
}

void CFRunLoopTimerSetNextFireDate(CFRunLoopTimerRef timer,
                                   CFAbsoluteTime fireDate) {
    if(!timer) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopTimerSetNextFireDate,
        LC32_CF_HOST(timer), LC32CFRunLoopDoubleBits(fireDate));
}

void CFRunLoopWakeUp(CFRunLoopRef runLoop) {
    if(!runLoop) return;
    LC32_CF_CALL(LC32CoreFoundationOpRunLoopWakeUp,
        LC32_CF_HOST(runLoop));
}
