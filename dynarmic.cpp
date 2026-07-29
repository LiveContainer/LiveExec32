#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <exception>
#include <iostream>
#include <memory>
#include <mutex>
#include <vector>

#include <assert.h>
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdlib.h>
#include <unistd.h>

#include <mach/thread_act.h>
#include <mach/mig_errors.h>
#include <mach/vm_map.h>
#include <mach/vm_page_size.h>
#include <mach/vm_region.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>

#include <dirent.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/attr.h>
#include <sys/errno.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/xattr.h>
#include <libgen.h>
#include "mach_private.h"
#include "codesign.h"
#include "dynarmic.h"
#include "32bit.h"


#define IGNORE_BAD_MEM_ACCESS 0
#define TRACE_RW 0
#define TRACE_BRANCH 0
#define TRACE_SVC 0
#define TRACE_THREADS 0
#define TRACE_WORKQUEUE 0
//#define TRACE_ALLOC 0
//#define fprintf(...)
//#define printf(...)

#if TRACE_WORKQUEUE
#define WORKQUEUE_TRACE(...) fprintf(stderr, __VA_ARGS__)
#else
#define WORKQUEUE_TRACE(...) do {} while (0)
#endif

#if TRACE_THREADS
#define THREAD_TRACE(...) fprintf(stderr, __VA_ARGS__)
#else
#define THREAD_TRACE(...) do {} while (0)
#endif

#define CS_OPS_STATUS 0
#define CS_ENFORCEMENT 0x00001000

#define msgh_request_port    msgh_remote_port
#define msgh_reply_port        msgh_local_port

static std::atomic<int> guestStopSignal{SIGTRAP};
static std::atomic<int> pendingGuestFatalSignal{0};
static std::atomic<bool> reemitPendingGuestStop{false};
static std::atomic<bool> guestDebuggerEnabled{false};
static std::atomic<bool> debuggerInterruptRequested{false};
static std::recursive_mutex guestVmMutex;

static bool NativeGuestThreadsRequested() {
    static const bool requested = [] {
        const char *value = getenv("NATIVE_GUEST_THREADS");
        return value != nullptr && value[0] != '\0' &&
            strcmp(value, "0") != 0;
    }();
    return requested;
}

static bool NativeGuestThreadsEnabled() {
    return NativeGuestThreadsRequested() &&
        !guestDebuggerEnabled.load(std::memory_order_relaxed);
}

static Dynarmic::A32::UserCallbacks *CurrentUserCallbacks();

enum class DebuggerMachCallPhase : uint8_t {
    Idle,
    Arming,
    InCall,
    Completing,
};
static std::atomic<DebuggerMachCallPhase> debuggerMachCallPhase{
    DebuggerMachCallPhase::Idle};
static std::atomic<mach_port_t> debuggerMachCallThread{MACH_PORT_NULL};

static bool PumpGuestWorkqueue();
static bool HandleGuestWorkqueueTransition();
static bool GuestWorkqueueTransitionPending();
static bool HandleGuestThreadTransition();
static bool GuestThreadTransitionPending();
static bool HandleGuestContextTransition();
static bool GuestContextTransitionPending();
static bool GuestThreadCanYieldBeforeBlocking();
static bool GuestThreadYieldBeforeBlocking();
static void GuestThreadRequestRotation();
static bool NativeGuestThreadIsCurrent();
static bool GuestWorkqueueActiveForCurrentThread();
static void InvalidateAllGuestJits(u32 address, size_t size);
static void HaltAllGuestJits(Dynarmic::HaltReason reason);
static u32 GuestBsdthreadCreate(
    u32 function, u32 argument, u32 stack, u32 pthread, u32 flags);
static u32 GuestBsdthreadTerminate(
    u32 freeAddress, u32 freeSize, mach_port_t threadPort,
    mach_port_t joinSemaphore);
static u64 GuestCurrentThreadSelfId();
static mach_port_t GuestCurrentSyntheticThreadPort();
static int GuestThreadSigmask(int how, u32 guestSet, u32 guestOldSet);
static u32 GuestPsynchMutexWait(u32 mutex, u32 generation);
static u32 GuestPsynchMutexDrop(u32 mutex);
static u32 GuestPsynchConditionWait(u32 condition, u32 mutex);
static u32 GuestPsynchConditionSignal(
    u32 condition, mach_port_t targetThread, bool broadcast);
static u32 GuestPsynchRwWait(u32 rwlock);
static u32 GuestPsynchRwUnlock(u32 rwlock);
static u32 GuestUlockWait(
    u32 operation, u32 address, u64 value, u32 timeout);
static u32 GuestUlockWake(
    u32 operation, u32 address, u64 wakeValue);
static bool guestSingleStepping;

struct DebuggerSoftwareBreakpoint {
    u32 address;
    size_t kind;
    std::array<uint8_t, sizeof(uint32_t)> original;
    std::array<uint8_t, sizeof(uint32_t)> trap;
};
static std::vector<DebuggerSoftwareBreakpoint> debuggerSoftwareBreakpoints;

static void SetGuestStopSignal(int signal, bool pending) {
    if (signal <= 0 || signal >= NSIG) {
        signal = SIGABRT;
    }
    guestStopSignal.store(signal, std::memory_order_relaxed);
    if (!pending) {
        pendingGuestFatalSignal.store(0, std::memory_order_relaxed);
        reemitPendingGuestStop.store(false, std::memory_order_relaxed);
    } else {
        pendingGuestFatalSignal.store(signal, std::memory_order_relaxed);
    }
}

static bool ConsumePendingGuestStop() {
    if (!reemitPendingGuestStop.exchange(false, std::memory_order_relaxed)) {
        return false;
    }

    const int signal = pendingGuestFatalSignal.load(std::memory_order_relaxed);
    if (signal <= 0) {
        return false;
    }
    guestStopSignal.store(signal, std::memory_order_relaxed);
    return true;
}

static void UpdateGuestStopSignalForHalt(Dynarmic::HaltReason reason) {
    if (Dynarmic::Has(reason, LC32HaltReasonInterrupt)) {
        debuggerInterruptRequested.store(false, std::memory_order_release);
        SetGuestStopSignal(SIGINT, false);
    } else if (Dynarmic::Has(reason, Dynarmic::HaltReason::MemoryAbort)) {
        SetGuestStopSignal(SIGSEGV, true);
    } else if (!Dynarmic::Has(reason, LC32HaltReasonTrap)) {
        // A normal single-step or any non-fault emulator stop must not retain
        // the signal from an earlier fatal stop.
        SetGuestStopSignal(SIGTRAP, false);
    }
}

static int FindGuestMapping(u32 loadAddress) {
    for (int i = 0; i < guestMappingLen; ++i) {
        if (guestMappings[i].start == loadAddress) {
            return i;
        }
    }
    return -1;
}

static void RemoveGuestMapping(u32 loadAddress) {
    const int index = FindGuestMapping(loadAddress);
    if (index < 0) {
        return;
    }

    free(const_cast<char *>(guestMappings[index].name));
    for (int i = index; i + 1 < guestMappingLen; ++i) {
        guestMappings[i] = guestMappings[i + 1];
    }
    guestMappings[--guestMappingLen] = {};
    ++guestMappingGeneration;
}

struct symbolicated_call {
    u32 address;
    u32 symbolOffset;
    const char *symbolName;
    const char *imageName;
};

extern "C"
int return_with_carry(int result, bool carry) {
    threadHandle.cpsr->setCarry(carry);
    return carry ? errno : result;
}

extern "C"
int return_with_carry_direct(int result, bool carry) {
    threadHandle.cpsr->setCarry(carry);
    return result;
}

extern "C"
int syscallRetCarry(long syscall, ...);
__asm__(" \
_syscallRetCarry: \n \
    mov x16, x0 \n \
    ldp x0, x1, [sp] \n \
    ldp x2, x3, [sp, #0x10] \n \
    ldp x4, x5, [sp, #0x20] \n \
    ldr x6, [sp, #0x30] \n \
    svc #0x80 \n \
    mov x1, #0 \n \
    b.lo LcarryClear\n \
    mov x1, #1 \n \
LcarryClear: \n \
    b _return_with_carry_direct \n \
");

// guest syscalls
int guest_csops(pid_t pid, unsigned int ops, u32 guest_useraddr, size_t usersize) {
    char *host_useraddr = (char *)malloc(usersize);
    int result = syscallRetCarry(SYS_csops, pid, ops, host_useraddr, usersize, 0,0,0);
    if(ops == CS_OPS_STATUS) {
        // remove code signature enforcement
        *(uint32_t *)host_useraddr &= ~CS_ENFORCEMENT;
    }
    Dynarmic_mem_1write(guest_useraddr, usersize, host_useraddr);
    free(host_useraddr);
    return result;
}

int guest_csops_audittoken(pid_t pid, unsigned int ops,
        u32 guest_useraddr, size_t usersize, u32 guest_audit_token) {
    audit_token_t audit_token = {};
    if (Dynarmic_mem_1read(
            guest_audit_token, sizeof(audit_token),
            reinterpret_cast<char *>(&audit_token)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    std::vector<char> host_useraddr(usersize);
    int result = syscallRetCarry(
        SYS_csops_audittoken, pid, ops, host_useraddr.data(), usersize,
        &audit_token, 0, 0);
    if (usersize != 0 &&
            Dynarmic_mem_1write(
                guest_useraddr, usersize, host_useraddr.data()) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
}

int guest_getrlimit(int resource, u32 guest_rlp) {
    struct rlimit host_rlp;
    int result = syscallRetCarry(SYS_getrlimit, resource, &host_rlp, 0,0,0,0,0);
    Dynarmic_mem_1write(guest_rlp, sizeof(host_rlp), (char *)&host_rlp);
    return result;
}


u32 guest_mmap(u32 guest_addr, size_t len, int prot, int flags, int fildes, off_t offset) {
    len = ALIGN_DYN_SIZE(len);
    u32 result = Dynarmic_mmap(guest_addr, len, prot, flags, fildes, offset);
    if(result == -1) {
        threadHandle.cpsr->setCarry(true);
        return errno;
    }
    return result;
}

int guest___sysctl(u32 guest_name, u_int namelen, u32 guest_oldp, u32 guest_oldlenp, u32 guest_newp, size_t newlen) {
    // TODO: fake stuff like CPU architecture and KERN_USRSTACK32
    int host_name[0x10];
    assert(namelen < sizeof(host_name));
    Dynarmic_mem_1read(guest_name, sizeof(int) * namelen, (char *)host_name);

    // Guess nothing is larger than 1kb
    size_t host_oldlenp;
    char host_oldp[0x400];
    char host_newp[0x400];
    assert(newlen <= sizeof(host_newp));
    if(guest_newp) {
        Dynarmic_mem_1read(guest_newp, newlen, host_newp);
    }

    int result = syscallRetCarry(SYS_sysctl,
        host_name, namelen,
        guest_oldp ? &host_oldp : NULL,
        guest_oldlenp ? &host_oldlenp : 0,
        guest_newp ? (int *)host_newp : NULL, newlen,
        0
    );

    if(guest_oldp) {
        Dynarmic_mem_1write(guest_oldp, host_oldlenp, host_oldp);
        CurrentUserCallbacks()->MemoryWrite32(
            guest_oldlenp, host_oldlenp);
    }
    return result;
}

int guest___sysctlbyname(u32 guest_name, u_int namelen, u32 guest_oldp, u32 guest_oldlenp, u32 guest_newp, size_t newlen) {
    // TODO: fake stuff like CPU architecture and KERN_USRSTACK32
    DynarmicHostString host_name(guest_name);

    // Guess nothing is larger than 1kb
    size_t host_oldlenp;
    char host_oldp[0x400];
    char host_newp[0x400];
    assert(newlen <= sizeof(host_newp));
    if(guest_newp) {
        Dynarmic_mem_1read(guest_newp, newlen, host_newp);
    }

    int result = syscallRetCarry(SYS_sysctlbyname,
        host_name.hostPtr, namelen,
        guest_oldp ? &host_oldp : NULL,
        guest_oldlenp ? &host_oldlenp : 0,
        guest_newp ? (int *)host_newp : NULL, newlen,
        0
    );

    if(guest_oldp) {
        Dynarmic_mem_1write(guest_oldp, host_oldlenp, host_oldp);
        CurrentUserCallbacks()->MemoryWrite32(
            guest_oldlenp, host_oldlenp);
    }
    return result;
}

int guest_getattrlist(u32 guest_path, u32 guest_attrList, u32 guest_attrBuf, size_t attrBufSize, unsigned long options) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    struct attrlist host_attrList;
    Dynarmic_mem_1read(guest_attrList, sizeof(struct attrlist), (char *)&host_attrList);
    char *host_attrBuf = (char *)malloc(attrBufSize);
    int result = syscallRetCarry(SYS_getattrlist, host_path, &host_attrList, host_attrBuf, attrBufSize, options, 0,0);
    Dynarmic_mem_1write(guest_attrBuf, attrBufSize, host_attrBuf);
    free(host_attrBuf);
    return result;
}

int guest_shm_open(u32 guest_name, int oflag, int mode) {
    DynarmicHostString host_name(guest_name);
    printf("LC32: shm_open %s\n", host_name.hostPtr);
    return syscallRetCarry(SYS_shm_open, host_name.hostPtr, oflag, mode);
}

int     guest_pthread_getugid_np(u32 uid, u32 gid) {
    uid_t host_uid, host_gid;
    int result = pthread_getugid_np(&host_uid, &host_gid);
    CurrentUserCallbacks()->MemoryWrite32(uid, host_uid);
    CurrentUserCallbacks()->MemoryWrite32(gid, host_gid);
    return result;
}

#define MACH_MSG_UNION(function, name) \
union MachMessage_##function { \
    __Request__##function##_t In; \
    __Reply__##function##_t Out; \
} *name = (MachMessage_##function *)host_header

static void *ResolveHostIOKitSymbol(const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol != nullptr) {
        return symbol;
    }
    static void *const handle = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        RTLD_LAZY | RTLD_LOCAL);
    return handle != nullptr ? dlsym(handle, name) : nullptr;
}

static mach_msg_return_t debugger_aware_mach_msg(
        mach_msg_header_t *msg,
        mach_msg_option_t option,
        mach_msg_size_t send_size,
        mach_msg_size_t rcv_size,
        mach_port_t rcv_name,
        mach_msg_timeout_t timeout,
        mach_port_t notify) {
    if ((option & (MACH_SEND_MSG | MACH_RCV_MSG)) == 0 ||
            !guestDebuggerEnabled.load(std::memory_order_relaxed)) {
        return mach_msg(msg, option, send_size, rcv_size, rcv_name,
            timeout, notify);
    }

    /*
     * The gdbstub socket reader runs on another host thread.  A Dynarmic halt
     * request cannot wake this thread while it is blocked in the kernel.
     * Publish the host thread and make only the host operation interruptible;
     * the guest retains its original options and libsystem retry policy.
     */
    debuggerMachCallThread.store(
        pthread_mach_thread_np(pthread_self()), std::memory_order_relaxed);
    debuggerMachCallPhase.store(
        DebuggerMachCallPhase::Arming, std::memory_order_release);

    const auto finishCall = [] {
        debuggerMachCallPhase.store(
            DebuggerMachCallPhase::Completing, std::memory_order_release);
        debuggerMachCallThread.store(
            MACH_PORT_NULL, std::memory_order_release);
        debuggerMachCallPhase.store(
            DebuggerMachCallPhase::Idle, std::memory_order_release);
    };
    const auto interruptedBeforeCall = [option] {
        return (option & MACH_SEND_MSG) != 0
            ? MACH_SEND_INTERRUPTED
            : MACH_RCV_INTERRUPTED;
    };

    if (debuggerInterruptRequested.load(std::memory_order_acquire)) {
        finishCall();
        return interruptedBeforeCall();
    }

    debuggerMachCallPhase.store(
        DebuggerMachCallPhase::InCall, std::memory_order_release);
    if (debuggerInterruptRequested.load(std::memory_order_acquire)) {
        finishCall();
        return interruptedBeforeCall();
    }

    mach_msg_option_t hostOption = option;
    if ((hostOption & MACH_SEND_MSG) != 0) {
        hostOption |= MACH_SEND_INTERRUPT;
    }
    if ((hostOption & MACH_RCV_MSG) != 0) {
        hostOption |= MACH_RCV_INTERRUPT;
    }

    const mach_msg_return_t result =
        mach_msg(msg, hostOption, send_size, rcv_size, rcv_name, timeout,
            notify);
    finishCall();
    return result;
}

// FIXME: cannot call mach_msg(2)_trap directly
mach_msg_return_t
guest_mach_msg_trap(u32 guest_msg,
         mach_msg_option_t option,
         mach_msg_size_t send_size,
         mach_msg_size_t rcv_size,
         mach_port_t rcv_name,
         mach_msg_timeout_t timeout,
         mach_port_t notify) {
    mach_msg_return_t result = MACH_MSG_SUCCESS;

    const mach_msg_size_t buffer_size = MAX(send_size, rcv_size);
    char *host_msg = (char *)calloc(1, MAX(buffer_size,
        (mach_msg_size_t)sizeof(mach_msg_header_t)));
    if (send_size != 0) {
        Dynarmic_mem_1read(guest_msg, send_size, host_msg);
    }

    mach_msg_header_t *host_header = (mach_msg_header_t *)host_msg;

    /*
     * A receive-only trap has no request header or message ID to dispatch.
     * Give the cooperative guest workqueue a chance to drain any libdispatch
     * sends and in-process Mach listeners first. A real kernel would run
     * those workers concurrently while this thread waits for its reply.
     */
    if (send_size == 0 && (option & MACH_RCV_MSG) != 0) {
        if (PumpGuestWorkqueue()) {
            free(host_msg);
            return MACH_RCV_INTERRUPTED;
        }
        /*
         * Probe the receive right before yielding.  Otherwise two guest
         * pthreads blocked in mach_msg can keep returning MACH_RCV_INTERRUPTED
         * to one another without either one ever consuming a queued message.
         * A zero-timeout probe preserves cooperative scheduling while still
         * allowing an asynchronously delivered reply to make progress.
         */
        if (GuestThreadCanYieldBeforeBlocking()) {
            const mach_msg_return_t probeResult = debugger_aware_mach_msg(
                host_header, option | MACH_RCV_TIMEOUT, 0, rcv_size,
                rcv_name, 0, notify);
            if (probeResult != MACH_RCV_TIMED_OUT) {
                if (rcv_size != 0 &&
                        probeResult != MACH_RCV_INTERRUPTED &&
                        probeResult != MACH_SEND_INTERRUPTED) {
                    Dynarmic_mem_1write(
                        guest_msg, rcv_size, host_msg);
                }
                free(host_msg);
                return probeResult;
            }
            if ((option & MACH_RCV_TIMEOUT) != 0 && timeout == 0) {
                free(host_msg);
                return MACH_RCV_TIMED_OUT;
            }
        }
        /*
         * A kernel pthread could run while this thread sleeps. LC32's
         * explicit guest pthreads share one JIT, so make an empty receive
         * interruptible at the guest ABI and let libsystem retry it after a
         * cooperative context switch.
         */
        if (GuestThreadYieldBeforeBlocking()) {
            free(host_msg);
            return MACH_RCV_INTERRUPTED;
        }
        result = debugger_aware_mach_msg(host_header, option, 0, rcv_size,
            rcv_name, timeout, notify);
        if (rcv_size != 0 && result != MACH_RCV_INTERRUPTED &&
                result != MACH_SEND_INTERRUPTED) {
            Dynarmic_mem_1write(guest_msg, rcv_size, host_msg);
        }
        free(host_msg);
        return result;
    }

    /*
     * A failed service lookup leaves a null destination. The kernel rejects
     * that send before MIG examines the request ID; doing the same here lets
     * callers take their ordinary unavailable-service path. For a combined
     * send/receive operation, a send failure also suppresses the receive.
     */
    if ((option & MACH_SEND_MSG) != 0 &&
            send_size >= sizeof(mach_msg_header_t) &&
            !MACH_PORT_VALID(host_header->msgh_remote_port)) {
        free(host_msg);
        return MACH_SEND_INVALID_DEST;
    }

    printf("LC32: mach_msg_trap id %d\n", host_header->msgh_id);

    // pre-process reply header
    const mach_msg_bits_t request_bits = host_header->msgh_bits;
    host_header->msgh_bits &= 0xff;
    switch(host_header->msgh_id) {
        case 0: {
            result = MACH_SEND_INVALID_HEADER; // TODO
            break;
        }
        case 200: {
            MACH_MSG_UNION(host_info, Mess);
            if(Mess->In.flavor == HOST_PRIORITY_INFO) {
                result = host_info(Mess->In.Head.msgh_request_port, Mess->In.flavor, (host_info_t)Mess->Out.host_info_out, &Mess->Out.host_info_outCnt);
                host_header->msgh_size = sizeof(Mess->Out) - sizeof(Mess->Out.host_info_out) + sizeof(Mess->Out.host_info_out[0])*Mess->Out.host_info_outCnt;
                Mess->Out.RetCode = result;
            } else {
                printf("LC32: Unhandled flavor %d\n", Mess->In.flavor);
                CurrentUserCallbacks()->ExceptionRaised(
                    0xDEADDEAD, Dynarmic::A32::Exception::Yield);
            }
            break;
        }
        case 205: {
            /*
             * iOS 10 calls this host_get_io_master; the current SDK renamed
             * the same MIG slot and returned right to host_get_io_main.
             */
            MACH_MSG_UNION(host_get_io_main, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = host_get_io_main(
                Mess->In.Head.msgh_request_port,
                &Mess->Out.io_main.name);
            Mess->Out.io_main.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.io_main.disposition = MACH_MSG_TYPE_MOVE_SEND;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 206: {
            MACH_MSG_UNION(host_get_clock_service, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = host_get_clock_service(Mess->In.Head.msgh_request_port, Mess->In.clock_id, &Mess->Out.clock_serv.name);
            Mess->Out.clock_serv.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.clock_serv.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 217: {
            MACH_MSG_UNION(host_request_notification, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.NDR = NDR_record;
            Mess->Out.RetCode = host_request_notification(
                Mess->In.Head.msgh_request_port,
                Mess->In.notify_type,
                Mess->In.notify_port.name);
            break;
        }
        case 412: {
            MACH_MSG_UNION(host_get_special_port, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = host_get_special_port(Mess->In.Head.msgh_request_port, Mess->In.node, Mess->In.which, &Mess->Out.port.name);
            Mess->Out.port.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.port.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case DYLD_PROCESS_INFO_NOTIFY_LOAD_ID: {
            const dyld_process_info_notify_header *Mess = (dyld_process_info_notify_header *)host_header;
            const dyld_process_info_image_entry* entries = (dyld_process_info_image_entry*)((uintptr_t)Mess + Mess->imagesOffset);
            uintptr_t stringPool = (uintptr_t)Mess + Mess->stringsOffset;
            for(unsigned i=0; i < Mess->imageCount; ++i) {
                u32 imageAddress = entries[i].loadAddress;
                char *imagePath = (char *)(stringPool + entries[i].pathStringOffset);
                // Find __TEXT size
                struct segment_command *seg = (struct segment_command *)((uintptr_t)get_memory(imageAddress) + sizeof(struct mach_header));
                while(seg->cmd != LC_SEGMENT || strcmp(seg->segname, SEG_TEXT) != 0){
                    seg = (struct segment_command *)((uintptr_t)seg + seg->cmdsize);
                }
                char hostImagePath[PATH_MAX];
                const bool debuggerPathResolved =
                    ResolveDebuggerImagePath(imagePath, hostImagePath);
                const char *mappingName =
                    debuggerPathResolved ? hostImagePath : imagePath;

                int mappingIndex = FindGuestMapping(imageAddress);
                if (mappingIndex >= 0) {
                    // Preserve a known-good standalone path when dyld repeats
                    // the executable or dyld with only a guest-path fallback.
                    if (guestMappings[mappingIndex].debuggerPathResolved ||
                        !debuggerPathResolved) {
                        continue;
                    }
                    free(const_cast<char *>(guestMappings[mappingIndex].name));
                } else {
                    if (guestMappingLen >= 1000) {
                        fprintf(stderr,
                                "LC32: too many mapped images for debugger\n");
                        break;
                    }
                    mappingIndex = guestMappingLen++;
                }

                guestMappings[mappingIndex].name = strdup(mappingName);
                guestMappings[mappingIndex].debuggerPathResolved =
                    debuggerPathResolved;
                guestMappings[mappingIndex].start = imageAddress;
                guestMappings[mappingIndex].end =
                    imageAddress + seg->vmsize;
                guestMappings[mappingIndex].hostAddr =
                    (uintptr_t)get_memory(imageAddress);
                // Even when ROOT_PATH only contains a dyld shared cache, LLDB
                // can resolve this original guest path through its matching
                // DeviceSupport Symbols tree.
                ++guestMappingGeneration;
                printf("LC32: added image %s (0x%08x-0x%08x)\n",
                       guestMappings[mappingIndex].name,
                       guestMappings[mappingIndex].start,
                       guestMappings[mappingIndex].end);
            }
            __attribute__((fallthrough));
        }
        case DYLD_PROCESS_INFO_NOTIFY_UNLOAD_ID: {
            if (host_header->msgh_id == DYLD_PROCESS_INFO_NOTIFY_UNLOAD_ID) {
                const dyld_process_info_notify_header *Mess =
                    (dyld_process_info_notify_header *)host_header;
                const dyld_process_info_image_entry *entries =
                    (dyld_process_info_image_entry *)((uintptr_t)Mess +
                                                      Mess->imagesOffset);
                for (unsigned i = 0; i < Mess->imageCount; ++i) {
                    RemoveGuestMapping((u32)entries[i].loadAddress);
                }
            }
            __attribute__((fallthrough));
        }
        case DYLD_PROCESS_INFO_NOTIFY_MAIN_ID: {
            host_header->msgh_bits        = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND);
            host_header->msgh_id          = 0;
            host_header->msgh_local_port  = MACH_PORT_NULL;
            host_header->msgh_reserved    = 0;
            host_header->msgh_size        = sizeof(*host_header);
            break;
        }
        case 3201: {
            MACH_MSG_UNION(mach_port_type, Mess);
            Mess->Out.NDR = NDR_record;
            Mess->Out.RetCode = mach_port_type(
                Mess->In.Head.msgh_request_port,
                Mess->In.name,
                &Mess->Out.ptype);
            host_header->msgh_size =
                Mess->Out.RetCode == KERN_SUCCESS
                    ? sizeof(Mess->Out)
                    : sizeof(mig_reply_error_t);
            break;
        }
        case 3213: {
            MACH_MSG_UNION(mach_port_request_notification, Mess);
            /*
             * Translate through the host API rather than forwarding the old
             * kernel MIG request verbatim. This lets the host stub use its
             * current wire ABI while preserving the port-right disposition.
             */
            mach_port_t previous = MACH_PORT_NULL;
            const kern_return_t kr = mach_port_request_notification(
                Mess->In.Head.msgh_request_port,
                Mess->In.name,
                Mess->In.msgid,
                Mess->In.sync,
                Mess->In.notify.name,
                Mess->In.notify.disposition,
                &previous);
            if (kr != KERN_SUCCESS) {
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = kr;
                break;
            }

            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            Mess->Out.previous = {};
            Mess->Out.previous.name = previous;
            Mess->Out.previous.disposition = MACH_MSG_TYPE_MOVE_SEND_ONCE;
            Mess->Out.previous.type = MACH_MSG_PORT_DESCRIPTOR;
            break;
        }
        case 3217: {
            MACH_MSG_UNION(mach_port_get_attributes, Mess);
            /*
             * The iOS 10 and host MIG routines share message ID 3217, but
             * forwarding the guest request would couple us to the host wire
             * layout.  Invoke the host API and construct the variable-sized
             * reply expected by the 32-bit client instead.
             */
            Mess->Out.NDR = NDR_record;
            mach_msg_type_number_t count = Mess->In.port_info_outCnt;
            constexpr mach_msg_type_number_t MaxPortInfoCount =
                sizeof(Mess->Out.port_info_out) /
                sizeof(Mess->Out.port_info_out[0]);
            if (count > MaxPortInfoCount) {
                Mess->Out.RetCode = MIG_ARRAY_TOO_LARGE;
                host_header->msgh_size = sizeof(mig_reply_error_t);
            } else {
                Mess->Out.RetCode = mach_port_get_attributes(
                    Mess->In.Head.msgh_request_port,
                    Mess->In.name,
                    Mess->In.flavor,
                    Mess->Out.port_info_out,
                    &count);
                if (Mess->Out.RetCode == KERN_SUCCESS) {
                    Mess->Out.port_info_outCnt = count;
                    host_header->msgh_size =
                        sizeof(Mess->Out) -
                        sizeof(Mess->Out.port_info_out) +
                        sizeof(Mess->Out.port_info_out[0]) * count;
                } else {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                }
            }
            break;
        }
        case 3218: {
            MACH_MSG_UNION(mach_port_set_attributes, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.NDR = NDR_record;
            if (Mess->In.port_infoCnt >
                    sizeof(Mess->In.port_info) /
                        sizeof(Mess->In.port_info[0])) {
                Mess->Out.RetCode = MIG_ARRAY_TOO_LARGE;
            } else {
                Mess->Out.RetCode = mach_port_set_attributes(
                    Mess->In.Head.msgh_request_port,
                    Mess->In.name,
                    Mess->In.flavor,
                    Mess->In.port_info,
                    Mess->In.port_infoCnt);
            }
            break;
        }
        case 3409: {
            MACH_MSG_UNION(task_get_special_port, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = task_get_special_port(Mess->In.Head.msgh_request_port, Mess->In.which_port, &Mess->Out.special_port.name);
            Mess->Out.special_port.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.special_port.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 3410: {
            MACH_MSG_UNION(task_set_special_port, Mess);
            Mess->Out.RetCode = task_set_special_port(Mess->In.Head.msgh_request_port, Mess->In.which_port, Mess->In.special_port.name);
            break;
        }
        case 3418: {
            MACH_MSG_UNION(semaphore_create, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = semaphore_create(Mess->In.Head.msgh_request_port, &Mess->Out.semaphore.name, Mess->In.policy, Mess->In.value);
            Mess->Out.semaphore.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.semaphore.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 3419: {
            MACH_MSG_UNION(semaphore_destroy, Mess);
            const task_t task =
                Mess->In.Head.msgh_request_port;
            const semaphore_t semaphore =
                Mess->In.semaphore.name;
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.NDR = NDR_record;
            const kern_return_t destroyResult =
                semaphore_destroy(task, semaphore);
            Mess->Out.RetCode = destroyResult;
            if (destroyResult != KERN_SUCCESS) {
                fprintf(stderr,
                    "LC32: semaphore_destroy task=0x%x "
                    "semaphore=0x%x failed: 0x%x\n",
                    task, semaphore, destroyResult);
            }
            break;
        }
        case 3444: {
            MACH_MSG_UNION(task_register_dyld_image_infos, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.RetCode = KERN_SUCCESS;
            break;
        }
        case 3447: {
            MACH_MSG_UNION(task_register_dyld_shared_cache_image_info, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.RetCode = KERN_SUCCESS;
            break;
        }
        case 3616: { // thread_policy
            MACH_MSG_UNION(thread_policy, Mess);
            /*
             * Explicit guest pthreads have synthetic Mach ports and are
             * cooperatively scheduled on one host thread. Applying their
             * policy to the emulator thread would incorrectly affect every
             * guest context, so acknowledge the per-thread policy locally.
             */
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.NDR = NDR_record;
            Mess->Out.RetCode = KERN_SUCCESS;
            break;
        }
        case 78945670: {
            MACH_MSG_UNION(_notify_server_register_check, Mess);
            /*
             * The guest cannot use the host's notify shared-memory table.
             * The -1 values make libnotify fall back to plain registration.
             */
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.size = -1;
            Mess->Out.slot = -1;
            Mess->Out.token = 0;
            Mess->Out.status = 0;
            Mess->Out.RetCode = 0;
            break;
        }
        case 78945679: {
            MACH_MSG_UNION(_notify_server_cancel, Mess);
            /*
             * Guest libnotify removes its client-side registration before
             * sending this request. register_check is synthesized above, so
             * its token has no corresponding host notifyd registration.
             * Acknowledge the cancellation locally rather than forwarding a
             * guest token into the host namespace.
             */
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.RetCode = KERN_SUCCESS;
            Mess->Out.status = 0;
            break;
        }
        case 78945680: {
            MACH_MSG_UNION(_notify_server_check, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.RetCode = KERN_SUCCESS;
            Mess->Out.check = 0;
            Mess->Out.status = 0;
            break;
        }
        case 78945698: {
            /*
             * _notify_server_register_mach_port_2 is a MIG simpleroutine:
             * the client only sends a registration and expects no reply.
             * The guest's notify dispatch port is not currently driven by a
             * workqueue event manager, so accept the registration locally.
             */
            free(host_msg);
            return MACH_MSG_SUCCESS;
        }
        case 2877: { // iOS 10 io_server_version
            struct __attribute__((packed, aligned(4))) IoServerVersionReply {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                kern_return_t RetCode;
                uint64_t version;
            };
            using IoServerVersion = kern_return_t (*)(
                mach_port_t, uint64_t *);
            static const IoServerVersion ioServerVersion =
                reinterpret_cast<IoServerVersion>(
                    ResolveHostIOKitSymbol("io_server_version"));

            auto *reply =
                reinterpret_cast<IoServerVersionReply *>(host_header);
            uint64_t version = 0;
            const kern_return_t kr = ioServerVersion != nullptr
                ? ioServerVersion(
                    host_header->msgh_request_port, &version)
                : KERN_NOT_SUPPORTED;
            reply->NDR = NDR_record;
            reply->RetCode = kr;
            reply->version = version;
            host_header->msgh_size = kr == KERN_SUCCESS
                ? sizeof(*reply)
                : sizeof(mig_reply_error_t);
            break;
        }
        case 2804: { // io_service_get_matching_services
            struct __attribute__((packed, aligned(4)))
                    IoMatchingServicesReply {
                mach_msg_header_t Head;
                mach_msg_body_t Body;
                mach_msg_port_descriptor_t existing;
            };
            using IoServiceGetMatchingServices = kern_return_t (*)(
                mach_port_t, const char *, mach_port_t *);
            static const IoServiceGetMatchingServices getMatchingServices =
                reinterpret_cast<IoServiceGetMatchingServices>(
                    ResolveHostIOKitSymbol(
                        "io_service_get_matching_services"));

            constexpr size_t MatchingOffset = 40;
            const char *matching = host_msg + MatchingOffset;
            const bool validRequest =
                send_size > MatchingOffset &&
                memchr(matching, '\0', send_size - MatchingOffset) != nullptr;
            mach_port_t existing = MACH_PORT_NULL;
            const kern_return_t kr =
                validRequest && getMatchingServices != nullptr
                ? getMatchingServices(
                    host_header->msgh_request_port,
                    matching, &existing)
                : MIG_BAD_ARGUMENTS;
            if (kr != KERN_SUCCESS) {
                auto *error =
                    reinterpret_cast<mig_reply_error_t *>(host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = kr;
                break;
            }

            auto *reply =
                reinterpret_cast<IoMatchingServicesReply *>(host_header);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(*reply);
            reply->Body.msgh_descriptor_count = 1;
            reply->existing = {};
            reply->existing.name = existing;
            reply->existing.disposition = MACH_MSG_TYPE_MOVE_SEND;
            reply->existing.type = MACH_MSG_PORT_DESCRIPTOR;
            break;
        }
        case 78: // libdispatch_internal_protocol.wakeup_runloop_thread
        case 79: // libdispatch_internal_protocol.consume_send_once_right
        case 0x77303074:
        case 0x10000000:
        case 0x20000000: {
            /*
             * These are libdispatch control messages, libxpc's 'w00t'
             * connection check-in, and XPC request/reply serializers.
             * Preserve their request dispositions and forward the complete
             * operation because they may transfer port rights and use both
             * send-only and combined send/receive calls.
             */
            host_header->msgh_bits = request_bits;
            result = debugger_aware_mach_msg(host_header, option, send_size,
                rcv_size, rcv_name, timeout, notify);
            if ((option & MACH_RCV_MSG) != 0 && rcv_size != 0 &&
                    result != MACH_RCV_INTERRUPTED &&
                    result != MACH_SEND_INTERRUPTED) {
                Dynarmic_mem_1write(guest_msg, rcv_size, host_msg);
            }
            free(host_msg);
            return result;
        }
        default:
            printf("LC32: Unhandled msgh_id %d\n",
                host_header->msgh_id);
            CurrentUserCallbacks()->ExceptionRaised(
                0xDEADDEAD, Dynarmic::A32::Exception::Yield);
            break;
    }

    host_header->msgh_reply_port = rcv_name;
    host_header->msgh_request_port = 0;
    host_header->msgh_id += 100; // reply Id always equals reqId+100

    Dynarmic_mem_1write(guest_msg, rcv_size, host_msg);
    free(host_msg);
    return result;
}

int guest_getdirentries64(int fd, u32 guest_buf, int nbytes, u32 guest_basep) {
    char *host_buf = (char *)malloc(nbytes);
    __darwin_off_t host_basep =
        static_cast<__darwin_off_t>(
            CurrentUserCallbacks()->MemoryRead32(
                guest_basep)); // is reading needed?
    // FIXME: is this correct?
    int result = syscallRetCarry(SYS_getdirentries64, fd, host_buf, nbytes, &host_basep, 0,0,0);
    Dynarmic_mem_1write(guest_buf, nbytes, host_buf);
    CurrentUserCallbacks()->MemoryWrite64(
        guest_basep, host_basep);
    free(host_buf);
    return result;
}

void guest_stat_copy(struct stat *host_buf, struct stat_32 *host_buf_32) {
    host_buf_32->st_dev = host_buf->st_dev;
    host_buf_32->st_mode = host_buf->st_mode;
    host_buf_32->st_nlink = host_buf->st_nlink;
    host_buf_32->st_ino = host_buf->st_ino;
    host_buf_32->st_uid = host_buf->st_uid;
    host_buf_32->st_gid = host_buf->st_gid;
    host_buf_32->st_rdev = host_buf->st_rdev;

    // Y2038???
    host_buf_32->st_atimespec.tv_sec = host_buf->st_atimespec.tv_sec;
    host_buf_32->st_atimespec.tv_nsec = host_buf->st_atimespec.tv_nsec;
    host_buf_32->st_mtimespec.tv_sec = host_buf->st_mtimespec.tv_sec;
    host_buf_32->st_mtimespec.tv_nsec = host_buf->st_mtimespec.tv_nsec;
    host_buf_32->st_ctimespec.tv_sec = host_buf->st_ctimespec.tv_sec;
    host_buf_32->st_ctimespec.tv_nsec = host_buf->st_ctimespec.tv_nsec;
    host_buf_32->st_birthtimespec.tv_sec = host_buf->st_birthtimespec.tv_sec;
    host_buf_32->st_birthtimespec.tv_nsec = host_buf->st_birthtimespec.tv_nsec;

    host_buf_32->st_size = host_buf->st_size;
    host_buf_32->st_blocks = host_buf->st_blocks;
    host_buf_32->st_blksize = host_buf->st_blksize;
    host_buf_32->st_flags = host_buf->st_flags;
    host_buf_32->st_gen = host_buf->st_gen;
    host_buf_32->st_lspare = host_buf->st_lspare;
    host_buf_32->st_qspare[0] = host_buf->st_qspare[0];
    host_buf_32->st_qspare[1] = host_buf->st_qspare[1];
}

int guest_stat64(u32 guest_path, u32 guest_buf) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    struct stat host_buf;
    struct stat_32 host_buf_32;
    int result = stat(host_path, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_fstat(int fildes, u32 guest_buf) {
    struct stat host_buf;
    struct stat_32 host_buf_32;
    int result = fstat(fildes, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_lstat(u32 guest_path, u32 guest_buf) {
    struct stat host_buf;
    struct stat_32 host_buf_32;
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    int result = lstat(host_path, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_statfs64(u32 guest_path, u32 guest_buf) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    struct statfs host_buf;
    int result = syscallRetCarry(SYS_statfs, host_path, &host_buf, 0,0,0,0,0);
    if(result == 0) {
        Dynarmic_mem_1write(guest_buf, sizeof(struct statfs), (char *)&host_buf);
    }
    return result;
}

int guest_fstatfs64(int fildes, u32 guest_buf) {
    struct statfs host_buf;
    int result = syscallRetCarry(SYS_fstatfs, fildes, &host_buf, 0,0,0,0,0);
    if(result == 0) {
        Dynarmic_mem_1write(guest_buf, sizeof(struct statfs), (char *)&host_buf);
    }
    return result;
}

u32 guest_bsdthread_thread_start;
u32 guest_bsdthread_wqthread_start;
int guest_bsdthread_pthread_size;
int guest_workqueue_dispatch_offset;
bool guest_workqueue_kevent_enabled;
bool guest_workqueue_opened;
u32 guest_bsdthread_tsd_offset;

struct GuestWorkqueueKevent {
    guest_kevent_qos_s event;
    bool enabled;
    bool triggered;
};

struct GuestWorkqueueRequest {
    int remaining;
    u32 priority;
};

static std::vector<GuestWorkqueueKevent> guestWorkqueueKevents;
static std::deque<GuestWorkqueueRequest> guestWorkqueueRequests;
static std::recursive_mutex guestWorkqueueMutex;
static u32 guestWorkqueueEventManagerPriority;
static bool guestWorkqueueUpcallActive;
static bool guestWorkqueueRestoreRequested;
static thread_local bool guestWorkqueueOverlayCurrent;

static_assert(sizeof(guest_kevent_qos_s) == 72,
    "iOS 10 kevent_qos_s ABI changed");

static u32 GuestWorkqueueQosClass(u32 priority) {
    switch ((priority & PTHREAD_PRIORITY_QOS_CLASS_MASK) >>
            PTHREAD_PRIORITY_QOS_CLASS_SHIFT) {
        case PTHREAD_PRIORITY_CBIT_USER_INTERACTIVE:
            return GUEST_QOS_CLASS_USER_INTERACTIVE;
        case PTHREAD_PRIORITY_CBIT_USER_INITIATED:
            return GUEST_QOS_CLASS_USER_INITIATED;
        case PTHREAD_PRIORITY_CBIT_UTILITY:
            return GUEST_QOS_CLASS_UTILITY;
        case PTHREAD_PRIORITY_CBIT_BACKGROUND:
            return GUEST_QOS_CLASS_BACKGROUND;
        case PTHREAD_PRIORITY_CBIT_MAINTENANCE:
            return GUEST_QOS_CLASS_MAINTENANCE;
        case PTHREAD_PRIORITY_CBIT_DEFAULT:
        default:
            return GUEST_QOS_CLASS_DEFAULT;
    }
}

static bool GuestKeventMatches(const GuestWorkqueueKevent &registered,
                               const guest_kevent_qos_s &change) {
    if (registered.event.ident != change.ident ||
            registered.event.filter != change.filter) {
        return false;
    }
    if (((registered.event.flags | change.flags) &
            EV_UDATA_SPECIFIC) != 0) {
        return registered.event.udata == change.udata;
    }
    return true;
}

static int ApplyGuestKeventChanges(u32 changelist, int nchanges) {
    if (nchanges < 0 || nchanges > 4096 ||
            (nchanges != 0 && changelist == 0)) {
        return EINVAL;
    }
    if (nchanges == 0) {
        return 0;
    }

    std::vector<guest_kevent_qos_s> changes(
        static_cast<size_t>(nchanges));
    if (Dynarmic_mem_1read(changelist,
            changes.size() * sizeof(changes[0]),
            reinterpret_cast<char *>(changes.data())) != 0) {
        return EFAULT;
    }

    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    for (const guest_kevent_qos_s &change : changes) {
        WORKQUEUE_TRACE(
            "LC32: workqueue change ident=0x%llx filter=%d "
            "flags=0x%x qos=0x%x fflags=0x%x udata=0x%llx\n",
            change.ident, change.filter, change.flags, change.qos,
            change.fflags, change.udata);
        auto registered = std::find_if(
            guestWorkqueueKevents.begin(), guestWorkqueueKevents.end(),
            [&change](const GuestWorkqueueKevent &candidate) {
                return GuestKeventMatches(candidate, change);
            });

        if (change.filter == EVFILT_USER &&
                (change.fflags & NOTE_TRIGGER) != 0 &&
                (change.flags & EV_ADD) == 0) {
            if (registered != guestWorkqueueKevents.end()) {
                registered->triggered = true;
            }
            continue;
        }

        if ((change.flags & EV_DELETE) != 0) {
            if (registered != guestWorkqueueKevents.end()) {
                guestWorkqueueKevents.erase(registered);
            }
            continue;
        }

        if ((change.flags & EV_ADD) != 0) {
            const bool enabled = (change.flags & EV_DISABLE) == 0;
            if (registered == guestWorkqueueKevents.end()) {
                guestWorkqueueKevents.push_back(
                    {.event = change,
                     .enabled = enabled,
                     .triggered = false});
            } else {
                registered->event = change;
                registered->enabled = enabled;
            }
            continue;
        }

        if (registered == guestWorkqueueKevents.end()) {
            continue;
        }
        registered->event = change;
        if ((change.flags & EV_DISABLE) != 0) {
            registered->enabled = false;
        } else if ((change.flags & EV_ENABLE) != 0) {
            registered->enabled = true;
        }
    }
    return 0;
}

int guest_bsdthread_register(u32 guest_func_thread_start, u32 guest_func_start_wqthread, int pthread_size, u32 data, int32_t datasize, off_t offset) {
    guest_bsdthread_thread_start = guest_func_thread_start;
    guest_bsdthread_wqthread_start = guest_func_start_wqthread;
    guest_bsdthread_pthread_size = pthread_size;
    guest_bsdthread_tsd_offset = 0;
    WORKQUEUE_TRACE(
        "LC32: bsdthread_register thread=0x%x workq=0x%x "
        "pthread_size=0x%x data_size=0x%x\n",
        guest_func_thread_start, guest_func_start_wqthread,
        pthread_size, datasize);
    if (data != 0 && datasize > 0) {
        guest_pthread_registration_data registration = {};
        const size_t copySize = MIN(
            static_cast<size_t>(datasize), sizeof(registration));
        if (Dynarmic_mem_1read(data, copySize,
                reinterpret_cast<char *>(&registration)) != 0) {
            return return_with_carry_direct(EINVAL, true);
        }
        if (registration.version >
                offsetof(guest_pthread_registration_data, tsd_offset) &&
                registration.tsd_offset <
                static_cast<u32>(pthread_size)) {
            guest_bsdthread_tsd_offset = registration.tsd_offset;
        }
        WORKQUEUE_TRACE(
            "LC32: bsdthread registration version=%llu "
            "dispatch_offset=0x%llx tsd_offset=0x%x\n",
            registration.version, registration.dispatch_queue_offset,
            registration.tsd_offset);
        registration.version = sizeof(registration);
        registration.main_qos = 0;
        if (Dynarmic_mem_1write(data, copySize,
                reinterpret_cast<char *>(&registration)) != 0) {
            return return_with_carry_direct(EINVAL, true);
        }
    }
    return return_with_carry(PTHREAD_FEATURE_DISPATCHFUNC |
        PTHREAD_FEATURE_FINEPRIO |
        PTHREAD_FEATURE_BSDTHREADCTL |
        PTHREAD_FEATURE_SETSELF |
        PTHREAD_FEATURE_QOS_MAINTENANCE |
        PTHREAD_FEATURE_KEVENT |
        PTHREAD_FEATURE_QOS_DEFAULT, false);
}

int guest_workq_open() {
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    if (guest_bsdthread_wqthread_start == 0) {
        return return_with_carry_direct(EINVAL, true);
    }
    guest_workqueue_opened = true;
    return return_with_carry_direct(0, false);
}

int guest_bsdthread_ctl(u32 command, u32 arg1, u32 arg2, u32 arg3) {
    switch (command) {
        case BSDTHREAD_CTL_QOS_OVERRIDE_START:
        case BSDTHREAD_CTL_QOS_OVERRIDE_END:
        case BSDTHREAD_CTL_QOS_OVERRIDE_DISPATCH:
        case BSDTHREAD_CTL_QOS_DISPATCH_ASYNC_ADD:
        case BSDTHREAD_CTL_QOS_DISPATCH_ASYNC_RESET:
            /*
             * QoS overrides affect scheduler state for another guest
             * pthread. All explicit and workqueue guest contexts share one
             * emulator host thread, so applying an override to the host
             * would leak it across every guest. Guest libpthread keeps the
             * bookkeeping needed to balance these calls; acknowledge the
             * kernel half without changing host scheduling policy.
             */
            return return_with_carry_direct(0, false);
        case BSDTHREAD_CTL_SET_SELF:
            WORKQUEUE_TRACE(
                "LC32: bsdthread_ctl SET_SELF priority=0x%x "
                "voucher=0x%x flags=0x%x\n",
                arg1, arg2, arg3);
            /*
             * QoS, current voucher, and kevent binding are kernel properties
             * of a thread. LC32's guest contexts cooperatively share one host
             * emulator thread, so forwarding SET_SELF would leak a worker's
             * state into the saved main context and into emulator-internal
             * Mach calls. Guest libpthread maintains its QoS and voucher state
             * in guest TSD, while direct-kevent delivery is already disabled
             * when an EV_DISPATCH event is selected. There is therefore no
             * host-side state to change here.
             */
            return return_with_carry_direct(0, false);
        case BSDTHREAD_CTL_QOS_OVERRIDE_RESET:
            /*
             * Dispatch uses this to clear scheduler overrides from the
             * current workqueue thread. LC32 does not model host scheduling
             * overrides, so its empty guest-side override set is already in
             * the requested state.
             */
            if (arg1 != 0 || arg2 != 0 || arg3 != 0) {
                return return_with_carry_direct(EINVAL, true);
            }
            return return_with_carry_direct(0, false);
        default:
            fprintf(stderr,
                "LC32: Unhandled bsdthread_ctl command 0x%x\n",
                command);
            return return_with_carry_direct(EINVAL, true);
    }
}

int guest_workq_kernreturn(int options, u32 item, int arg2, int arg3) {
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    WORKQUEUE_TRACE(
        "LC32: workq_kernreturn op=0x%x item=0x%x arg2=%d "
        "arg3=0x%x active=%d\n",
        options, item, arg2, arg3, guestWorkqueueUpcallActive);
    switch (options) {
        case WQOPS_QUEUE_NEWSPISUPP:
            /*
             * libpthread uses this as the dispatch/kevent capability
             * handshake. arg2 is the dispatch queue serial-number offset and
             * bit zero of arg3 requests direct kevent delivery.
             */
            guest_workqueue_dispatch_offset = arg2;
            guest_workqueue_kevent_enabled = (arg3 & 1) != 0;
            return return_with_carry_direct(0, false);
        case WQOPS_SET_EVENT_MANAGER_PRIORITY:
            guestWorkqueueEventManagerPriority = static_cast<u32>(arg2);
            return return_with_carry_direct(0, false);
        case WQOPS_QUEUE_REQTHREADS: {
            if (!guest_workqueue_opened || arg2 <= 0 || arg2 > 4096) {
                return return_with_carry_direct(EINVAL, true);
            }
            guestWorkqueueRequests.push_back(
                {.remaining = arg2, .priority = static_cast<u32>(arg3)});
            return return_with_carry_direct(0, false);
        }
        case WQOPS_QUEUE_REQTHREADS2:
            /*
             * The iOS 10 userspace library does not issue this operation, and
             * its request-array ABI is distinct from QUEUE_REQTHREADS.
             */
            return return_with_carry_direct(ENOTSUP, true);
        case WQOPS_THREAD_KEVENT_RETURN: {
            const int error = ApplyGuestKeventChanges(item, arg2);
            return return_with_carry_direct(error, error != 0);
        }
        case WQOPS_THREAD_RETURN:
            return return_with_carry_direct(0, false);
        default:
            return return_with_carry_direct(EINVAL, true);
    }
}

int guest_kevent_qos(int kq, u32 changelist, int nchanges,
        u32 eventlist, int nevents, u32 data_out, u32 data_available,
        unsigned int flags) {
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    WORKQUEUE_TRACE(
        "LC32: kevent_qos kq=%d changes=%d events=%d flags=0x%x\n",
        kq, nchanges, nevents, flags);
    /*
     * This is the registration half of direct-kevent workqueue support.
     * libdispatch asks the default workqueue kqueue (-1) to install changes
     * and optionally return change errors. There can be no delivery until
     * WQOPS_QUEUE_REQTHREADS can create a guest event-manager thread.
     */
    if (kq != -1 || !guest_workqueue_opened ||
            !guest_workqueue_kevent_enabled ||
            (flags & KEVENT_FLAG_WORKQ) == 0) {
        return return_with_carry_direct(ENOTSUP, true);
    }
    if (eventlist != 0 && nevents > 0 &&
            (flags & KEVENT_FLAG_ERROR_EVENTS) == 0) {
        return return_with_carry_direct(ENOTSUP, true);
    }
    const int error = ApplyGuestKeventChanges(changelist, nchanges);
    return return_with_carry_direct(error, error != 0);
}

int guest_sandbox_ms(u32 guest_policyname, int call, u32 guest_arg) {
    // TODO: ???
    char host_policyname[0x20];
    Dynarmic_mem_1read(guest_policyname, sizeof(host_policyname), host_policyname);
    printf("sandbox(%s, %d)\n", host_policyname, call);
    return 0;
}

int guest_getentropy(u32 guest_buffer, u32 length) {
    char *host_buffer = (char *)malloc(length);
    int result = syscallRetCarry(SYS_getentropy, (void *)host_buffer, length, 0,0,0,0,0);
    Dynarmic_mem_1write(guest_buffer, length, host_buffer);
    free(host_buffer);
    return result;
}

int guest_connect(int socket, u32 guest_address, socklen_t address_len) {
    // See https://developer.apple.com/forums/thread/756756?answerId=790507022#790507022
    // sockaddr_un.sun_path has an artificial limit is 104 bytes, however it allows up to 253 bytes
    if(address_len > SOCK_MAXADDRLEN) {
        return return_with_carry_direct(EINVAL, true);
    }
    char host_address[SOCK_MAXADDRLEN];
    Dynarmic_mem_1read(guest_address, address_len, host_address);

    int type;
    socklen_t length = sizeof(int);
    getsockopt(socket, SOL_SOCKET, SO_TYPE, &type, &length);
    if(type == SOCK_DGRAM) {
        char host_path[PATH_MAX];
        sockaddr_un *sock = (sockaddr_un *)host_address;
        sharedHandle.fs->pathGuestToHost(sock->sun_path, host_path);
        if(strlen(host_path) > SOCK_MAXADDRLEN - offsetof(sockaddr_un, sun_path)) {
            return return_with_carry_direct(EINVAL, true);
        }
        strcpy(sock->sun_path, host_path);
        address_len = SUN_LEN(sock);
    }

    return syscallRetCarry(SYS_connect, socket, (const sockaddr *)host_address, address_len, 0,0,0,0);
}

int guest_gettimeofday(u32 guest_tp, u32 guest_tzp) {
    // tzp is always null since it's no longer used
    //assert(!guest_tzp);
    struct timeval host_tp;
    int result = syscallRetCarry(SYS_gettimeofday, &host_tp, NULL, 0,0,0,0,0);
    if (result == 0 && guest_tp != 0) {
        // time_t/suseconds_t are 64-bit in the arm64 host ABI but 32-bit in
        // this armv7 guest ABI.  Copying sizeof(host_tp) would overwrite the
        // eight bytes following the guest timeval.
        timeval_32 guest_tp_value = {
            .tv_sec = static_cast<int32_t>(host_tp.tv_sec),
            .tv_usec = static_cast<int32_t>(host_tp.tv_usec),
        };
        Dynarmic_mem_1write(
            guest_tp, sizeof(guest_tp_value),
            reinterpret_cast<char *>(&guest_tp_value));
    }
    return result;
}

int guest_rename(u32 guest_old, u32 guest_new) {
    char host_old[PATH_MAX], host_new[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_old, host_old);
    sharedHandle.fs->pathGuestToHost(guest_new, host_new);
    return syscallRetCarry(SYS_rename, host_old, host_new, 0,0,0,0,0);
}

ssize_t guest_sendto(int socket, const u32 guest_buffer, size_t length, int flags, u32 guest_dest_addr, socklen_t dest_len) {
    char *host_buffer = (char *)malloc(length);
    char *host_dest_addr = (char *)malloc(dest_len);
    Dynarmic_mem_1read(guest_buffer, length, host_buffer);
    Dynarmic_mem_1read(guest_dest_addr, dest_len, host_dest_addr);
    int result = syscallRetCarry(SYS_sendto, socket, host_buffer, length, flags, (const sockaddr *)host_dest_addr, dest_len, 0);
    free(host_buffer);
    free(host_dest_addr);
    return result;
}

ssize_t guest_pread(int NR, int fildes, u32 guest_buf, size_t nbyte, off_t offset) {
    char *host_buf = (char *)malloc(nbyte);
    ssize_t result = syscallRetCarry(NR, fildes, host_buf, nbyte, offset, 0,0,0);
    Dynarmic_mem_1write(guest_buf, nbyte, host_buf);
    free(host_buf);
    return result;
}

ssize_t guest_read(int NR, int fildes, u32 guest_buf, size_t nbyte) {
    char *host_buf = (char *)malloc(nbyte);
    ssize_t result = syscallRetCarry(NR, fildes, host_buf, nbyte, 0,0,0,0);
    Dynarmic_mem_1write(guest_buf, nbyte, host_buf);
    free(host_buf);
    return result;
}

ssize_t guest_write(int NR, int fildes, u32 guest_buf, size_t nbyte) {
    char *host_buf = (char *)malloc(nbyte);
    Dynarmic_mem_1read(guest_buf, nbyte, host_buf);
    ssize_t result = syscallRetCarry(NR, fildes, host_buf, nbyte, 0,0,0,0);
    free(host_buf);
    return result;
}

ssize_t guest_writev(int NR, int fildes, u32 guest_iov, int iovcnt) {
    size_t iovsize = sizeof(iovec_32) * iovcnt;
    iovec_32 *host_iov = (iovec_32 *)malloc(iovsize);
    Dynarmic_mem_1read(guest_iov, iovsize, (char *)host_iov);
    ssize_t result = 0;
    for (int i = 0; i < iovcnt; i++) {
        result += guest_write(NR == SYS_writev ? SYS_write : SYS_write_nocancel, fildes, host_iov[i].guest_iov_base, host_iov[i].iov_len);
    }
    free(host_iov);
    return result;
}

int guest_open(int NR, u32 guest_path, int oflag, int mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    int result = syscallRetCarry(NR, host_path, oflag, mode, 0,0,0,0);
    return result;
}

int guest_unlink(u32 guest_path) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_unlink, host_path, 0,0,0,0,0,0);
}

int guest_chmod(u32 guest_path, mode_t mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_chmod, host_path, mode, 0,0,0,0,0);
}

int guest_chown(u32 guest_path, uid_t owner, gid_t group) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_chown, host_path, owner, group, 0,0,0,0);
}

int guest_access(u32 guest_path, int mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_access, host_path, mode, 0,0,0,0,0);
}

int guest_sigaction(int sig, u32 guest_act, u32 guest_oact) {
    static sigaction_32 host_actions[SIGUSR2 + 1];
    if (guest_oact) {
        Dynarmic_mem_1write(guest_oact, sizeof(sigaction_32), (char *)&host_actions[sig]);
    }
    if (guest_act) {
        printf("LC32: sigaction: 0x%08x -> ", host_actions[sig]._sa_handler);
        Dynarmic_mem_1read(guest_act, sizeof(sigaction_32), (char *)&host_actions[sig]);
        printf("LC32: 0x%08x\n", host_actions[sig]._sa_handler);
    }
    return 0;
}

int guest_sigprocmask(int how, u32 guest_set, u32 guest_oldset) {
    sigset_t host_set = guest_set
        ? CurrentUserCallbacks()->MemoryRead32(guest_set)
        : 0;
    sigset_t host_oldset = 0;
    int result = syscallRetCarry(SYS_sigprocmask, how, guest_set ? &host_set : NULL, &host_oldset, 0,0,0,0);
    if (guest_oldset) {
        CurrentUserCallbacks()->MemoryWrite32(
            guest_oldset, host_oldset);
    }
    return result;
}

int guest_ioctl(int fildes, u32 request, u32 guest_r2) {
    switch(request) {
        case TIOCSCTTY:
        case TIOCEXCL:
        case TIOCSBRK:
        case TIOCCBRK:
        case TIOCPTYGRANT:
        case TIOCPTYUNLK:
            //case DTRACEHIOC_REMOVE:
            //case BIOCFLUSH:
            //case BIOCPROMISC:
            return syscallRetCarry(SYS_ioctl, fildes, request, guest_r2, 0,0,0,0);
        case FIODTYPE: {
            int host_r2;
            int result = syscallRetCarry(SYS_ioctl, fildes, request, &host_r2, 0,0,0,0);
            CurrentUserCallbacks()->MemoryWrite32(
                guest_r2, host_r2);
            return result;
        }
        case DTRACEHIOC_ADD:
        case DTRACEHIOC_ADDDOF:
        case DTRACEHIOC_REMOVE:
        case 0x80046804: // FIXME?
            return -1;
    }
    printf("Unhandled ioctl request: %d (0x%x)\n", request, request);
    CurrentUserCallbacks()->ExceptionRaised(
        0xDEADDEAD, Dynarmic::A32::Exception::Yield);
    return -1;
}

int guest_pthread_sigmask(int how, u32 guest_set, u32 guest_oldset) {
    return GuestThreadSigmask(how, guest_set, guest_oldset);
}

ssize_t guest_readlink(u32 guest_pathname, u32 guest_buf, size_t bufsiz) {
    char host_pathname[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_pathname, host_pathname);
    char *host_buf = (char *)malloc(bufsiz);
    int result = syscallRetCarry(SYS_readlink, host_pathname, host_buf, bufsiz, 0,0,0,0);
    sharedHandle.fs->pathHostToGuest(host_buf, guest_buf);
    Dynarmic_mem_1write(guest_buf, bufsiz, host_buf);
    free(host_buf);
    return result;
}

int guest_munmap(u32 guest_addr, size_t len) {
    int result = Dynarmic_munmap(guest_addr, len);
    if(result == -1) {
        threadHandle.cpsr->setCarry(true);
        return errno;
    }
    return result;
}

int guest_mprotect(u32 guest_addr, size_t len, int prot) {
    int result = Dynarmic_mprotect(guest_addr, len, prot);
    if(result == -1) {
        threadHandle.cpsr->setCarry(true);
        return errno;
    }
    return result;
}

int guest_fcntl(int fildes, int cmd, u32 guest_r2) {
    switch (cmd) {
        // r2 is null or is a literal
        case F_DUPFD:
        case F_GETFD:
        case F_SETFD:
        case F_GETFL:
        case F_SETFL:
        case F_GETOWN:
        case F_SETOWN:
        case F_RDAHEAD:
        case F_NOCACHE:
        case F_FULLFSYNC:
            return syscallRetCarry(SYS_fcntl, fildes, cmd, guest_r2, 0,0,0,0);
        case F_ADDFILESIGS_RETURN:
            // fsig->fs_file_start = 0xFFFFFFFF;
            CurrentUserCallbacks()->MemoryWrite32(
                guest_r2, 0xFFFFFFFF);
            return 0;
        case F_CHECK_LV:
            return 0;
        // r2 is a pointer
        case F_GETPATH: {
            char host_r2[PATH_MAX];
            int result = syscallRetCarry(SYS_fcntl, fildes, cmd, host_r2, 0,0,0,0);
            sharedHandle.fs->pathHostToGuest(host_r2, guest_r2);
            return result;
        }
        case F_PREALLOCATE: {
            fstore_t host_r2;
            Dynarmic_mem_1read(guest_r2, sizeof(fstore_t), (char *)&host_r2);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2, 0,0,0,0);
        }
        case F_SETSIZE: {
            off_t host_r2 =
                CurrentUserCallbacks()->MemoryRead64(guest_r2);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2);
        }
        case F_RDADVISE: {
            struct radvisory host_r2;
            Dynarmic_mem_1read(guest_r2, sizeof(struct radvisory), (char *)&host_r2);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2, 0,0,0,0);
        }
        //case F_READBOOTSTRAP:
        //case F_WRITEBOOTSTRAP:

        case F_LOG2PHYS: {
            struct log2phys host_r2;
            Dynarmic_mem_1read(guest_r2, sizeof(struct log2phys), (char *)&host_r2);
            int result = syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2, 0,0,0,0);
            Dynarmic_mem_1write(guest_r2, sizeof(struct log2phys), (char *)&host_r2);
            return result;
        }
        default:
            printf("Unhandled fcntl command: %d\n", cmd);
            CurrentUserCallbacks()->ExceptionRaised(
                0xDEADDEAD, Dynarmic::A32::Exception::Yield);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, guest_r2, 0,0,0,0);
    }
}

int guest_proc_info(int callnum, int pid, int flavor, uint64_t arg, u32 guest_buffer, int buffersize) {
    // FIXME: check buffer size
    char *host_buffer = (char *)malloc(buffersize);
    int result = syscallRetCarry(SYS_proc_info, callnum, pid, flavor, arg, host_buffer, buffersize, 0);
    if(callnum == 2 && flavor == PROC_PIDT_SHORTBSDINFO) {
        proc_bsdshortinfo *info = (proc_bsdshortinfo *)host_buffer;
        info->pbsi_flags |= 2; // set PROC_FLAG_TRACED. FIXME: without this, it will crash
        info->pbsi_flags &= ~0x10; // unset PROC_FLAG_LP64
    }
    Dynarmic_mem_1write(guest_buffer, buffersize, host_buffer);
    free(host_buffer);
    return result;
}

int guest_mach_timebase_info(u32 guest_info) {
    struct mach_timebase_info host_info;
    int result = mach_timebase_info(&host_info);
    Dynarmic_mem_1write(guest_info, sizeof(host_info), (char *)&host_info);
    return result;
}

kern_return_t guest_host_create_mach_voucher_trap(mach_port_name_t host, u32 guest_recipes, int recipes_size, u32 guest_voucher) {
    // array of bytes
    mach_voucher_attr_raw_recipe_array_t host_recipes = (mach_voucher_attr_raw_recipe_array_t)malloc(recipes_size);
    Dynarmic_mem_1read(guest_recipes, recipes_size, (char *)host_recipes);
    mach_port_name_t host_voucher;
    kern_return_t result = host_create_mach_voucher_trap(host, host_recipes, recipes_size, &host_voucher);
    CurrentUserCallbacks()->MemoryWrite32(
        guest_voucher, host_voucher);
    return result;
}

kern_return_t guest_mach_voucher_extract_attr_recipe_trap(
        mach_port_name_t voucher,
        mach_voucher_attr_key_t key,
        u32 guest_recipe,
        u32 guest_recipe_size) {
    mach_msg_type_number_t recipe_capacity = 0;
    if (Dynarmic_mem_1read(
            guest_recipe_size, sizeof(recipe_capacity),
            reinterpret_cast<char *>(&recipe_capacity)) != 0) {
        return KERN_MEMORY_ERROR;
    }

    if (recipe_capacity >
            MACH_VOUCHER_ATTR_MAX_RAW_RECIPE_ARRAY_SIZE) {
        return MIG_ARRAY_TOO_LARGE;
    }

    std::vector<uint8_t> recipe(std::max<size_t>(recipe_capacity, 1));
    if (recipe_capacity != 0 &&
            Dynarmic_mem_1read(
                guest_recipe, recipe_capacity,
                reinterpret_cast<char *>(recipe.data())) != 0) {
        return KERN_MEMORY_ERROR;
    }

    mach_msg_type_number_t recipe_size = recipe_capacity;
    kern_return_t result = mach_voucher_extract_attr_recipe_trap(
        voucher, key, recipe.data(), &recipe_size);
    if (result != KERN_SUCCESS) {
        return result;
    }
    if (recipe_size > recipe_capacity) {
        return MIG_ARRAY_TOO_LARGE;
    }
    if (recipe_size != 0 &&
            Dynarmic_mem_1write(
                guest_recipe, recipe_size,
                reinterpret_cast<char *>(recipe.data())) != 0) {
        return KERN_MEMORY_ERROR;
    }
    if (Dynarmic_mem_1write(
            guest_recipe_size, sizeof(recipe_size),
            reinterpret_cast<char *>(&recipe_size)) != 0) {
        return KERN_MEMORY_ERROR;
    }
    return result;
}

kern_return_t guest_mach_generate_activity_id(
        mach_port_name_t target, int count, u32 guest_activity_ids) {
    if (count < 0 || count > MACH_ACTIVITY_ID_COUNT_MAX) {
        return KERN_INVALID_ARGUMENT;
    }

    std::array<uint64_t, MACH_ACTIVITY_ID_COUNT_MAX> activity_ids = {};
    kern_return_t result = mach_generate_activity_id(
        target, count, count == 0 ? nullptr : activity_ids.data());
    if (result == KERN_SUCCESS && count != 0 &&
            Dynarmic_mem_1write(
                guest_activity_ids,
                static_cast<size_t>(count) * sizeof(activity_ids[0]),
                reinterpret_cast<char *>(activity_ids.data())) != 0) {
        return KERN_MEMORY_ERROR;
    }
    return result;
}

kern_return_t guest_mk_timer_cancel(
        mach_port_name_t timer, u32 guest_result_time) {
    uint64_t result_time = 0;
    kern_return_t result = mk_timer_cancel(
        timer, guest_result_time == 0 ? nullptr : &result_time);
    if (result == KERN_SUCCESS && guest_result_time != 0 &&
            Dynarmic_mem_1write(
                guest_result_time, sizeof(result_time),
                reinterpret_cast<char *>(&result_time)) != 0) {
        return KERN_FAILURE;
    }
    return result;
}

kern_return_t guest__kernelrpc_mach_vm_allocate_trap(u32 target, u32 guest_address, mach_vm_size_t size, int flags) {
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }

    // FIXME: change the behavior of this to ensure re-mmapping works
    //int tag = flags >> 24;
    bool anywhere = (flags & VM_FLAGS_ANYWHERE) != 0;
    if (anywhere) {
        // Sometimes the address pointer will contain garbage value, change it to 0
        CurrentUserCallbacks()->MemoryWrite32(
            guest_address, 0);
    }
    u32 result = Dynarmic_mmap(
        CurrentUserCallbacks()->MemoryRead32(guest_address),
        size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS |
            (anywhere ? 0 : MAP_FIXED),
        -1, 0);
    if (result == -1) {
/*
        if (!anywhere && tag != VM_MEMORY_REALLOC) {
            printf("IllegalStateException\n");
            abort();
        }
*/
        return KERN_NO_SPACE;
    }
    CurrentUserCallbacks()->MemoryWrite32(
        guest_address, result);
    return KERN_SUCCESS;
}

kern_return_t guest__kernelrpc_mach_port_construct_trap(mach_port_name_t target, u32 guest_options, u64 context, u32 guest_name) {
    mach_port_options_t host_options;
    mach_port_name_t host_name;
    Dynarmic_mem_1read(guest_options, sizeof(host_options), (char *)&host_options);
    kern_return_t result = _kernelrpc_mach_port_construct_trap(target, &host_options, context, &host_name);
    CurrentUserCallbacks()->MemoryWrite32(
        guest_name, host_name);
    return result;
}

kern_return_t guest__kernelrpc_mach_port_allocate_trap(mach_port_name_t target, mach_port_right_t right, u32 guest_name) {
    mach_port_name_t host_name;
    kern_return_t result = _kernelrpc_mach_port_allocate_trap(target, right, &host_name);
    CurrentUserCallbacks()->MemoryWrite32(
        guest_name, host_name);
    return result;
}

kern_return_t guest__kernelrpc_mach_vm_map_trap(mach_port_name_t target, u32 guest_address, mach_vm_size_t size, mach_vm_offset_t mask, int flags, vm_prot_t cur_protection) {
    // TODO: verify and round mask accordingly
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }
    bool anywhere = (flags & VM_FLAGS_ANYWHERE) != 0;
    if (!anywhere) {
        printf("LC32: BackendException: _kernelrpc_mach_vm_map_trap fixed\n");
        return KERN_FAILURE;
    }
    u32 result = Dynarmic_mmap(
        CurrentUserCallbacks()->MemoryRead32(guest_address),
        size, cur_protection, MAP_PRIVATE | MAP_ANONYMOUS,
        -1, 0, mask ?: DYN_PAGE_MASK);
    if (result == -1) {
        return KERN_NO_SPACE;
    }
    CurrentUserCallbacks()->MemoryWrite32(
        guest_address, result);
    return KERN_SUCCESS;
}

kern_return_t guest__kernelrpc_mach_vm_deallocate_trap(u32 target, vm_address_t address, mach_vm_size_t size) {
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }
    return Dynarmic_munmap(address, size) == 0 ? KERN_SUCCESS : KERN_FAILURE;
}

int guest_abort_with_payload(u32 reason_namespace, u64 reason_code, u32 guest_payload, u32 payload_size, u32 guest_reason_string, u64 reason_flags) {
    DynarmicHostString host_reason_string(guest_reason_string);
    printf("abort_with_payload called with namespace=0x%x, code=0x%llx, reason=%s\n", reason_namespace, reason_code, host_reason_string.hostPtr);
    return 0;
}

////////
int guestMappingLen = 0;
guest_file_mapping guestMappings[1000];
size_t guestMappingGeneration = 0;

static void load_symbols_for_image(guest_file_mapping *mapping, void(^iterator)(u32 address, const char *name)) {
    const struct mach_header *header = (const struct mach_header *)mapping->hostAddr;
    u32 slide = mapping->start;
    uintptr_t loadCommand = (uintptr_t)header + sizeof(*header);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        const load_command *command = (const load_command *)loadCommand;
        if (command->cmd == LC_SEGMENT) {
            const segment_command *segment =
                (const segment_command *)command;
            if (strncmp(segment->segname, "__PAGEZERO",
                    sizeof(segment->segname)) != 0) {
                slide = mapping->start - segment->vmaddr;
                break;
            }
        }
        loadCommand += command->cmdsize;
    }
    
    u32 crashInfoSize;
    u64 crash_info = (u32)(u64)getsectdatafromheader(header, SEG_DATA, "__crash_info", &crashInfoSize);
    if (crash_info && crashInfoSize >= sizeof(crashreporter_annotations_t)) {
        crash_info += slide;
        crashreporter_annotations_t host_gCRAnnotations;
        Dynarmic_mem_1read(crash_info, sizeof(crashreporter_annotations_t), (char *)&host_gCRAnnotations);
        if (host_gCRAnnotations.message) {
            char message[0x1000] = {};
            Dynarmic_mem_1read(host_gCRAnnotations.message, sizeof(message), message);
            message[sizeof(message) - 1] = '\0';
            printf("Crash message from %s: %s (cause: 0x%llx)\n",
                mapping->name, message, host_gCRAnnotations.abort_cause);
        } else if (host_gCRAnnotations.message2) {
            printf("gCRAnnotations has message2 but unhandled. Crashing to raise attention\n");
        }
    }
    
    segment_command *cur_seg_cmd;
    struct symtab_command* symtab_cmd = NULL;
    uintptr_t cur = (uintptr_t)header + sizeof(mach_header);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (segment_command *)cur;
        if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command*)cur_seg_cmd;
        }
    }
    
    if (!symtab_cmd) {
        return;
    }
    
    // Find base symbol/string table addresses
    // FIXME: symbol resolution for dyld shared cache
#if 1
    struct nlist *symtab = (struct nlist *)((u64)mapping->start + symtab_cmd->symoff);
    u32 strtab = (u32)(mapping->start + symtab_cmd->stroff);
    iterator(mapping->start, "(unknown symbol)");
    if(!get_memory(strtab)) {
        return;
    }
    
    for(int i=0; i < symtab_cmd->nsyms; i++) {
        u32 addr = strtab +
            CurrentUserCallbacks()->MemoryRead32(
                static_cast<u32>(
                    reinterpret_cast<uintptr_t>(
                        &symtab[i].n_un.n_strx)));
        if(!get_memory(addr)) continue;
        u64 symbolAddr =
            CurrentUserCallbacks()->MemoryRead32(
                static_cast<u32>(
                    reinterpret_cast<uintptr_t>(
                        &symtab[i].n_value))) + slide;
        DynarmicHostString host_sym(addr);
        if(*host_sym.hostPtr) {
            iterator(symbolAddr, (const char *)host_sym.hostPtr);
        } else {
            iterator(symbolAddr, (const char *)symbolAddr);
        }
    }
#else
    struct nlist *symtab = (struct nlist *)((uintptr_t)header + symtab_cmd->symoff);
    char *strtab = (char *)((uintptr_t)header + symtab_cmd->stroff);
    for(int i=0; i < symtab_cmd->nsyms; i++) {
        iterator(symtab[i].n_value + slide, (const char *)(strtab + symtab[i].n_un.n_strx));
    }
#endif
}

void symbolicate_call_stack(symbolicated_call *callStack, int callStackLen) {
    for (int n = 0; n < guestMappingLen; n++) {
        load_symbols_for_image(&guestMappings[n], ^(u32 address, const char *name){
            //printf("[0x%08x-0x%08x] %s`%s\n", address, guestMappings[n].name, name);
            for (int i = 0; i < callStackLen; i++) {
                if (callStack[i].address >= address && (!callStack[i].symbolName || callStack[i].address - address < callStack[i].symbolOffset)) {
                    //printf("0x%08x [0x%08x-0x%08x]\n", callStack[i].address, start, end);
                    callStack[i].imageName = guestMappings[n].name;
                    callStack[i].symbolName = name;
                    callStack[i].symbolOffset = callStack[i].address - address;
                }
            }
        });
    }
}

char *get_memory_page(u64 vaddr) {
    size_t num_page_table_entries = sharedHandle.num_page_table_entries;
    void **page_table = sharedHandle.page_table;
    khash_t(memory) *memory = sharedHandle.memory;
    u64 idx = vaddr >> DYN_PAGE_BITS;
    if(page_table && idx < num_page_table_entries) {
      return static_cast<char *>(__atomic_load_n(
          &page_table[idx], __ATOMIC_ACQUIRE));
    }
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    u64 base = vaddr & ~DYN_PAGE_MASK;
    khiter_t k = kh_get(memory, memory, base);
    if(k == kh_end(memory)) {
      return NULL;
    }
    t_memory_page page = kh_value(memory, k);
    return (char *)page->addr;
}

inline void *get_memory(u64 vaddr) {
    char *page = get_memory_page(vaddr);
    return page ? &page[vaddr & DYN_PAGE_MASK] : NULL;
}

class DynarmicCallbacks32 final : public Dynarmic::A32::UserCallbacks {
private:
    bool dumpingBacktrace = false;
    ~DynarmicCallbacks32() = default;

public:
    void destroy() {
        this->cp15 = nullptr;
        delete this;
    }

    DynarmicCallbacks32(khash_t(memory) *memory)
        : memory{memory}, cp15(std::make_shared<DynarmicCP15>()) {}

    bool IsReadOnlyMemory(u32 vaddr) override {
//        u32 idx;
//        return mem_map && (idx = vaddr >> DYN_PAGE_BITS) < num_page_table_entries && mem_map[idx] & PAGE_EXISTS_BIT && (mem_map[idx] & UC_PROT_WRITE) == 0;
        return false;
    }

    std::optional<uint32_t> MemoryReadCode(u32 vaddr) override {
#if TRACE_BRANCH
        static u32 lastRead;
        if (vaddr - lastRead != 4 && vaddr == cpu->Regs()[15]) {
            lastRead = vaddr;
            DumpBacktrace(false);
        }
#endif
        if (vaddr > UINT32_MAX - (sizeof(uint32_t) - 1) ||
            get_memory(vaddr) == nullptr ||
            get_memory(vaddr + sizeof(uint32_t) - 1) == nullptr) {
            return std::nullopt;
        }
        return MemoryRead32(vaddr, false);
    }
    u16 MemoryReadThumbCode(u32 vaddr) {
        u16 code = MemoryRead16(vaddr, false);
//        printf("MemoryReadThumbCode[%s->%s:%d]: vaddr=0x%x, code=0x%04x\n", __FILE__, __func__, __LINE__, vaddr, code);
        return code;
    }

    /*
     * Yield to the remote debugger without running the built-in backtrace.
     * The latter reads more guest memory and can recursively fault before
     * gdbstub gets a chance to report the original stop.
     */
    void StopForDebugger(int signal, bool pendingSignal) {
        SetGuestStopSignal(signal, pendingSignal);
        cpu->HaltExecution(LC32HaltReasonTrap);
    }

// FIXME: sometimes it will try to access 0x4, 0x8 and 0xc, I disassembled and found nothing, is there something to do with cpsr? For now let it do stuff in an empty page...
    void HandleBadMemoryAccess() {
#if !IGNORE_BAD_MEM_ACCESS
        // Diagnostic frame walking is not guest execution.  A failed unwind
        // read must not replace the original debugger stop with SIGSEGV.
        if (!dumpingBacktrace) {
            if (guestDebuggerEnabled.load(std::memory_order_relaxed)) {
                StopForDebugger(SIGSEGV, true);
            } else {
                DumpCrashReport(SIGSEGV);
            }
        }
#endif
    }

    u8 MemoryRead8(u32 vaddr) override {
        u8 *dest = (u8 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: read08(0x%04x) = 0x%01x\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
            return 0;
        }
    }
    u16 MemoryRead16(u32 vaddr, bool trace) {
        if(vaddr & 1) {
            const u8 a{MemoryRead8(vaddr)};
            const u8 b{MemoryRead8(vaddr + sizeof(u8))};
            return (static_cast<u16>(b) << 8) | a;
        }
        u16 *dest = (u16 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            if (trace)
            printf("Trace: read16(0x%04x) = 0x%02x\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            // trace = tolerance bad mem access, else crash
            if(trace) {
                HandleBadMemoryAccess();
            } else {
                DumpCrashReport(SIGSEGV);
            }
            return 0;
        }
    }
    u16 MemoryRead16(u32 vaddr) override {
        return MemoryRead16(vaddr, true);
    }
    u32 MemoryRead32(u32 vaddr, bool trace) {
        if(vaddr & 3) {
            const u16 a{MemoryRead16(vaddr)};
            const u16 b{MemoryRead16(vaddr + sizeof(u16))};
            return (static_cast<u32>(b) << 16) | a;
        }
        u32 *dest = (u32 *) get_memory(vaddr);
        if(dest) {
            //printf("MemoryRead32[%s->%s:%d]: vaddr=0x%x, value=0x%x\n", __FILE__, __func__, __LINE__, vaddr, dest[0]);
#if TRACE_RW
            if (trace)
            printf("Trace: read32(0x%04x) = 0x%04x\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            // trace = tolerance bad mem access, else crash
            if(trace) {
                HandleBadMemoryAccess();
            } else {
                DumpCrashReport(SIGSEGV);
            }
            return 0;
        }
    }
    u32 MemoryRead32(u32 vaddr) override {
        return MemoryRead32(vaddr, true);
    }
    u64 MemoryRead64(u32 vaddr) override {
        if(vaddr & 7) {
            const u32 a{MemoryRead32(vaddr)};
            const u32 b{MemoryRead32(vaddr + sizeof(u32))};
            return (static_cast<u64>(b) << 32) | a;
        }
        u64 *dest = (u64 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: read64(0x%04x) = 0x%08llx\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
            return 0;
        }
    }

    void MemoryWrite8(u32 vaddr, u8 value) override {
        u8 *dest = (u8 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write08(0x%04x) = 0x%01x\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }
    void MemoryWrite16(u32 vaddr, u16 value) override {
        if(vaddr & 1) {
            MemoryWrite8(vaddr, static_cast<u8>(value));
            MemoryWrite8(vaddr + sizeof(u8), static_cast<u8>(value >> 8));
            return;
        }
        u16 *dest = (u16 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write16(0x%04x) = 0x%02x\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }
    void MemoryWrite32(u32 vaddr, u32 value) override {
        if(vaddr & 3) {
            MemoryWrite16(vaddr, static_cast<u16>(value));
            MemoryWrite16(vaddr + sizeof(u16), static_cast<u16>(value >> 16));
            return;
        }
        u32 *dest = (u32 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write32(0x%04x) = 0x%04x\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }
    void MemoryWrite64(u32 vaddr, u64 value) override {
        if(vaddr & 7) {
            MemoryWrite32(vaddr, static_cast<u32>(value));
            MemoryWrite32(vaddr + sizeof(u32), static_cast<u32>(value >> 32));
            return;
        }
        u64 *dest = (u64 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write64(0x%04x) = 0x%08llx\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }

    bool MemoryWriteExclusive8(u32 vaddr, u8 value, u8 expected) override {
        bool write = MemoryRead8(vaddr) == expected;
        if(write) {
            MemoryWrite8(vaddr, value);
        }
        return write;
    }
    bool MemoryWriteExclusive16(u32 vaddr, u16 value, u16 expected) override {
        bool write = MemoryRead16(vaddr) == expected;
        if(write) {
            MemoryWrite16(vaddr, value);
        }
        return write;
    }
    bool MemoryWriteExclusive32(u32 vaddr, u32 value, u32 expected) override {
        bool write = MemoryRead32(vaddr) == expected;
        if(write) {
            MemoryWrite32(vaddr, value);
        }
        return write;
    }
    bool MemoryWriteExclusive64(u32 vaddr, u64 value, u64 expected) override {
        bool write = MemoryRead64(vaddr) == expected;
        if(write) {
            MemoryWrite64(vaddr, value);
        }
        return write;
    }

    void InterpreterFallback(u32 pc, std::size_t num_instructions) override {
        cpu->HaltExecution();
        std::optional<std::uint32_t> code = MemoryReadCode(pc);
        if(code) {
            fprintf(stderr, "Unicorn fallback @ 0x%x for %lu instructions (instr = 0x%08X)", pc, num_instructions, *(cpsr->isThumb() ? MemoryReadThumbCode(pc) : MemoryReadCode(pc)));
        }
        cpu->Regs()[Reg::PC] = pc;
        DumpCrashReport(SIGILL);
    }

    void ExceptionRaised(u32 pc, Dynarmic::A32::Exception exception) override {
        const bool isBkpt =
            exception == Dynarmic::A32::Exception::Breakpoint;
        const bool isDebuggerBreakpoint =
            isBkpt && Dynarmic_debugger_has_breakpoint(pc);
        const bool inspectInstruction =
            isBkpt ||
            exception == Dynarmic::A32::Exception::UndefinedInstruction ||
            exception == Dynarmic::A32::Exception::UnpredictableInstruction ||
            exception == Dynarmic::A32::Exception::DecodeError;
        u32 code = 0;
        if (inspectInstruction) {
            code = cpsr->isThumb() ? MemoryReadThumbCode(pc)
                                   : MemoryReadCode(pc).value_or(0);
        }
        int signal = SIGABRT;
        bool replayInstruction = false;

        switch (exception) {
        case Dynarmic::A32::Exception::Breakpoint:
            signal = SIGTRAP;
            break;
        case Dynarmic::A32::Exception::UndefinedInstruction:
        case Dynarmic::A32::Exception::UnpredictableInstruction:
        case Dynarmic::A32::Exception::DecodeError:
            signal = SIGILL;
            replayInstruction = true;
            break;
        case Dynarmic::A32::Exception::NoExecuteFault:
            signal = SIGSEGV;
            replayInstruction = true;
            break;
        default:
            break;
        }

        // LLVM uses UDF #0xDEFE for an explicit trap. It is a bad-instruction
        // fault, not a debugger breakpoint.
        if ((code & 0xFFFF) == 0xDEFE) {
            signal = SIGILL;
            replayInstruction = true;
        }

        /*
         * Dynarmic has already advanced r15 when it invokes ExceptionRaised.
         * Synchronous faults must replay the faulting instruction.  A
         * debugger-planted BKPT must also report the breakpoint's address so
         * LLDB can match it and temporarily restore/step the original
         * instruction.  A BKPT that belongs to the guest itself keeps the
         * architectural post-instruction PC.
         */
        if (replayInstruction || isDebuggerBreakpoint) {
            cpu->Regs()[Reg::PC] = pc;
        }

        if (isBkpt) {
            if (guestDebuggerEnabled.load(std::memory_order_relaxed)) {
                fprintf(stderr, "%s breakpoint at 0x%08x\n",
                        isDebuggerBreakpoint ? "Debugger-managed" : "Guest",
                        pc);
                StopForDebugger(SIGTRAP, false);
            } else {
                printf("Breakpoint!\n");
                DumpCrashReport(SIGTRAP, false);
            }
            return;
        }

        if ((code & 0xFFFF) == 0xDEFE) {
            printf("ExceptionRaised[%s->%s:%d]: pc=0x%x, exception=%d, code=TRAP\n", __FILE__, __func__, __LINE__, pc, exception);
            DumpCrashReport(signal);
        } else {
            printf("ExceptionRaised[%s->%s:%d]: pc=0x%x, exception=%d, code=0x%08X\n", __FILE__, __func__, __LINE__, pc, exception, code);
            DumpCrashReport(signal);
        }
    }

    void DumpCrashReport(int signal = SIGABRT, bool pendingSignal = true) {
        DumpBacktrace(true, signal, pendingSignal);
    }
    
    void DumpBacktrace(bool crash,
                       int signal = SIGABRT,
                       bool pendingSignal = true) {
        if (dumpingBacktrace) {
            printf("Caught error while dumping call stack\n");
            if (crash) {
                HaltAllGuestJits(LC32HaltReasonTrap);
            }
            return;
        }
        if (crash) {
            SetGuestStopSignal(signal, pendingSignal);
        }
        dumpingBacktrace = true;

        printf("# %s\n", crash ? "CRASHED" : "Branch");
        printf("Registers: \n");
        printf(" r0 0x%08x  r1 0x%08x  r2 0x%08x  r3 0x%08x\n", cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
        printf(" r4 0x%08x  r5 0x%08x  r6 0x%08x  r7 0x%08x\n", cpu->Regs()[4], cpu->Regs()[5], cpu->Regs()[6], cpu->Regs()[7]);
        printf(" r8 0x%08x  r9 0x%08x r10 0x%08x r11 0x%08x\n", cpu->Regs()[8], cpu->Regs()[9], cpu->Regs()[10], cpu->Regs()[11]);
        printf("r12 0x%08x  sp 0x%08x  lr 0x%08x  pc 0x%08x\n", cpu->Regs()[12], cpu->Regs()[13], cpu->Regs()[14], cpu->Regs()[15]);
        printf("CPSR: 0x%08x thumb(%d) N(%d) Z(%d) C(%d) V(%d)\n", cpu->Cpsr(), threadHandle.cpsr->isThumb(), threadHandle.cpsr->isNegative(), threadHandle.cpsr->isZero(), threadHandle.cpsr->hasCarry(), threadHandle.cpsr->isOverflow());

        u32 pc = cpu->Regs()[15];
        u32 lr = cpu->Regs()[14];
        u32 fp = cpu->Regs()[7];

        struct symbolicated_call callStack[0x100] = {{0}};
        int callStackLen = 0;
        callStack[callStackLen++].address = pc - 2;
        callStack[callStackLen++].address = lr - 2;
        for (; callStackLen < 0x100; callStackLen++) {
            pc = MemoryRead32(fp + 4, false) & ~1;
            callStack[callStackLen].address = pc - 2;
            fp = MemoryRead32(fp, false);
            if(!fp) break;
        }
        symbolicate_call_stack(callStack, callStackLen);

        printf("Call stack: \n");
        for (int i = 0; i < 0x100; i++) {
            if (!callStack[i].address) break;
            printf("%3d: 0x%08x", i, callStack[i].address);
            const char *symbolName = callStack[i].symbolName;
            if (symbolName) {
                printf(" %s`%s + 0x%x\n", callStack[i].imageName, &symbolName[symbolName[0] == '_'], callStack[i].symbolOffset);
            } else {
                printf("\n");
            }
        }

        printf("Binary images: \n");
        for (int i = 0; i < guestMappingLen; i++) {
            printf("%3d: 0x%08x-0x%08x %s\n", i, guestMappings[i].start, guestMappings[i].end, guestMappings[i].name);
        }

        dumpingBacktrace = false;
        if (crash) {
            HaltAllGuestJits(LC32HaltReasonTrap);
        }
    }

    void CallSVC(u32 swi) override {
        int NR = cpu->Regs()[12];
        if (swi == 0 && cpu->Regs()[5] == POST_CALLBACK_SYSCALL_NUMBER && cpu->Regs()[7] == 0) { // postCallback
            int number = cpu->Regs()[4];
/*
            Svc svc = svcMemory.getSvc(number);
            if (svc != null) {
                svc.handlePostCallback(emulator);
                    return;
            }
            backend.emu_stop();
*/
            printf("svc number: %d\n", number);
            DumpCrashReport();
        }
        if (swi == 0 && cpu->Regs()[5] == PRE_CALLBACK_SYSCALL_NUMBER && cpu->Regs()[7] == 0) { // preCallback
            int number = cpu->Regs()[4];
/*
            Svc svc = svcMemory.getSvc(number);
            if (svc != null) {
                svc.handlePreCallback(emulator);
                return;
             }
            backend.emu_stop();
*/
            printf("Unhandled svc number: %d\n", number);
            DumpCrashReport();
        }
        if (swi != DARWIN_SWI_SYSCALL) {
            if (swi == (cpsr->isThumb() ? 0xff : 0xffffff)) {
                printf("LC32: throw: PopContextException\n");
                DumpCrashReport();
            }
            if (swi == (cpsr->isThumb() ? 0xff : 0xffffff) - 1) {
                printf("LC32: throw: ThreadContextSwitchException\n");
                DumpCrashReport();
            }
            printf("Unhandled svc number: %d\n", swi);
            DumpCrashReport();
/*
            Svc svc = svcMemory.getSvc(swi);
            if (svc != null) {
                backend.reg_write(ArmConst.UC_ARM_REG_R0, (int) svc.handle(emulator));
                return;
            }
            backend.emu_stop();
            throw new IllegalStateException("svc number: " + swi + ", NR=" + NR);
*/
        }

#if TRACE_SVC
        printf("CallSVC(NR=%d)\n", NR);
#endif

        cpsr->setCarry(false);
/*
BE CAREFUL WHEN MOVING SYSCALL. Checklist:
- Declared max args of the category
- Arg contains 64bit value? (must not)
- Exclude pointer-involved (guest_*)
*/
        switch (NR) {
            // direct calls with 0-4 arguments, returns 32bit value
            case -91: // mk_timer_create
            case -29: // host_self_trap
            case -28: // task_self_trap
            case -26: // mach_reply_port
            case -21: // _kernelrpc_mach_port_insert_right_trap
            case -19: // _kernelrpc_mach_port_mod_refs_trap
            case SYS_close: // 6
            case SYS_getpid: // 20
            case SYS_setuid: // 23
            case SYS_getuid: // 24
            case SYS_geteuid: // 25
            case SYS_getppid: // 39
            case SYS_getegid: // 43
            case SYS_getgid: // 47
            case SYS_fsync: // 95
            case SYS_socket: // 97
            case SYS_issetugid: // 327
            case SYS_close_nocancel: // 399
                cpu->Regs()[0] = syscallRetCarry(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                cpsr->setCarry(false); // FIXME: mach_reply_port sets carry to true, idk why
                break;
            // direct calls with 0-2 arguments, returns 64bit value
            case -18: // _kernelrpc_mach_port_deallocate_trap
            case -3: { // mach_absolute_time
                u64 result = syscallRetCarry((long)NR, cpu->Regs()[0], cpu->Regs()[1]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
            } break;
            // direct call with custom args
            case 334: // semwait_signal
            case 423: // semwait_signal_nocancel
                cpu->Regs()[0] = syscallRetCarry(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4] | ((u64)cpu->Regs()[5] << 32), cpu->Regs()[6]);
                break;
            // the rest are indirect calls
            case -17:
                cpu->Regs()[0] = mach_port_destroy(
                    cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case -20:
                cpu->Regs()[0] =
                    _kernelrpc_mach_port_move_member_trap(
                        cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case -27: { // thread_self_trap
                const mach_port_t syntheticPort =
                    GuestCurrentSyntheticThreadPort();
                if (MACH_PORT_VALID(syntheticPort)) {
                    const kern_return_t result = mach_port_mod_refs(
                        mach_task_self(), syntheticPort,
                        MACH_PORT_RIGHT_SEND, 1);
                    cpu->Regs()[0] = result == KERN_SUCCESS
                        ? syntheticPort
                        : MACH_PORT_NULL;
                } else {
                    cpu->Regs()[0] = syscallRetCarry(
                        NR, cpu->Regs()[0], cpu->Regs()[1],
                        cpu->Regs()[2], cpu->Regs()[3]);
                    cpsr->setCarry(false);
                }
                break;
            }
            case -22:
                cpu->Regs()[0] =
                    _kernelrpc_mach_port_insert_member_trap(
                        cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case -23:
                cpu->Regs()[0] =
                    _kernelrpc_mach_port_extract_member_trap(
                        cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case -25:
                cpu->Regs()[0] = _kernelrpc_mach_port_destruct_trap(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3] | (static_cast<uint64_t>(
                        cpu->Regs()[4]) << 32));
                break;
            case -33:
                cpu->Regs()[0] =
                    semaphore_signal_trap(cpu->Regs()[0]);
                break;
            case -36:
                cpu->Regs()[0] =
                    semaphore_wait_trap(cpu->Regs()[0]);
                break;
            case -38:
                cpu->Regs()[0] = semaphore_timedwait_trap(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case -41:
                cpu->Regs()[0] = _kernelrpc_mach_port_guard_trap(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2] | (static_cast<uint64_t>(
                        cpu->Regs()[3]) << 32),
                    cpu->Regs()[4]);
                break;
            case -43:
                cpu->Regs()[0] = guest_mach_generate_activity_id(
                    cpu->Regs()[0], static_cast<int>(cpu->Regs()[1]),
                    cpu->Regs()[2]);
                break;
            case -59: // swtch_pri
            case -60: // swtch
                /*
                 * These are scheduler hints used by libpthread's spin paths.
                 * Yield the real host pthread in native mode and retain the
                 * same call as a cooperative rotation point otherwise.
                 */
                (void)sched_yield();
                cpu->Regs()[0] = 0;
                GuestThreadRequestRotation();
                break;
            case -61:
                /*
                 * The host emulator thread is not the logical guest thread.
                 * Treat thread_switch as a cooperative scheduling point.
                 */
                cpu->Regs()[0] = KERN_SUCCESS;
                GuestThreadRequestRotation();
                break;
            case -89:
                cpu->Regs()[0] = guest_mach_timebase_info(cpu->Regs()[0]);
                break;
            case -92:
                cpu->Regs()[0] = mk_timer_destroy(cpu->Regs()[0]);
                break;
            case -93:
                cpu->Regs()[0] = mk_timer_arm(
                    cpu->Regs()[0],
                    cpu->Regs()[1] | (static_cast<uint64_t>(
                        cpu->Regs()[2]) << 32));
                break;
            case -94:
                cpu->Regs()[0] = guest_mk_timer_cancel(
                    cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case -70:
                cpu->Regs()[0] = guest_host_create_mach_voucher_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                break;
            case -72:
                cpu->Regs()[0] =
                    guest_mach_voucher_extract_attr_recipe_trap(
                        cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2],
                        cpu->Regs()[3]);
                break;
            case -31:
                cpu->Regs()[0] = guest_mach_msg_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5], cpu->Regs()[6]);
                break;
            case -24:
                cpu->Regs()[0] = guest__kernelrpc_mach_port_construct_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32), cpu->Regs()[4]);
                break;
            case -16: // _kernelrpc_mach_port_allocate_trap
                cpu->Regs()[0] = guest__kernelrpc_mach_port_allocate_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case -15:
                // NOTE: skip r7 since it's frame pointer
                cpu->Regs()[0] = guest__kernelrpc_mach_vm_map_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32), cpu->Regs()[4] | ((u64)cpu->Regs()[5] << 32), cpu->Regs()[6], cpu->Regs()[8]);
                break;
            case -12:
                cpu->Regs()[0] = guest__kernelrpc_mach_vm_deallocate_trap(cpu->Regs()[0], cpu->Regs()[1] | ((u64)cpu->Regs()[2] << 32), cpu->Regs()[3] | ((u64)cpu->Regs()[4] << 32));
                break;
            case -10:
                cpu->Regs()[0] = guest__kernelrpc_mach_vm_allocate_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32), cpu->Regs()[4]);
                break;
            case SYS_syscall: {
                printf("Warning: CallSVC(SYS_syscall, NR=%d) called. Be sure to check arguments\n", cpu->Regs()[0]);
                cpu->Regs()[12] = cpu->Regs()[0];
                CallSVC(0x80);
                break;
            }
            case SYS_exit: // 1
                printf("Guest exited with code %d\n", cpu->Regs()[0]);
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonExit);
                }
                break;
            case SYS_fork: // 2
                printf("fork() not supported\n");
                cpu->Regs()[0] = ENOSYS;
                break;
            case SYS_read: // 3
            case SYS_read_nocancel: // 396
                // Note: we don't use the cancel version cause unidbg also doesn't and it hangs
                cpu->Regs()[0] = guest_read(SYS_read_nocancel, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_write: // 4
            case SYS_write_nocancel:
                cpu->Regs()[0] = guest_write(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_open: // 5
            case SYS_open_nocancel:
                // Note: we don't use the cancel version cause unidbg also doesn't and it hangs
                cpu->Regs()[0] = guest_open(SYS_open_nocancel, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_unlink: // 10
                cpu->Regs()[0] = guest_unlink(cpu->Regs()[0]);
                break;
            case SYS_chmod: // 15
                cpu->Regs()[0] = guest_chmod(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case SYS_chown: // 16
                cpu->Regs()[0] = guest_chown(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 33:
                cpu->Regs()[0] = guest_access(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 46:
                cpu->Regs()[0] = guest_sigaction(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 48:
                cpu->Regs()[0] = guest_sigprocmask(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 54:
                cpu->Regs()[0] = guest_ioctl(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 58:
                cpu->Regs()[0] = guest_readlink(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 73:
                cpu->Regs()[0] = guest_munmap(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 74:
                cpu->Regs()[0] = guest_mprotect(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 75: // posix_madvise
                cpu->Regs()[0] = 0;
                break;
            case 92:
            case SYS_fcntl_nocancel:
                cpu->Regs()[0] = guest_fcntl(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 98:
                cpu->Regs()[0] = guest_connect(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 116:
                cpu->Regs()[0] = guest_gettimeofday(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 121:
            case SYS_writev_nocancel:
                cpu->Regs()[0] = guest_writev(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 128:
                cpu->Regs()[0] = guest_rename(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 133:
                cpu->Regs()[0] = guest_sendto(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case 153:
            case SYS_pread_nocancel:
                cpu->Regs()[0] = guest_pread(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3] | ((u64)cpu->Regs()[4] << 32));
                break;
            case 169:
                cpu->Regs()[0] = guest_csops(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                break;
            case 170:
                cpu->Regs()[0] = guest_csops_audittoken(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3], cpu->Regs()[4]);
                break;
            case 194:
                cpu->Regs()[0] = guest_getrlimit(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 197:
                cpu->Regs()[0] = guest_mmap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5] | ((u64)cpu->Regs()[6] << 32));
                break;
            case 202:
                cpu->Regs()[0] = guest___sysctl(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case 220:
                cpu->Regs()[0] = guest_getattrlist(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4]);
                break;
            case 266:
                cpu->Regs()[0] = guest_shm_open(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 274:
                cpu->Regs()[0] = guest___sysctlbyname(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case 286:
                cpu->Regs()[0] = guest_pthread_getugid_np(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 294: // __shared_region_check_np
                cpu->Regs()[0] = return_with_carry_direct(EINVAL, true);
                break;
            case 300: // psynch_rw_upgrade
            case 306: // psynch_rw_rdlock
            case 307: // psynch_rw_wrlock
                cpu->Regs()[0] =
                    GuestPsynchRwWait(cpu->Regs()[0]);
                break;
            case 301: // psynch_mutexwait
                cpu->Regs()[0] = GuestPsynchMutexWait(
                    cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 302: // psynch_mutexdrop
                cpu->Regs()[0] =
                    GuestPsynchMutexDrop(cpu->Regs()[0]);
                break;
            case 303: // psynch_cvbroad
                cpu->Regs()[0] = GuestPsynchConditionSignal(
                    cpu->Regs()[0], MACH_PORT_NULL, true);
                break;
            case 304: // psynch_cvsignal
                cpu->Regs()[0] = GuestPsynchConditionSignal(
                    cpu->Regs()[0],
                    static_cast<mach_port_t>(cpu->Regs()[4]),
                    false);
                break;
            case 305: // psynch_cvwait
                cpu->Regs()[0] = GuestPsynchConditionWait(
                    cpu->Regs()[0], cpu->Regs()[4]);
                break;
            case 308: // psynch_rw_unlock
            case 309: // psynch_rw_unlock2
                cpu->Regs()[0] =
                    GuestPsynchRwUnlock(cpu->Regs()[0]);
                break;
            case 312: // psynch_cvclrprepost
                cpu->Regs()[0] =
                    return_with_carry_direct(0, false);
                break;
            case 328:
                printf("pthread_kill called with signal %u\n", cpu->Regs()[1]);
                if (cpu->Regs()[1] == 0) {
                    // Signal zero only probes whether the target thread exists.
                    cpu->Regs()[0] = 0;
                } else if (cpu->Regs()[1] >= NSIG) {
                    cpu->Regs()[0] =
                        return_with_carry_direct(EINVAL, true);
                } else {
                    cpu->Regs()[0] = 0;
                    DumpCrashReport(static_cast<int>(cpu->Regs()[1]));
                }
                break;
            case 329:
                cpu->Regs()[0] = guest_pthread_sigmask(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 331: // __disable_threadsignal
                /*
                 * XNU marks the terminating uthread as unable to receive
                 * signals or cancellation. Guest signal delivery is already
                 * virtualized here, and bsdthread_terminate immediately
                 * retires the guest execution context, so no additional host
                 * state is needed.
                 */
                cpu->Regs()[0] =
                    return_with_carry_direct(0, false);
                break;
#if 0
                case 330:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, sigwait(emulator));
                    break;
#endif
            case 336:
                cpu->Regs()[0] = guest_proc_info(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3] | ((u64)cpu->Regs()[4] << 32), cpu->Regs()[5], cpu->Regs()[6]);
                break;
            case 338:
                cpu->Regs()[0] = guest_stat64(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 339:
                cpu->Regs()[0] = guest_fstat(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 340:
                cpu->Regs()[0] = guest_lstat(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 344:
                cpu->Regs()[0] = guest_getdirentries64(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                break;
            case 345:
                cpu->Regs()[0] = guest_statfs64(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 346:
                cpu->Regs()[0] = guest_fstatfs64(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 360: // bsdthread_create
                cpu->Regs()[0] = GuestBsdthreadCreate(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3], cpu->Regs()[4]);
                break;
            case 361: // bsdthread_terminate
                cpu->Regs()[0] = GuestBsdthreadTerminate(
                    cpu->Regs()[0], cpu->Regs()[1],
                    static_cast<mach_port_t>(cpu->Regs()[2]),
                    static_cast<mach_port_t>(cpu->Regs()[3]));
                break;
            case 366:
                cpu->Regs()[0] = guest_bsdthread_register(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5] | ((u64)cpu->Regs()[6] << 32));
                break;
            case 367: // workq_open
                cpu->Regs()[0] = guest_workq_open();
                break;
            case 368: { // workq_kernreturn
                const int operation = static_cast<int>(cpu->Regs()[0]);
                cpu->Regs()[0] = guest_workq_kernreturn(
                    operation, cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3]);
                if (GuestWorkqueueActiveForCurrentThread() &&
                        cpu->Regs()[0] == 0 &&
                        (operation == WQOPS_THREAD_RETURN ||
                         operation == WQOPS_THREAD_KEVENT_RETURN)) {
                    /*
                     * These calls park a kernel-created worker and never
                     * return to its abandoned userspace stack. The outer
                     * execution loop restores the waiting guest context
                     * before it executes another worker instruction.
                     */
                    std::lock_guard<std::recursive_mutex> lock(
                        guestWorkqueueMutex);
                    guestWorkqueueRestoreRequested = true;
                }
            }
                break;
            case 372: { // thread_selfid
                const u64 result = GuestCurrentThreadSelfId();
                cpu->Regs()[0] = static_cast<u32>(result);
                cpu->Regs()[1] = static_cast<u32>(result >> 32);
                cpsr->setCarry(false);
                break;
            }
            case 374: { // kevent_qos
                /*
                 * libsystem_kernel's ARM wrapper loads arguments 5-7 into
                 * r4-r6 and leaves argument 8 in its caller's stack. It has
                 * pushed r4-r6/r8 by the time SVC executes, hence sp + 28.
                 */
                const u32 flags = MemoryRead32(cpu->Regs()[Reg::SP] + 28,
                    false);
                cpu->Regs()[0] = guest_kevent_qos(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5],
                    cpu->Regs()[6], flags);
                break;
            }
            case 478: // bsdthread_ctl
                cpu->Regs()[0] = guest_bsdthread_ctl(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3]);
                break;
            case 381:
                cpu->Regs()[0] = guest_sandbox_ms(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 489: //mremap_encrypted
                printf("LC32: attempted to load encrypted binaries?\n");
                cpu->Regs()[0] = 0; //return_with_carry_direct(EPERM, true);
                break;
            case 500:
                cpu->Regs()[0] = guest_getentropy(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 515: // ulock_wait
                cpu->Regs()[0] = GuestUlockWait(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2] |
                        (static_cast<u64>(cpu->Regs()[3]) << 32),
                    cpu->Regs()[4]);
                break;
            case 516: // ulock_wake
                cpu->Regs()[0] = GuestUlockWake(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2] |
                        (static_cast<u64>(cpu->Regs()[3]) << 32));
                break;
            case SYS_abort_with_payload:
                cpu->Regs()[0] = guest_abort_with_payload(cpu->Regs()[0], cpu->Regs()[1] | ((u64)cpu->Regs()[2] << 32), cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5], cpu->Regs()[6] | ((u64)cpu->Regs()[8] << 32));
                DumpCrashReport(SIGABRT);
                break;
            case (int)0x80000000:
                NR = cpu->Regs()[3];
                if(handleMachineDependentSyscall(NR)) {
                    break;
                }
            case 1001: { // LC32Dlsym
                u64 result = LC32Dlsym(cpu->Regs()[0], cpu->Regs()[1]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1002: { // LC32InvokeHostCRet32
                if(cpu->IsExecuting()) {
                    // Get out of the callback first, since host may call other guest functions
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                typedef u32(*HostCall)(u32, u32, u32);
                HostCall hostCall = (HostCall)((u64)cpu->Regs()[0] | ((u64)cpu->Regs()[1] << 32));
                cpu->Regs()[0] = hostCall(cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[Reg::SP]);
                break;
            }
            case 1003: { // LC32GuestToHostCString
                DynarmicHostString host_pointer(cpu->Regs()[0], cpu->Regs()[1]);
                u64 result = (u64)host_pointer.hostPtrForGuest();
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1004: { // LC32GuestToHostCStringFree
                u64 pointer = cpu->Regs()[0] | ((u64)cpu->Regs()[1] << 32);
                // TODO: maybe move the check to guest
                if(pointer & DynarmicHostString_NEED_FREE) {
                    free((void *)((u64)pointer & ~DynarmicHostString_NEED_FREE));
                }
                break;
            }
            case 1005: { // LC32GetHostSelector
                u64 result = LC32GetHostSelector(cpu->Regs()[0]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1006: { // LC32InvokeHostSelector
                if(cpu->IsExecuting()) {
                    // Get out of the callback first, since host may call other guest functions
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                u64 host_self = (u64)cpu->Regs()[0] | ((u64)cpu->Regs()[1] << 32);
                u64 host_cmd = (u64)cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32);
                u64 result = LC32InvokeHostSelector(host_self, host_cmd, cpu->Regs()[Reg::SP]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1007: { // LC32GetHostObject
                if(cpu->IsExecuting()) {
                    // Get out of the callback first, since host may call other guest functions
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                u64 result = LC32GetHostObject(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1008: { // LC32HostToGuestCopyString
                u64 host_object = (u64)cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32);
                cpu->Regs()[0] = LC32HostToGuestCopyClassName(cpu->Regs()[0], cpu->Regs()[1], host_object);
                break;
            }
            case 1009:
                assert(cpu->IsExecuting());
                // We're returning from guest call
                cpu->HaltExecution(LC32HaltReasonRetFromGuest);
                break;
            default:
                printf("Unhandled svc number: %d\n", NR);
                DumpCrashReport(SIGSYS);
                break;
        }
#if TRACE_SVC
        printf("CallSVC returned 0x%08x, carry %d\n", cpu->Regs()[0], cpsr->hasCarry());
#endif
        /*
         * There is no host timer preempting the one shared JIT.  Rotate
         * explicit guest pthreads at completed Darwin syscall boundaries.
         * Fatal stops and LC32's private callback syscalls must retain their
         * current context.
         */
        if (NR < 1000 && NR != SYS_exit &&
                pendingGuestFatalSignal.load(
                    std::memory_order_relaxed) == 0) {
            GuestThreadRequestRotation();
        }
        /*
         * Ordinary SVC callbacks execute inline inside Dynarmic::Run().
         * Context replacement is only legal after Run() has unwound, so use
         * a private halt reason to transfer control to the outer loop without
         * replaying this already-completed syscall.
         */
        if (cpu->IsExecuting() &&
                GuestContextTransitionPending()) {
            cpu->HaltExecution(LC32HaltReasonWorkqueue);
        }
    }

    bool handleMachineDependentSyscall(int NR) {
        printf("handleMachineDependentSyscall(%d)\n", NR);
        switch (NR) {
            case 0:
                InvalidateAllGuestJits(
                    cpu->Regs()[0], cpu->Regs()[1]);
                cpu->Regs()[0] = 0;
                return true;
            case 1:
                //backend.reg_write(ArmConst.UC_ARM_REG_R0, sys_dcache_flush(emulator));
                return true;
            case 2:
                printf("TSB set to 0x%08x\n", cpu->Regs()[0]);
                cp15.get()->uro = cpu->Regs()[0];
                cpu->Regs()[0] = 0;
                return true;
            case 3:
                cpu->Regs()[0] = cp15.get()->uro;
                return true;
        }
        return false;
    }

    void AddTicks(u64 ticks) override {
    }

    u64 GetTicksRemaining() override {
        return 0x10000000000ULL;
    }

    khash_t(memory) *memory = NULL;
    size_t num_page_table_entries;
    void **page_table = NULL;
    Dynarmic::A32::Jit *cpu;
    DynarmicCpsr *cpsr;
    std::shared_ptr<DynarmicCP15> cp15;
};

static Dynarmic::A32::UserCallbacks *CurrentUserCallbacks() {
    return threadHandle.cb != nullptr
        ? static_cast<Dynarmic::A32::UserCallbacks *>(
            threadHandle.cb)
        : sharedHandle.ucb;
}

Dynarmic::A32::UserCallbacks *Dynarmic_current_user_callbacks() {
    return CurrentUserCallbacks();
}

namespace {

constexpr size_t MaxNativeGuestProcessors = 64;

enum class GuestThreadWaitKind : uint8_t {
    None,
    Mutex,
    Condition,
    Rwlock,
    Ulock,
};

struct NativeGuestJit {
    Dynarmic::A32::Jit *jit = nullptr;
    DynarmicCpsr *cpsr = nullptr;
    DynarmicCallbacks32 *callbacks = nullptr;
    size_t processorId = 0;
    pthread_t hostThread = {};
    mach_port_t hostMachThread = MACH_PORT_NULL;
    std::mutex startMutex;
    std::condition_variable startCondition;
    bool startAllowed = false;
};

struct GuestThreadContext {
    gdb_thread_id_t debuggerId = 0;
    u64 threadSelfId = 0;
    u32 pthreadAddress = 0;
    mach_port_t threadPort = MACH_PORT_NULL;
    u32 allocationAddress = 0;
    u32 allocationSize = 0;
    context32 saved = {};
    u32 signalMask = 0;
    GuestThreadWaitKind waitKind = GuestThreadWaitKind::None;
    u32 waitAddress = 0;
    u32 wakeResult = 0;
    u64 waitSequence = 0;
    bool savedValid = false;
    bool alive = false;
    bool runnable = false;
    NativeGuestJit *nativeJit = nullptr;
};

std::recursive_mutex guestThreadMutex;
std::deque<GuestThreadContext> guestThreads;
gdb_thread_id_t guestCurrentThreadId = 1;
gdb_thread_id_t guestNextDebuggerThreadId = 3;
u64 guestNextThreadSelfId;
bool guestThreadRegistryInitialized;
bool guestThreadRotationRequested;
bool guestThreadCurrentRetiring;
std::atomic<u64> guestNextWaitSequence{1};
uint64_t guestProcessorIdsInUse = 1;
thread_local gdb_thread_id_t nativeGuestThreadId;
thread_local bool nativeGuestThreadRetiring;

std::mutex nativeGuestJitMutex;
std::vector<NativeGuestJit *> nativeGuestJits;

struct GuestPsynchPrepost {
    GuestThreadWaitKind kind;
    u32 address;
    size_t count;
};
std::mutex guestPsynchPrepostMutex;
std::vector<GuestPsynchPrepost> guestPsynchPreposts;

struct NativeGuestWaiter {
    GuestThreadWaitKind kind = GuestThreadWaitKind::None;
    u32 address = 0;
    uint8_t ulockOpcode = 0;
    mach_port_t threadPort = MACH_PORT_NULL;
    u32 wakeResult = 0;
    u64 sequence = 0;
    bool signaled = false;
    std::condition_variable condition;
};

std::mutex nativeGuestWaitMutex;
std::vector<std::shared_ptr<NativeGuestWaiter>> nativeGuestWaiters;

constexpr u32 GuestWorkqueueGuardSize = DYN_PAGE_SIZE;
constexpr u32 GuestWorkqueueStackSize = 0x80000;
constexpr size_t GuestWorkqueueEventCapacity = 16;
constexpr size_t GuestWorkqueueMessageCapacity = 32 * 1024;

u32 guestWorkqueueAllocation;
u32 guestWorkqueueAllocationSize;
u32 guestWorkqueuePthread;
u32 guestWorkqueueStackBottom;
mach_port_t guestWorkqueueThreadPort;
bool guestWorkqueueWorkerInitialized;

struct GuestWorkqueueDelivery {
    guest_kevent_qos_s event = {};
    std::vector<uint8_t> message;
    bool eventManager = false;
};

struct GuestWorkqueuePendingUpcall {
    u32 eventList;
    u32 eventCount;
    u32 stackPointer;
    u32 flags;
    bool valid;
};

GuestWorkqueuePendingUpcall guestWorkqueuePendingUpcall;
context32 guestWorkqueueWaitingContext;
bool guestWorkqueueWaitingContextValid;
gdb_thread_id_t guestWorkqueueWaitingThreadId;
u64 guestWorkqueueThreadSelfId;
u32 guestWorkqueueSignalMask;

void SaveGuestContext(context32 &context) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    DynarmicCallbacks32 *callbacks = threadHandle.cb;
    context.regs = jit->Regs();
    context.extRegs = jit->ExtRegs();
    context.cpsr = jit->Cpsr();
    context.fpscr = jit->Fpscr();
    context.uro = callbacks->cp15->uro;
}

void LoadGuestContext(const context32 &context) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    DynarmicCallbacks32 *callbacks = threadHandle.cb;
    jit->Regs() = context.regs;
    jit->ExtRegs() = context.extRegs;
    jit->SetCpsr(context.cpsr);
    jit->SetFpscr(context.fpscr);
    callbacks->cp15->uro = context.uro;
    jit->ClearExclusiveState();
}

gdb_thread_id_t CurrentGuestThreadId() {
    if (NativeGuestThreadsEnabled() && nativeGuestThreadId != 0) {
        return nativeGuestThreadId;
    }
    return guestCurrentThreadId;
}

void EnsureGuestThreadRegistry() {
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    if (guestThreadRegistryInitialized) {
        if (NativeGuestThreadsEnabled() && nativeGuestThreadId == 0) {
            nativeGuestThreadId = 1;
        }
        return;
    }

    sigset_t hostMask = 0;
    (void)pthread_sigmask(SIG_SETMASK, nullptr, &hostMask);
    u32 guestMask = 0;
    memcpy(&guestMask, &hostMask,
        std::min(sizeof(guestMask), sizeof(hostMask)));

    const u64 mainThreadSelfId = __thread_selfid();
    guestThreads.push_back({
        .debuggerId = 1,
        .threadSelfId = mainThreadSelfId,
        .threadPort = NativeGuestThreadsEnabled()
            ? pthread_mach_thread_np(pthread_self())
            : MACH_PORT_NULL,
        .signalMask = guestMask,
        .savedValid = false,
        .alive = true,
        .runnable = true,
    });
    guestNextThreadSelfId = mainThreadSelfId + 1;
    if (guestNextThreadSelfId == 0) {
        guestNextThreadSelfId = 1;
    }
    guestThreadRegistryInitialized = true;
    if (NativeGuestThreadsEnabled()) {
        nativeGuestThreadId = 1;
        fprintf(stderr,
            "LC32: native guest pthread experiment enabled "
            "(debugger support disabled)\n");
    }
}

GuestThreadContext *FindGuestThread(
        gdb_thread_id_t debuggerId, bool requireAlive = false) {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    for (GuestThreadContext &thread : guestThreads) {
        if (thread.debuggerId == debuggerId &&
                (!requireAlive || thread.alive)) {
            return &thread;
        }
    }
    return nullptr;
}

size_t LiveGuestThreadCount() {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    return static_cast<size_t>(std::count_if(
        guestThreads.begin(), guestThreads.end(),
        [](const GuestThreadContext &thread) {
            return thread.alive;
        }));
}

u64 AllocateGuestThreadSelfId() {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    return guestNextThreadSelfId++;
}

GuestThreadContext *NextGuestThread() {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    if (guestThreads.empty()) {
        return nullptr;
    }

    const gdb_thread_id_t currentThreadId =
        CurrentGuestThreadId();
    size_t currentIndex = 0;
    for (; currentIndex < guestThreads.size(); ++currentIndex) {
        if (guestThreads[currentIndex].debuggerId ==
                currentThreadId) {
            break;
        }
    }
    if (currentIndex == guestThreads.size()) {
        return nullptr;
    }
    for (size_t offset = 1; offset <= guestThreads.size(); ++offset) {
        GuestThreadContext &candidate =
            guestThreads[(currentIndex + offset) % guestThreads.size()];
        if (candidate.alive && candidate.runnable &&
                candidate.debuggerId != currentThreadId) {
            return &candidate;
        }
    }
    return nullptr;
}

mach_port_t AllocateGuestThreadPort() {
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t result = mach_port_allocate(
        mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    if (result == KERN_SUCCESS) {
        result = mach_port_insert_right(
            mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
    }
    if (result != KERN_SUCCESS) {
        if (MACH_PORT_VALID(port)) {
            mach_port_destroy(mach_task_self(), port);
        }
        return MACH_PORT_NULL;
    }
    return port;
}

bool ParkCurrentGuestThread(
        GuestThreadWaitKind kind, u32 address, u32 wakeResult) {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread()) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    GuestThreadContext *current =
        FindGuestThread(CurrentGuestThreadId(), true);
    if (current == nullptr || !current->runnable) {
        return false;
    }

    current->runnable = false;
    current->waitKind = kind;
    current->waitAddress = address;
    current->wakeResult = wakeResult;
    current->waitSequence = guestNextWaitSequence.fetch_add(
        1, std::memory_order_relaxed);
    if (NextGuestThread() == nullptr) {
        current->runnable = true;
        current->waitKind = GuestThreadWaitKind::None;
        current->waitAddress = 0;
        current->wakeResult = 0;
        current->waitSequence = 0;
        return false;
    }
    guestThreadRotationRequested = true;
    return true;
}

size_t WakeGuestThreads(
        GuestThreadWaitKind kind, u32 address, bool wakeAll,
        mach_port_t targetThread = MACH_PORT_NULL) {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    size_t count = 0;
    for (;;) {
        GuestThreadContext *selected = nullptr;
        for (GuestThreadContext &thread : guestThreads) {
            if (!thread.alive || thread.runnable ||
                    thread.waitKind != kind ||
                    thread.waitAddress != address ||
                    (MACH_PORT_VALID(targetThread) &&
                     thread.threadPort != targetThread)) {
                continue;
            }
            if (selected == nullptr ||
                    thread.waitSequence < selected->waitSequence) {
                selected = &thread;
            }
        }
        if (selected == nullptr) {
            break;
        }

        selected->runnable = true;
        selected->waitKind = GuestThreadWaitKind::None;
        selected->waitAddress = 0;
        selected->waitSequence = 0;
        if (selected->savedValid) {
            selected->saved.regs[Reg::R0] =
                selected->wakeResult;
            selected->saved.cpsr &=
                ~(static_cast<u32>(1) << CARRY_BIT);
        }
        selected->wakeResult = 0;
        ++count;
        if (!wakeAll || MACH_PORT_VALID(targetThread)) {
            break;
        }
    }
    return count;
}

void RecordGuestPsynchPrepost(
        GuestThreadWaitKind kind, u32 address) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    for (GuestPsynchPrepost &prepost : guestPsynchPreposts) {
        if (prepost.kind == kind &&
                prepost.address == address) {
            ++prepost.count;
            return;
        }
    }
    guestPsynchPreposts.push_back({
        .kind = kind,
        .address = address,
        .count = 1,
    });
}

bool ConsumeGuestPsynchPrepost(
        GuestThreadWaitKind kind, u32 address) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    for (auto it = guestPsynchPreposts.begin();
            it != guestPsynchPreposts.end(); ++it) {
        if (it->kind != kind || it->address != address) {
            continue;
        }
        if (--it->count == 0) {
            guestPsynchPreposts.erase(it);
        }
        return true;
    }
    return false;
}

bool EnsureGuestWorkqueueWorker() {
    if (guestWorkqueueAllocation != 0) {
        return MACH_PORT_VALID(guestWorkqueueThreadPort);
    }
    if (guest_bsdthread_wqthread_start == 0 ||
            guest_bsdthread_pthread_size <= 0 ||
            guest_bsdthread_tsd_offset >=
            static_cast<u32>(guest_bsdthread_pthread_size)) {
        return false;
    }

    const u32 pthreadSize =
        (static_cast<u32>(guest_bsdthread_pthread_size) +
         DYN_PAGE_MASK) & ~DYN_PAGE_MASK;
    if (pthreadSize == 0 ||
            pthreadSize > UINT32_MAX - GuestWorkqueueGuardSize -
                GuestWorkqueueStackSize) {
        return false;
    }
    guestWorkqueueAllocationSize =
        GuestWorkqueueGuardSize + GuestWorkqueueStackSize + pthreadSize;
    guestWorkqueueAllocation = Dynarmic_mmap(
        0, guestWorkqueueAllocationSize, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (guestWorkqueueAllocation == UINT32_MAX) {
        guestWorkqueueAllocation = 0;
        guestWorkqueueAllocationSize = 0;
        return false;
    }

    guestWorkqueueStackBottom =
        guestWorkqueueAllocation + GuestWorkqueueGuardSize;
    guestWorkqueuePthread =
        guestWorkqueueStackBottom + GuestWorkqueueStackSize;
    kern_return_t portResult = mach_port_allocate(
        mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
        &guestWorkqueueThreadPort);
    if (portResult == KERN_SUCCESS) {
        portResult = mach_port_insert_right(
            mach_task_self(), guestWorkqueueThreadPort,
            guestWorkqueueThreadPort, MACH_MSG_TYPE_MAKE_SEND);
    }
    if (portResult != KERN_SUCCESS) {
        if (MACH_PORT_VALID(guestWorkqueueThreadPort)) {
            mach_port_destroy(
                mach_task_self(), guestWorkqueueThreadPort);
        }
        guestWorkqueueThreadPort = MACH_PORT_NULL;
        Dynarmic_munmap(
            guestWorkqueueAllocation, guestWorkqueueAllocationSize);
        guestWorkqueueAllocation = 0;
        guestWorkqueueAllocationSize = 0;
        guestWorkqueueStackBottom = 0;
        guestWorkqueuePthread = 0;
        return false;
    }
    if (guestWorkqueueThreadSelfId == 0) {
        guestWorkqueueThreadSelfId = AllocateGuestThreadSelfId();
    }
    return true;
}

bool PrepareGuestWorkqueueUpcall(const GuestWorkqueueDelivery *delivery,
                                 u32 priority) {
    if (!EnsureGuestWorkqueueWorker() || guestWorkqueueUpcallActive ||
            guestWorkqueuePendingUpcall.valid) {
        return false;
    }

    const u32 eventList = guestWorkqueuePthread -
        static_cast<u32>(GuestWorkqueueEventCapacity *
                         sizeof(guest_kevent_qos_s));
    const u32 messageBuffer =
        eventList - static_cast<u32>(GuestWorkqueueMessageCapacity);
    const u32 stackPointer = (messageBuffer - 16) & ~0xfu;

    u32 upcallFlags =
        WQ_FLAG_THREAD_NEWSPI | WQ_FLAG_THREAD_TSD_BASE_SET;
    if (guestWorkqueueWorkerInitialized) {
        upcallFlags |= WQ_FLAG_THREAD_REUSE;
    }

    u32 eventListArgument = 0;
    u32 eventCount = 0;
    if (delivery != nullptr) {
        guest_kevent_qos_s event = delivery->event;
        if (delivery->message.size() > GuestWorkqueueMessageCapacity) {
            return false;
        }
        if (!delivery->message.empty()) {
            if (Dynarmic_mem_1write(
                    messageBuffer, delivery->message.size(),
                    reinterpret_cast<char *>(
                        const_cast<uint8_t *>(
                            delivery->message.data()))) != 0) {
                return false;
            }
            event.ext[0] = messageBuffer;
            event.ext[1] = delivery->message.size();
        }
        if (Dynarmic_mem_1write(
                eventList, sizeof(event),
                reinterpret_cast<char *>(&event)) != 0) {
            return false;
        }
        eventListArgument = eventList;
        eventCount = 1;
        upcallFlags |= WQ_FLAG_THREAD_KEVENT;
        priority = static_cast<u32>(event.qos);
        if (delivery->eventManager) {
            upcallFlags |= WQ_FLAG_THREAD_EVENT_MANAGER;
            priority = guestWorkqueueEventManagerPriority;
        }
    }
    if ((priority & PTHREAD_PRIORITY_OVERCOMMIT_FLAG) != 0) {
        upcallFlags |= WQ_FLAG_THREAD_OVERCOMMIT;
    }
    upcallFlags |= GuestWorkqueueQosClass(priority);

    guestWorkqueuePendingUpcall = {
        .eventList = eventListArgument,
        .eventCount = eventCount,
        .stackPointer = stackPointer,
        .flags = upcallFlags,
        .valid = true,
    };
    WORKQUEUE_TRACE(
        "LC32: prepared workqueue upcall events=%u flags=0x%x "
        "sp=0x%x\n",
        eventCount, upcallFlags, stackPointer);
    return true;
}

bool NextGuestWorkqueueEvent(GuestWorkqueueDelivery &delivery) {
    for (size_t i = 0; i < guestWorkqueueKevents.size(); ++i) {
        GuestWorkqueueKevent &registered = guestWorkqueueKevents[i];
        if (!registered.enabled) {
            continue;
        }

        if (registered.event.filter == EVFILT_USER &&
                registered.triggered) {
            delivery = {};
            delivery.event = registered.event;
            delivery.event.fflags = NOTE_TRIGGER;
            delivery.eventManager =
                (registered.event.qos &
                 PTHREAD_PRIORITY_EVENT_MANAGER_FLAG) != 0;
            registered.triggered = false;
            if ((registered.event.flags & EV_DISPATCH) != 0) {
                registered.enabled = false;
            }
            return true;
        }
        if (registered.event.filter != EVFILT_MACHPORT) {
            continue;
        }

        delivery = {};
        delivery.event = registered.event;
        delivery.eventManager =
            (registered.event.qos &
             PTHREAD_PRIORITY_EVENT_MANAGER_FLAG) != 0;

        mach_msg_return_t result;
        if ((registered.event.fflags & MACH_RCV_MSG) == 0) {
            /*
             * Without MACH_RCV_MSG, EVFILT_MACHPORT only reports readiness.
             * Deliberately use a 20-byte LARGE receive: that is sufficient
             * for Mach's size/identity copyout but smaller than every valid
             * message header, so the queued XPC message is not consumed.
             */
            mach_msg_header_t probe = {};
            constexpr mach_msg_size_t ProbeSize =
                sizeof(mach_msg_header_t) - sizeof(mach_msg_id_t);
            result = mach_msg(
                &probe,
                MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_LARGE |
                    MACH_RCV_LARGE_IDENTITY,
                0, ProbeSize,
                static_cast<mach_port_t>(registered.event.ident),
                MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
            if (result == MACH_RCV_TIMED_OUT) {
                continue;
            }
            if (result != MACH_RCV_TOO_LARGE) {
                fprintf(stderr,
                    "LC32: workqueue probe on port 0x%llx failed: 0x%x\n",
                    registered.event.ident, result);
                registered.enabled = false;
                continue;
            }
            delivery.event.data = static_cast<int64_t>(
                MACH_PORT_VALID(probe.msgh_local_port)
                    ? probe.msgh_local_port
                    : static_cast<mach_port_t>(registered.event.ident));
            delivery.event.ext[0] = 0;
            delivery.event.ext[1] = 0;
        } else {
            std::vector<uint8_t> buffer(
                GuestWorkqueueMessageCapacity);
            auto *header =
                reinterpret_cast<mach_msg_header_t *>(buffer.data());
            const mach_msg_option_t options =
                static_cast<mach_msg_option_t>(
                    registered.event.fflags) |
                MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_LARGE |
                MACH_RCV_LARGE_IDENTITY;
            result = mach_msg(
                header, options, 0,
                static_cast<mach_msg_size_t>(buffer.size()),
                static_cast<mach_port_t>(registered.event.ident),
                MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
            if (result == MACH_RCV_TIMED_OUT) {
                continue;
            }
            if (result == MACH_RCV_TOO_LARGE) {
                delivery.event.fflags = MACH_RCV_TOO_LARGE;
                delivery.event.data =
                    static_cast<int64_t>(header->msgh_local_port);
                delivery.event.ext[0] = 0;
                delivery.event.ext[1] = header->msgh_size;
            } else if (result == MACH_MSG_SUCCESS) {
                const size_t roundedMessageSize =
                    (static_cast<size_t>(header->msgh_size) + 3) & ~3u;
                size_t receivedExtent = roundedMessageSize;
                if (roundedMessageSize +
                        sizeof(mach_msg_trailer_t) <= buffer.size()) {
                    const auto *trailer =
                        reinterpret_cast<const mach_msg_trailer_t *>(
                            buffer.data() + roundedMessageSize);
                    if (trailer->msgh_trailer_size <=
                            buffer.size() - roundedMessageSize) {
                        receivedExtent += trailer->msgh_trailer_size;
                    }
                }
                buffer.resize(receivedExtent);
                delivery.event.fflags = MACH_MSG_SUCCESS;
                delivery.event.data = MACH_PORT_NULL;
                delivery.message = std::move(buffer);
            } else {
                fprintf(stderr,
                    "LC32: workqueue receive on port 0x%llx failed: 0x%x\n",
                    registered.event.ident, result);
                registered.enabled = false;
                continue;
            }
        }

        const bool oneShot =
            (registered.event.flags & EV_ONESHOT) != 0;
        if (oneShot) {
            delivery.event.flags |= EV_DELETE;
            guestWorkqueueKevents.erase(
                guestWorkqueueKevents.begin() + i);
        } else if ((registered.event.flags & EV_DISPATCH) != 0) {
            registered.enabled = false;
        }
        return true;
    }
    return false;
}

} // anonymous namespace

static void InvalidateAllGuestJits(
        u32 address, size_t size) {
    if (size == 0) {
        return;
    }
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? sharedHandle.cb->cpu
        : nullptr;
    if (mainJit != nullptr) {
        mainJit->InvalidateCacheRange(
            address, size);
    }
    std::lock_guard<std::mutex> lock(
        nativeGuestJitMutex);
    for (NativeGuestJit *runtime : nativeGuestJits) {
        if (runtime != nullptr &&
                runtime->jit != nullptr &&
                runtime->jit != mainJit) {
            runtime->jit->InvalidateCacheRange(
                address, size);
        }
    }
}

static void HaltAllGuestJits(
        Dynarmic::HaltReason reason) {
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? sharedHandle.cb->cpu
        : nullptr;
    if (mainJit != nullptr) {
        mainJit->HaltExecution(reason);
    }
    std::lock_guard<std::mutex> lock(
        nativeGuestJitMutex);
    for (NativeGuestJit *runtime : nativeGuestJits) {
        if (runtime != nullptr &&
                runtime->jit != nullptr &&
                runtime->jit != mainJit) {
            runtime->jit->HaltExecution(reason);
        }
    }
}

struct NativeGuestThreadStart {
    gdb_thread_id_t debuggerId;
    NativeGuestJit *runtime;
};

class NativeGuestAutoreleasePool {
public:
    NativeGuestAutoreleasePool() {
        using Push = void *(*)();
        static Push push = reinterpret_cast<Push>(
            dlsym(RTLD_DEFAULT, "objc_autoreleasePoolPush"));
        if (push != nullptr) {
            token = push();
        }
    }

    ~NativeGuestAutoreleasePool() {
        using Pop = void (*)(void *);
        static Pop pop = reinterpret_cast<Pop>(
            dlsym(RTLD_DEFAULT, "objc_autoreleasePoolPop"));
        if (token != nullptr && pop != nullptr) {
            pop(token);
        }
    }

    NativeGuestAutoreleasePool(
        const NativeGuestAutoreleasePool &) = delete;
    NativeGuestAutoreleasePool &operator=(
        const NativeGuestAutoreleasePool &) = delete;

private:
    void *token = nullptr;
};

static NativeGuestJit *CreateNativeGuestJit(
        const context32 &initial, size_t processorId) {
    auto *runtime = new NativeGuestJit();
    runtime->processorId = processorId;
    runtime->callbacks =
        new DynarmicCallbacks32(sharedHandle.memory);

    Dynarmic::A32::UserConfig config;
    config.callbacks = runtime->callbacks;
    config.coprocessors[15] = runtime->callbacks->cp15;
    config.processor_id = processorId;
    config.global_monitor = sharedHandle.monitor;
    config.always_little_endian = false;
    config.wall_clock_cntpct = true;
    config.check_halt_on_memory_access = true;
    config.define_unpredictable_behaviour = true;
    // A separate cache is required for every JIT. Keep the experiment's
    // per-pthread footprint well below Dynarmic's 128 MiB default.
    config.code_cache_size = 16 * 1024 * 1024;

    runtime->callbacks->num_page_table_entries =
        sharedHandle.num_page_table_entries;
    runtime->callbacks->page_table =
        sharedHandle.page_table;
    if (sharedHandle.page_table != nullptr) {
        config.page_table = reinterpret_cast<
            std::array<std::uint8_t *,
                Dynarmic::A32::UserConfig::NUM_PAGE_TABLE_ENTRIES> *>(
                    sharedHandle.page_table);
        config.absolute_offset_page_table = false;
        config.detect_misaligned_access_via_page_table =
            16 | 32 | 64 | 128;
        config.only_detect_misalignment_via_page_table_on_page_boundary =
            true;
    }

    try {
        runtime->jit =
            new Dynarmic::A32::Jit(config);
        runtime->cpsr =
            new DynarmicCpsr(runtime->jit);
    } catch (const std::exception &exception) {
        fprintf(stderr,
            "LC32: native guest JIT creation failed: %s\n",
            exception.what());
        if (runtime->jit != nullptr) {
            delete runtime->jit;
        }
        runtime->callbacks->destroy();
        delete runtime;
        return nullptr;
    }

    runtime->callbacks->cpu = runtime->jit;
    runtime->callbacks->cpsr = runtime->cpsr;
    runtime->jit->Regs() = initial.regs;
    runtime->jit->ExtRegs() = initial.extRegs;
    runtime->jit->SetCpsr(initial.cpsr);
    runtime->jit->SetFpscr(initial.fpscr);
    runtime->callbacks->cp15->uro = initial.uro;
    runtime->jit->ClearExclusiveState();

    {
        std::lock_guard<std::mutex> lock(
            nativeGuestJitMutex);
        nativeGuestJits.push_back(runtime);
    }
    return runtime;
}

static void DestroyNativeGuestJit(
        NativeGuestJit *runtime) {
    if (runtime == nullptr) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(
            nativeGuestJitMutex);
        nativeGuestJits.erase(std::remove(
            nativeGuestJits.begin(), nativeGuestJits.end(),
            runtime), nativeGuestJits.end());
    }
    if (sharedHandle.monitor != nullptr &&
            runtime->processorId <
                MaxNativeGuestProcessors) {
        sharedHandle.monitor->ClearProcessor(
            runtime->processorId);
    }
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        guestProcessorIdsInUse &=
            ~(uint64_t{1} << runtime->processorId);
    }
    delete runtime->cpsr;
    delete runtime->jit;
    runtime->callbacks->destroy();
    delete runtime;
}

static void *RunNativeGuestThread(void *opaque) {
    std::unique_ptr<NativeGuestThreadStart> start(
        static_cast<NativeGuestThreadStart *>(opaque));
    NativeGuestJit *runtime = start->runtime;
    {
        std::unique_lock<std::mutex> lock(
            runtime->startMutex);
        runtime->startCondition.wait(lock, [&] {
            return runtime->startAllowed;
        });
    }

    threadHandle.jit = runtime->jit;
    threadHandle.cpsr = runtime->cpsr;
    threadHandle.cb = runtime->callbacks;
    nativeGuestThreadId = start->debuggerId;
    nativeGuestThreadRetiring = false;
    runtime->hostMachThread =
        pthread_mach_thread_np(pthread_self());

    fprintf(stderr,
        "LC32: native guest-thread=%llu running on "
        "host-thread=0x%x processor=%zu\n",
        start->debuggerId, runtime->hostMachThread,
        runtime->processorId);

    {
        /*
         * Unlike NSThread and libdispatch workers, a raw host pthread has no
         * Objective-C autorelease pool. Guest code can enter the host bridge
         * from this thread, so keep a pool alive while its JIT is running.
         * Drain it before clearing TLS or destroying the per-thread runtime.
         */
        NativeGuestAutoreleasePool autoreleasePool;
        const Dynarmic::HaltReason reason =
            Dynarmic_emu_1resume();
        if (!nativeGuestThreadRetiring) {
            fprintf(stderr,
                "LC32: native guest-thread=%llu stopped "
                "without bsdthread_terminate (reason=0x%llx)\n",
                start->debuggerId,
                static_cast<unsigned long long>(reason));
        }

        {
            std::lock_guard<std::recursive_mutex> lock(
                guestThreadMutex);
            if (GuestThreadContext *thread =
                    FindGuestThread(start->debuggerId, false)) {
                thread->alive = false;
                thread->runnable = false;
                thread->savedValid = false;
                thread->nativeJit = nullptr;
            }
        }
    }

    threadHandle = {};
    nativeGuestThreadId = 0;
    DestroyNativeGuestJit(runtime);
    return nullptr;
}

static u32 GuestBsdthreadCreate(
        u32 function, u32 argument, u32 stack, u32 pthread,
        u32 flags) {
    EnsureGuestThreadRegistry();
    if (guest_bsdthread_thread_start == 0 ||
            guest_bsdthread_pthread_size <= 0 ||
            function == 0 || stack == 0) {
        return return_with_carry_direct(EINVAL, true);
    }

    const bool custom = (flags & PTHREAD_START_CUSTOM) != 0;
    u32 allocationAddress = 0;
    u32 allocationSize = 0;
    u32 stackTop = stack;
    u32 pthreadAddress = pthread;

    if (!custom) {
        const u64 pthreadSize =
            (static_cast<u64>(guest_bsdthread_pthread_size) +
             DYN_PAGE_MASK) & ~static_cast<u64>(DYN_PAGE_MASK);
        const u64 requiredSize =
            static_cast<u64>(DYN_PAGE_SIZE) + stack + pthreadSize;
        const u64 roundedSize =
            (requiredSize + DYN_PAGE_MASK) &
            ~static_cast<u64>(DYN_PAGE_MASK);
        if (pthreadSize == 0 || roundedSize > UINT32_MAX ||
                roundedSize < requiredSize) {
            return return_with_carry_direct(EINVAL, true);
        }

        allocationSize = static_cast<u32>(roundedSize);
        allocationAddress = Dynarmic_mmap(
            0, allocationSize, PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (allocationAddress == UINT32_MAX) {
            return return_with_carry_direct(ENOMEM, true);
        }
        if (Dynarmic_mprotect(
                allocationAddress, DYN_PAGE_SIZE, PROT_NONE) != 0) {
            (void)Dynarmic_munmap(
                allocationAddress, allocationSize);
            return return_with_carry_direct(ENOMEM, true);
        }
        const u64 pthread64 =
            static_cast<u64>(allocationAddress) +
            DYN_PAGE_SIZE + stack;
        if (pthread64 > UINT32_MAX) {
            (void)Dynarmic_munmap(
                allocationAddress, allocationSize);
            return return_with_carry_direct(ENOMEM, true);
        }
        pthreadAddress = static_cast<u32>(pthread64);
        stackTop = pthreadAddress;
    } else if (pthreadAddress == 0) {
        return return_with_carry_direct(EINVAL, true);
    }

    if (stackTop < 16) {
        if (allocationAddress != 0) {
            (void)Dynarmic_munmap(
                allocationAddress, allocationSize);
        }
        return return_with_carry_direct(EINVAL, true);
    }

    const mach_port_t threadPort = AllocateGuestThreadPort();
    if (!MACH_PORT_VALID(threadPort)) {
        if (allocationAddress != 0) {
            (void)Dynarmic_munmap(
                allocationAddress, allocationSize);
        }
        return return_with_carry_direct(EAGAIN, true);
    }

    GuestThreadContext thread = {};
    size_t processorId = 0;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        thread.debuggerId =
            guestNextDebuggerThreadId++;
        if (NativeGuestThreadsEnabled()) {
            for (size_t candidate = 1;
                    candidate < MaxNativeGuestProcessors;
                    ++candidate) {
                const uint64_t bit =
                    uint64_t{1} << candidate;
                if ((guestProcessorIdsInUse & bit) == 0) {
                    guestProcessorIdsInUse |= bit;
                    processorId = candidate;
                    break;
                }
            }
            if (processorId == 0) {
                (void)mach_port_destroy(
                    mach_task_self(), threadPort);
                if (allocationAddress != 0) {
                    (void)Dynarmic_munmap(
                        allocationAddress, allocationSize);
                }
                return return_with_carry_direct(
                    EAGAIN, true);
            }
        }
    }
    thread.threadSelfId = AllocateGuestThreadSelfId();
    thread.pthreadAddress = pthreadAddress;
    thread.threadPort = threadPort;
    thread.allocationAddress = allocationAddress;
    thread.allocationSize = allocationSize;
    thread.alive = true;
    thread.runnable = true;
    thread.savedValid = true;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        if (GuestThreadContext *parent =
                FindGuestThread(CurrentGuestThreadId(), true)) {
            thread.signalMask = parent->signalMask;
        }
    }

    u32 childFlags = flags;
    if (guest_bsdthread_tsd_offset != 0 &&
            guest_bsdthread_tsd_offset <
                static_cast<u32>(guest_bsdthread_pthread_size) &&
            pthreadAddress <=
                UINT32_MAX - guest_bsdthread_tsd_offset) {
        thread.saved.uro =
            pthreadAddress + guest_bsdthread_tsd_offset;
        childFlags |= PTHREAD_START_TSD_BASE_SET;
    }
    thread.saved.cpsr =
        (guest_bsdthread_thread_start & 1) != 0
        ? 0x00000030
        : 0x000001d0;
    thread.saved.regs[Reg::R0] = pthreadAddress;
    thread.saved.regs[Reg::R1] = threadPort;
    thread.saved.regs[Reg::R2] = function;
    thread.saved.regs[Reg::R3] = argument;
    thread.saved.regs[Reg::R4] = stack;
    thread.saved.regs[Reg::R5] = childFlags;
    thread.saved.regs[Reg::R7] = 0;
    thread.saved.regs[Reg::SP] = stackTop - 16;
    thread.saved.regs[Reg::LR] = 0;
    thread.saved.regs[Reg::PC] =
        guest_bsdthread_thread_start & ~1u;

    fprintf(stderr,
        "LC32: bsdthread_create guest-thread=%llu self=0x%llx "
        "pthread=0x%x port=0x%x pc=0x%x sp=0x%x flags=0x%x\n",
        thread.debuggerId, thread.threadSelfId,
        thread.pthreadAddress, thread.threadPort,
        thread.saved.regs[Reg::PC], thread.saved.regs[Reg::SP],
        childFlags);

    if (NativeGuestThreadsEnabled()) {
        NativeGuestJit *runtime =
            CreateNativeGuestJit(
                thread.saved, processorId);
        if (runtime == nullptr) {
            {
                std::lock_guard<std::recursive_mutex> lock(
                    guestThreadMutex);
                guestProcessorIdsInUse &=
                    ~(uint64_t{1} << processorId);
            }
            (void)mach_port_destroy(
                mach_task_self(), threadPort);
            if (allocationAddress != 0) {
                (void)Dynarmic_munmap(
                    allocationAddress, allocationSize);
            }
            return return_with_carry_direct(
                EAGAIN, true);
        }
        thread.nativeJit = runtime;
        const gdb_thread_id_t debuggerId =
            thread.debuggerId;
        {
            std::lock_guard<std::recursive_mutex> lock(
                guestThreadMutex);
            guestThreads.push_back(
                std::move(thread));
        }

        auto *start = new NativeGuestThreadStart{
            .debuggerId = debuggerId,
            .runtime = runtime,
        };
        pthread_t hostThread;
        const int createResult = pthread_create(
            &hostThread, nullptr,
            RunNativeGuestThread, start);
        if (createResult != 0) {
            delete start;
            {
                std::lock_guard<std::recursive_mutex> lock(
                    guestThreadMutex);
                guestThreads.erase(std::remove_if(
                    guestThreads.begin(), guestThreads.end(),
                    [debuggerId](const GuestThreadContext &candidate) {
                        return candidate.debuggerId == debuggerId;
                    }), guestThreads.end());
            }
            DestroyNativeGuestJit(runtime);
            (void)mach_port_destroy(
                mach_task_self(), threadPort);
            if (allocationAddress != 0) {
                (void)Dynarmic_munmap(
                    allocationAddress, allocationSize);
            }
            return return_with_carry_direct(
                createResult, true);
        }
        runtime->hostThread = hostThread;
        (void)pthread_detach(hostThread);
        {
            std::lock_guard<std::mutex> lock(
                runtime->startMutex);
            runtime->startAllowed = true;
        }
        runtime->startCondition.notify_one();
    } else {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        guestThreads.push_back(std::move(thread));
    }
    return return_with_carry_direct(
        static_cast<int>(pthreadAddress), false);
}

static u32 GuestBsdthreadTerminate(
        u32 freeAddress, u32 freeSize, mach_port_t threadPort,
        mach_port_t joinSemaphore) {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread()) {
        return return_with_carry_direct(EINVAL, true);
    }

    const gdb_thread_id_t currentThreadId =
        CurrentGuestThreadId();
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        GuestThreadContext *current =
            FindGuestThread(currentThreadId, true);
        if (current == nullptr || current->debuggerId == 1) {
            return return_with_carry_direct(EINVAL, true);
        }
    }

    if (freeAddress != 0 && freeSize != 0 &&
            Dynarmic_munmap(freeAddress, freeSize) != 0) {
        return return_with_carry_direct(EINVAL, true);
    }

    if (MACH_PORT_VALID(joinSemaphore)) {
        const kern_return_t result =
            semaphore_signal_trap(joinSemaphore);
        if (result != KERN_SUCCESS) {
            fprintf(stderr,
                "LC32: bsdthread_terminate join semaphore 0x%x "
                "failed: 0x%x\n",
                joinSemaphore, result);
        }
    }

    mach_port_t currentPort = MACH_PORT_NULL;
    gdb_thread_id_t debuggerId = 0;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        GuestThreadContext *current =
            FindGuestThread(currentThreadId, false);
        if (current == nullptr) {
            return return_with_carry_direct(EINVAL, true);
        }
        currentPort = current->threadPort;
        debuggerId = current->debuggerId;
        current->threadPort = MACH_PORT_NULL;
        current->alive = false;
        current->runnable = false;
        current->savedValid = false;
    }

    if (MACH_PORT_VALID(threadPort) &&
            threadPort != currentPort) {
        fprintf(stderr,
            "LC32: bsdthread_terminate port mismatch "
            "argument=0x%x current=0x%x\n",
            threadPort, currentPort);
    }
    if (MACH_PORT_VALID(currentPort)) {
        (void)mach_port_destroy(
            mach_task_self(), currentPort);
    }

    fprintf(stderr,
        "LC32: bsdthread_terminate guest-thread=%llu "
        "free=0x%x+0x%x\n",
        debuggerId, freeAddress, freeSize);
    if (NativeGuestThreadIsCurrent()) {
        nativeGuestThreadRetiring = true;
        if (threadHandle.jit->IsExecuting()) {
            threadHandle.jit->HaltExecution(
                LC32HaltReasonExit);
        }
        return return_with_carry_direct(0, false);
    }
    guestThreadCurrentRetiring = true;
    guestThreadRotationRequested = true;
    if (LiveGuestThreadCount() == 0) {
        guestThreadCurrentRetiring = false;
        guestThreadRotationRequested = false;
        if (threadHandle.jit->IsExecuting()) {
            threadHandle.jit->HaltExecution(
                LC32HaltReasonExit);
        }
    }
    return return_with_carry_direct(0, false);
}

static void GuestThreadRequestRotation() {
    EnsureGuestThreadRegistry();
    if (NativeGuestThreadIsCurrent()) {
        return;
    }
    if (guestThreadCurrentRetiring || guestSingleStepping ||
            GuestWorkqueueActiveForCurrentThread() ||
            GuestWorkqueueTransitionPending() ||
            LiveGuestThreadCount() <= 1) {
        return;
    }
    guestThreadRotationRequested = NextGuestThread() != nullptr;
}

static bool GuestThreadCanYieldBeforeBlocking() {
    EnsureGuestThreadRegistry();
    if (NativeGuestThreadIsCurrent()) {
        return false;
    }
    return !GuestWorkqueueActiveForCurrentThread() &&
        NextGuestThread() != nullptr;
}

static bool GuestThreadYieldBeforeBlocking() {
    if (!GuestThreadCanYieldBeforeBlocking()) {
        return false;
    }
    if (!guestSingleStepping) {
        guestThreadRotationRequested = true;
    }
    return true;
}

static bool GuestThreadTransitionPending() {
    if (NativeGuestThreadIsCurrent()) {
        return false;
    }
    return guestThreadRotationRequested;
}

static bool HandleGuestThreadTransition() {
    if (NativeGuestThreadIsCurrent()) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    if (!guestThreadRotationRequested ||
            GuestWorkqueueActiveForCurrentThread() ||
            threadHandle.jit == nullptr ||
            threadHandle.cb == nullptr) {
        return false;
    }

    GuestThreadContext *current =
        FindGuestThread(guestCurrentThreadId, false);
    GuestThreadContext *next = NextGuestThread();
    if (current == nullptr || next == nullptr ||
            !next->savedValid) {
        guestThreadRotationRequested = false;
        guestThreadCurrentRetiring = false;
        return false;
    }

    if (!guestThreadCurrentRetiring) {
        SaveGuestContext(current->saved);
        current->savedValid = true;
    }
    LoadGuestContext(next->saved);
    THREAD_TRACE(
        "LC32: switched guest-thread %llu -> %llu pc=0x%x\n",
        guestCurrentThreadId, next->debuggerId,
        threadHandle.jit->Regs()[Reg::PC]);
    guestCurrentThreadId = next->debuggerId;
    guestThreadRotationRequested = false;
    guestThreadCurrentRetiring = false;
    return true;
}

static u64 GuestCurrentThreadSelfId() {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread()) {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        return guestWorkqueueThreadSelfId;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    GuestThreadContext *current =
        FindGuestThread(CurrentGuestThreadId(), true);
    return current != nullptr
        ? current->threadSelfId
        : __thread_selfid();
}

static mach_port_t GuestCurrentSyntheticThreadPort() {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread()) {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        return guestWorkqueueThreadPort;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    GuestThreadContext *current =
        FindGuestThread(CurrentGuestThreadId(), true);
    return current != nullptr ? current->threadPort : MACH_PORT_NULL;
}

static int GuestThreadSigmask(
        int how, u32 guestSet, u32 guestOldSet) {
    EnsureGuestThreadRegistry();
    const bool workqueue =
        GuestWorkqueueActiveForCurrentThread();
    std::recursive_mutex &mutex = workqueue
        ? guestWorkqueueMutex
        : guestThreadMutex;
    std::lock_guard<std::recursive_mutex> lock(mutex);
    u32 *mask = nullptr;
    if (workqueue) {
        mask = &guestWorkqueueSignalMask;
    } else if (GuestThreadContext *current =
            FindGuestThread(CurrentGuestThreadId(), true)) {
        mask = &current->signalMask;
    }
    if (mask == nullptr) {
        return EINVAL;
    }

    const u32 oldMask = *mask;
    if (guestOldSet != 0 &&
            Dynarmic_mem_1write(
                guestOldSet, sizeof(oldMask),
                reinterpret_cast<char *>(
                    const_cast<u32 *>(&oldMask))) != 0) {
        return EFAULT;
    }
    if (guestSet == 0) {
        return 0;
    }

    u32 set = 0;
    if (Dynarmic_mem_1read(
            guestSet, sizeof(set),
            reinterpret_cast<char *>(&set)) != 0) {
        return EFAULT;
    }
    switch (how) {
        case SIG_BLOCK:
            *mask |= set;
            break;
        case SIG_UNBLOCK:
            *mask &= ~set;
            break;
        case SIG_SETMASK:
            *mask = set;
            break;
        default:
            return EINVAL;
    }
    return 0;
}

static bool NativeGuestThreadIsCurrent() {
    return NativeGuestThreadsEnabled() &&
        nativeGuestThreadId != 0;
}

static bool GuestWorkqueueActiveForCurrentThread() {
    if (NativeGuestThreadIsCurrent()) {
        return guestWorkqueueOverlayCurrent;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    return guestWorkqueueUpcallActive;
}

static u32 WaitNativeGuestThread(
        GuestThreadWaitKind kind, u32 address,
        u32 wakeResult) {
    auto waiter = std::make_shared<NativeGuestWaiter>();
    waiter->kind = kind;
    waiter->address = address;
    waiter->threadPort = GuestCurrentSyntheticThreadPort();
    waiter->wakeResult = wakeResult;

    std::unique_lock<std::mutex> lock(nativeGuestWaitMutex);
    if (ConsumeGuestPsynchPrepost(kind, address)) {
        return return_with_carry_direct(
            static_cast<int>(wakeResult), false);
    }
    waiter->sequence = guestNextWaitSequence.fetch_add(
        1, std::memory_order_relaxed);
    nativeGuestWaiters.push_back(waiter);
    waiter->condition.wait(lock, [&] {
        return waiter->signaled;
    });
    nativeGuestWaiters.erase(std::remove(
        nativeGuestWaiters.begin(), nativeGuestWaiters.end(),
        waiter), nativeGuestWaiters.end());
    return return_with_carry_direct(
        static_cast<int>(waiter->wakeResult), false);
}

static size_t WakeNativeGuestThreadsLocked(
        GuestThreadWaitKind kind, u32 address, bool wakeAll,
        mach_port_t targetThread = MACH_PORT_NULL) {
    size_t count = 0;
    for (;;) {
        std::shared_ptr<NativeGuestWaiter> selected;
        for (const auto &waiter : nativeGuestWaiters) {
            if (waiter->signaled || waiter->kind != kind ||
                    waiter->address != address ||
                    (MACH_PORT_VALID(targetThread) &&
                     waiter->threadPort != targetThread)) {
                continue;
            }
            if (!selected ||
                    waiter->sequence < selected->sequence) {
                selected = waiter;
            }
        }
        if (!selected) {
            break;
        }
        selected->signaled = true;
        selected->condition.notify_one();
        ++count;
        if (!wakeAll || MACH_PORT_VALID(targetThread)) {
            break;
        }
    }
    return count;
}

static size_t WakeNativeGuestThreads(
        GuestThreadWaitKind kind, u32 address, bool wakeAll,
        mach_port_t targetThread = MACH_PORT_NULL) {
    std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
    return WakeNativeGuestThreadsLocked(
        kind, address, wakeAll, targetThread);
}

static u32 GuestPsynchMutexWait(
        u32 mutex, u32 generation) {
    const u32 wakeResult =
        (generation & ~0xffu) | 0x03u;
    if (NativeGuestThreadIsCurrent() &&
            !GuestWorkqueueActiveForCurrentThread()) {
        return WaitNativeGuestThread(
            GuestThreadWaitKind::Mutex, mutex, wakeResult);
    }
    if (ConsumeGuestPsynchPrepost(
            GuestThreadWaitKind::Mutex, mutex)) {
        return return_with_carry_direct(
            static_cast<int>(wakeResult), false);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Mutex, mutex, wakeResult)) {
        return return_with_carry_direct(0, false);
    }
    return return_with_carry_direct(EINTR, true);
}

static u32 GuestPsynchMutexDrop(u32 mutex) {
    const bool native = NativeGuestThreadIsCurrent();
    size_t woken;
    if (native) {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        woken = WakeNativeGuestThreadsLocked(
            GuestThreadWaitKind::Mutex, mutex, false);
        if (woken == 0) {
            RecordGuestPsynchPrepost(
                GuestThreadWaitKind::Mutex, mutex);
        }
    } else {
        woken = WakeGuestThreads(
            GuestThreadWaitKind::Mutex, mutex, false);
    }
    if (!native && woken == 0) {
        RecordGuestPsynchPrepost(
            GuestThreadWaitKind::Mutex, mutex);
    }
    return return_with_carry_direct(0, false);
}

static u32 GuestPsynchConditionWait(
        u32 condition, u32 mutex) {
    if (mutex != 0) {
        if (NativeGuestThreadIsCurrent()) {
            (void)WakeNativeGuestThreads(
                GuestThreadWaitKind::Mutex, mutex, false);
        } else {
            (void)WakeGuestThreads(
                GuestThreadWaitKind::Mutex, mutex, false);
        }
    }
    if (NativeGuestThreadIsCurrent() &&
            !GuestWorkqueueActiveForCurrentThread()) {
        return WaitNativeGuestThread(
            GuestThreadWaitKind::Condition, condition, 0x100);
    }
    if (ConsumeGuestPsynchPrepost(
            GuestThreadWaitKind::Condition, condition)) {
        return return_with_carry_direct(0x100, false);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Condition, condition, 0)) {
        return return_with_carry_direct(0, false);
    }
    return return_with_carry_direct(EINTR, true);
}

static u32 GuestPsynchConditionSignal(
        u32 condition, mach_port_t targetThread,
        bool broadcast) {
    const bool native = NativeGuestThreadIsCurrent();
    size_t woken;
    if (native) {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        woken = WakeNativeGuestThreadsLocked(
            GuestThreadWaitKind::Condition, condition,
            broadcast, targetThread);
        if (woken == 0 && !MACH_PORT_VALID(targetThread)) {
            RecordGuestPsynchPrepost(
                GuestThreadWaitKind::Condition, condition);
        }
    } else {
        woken = WakeGuestThreads(
            GuestThreadWaitKind::Condition, condition,
            broadcast, targetThread);
    }
    if (MACH_PORT_VALID(targetThread) && woken == 0) {
        return return_with_carry_direct(ESRCH, true);
    }
    if (!native && woken == 0 &&
            !MACH_PORT_VALID(targetThread)) {
        RecordGuestPsynchPrepost(
            GuestThreadWaitKind::Condition, condition);
    }
    const u64 update =
        static_cast<u64>(woken) * 0x100u;
    const u32 updateBits =
        static_cast<u32>(std::min<u64>(
            update, UINT32_MAX)) |
        (woken != 0 ? 0x01u : 0u);
    return return_with_carry_direct(
        static_cast<int>(updateBits), false);
}

static u32 GuestPsynchRwWait(u32 rwlock) {
    if (NativeGuestThreadIsCurrent() &&
            !GuestWorkqueueActiveForCurrentThread()) {
        return WaitNativeGuestThread(
            GuestThreadWaitKind::Rwlock, rwlock, 0);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Rwlock, rwlock, 0)) {
        return return_with_carry_direct(0, false);
    }
    return return_with_carry_direct(EINTR, true);
}

static u32 GuestPsynchRwUnlock(u32 rwlock) {
    if (NativeGuestThreadIsCurrent()) {
        (void)WakeNativeGuestThreads(
            GuestThreadWaitKind::Rwlock, rwlock, true);
    } else {
        (void)WakeGuestThreads(
            GuestThreadWaitKind::Rwlock, rwlock, true);
    }
    return return_with_carry_direct(0, false);
}

namespace {

constexpr u32 GuestUlCompareAndWait = 1;
constexpr u32 GuestUlUnfairLock = 2;
constexpr u32 GuestUlOpcodeMask = 0x000000ff;
constexpr u32 GuestUlfWakeAll = 0x00000100;
constexpr u32 GuestUlfWakeThread = 0x00000200;
constexpr u32 GuestUlfWaitWorkqDataContention = 0x00010000;
constexpr u32 GuestUlfNoErrno = 0x01000000;
constexpr u32 GuestUlfWaitMask =
    GuestUlfWaitWorkqDataContention | GuestUlfNoErrno;
constexpr u32 GuestUlfWakeMask =
    GuestUlfWakeAll | GuestUlfWakeThread | GuestUlfNoErrno;

static u32 GuestUlockReturn(
        int error, u32 flags, size_t successValue = 0) {
    if (error == 0) {
        return return_with_carry_direct(
            static_cast<int>(std::min<size_t>(
                successValue, INT32_MAX)),
            false);
    }
    if ((flags & GuestUlfNoErrno) != 0) {
        return return_with_carry_direct(-error, false);
    }
    return return_with_carry_direct(error, true);
}

static int ReadGuestUlockWord(u32 address, u32 &word) {
    if (address == 0 || (address & (sizeof(word) - 1)) != 0) {
        return EINVAL;
    }

    std::lock_guard<std::recursive_mutex> vmLock(guestVmMutex);
    auto *hostWord = static_cast<u32 *>(get_memory(address));
    if (hostWord == nullptr) {
        return EFAULT;
    }
    word = __atomic_load_n(hostWord, __ATOMIC_ACQUIRE);
    return 0;
}

static bool GuestUlockOpcodeValid(uint8_t opcode) {
    return opcode == GuestUlCompareAndWait ||
        opcode == GuestUlUnfairLock;
}

static size_t MatchingNativeUlockWaitersLocked(
        u32 address, uint8_t opcode) {
    return static_cast<size_t>(std::count_if(
        nativeGuestWaiters.begin(), nativeGuestWaiters.end(),
        [address, opcode](
                const std::shared_ptr<NativeGuestWaiter> &waiter) {
            return waiter->kind == GuestThreadWaitKind::Ulock &&
                waiter->address == address &&
                waiter->ulockOpcode == opcode;
        }));
}

static bool NativeUlockAddressHasOtherOpcodeLocked(
        u32 address, uint8_t opcode) {
    return std::any_of(
        nativeGuestWaiters.begin(), nativeGuestWaiters.end(),
        [address, opcode](
                const std::shared_ptr<NativeGuestWaiter> &waiter) {
            return waiter->kind == GuestThreadWaitKind::Ulock &&
                waiter->address == address &&
                waiter->ulockOpcode != opcode;
        });
}

static bool GuestUlockTargetThreadExists(mach_port_t target) {
    if (!MACH_PORT_VALID(target)) {
        return false;
    }
    EnsureGuestThreadRegistry();
    mach_port_t workqueueThreadPort = MACH_PORT_NULL;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        workqueueThreadPort = guestWorkqueueThreadPort;
    }
    if (target == workqueueThreadPort) {
        return true;
    }
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    return std::any_of(
        guestThreads.begin(), guestThreads.end(),
        [target](const GuestThreadContext &thread) {
            return thread.alive && thread.threadPort == target;
        });
}

} // namespace

static u32 GuestUlockWait(
        u32 operation, u32 address, u64 value, u32 timeout) {
    const uint8_t opcode =
        static_cast<uint8_t>(operation & GuestUlOpcodeMask);
    const u32 flags = operation & ~GuestUlOpcodeMask;
    if (!GuestUlockOpcodeValid(opcode) ||
            (flags & ~GuestUlfWaitMask) != 0) {
        return GuestUlockReturn(EINVAL, flags);
    }

    if (NativeGuestThreadIsCurrent() &&
            !GuestWorkqueueActiveForCurrentThread()) {
        auto waiter = std::make_shared<NativeGuestWaiter>();
        waiter->kind = GuestThreadWaitKind::Ulock;
        waiter->address = address;
        waiter->ulockOpcode = opcode;
        waiter->threadPort = GuestCurrentSyntheticThreadPort();

        std::unique_lock<std::mutex> lock(nativeGuestWaitMutex);
        if (NativeUlockAddressHasOtherOpcodeLocked(
                address, opcode)) {
            return GuestUlockReturn(EDOM, flags);
        }

        /*
         * The guest stores the unlocked value before entering ulock_wake.
         * Compare and enqueue while holding the same mutex used by wake so
         * that a wake cannot slip between those two operations and get lost.
         */
        u32 currentValue = 0;
        const int readError =
            ReadGuestUlockWord(address, currentValue);
        if (readError != 0) {
            return GuestUlockReturn(readError, flags);
        }
        if (static_cast<u64>(currentValue) != value) {
            return GuestUlockReturn(
                0, flags,
                MatchingNativeUlockWaitersLocked(
                    address, opcode));
        }

        waiter->sequence = guestNextWaitSequence.fetch_add(
            1, std::memory_order_relaxed);
        nativeGuestWaiters.push_back(waiter);
        bool woke = true;
        if (timeout == 0) {
            waiter->condition.wait(lock, [&] {
                return waiter->signaled;
            });
        } else {
            woke = waiter->condition.wait_for(
                lock, std::chrono::microseconds(timeout), [&] {
                    return waiter->signaled;
                });
        }

        nativeGuestWaiters.erase(std::remove(
            nativeGuestWaiters.begin(), nativeGuestWaiters.end(),
            waiter), nativeGuestWaiters.end());
        if (!woke) {
            return GuestUlockReturn(ETIMEDOUT, flags);
        }
        return GuestUlockReturn(
            0, flags,
            MatchingNativeUlockWaitersLocked(address, opcode));
    }

    u32 currentValue = 0;
    const int readError =
        ReadGuestUlockWord(address, currentValue);
    if (readError != 0) {
        return GuestUlockReturn(readError, flags);
    }
    if (static_cast<u64>(currentValue) != value) {
        return GuestUlockReturn(0, flags);
    }
    if (timeout != 0) {
        /*
         * Cooperative threads have no independent timer source. Returning a
         * timeout is preferable to parking forever when no guest can wake it.
         */
        return GuestUlockReturn(ETIMEDOUT, flags);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Ulock, address, 0)) {
        return GuestUlockReturn(0, flags);
    }
    return GuestUlockReturn(EINTR, flags);
}

static u32 GuestUlockWake(
        u32 operation, u32 address, u64 wakeValue) {
    const uint8_t opcode =
        static_cast<uint8_t>(operation & GuestUlOpcodeMask);
    const u32 flags = operation & ~GuestUlOpcodeMask;
    if (!GuestUlockOpcodeValid(opcode) ||
            (flags & ~GuestUlfWakeMask) != 0 ||
            (flags & (GuestUlfWakeAll |
                      GuestUlfWakeThread)) ==
                (GuestUlfWakeAll | GuestUlfWakeThread) ||
            address == 0) {
        return GuestUlockReturn(EINVAL, flags);
    }

    const bool targetWake =
        (flags & GuestUlfWakeThread) != 0;
    const mach_port_t target =
        static_cast<mach_port_t>(wakeValue);
    if (targetWake && !GuestUlockTargetThreadExists(target)) {
        return GuestUlockReturn(ESRCH, flags);
    }

    if (NativeGuestThreadIsCurrent()) {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        const bool otherOpcode =
            NativeUlockAddressHasOtherOpcodeLocked(
                address, opcode);
        const size_t matching =
            MatchingNativeUlockWaitersLocked(
                address, opcode);
        if (matching == 0) {
            return GuestUlockReturn(
                otherOpcode ? EDOM : ENOENT, flags);
        }

        size_t woken = 0;
        for (;;) {
            std::shared_ptr<NativeGuestWaiter> selected;
            for (const auto &waiter : nativeGuestWaiters) {
                if (waiter->kind != GuestThreadWaitKind::Ulock ||
                        waiter->address != address ||
                        waiter->ulockOpcode != opcode ||
                        waiter->signaled ||
                        (targetWake &&
                         waiter->threadPort != target)) {
                    continue;
                }
                if (!selected ||
                        waiter->sequence < selected->sequence) {
                    selected = waiter;
                }
            }
            if (!selected) {
                break;
            }
            selected->signaled = true;
            selected->condition.notify_one();
            ++woken;
            if ((flags & GuestUlfWakeAll) == 0 ||
                    targetWake) {
                break;
            }
        }
        if (targetWake && woken == 0) {
            return GuestUlockReturn(EALREADY, flags);
        }
        /*
         * A matching ulock object can temporarily contain only threads that
         * have been signaled but have not yet completed syscall cleanup. XNU
         * treats an additional non-targeted wake in that window as success.
         */
        return GuestUlockReturn(0, flags);
    }

    const size_t woken = WakeGuestThreads(
        GuestThreadWaitKind::Ulock, address,
        (flags & GuestUlfWakeAll) != 0,
        targetWake ? target : MACH_PORT_NULL);
    if (woken == 0) {
        return GuestUlockReturn(
            targetWake ? EALREADY : ENOENT, flags);
    }
    return GuestUlockReturn(0, flags);
}

static bool GuestContextTransitionPending() {
    return GuestWorkqueueTransitionPending() ||
        GuestThreadTransitionPending();
}

static bool HandleGuestContextTransition() {
    if (GuestWorkqueueTransitionPending()) {
        return HandleGuestWorkqueueTransition();
    }
    return HandleGuestThreadTransition();
}

static bool PumpGuestWorkqueue() {
    if (NativeGuestThreadIsCurrent() &&
            CurrentGuestThreadId() != 1) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    if (guestWorkqueueUpcallActive || !guest_workqueue_opened) {
        return false;
    }
    /*
     * Allocate the worker before consuming a request or Mach message.  A
     * setup failure must leave the work available for a later attempt.
     */
    if (!EnsureGuestWorkqueueWorker()) {
        return false;
    }

    /*
     * The emulator currently has one JIT context. Cooperatively run the work
     * that XNU would schedule concurrently. The syscall returns interrupted,
     * the outer execution loop runs exactly one worker upcall, and libsystem
     * retries the original receive after that worker parks.
     */
    while (!guestWorkqueueRequests.empty() &&
            guestWorkqueueRequests.front().remaining <= 0) {
        guestWorkqueueRequests.pop_front();
    }
    if (!guestWorkqueueRequests.empty()) {
        GuestWorkqueueRequest &request =
            guestWorkqueueRequests.front();
        const u32 priority = request.priority;
        WORKQUEUE_TRACE(
            "LC32: pumping root worker priority=0x%x remaining=%d\n",
            priority, request.remaining - 1);
        if (!PrepareGuestWorkqueueUpcall(nullptr, priority)) {
            return false;
        }
        --request.remaining;
        return true;
    }

    GuestWorkqueueDelivery delivery;
    if (!NextGuestWorkqueueEvent(delivery)) {
        return false;
    }
    WORKQUEUE_TRACE(
        "LC32: pumping event ident=0x%llx filter=%d data=0x%llx\n",
        delivery.event.ident, delivery.event.filter,
        static_cast<uint64_t>(delivery.event.data));
    return PrepareGuestWorkqueueUpcall(&delivery, 0);
}

static bool HandleGuestWorkqueueTransition() {
    if (NativeGuestThreadIsCurrent() &&
            CurrentGuestThreadId() != 1) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    DynarmicCallbacks32 *callbacks = threadHandle.cb;
    if (guestWorkqueuePendingUpcall.valid ||
            guestWorkqueueRestoreRequested) {
        WORKQUEUE_TRACE(
            "LC32: workqueue transition pending=%d restore=%d "
            "active=%d jit=%p callbacks=%p\n",
            guestWorkqueuePendingUpcall.valid,
            guestWorkqueueRestoreRequested,
            guestWorkqueueUpcallActive, jit, callbacks);
    }
    if (jit == nullptr || callbacks == nullptr) {
        return false;
    }

    if (guestWorkqueueRestoreRequested) {
        guestWorkqueueRestoreRequested = false;
        if (!guestWorkqueueUpcallActive ||
                !guestWorkqueueWaitingContextValid) {
            return false;
        }
        LoadGuestContext(guestWorkqueueWaitingContext);
        guestWorkqueueWaitingContextValid = false;
        guestWorkqueueWaitingThreadId = 0;
        guestWorkqueueUpcallActive = false;
        guestWorkqueueOverlayCurrent = false;
        WORKQUEUE_TRACE(
            "LC32: restored waiting context pc=0x%x\n",
            jit->Regs()[Reg::PC]);
        return true;
    }

    if (!guestWorkqueuePendingUpcall.valid ||
            guestWorkqueueUpcallActive) {
        return false;
    }

    SaveGuestContext(guestWorkqueueWaitingContext);
    guestWorkqueueWaitingContextValid = true;
    guestWorkqueueWaitingThreadId = CurrentGuestThreadId();
    {
        std::lock_guard<std::recursive_mutex> threadLock(
            guestThreadMutex);
        if (GuestThreadContext *thread =
                FindGuestThread(CurrentGuestThreadId(), true)) {
            guestWorkqueueSignalMask = thread->signalMask;
        }
    }

    const GuestWorkqueuePendingUpcall upcall =
        guestWorkqueuePendingUpcall;
    guestWorkqueuePendingUpcall.valid = false;
    jit->Regs().fill(0);
    jit->ExtRegs().fill(0);
    jit->SetFpscr(0);
    jit->SetCpsr((guest_bsdthread_wqthread_start & 1) != 0
        ? 0x00000030
        : 0x000001d0);
    jit->Regs()[Reg::R0] = guestWorkqueuePthread;
    jit->Regs()[Reg::R1] = guestWorkqueueThreadPort;
    jit->Regs()[Reg::R2] = guestWorkqueueStackBottom;
    jit->Regs()[Reg::R3] = upcall.eventList;
    jit->Regs()[Reg::R4] = upcall.flags;
    jit->Regs()[Reg::R5] = upcall.eventCount;
    jit->Regs()[Reg::SP] = upcall.stackPointer;
    jit->Regs()[Reg::PC] =
        guest_bsdthread_wqthread_start & ~1u;
    callbacks->cp15->uro =
        guestWorkqueuePthread + guest_bsdthread_tsd_offset;

    guestWorkqueueWorkerInitialized = true;
    guestWorkqueueUpcallActive = true;
    guestWorkqueueOverlayCurrent = true;
    WORKQUEUE_TRACE(
        "LC32: entered workqueue upcall pc=0x%x self=0x%x "
        "tsd=0x%x flags=0x%x\n",
        jit->Regs()[Reg::PC], guestWorkqueuePthread,
        callbacks->cp15->uro, upcall.flags);
    return true;
}

static bool GuestWorkqueueTransitionPending() {
    if (NativeGuestThreadIsCurrent() &&
            CurrentGuestThreadId() != 1) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    return guestWorkqueuePendingUpcall.valid ||
        guestWorkqueueRestoreRequested;
}

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    nativeInitialize
 * Signature: (Z)J
 */
bool Dynarmic_nativeInitialize() {
    sharedHandle.memory = kh_init(memory);
    if(sharedHandle.memory == NULL) {
        fprintf(stderr, "kh_init memory failed\n");
        abort();
        return 0;
    }
    int ret = kh_resize(memory, sharedHandle.memory, 0x1000);
    if(ret == -1) {
        fprintf(stderr, "kh_resize memory failed\n");
        abort();
        return 0;
    }
    sharedHandle.monitor =
        new Dynarmic::ExclusiveMonitor(
            MaxNativeGuestProcessors);
    {
        DynarmicCallbacks32 *callbacks = new DynarmicCallbacks32(sharedHandle.memory);
        
        Dynarmic::A32::UserConfig config;
        config.callbacks = callbacks;
        config.coprocessors[15] = callbacks->cp15;
        config.processor_id = 0;
        config.global_monitor = sharedHandle.monitor;
        config.always_little_endian = false;
        config.wall_clock_cntpct = true;
        config.check_halt_on_memory_access = true;
        //    config.page_table_pointer_mask_bits = DYN_PAGE_BITS;
        
        //    config.unsafe_optimizations = true;
        //    config.optimizations |= Dynarmic::OptimizationFlag::Unsafe_UnfuseFMA;
        //    config.optimizations |= Dynarmic::OptimizationFlag::Unsafe_ReducedErrorFP;
        
        sharedHandle.num_page_table_entries = Dynarmic::A32::UserConfig::NUM_PAGE_TABLE_ENTRIES;
        size_t size = sharedHandle.num_page_table_entries * sizeof(void*);
        sharedHandle.page_table = (void **)mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
        if(sharedHandle.page_table == MAP_FAILED) {
            fprintf(stderr, "nativeInitialize mmap failed[%s->%s:%d] size=0x%zx, errno=%d, msg=%s\n", __FILE__, __func__, __LINE__, size, errno, strerror(errno));
            sharedHandle.page_table = NULL;
        } else {
            callbacks->num_page_table_entries = sharedHandle.num_page_table_entries;
            callbacks->page_table = sharedHandle.page_table;
            
            // Unpredictable instructions
            config.define_unpredictable_behaviour = true;
            
            // Memory
            config.page_table = reinterpret_cast<std::array<std::uint8_t*, Dynarmic::A32::UserConfig::NUM_PAGE_TABLE_ENTRIES>*>(sharedHandle.page_table);
            config.absolute_offset_page_table = false;
            config.detect_misaligned_access_via_page_table = 16 | 32 | 64 | 128;
            config.only_detect_misalignment_via_page_table_on_page_boundary = true;
        }
        
        sharedHandle.cb = callbacks;
        threadHandle.jit = new Dynarmic::A32::Jit(config);
        threadHandle.cpsr = new DynarmicCpsr(threadHandle.jit);
        threadHandle.cb = callbacks;
        sharedHandle.fs = new LC32Filesystem();
        callbacks->cpu = threadHandle.jit;
        callbacks->cpsr = threadHandle.cpsr;
    }
    return true;
}

static void ReleaseMemoryPageBacking(t_memory_page page) {
    if (page == nullptr || page->backing == nullptr) {
        return;
    }
    t_memory_backing backing = page->backing;
    page->backing = nullptr;
    assert(backing->references != 0);
    if (--backing->references != 0) {
        return;
    }
    if (munmap(backing->addr, backing->size) != 0) {
        fprintf(stderr,
            "munmap backing failed[%s->%s:%d]: "
            "addr=%p, size=0x%zx, errno=%d\n",
            __FILE__, __func__, __LINE__,
            backing->addr, backing->size, errno);
    }
    free(backing);
}

void Dynarmic_nativeDestroy() {
    khash_t(memory) *memory = sharedHandle.memory;
    for (khiter_t k = kh_begin(memory); k < kh_end(memory); k++) {
        if(kh_exist(memory, k)) {
            t_memory_page page = kh_value(memory, k);
            ReleaseMemoryPageBacking(page);
            free(page);
        }
    }
    kh_destroy(memory, memory);
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
        jit->ClearCache();
        jit->Reset();
        delete jit;
    }
    DynarmicCallbacks32 *cb = sharedHandle.cb;
    if(cb) {
        cb->destroy();
    }
    if(sharedHandle.page_table) {
        int ret = munmap(sharedHandle.page_table, sharedHandle.num_page_table_entries * sizeof(void*));
        if(ret != 0) {
            fprintf(stderr, "munmap failed[%s->%s:%d]: page_table=%p, ret=%d\n", __FILE__, __func__, __LINE__, sharedHandle.page_table, ret);
        }
    }
    delete sharedHandle.monitor;
}

int Dynarmic_munmap(u64 address, u64 size) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
        u64 idx = vaddr >> DYN_PAGE_BITS;
        khiter_t k = kh_get(memory, memory, vaddr);
        if(k == kh_end(memory)) {
            fprintf(stderr, "mem_unmap failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
            errno = ENOMEM;
            return -1;
        }
        if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[idx], nullptr,
                __ATOMIC_RELEASE);
        }
        t_memory_page page = kh_value(memory, k);
        /*
         * Guest pages are 4 KiB while Apple Silicon host VM pages are
         * 16 KiB. Anonymous guest mappings therefore share one host mmap
         * backing object and release it only after every guest slice has
         * gone away. Per-slice munmap would also remove adjacent live guest
         * pages (notably the pthread structure beside a retired stack).
         */
        ReleaseMemoryPageBacking(page);
        free(page);
        kh_del(memory, memory, k);
    }
    return 0;
}

u64 Dynarmic_mem_reserve(u64 address, u64 size, bool fixed, u64 mask) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    
    // Don't allocate anything below 16MB region to better catch bad accesses
    if (address < 0x10000000) { // DYN_PAGE_SIZE
        if (fixed) {
            printf("Dynarmic_mem_reserve: refusing to reserve below 16MB range\n");
            return -1;
        } else {
            address += 0x10000000;
        }
    }
    
    address = (address + mask) &~ mask;
    khash_t(memory) *memory = sharedHandle.memory;
    int ret;
    if (fixed) {
        for(u64 vaddr = address; vaddr < address + size;
                vaddr += DYN_PAGE_SIZE) {
            khiter_t k;
            if((k = kh_get(memory, memory, vaddr)) != kh_end(memory)) {
#if 0
                pthread_mutex_unlock(&mutex);
                printf("Dynarmic_mem_reserve: cannot reserve fixed address 0x%llx. It is bound to 0x%llx\n", address, kh_value(memory, k)->addr);
                return -1;
#else
                //printf("Dynarmic_mem_reserve: force-remapping at address 0x%llx\n", address);
                // FIXME: what should I really do here? Unmap will cause subsequent 3 pages (remember we're running 4k binaries on 16k) to be unmapped aswell
                //Dynarmic_munmap(vaddr, DYN_PAGE_SIZE);
#endif
            }
        }
    } else {
        /*
         * A Mach VM alignment mask constrains every candidate, not just the
         * initial hint. Restart the complete range scan after a collision:
         * advancing from a 4K page by mask + 1 alone can produce a result
         * that is not aligned to mask + 1 (for example ...9000 for a 16K
         * request), which breaks clients such as libobjc autorelease pages.
         */
        for (;;) {
            bool collision = false;
            for(u64 vaddr = address; vaddr < address + size;
                    vaddr += DYN_PAGE_SIZE) {
                if(kh_get(memory, memory, vaddr) == kh_end(memory)) {
                    continue;
                }
                address =
                    (vaddr + DYN_PAGE_SIZE + mask) & ~mask;
                collision = true;
                break;
            }
            if(!collision) {
                break;
            }
        }
    }
    
    for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
        khiter_t k = kh_put(memory, memory, vaddr, &ret);
        t_memory_page page = (t_memory_page) calloc(1, sizeof(struct memory_page));
        kh_value(memory, k) = page;
    }
    
    printf("Dynarmic_mem_reserve: 0x%llx-0x%llx\n", address, address + size);
    return address;
}

u32 Dynarmic_direct_mmap(u32 address, u32 size, int protection, int flags, void *src, u64 off) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    
    khash_t(memory) *memory = sharedHandle.memory;
    address = Dynarmic_mem_reserve(address, size, flags & MAP_FIXED, DYN_PAGE_MASK);
    if(address == -1) {
        fprintf(stderr, "reserve failed[%s->%s:%d]: addr=0x%x\n", __FILE__, __func__, __LINE__, address);
        return -1;
    }
    
    for(u32 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
        u64 idx = vaddr >> DYN_PAGE_BITS;
        
        void *addr = (void *)((u64)src + off + vaddr - address);
        t_memory_page page = kh_value(memory, kh_get(memory, memory, vaddr));
        ReleaseMemoryPageBacking(page);
        page->addr = addr;
        page->perms = protection;
        page->backing = nullptr;
        if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[idx], addr,
                __ATOMIC_RELEASE);
        } else {
            // 0xffffff80001f0000ULL: 0x10000
        }
    }
    return address;
}

u32 Dynarmic_mmap(u32 address, u32 size, int protection, int flags, int fildes, u64 off, u64 mask) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    address = Dynarmic_mem_reserve(address, size, flags & MAP_FIXED, mask);
    if(address == -1) {
        fprintf(stderr, "reserve failed[%s->%s:%d]: addr=0x%x\n", __FILE__, __func__, __LINE__, address);
        return -1;
    }
    
    if ((protection & PROT_EXEC) != 0 && fildes != -1 && size > 0x1000 && off == 0) {
        // write for Debug
        protection |= PROT_WRITE;
        flags |= MAP_PRIVATE;
        flags &= ~MAP_SHARED;
    }
    
    off_t aligned_off = off & ~(PAGE_SIZE-1);
    const size_t mappingSize = size + (off - aligned_off);
    void *mappingAddress = mmap(
        NULL, mappingSize, protection & ~PROT_EXEC,
        flags & ~MAP_FIXED, fildes, aligned_off);
    if(mappingAddress == MAP_FAILED) {
        fprintf(stderr, "mmap failed[%s->%s:%d]: addr=%p\n", __FILE__, __func__, __LINE__, mappingAddress);
        return -1;
    }
    t_memory_backing backing =
        static_cast<t_memory_backing>(
            calloc(1, sizeof(struct memory_backing)));
    if (backing == nullptr) {
        (void)munmap(mappingAddress, mappingSize);
        errno = ENOMEM;
        return -1;
    }
    backing->addr = mappingAddress;
    backing->size = mappingSize;
    backing->references = size / DYN_PAGE_SIZE;
    u64 addr = reinterpret_cast<u64>(mappingAddress) +
        (off - aligned_off);
    
    printf("DBG: mmaping host 0x%llx to 0x%x\n", addr, address);
    
    for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
        u64 idx = vaddr >> DYN_PAGE_BITS;
        
        t_memory_page page = kh_value(memory, kh_get(memory, memory, vaddr));
        ReleaseMemoryPageBacking(page);
        page->addr = (void *)addr;
        page->perms = protection;
        page->backing = backing;
        if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[idx],
                reinterpret_cast<void *>(addr),
                __ATOMIC_RELEASE);
        } else {
            // 0xffffff80001f0000ULL: 0x10000
        }
        
        addr += DYN_PAGE_SIZE;
    }
    return address;
}

int Dynarmic_mprotect(u64 address, u64 size, int perms) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
        khiter_t k = kh_get(memory, memory, vaddr);
        if(k == kh_end(memory)) {
            fprintf(stderr, "mem_protect failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
            errno = ENOMEM;
            return -1;
        }
        t_memory_page page = kh_value(memory, k);
        page->perms = perms;
    }
    return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    mem_write
 * Signature: (JJ[B)I
 */
int Dynarmic_mem_1write(u64 address, u64 size, char* src) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    u64 vaddr_end = address + size;
    for(u64 vaddr = address & ~DYN_PAGE_MASK; vaddr < vaddr_end; vaddr += DYN_PAGE_SIZE) {
        u64 start = vaddr < address ? address - vaddr : 0;
        u64 end = vaddr + DYN_PAGE_SIZE <= vaddr_end ? DYN_PAGE_SIZE : (vaddr_end - vaddr);
        u64 len = end - start;
        char *addr = get_memory_page(vaddr);
        if(addr == NULL) {
            fprintf(stderr, "mem_write failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
            return 1;
        }
        char *dest = &addr[start];
        //    printf("mem_write address=%p, vaddr=%p, start=%ld, len=%ld, addr=%p, dest=%p\n", (void*)address, (void*)vaddr, start, len, addr, dest);
        memcpy(dest, src, len);
        src += len;
    }
    return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    mem_read
 * Signature: (JJI)[B
 */
int Dynarmic_mem_1read(u64 address, u64 size, char* dest) {
    std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
    u64 vaddr_end = address + size;
    for(u64 vaddr = address & ~DYN_PAGE_MASK; vaddr < vaddr_end; vaddr += DYN_PAGE_SIZE) {
        u64 start = vaddr < address ? address - vaddr : 0;
        u64 end = vaddr + DYN_PAGE_SIZE <= vaddr_end ? DYN_PAGE_SIZE : (vaddr_end - vaddr);
        u64 len = end - start;
        char *addr = get_memory_page(vaddr);
        if(addr == NULL) {
            fprintf(stderr, "mem_read failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
            return 1;
        }
        char *src = (char *)&addr[start];
        memcpy(dest, src, len);
        dest += len;
    }
    return 0;
}

static bool DebuggerMemoryRangeIsValid(u64 address, u64 size) {
    constexpr u64 addressSpaceSize = UINT64_C(1) << 32;
    return address < addressSpaceSize &&
           size <= addressSpaceSize - address;
}

static bool DebuggerRangesOverlap(u64 firstAddress,
                                  u64 firstSize,
                                  u64 secondAddress,
                                  u64 secondSize) {
    return firstSize != 0 && secondSize != 0 &&
           firstAddress < secondAddress + secondSize &&
           secondAddress < firstAddress + firstSize;
}

static bool DebuggerMemoryRangeIsMapped(u64 address, u64 size) {
    const u64 end = address + size;
    for (u64 page = address & ~DYN_PAGE_MASK; page < end;
         page += DYN_PAGE_SIZE) {
        if (get_memory_page(page) == nullptr) {
            return false;
        }
    }
    return true;
}

/*
 * LLDB's expression evaluator writes a small JIT image into inferior memory.
 * Some guest pages are backed by read-only host mappings, so a plain memcpy
 * would crash LiveExec32 itself. Temporarily add write permission to the
 * actual host VM pages, then restore their original protection.
 */
static int DebuggerWriteHostMemory(void *destination,
                                   const void *source,
                                   size_t size) {
    auto *dest = static_cast<uint8_t *>(destination);
    auto *src = static_cast<const uint8_t *>(source);

    while (size != 0) {
        vm_address_t regionAddress =
            reinterpret_cast<vm_address_t>(dest);
        vm_size_t regionSize = 0;
        vm_region_basic_info_data_64_t regionInfo = {};
        mach_msg_type_number_t regionInfoCount =
            VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName = MACH_PORT_NULL;
        const kern_return_t regionResult = vm_region_64(
            mach_task_self(), &regionAddress, &regionSize,
            VM_REGION_BASIC_INFO_64,
            reinterpret_cast<vm_region_info_t>(&regionInfo),
            &regionInfoCount, &objectName);
        if (objectName != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), objectName);
        }

        const vm_address_t destinationAddress =
            reinterpret_cast<vm_address_t>(dest);
        if (regionResult != KERN_SUCCESS ||
            destinationAddress < regionAddress ||
            destinationAddress - regionAddress >= regionSize) {
            return 1;
        }
        const vm_size_t available =
            regionSize - (destinationAddress - regionAddress);
        const size_t chunk =
            size < available ? size : static_cast<size_t>(available);

        bool protectionChanged = false;
        vm_address_t protectStart = 0;
        vm_size_t protectSize = 0;
        if ((regionInfo.protection & VM_PROT_WRITE) == 0) {
            if ((regionInfo.max_protection & VM_PROT_WRITE) == 0 ||
                vm_page_size == 0 ||
                destinationAddress >
                    UINTPTR_MAX - chunk - (vm_page_size - 1)) {
                return 1;
            }
            protectStart =
                destinationAddress -
                destinationAddress % vm_page_size;
            const vm_address_t protectEnd =
                (destinationAddress + chunk + vm_page_size - 1) /
                vm_page_size * vm_page_size;
            protectSize = protectEnd - protectStart;
            if (vm_protect(mach_task_self(), protectStart, protectSize,
                           FALSE,
                           regionInfo.protection | VM_PROT_WRITE) !=
                KERN_SUCCESS) {
                return 1;
            }
            protectionChanged = true;
        }

        memcpy(dest, src, chunk);

        if (protectionChanged &&
            vm_protect(mach_task_self(), protectStart, protectSize,
                       FALSE, regionInfo.protection) != KERN_SUCCESS) {
            return 1;
        }
        dest += chunk;
        src += chunk;
        size -= chunk;
    }
    return 0;
}

static int DebuggerWritePhysicalMemory(u64 address,
                                       u64 size,
                                       const char *source) {
    const u64 end = address + size;
    for (u64 page = address & ~DYN_PAGE_MASK; page < end;
         page += DYN_PAGE_SIZE) {
        const u64 start = page < address ? address - page : 0;
        const u64 pageEnd =
            page + DYN_PAGE_SIZE < end ? page + DYN_PAGE_SIZE : end;
        const size_t length =
            static_cast<size_t>(pageEnd - page - start);
        char *hostPage = get_memory_page(page);
        if (hostPage == nullptr ||
            DebuggerWriteHostMemory(hostPage + start, source,
                                    length) != 0) {
            return 1;
        }
        source += length;
    }
    return 0;
}

/*
 * RSP memory reads describe the logical inferior memory.  Software
 * breakpoints are a debugger implementation detail, so overlay the saved
 * instruction bytes over the physically planted trap before replying.
 */
int Dynarmic_debugger_mem_read(u64 address, u64 size, char* dest) {
    if (!DebuggerMemoryRangeIsValid(address, size) ||
        (size != 0 && dest == nullptr) ||
        Dynarmic_mem_1read(address, size, dest) != 0) {
        return 1;
    }

    for (const DebuggerSoftwareBreakpoint &breakpoint :
         debuggerSoftwareBreakpoints) {
        if (!DebuggerRangesOverlap(address, size, breakpoint.address,
                                   breakpoint.kind)) {
            continue;
        }

        const u64 overlapStart =
            address > breakpoint.address ? address : breakpoint.address;
        const u64 requestEnd = address + size;
        const u64 breakpointEnd = breakpoint.address + breakpoint.kind;
        const u64 overlapEnd =
            requestEnd < breakpointEnd ? requestEnd : breakpointEnd;
        memcpy(dest + overlapStart - address,
               breakpoint.original.data() +
                   (overlapStart - breakpoint.address),
               overlapEnd - overlapStart);
    }
    return 0;
}

/*
 * A debugger memory write changes the logical instruction beneath any
 * active software breakpoint.  Keep the physical trap planted, update the
 * bytes that will be restored by z0, and invalidate translated code for the
 * whole modified range.
 */
int Dynarmic_debugger_mem_write(u64 address, u64 size, char* src) {
    if (!DebuggerMemoryRangeIsValid(address, size) ||
        (size != 0 && src == nullptr) ||
        !DebuggerMemoryRangeIsMapped(address, size)) {
        return 1;
    }
    if (size == 0) {
        return 0;
    }

    std::vector<uint8_t> physical(
        reinterpret_cast<uint8_t *>(src),
        reinterpret_cast<uint8_t *>(src) + size);
    for (const DebuggerSoftwareBreakpoint &breakpoint :
         debuggerSoftwareBreakpoints) {
        if (!DebuggerRangesOverlap(address, size, breakpoint.address,
                                   breakpoint.kind)) {
            continue;
        }

        const u64 overlapStart =
            address > breakpoint.address ? address : breakpoint.address;
        const u64 requestEnd = address + size;
        const u64 breakpointEnd = breakpoint.address + breakpoint.kind;
        const u64 overlapEnd =
            requestEnd < breakpointEnd ? requestEnd : breakpointEnd;
        memcpy(physical.data() + overlapStart - address,
               breakpoint.trap.data() +
                   (overlapStart - breakpoint.address),
               overlapEnd - overlapStart);
    }

    if (DebuggerWritePhysicalMemory(
            address, size,
            reinterpret_cast<const char *>(physical.data())) != 0) {
        return 1;
    }

    for (DebuggerSoftwareBreakpoint &breakpoint :
         debuggerSoftwareBreakpoints) {
        if (!DebuggerRangesOverlap(address, size, breakpoint.address,
                                   breakpoint.kind)) {
            continue;
        }

        const u64 overlapStart =
            address > breakpoint.address ? address : breakpoint.address;
        const u64 requestEnd = address + size;
        const u64 breakpointEnd = breakpoint.address + breakpoint.kind;
        const u64 overlapEnd =
            requestEnd < breakpointEnd ? requestEnd : breakpointEnd;
        memcpy(breakpoint.original.data() +
                   (overlapStart - breakpoint.address),
               reinterpret_cast<uint8_t *>(src) +
                   (overlapStart - address),
               overlapEnd - overlapStart);
    }

    InvalidateAllGuestJits(
        static_cast<u32>(address),
        static_cast<size_t>(size));
    return 0;
}

static u32 NormalizeDebuggerBreakpointAddress(u64 address, size_t kind) {
    if (address > UINT32_MAX) {
        return UINT32_MAX;
    }
    const u32 guestAddress = static_cast<u32>(address);
    return kind == sizeof(uint16_t) ? guestAddress & ~1u : guestAddress;
}

bool Dynarmic_debugger_has_breakpoint(u32 address) {
    address &= ~1u;
    for (const DebuggerSoftwareBreakpoint &breakpoint :
         debuggerSoftwareBreakpoints) {
        if (breakpoint.address == address) {
            return true;
        }
    }
    return false;
}

bool Dynarmic_debugger_set_breakpoint(u64 address, size_t kind) {
    if (kind != sizeof(uint16_t) && kind != sizeof(uint32_t)) {
        return false;
    }

    const u32 guestAddress =
        NormalizeDebuggerBreakpointAddress(address, kind);
    if (guestAddress == UINT32_MAX ||
        (kind == sizeof(uint32_t) &&
         (guestAddress & (sizeof(uint32_t) - 1)) != 0)) {
        return false;
    }

    for (const DebuggerSoftwareBreakpoint &breakpoint :
         debuggerSoftwareBreakpoints) {
        if (breakpoint.address == guestAddress &&
            breakpoint.kind == kind) {
            return true;
        }
        if (DebuggerRangesOverlap(guestAddress, kind, breakpoint.address,
                                  breakpoint.kind)) {
            return false;
        }
    }

    DebuggerSoftwareBreakpoint breakpoint = {
        .address = guestAddress,
        .kind = kind,
        .original = {},
        .trap = {},
    };
    if (Dynarmic_mem_1read(guestAddress, kind,
                           reinterpret_cast<char *>(
                               breakpoint.original.data())) != 0) {
        return false;
    }

    const uint32_t instruction =
        kind == sizeof(uint16_t) ? 0x0000BE00u : 0xE1200070u;
    memcpy(breakpoint.trap.data(), &instruction, kind);
    // Allocate registry storage before modifying guest code so the running
    // process can never contain an untracked trap instruction.
    debuggerSoftwareBreakpoints.push_back(breakpoint);
    if (DebuggerWritePhysicalMemory(
            guestAddress, kind,
            reinterpret_cast<const char *>(
                debuggerSoftwareBreakpoints.back().trap.data())) != 0) {
        debuggerSoftwareBreakpoints.pop_back();
        return false;
    }
    InvalidateAllGuestJits(guestAddress, kind);
    return true;
}

bool Dynarmic_debugger_delete_breakpoint(u64 address, size_t kind) {
    (void)kind;
    if (address > UINT32_MAX) {
        return false;
    }

    /*
     * LLDB derives ARM breakpoint kind again when disabling a site.  Its
     * answer can differ from the kind used by the earlier Z0 packet (for
     * example, Z0(...,2) followed by z0(...,4) for Thumb code).  The active
     * record is authoritative: locate it by canonical address and restore
     * the exact byte count saved when it was installed.
     */
    const u32 guestAddress = static_cast<u32>(address) & ~1u;
    for (auto it = debuggerSoftwareBreakpoints.begin();
         it != debuggerSoftwareBreakpoints.end(); ++it) {
        if (it->address != guestAddress) {
            continue;
        }
        if (DebuggerWritePhysicalMemory(
                guestAddress, it->kind,
                reinterpret_cast<const char *>(
                    it->original.data())) != 0) {
            return false;
        }
        InvalidateAllGuestJits(
            guestAddress, it->kind);
        debuggerSoftwareBreakpoints.erase(it);
        return true;
    }

    // GDB remote breakpoint removal is idempotent.
    return true;
}

size_t Dynarmic_debugger_thread_ids(
        gdb_thread_id_t *ids, size_t capacity) {
    if (threadHandle.jit == nullptr) {
        return 0;
    }
    EnsureGuestThreadRegistry();

    size_t count = 0;
    const auto append = [&](gdb_thread_id_t id) {
        if (ids != nullptr && count < capacity) {
            ids[count] = id;
        }
        ++count;
    };
    if (GuestThreadContext *main = FindGuestThread(1, true)) {
        append(main->debuggerId);
    }
    if (guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid) {
        append(2);
    }
    for (const GuestThreadContext &thread : guestThreads) {
        if (thread.alive && thread.debuggerId >= 3) {
            append(thread.debuggerId);
        }
    }
    return count;
}

gdb_thread_id_t Dynarmic_debugger_current_thread() {
    EnsureGuestThreadRegistry();
    return guestWorkqueueUpcallActive
        ? 2
        : guestCurrentThreadId;
}

bool Dynarmic_debugger_thread_alive(gdb_thread_id_t thread_id) {
    if (threadHandle.jit == nullptr) {
        return false;
    }
    EnsureGuestThreadRegistry();
    if (thread_id == 2) {
        return guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid;
    }
    return FindGuestThread(thread_id, true) != nullptr;
}

bool Dynarmic_debugger_thread_read_reg(
        gdb_thread_id_t thread_id, int regno, u32 *value) {
    if (value == nullptr || regno < 0 || regno > 16 ||
            !Dynarmic_debugger_thread_alive(thread_id)) {
        return false;
    }

    if (thread_id == Dynarmic_debugger_current_thread()) {
        *value = regno == 16
            ? static_cast<u32>(threadHandle.jit->Cpsr())
            : threadHandle.jit->Regs()[regno];
        return true;
    }

    if (guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid &&
            thread_id == guestWorkqueueWaitingThreadId) {
        *value = regno == 16
            ? guestWorkqueueWaitingContext.cpsr
            : guestWorkqueueWaitingContext.regs[regno];
        return true;
    }
    GuestThreadContext *thread =
        FindGuestThread(thread_id, true);
    if (thread != nullptr && thread->savedValid) {
        *value = regno == 16
            ? thread->saved.cpsr
            : thread->saved.regs[regno];
        return true;
    }
    return false;
}

bool Dynarmic_debugger_thread_write_reg(
        gdb_thread_id_t thread_id, int regno, u32 value) {
    if (regno < 0 || regno > 16 ||
            !Dynarmic_debugger_thread_alive(thread_id)) {
        return false;
    }

    if (thread_id == Dynarmic_debugger_current_thread()) {
        if (regno == 16) {
            threadHandle.jit->SetCpsr(value);
        } else {
            threadHandle.jit->Regs()[regno] = value;
        }
        return true;
    }

    if (guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid &&
            thread_id == guestWorkqueueWaitingThreadId) {
        if (regno == 16) {
            guestWorkqueueWaitingContext.cpsr = value;
        } else {
            guestWorkqueueWaitingContext.regs[regno] = value;
        }
        return true;
    }
    GuestThreadContext *thread =
        FindGuestThread(thread_id, true);
    if (thread != nullptr && thread->savedValid) {
        if (regno == 16) {
            thread->saved.cpsr = value;
        } else {
            thread->saved.regs[regno] = value;
        }
        return true;
    }
    return false;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_write
 * Signature: (JIJ)I
 */
int Dynarmic_reg_1write(int index, u32 value) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
        jit->Regs()[index] = value;
    } else {
        return 1;
    }
    return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_read
 * Signature: (JI)J
 */
u32 Dynarmic_reg_1read(int index) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      return jit->Regs()[index];
    } else {
      abort();
      return -1;
    }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_read_cpsr
 * Signature: (J)I
 */
int Dynarmic_reg_1read_1cpsr() {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      return jit->Cpsr();
    } else {
      abort();
      return -1;
    }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_write_cpsr
 * Signature: (JI)I
 */
int Dynarmic_reg_1write_1cpsr(int value) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      jit->SetCpsr(value);
      return 0;
    } else {
      abort();
      return -1;
    }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_write_c13_c0_3
 * Signature: (JI)I
 */
int Dynarmic_reg_1write_1c13_1c0_13(int value) {
    DynarmicCallbacks32 *cb = threadHandle.cb;
    if(cb) {
      cb->cp15.get()->uro = value;
      return 0;
    } else {
      abort();
      return -1;
    }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    emu_start
 * Signature: (JJ)I
 */
Dynarmic::HaltReason Dynarmic_emu_1start(u32 pc) {
    Dynarmic::HaltReason reason;
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      if (ConsumePendingGuestStop()) {
        return LC32HaltReasonTrap;
      }
      Dynarmic::A32::Jit *cpu = jit;
      if(pc & 1) {
        cpu->SetCpsr(0x00000030); // Thumb user mode
      } else {
        cpu->SetCpsr(0x000001d0); // Arm user mode
      }
      cpu->Regs()[15] = (u32) (pc & ~1);
      for (;;) {
        reason = cpu->Run();
        if (Dynarmic::Has(
                reason, Dynarmic::HaltReason::CacheInvalidation)) {
          reason = reason &
              ~Dynarmic::HaltReason::CacheInvalidation;
          if (!reason) {
            continue;
          }
        }
        if (Dynarmic::Has(reason, LC32HaltReasonWorkqueue)) {
          if (!HandleGuestContextTransition()) {
            reason = LC32HaltReasonTrap;
            break;
          }
          const Dynarmic::HaltReason remaining =
              reason & ~LC32HaltReasonWorkqueue;
          if (!!remaining) {
            reason = remaining;
            break;
          }
          continue;
        }
        if (!Dynarmic::Has(reason, LC32HaltReasonSVC)) {
          break;
        }
        threadHandle.cb->CallSVC(0x80);
        HandleGuestContextTransition();
      }
    } else {
      return LC32HaltReasonTrap;
    }
  UpdateGuestStopSignalForHalt(reason);
  return reason;
}

Dynarmic::HaltReason Dynarmic_emu_1resume() {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if (!jit) {
        return LC32HaltReasonTrap;
    }
    if (ConsumePendingGuestStop()) {
        return LC32HaltReasonTrap;
    }

    Dynarmic::HaltReason reason;
    for (;;) {
        reason = jit->Run();
        if (Dynarmic::Has(
                reason, Dynarmic::HaltReason::CacheInvalidation)) {
            reason = reason &
                ~Dynarmic::HaltReason::CacheInvalidation;
            if (!reason) {
                continue;
            }
        }
        if (Dynarmic::Has(reason, LC32HaltReasonWorkqueue)) {
            if (!HandleGuestContextTransition()) {
                reason = LC32HaltReasonTrap;
                break;
            }
            const Dynarmic::HaltReason remaining =
                reason & ~LC32HaltReasonWorkqueue;
            if (!!remaining) {
                reason = remaining;
                break;
            }
            continue;
        }
        if (!Dynarmic::Has(reason, LC32HaltReasonSVC)) {
            break;
        }
        threadHandle.cb->CallSVC(0x80);
        HandleGuestContextTransition();
    }
    UpdateGuestStopSignalForHalt(reason);
    return reason;
}

Dynarmic::HaltReason Dynarmic_emu_1step() {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if (!jit) {
        return LC32HaltReasonTrap;
    }
    if (ConsumePendingGuestStop()) {
        return LC32HaltReasonTrap;
    }

    Dynarmic::HaltReason reason;
    bool drainInternalWorker = false;
    guestSingleStepping = true;
    for (;;) {
        reason = drainInternalWorker ? jit->Run() : jit->Step();
        if (Dynarmic::Has(
                reason, Dynarmic::HaltReason::CacheInvalidation)) {
            reason = reason &
                ~Dynarmic::HaltReason::CacheInvalidation;
            if (!reason) {
                continue;
            }
        }
        if (Dynarmic::Has(reason, LC32HaltReasonWorkqueue)) {
            const bool wasWorkerActive = guestWorkqueueUpcallActive;
            const bool hadGuestThreadTransition =
                GuestThreadTransitionPending();
            if (!HandleGuestContextTransition()) {
                reason = LC32HaltReasonTrap;
                break;
            }
            const Dynarmic::HaltReason remaining =
                reason & ~(LC32HaltReasonWorkqueue |
                           Dynarmic::HaltReason::Step);
            if (!!remaining) {
                reason = remaining;
                break;
            }
            if (hadGuestThreadTransition &&
                    !wasWorkerActive &&
                    !guestWorkqueueUpcallActive) {
                reason = Dynarmic::HaltReason::Step;
                break;
            }
            if (!wasWorkerActive && guestWorkqueueUpcallActive) {
                /*
                 * Finish an internal worker spawned by the instruction being
                 * stepped. If the debugger was already stopped in a worker,
                 * drainInternalWorker remains false and Step() retains normal
                 * single-instruction semantics for that worker.
                 */
                drainInternalWorker = true;
                continue;
            }
            if (wasWorkerActive && !guestWorkqueueUpcallActive) {
                reason = Dynarmic::HaltReason::Step;
                break;
            }
            continue;
        }
        if (!Dynarmic::Has(reason, LC32HaltReasonSVC)) {
            break;
        }
        threadHandle.cb->CallSVC(0x80);
        HandleGuestContextTransition();
    }
    guestSingleStepping = false;
    UpdateGuestStopSignalForHalt(reason);
    return reason;
}

void Dynarmic_emu_1set_1debugger_1enabled(bool enabled) {
    guestDebuggerEnabled.store(enabled, std::memory_order_relaxed);
    if (!enabled) {
        debuggerInterruptRequested.store(false, std::memory_order_release);
    }
}

int Dynarmic_emu_1get_1stop_1signal() {
    return guestStopSignal.load(std::memory_order_relaxed);
}

void Dynarmic_emu_1set_1resume_1signal(int signal) {
    const int pending =
        pendingGuestFatalSignal.load(std::memory_order_relaxed);
    if (signal > 0 && signal == pending) {
        reemitPendingGuestStop.store(true, std::memory_order_relaxed);
        return;
    }

    // Signal zero is the lowercase c/s suppression path.  A different signal
    // also cannot faithfully deliver the pending guest fault, so let execution
    // proceed instead of re-reporting stale state.
    pendingGuestFatalSignal.store(0, std::memory_order_relaxed);
    reemitPendingGuestStop.store(false, std::memory_order_relaxed);
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    emu_stop
 * Signature: (J)I
 */
int Dynarmic_emu_1stop() {
    // on_interrupt is invoked by mini-gdbstub's socket-reader thread. That
    // thread has no thread-local dynarmic_thread, so use the JIT published by
    // the shared callbacks instead of threadHandle.jit.
    DynarmicCallbacks32 *callbacks = sharedHandle.cb;
    Dynarmic::A32::Jit *jit = callbacks ? callbacks->cpu : NULL;
    if(jit) {
      debuggerInterruptRequested.store(true, std::memory_order_release);
      jit->HaltExecution(LC32HaltReasonInterrupt);
      for (;;) {
        const DebuggerMachCallPhase phase =
            debuggerMachCallPhase.load(std::memory_order_acquire);
        if (phase == DebuggerMachCallPhase::Idle ||
                phase == DebuggerMachCallPhase::Completing) {
            break;
        }
        if (phase == DebuggerMachCallPhase::InCall) {
            const mach_port_t thread =
                debuggerMachCallThread.load(std::memory_order_acquire);
            if (MACH_PORT_VALID(thread)) {
                (void)thread_abort_safely(thread);
            }
        }
        sched_yield();
      }
    } else {
      return 1;
    }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_alloc
 * Signature: (J)J
 */
void* Dynarmic_context_1alloc() {
    void *ctx = malloc(sizeof(struct context32));
    return ctx;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_restore
 * Signature: (JJ)V
 */
void Dynarmic_context_1restore(t_context32 ctx) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    jit->Regs() = ctx->regs;
    jit->ExtRegs() = ctx->extRegs;
    jit->SetCpsr(ctx->cpsr);
    jit->SetFpscr(ctx->fpscr);

    DynarmicCallbacks32 *cb = threadHandle.cb;
    cb->cp15.get()->uro = ctx->uro;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_save
 * Signature: (JJ)V
 */
void Dynarmic_context_1save(t_context32 ctx) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    ctx->regs = jit->Regs();
    ctx->extRegs = jit->ExtRegs();
    ctx->cpsr = jit->Cpsr();
    ctx->fpscr = jit->Fpscr();

    DynarmicCallbacks32 *cb = threadHandle.cb;
    ctx->uro = cb->cp15.get()->uro;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    free
 * Signature: (J)V
 */
void Dynarmic_free(void *ctx) {
  free(ctx);
}

#ifdef __cplusplus
}
#endif
