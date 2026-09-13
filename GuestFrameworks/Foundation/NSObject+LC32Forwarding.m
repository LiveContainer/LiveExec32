#import <Foundation/Foundation+LC32.h>
#import <objc/message.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void LC32GuestForwardMessage(void);
extern void LC32GuestForwardMessageStret(void);

static void LC32ForwardingFailure(id receiver, SEL selector,
        const char *reason) __attribute__((noreturn));
static void LC32ForwardingFailure(id receiver, SEL selector,
        const char *reason) {
    fprintf(stderr, "LC32: cannot forward guest %c[%s %s]: %s\n",
        object_isClass(receiver) ? '+' : '-',
        receiver ? class_getName(object_getClass(receiver)) : "(nil)",
        selector ? sel_getName(selector) : "(null)", reason);
    abort();
}

/* Called with the original argument registers saved directly before the
 * caller's stack arguments. A fast-forward target requires no signature or
 * cross-ABI conversion: the assembly tail call restores every argument. */
id LC32GuestForwardingTarget(const uint32_t *words, uint32_t stret) {
    id receiver = (id)(uintptr_t)words[stret ? 1 : 0];
    SEL selector = (SEL)(uintptr_t)words[stret ? 2 : 1];
    if(!receiver || !selector) return nil;

    const SEL forwardingSelector = @selector(forwardingTargetForSelector:);
    if(!class_getInstanceMethod(object_getClass(receiver), forwardingSelector))
        return nil;
    id target = ((id (*)(id, SEL, SEL))objc_msgSend)(
        receiver, forwardingSelector, selector);
    return target != receiver ? target : nil;
}

/* These C-string-returning NSMethodSignature methods are not generated guest
 * shims. Copy their native strings while the signature is alive instead of
 * exposing a host pointer or retaining a transient shared guest buffer. */
static BOOL LC32ForwardingCopyType(NSMethodSignature *signature,
        NSUInteger index, BOOL returnType, char *buffer, size_t capacity) {
    static uint64_t returnSelector __attribute__((aligned(8)));
    static uint64_t argumentSelector __attribute__((aligned(8)));
    uint64_t selector = LC32CachedHostSelector(
        returnType ? &returnSelector : &argumentSelector,
        returnType ? @selector(methodReturnType) : @selector(getArgumentTypeAtIndex:),
        NO);
    const uint64_t string = LC32InvokeHostSelector(
        signature.host_self, selector, (uint64_t)index, (uint64_t)0);
    if(!string) return NO;
    const uint32_t required = LC32CopyHostCString(string, buffer, capacity);
    return required && required <= capacity;
}

static unsigned LC32ForwardingTypeWords(const char *type, BOOL result) {
    while(*type && strchr("rnNoORVA", *type)) ++type;
    switch(*type) {
        case 'v': return result ? 0 : UINT32_MAX;
        case 'q': case 'Q': case 'd': return 2;
        case 'B': case 'c': case 'C': case 's': case 'S':
        case 'i': case 'I': case 'l': case 'L': case 'f':
        case '#': case ':': return 1;
        case '@': return type[1] == '?' ? UINT32_MAX : 1;
        default: return UINT32_MAX;
    }
}

uint64_t LC32GuestForwardInvocation(const uint32_t *words, uint32_t stret) {
    id receiver = (id)(uintptr_t)words[stret ? 1 : 0];
    SEL selector = (SEL)(uintptr_t)words[stret ? 2 : 1];
    if(stret) {
        LC32ForwardingFailure(receiver, selector,
            "aggregate return requires an unsupported full-forwarding ABI");
    }
    if(!receiver || !selector) {
        LC32ForwardingFailure(receiver, selector, "invalid receiver or selector");
    }
    const SEL signatureSelector = @selector(methodSignatureForSelector:);
    if(!class_getInstanceMethod(object_getClass(receiver), signatureSelector)) {
        LC32ForwardingFailure(receiver, selector, "no method-signature provider");
    }
    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
    if(!signature) {
        const SEL unrecognizedSelector = @selector(doesNotRecognizeSelector:);
        if(class_getInstanceMethod(object_getClass(receiver), unrecognizedSelector))
            [receiver doesNotRecognizeSelector:selector];
        LC32ForwardingFailure(receiver, selector, "no method signature");
    }

    const NSUInteger argumentCount = signature.numberOfArguments;
    if(argumentCount < 2 || argumentCount > 34) {
        LC32ForwardingFailure(receiver, selector, "unsupported argument count");
    }
    char type[256];
    if(!LC32ForwardingCopyType(signature, 0, YES, type, sizeof(type))) {
        LC32ForwardingFailure(receiver, selector, "invalid return encoding");
    }
    const unsigned resultWords = LC32ForwardingTypeWords(type, YES);
    if(resultWords == UINT32_MAX) {
        LC32ForwardingFailure(receiver, selector, "unsupported return encoding");
    }
    const char *unqualifiedResult = type;
    while(*unqualifiedResult && strchr("rnNoORVA", *unqualifiedResult))
        ++unqualifiedResult;
    const char resultKind = *unqualifiedResult;
    unsigned widths[32];
    for(NSUInteger index = 2; index < argumentCount; ++index) {
        if(!LC32ForwardingCopyType(signature, index, NO, type, sizeof(type))) {
            LC32ForwardingFailure(receiver, selector, "invalid argument encoding");
        }
        widths[index - 2] = LC32ForwardingTypeWords(type, NO);
        if(widths[index - 2] == UINT32_MAX) {
            LC32ForwardingFailure(receiver, selector, "unsupported argument encoding");
        }
    }
    if(!class_getInstanceMethod(object_getClass(receiver), @selector(forwardInvocation:))) {
        LC32ForwardingFailure(receiver, selector, "no invocation forwarder");
    }

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = receiver;
    invocation.selector = selector;
    size_t word = 2;
    for(NSUInteger index = 2; index < argumentCount; ++index) {
        [invocation setArgument:(void *)&words[word] atIndex:index];
        /* Apple's ARM32 Objective-C ABI packs scalar words at four-byte
         * alignment, including q/d split across r3 and the first stack word. */
        word += widths[index - 2];
    }
    [receiver forwardInvocation:invocation];
    uint64_t result = 0;
    if(resultWords) [invocation getReturnValue:&result];
    /* NSInvocation copies the value's storage width, but ARM32 returns
     * signed narrow integers already sign-extended through all of r0. */
    if(resultKind == 'c') return (uint32_t)(int32_t)(int8_t)result;
    if(resultKind == 's') return (uint32_t)(int32_t)(int16_t)result;
    return result;
}

__attribute__((constructor)) static void LC32InstallGuestForwarding(void) {
    /* libobjc supplies only its fatal default handler. Foundation owns the
     * forwarding protocol, including NSProxy's independent root hierarchy. */
    objc_setForwardHandler((void *)&LC32GuestForwardMessage,
        (void *)&LC32GuestForwardMessageStret);
}
