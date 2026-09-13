#include "guest_dispatch.h"
#include "bridge.h"
#include "dynarmic_internal.h"

#include <CoreFoundation/CoreFoundation.h>
#include <atomic>
#include <mutex>
#include <new>
#include <pthread.h>
#include <stdio.h>

namespace {

struct MainQueueSource {
    std::atomic<unsigned> references{1};
    std::atomic<bool> enabled{true};
    const mach_port_t port;
    const u32 callback;
    std::mutex sourcesMutex;
    CFRunLoopSourceRef portSource = nullptr;
    CFRunLoopSourceRef continuationSource = nullptr;
    // Accessed only by the physical main thread, including nested run loops.
    bool draining = false;
    bool pending = false;

    MainQueueSource(mach_port_t port, u32 callback)
        : port(port), callback(callback) {}
};

std::mutex mainQueueSourceMutex;
MainQueueSource *mainQueueSource = nullptr;

const void *RetainSourceContext(const void *info) {
    auto *state = static_cast<MainQueueSource *>(const_cast<void *>(info));
    state->references.fetch_add(1, std::memory_order_relaxed);
    return info;
}

void ReleaseSourceContext(const void *info) {
    auto *state = static_cast<MainQueueSource *>(const_cast<void *>(info));
    if(state->references.fetch_sub(1, std::memory_order_acq_rel) == 1)
        delete state;
}

bool GuestIsStopping() {
    return nativeShutdownRequested.load(std::memory_order_acquire) ||
        guestProcessExitRequested.load(std::memory_order_acquire);
}

void SignalContinuation(MainQueueSource *state) {
    CFRunLoopSourceRef source = nullptr;
    {
        std::lock_guard<std::mutex> lock(state->sourcesMutex);
        if(state->enabled.load(std::memory_order_acquire) &&
           state->continuationSource) {
            source = (CFRunLoopSourceRef)CFRetain(state->continuationSource);
        }
    }
    if(source) {
        CFRunLoopSourceSignal(source);
        CFRunLoopWakeUp(CFRunLoopGetMain());
        CFRelease(source);
    }
}

void DrainMainQueue(void *info) {
    auto *state = static_cast<MainQueueSource *>(info);
    RetainSourceContext(state);
    struct ContextScope {
        MainQueueSource *state;
        ~ContextScope() { ReleaseSourceContext(state); }
    } contextScope{state};
    if(!state->enabled.load(std::memory_order_acquire) || GuestIsStopping())
        return;
    if(!pthread_main_np() || !Dynarmic_guest_thread_is_registered() ||
       CurrentGuestThreadId() != 1)
        return;

    state->pending = true;
    if(state->draining) return;
    state->draining = true;
    state->pending = false;
    struct DrainScope {
        MainQueueSource *state;
        ~DrainScope() {
            state->draining = false;
            // A nested run loop may have consumed another Mach wakeup. Defer
            // that drain until the outer dispatch callback has unwound.
            if(state->pending && !GuestIsStopping()) SignalContinuation(state);
        }
    } scope{state};

    // The 32-bit libdispatch SPI does not inspect its message argument. Do
    // not pass the native Mach message's address into the guest address space.
    u32 unusedMessage = 0;
    LC32InvokeGuestC(state->callback, false, 1, &unusedMessage);
}

mach_port_t MainQueuePort(void *info) {
    return static_cast<MainQueueSource *>(info)->port;
}

void *MainQueuePortReady(void *, CFIndex, CFAllocatorRef, void *info) {
    DrainMainQueue(info);
    return nullptr; // A dispatch wakeup is one-way, with no Mach reply.
}

void InvalidateSources(MainQueueSource *state) {
    state->enabled.store(false, std::memory_order_release);
    CFRunLoopSourceRef portSource;
    CFRunLoopSourceRef continuationSource;
    {
        std::lock_guard<std::mutex> lock(state->sourcesMutex);
        portSource = state->portSource;
        continuationSource = state->continuationSource;
        state->portSource = nullptr;
        state->continuationSource = nullptr;
    }
    if(portSource) {
        CFRunLoopSourceInvalidate(portSource);
        CFRelease(portSource);
    }
    if(continuationSource) {
        CFRunLoopSourceInvalidate(continuationSource);
        CFRelease(continuationSource);
    }
}

} // namespace

void LC32InstallGuestMainQueueSource(void) {
    if(!pthread_main_np() || !Dynarmic_guest_thread_is_registered() ||
       CurrentGuestThreadId() != 1 || GuestIsStopping())
        return;
    {
        std::lock_guard<std::mutex> lock(mainQueueSourceMutex);
        if(mainQueueSource) return;
    }

    // libSystem (including guest libdispatch) is initialized before LC32's
    // constructor publishes the guest dlsym and callback entry points.
    const u32 getPort = guest_dlsym("_dispatch_get_main_queue_port_4CF");
    const u32 callback = guest_dlsym("_dispatch_main_queue_callback_4CF");
    if(!getPort || !callback) {
        fprintf(stderr, "LC32: guest libdispatch main-run-loop SPI missing\n");
        return;
    }
    const mach_port_t port = (mach_port_t)LC32InvokeGuestC(getPort, false, 0, nullptr);
    mach_port_type_t portType = 0;
    if(!MACH_PORT_VALID(port) ||
       mach_port_type(mach_task_self(), port, &portType) != KERN_SUCCESS ||
       !(portType & MACH_PORT_TYPE_RECEIVE)) {
        fprintf(stderr, "LC32: invalid guest main-queue receive port 0x%x\n", port);
        return;
    }
    auto *state = new(std::nothrow) MainQueueSource(port, callback);
    if(!state) {
        fprintf(stderr, "LC32: could not allocate guest main-queue source\n");
        return;
    }
    CFRunLoopSourceContext1 portContext = {};
    portContext.version = 1;
    portContext.info = state;
    portContext.retain = RetainSourceContext;
    portContext.release = ReleaseSourceContext;
    portContext.getPort = MainQueuePort;
    portContext.perform = MainQueuePortReady;
    state->portSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0,
        reinterpret_cast<CFRunLoopSourceContext *>(&portContext));

    CFRunLoopSourceContext continuationContext = {};
    continuationContext.info = state;
    continuationContext.retain = RetainSourceContext;
    continuationContext.release = ReleaseSourceContext;
    continuationContext.perform = DrainMainQueue;
    state->continuationSource = CFRunLoopSourceCreate(
        kCFAllocatorDefault, 0, &continuationContext);
    if(!state->portSource || !state->continuationSource) {
        fprintf(stderr, "LC32: could not create guest main-queue run-loop sources\n");
        InvalidateSources(state);
        ReleaseSourceContext(state);
        return;
    }

    {
        std::lock_guard<std::mutex> lock(mainQueueSourceMutex);
        if(!mainQueueSource && !GuestIsStopping()) {
            mainQueueSource = state;
            CFRunLoopAddSource(CFRunLoopGetMain(), state->portSource,
                               kCFRunLoopCommonModes);
            CFRunLoopAddSource(CFRunLoopGetMain(), state->continuationSource,
                               kCFRunLoopCommonModes);
            // Service work queued before registration even if libdispatch's
            // initial queue transition preceded its run-loop-port setup.
            CFRunLoopSourceSignal(state->continuationSource);
            CFRunLoopWakeUp(CFRunLoopGetMain());
            return;
        }
    }
    InvalidateSources(state);
    ReleaseSourceContext(state);
}

void LC32RemoveGuestMainQueueSource(void) {
    MainQueueSource *state;
    {
        std::lock_guard<std::mutex> lock(mainQueueSourceMutex);
        state = mainQueueSource;
        mainQueueSource = nullptr;
        if(state) state->enabled.store(false, std::memory_order_release);
    }
    if(state) {
        InvalidateSources(state);
        ReleaseSourceContext(state);
    }
}
