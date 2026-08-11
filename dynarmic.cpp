#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdarg>
#include <cstdio>
#include <deque>
#include <exception>
#include <iostream>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
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
#include "debugger_server.h"
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
static std::atomic<bool> debuggerAllStopRequested{false};
static std::atomic<bool> nativeShutdownRequested{false};
static std::atomic<bool> guestProcessExitRequested{false};
static std::atomic<int> guestProcessExitCode{0};
static std::atomic<bool> guestCrashTerminationStarted{false};
static std::recursive_mutex guestVmMutex;
static std::mutex guestMappingMutex;

/*
 * These interfaces are exported by libSystem on both iOS 10 and current
 * iOS, but Apple does not ship their declarations in the public SDK.  The
 * OS-reason string is deliberately compact; the complete report is retained
 * through CrashReporter's application-specific-information annotation.
 */
extern "C" void abort_with_reason(
    uint32_t reason_namespace, uint64_t reason_code,
    const char *reason_string, uint64_t reason_flags)
    __attribute__((noreturn, cold));
extern "C" const char *__crashreporter_info__;

constexpr uint32_t LC32_OS_REASON_LIBSYSTEM = 18;
constexpr uint32_t LC32_OS_REASON_MAX_VALID_NAMESPACE = 47;
constexpr uint64_t LC32_GUEST_CRASH_REASON_CODE = 2;
constexpr size_t LC32_OS_REASON_STRING_MAX = 1023;
constexpr size_t LC32_GUEST_ERROR_IN_COMPACT_REASON_MAX = 280;
constexpr size_t LC32_FULL_CRASH_REPORT_MAX = 2 * 1024 * 1024;
constexpr size_t LC32_CRASH_ANNOTATIONS_MAX = 16;
constexpr size_t LC32_CRASH_ANNOTATION_BYTES_MAX = 64 * 1024;
constexpr uint32_t LC32_CRASH_SYMBOLS_MAX = 256 * 1024;

struct GuestAbortMetadata {
    bool valid = false;
    uint32_t reasonNamespace = 0;
    uint64_t reasonCode = 0;
    uint32_t payloadSize = 0;
    uint64_t reasonFlags = 0;
    std::string reason;
};

static thread_local GuestAbortMetadata pendingGuestAbortMetadata;
static thread_local std::string pendingGuestCrashMessage;

static std::string FormatString(const char *format, va_list arguments) {
    va_list copiedArguments;
    va_copy(copiedArguments, arguments);
    const int length = vsnprintf(nullptr, 0, format, copiedArguments);
    va_end(copiedArguments);
    if (length <= 0) {
        return {};
    }

    std::vector<char> buffer(static_cast<size_t>(length) + 1);
    vsnprintf(buffer.data(), buffer.size(), format, arguments);
    return std::string(buffer.data(), static_cast<size_t>(length));
}

static void SetPendingGuestCrashMessage(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    pendingGuestCrashMessage = FormatString(format, arguments);
    va_end(arguments);
}

static void SetPendingGuestCrashMessageIfEmpty(const char *format, ...) {
    if (!pendingGuestCrashMessage.empty()) {
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    pendingGuestCrashMessage = FormatString(format, arguments);
    va_end(arguments);
}

static bool read_guest_memory_with_permissions(
    u64 address, void *destination, size_t size,
    int requiredPermissions);
static bool GuestAddressRangeIsValid32(u64 address, u64 size);
static std::string CopyGuestCStringForCrash(
    u64 guestAddress, size_t maximumLength);

enum class NativeLifecycleState : uint8_t {
    Uninitialized,
    Running,
    ShuttingDown,
    Destroyed,
};

static std::mutex nativeLifecycleMutex;
static std::condition_variable nativeLifecycleCondition;
static NativeLifecycleState nativeLifecycleState =
    NativeLifecycleState::Uninitialized;

struct GuestVmEpochParticipant {
    uint64_t epoch = 0;
    size_t activeDepth = 0;
    bool registered = false;
};

struct RetiredMemoryBacking {
    t_memory_backing backing = nullptr;
    uint64_t retirementEpoch = 0;
};

static std::mutex guestVmEpochMutex;
static uint64_t guestVmEpoch = 1;
static GuestVmEpochParticipant mainGuestVmParticipant;
static std::vector<GuestVmEpochParticipant *>
    guestVmEpochParticipants;
static std::vector<RetiredMemoryBacking>
    retiredMemoryBackings;

static void ReclaimRetiredMemoryBackingsLocked() {
    for (auto iterator = retiredMemoryBackings.begin();
            iterator != retiredMemoryBackings.end();) {
        bool safe = true;
        for (const GuestVmEpochParticipant *participant :
                guestVmEpochParticipants) {
            if (participant != nullptr &&
                    participant->activeDepth != 0 &&
                    participant->epoch <
                        iterator->retirementEpoch) {
                safe = false;
                break;
            }
        }
        if (!safe) {
            ++iterator;
            continue;
        }
        t_memory_backing backing =
            iterator->backing;
        if (backing != nullptr &&
                munmap(backing->addr,
                    backing->size) != 0) {
            fprintf(stderr,
                "munmap retired backing failed: "
                "addr=%p, size=0x%zx, errno=%d\n",
                backing->addr, backing->size,
                errno);
        }
        free(backing);
        iterator =
            retiredMemoryBackings.erase(iterator);
    }
}

static void RegisterGuestVmEpochParticipant(
        GuestVmEpochParticipant *participant) {
    if (participant == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(
        guestVmEpochMutex);
    if (participant->registered) {
        return;
    }
    participant->registered = true;
    participant->epoch = guestVmEpoch;
    participant->activeDepth = 0;
    guestVmEpochParticipants.push_back(
        participant);
}

static void UnregisterGuestVmEpochParticipant(
        GuestVmEpochParticipant *participant) {
    if (participant == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(
        guestVmEpochMutex);
    if (!participant->registered) {
        return;
    }
    assert(participant->activeDepth == 0);
    guestVmEpochParticipants.erase(std::remove(
        guestVmEpochParticipants.begin(),
        guestVmEpochParticipants.end(),
        participant), guestVmEpochParticipants.end());
    participant->registered = false;
    ReclaimRetiredMemoryBackingsLocked();
}

static void RetireMemoryBacking(
        t_memory_backing backing) {
    if (backing == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(
        guestVmEpochMutex);
    retiredMemoryBackings.push_back({
        .backing = backing,
        .retirementEpoch = ++guestVmEpoch,
    });
    ReclaimRetiredMemoryBackingsLocked();
}

class GuestVmEpochGuard {
public:
    explicit GuestVmEpochGuard(
            GuestVmEpochParticipant *participant)
        : participant(participant) {
        if (participant == nullptr) {
            return;
        }
        std::lock_guard<std::mutex> lock(
            guestVmEpochMutex);
        assert(participant->registered);
        if (participant->activeDepth++ == 0) {
            participant->epoch = guestVmEpoch;
        }
    }

    ~GuestVmEpochGuard() {
        if (participant == nullptr) {
            return;
        }
        std::lock_guard<std::mutex> lock(
            guestVmEpochMutex);
        assert(participant->activeDepth != 0);
        if (--participant->activeDepth == 0) {
            ReclaimRetiredMemoryBackingsLocked();
        }
    }

    GuestVmEpochGuard(
        const GuestVmEpochGuard &) = delete;
    GuestVmEpochGuard &operator=(
        const GuestVmEpochGuard &) = delete;

private:
    GuestVmEpochParticipant *participant;
};

struct GuestStopRequest {
    int signal = SIGTRAP;
    bool pending = false;
    bool valid = false;
};

/*
 * A native guest thread must not publish process-wide signal state until it
 * wins the all-stop coordinator. Otherwise two simultaneous faults can make
 * LLDB report one thread with another thread's signal (and a losing SIGTRAP
 * can incorrectly clear a winning fatal signal's replay state).
 */
static thread_local GuestStopRequest currentGuestStopRequest;

static bool NativeGuestThreadsRequested() {
    static const bool requested = [] {
        const char *value = getenv("NATIVE_GUEST_THREADS");
        return value != nullptr && value[0] != '\0' &&
            strcmp(value, "0") != 0;
    }();
    return requested;
}

static bool NativeGuestThreadsEnabled() {
    return NativeGuestThreadsRequested();
}

static Dynarmic::A32::UserCallbacks *CurrentUserCallbacks();

enum class DebuggerMachCallPhase : uint8_t {
    Idle,
    Arming,
    InCall,
    Completing,
};

struct DebuggerMachCall {
    std::atomic<DebuggerMachCallPhase> phase{
        DebuggerMachCallPhase::Idle};
    std::atomic<bool> interruptRequested{false};
    mach_port_t thread = MACH_PORT_NULL;
    /*
     * thread_abort_safely is sufficient for Mach traps, but Darwin may leave
     * a raw BSD syscall such as read(2) asleep even after reporting success.
     * Generic wrappers are installed only around known syscall boundaries,
     * where thread_abort can safely force an EINTR return.
     */
    bool forceAbort = false;
};

static std::mutex debuggerMachCallsMutex;
static std::vector<DebuggerMachCall *> debuggerMachCalls;

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
static void InterruptDebuggerMachCalls();
static void ScheduleMainGuestWorkqueueTransition();
namespace {
bool NativeDebuggerPauseHostWaitIfNeeded();
void NotifyNativeDebuggerWaiters();
void NotifyNativeDebuggerCoordinator();
gdb_thread_id_t CurrentGuestThreadId();
}
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
static thread_local bool guestSingleStepping;
static thread_local bool guestDeferredSVC;

struct DebuggerSoftwareBreakpoint {
    u32 address;
    size_t kind;
    std::array<uint8_t, sizeof(uint32_t)> original;
    std::array<uint8_t, sizeof(uint32_t)> trap;
};
static std::vector<DebuggerSoftwareBreakpoint> debuggerSoftwareBreakpoints;

static int NormalizeGuestStopSignal(int signal) {
    if (signal <= 0 || signal >= NSIG) {
        return SIGABRT;
    }
    return signal;
}

static void CommitGuestStopSignal(int signal, bool pending) {
    signal = NormalizeGuestStopSignal(signal);
    guestStopSignal.store(signal, std::memory_order_relaxed);
    if (!pending) {
        pendingGuestFatalSignal.store(0, std::memory_order_relaxed);
        reemitPendingGuestStop.store(false, std::memory_order_relaxed);
    } else {
        pendingGuestFatalSignal.store(signal, std::memory_order_relaxed);
    }
}

static void RecordGuestStopSignal(int signal, bool pending) {
    signal = NormalizeGuestStopSignal(signal);
    if (NativeGuestThreadsEnabled() &&
            guestDebuggerEnabled.load(std::memory_order_acquire)) {
        currentGuestStopRequest = {
            .signal = signal,
            .pending = pending,
            .valid = true,
        };
        return;
    }
    CommitGuestStopSignal(signal, pending);
}

static void ClearCurrentGuestStopRequest() {
    currentGuestStopRequest = {};
}

static GuestStopRequest CurrentGuestStopRequestForReason(
        Dynarmic::HaltReason reason) {
    GuestStopRequest request = currentGuestStopRequest;
    if (request.valid) {
        return request;
    }

    const Dynarmic::HaltReason visibleReason =
        reason & ~LC32HaltReasonDebuggerPause;
    request.valid = true;
    if (Dynarmic::Has(
            visibleReason, LC32HaltReasonInterrupt)) {
        request.signal = SIGINT;
    } else if (Dynarmic::Has(
            visibleReason,
            Dynarmic::HaltReason::MemoryAbort)) {
        request.signal = SIGSEGV;
        request.pending = true;
    } else {
        request.signal = SIGTRAP;
    }
    return request;
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
    const Dynarmic::HaltReason visibleReason =
        reason & ~LC32HaltReasonDebuggerPause;
    if (!visibleReason) {
        return;
    }
    if (Dynarmic::Has(
            visibleReason, LC32HaltReasonInterrupt)) {
        debuggerInterruptRequested.store(false, std::memory_order_release);
        RecordGuestStopSignal(SIGINT, false);
    } else if (Dynarmic::Has(
            visibleReason,
            Dynarmic::HaltReason::MemoryAbort)) {
        RecordGuestStopSignal(SIGSEGV, true);
    } else if (!Dynarmic::Has(
            visibleReason, LC32HaltReasonTrap)) {
        // A normal single-step or any non-fault emulator stop must not retain
        // the signal from an earlier fatal stop.
        RecordGuestStopSignal(SIGTRAP, false);
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
    std::lock_guard<std::mutex> lock(guestMappingMutex);
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
    u32 address = 0;
    u32 symbolOffset = 0;
    std::string symbolName;
    std::string imageName;
};

struct GuestImageSnapshot {
    u32 start = 0;
    u32 end = 0;
    std::string name;
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
            (!guestDebuggerEnabled.load(std::memory_order_relaxed) &&
             !NativeGuestThreadsEnabled())) {
        return mach_msg(msg, option, send_size, rcv_size, rcv_name,
            timeout, notify);
    }

    /*
     * Every native guest pthread may block in Mach independently. Publish a
     * stack record for this call so an all-stop request can interrupt every
     * host thread, rather than whichever thread most recently overwrote a
     * process-global slot.
     */
    DebuggerMachCall call;
    call.thread = pthread_mach_thread_np(pthread_self());
    call.phase.store(
        DebuggerMachCallPhase::Arming, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(debuggerMachCallsMutex);
        debuggerMachCalls.push_back(&call);
    }

    const auto finishCall = [&call] {
        call.phase.store(
            DebuggerMachCallPhase::Completing, std::memory_order_release);
        {
            std::lock_guard<std::mutex> lock(debuggerMachCallsMutex);
            debuggerMachCalls.erase(std::remove(
                debuggerMachCalls.begin(), debuggerMachCalls.end(),
                &call), debuggerMachCalls.end());
        }
        call.phase.store(
            DebuggerMachCallPhase::Idle, std::memory_order_release);
    };
    const auto interruptedBeforeCall = [option] {
        return (option & MACH_SEND_MSG) != 0
            ? MACH_SEND_INTERRUPTED
            : MACH_RCV_INTERRUPTED;
    };
    const auto stopRequested = [&call] {
        return call.interruptRequested.load(
                   std::memory_order_acquire) ||
            debuggerInterruptRequested.load(std::memory_order_acquire) ||
            debuggerAllStopRequested.load(std::memory_order_acquire) ||
            nativeShutdownRequested.load(std::memory_order_acquire) ||
            guestProcessExitRequested.load(std::memory_order_acquire);
    };

    if (stopRequested()) {
        finishCall();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
        return interruptedBeforeCall();
    }

    call.phase.store(
        DebuggerMachCallPhase::InCall, std::memory_order_release);
    if (stopRequested()) {
        finishCall();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
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
    if (stopRequested()) {
        (void)NativeDebuggerPauseHostWaitIfNeeded();
    }
    return result;
}

static void InterruptDebuggerMachCalls() {
    constexpr unsigned retryCount = 100;
    constexpr useconds_t retryDelayMicroseconds = 1000;

    const auto interruptionStillRequested = [] {
        return debuggerInterruptRequested.load(
                   std::memory_order_acquire) ||
            debuggerAllStopRequested.load(
                   std::memory_order_acquire) ||
            nativeShutdownRequested.load(
                   std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                   std::memory_order_acquire);
    };

    /*
     * Publishing InCall necessarily precedes the actual user-to-kernel
     * transition. A one-shot thread_abort can therefore arrive in that tiny
     * window and be lost before mach_msg/read enters the kernel. Persist the
     * request in each stack record and retry for a bounded interval.
     */
    for (unsigned attempt = 0;
            attempt < retryCount &&
            interruptionStillRequested();
            ++attempt) {
        std::vector<std::pair<mach_port_t, bool>> threads;
        size_t activeCalls = 0;
        {
            std::lock_guard<std::mutex> lock(
                debuggerMachCallsMutex);
            for (DebuggerMachCall *call :
                    debuggerMachCalls) {
                if (call == nullptr ||
                        !MACH_PORT_VALID(call->thread)) {
                    continue;
                }
                const DebuggerMachCallPhase phase =
                    call->phase.load(
                        std::memory_order_acquire);
                if (phase ==
                        DebuggerMachCallPhase::Arming ||
                        phase ==
                        DebuggerMachCallPhase::InCall) {
                    ++activeCalls;
                    call->interruptRequested.store(
                        true, std::memory_order_release);
                }
                /*
                 * Arming records have not committed to the host call and will
                 * observe interruptRequested themselves. Only abort a thread
                 * after it has published InCall.
                 */
                if (phase ==
                        DebuggerMachCallPhase::InCall) {
                    threads.push_back({
                        call->thread, call->forceAbort});
                }
            }

            std::sort(threads.begin(), threads.end());
            size_t output = 0;
            for (size_t index = 0;
                    index < threads.size();) {
                const mach_port_t thread =
                    threads[index].first;
                bool forceAbort = false;
                size_t next = index;
                while (next < threads.size() &&
                        threads[next].first ==
                            thread) {
                    forceAbort |= threads[next].second;
                    ++next;
                }
                /*
                 * The stack record may disappear once this mutex is released.
                 * Retain the send right so a terminating pthread cannot make
                 * this copied port name stale or reusable during the abort.
                 */
                if (mach_port_mod_refs(
                        mach_task_self(), thread,
                        MACH_PORT_RIGHT_SEND, 1) ==
                        KERN_SUCCESS) {
                    threads[output++] = {
                        thread, forceAbort};
                }
                index = next;
            }
            threads.resize(output);
        }

        for (const auto &entry : threads) {
            if (entry.second) {
                (void)thread_abort(entry.first);
            } else {
                (void)thread_abort_safely(entry.first);
            }
            (void)mach_port_deallocate(
                mach_task_self(), entry.first);
        }

        if (activeCalls == 0 ||
                attempt + 1 == retryCount) {
            break;
        }
        usleep(retryDelayMicroseconds);
    }
}

static void DrainDebuggerMachCalls() {
    for (;;) {
        InterruptDebuggerMachCalls();
        bool active = false;
        {
            std::lock_guard<std::mutex> lock(
                debuggerMachCallsMutex);
            for (const DebuggerMachCall *call :
                    debuggerMachCalls) {
                if (call == nullptr) {
                    continue;
                }
                const DebuggerMachCallPhase phase =
                    call->phase.load(
                        std::memory_order_acquire);
                if (phase ==
                        DebuggerMachCallPhase::Arming ||
                        phase ==
                        DebuggerMachCallPhase::InCall) {
                    active = true;
                    break;
                }
            }
        }
        if (!active) {
            return;
        }
    }
}

template <typename Result, typename Function>
static Result debugger_aware_host_wait(
        Function &&function, Result interruptedResult) {
    if (!guestDebuggerEnabled.load(
            std::memory_order_acquire) &&
            !NativeGuestThreadsEnabled()) {
        return function();
    }

    DebuggerMachCall call;
    call.thread = pthread_mach_thread_np(
        pthread_self());
    call.forceAbort = true;
    call.phase.store(
        DebuggerMachCallPhase::Arming,
        std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(
            debuggerMachCallsMutex);
        debuggerMachCalls.push_back(&call);
    }
    const auto finishCall = [&call] {
        call.phase.store(
            DebuggerMachCallPhase::Completing,
            std::memory_order_release);
        {
            std::lock_guard<std::mutex> lock(
                debuggerMachCallsMutex);
            debuggerMachCalls.erase(std::remove(
                debuggerMachCalls.begin(),
                debuggerMachCalls.end(), &call),
                debuggerMachCalls.end());
        }
        call.phase.store(
            DebuggerMachCallPhase::Idle,
            std::memory_order_release);
    };
    const auto stopRequested = [&call] {
        return call.interruptRequested.load(
                   std::memory_order_acquire) ||
            debuggerInterruptRequested.load(
                   std::memory_order_acquire) ||
            debuggerAllStopRequested.load(
                   std::memory_order_acquire) ||
            nativeShutdownRequested.load(
                   std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                   std::memory_order_acquire);
    };

    if (stopRequested()) {
        finishCall();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
        return interruptedResult;
    }
    call.phase.store(
        DebuggerMachCallPhase::InCall,
        std::memory_order_release);
    if (stopRequested()) {
        finishCall();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
        return interruptedResult;
    }

    Result result = function();
    finishCall();
    if (stopRequested()) {
        (void)NativeDebuggerPauseHostWaitIfNeeded();
    }
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
                SetPendingGuestCrashMessage(
                    "Unhandled host_info flavor %d", Mess->In.flavor);
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
            std::lock_guard<std::mutex> mappingLock(
                guestMappingMutex);
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
            SetPendingGuestCrashMessage(
                "Unhandled Mach message id %d",
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
            /*
             * XNU may start the requested worker before this syscall returns.
             * Prepare the cooperative overlay now so dispatch_async does not
             * depend on the main thread eventually entering mach_msg.
             */
            const bool prepared = PumpGuestWorkqueue();
            if (prepared && NativeGuestThreadIsCurrent() &&
                    CurrentGuestThreadId() != 1) {
                /*
                 * Workqueue overlays run on the main JIT. A request can be
                 * made by any native guest pthread, so wake the main runner
                 * and let it install the prepared upcall at a safe boundary.
                 */
                ScheduleMainGuestWorkqueueTransition();
            }
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

int guest_bind(int socket, u32 guest_address, socklen_t address_len) {
    if (guest_address == 0) {
        return return_with_carry_direct(EDESTADDRREQ, true);
    }
    if (address_len > SOCK_MAXADDRLEN) {
        return return_with_carry_direct(ENAMETOOLONG, true);
    }
    if (address_len < sizeof(__sockaddr_header)) {
        return return_with_carry_direct(EINVAL, true);
    }

    std::array<char, SOCK_MAXADDRLEN> host_address = {};
    if (Dynarmic_mem_1read(
            guest_address, address_len, host_address.data()) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    constexpr size_t pathOffset = offsetof(sockaddr_un, sun_path);
    if (reinterpret_cast<const sockaddr *>(
                host_address.data())->sa_family == AF_UNIX &&
            address_len > pathOffset &&
            host_address[pathOffset] != '\0') {
        /*
         * Unix-domain socket names participate in the same guest mount
         * namespace as open/unlink.  SOCK_MAXADDRLEN is deliberately used
         * instead of sizeof(sockaddr_un): Darwin accepts paths longer than
         * the public 104-byte sun_path member when the supplied buffer and
         * length contain them.
         */
        std::array<char, SOCK_MAXADDRLEN - pathOffset + 1> guest_path = {};
        memcpy(
            guest_path.data(), host_address.data() + pathOffset,
            address_len - pathOffset);

        char host_path[PATH_MAX];
        sharedHandle.fs->pathGuestToHost(
            guest_path.data(), host_path);
        const size_t host_path_len = strlen(host_path);
        if (host_path_len > SOCK_MAXADDRLEN - pathOffset) {
            return return_with_carry_direct(ENAMETOOLONG, true);
        }

        memcpy(
            host_address.data() + pathOffset,
            host_path, host_path_len);
        address_len = static_cast<socklen_t>(
            pathOffset + host_path_len);
        host_address[0] = static_cast<char>(address_len);
    }

    return syscallRetCarry(
        SYS_bind, socket,
        reinterpret_cast<const sockaddr *>(host_address.data()),
        address_len, 0, 0, 0, 0);
}

int guest_setsockopt(int socket, int level, int option,
        u32 guest_value, socklen_t value_len) {
    if (guest_value == 0 && value_len != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    /*
     * XNU's mbuf-backed socket-option path is limited to one cluster. Keep
     * the guest from making the bridge allocate an arbitrary 32-bit length
     * before the host kernel gets a chance to reject it.
     */
    if (value_len > MCLBYTES) {
        return return_with_carry_direct(EINVAL, true);
    }

    char *value_storage = nullptr;
    const void *host_value = nullptr;
    socklen_t host_value_len = value_len;

    if (value_len != 0) {
        value_storage = static_cast<char *>(malloc(value_len));
        if (value_storage == nullptr) {
            return return_with_carry_direct(ENOMEM, true);
        }
        if (Dynarmic_mem_1read(
                guest_value, value_len, value_storage) != 0) {
            free(value_storage);
            return return_with_carry_direct(EFAULT, true);
        }
        host_value = value_storage;
    }

    struct guest_timeval32 {
        int32_t tv_sec;
        int32_t tv_usec;
    };
    struct timeval host_timeval = {};
    if (level == SOL_SOCKET &&
            (option == SO_SNDTIMEO || option == SO_RCVTIMEO) &&
            value_len >= sizeof(guest_timeval32)) {
        /* XNU accepts a larger buffer but consumes one user32_timeval. */
        const auto *guest_timeval =
            reinterpret_cast<const guest_timeval32 *>(
                value_storage);
        host_timeval.tv_sec = guest_timeval->tv_sec;
        host_timeval.tv_usec = guest_timeval->tv_usec;
        host_value = &host_timeval;
        host_value_len = sizeof(host_timeval);
    }

    const int result = syscallRetCarry(
        SYS_setsockopt, socket, level, option,
        host_value, host_value_len, 0, 0);
    free(value_storage);
    return result;
}

int guest_getsockopt(int socket, int level, int option,
        u32 guest_value, u32 guest_value_len) {
    u32 requested_len = 0;
    if (guest_value != 0) {
        /* XNU skips this copyin entirely when val is NULL. */
        if (guest_value_len == 0 || Dynarmic_mem_1read(
                guest_value_len, sizeof(requested_len),
                reinterpret_cast<char *>(&requested_len)) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }
    }

    const bool is_timeval = level == SOL_SOCKET &&
        (option == SO_SNDTIMEO || option == SO_RCVTIMEO);
    struct timeval host_timeval = {};
    std::vector<char> host_storage;
    void *host_value = nullptr;
    socklen_t host_value_len = 0;

    if (guest_value != 0) {
        if (is_timeval) {
            /*
             * The host kernel sees this process as 64-bit and therefore
             * returns two 64-bit timeval fields. Ask it for the complete
             * host value, then apply the guest's 8-byte truncation below.
             */
            host_value = &host_timeval;
            host_value_len = sizeof(host_timeval);
        } else {
            /*
             * Socket-option results are mbuf-backed. Cap the intermediate
             * host buffer while retaining getsockopt's normal behavior for
             * callers that advertise an unnecessarily large capacity.
             */
            const size_t host_capacity = std::min(
                static_cast<size_t>(requested_len),
                static_cast<size_t>(MCLBYTES));
            host_storage.resize(std::max<size_t>(host_capacity, 1));
            host_value = host_storage.data();
            host_value_len = static_cast<socklen_t>(host_capacity);
        }
    }

    const int result = syscallRetCarry(
        SYS_getsockopt, socket, level, option,
        host_value, &host_value_len, 0, 0);
    if (threadHandle.cpsr->hasCarry()) {
        return result;
    }

    u32 returned_len = 0;
    if (guest_value != 0 && is_timeval) {
        timeval_32 guest_timeval = {
            .tv_sec = static_cast<int32_t>(host_timeval.tv_sec),
            .tv_usec = static_cast<int32_t>(host_timeval.tv_usec),
        };
        returned_len = static_cast<u32>(std::min(
            static_cast<size_t>(requested_len),
            sizeof(guest_timeval)));
        if (returned_len != 0 && Dynarmic_mem_1write(
                guest_value, returned_len,
                reinterpret_cast<char *>(&guest_timeval)) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }
    } else if (guest_value != 0) {
        returned_len = static_cast<u32>(std::min({
            static_cast<size_t>(requested_len),
            static_cast<size_t>(host_value_len),
            host_storage.size()}));
        if (returned_len != 0 && Dynarmic_mem_1write(
                guest_value, returned_len,
                host_storage.data()) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }
    }

    if (Dynarmic_mem_1write(
            guest_value_len, sizeof(returned_len),
            reinterpret_cast<char *>(&returned_len)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    return return_with_carry_direct(0, false);
}

int guest_getsockname(int socket, u32 guest_address,
        u32 guest_address_len) {
    if (guest_address_len == 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    u32 requested_len = 0;
    if (Dynarmic_mem_1read(
            guest_address_len, sizeof(requested_len),
            reinterpret_cast<char *>(&requested_len)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    std::array<char, SOCK_MAXADDRLEN> host_address = {};
    socklen_t host_address_len = host_address.size();
    const int result = syscallRetCarry(
        SYS_getsockname, socket,
        reinterpret_cast<sockaddr *>(host_address.data()),
        &host_address_len, 0, 0, 0, 0);
    if (threadHandle.cpsr->hasCarry()) {
        return result;
    }

    std::array<char, SOCK_MAXADDRLEN> guest_address_storage =
        host_address;
    u32 returned_len = host_address_len;
    size_t stored_len = std::min(
        static_cast<size_t>(host_address_len),
        host_address.size());

    constexpr size_t path_offset =
        offsetof(sockaddr_un, sun_path);
    if (stored_len >= sizeof(__sockaddr_header) &&
            reinterpret_cast<const sockaddr *>(
                host_address.data())->sa_family == AF_UNIX &&
            stored_len > path_offset &&
            host_address[path_offset] == '/') {
        std::array<char,
            SOCK_MAXADDRLEN - path_offset + 1> host_path = {};
        memcpy(host_path.data(),
            host_address.data() + path_offset,
            stored_len - path_offset);

        char guest_path[PATH_MAX] = {};
        sharedHandle.fs->pathHostToGuest(
            host_path.data(), guest_path);
        const size_t guest_path_len = strlen(guest_path);
        if (guest_path_len >
                SOCK_MAXADDRLEN - path_offset) {
            return return_with_carry_direct(
                ENAMETOOLONG, true);
        }

        guest_address_storage.fill(0);
        memcpy(guest_address_storage.data(),
            host_address.data(), path_offset);
        memcpy(guest_address_storage.data() + path_offset,
            guest_path, guest_path_len);
        returned_len = static_cast<u32>(
            path_offset + guest_path_len);
        stored_len = returned_len;
        guest_address_storage[0] =
            static_cast<char>(returned_len);
    }

    const size_t copy_len = std::min(
        static_cast<size_t>(requested_len), stored_len);
    if (copy_len != 0 &&
            (guest_address == 0 ||
             Dynarmic_mem_1write(
                guest_address, copy_len,
                guest_address_storage.data()) != 0)) {
        return return_with_carry_direct(EFAULT, true);
    }
    if (Dynarmic_mem_1write(
            guest_address_len, sizeof(returned_len),
            reinterpret_cast<char *>(&returned_len)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    return return_with_carry_direct(0, false);
}

ssize_t guest_recvfrom(int syscall_number, int socket,
        u32 guest_buffer, size_t length, int flags,
        u32 guest_from, u32 guest_from_len) {
    u32 requested_from_len = 0;
    if (guest_from_len != 0 &&
            Dynarmic_mem_1read(
                guest_from_len, sizeof(requested_from_len),
                reinterpret_cast<char *>(
                    &requested_from_len)) != 0) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }
    if (length > static_cast<size_t>(INT32_MAX)) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EINVAL, true));
    }

    char *host_buffer = nullptr;
    if (length != 0) {
        host_buffer = static_cast<char *>(malloc(length));
        if (host_buffer == nullptr) {
            return static_cast<ssize_t>(
                return_with_carry_direct(ENOMEM, true));
        }
    }

    std::array<char, SOCK_MAXADDRLEN> host_from = {};
    const size_t host_from_capacity = host_from.size();
    socklen_t host_from_len = host_from.size();

    const auto receive = [&](int receive_flags) {
        return debugger_aware_host_wait(
            [&] {
                return static_cast<ssize_t>(
                    syscallRetCarry(
                        syscall_number, socket, host_buffer,
                        length, receive_flags,
                        reinterpret_cast<sockaddr *>(
                            host_from.data()),
                        &host_from_len,
                        0));
            },
            static_cast<ssize_t>(
                return_with_carry_direct(EINTR, true)));
    };

    bool can_probe_without_blocking =
        (flags & MSG_DONTWAIT) == 0 &&
        GuestThreadCanYieldBeforeBlocking();
    if (can_probe_without_blocking) {
        const int socket_flags = ::fcntl(
            socket, F_GETFL);
        if (socket_flags >= 0 &&
                (socket_flags & O_NONBLOCK) != 0) {
            can_probe_without_blocking = false;
        }
    }
    if (can_probe_without_blocking) {
        int socket_type = 0;
        socklen_t socket_type_len = sizeof(socket_type);
        can_probe_without_blocking =
            ::getsockopt(socket, SOL_SOCKET, SO_TYPE,
                &socket_type, &socket_type_len) == 0 &&
            socket_type == SOCK_DGRAM;
    }

    ssize_t result;
    if (can_probe_without_blocking) {
        result = receive(flags | MSG_DONTWAIT);
        if (threadHandle.cpsr->hasCarry() &&
                (result == EAGAIN || result == EWOULDBLOCK)) {
            if (GuestThreadYieldBeforeBlocking()) {
                free(host_buffer);
                return static_cast<ssize_t>(
                    return_with_carry_direct(EINTR, true));
            }
            host_from_len = static_cast<socklen_t>(
                host_from_capacity);
            result = receive(flags);
        }
    } else {
        result = receive(flags);
    }
    if (threadHandle.cpsr->hasCarry()) {
        free(host_buffer);
        return result;
    }

    if (result > 0 &&
            (guest_buffer == 0 ||
             Dynarmic_mem_1write(
                guest_buffer,
                std::min(
                    static_cast<size_t>(result), length),
                host_buffer) != 0)) {
        free(host_buffer);
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }
    free(host_buffer);

    /*
     * XNU only copies out the source address and its actual, untruncated
     * length when both the source buffer and length pointer are present.
     */
    if (guest_from == 0 || guest_from_len == 0) {
        return return_with_carry_direct(
            static_cast<int>(result), false);
    }

    std::array<char, SOCK_MAXADDRLEN> guest_from_storage =
        host_from;
    u32 returned_from_len = requested_from_len != 0
        ? host_from_len
        : 0;
    size_t stored_from_len = std::min(
        static_cast<size_t>(host_from_len),
        host_from_capacity);

    constexpr size_t path_offset =
        offsetof(sockaddr_un, sun_path);
    if (requested_from_len != 0 &&
            host_from_len <= host_from_capacity &&
            stored_from_len >= sizeof(__sockaddr_header) &&
            reinterpret_cast<const sockaddr *>(
                host_from.data())->sa_family == AF_UNIX &&
            stored_from_len > path_offset &&
            host_from[path_offset] == '/') {
        std::array<char,
            SOCK_MAXADDRLEN - path_offset + 1> host_path = {};
        memcpy(host_path.data(),
            host_from.data() + path_offset,
            stored_from_len - path_offset);

        char guest_path[PATH_MAX] = {};
        sharedHandle.fs->pathHostToGuest(
            host_path.data(), guest_path);
        const size_t guest_path_len = strlen(guest_path);
        if (guest_path_len >
                SOCK_MAXADDRLEN - path_offset) {
            return static_cast<ssize_t>(
                return_with_carry_direct(
                    ENAMETOOLONG, true));
        }

        guest_from_storage.fill(0);
        memcpy(guest_from_storage.data(),
            host_from.data(), path_offset);
        memcpy(guest_from_storage.data() + path_offset,
            guest_path, guest_path_len);
        returned_from_len = static_cast<u32>(
            path_offset + guest_path_len);
        stored_from_len = returned_from_len;
        guest_from_storage[0] =
            static_cast<char>(returned_from_len);
    }

    const size_t copy_from_len = std::min(
        static_cast<size_t>(requested_from_len),
        stored_from_len);
    if (copy_from_len != 0 &&
            Dynarmic_mem_1write(
                guest_from, copy_from_len,
                guest_from_storage.data()) != 0) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }
    if (Dynarmic_mem_1write(
            guest_from_len, sizeof(returned_from_len),
            reinterpret_cast<char *>(
                &returned_from_len)) != 0) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }
    return return_with_carry_direct(
        static_cast<int>(result), false);
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

    return debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                SYS_connect, socket,
                reinterpret_cast<const sockaddr *>(
                    host_address),
                address_len, 0, 0, 0, 0);
        },
        return_with_carry_direct(EINTR, true));
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
    int result = debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                SYS_sendto, socket, host_buffer, length,
                flags,
                reinterpret_cast<const sockaddr *>(
                    host_dest_addr),
                dest_len, 0);
        },
        return_with_carry_direct(EINTR, true));
    free(host_buffer);
    free(host_dest_addr);
    return result;
}

ssize_t guest_pread(int NR, int fildes, u32 guest_buf, size_t nbyte, off_t offset) {
    char *host_buf = (char *)malloc(nbyte);
    ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(
                syscallRetCarry(
                    NR, fildes, host_buf, nbyte,
                    offset, 0, 0, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
    if (!threadHandle.cpsr->hasCarry() && result > 0) {
        Dynarmic_mem_1write(
            guest_buf,
            std::min(static_cast<size_t>(result), nbyte),
            host_buf);
    }
    free(host_buf);
    return result;
}

ssize_t guest_read(int NR, int fildes, u32 guest_buf, size_t nbyte) {
    char *host_buf = (char *)malloc(nbyte);
    ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(
                syscallRetCarry(
                    NR, fildes, host_buf, nbyte,
                    0, 0, 0, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
    if (!threadHandle.cpsr->hasCarry() && result > 0) {
        Dynarmic_mem_1write(
            guest_buf,
            std::min(static_cast<size_t>(result), nbyte),
            host_buf);
    }
    free(host_buf);
    return result;
}

ssize_t guest_write(int NR, int fildes, u32 guest_buf, size_t nbyte) {
    char *host_buf = (char *)malloc(nbyte);
    Dynarmic_mem_1read(guest_buf, nbyte, host_buf);
    ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(
                syscallRetCarry(
                    NR, fildes, host_buf, nbyte,
                    0, 0, 0, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
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
    int result = debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                NR, host_path, oflag, mode,
                0, 0, 0, 0);
        },
        return_with_carry_direct(EINTR, true));
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

int guest_mkdir(u32 guest_path, mode_t mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_mkdir, host_path, mode, 0,0,0,0,0);
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
    SetPendingGuestCrashMessage(
        "Unhandled ioctl request %u (0x%x)", request, request);
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
            return syscallRetCarry(SYS_fcntl, fildes, cmd, guest_r2, 0,0,0,0);
        case F_FULLFSYNC:
            return debugger_aware_host_wait(
                [&] {
                    return syscallRetCarry(
                        SYS_fcntl, fildes, cmd,
                        guest_r2, 0, 0, 0, 0);
                },
                return_with_carry_direct(EINTR, true));
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
            return debugger_aware_host_wait(
                [&] {
                    return syscallRetCarry(
                        SYS_fcntl, fildes, cmd,
                        &host_r2, 0, 0, 0, 0);
                },
                return_with_carry_direct(EINTR, true));
        }
        case F_SETSIZE: {
            off_t host_r2 =
                CurrentUserCallbacks()->MemoryRead64(guest_r2);
            return debugger_aware_host_wait(
                [&] {
                    return syscallRetCarry(
                        SYS_fcntl, fildes, cmd,
                        &host_r2, 0, 0, 0, 0);
                },
                return_with_carry_direct(EINTR, true));
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
            SetPendingGuestCrashMessage(
                "Unhandled fcntl command %d", cmd);
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
    GuestAbortMetadata metadata;
    metadata.valid = true;
    metadata.reasonNamespace = reason_namespace;
    metadata.reasonCode = reason_code;
    metadata.payloadSize = payload_size;
    metadata.reasonFlags = reason_flags;
    metadata.reason = CopyGuestCStringForCrash(
        guest_reason_string, 16 * 1024);
    pendingGuestAbortMetadata = std::move(metadata);

    fprintf(stderr,
        "abort_with_payload called with namespace=0x%x, "
        "code=0x%llx, payload=0x%08x/0x%x, flags=0x%llx, "
        "reason=%s\n",
        reason_namespace,
        static_cast<unsigned long long>(reason_code),
        guest_payload, payload_size,
        static_cast<unsigned long long>(reason_flags),
        pendingGuestAbortMetadata.reason.empty()
            ? "(none)"
            : pendingGuestAbortMetadata.reason.c_str());
    return 0;
}

////////
int guestMappingLen = 0;
guest_file_mapping guestMappings[1000];
size_t guestMappingGeneration = 0;

static std::vector<GuestImageSnapshot> SnapshotGuestImages() {
    std::lock_guard<std::mutex> lock(guestMappingMutex);
    std::vector<GuestImageSnapshot> images;
    const int count = std::max(0, std::min(guestMappingLen, 1000));
    images.reserve(static_cast<size_t>(count));
    for (int index = 0; index < count; ++index) {
        const guest_file_mapping &mapping = guestMappings[index];
        images.push_back({
            mapping.start,
            mapping.end,
            mapping.name != nullptr
                ? std::string(mapping.name,
                    strnlen(mapping.name, PATH_MAX))
                : "(unknown image)",
        });
    }
    return images;
}

static bool GuestImageLoadCommandsAreSane(
        const mach_header *header) {
    return header != nullptr && header->magic == MH_MAGIC &&
        header->ncmds <= 4096 && header->sizeofcmds <= 1024 * 1024;
}

struct GuestMachOImage {
    mach_header header{};
    std::vector<uint8_t> loadCommands;
};

static bool ReadGuestMachOImage(
        const GuestImageSnapshot &mapping,
        GuestMachOImage &image) {
    if (!read_guest_memory_with_permissions(
            mapping.start, &image.header, sizeof(image.header),
            PROT_READ) ||
            !GuestImageLoadCommandsAreSane(&image.header)) {
        return false;
    }

    image.loadCommands.resize(image.header.sizeofcmds);
    return image.loadCommands.empty() ||
        read_guest_memory_with_permissions(
            static_cast<u64>(mapping.start) + sizeof(image.header),
            image.loadCommands.data(), image.loadCommands.size(),
            PROT_READ);
}

static u32 GuestImageSlide(
        const GuestImageSnapshot &mapping,
        const GuestMachOImage &image) {
    size_t cursor = 0;
    for (uint32_t index = 0; index < image.header.ncmds; ++index) {
        if (cursor + sizeof(load_command) > image.loadCommands.size()) {
            break;
        }
        load_command command{};
        memcpy(&command, image.loadCommands.data() + cursor,
            sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
                command.cmdsize > image.loadCommands.size() - cursor) {
            break;
        }
        if (command.cmd == LC_SEGMENT &&
                command.cmdsize >= sizeof(segment_command)) {
            segment_command segment{};
            memcpy(&segment, image.loadCommands.data() + cursor,
                sizeof(segment));
            if (strncmp(segment.segname, "__PAGEZERO",
                    sizeof(segment.segname)) != 0) {
                return mapping.start - segment.vmaddr;
            }
        }
        cursor += command.cmdsize;
    }
    return mapping.start;
}

struct GuestCrashAnnotation {
    std::string imageName;
    std::string message;
    uint64_t abortCause = 0;
};

static std::vector<GuestCrashAnnotation>
CollectGuestCrashAnnotations(
        const std::vector<GuestImageSnapshot> &images) {
    std::vector<GuestCrashAnnotation> annotations;
    std::unordered_set<std::string> seenMessages;
    size_t annotationBytes = 0;
    for (const GuestImageSnapshot &mapping : images) {
        if (annotations.size() >= LC32_CRASH_ANNOTATIONS_MAX ||
                annotationBytes >= LC32_CRASH_ANNOTATION_BYTES_MAX) {
            break;
        }
        GuestMachOImage image;
        if (!ReadGuestMachOImage(mapping, image)) {
            continue;
        }
        const u32 slide = GuestImageSlide(mapping, image);
        size_t cursor = 0;
        u32 crashInfoAddress = 0;
        uint32_t crashInfoSize = 0;
        for (uint32_t index = 0; index < image.header.ncmds; ++index) {
            if (cursor + sizeof(load_command) > image.loadCommands.size()) {
                break;
            }
            load_command command{};
            memcpy(&command, image.loadCommands.data() + cursor,
                sizeof(command));
            if (command.cmdsize < sizeof(load_command) ||
                    command.cmdsize > image.loadCommands.size() - cursor) {
                break;
            }
            if (command.cmd == LC_SEGMENT &&
                    command.cmdsize >= sizeof(segment_command)) {
                segment_command segment{};
                memcpy(&segment, image.loadCommands.data() + cursor,
                    sizeof(segment));
                const size_t sectionsBytes =
                    command.cmdsize - sizeof(segment_command);
                if (segment.nsects <=
                        sectionsBytes / sizeof(section)) {
                    for (uint32_t sectionIndex = 0;
                            sectionIndex < segment.nsects; ++sectionIndex) {
                        section currentSection{};
                        memcpy(&currentSection,
                            image.loadCommands.data() + cursor +
                                sizeof(segment_command) +
                                static_cast<size_t>(sectionIndex) *
                                    sizeof(section),
                            sizeof(currentSection));
                        if (strncmp(currentSection.sectname,
                                "__crash_info",
                                sizeof(currentSection.sectname)) == 0) {
                            const u64 address = static_cast<u64>(slide) +
                                currentSection.addr;
                            if (address <= UINT32_MAX) {
                                crashInfoAddress = static_cast<u32>(address);
                                crashInfoSize = currentSection.size;
                            }
                            break;
                        }
                    }
                }
            }
            if (crashInfoAddress != 0) {
                break;
            }
            cursor += command.cmdsize;
        }

        if (crashInfoAddress == 0 ||
                crashInfoSize < sizeof(crashreporter_annotations_t)) {
            continue;
        }
        crashreporter_annotations_t annotation{};
        if (!read_guest_memory_with_permissions(
                crashInfoAddress, &annotation, sizeof(annotation),
                PROT_READ)) {
            continue;
        }
        const uint64_t messageAddresses[] = {
            annotation.message,
            annotation.message2,
        };
        for (const uint64_t messageAddress : messageAddresses) {
            const size_t remainingBytes =
                LC32_CRASH_ANNOTATION_BYTES_MAX - annotationBytes;
            if (annotations.size() >= LC32_CRASH_ANNOTATIONS_MAX ||
                    remainingBytes == 0) {
                break;
            }
            std::string message = CopyGuestCStringForCrash(
                messageAddress,
                std::min<size_t>(16 * 1024, remainingBytes));
            if (message.size() > remainingBytes) {
                message.resize(remainingBytes);
            }
            if (message.empty() || !seenMessages.insert(message).second) {
                continue;
            }
            annotationBytes += message.size();
            annotations.push_back({
                mapping.name,
                std::move(message),
                annotation.abort_cause,
            });
        }
    }
    return annotations;
}

static void load_symbols_for_image(
        const GuestImageSnapshot &mapping,
        void (^iterator)(u32 address, const char *name)) {
    GuestMachOImage image;
    if (!ReadGuestMachOImage(mapping, image)) {
        return;
    }
    const u32 slide = GuestImageSlide(mapping, image);
    symtab_command symbolTable{};
    bool foundSymbolTable = false;
    size_t cursor = 0;
    for (uint32_t index = 0; index < image.header.ncmds; ++index) {
        if (cursor + sizeof(load_command) > image.loadCommands.size()) {
            break;
        }
        load_command command{};
        memcpy(&command, image.loadCommands.data() + cursor,
            sizeof(command));
        if (command.cmdsize < sizeof(load_command) ||
                command.cmdsize > image.loadCommands.size() - cursor) {
            break;
        }
        if (command.cmd == LC_SYMTAB &&
                command.cmdsize >= sizeof(symtab_command)) {
            memcpy(&symbolTable, image.loadCommands.data() + cursor,
                sizeof(symbolTable));
            foundSymbolTable = true;
            break;
        }
        cursor += command.cmdsize;
    }

    iterator(mapping.start, "(unknown symbol)");
    if (!foundSymbolTable ||
            symbolTable.nsyms > LC32_CRASH_SYMBOLS_MAX) {
        return;
    }

    const u64 symbolTableAddress =
        static_cast<u64>(mapping.start) + symbolTable.symoff;
    const u64 stringTableAddress =
        static_cast<u64>(mapping.start) + symbolTable.stroff;
    if (!GuestAddressRangeIsValid32(symbolTableAddress,
            static_cast<u64>(symbolTable.nsyms) * sizeof(struct nlist)) ||
            !GuestAddressRangeIsValid32(
                stringTableAddress, symbolTable.strsize)) {
        return;
    }
    for (uint32_t index = 0; index < symbolTable.nsyms; ++index) {
        const u64 entryAddress = symbolTableAddress +
            static_cast<u64>(index) * sizeof(struct nlist);
        struct nlist entry{};
        if (!read_guest_memory_with_permissions(
                entryAddress, &entry, sizeof(entry), PROT_READ)) {
            break;
        }
        if (entry.n_un.n_strx == 0 ||
                entry.n_un.n_strx >= symbolTable.strsize ||
                entry.n_value == 0) {
            continue;
        }
        const u64 resolvedAddress =
            static_cast<u64>(entry.n_value) + slide;
        if (resolvedAddress < mapping.start ||
                resolvedAddress >= mapping.end) {
            continue;
        }
        const size_t maximumNameLength = std::min<size_t>(
            1024, symbolTable.strsize - entry.n_un.n_strx);
        std::string name = CopyGuestCStringForCrash(
            stringTableAddress + entry.n_un.n_strx,
            maximumNameLength);
        if (!name.empty()) {
            iterator(static_cast<u32>(resolvedAddress), name.c_str());
        }
    }
}

static void symbolicate_call_stack(
        symbolicated_call *callStack, int callStackLen,
        const std::vector<GuestImageSnapshot> &images) {
    for (const GuestImageSnapshot &mapping : images) {
        bool containsFrame = false;
        for (int index = 0; index < callStackLen; ++index) {
            symbolicated_call &call = callStack[index];
            if (call.address >= mapping.start && call.address < mapping.end) {
                call.imageName = mapping.name;
                call.symbolOffset = call.address - mapping.start;
                containsFrame = true;
            }
        }
        if (!containsFrame) {
            continue;
        }
        load_symbols_for_image(mapping, ^(u32 address, const char *name) {
            for (int index = 0; index < callStackLen; ++index) {
                symbolicated_call &call = callStack[index];
                if (call.address < mapping.start ||
                        call.address >= mapping.end ||
                        call.address < address) {
                    continue;
                }
                const u32 offset = call.address - address;
                if (call.symbolName.empty() || offset < call.symbolOffset) {
                    call.imageName = mapping.name;
                    call.symbolName = name;
                    call.symbolOffset = offset;
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
      char *fastPage = static_cast<char *>(
          __atomic_load_n(
              &page_table[idx], __ATOMIC_ACQUIRE));
      if (fastPage != nullptr) {
        return fastPage;
      }
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

static int HostProtectionForGuestPermissions(
        int permissions) {
    int hostProtection =
        permissions & (PROT_READ | PROT_WRITE);
    /*
     * Guest execute permission is implemented by MemoryReadCode rather than
     * host execution, but translating execute-only pages still needs to read
     * their instruction bytes.
     */
    if ((permissions & PROT_EXEC) != 0) {
        hostProtection |= PROT_READ;
    }
    return hostProtection;
}

static void *GuestPageTablePointer(
        const t_memory_page page) {
    if (page == nullptr || page->addr == nullptr) {
        return nullptr;
    }
    if (page->enforceDataPermissions &&
            (page->perms &
                (PROT_READ | PROT_WRITE)) !=
                (PROT_READ | PROT_WRITE)) {
        return nullptr;
    }
    return page->addr;
}

static char *get_memory_page_with_permissions(
        u64 vaddr, int requiredPermissions) {
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    khash_t(memory) *memory = sharedHandle.memory;
    if (memory == nullptr) {
        return nullptr;
    }
    const u64 base = vaddr & ~DYN_PAGE_MASK;
    const khiter_t iterator =
        kh_get(memory, memory, base);
    if (iterator == kh_end(memory)) {
        return nullptr;
    }
    const t_memory_page page =
        kh_value(memory, iterator);
    if (page == nullptr ||
            (page->perms & requiredPermissions) !=
                requiredPermissions) {
        return nullptr;
    }
    return static_cast<char *>(page->addr);
}

static bool GuestAddressRangeIsValid32(
        u64 address, u64 size) {
    constexpr u64 addressSpaceSize =
        UINT64_C(1) << 32;
    return address < addressSpaceSize &&
        size <= addressSpaceSize - address;
}

static bool GuestProtectionIsValid(int protection) {
    constexpr int supportedProtection =
        PROT_READ | PROT_WRITE | PROT_EXEC;
    return (protection & ~supportedProtection) == 0;
}

static bool read_guest_memory_with_permissions(
        u64 address, void *destination, size_t size,
        int requiredPermissions) {
    if (!GuestAddressRangeIsValid32(
            address, size)) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    u64 validationAddress = address;
    size_t validationSize = size;
    while (validationSize != 0) {
        if (get_memory_page_with_permissions(
                validationAddress,
                requiredPermissions) == nullptr) {
            return false;
        }
        const size_t pageOffset =
            validationAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            validationSize,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        validationAddress += chunk;
        validationSize -= chunk;
    }

    auto *output = static_cast<uint8_t *>(
        destination);
    while (size != 0) {
        char *page =
            get_memory_page_with_permissions(
                address, requiredPermissions);
        if (page == nullptr) {
            return false;
        }
        const size_t pageOffset =
            address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            size,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        memcpy(output, page + pageOffset, chunk);
        output += chunk;
        address += chunk;
        size -= chunk;
    }
    return true;
}

static std::string CopyGuestCStringForCrash(
        u64 guestAddress, size_t maximumLength) {
    if (guestAddress == 0 || maximumLength == 0 ||
            guestAddress > UINT32_MAX) {
        return {};
    }

    std::string result;
    result.reserve(std::min<size_t>(maximumLength, 256));
    while (result.size() < maximumLength) {
        const u64 address = guestAddress + result.size();
        if (address > UINT32_MAX) {
            break;
        }
        const size_t pageRemaining =
            DYN_PAGE_SIZE - (address & DYN_PAGE_MASK);
        const size_t chunkLength = std::min(
            maximumLength - result.size(), pageRemaining);
        std::array<char, DYN_PAGE_SIZE> chunk{};
        if (!read_guest_memory_with_permissions(
                address, chunk.data(), chunkLength,
                PROT_READ)) {
            break;
        }
        const void *terminator =
            memchr(chunk.data(), '\0', chunkLength);
        const size_t copiedLength = terminator != nullptr
            ? static_cast<const char *>(terminator) - chunk.data()
            : chunkLength;
        result.append(chunk.data(), copiedLength);
        if (terminator != nullptr) {
            return result;
        }
    }
    if (result.size() == maximumLength) {
        result.append(" [truncated]");
    } else if (!result.empty()) {
        result.append(" [unreadable]");
    }
    return result;
}

static bool write_guest_memory_with_permissions(
        u64 address, const void *source, size_t size,
        int requiredPermissions) {
    if (!GuestAddressRangeIsValid32(
            address, size)) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    /*
     * Validate the complete range before modifying it. An unaligned scalar
     * store may span two guest pages; discovering a protected second page
     * after writing the first would make a faulting instruction partially
     * visible even though it has not retired.
     */
    u64 validationAddress = address;
    size_t validationSize = size;
    while (validationSize != 0) {
        if (get_memory_page_with_permissions(
                validationAddress,
                requiredPermissions) == nullptr) {
            return false;
        }
        const size_t pageOffset =
            validationAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            validationSize,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        validationAddress += chunk;
        validationSize -= chunk;
    }

    const auto *input =
        static_cast<const uint8_t *>(source);
    while (size != 0) {
        char *page =
            get_memory_page_with_permissions(
                address, requiredPermissions);
        if (page == nullptr) {
            return false;
        }
        const size_t pageOffset =
            address & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            size,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        memcpy(page + pageOffset, input, chunk);
        input += chunk;
        address += chunk;
        size -= chunk;
    }
    return true;
}

enum class ExclusiveGuestWriteResult {
    Committed,
    ComparisonFailed,
    Fault,
};

template<typename T>
static ExclusiveGuestWriteResult
compare_exchange_guest_memory_with_permissions(
        u64 address, T value, T expected) {
    if (!GuestAddressRangeIsValid32(
            address, sizeof(T))) {
        return ExclusiveGuestWriteResult::Fault;
    }

    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);

    /*
     * An exclusive write is one memory transaction: first validate the full
     * write range, then compare and commit without dropping guestVmMutex.
     * In particular, an unaligned value spanning two guest pages must neither
     * report success nor modify its first page if the second page is not
     * writable.
     *
     * Reading the comparison value is an implementation detail of the
     * exclusive monitor, so only guest write permission is required here.
     */
    u64 validationAddress = address;
    size_t validationSize = sizeof(T);
    while (validationSize != 0) {
        if (get_memory_page_with_permissions(
                validationAddress,
                PROT_WRITE) == nullptr) {
            return ExclusiveGuestWriteResult::Fault;
        }
        const size_t pageOffset =
            validationAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            validationSize,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        validationAddress += chunk;
        validationSize -= chunk;
    }

    T current{};
    auto *currentBytes =
        reinterpret_cast<uint8_t *>(&current);
    u64 readAddress = address;
    size_t remaining = sizeof(T);
    while (remaining != 0) {
        char *page =
            get_memory_page_with_permissions(
                readAddress, PROT_WRITE);
        const size_t pageOffset =
            readAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            remaining,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        memcpy(currentBytes, page + pageOffset, chunk);
        currentBytes += chunk;
        readAddress += chunk;
        remaining -= chunk;
    }

    if (memcmp(
            &current, &expected, sizeof(T)) != 0) {
        return ExclusiveGuestWriteResult::
            ComparisonFailed;
    }

    const auto *valueBytes =
        reinterpret_cast<const uint8_t *>(&value);
    u64 writeAddress = address;
    remaining = sizeof(T);
    while (remaining != 0) {
        char *page =
            get_memory_page_with_permissions(
                writeAddress, PROT_WRITE);
        const size_t pageOffset =
            writeAddress & DYN_PAGE_MASK;
        const size_t chunk = std::min(
            remaining,
            static_cast<size_t>(
                DYN_PAGE_SIZE - pageOffset));
        memcpy(page + pageOffset, valueBytes, chunk);
        valueBytes += chunk;
        writeAddress += chunk;
        remaining -= chunk;
    }
    return ExclusiveGuestWriteResult::Committed;
}

static void AppendCrashReportText(
        std::string &report, const std::string &text) {
    constexpr char truncatedMarker[] = "\n[report truncated]\n";
    constexpr size_t markerLength = sizeof(truncatedMarker) - 1;
    constexpr size_t payloadLimit =
        LC32_FULL_CRASH_REPORT_MAX - markerLength;
    if (text.empty()) {
        return;
    }
    if (report.size() >= payloadLimit) {
        if (report.size() == payloadLimit) {
            report.append(truncatedMarker, markerLength);
        }
        return;
    }
    const size_t available = payloadLimit - report.size();
    if (text.size() <= available) {
        report.append(text);
        return;
    }
    report.append(text.data(), available);
    report.append(truncatedMarker, markerLength);
}

static void AppendCrashReportFormat(
        std::string &report, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    const std::string formatted = FormatString(format, arguments);
    va_end(arguments);
    AppendCrashReportText(report, formatted);
}

static const char *GuestSignalName(int signal) {
    switch (signal) {
        case SIGABRT: return "SIGABRT";
        case SIGBUS: return "SIGBUS";
        case SIGILL: return "SIGILL";
        case SIGINT: return "SIGINT";
        case SIGSEGV: return "SIGSEGV";
        case SIGSYS: return "SIGSYS";
        case SIGTRAP: return "SIGTRAP";
        default: return "unknown";
    }
}

static std::string GuestImageBasename(const std::string &path) {
    const size_t separator = path.find_last_of('/');
    return separator == std::string::npos
        ? path
        : path.substr(separator + 1);
}

static std::string SanitizeCompactCrashText(
        const std::string &text, size_t maximumLength) {
    std::string result;
    result.reserve(std::min(text.size(), maximumLength));
    bool previousWasSpace = false;
    bool truncated = false;
    for (const unsigned char character : text) {
        const bool whitespace = character == '\n' || character == '\r' ||
            character == '\t';
        const unsigned char output = whitespace ? ' ' : character;
        if (output == ' ' && previousWasSpace) {
            continue;
        }
        if (output < 0x20 || output == 0x7f) {
            continue;
        }
        if (result.size() == maximumLength) {
            truncated = true;
            break;
        }
        result.push_back(static_cast<char>(output));
        previousWasSpace = output == ' ';
    }
    if (truncated && result.size() >= 3) {
        result.replace(result.size() - 3, 3, "...");
    }
    return result;
}

static void PublishGuestCrashReport(const std::string &report) {
    char *persistentReport = static_cast<char *>(
        malloc(report.size() + 1));
    if (persistentReport != nullptr) {
        memcpy(persistentReport, report.c_str(), report.size() + 1);
        __atomic_store_n(
            &__crashreporter_info__, persistentReport,
            __ATOMIC_RELEASE);
    }

    if (!report.empty()) {
        fwrite(report.data(), 1, report.size(), stderr);
        if (report.back() != '\n') {
            fputc('\n', stderr);
        }
    }
    fflush(stderr);
}

static bool GuestAbortReasonIsUsable(
        const GuestAbortMetadata &metadata) {
    return metadata.valid && metadata.reasonNamespace > 0 &&
        metadata.reasonNamespace <=
            LC32_OS_REASON_MAX_VALID_NAMESPACE;
}

static uint32_t GuestAbortReasonNamespace(
        const GuestAbortMetadata &metadata) {
    return GuestAbortReasonIsUsable(metadata)
        ? metadata.reasonNamespace
        : LC32_OS_REASON_LIBSYSTEM;
}

static uint64_t GuestAbortReasonCode(
        const GuestAbortMetadata &metadata) {
    return GuestAbortReasonIsUsable(metadata)
        ? metadata.reasonCode
        : LC32_GUEST_CRASH_REASON_CODE;
}

[[noreturn]] static void AbortHostWithGuestCrashReport(
        const GuestAbortMetadata &metadata,
        const std::string &fullReport,
        std::string compactReason) {
    PublishGuestCrashReport(fullReport);
    if (compactReason.empty()) {
        compactReason = "LiveExec32 guest process crashed";
    }
    if (compactReason.size() > LC32_OS_REASON_STRING_MAX) {
        compactReason.resize(LC32_OS_REASON_STRING_MAX);
    }

    const uint32_t reasonNamespace =
        GuestAbortReasonNamespace(metadata);
    const uint64_t reasonCode =
        GuestAbortReasonCode(metadata);

    /*
     * Do not propagate NO_CRASH_REPORT or private guest-era flags. Passing
     * zero asks the host kernel for its normal abort report while retaining
     * the guest namespace and code above.
     */
    abort_with_reason(
        reasonNamespace, reasonCode, compactReason.c_str(), 0);
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

    bool IsReadOnlyMemory(
            u32 vaddr __attribute__((unused)))
            override {
        /*
         * Debugger writes and later mprotect calls can still change a
         * read-only page. Keep this conservative so Dynarmic never embeds a
         * value as permanently immutable.
         */
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
        uint32_t result = 0;
        if (!read_guest_memory_with_permissions(
                vaddr, &result, sizeof(result),
                PROT_EXEC)) {
            return std::nullopt;
        }
        return result;
    }
    u16 MemoryReadThumbCode(u32 vaddr) {
        u16 code = 0;
        if (!read_guest_memory_with_permissions(
                vaddr, &code, sizeof(code),
                PROT_EXEC)) {
            return 0;
        }
//        printf("MemoryReadThumbCode[%s->%s:%d]: vaddr=0x%x, code=0x%04x\n", __FILE__, __func__, __LINE__, vaddr, code);
        return code;
    }

    /*
     * Yield to the remote debugger without running the built-in backtrace.
     * The latter reads more guest memory and can recursively fault before
     * gdbstub gets a chance to report the original stop.
     */
    void StopForDebugger(int signal, bool pendingSignal) {
        RecordGuestStopSignal(signal, pendingSignal);
        cpu->HaltExecution(LC32HaltReasonTrap);
    }

// FIXME: sometimes it will try to access 0x4, 0x8 and 0xc, I disassembled and found nothing, is there something to do with cpsr? For now let it do stuff in an empty page...
    void HandleBadMemoryAccess(
            const char *operation, u32 address) {
#if !IGNORE_BAD_MEM_ACCESS
        SetPendingGuestCrashMessage(
            "%s at guest address 0x%08x", operation, address);
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
        u8 value = 0;
        if (read_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_READ)) {
#if TRACE_RW
            printf("Trace: read08(0x%04x) = 0x%01x\n", vaddr, value);
#endif
            return value;
        } else {
            fprintf(stderr, "MemoryRead8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryRead8", vaddr);
            return 0;
        }
    }
    u16 MemoryRead16(u32 vaddr, bool trace) {
        u16 value = 0;
        if (read_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_READ)) {
#if TRACE_RW
            if (trace)
            printf("Trace: read16(0x%04x) = 0x%02x\n", vaddr, value);
#endif
            return value;
        } else {
            fprintf(stderr, "MemoryRead16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            // trace = tolerance bad mem access, else crash
            if(trace) {
                HandleBadMemoryAccess("MemoryRead16", vaddr);
            } else {
                SetPendingGuestCrashMessage(
                    "MemoryRead16 at guest address 0x%08x", vaddr);
                DumpCrashReport(SIGSEGV);
            }
            return 0;
        }
    }
    u16 MemoryRead16(u32 vaddr) override {
        return MemoryRead16(vaddr, true);
    }
    u32 MemoryRead32(u32 vaddr, bool trace) {
        u32 value = 0;
        if (read_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_READ)) {
            //printf("MemoryRead32[%s->%s:%d]: vaddr=0x%x, value=0x%x\n", __FILE__, __func__, __LINE__, vaddr, dest[0]);
#if TRACE_RW
            if (trace)
            printf("Trace: read32(0x%04x) = 0x%04x\n", vaddr, value);
#endif
            return value;
        } else {
            fprintf(stderr, "MemoryRead32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            // trace = tolerance bad mem access, else crash
            if(trace) {
                HandleBadMemoryAccess("MemoryRead32", vaddr);
            } else {
                SetPendingGuestCrashMessage(
                    "MemoryRead32 at guest address 0x%08x", vaddr);
                DumpCrashReport(SIGSEGV);
            }
            return 0;
        }
    }
    u32 MemoryRead32(u32 vaddr) override {
        return MemoryRead32(vaddr, true);
    }
    u64 MemoryRead64(u32 vaddr) override {
        u64 value = 0;
        if (read_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_READ)) {
#if TRACE_RW
            printf("Trace: read64(0x%04x) = 0x%08llx\n", vaddr, value);
#endif
            return value;
        } else {
            fprintf(stderr, "MemoryRead64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryRead64", vaddr);
            return 0;
        }
    }

    void MemoryWrite8(u32 vaddr, u8 value) override {
        if (write_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_WRITE)) {
#if TRACE_RW
            printf("Trace: write08(0x%04x) = 0x%01x\n", vaddr, value);
#endif
        } else {
            fprintf(stderr, "MemoryWrite8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWrite8", vaddr);
        }
    }
    void MemoryWrite16(u32 vaddr, u16 value) override {
        if (write_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_WRITE)) {
#if TRACE_RW
            printf("Trace: write16(0x%04x) = 0x%02x\n", vaddr, value);
#endif
        } else {
            fprintf(stderr, "MemoryWrite16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWrite16", vaddr);
        }
    }
    void MemoryWrite32(u32 vaddr, u32 value) override {
        if (write_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_WRITE)) {
#if TRACE_RW
            printf("Trace: write32(0x%04x) = 0x%04x\n", vaddr, value);
#endif
        } else {
            fprintf(stderr, "MemoryWrite32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWrite32", vaddr);
        }
    }
    void MemoryWrite64(u32 vaddr, u64 value) override {
        if (write_guest_memory_with_permissions(
                vaddr, &value, sizeof(value),
                PROT_WRITE)) {
#if TRACE_RW
            printf("Trace: write64(0x%04x) = 0x%08llx\n", vaddr, value);
#endif
        } else {
            fprintf(stderr, "MemoryWrite64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWrite64", vaddr);
        }
    }

    bool MemoryWriteExclusive8(u32 vaddr, u8 value, u8 expected) override {
        const ExclusiveGuestWriteResult result =
            compare_exchange_guest_memory_with_permissions(
                vaddr, value, expected);
        if (result == ExclusiveGuestWriteResult::Fault) {
            fprintf(stderr, "MemoryWriteExclusive8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWriteExclusive8", vaddr);
        }
        return result ==
            ExclusiveGuestWriteResult::Committed;
    }
    bool MemoryWriteExclusive16(u32 vaddr, u16 value, u16 expected) override {
        const ExclusiveGuestWriteResult result =
            compare_exchange_guest_memory_with_permissions(
                vaddr, value, expected);
        if (result == ExclusiveGuestWriteResult::Fault) {
            fprintf(stderr, "MemoryWriteExclusive16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWriteExclusive16", vaddr);
        }
        return result ==
            ExclusiveGuestWriteResult::Committed;
    }
    bool MemoryWriteExclusive32(u32 vaddr, u32 value, u32 expected) override {
        const ExclusiveGuestWriteResult result =
            compare_exchange_guest_memory_with_permissions(
                vaddr, value, expected);
        if (result == ExclusiveGuestWriteResult::Fault) {
            fprintf(stderr, "MemoryWriteExclusive32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWriteExclusive32", vaddr);
        }
        return result ==
            ExclusiveGuestWriteResult::Committed;
    }
    bool MemoryWriteExclusive64(u32 vaddr, u64 value, u64 expected) override {
        const ExclusiveGuestWriteResult result =
            compare_exchange_guest_memory_with_permissions(
                vaddr, value, expected);
        if (result == ExclusiveGuestWriteResult::Fault) {
            fprintf(stderr, "MemoryWriteExclusive64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess("MemoryWriteExclusive64", vaddr);
        }
        return result ==
            ExclusiveGuestWriteResult::Committed;
    }

    void InterpreterFallback(u32 pc, std::size_t num_instructions) override {
        cpu->HaltExecution();
        std::optional<std::uint32_t> code = MemoryReadCode(pc);
        SetPendingGuestCrashMessage(
            "Interpreter fallback at 0x%08x for %zu instruction(s)%s0x%08x",
            pc, num_instructions, code ? ", instruction=" : ", unreadable instruction ",
            code.value_or(0));
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
                SetPendingGuestCrashMessage(
                    "Guest breakpoint at 0x%08x", pc);
                DumpCrashReport(SIGTRAP, false);
            }
            return;
        }

        if ((code & 0xFFFF) == 0xDEFE) {
            SetPendingGuestCrashMessageIfEmpty(
                "Guest trap at pc=0x%08x, exception=%d, instruction=0x%08x",
                pc, static_cast<int>(exception), code);
            printf("ExceptionRaised[%s->%s:%d]: pc=0x%x, exception=%d, code=TRAP\n", __FILE__, __func__, __LINE__, pc, exception);
            DumpCrashReport(signal);
        } else {
            SetPendingGuestCrashMessageIfEmpty(
                "Guest exception at pc=0x%08x, exception=%d, instruction=0x%08x",
                pc, static_cast<int>(exception), code);
            printf("ExceptionRaised[%s->%s:%d]: pc=0x%x, exception=%d, code=0x%08X\n", __FILE__, __func__, __LINE__, pc, exception, code);
            DumpCrashReport(signal);
        }
    }

    void DumpCrashReport(int signal = SIGABRT, bool pendingSignal = true) {
        if (guestDebuggerEnabled.load(std::memory_order_acquire)) {
            pendingGuestAbortMetadata = {};
            pendingGuestCrashMessage.clear();
            StopForDebugger(signal, pendingSignal);
            return;
        }

        const GuestAbortMetadata &metadata =
            pendingGuestAbortMetadata;
        const char *fallbackError = !metadata.reason.empty()
            ? metadata.reason.c_str()
            : (!pendingGuestCrashMessage.empty()
                ? pendingGuestCrashMessage.c_str()
                : "(no guest error text)");
        const auto registers = cpu->Regs();
        char fallbackReason[LC32_OS_REASON_STRING_MAX + 1];
        snprintf(fallbackReason, sizeof(fallbackReason),
            "LiveExec32 guest %s (%d); crash report construction failed\n"
            "Error: %.*s\n"
            "Registers: r0=%08x r1=%08x r2=%08x r3=%08x "
            "r4=%08x r5=%08x r6=%08x r7=%08x "
            "r8=%08x r9=%08x r10=%08x r11=%08x r12=%08x "
            "sp=%08x lr=%08x pc=%08x cpsr=%08x",
            GuestSignalName(signal), signal,
            static_cast<int>(LC32_GUEST_ERROR_IN_COMPACT_REASON_MAX),
            fallbackError,
            registers[0], registers[1], registers[2], registers[3],
            registers[4], registers[5], registers[6], registers[7],
            registers[8], registers[9], registers[10], registers[11],
            registers[12], registers[13], registers[14], registers[15],
            cpu->Cpsr());
        const uint32_t fallbackNamespace =
            GuestAbortReasonNamespace(metadata);
        const uint64_t fallbackCode =
            GuestAbortReasonCode(metadata);

        try {
            DumpBacktrace(true, signal, pendingSignal);
        } catch (const std::exception &exception) {
            dumpingBacktrace = false;
            HaltAllGuestJits(LC32HaltReasonTrap);
            fprintf(stderr,
                "LiveExec32 failed to construct guest crash report: %s\n%s\n",
                exception.what(), fallbackReason);
            fflush(stderr);
            abort_with_reason(fallbackNamespace, fallbackCode,
                fallbackReason, 0);
        } catch (...) {
            dumpingBacktrace = false;
            HaltAllGuestJits(LC32HaltReasonTrap);
            fprintf(stderr,
                "LiveExec32 failed to construct guest crash report\n%s\n",
                fallbackReason);
            fflush(stderr);
            abort_with_reason(fallbackNamespace, fallbackCode,
                fallbackReason, 0);
        }
    }
    
    void DumpBacktrace(bool crash,
                       int signal = SIGABRT,
                       bool pendingSignal = true) {
        if (dumpingBacktrace) {
            fprintf(stderr, "Caught error while dumping call stack\n");
            if (crash) {
                HaltAllGuestJits(LC32HaltReasonTrap);
            }
            return;
        }
        if (crash) {
            CommitGuestStopSignal(signal, pendingSignal);
            HaltAllGuestJits(LC32HaltReasonTrap);
            if (guestCrashTerminationStarted.exchange(
                    true, std::memory_order_acq_rel)) {
                return;
            }
        }
        dumpingBacktrace = true;

        GuestAbortMetadata abortMetadata;
        std::string crashMessage;
        if (crash) {
            abortMetadata = std::move(pendingGuestAbortMetadata);
            pendingGuestAbortMetadata = {};
            crashMessage = std::move(pendingGuestCrashMessage);
            pendingGuestCrashMessage.clear();
        }

        const auto registers = cpu->Regs();
        const u32 cpsrValue = cpu->Cpsr();
        const std::vector<GuestImageSnapshot> images =
            SnapshotGuestImages();
        const std::vector<GuestCrashAnnotation> annotations =
            CollectGuestCrashAnnotations(images);

        std::array<symbolicated_call, 0x100> callStack{};
        int callStackLength = 0;
        const auto appendAddress = [&](u32 address) {
            if (address == 0 || callStackLength >=
                    static_cast<int>(callStack.size())) {
                return;
            }
            callStack[callStackLength++].address = address & ~1u;
        };
        const auto appendReturnAddress = [&](u32 returnAddress) {
            if (returnAddress == 0) {
                return;
            }
            const u32 instructionSize =
                (returnAddress & 1u) != 0 ? 2u : 4u;
            const u32 normalizedAddress = returnAddress & ~1u;
            appendAddress(normalizedAddress >= instructionSize
                ? normalizedAddress - instructionSize
                : normalizedAddress);
        };
        // The register dump should agree with frame zero: PC is the current
        // architectural location, while LR and frame-chain entries are
        // return addresses and need to be moved back to their ARM/Thumb call.
        appendAddress(registers[Reg::PC]);
        appendReturnAddress(registers[Reg::LR]);

        u32 framePointer = registers[7];
        std::unordered_set<u32> visitedFramePointers;
        std::string unwindMessage;
        while (framePointer != 0 &&
                callStackLength < static_cast<int>(callStack.size())) {
            if ((framePointer & 3) != 0 ||
                    framePointer > UINT32_MAX - 8) {
                AppendCrashReportFormat(unwindMessage,
                    "unwind stopped at invalid frame pointer 0x%08x",
                    framePointer);
                break;
            }
            if (!visitedFramePointers.insert(framePointer).second) {
                AppendCrashReportFormat(unwindMessage,
                    "unwind stopped at cyclic frame pointer 0x%08x",
                    framePointer);
                break;
            }
            u32 nextFramePointer = 0;
            u32 returnAddress = 0;
            if (!read_guest_memory_with_permissions(
                    framePointer, &nextFramePointer,
                    sizeof(nextFramePointer), PROT_READ) ||
                    !read_guest_memory_with_permissions(
                    framePointer + 4, &returnAddress,
                    sizeof(returnAddress), PROT_READ)) {
                AppendCrashReportFormat(unwindMessage,
                    "unwind stopped at unreadable frame pointer 0x%08x",
                    framePointer);
                break;
            }
            appendReturnAddress(returnAddress);
            framePointer = nextFramePointer;
        }
        if (framePointer != 0 &&
                callStackLength == static_cast<int>(callStack.size()) &&
                unwindMessage.empty()) {
            unwindMessage = "unwind stopped at the 256-frame limit";
        }
        symbolicate_call_stack(
            callStack.data(), callStackLength, images);

        std::string report;
        AppendCrashReportFormat(report,
            "LiveExec32 guest %s report\n"
            "Signal: %s (%d)\n",
            crash ? "crash" : "branch",
            GuestSignalName(signal), signal);
        if (abortMetadata.valid) {
            AppendCrashReportFormat(report,
                "Guest abort: namespace=%u, code=0x%llx, "
                "payload_size=0x%x, flags=0x%llx\n",
                abortMetadata.reasonNamespace,
                static_cast<unsigned long long>(
                    abortMetadata.reasonCode),
                abortMetadata.payloadSize,
                static_cast<unsigned long long>(
                    abortMetadata.reasonFlags));
            if (!abortMetadata.reason.empty()) {
                AppendCrashReportFormat(report,
                    "Guest error: %s\n",
                    abortMetadata.reason.c_str());
            }
        }
        if (!crashMessage.empty()) {
            AppendCrashReportFormat(report,
                "Emulator error: %s\n", crashMessage.c_str());
        }
        for (const GuestCrashAnnotation &annotation : annotations) {
            if (annotation.message == abortMetadata.reason) {
                continue;
            }
            AppendCrashReportFormat(report,
                "Crash message from %s: %s (cause: 0x%llx)\n",
                annotation.imageName.c_str(),
                annotation.message.c_str(),
                static_cast<unsigned long long>(annotation.abortCause));
        }

        AppendCrashReportFormat(report,
            "Registers:\n"
            " r0 0x%08x  r1 0x%08x  r2 0x%08x  r3 0x%08x\n"
            " r4 0x%08x  r5 0x%08x  r6 0x%08x  r7 0x%08x\n"
            " r8 0x%08x  r9 0x%08x r10 0x%08x r11 0x%08x\n"
            "r12 0x%08x  sp 0x%08x  lr 0x%08x  pc 0x%08x\n"
            "CPSR: 0x%08x thumb(%d) N(%d) Z(%d) C(%d) V(%d)\n",
            registers[0], registers[1], registers[2], registers[3],
            registers[4], registers[5], registers[6], registers[7],
            registers[8], registers[9], registers[10], registers[11],
            registers[12], registers[13], registers[14], registers[15],
            cpsrValue, threadHandle.cpsr->isThumb(),
            threadHandle.cpsr->isNegative(), threadHandle.cpsr->isZero(),
            threadHandle.cpsr->hasCarry(), threadHandle.cpsr->isOverflow());

        AppendCrashReportText(report, "Call stack:\n");
        for (int index = 0; index < callStackLength; ++index) {
            const symbolicated_call &call = callStack[index];
            AppendCrashReportFormat(report,
                "%3d: 0x%08x", index, call.address);
            if (!call.imageName.empty()) {
                const char *symbolName = call.symbolName.c_str();
                if (symbolName[0] == '_') {
                    ++symbolName;
                }
                AppendCrashReportFormat(report,
                    " %s`%s + 0x%x",
                    call.imageName.c_str(),
                    call.symbolName.empty()
                        ? "(unknown symbol)"
                        : symbolName,
                    call.symbolOffset);
            }
            AppendCrashReportText(report, "\n");
        }
        if (!unwindMessage.empty()) {
            AppendCrashReportFormat(report,
                "  [%s]\n", unwindMessage.c_str());
        }

        AppendCrashReportText(report, "Binary images:\n");
        for (size_t index = 0; index < images.size(); ++index) {
            AppendCrashReportFormat(report,
                "%3zu: 0x%08x-0x%08x %s\n",
                index, images[index].start, images[index].end,
                images[index].name.c_str());
        }

        if (!crash) {
            fwrite(report.data(), 1, report.size(), stderr);
            fflush(stderr);
            dumpingBacktrace = false;
            return;
        }

        std::string compactError;
        if (!abortMetadata.reason.empty()) {
            compactError = abortMetadata.reason;
        } else if (!annotations.empty()) {
            compactError = annotations.front().message;
            if (!crashMessage.empty() &&
                    crashMessage != compactError) {
                compactError += " | Emulator: ";
                compactError += crashMessage;
            }
        } else if (!crashMessage.empty()) {
            compactError = crashMessage;
        }

        std::string compactReason;
        AppendCrashReportFormat(compactReason,
            "LiveExec32 guest %s (%d)",
            GuestSignalName(signal), signal);
        if (abortMetadata.valid) {
            AppendCrashReportFormat(compactReason,
                "; abort ns=%u code=0x%llx",
                abortMetadata.reasonNamespace,
                static_cast<unsigned long long>(
                    abortMetadata.reasonCode));
        }
        compactReason += '\n';
        if (!compactError.empty()) {
            compactReason += "Error: ";
            compactReason += SanitizeCompactCrashText(
                compactError,
                LC32_GUEST_ERROR_IN_COMPACT_REASON_MAX);
            compactReason += '\n';
        }
        AppendCrashReportFormat(compactReason,
            "Registers: r0=%08x r1=%08x r2=%08x r3=%08x "
            "r4=%08x r5=%08x r6=%08x r7=%08x\n"
            "r8=%08x r9=%08x r10=%08x r11=%08x r12=%08x "
            "sp=%08x lr=%08x pc=%08x cpsr=%08x\n",
            registers[0], registers[1], registers[2], registers[3],
            registers[4], registers[5], registers[6], registers[7],
            registers[8], registers[9], registers[10], registers[11],
            registers[12], registers[13], registers[14], registers[15],
            cpsrValue);

        std::string compactFrames = "Call stack:";
        for (int index = 0; index < callStackLength; ++index) {
            std::string entry;
            AppendCrashReportFormat(entry, " %d=%08x", index,
                callStack[index].address);
            if (!callStack[index].imageName.empty()) {
                entry += '@';
                entry += SanitizeCompactCrashText(
                    GuestImageBasename(callStack[index].imageName), 40);
            }
            if (compactFrames.size() + entry.size() > 180) {
                compactFrames += " ...";
                break;
            }
            compactFrames += entry;
        }
        compactReason += compactFrames;
        compactReason += '\n';

        std::string compactImages = "Binary images:";
        std::unordered_set<std::string> emittedImageNames;
        const auto appendCompactImage = [&](
                const GuestImageSnapshot &image) {
            if (emittedImageNames.count(image.name) != 0) {
                return true;
            }
            std::string entry;
            const std::string imageName = SanitizeCompactCrashText(
                GuestImageBasename(image.name), 48);
            AppendCrashReportFormat(entry,
                " %08x-%08x=%s", image.start, image.end,
                imageName.c_str());
            if (compactImages.size() + entry.size() > 130) {
                return false;
            }
            emittedImageNames.insert(image.name);
            compactImages += entry;
            return true;
        };
        bool imageSpaceAvailable = true;
        if (!images.empty()) {
            imageSpaceAvailable = appendCompactImage(images.front());
        }
        for (int frameIndex = 0;
                frameIndex < callStackLength && imageSpaceAvailable;
                ++frameIndex) {
            const u32 address = callStack[frameIndex].address;
            for (const GuestImageSnapshot &image : images) {
                if (address >= image.start && address < image.end) {
                    imageSpaceAvailable = appendCompactImage(image);
                    break;
                }
            }
        }
        if (!imageSpaceAvailable) {
            compactImages += " ...";
        }
        compactReason += compactImages;

        dumpingBacktrace = false;
        AbortHostWithGuestCrashReport(
            abortMetadata, report, std::move(compactReason));
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
            SetPendingGuestCrashMessage(
                "Unhandled post-callback SVC number %d", number);
            DumpCrashReport();
            return;
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
            SetPendingGuestCrashMessage(
                "Unhandled pre-callback SVC number %d", number);
            DumpCrashReport();
            return;
        }
        if (swi != DARWIN_SWI_SYSCALL) {
            if (swi == (cpsr->isThumb() ? 0xff : 0xffffff)) {
                printf("LC32: throw: PopContextException\n");
                SetPendingGuestCrashMessage(
                    "Unhandled PopContextException SVC 0x%x", swi);
                DumpCrashReport();
                return;
            }
            if (swi == (cpsr->isThumb() ? 0xff : 0xffffff) - 1) {
                printf("LC32: throw: ThreadContextSwitchException\n");
                SetPendingGuestCrashMessage(
                    "Unhandled ThreadContextSwitchException SVC 0x%x", swi);
                DumpCrashReport();
                return;
            }
            printf("Unhandled svc number: %d\n", swi);
            SetPendingGuestCrashMessage(
                "Unhandled non-Darwin SVC number %u (syscall r12=%d)",
                swi, NR);
            DumpCrashReport();
            return;
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
            case 333: // __pthread_canceled
                /*
                 * Guest pthread cancellation requests are not modeled yet.
                 * XNU accepts actions 1 and 2 (enable/disable) unconditionally;
                 * action 0 reports EINVAL when there is no pending enabled
                 * cancellation. Handle this at the guest ABI instead of
                 * mutating cancellation state on the emulator's host thread.
                 */
                if (cpu->Regs()[0] == 1 || cpu->Regs()[0] == 2) {
                    cpu->Regs()[0] =
                        return_with_carry_direct(0, false);
                } else {
                    cpu->Regs()[0] =
                        return_with_carry_direct(EINVAL, true);
                }
                break;
            case 334: // semwait_signal
            case 423: // semwait_signal_nocancel
                if (cpu->Regs()[1] == 0 && cpu->Regs()[2] == 0 &&
                        GuestThreadYieldBeforeBlocking()) {
                    /*
                     * pthread_join uses an untimed wait without a paired
                     * signal semaphore. Do not block the sole cooperative
                     * JIT; libpthread retries after EINTR, by which time the
                     * terminating guest thread can signal the host semaphore.
                     */
                    cpu->Regs()[0] =
                        return_with_carry_direct(EINTR, true);
                } else {
                    cpu->Regs()[0] = debugger_aware_host_wait(
                        [&] {
                            return syscallRetCarry(
                                NR, cpu->Regs()[0], cpu->Regs()[1],
                                cpu->Regs()[2], cpu->Regs()[3],
                                cpu->Regs()[4] |
                                    (static_cast<u64>(
                                        cpu->Regs()[5]) << 32),
                                cpu->Regs()[6]);
                        },
                        return_with_carry_direct(EINTR, true));
                }
                break;
            case SYS_fsync: // 95
                cpu->Regs()[0] = debugger_aware_host_wait(
                    [&] {
                        return syscallRetCarry(
                            NR, cpu->Regs()[0],
                            0, 0, 0, 0, 0, 0);
                    },
                    return_with_carry_direct(EINTR, true));
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
                if (GuestThreadCanYieldBeforeBlocking()) {
                    const kern_return_t probe =
                        semaphore_timedwait_trap(
                            cpu->Regs()[0], 0, 0);
                    if (probe == KERN_OPERATION_TIMED_OUT &&
                            GuestThreadYieldBeforeBlocking()) {
                        cpu->Regs()[0] = KERN_ABORTED;
                    } else {
                        cpu->Regs()[0] = probe;
                    }
                } else {
                    cpu->Regs()[0] = debugger_aware_host_wait(
                        [&] {
                            return semaphore_wait_trap(
                                cpu->Regs()[0]);
                        },
                        static_cast<kern_return_t>(KERN_ABORTED));
                }
                break;
            case -38:
                if (GuestThreadCanYieldBeforeBlocking()) {
                    const kern_return_t probe =
                        semaphore_timedwait_trap(
                            cpu->Regs()[0], 0, 0);
                    if (probe == KERN_OPERATION_TIMED_OUT &&
                            (cpu->Regs()[1] != 0 || cpu->Regs()[2] != 0) &&
                            GuestThreadYieldBeforeBlocking()) {
                        cpu->Regs()[0] = KERN_ABORTED;
                    } else {
                        cpu->Regs()[0] = probe;
                    }
                } else {
                    cpu->Regs()[0] = debugger_aware_host_wait(
                        [&] {
                            return semaphore_timedwait_trap(
                                cpu->Regs()[0], cpu->Regs()[1],
                                cpu->Regs()[2]);
                        },
                        static_cast<kern_return_t>(KERN_ABORTED));
                }
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
                guestProcessExitCode.store(
                    static_cast<int>(
                        cpu->Regs()[0] & 0xff),
                    std::memory_order_release);
                guestProcessExitRequested.store(
                    true, std::memory_order_release);
                HaltAllGuestJits(LC32HaltReasonExit);
                InterruptDebuggerMachCalls();
                NotifyNativeDebuggerWaiters();
                NotifyNativeDebuggerCoordinator();
                break;
            case SYS_fork: // 2
                printf("fork() not supported\n");
                cpu->Regs()[0] = ENOSYS;
                break;
            case SYS_read: // 3
            case SYS_read_nocancel: // 396
                /*
                 * Native guest pthreads need an interruptible host call so
                 * debugger all-stop and process teardown can abort a blocked
                 * read. Cooperative mode retains the historical nocancel
                 * behavior.
                 */
                cpu->Regs()[0] = guest_read(
                    NativeGuestThreadsEnabled()
                        ? SYS_read
                        : SYS_read_nocancel,
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2]);
                break;
            case SYS_write: // 4
            case SYS_write_nocancel:
                cpu->Regs()[0] = guest_write(
                    NativeGuestThreadsEnabled()
                        ? SYS_write
                        : NR,
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2]);
                break;
            case SYS_open: // 5
            case SYS_open_nocancel:
                cpu->Regs()[0] = guest_open(
                    NativeGuestThreadsEnabled()
                        ? SYS_open
                        : SYS_open_nocancel,
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2]);
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
            case SYS_recvfrom: // 29
            case SYS_recvfrom_nocancel: // 403
                /*
                 * Match guest_read: native pthreads use the cancellable
                 * syscall so debugger all-stop can abort a blocked receive;
                 * cooperative mode retains the nocancel entry point.
                 */
                cpu->Regs()[0] = static_cast<u32>(guest_recvfrom(
                    NativeGuestThreadsEnabled()
                        ? SYS_recvfrom
                        : SYS_recvfrom_nocancel,
                    static_cast<int>(cpu->Regs()[0]),
                    cpu->Regs()[1], cpu->Regs()[2],
                    static_cast<int>(cpu->Regs()[3]),
                    cpu->Regs()[4], cpu->Regs()[5]));
                break;
            case SYS_getsockname: // 32
                cpu->Regs()[0] = guest_getsockname(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
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
            case SYS_bind: // 104
                cpu->Regs()[0] = guest_bind(
                    cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_setsockopt: // 105
                /*
                 * The armv7 libsystem_kernel wrapper moves the fifth
                 * stack argument (optlen) into r4 before entering XNU.
                 */
                cpu->Regs()[0] = guest_setsockopt(
                    static_cast<int>(cpu->Regs()[0]),
                    static_cast<int>(cpu->Regs()[1]),
                    static_cast<int>(cpu->Regs()[2]),
                    cpu->Regs()[3], cpu->Regs()[4]);
                break;
            case SYS_getsockopt: // 118
                /*
                 * The fifth argument is a guest socklen_t pointer which the
                 * armv7 wrapper has moved from its caller's stack into r4.
                 */
                cpu->Regs()[0] = guest_getsockopt(
                    static_cast<int>(cpu->Regs()[0]),
                    static_cast<int>(cpu->Regs()[1]),
                    static_cast<int>(cpu->Regs()[2]),
                    cpu->Regs()[3], cpu->Regs()[4]);
                break;
            case 116:
                cpu->Regs()[0] = guest_gettimeofday(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 121:
            case SYS_writev_nocancel:
                cpu->Regs()[0] = guest_writev(
                    NativeGuestThreadsEnabled()
                        ? SYS_writev
                        : NR,
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2]);
                break;
            case 128:
                cpu->Regs()[0] = guest_rename(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 133:
                cpu->Regs()[0] = guest_sendto(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case SYS_mkdir: // 136
                cpu->Regs()[0] = guest_mkdir(
                    cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 153:
            case SYS_pread_nocancel:
                cpu->Regs()[0] = guest_pread(
                    NativeGuestThreadsEnabled()
                        ? SYS_pread
                        : NR,
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2],
                    cpu->Regs()[3] |
                        (static_cast<u64>(
                            cpu->Regs()[4]) << 32));
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
            case SYS_lseek: { // 199
                /*
                 * Darwin's armv7 syscall ABI packs off_t into r1:r2 without
                 * an AAPCS alignment hole.  Use the typed host API so the
                 * combined value is passed as one arm64 off_t argument.
                 */
                const u64 offsetBits =
                    static_cast<u64>(cpu->Regs()[1]) |
                    (static_cast<u64>(cpu->Regs()[2]) << 32);
                const off_t result = ::lseek(
                    static_cast<int>(cpu->Regs()[0]),
                    static_cast<off_t>(offsetBits),
                    static_cast<int>(cpu->Regs()[3]));
                if (result == static_cast<off_t>(-1)) {
                    const int error = errno;
                    cpu->Regs()[0] =
                        return_with_carry_direct(error, true);
                    cpu->Regs()[1] = 0;
                } else {
                    const u64 resultBits = static_cast<u64>(result);
                    cpu->Regs()[0] = static_cast<u32>(resultBits);
                    cpu->Regs()[1] = static_cast<u32>(resultBits >> 32);
                    cpsr->setCarry(false);
                }
                break;
            }
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
                    SetPendingGuestCrashMessage(
                        "Guest pthread_kill requested signal %u",
                        cpu->Regs()[1]);
                    DumpCrashReport(static_cast<int>(cpu->Regs()[1]));
                    return;
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
                return;
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
            case 1010: { // LC32InvokeHostNSStringFormat
                if(cpu->IsExecuting()) {
                    // Formatting %@ may call a guest object's description, so
                    // leave the callback before entering the host runtime.
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                u64 host_self = (u64)cpu->Regs()[0] |
                    ((u64)cpu->Regs()[1] << 32);
                u64 host_selector = (u64)cpu->Regs()[2] |
                    ((u64)cpu->Regs()[3] << 32);
                u32 stack = cpu->Regs()[Reg::SP];
                u64 host_format =
                    Dynarmic_current_user_callbacks()->MemoryRead64(stack);
                u64 host_locale =
                    Dynarmic_current_user_callbacks()->MemoryRead64(stack + 8);
                u32 guest_arguments =
                    Dynarmic_current_user_callbacks()->MemoryRead32(stack + 16);
                u32 options =
                    Dynarmic_current_user_callbacks()->MemoryRead32(stack + 20);
                u64 result = LC32InvokeHostNSStringFormat(
                    host_self, host_selector, host_format, host_locale,
                    guest_arguments, options);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1011: { // LC32CopyHostStringUTF8
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u64 host_object = (u64)cpu->Regs()[0] |
                    ((u64)cpu->Regs()[1] << 32);
                cpu->Regs()[0] = LC32CopyHostStringUTF8(
                    host_object, cpu->Regs()[2], cpu->Regs()[3]);
                break;
            }
            case 1012: { // LC32CopyHostDataBytes
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u64 host_object = (u64)cpu->Regs()[0] |
                    ((u64)cpu->Regs()[1] << 32);
                const u32 offset =
                    Dynarmic_current_user_callbacks()->MemoryRead32(
                        cpu->Regs()[Reg::SP]);
                cpu->Regs()[0] = LC32CopyHostDataBytes(
                    host_object, cpu->Regs()[2], cpu->Regs()[3], offset);
                break;
            }
            default:
                printf("Unhandled svc number: %d\n", NR);
                SetPendingGuestCrashMessage(
                    "Unhandled Darwin syscall number %d", NR);
                DumpCrashReport(SIGSYS);
                return;
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
    GuestVmEpochParticipant vmEpochParticipant;
    gdb_thread_id_t debuggerId = 0;
    size_t processorId = 0;
    pthread_t hostThread = {};
    mach_port_t hostMachThread = MACH_PORT_NULL;
    std::mutex startMutex;
    std::condition_variable startCondition;
    bool startAllowed = false;
    bool debuggerExecuting = false;
    bool debuggerHostWaitPaused = false;
    bool hostThreadCreated = false;
    bool exited = false;
    mach_port_t joinSemaphore = MACH_PORT_NULL;
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
thread_local NativeGuestJit *nativeGuestRuntime;
thread_local bool nativeDebuggerHostWaitStep;
thread_local uint64_t nativeDebuggerHostWaitStepGeneration;
thread_local gdb_thread_id_t
    cooperativeDebuggerResumeThread =
        GDB_THREAD_ID_ALL;

std::mutex nativeGuestJitMutex;
std::condition_variable nativeGuestJitCondition;
std::vector<NativeGuestJit *> nativeGuestJits;

enum class NativeDebuggerRunState : uint8_t {
    Disabled,
    Stopped,
    Running,
    Stopping,
    ShuttingDown,
};

enum class NativeDebuggerResumeMode : uint8_t {
    ContinueAll,
    ContinueOne,
    StepOne,
    StepOneContinueOthers,
};

struct NativeDebuggerCoordinator {
    std::mutex mutex;
    std::condition_variable condition;
    NativeDebuggerRunState state =
        NativeDebuggerRunState::Disabled;
    NativeDebuggerResumeMode resumeMode =
        NativeDebuggerResumeMode::ContinueAll;
    gdb_thread_id_t stopOwner = 1;
    gdb_thread_id_t stepThread = 1;
    Dynarmic::HaltReason stopReason =
        LC32HaltReasonTrap;
    int stopSignal = SIGTRAP;
    uint64_t generation = 0;
    size_t executingWorkers = 0;
    bool mainExecuting = false;
    /*
     * The socket reader can receive ^C after async I/O is enabled but before
     * the target thread has changed Stopped to Running. Preserve that request
     * across the resume handoff instead of clearing it as stale state.
     */
    bool resumeStarting = false;
    bool pendingInterrupt = false;
};

NativeDebuggerCoordinator nativeDebugger;

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

static bool NativeDebuggerActive() {
    return NativeGuestThreadsEnabled() &&
        guestDebuggerEnabled.load(std::memory_order_acquire);
}

static void NativeDebuggerSetWorkerExecutingLocked(
        NativeGuestJit *runtime, bool executing) {
    if (runtime == nullptr ||
            runtime->debuggerExecuting == executing) {
        return;
    }
    runtime->debuggerExecuting = executing;
    if (executing) {
        ++nativeDebugger.executingWorkers;
    } else {
        assert(nativeDebugger.executingWorkers != 0);
        --nativeDebugger.executingWorkers;
    }
}

static bool NativeDebuggerRunsThreadLocked(
        gdb_thread_id_t threadId) {
    switch (nativeDebugger.resumeMode) {
    case NativeDebuggerResumeMode::ContinueAll:
    case NativeDebuggerResumeMode::StepOneContinueOthers:
        return true;
    case NativeDebuggerResumeMode::ContinueOne:
    case NativeDebuggerResumeMode::StepOne:
        return nativeDebugger.stepThread ==
            threadId;
    }
}

static bool NativeDebuggerStepsThreadLocked(
        gdb_thread_id_t threadId) {
    return (nativeDebugger.resumeMode ==
                NativeDebuggerResumeMode::StepOne ||
            nativeDebugger.resumeMode ==
                NativeDebuggerResumeMode::StepOneContinueOthers) &&
        nativeDebugger.stepThread == threadId;
}

/*
 * A native pthread may be inside a host wait when another guest thread stops.
 * Such a worker acknowledges the all-stop epoch here and remains inside the
 * emulated syscall until ContinueAll opens the next epoch. The main emulator
 * thread cannot park here because it is also the gdbstub target thread; it
 * instead unwinds the host wait and returns to Dynarmic so the target callback
 * can report the stop.
 */
bool NativeDebuggerPauseHostWaitIfNeeded() {
    if (nativeShutdownRequested.load(std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        return true;
    }
    if (!NativeDebuggerActive() ||
            !debuggerAllStopRequested.load(std::memory_order_acquire)) {
        return false;
    }
    if (nativeGuestRuntime == nullptr ||
            nativeGuestThreadId <= 1) {
        return true;
    }

    std::unique_lock<std::mutex> lock(nativeDebugger.mutex);
    if (nativeDebugger.state == NativeDebuggerRunState::Running) {
        return false;
    }
    nativeGuestRuntime->debuggerHostWaitPaused = true;
    NativeDebuggerSetWorkerExecutingLocked(
        nativeGuestRuntime, false);
    nativeDebugger.condition.notify_all();
    nativeDebugger.condition.wait(lock, [] {
        return !NativeDebuggerActive() ||
            nativeGuestThreadRetiring ||
            nativeDebugger.state ==
                NativeDebuggerRunState::ShuttingDown ||
            (nativeDebugger.state ==
                NativeDebuggerRunState::Running &&
             NativeDebuggerRunsThreadLocked(
                 nativeGuestRuntime->debuggerId));
    });
    if (!NativeDebuggerActive() ||
            nativeGuestThreadRetiring ||
            nativeDebugger.state ==
                NativeDebuggerRunState::ShuttingDown) {
        nativeGuestRuntime->debuggerHostWaitPaused = false;
        nativeDebuggerHostWaitStep = false;
        nativeDebuggerHostWaitStepGeneration = 0;
        return true;
    }
    nativeDebuggerHostWaitStep =
        NativeDebuggerStepsThreadLocked(
            nativeGuestRuntime->debuggerId);
    nativeDebuggerHostWaitStepGeneration =
        nativeDebuggerHostWaitStep
        ? nativeDebugger.generation
        : 0;
    if (nativeDebuggerHostWaitStep &&
            nativeGuestRuntime->jit != nullptr) {
        /*
         * The host wait lives inside an existing Jit::Run callback. Re-arm the
         * internal pause so that old Run unwinds after syscall copyout; the
         * worker loop can then issue a real Jit::Step for the selected thread.
         */
        nativeGuestRuntime->jit->HaltExecution(
            LC32HaltReasonDebuggerPause);
    } else {
        nativeGuestRuntime->debuggerHostWaitPaused = false;
    }
    NativeDebuggerSetWorkerExecutingLocked(
        nativeGuestRuntime, true);
    return true;
}

static bool ConsumeNativeDebuggerHostWaitStep(
        uint64_t commandGeneration) {
    const bool step =
        nativeDebuggerHostWaitStep &&
        nativeDebuggerHostWaitStepGeneration ==
            commandGeneration;
    nativeDebuggerHostWaitStep = false;
    nativeDebuggerHostWaitStepGeneration = 0;
    return step;
}

void NotifyNativeDebuggerWaiters() {
    std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
    for (const auto &waiter : nativeGuestWaiters) {
        waiter->condition.notify_all();
    }
}

void NotifyNativeDebuggerCoordinator() {
    nativeDebugger.condition.notify_all();
}

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

static gdb_thread_id_t ActiveMainDebuggerThread() {
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    return guestWorkqueueUpcallActive &&
        guestWorkqueueWaitingContextValid
        ? 2
        : 1;
}

static bool NativeDebuggerMainContextMayRun() {
    if (nativeGuestRuntime != nullptr) {
        return true;
    }
    if (!NativeDebuggerActive()) {
        if (!guestDebuggerEnabled.load(
                std::memory_order_acquire)) {
            return true;
        }
        /*
         * Cooperative pthreads and the workqueue pseudo-thread all overlay
         * the one JIT. Stop at a context-switch boundary if an exact-thread
         * resume selected a different logical context.
         */
        const gdb_thread_id_t activeThread =
            Dynarmic_debugger_current_thread();
        return cooperativeDebuggerResumeThread ==
                GDB_THREAD_ID_ANY ||
            cooperativeDebuggerResumeThread ==
                GDB_THREAD_ID_ALL ||
            cooperativeDebuggerResumeThread ==
                activeThread;
    }
    /*
     * Snapshot the overlay without holding guestWorkqueueMutex while taking
     * the coordinator. Register access takes those locks in the opposite
     * order while stopped.
     */
    const gdb_thread_id_t activeThread =
        ActiveMainDebuggerThread();
    std::lock_guard<std::mutex> lock(
        nativeDebugger.mutex);
    return nativeDebugger.state ==
            NativeDebuggerRunState::Running &&
        NativeDebuggerRunsThreadLocked(activeThread);
}

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
            "LC32: native guest pthread experiment enabled\n");
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

static void ScheduleMainGuestWorkqueueTransition() {
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? sharedHandle.cb->cpu
        : nullptr;
    if (mainJit != nullptr) {
        mainJit->HaltExecution(LC32HaltReasonWorkqueue);
    }
    InterruptDebuggerMachCalls();
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

static void ClearAllGuestJitHalts(
        Dynarmic::HaltReason reason) {
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? sharedHandle.cb->cpu
        : nullptr;
    if (mainJit != nullptr) {
        mainJit->ClearHalt(reason);
    }
    std::lock_guard<std::mutex> lock(
        nativeGuestJitMutex);
    for (NativeGuestJit *runtime : nativeGuestJits) {
        if (runtime != nullptr &&
                runtime->jit != nullptr &&
                runtime->jit != mainJit) {
            runtime->jit->ClearHalt(reason);
        }
    }
}

static Dynarmic::HaltReason NativeDebuggerVisibleReason(
        Dynarmic::HaltReason reason) {
    return reason & ~LC32HaltReasonDebuggerPause;
}

static bool NativeDebuggerStopOwnerAlive(
        gdb_thread_id_t owner) {
    if (owner == 1) {
        return sharedHandle.cb != nullptr &&
            sharedHandle.cb->cpu != nullptr;
    }
    if (owner == 2) {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        return guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    for (const GuestThreadContext &thread :
            guestThreads) {
        if (thread.debuggerId == owner) {
            return thread.alive;
        }
    }
    return false;
}

/*
 * Called with nativeDebugger.mutex held. The registry locks are acquired in
 * the same coordinator-first order used by stopped register access. A thread
 * A context transition or retiring thread transfers an already committed
 * owner only after dropping its registry lock, closing both sides of the
 * validation/commit race.
 */
static gdb_thread_id_t NativeDebuggerNormalizeStopOwnerLocked(
        gdb_thread_id_t owner) {
    /*
     * Thread 2 owns the main JIT while the workqueue overlay is active.
     * Thread 1 remains alive only as a saved register context and must not be
     * exposed as the owner of a stop taken by that JIT.
     */
    if (owner == 1 &&
            NativeDebuggerStopOwnerAlive(2)) {
        return 2;
    }
    if (NativeDebuggerStopOwnerAlive(owner)) {
        return owner;
    }
    if (NativeDebuggerStopOwnerAlive(2)) {
        return 2;
    }
    return 1;
}

static void NativeDebuggerTransferStopOwner(
        gdb_thread_id_t previousOwner,
        gdb_thread_id_t replacementOwner) {
    if (!NativeDebuggerActive()) {
        return;
    }
    std::lock_guard<std::mutex> lock(
        nativeDebugger.mutex);
    if ((nativeDebugger.state ==
                NativeDebuggerRunState::Stopping ||
            nativeDebugger.state ==
                NativeDebuggerRunState::Stopped) &&
            nativeDebugger.stopOwner ==
                previousOwner) {
        nativeDebugger.stopOwner =
            NativeDebuggerNormalizeStopOwnerLocked(
                replacementOwner);
    }
}

static bool NativeDebuggerRequestStop(
        gdb_thread_id_t owner,
        Dynarmic::HaltReason reason,
        int forcedSignal = 0,
        bool forcedPendingSignal = false,
        bool queueWhileStopped = false) {
    const Dynarmic::HaltReason visibleReason =
        NativeDebuggerVisibleReason(reason);
    GuestStopRequest request =
        CurrentGuestStopRequestForReason(
            visibleReason);
    if (forcedSignal > 0) {
        request.signal =
            NormalizeGuestStopSignal(forcedSignal);
        request.pending = forcedPendingSignal;
        request.valid = true;
    }
    bool firstStop = false;
    {
        std::lock_guard<std::mutex> lock(nativeDebugger.mutex);
        if (nativeDebugger.state ==
                NativeDebuggerRunState::Running) {
            nativeDebugger.state =
                NativeDebuggerRunState::Stopping;
            nativeDebugger.stopOwner =
                NativeDebuggerNormalizeStopOwnerLocked(
                    owner);
            nativeDebugger.stopReason = !!visibleReason
                ? visibleReason
                : LC32HaltReasonTrap;
            nativeDebugger.stopSignal =
                NormalizeGuestStopSignal(request.signal);
            CommitGuestStopSignal(
                nativeDebugger.stopSignal,
                request.pending);
            debuggerAllStopRequested.store(
                true, std::memory_order_release);
            firstStop = true;
        } else if (queueWhileStopped &&
                nativeDebugger.state ==
                    NativeDebuggerRunState::Stopped) {
            nativeDebugger.pendingInterrupt = true;
        }
    }
    if (!firstStop) {
        return false;
    }
    ClearCurrentGuestStopRequest();

    /*
     * Never hold the coordinator while touching the JIT registry or aborting
     * host waits. Workers acknowledge this stop after Run()/Step() returns.
     */
    HaltAllGuestJits(LC32HaltReasonDebuggerPause);
    InterruptDebuggerMachCalls();
    NotifyNativeDebuggerWaiters();
    nativeDebugger.condition.notify_all();
    return true;
}

/*
 * A thread can lose first-stop-wins after completing a fatal SVC while a peer
 * reports another stop. Unlike a synchronous instruction fault, that SVC will
 * not naturally replay. Preserve its TLS request and publish it as soon as
 * this logical thread is next resumed.
 */
static bool NativeDebuggerRepublishPendingStop(
        gdb_thread_id_t owner) {
    if (!currentGuestStopRequest.valid ||
            !currentGuestStopRequest.pending) {
        ClearCurrentGuestStopRequest();
        return false;
    }
    (void)NativeDebuggerRequestStop(
        owner, LC32HaltReasonTrap);
    return true;
}

static bool NativeDebuggerWaitForWorkerCommand(
        NativeGuestJit *runtime, bool &singleStep,
        uint64_t &commandGeneration) {
    commandGeneration = 0;
    if (runtime == nullptr) {
        return false;
    }
    if (nativeShutdownRequested.load(std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        return false;
    }
    if (!NativeDebuggerActive()) {
        singleStep = false;
        return true;
    }

    std::unique_lock<std::mutex> lock(nativeDebugger.mutex);
    nativeDebugger.condition.wait(lock, [runtime] {
        return nativeShutdownRequested.load(
                   std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                   std::memory_order_acquire) ||
            !NativeDebuggerActive() ||
            nativeGuestThreadRetiring ||
            nativeDebugger.state ==
                NativeDebuggerRunState::ShuttingDown ||
            (nativeDebugger.state ==
                NativeDebuggerRunState::Running &&
             NativeDebuggerRunsThreadLocked(
                 runtime->debuggerId));
    });
    if (nativeShutdownRequested.load(std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire) ||
            nativeGuestThreadRetiring ||
            nativeDebugger.state ==
                NativeDebuggerRunState::ShuttingDown) {
        return false;
    }
    if (!NativeDebuggerActive()) {
        singleStep = false;
        return true;
    }

    singleStep =
        NativeDebuggerStepsThreadLocked(
            runtime->debuggerId);
    commandGeneration = nativeDebugger.generation;
    NativeDebuggerSetWorkerExecutingLocked(runtime, true);
    return true;
}

static void NativeDebuggerWorkerStopped(
        NativeGuestJit *runtime,
        Dynarmic::HaltReason reason) {
    const Dynarmic::HaltReason visibleReason =
        NativeDebuggerVisibleReason(reason);
    if (!!visibleReason && !nativeGuestThreadRetiring) {
        (void)NativeDebuggerRequestStop(
            runtime->debuggerId, visibleReason);
    }
    {
        std::lock_guard<std::mutex> lock(nativeDebugger.mutex);
        NativeDebuggerSetWorkerExecutingLocked(
            runtime, false);
    }
    nativeDebugger.condition.notify_all();
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
    RegisterGuestVmEpochParticipant(
        &runtime->vmEpochParticipant);

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
    UnregisterGuestVmEpochParticipant(
        &runtime->vmEpochParticipant);
    delete runtime->cpsr;
    delete runtime->jit;
    runtime->callbacks->destroy();
    delete runtime;
}

static void JoinNativeGuestJit(
        NativeGuestJit *runtime) {
    if (runtime == nullptr ||
            !runtime->hostThreadCreated) {
        return;
    }
    const int result =
        pthread_join(runtime->hostThread, nullptr);
    if (result != 0) {
        /*
         * Continuing would free a JIT and callbacks that the host thread may
         * still own. Treat this as an internal lifecycle invariant failure
         * instead of turning a rare join error into a use-after-free.
         */
        fprintf(stderr,
            "LC32: pthread_join guest-thread=%llu "
            "failed: %d (%s)\n",
            runtime->debuggerId, result,
            strerror(result));
        abort();
    }
    runtime->hostThreadCreated = false;
}

static void ReapExitedNativeGuestJits() {
    std::vector<NativeGuestJit *> exited;
    {
        std::lock_guard<std::mutex> lock(
            nativeGuestJitMutex);
        for (auto iterator = nativeGuestJits.begin();
                iterator != nativeGuestJits.end();) {
            NativeGuestJit *runtime = *iterator;
            if (runtime != nullptr && runtime->exited) {
                exited.push_back(runtime);
                iterator = nativeGuestJits.erase(iterator);
            } else {
                ++iterator;
            }
        }
    }
    for (NativeGuestJit *runtime : exited) {
        JoinNativeGuestJit(runtime);
        DestroyNativeGuestJit(runtime);
    }
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
    nativeGuestRuntime = runtime;
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
        for (;;) {
            bool singleStep = false;
            uint64_t commandGeneration = 0;
            if (!NativeDebuggerWaitForWorkerCommand(
                    runtime, singleStep,
                    commandGeneration)) {
                break;
            }

            if (NativeDebuggerRepublishPendingStop(
                    runtime->debuggerId)) {
                (void)ConsumeNativeDebuggerHostWaitStep(
                    commandGeneration);
                NativeDebuggerWorkerStopped(
                    runtime,
                    LC32HaltReasonDebuggerPause);
                continue;
            }
            if (ConsumeNativeDebuggerHostWaitStep(
                    commandGeneration) &&
                    singleStep) {
                runtime->jit->ClearHalt(
                    LC32HaltReasonDebuggerPause);
            }
            const Dynarmic::HaltReason reason = singleStep
                ? Dynarmic_emu_1step()
                : Dynarmic_emu_1resume();
            if (nativeDebuggerHostWaitStep) {
                /*
                 * The interrupted callback has now copied out its result and
                 * the old Run() has unwound. Registers are stable even if a
                 * peer wins before this worker reaches its follow-up step.
                 */
                std::lock_guard<std::mutex> lock(
                    nativeDebugger.mutex);
                runtime->debuggerHostWaitPaused = false;
            }

            bool retiringSelectedThread = false;
            if (nativeGuestThreadRetiring &&
                    NativeDebuggerActive()) {
                std::lock_guard<std::mutex> lock(
                    nativeDebugger.mutex);
                retiringSelectedThread =
                    nativeDebugger.stepThread ==
                        runtime->debuggerId &&
                    (singleStep ||
                     nativeDebugger.resumeMode ==
                         NativeDebuggerResumeMode::ContinueOne);
            }
            if (retiringSelectedThread) {
                (void)NativeDebuggerRequestStop(
                    ActiveMainDebuggerThread(),
                    Dynarmic::HaltReason::Step,
                    SIGTRAP, false);
            }
            NativeDebuggerWorkerStopped(
                runtime, reason);

            if (nativeGuestThreadRetiring) {
                break;
            }
            if (NativeDebuggerActive()) {
                /*
                 * A debugger halt parks this host pthread with its JIT and
                 * register file intact. The next loop iteration waits for a
                 * ContinueAll or a step command selecting this guest thread.
                 */
                continue;
            }

            if (!nativeShutdownRequested.load(
                    std::memory_order_acquire) &&
                    !guestProcessExitRequested.load(
                        std::memory_order_acquire) &&
                    !!NativeDebuggerVisibleReason(
                        reason)) {
                fprintf(stderr,
                    "LC32: native guest-thread=%llu stopped "
                    "without bsdthread_terminate "
                    "(reason=0x%llx)\n",
                    start->debuggerId,
                    static_cast<unsigned long long>(
                        reason));
            }
            break;
        }

        mach_port_t leftoverPort = MACH_PORT_NULL;
        {
            std::lock_guard<std::recursive_mutex> lock(
                guestThreadMutex);
            if (GuestThreadContext *thread =
                    FindGuestThread(start->debuggerId, false)) {
                leftoverPort = thread->threadPort;
                thread->threadPort = MACH_PORT_NULL;
                thread->alive = false;
                thread->runnable = false;
                thread->savedValid = false;
                thread->nativeJit = nullptr;
            }
        }
        NativeDebuggerTransferStopOwner(
            start->debuggerId, 1);
        if (MACH_PORT_VALID(leftoverPort)) {
            (void)mach_port_destroy(
                mach_task_self(), leftoverPort);
        }
    }

    threadHandle = {};
    nativeGuestThreadId = 0;
    nativeGuestThreadRetiring = false;
    nativeGuestRuntime = nullptr;
    runtime->hostMachThread = MACH_PORT_NULL;
    {
        std::lock_guard<std::mutex> lock(
            nativeGuestJitMutex);
        runtime->exited = true;
    }
    nativeGuestJitCondition.notify_all();
    if (MACH_PORT_VALID(runtime->joinSemaphore)) {
        const kern_return_t result =
            semaphore_signal_trap(
                runtime->joinSemaphore);
        if (result != KERN_SUCCESS) {
            fprintf(stderr,
                "LC32: native guest-thread=%llu join "
                "semaphore 0x%x failed: 0x%x\n",
                runtime->debuggerId,
                runtime->joinSemaphore, result);
        }
        runtime->joinSemaphore = MACH_PORT_NULL;
    }
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

    std::unique_lock<std::mutex> nativeCreateLock;
    if (NativeGuestThreadsEnabled()) {
        nativeCreateLock =
            std::unique_lock<std::mutex>(
                nativeLifecycleMutex);
        if (nativeLifecycleState !=
                NativeLifecycleState::Running ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire)) {
            return return_with_carry_direct(
                EAGAIN, true);
        }
        ReapExitedNativeGuestJits();
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
        runtime->debuggerId = debuggerId;
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
        runtime->hostThreadCreated = true;
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

    const bool nativeThread =
        NativeGuestThreadIsCurrent();
    if (MACH_PORT_VALID(joinSemaphore) &&
            !nativeThread) {
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
    NativeDebuggerTransferStopOwner(
        debuggerId, 1);

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
    if (nativeThread) {
        if (nativeGuestRuntime != nullptr) {
            /*
             * pthread_join must not return while the host worker still owns
             * its JIT. Signal from RunNativeGuestThread after it has published
             * the exited state. The reaper keeps the processor slot reserved
             * until the host pthread is joined and its JIT is destroyed.
             */
            nativeGuestRuntime->joinSemaphore =
                joinSemaphore;
        }
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
    while (!waiter->signaled) {
        waiter->condition.wait(lock, [&] {
            return waiter->signaled ||
                debuggerAllStopRequested.load(
                    std::memory_order_acquire) ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire) ||
                guestProcessExitRequested.load(
                    std::memory_order_acquire);
        });
        if (waiter->signaled) {
            break;
        }
        lock.unlock();
        const bool paused =
            NativeDebuggerPauseHostWaitIfNeeded();
        lock.lock();
        if (paused &&
                (nativeGuestRuntime == nullptr ||
                 nativeDebuggerHostWaitStep ||
                 nativeShutdownRequested.load(
                     std::memory_order_acquire) ||
                 guestProcessExitRequested.load(
                     std::memory_order_acquire))) {
            nativeGuestWaiters.erase(std::remove(
                nativeGuestWaiters.begin(),
                nativeGuestWaiters.end(),
                waiter), nativeGuestWaiters.end());
            return return_with_carry_direct(EINTR, true);
        }
    }
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
        auto deadline = std::chrono::steady_clock::now() +
            std::chrono::microseconds(timeout);
        while (!waiter->signaled) {
            if (timeout == 0) {
                waiter->condition.wait(lock, [&] {
                    return waiter->signaled ||
                        debuggerAllStopRequested.load(
                            std::memory_order_acquire) ||
                        nativeShutdownRequested.load(
                            std::memory_order_acquire) ||
                        guestProcessExitRequested.load(
                            std::memory_order_acquire);
                });
            } else {
                woke = waiter->condition.wait_until(
                    lock, deadline, [&] {
                        return waiter->signaled ||
                            debuggerAllStopRequested.load(
                                std::memory_order_acquire) ||
                            nativeShutdownRequested.load(
                                std::memory_order_acquire) ||
                            guestProcessExitRequested.load(
                                std::memory_order_acquire);
                    });
                if (!woke) {
                    break;
                }
            }
            if (waiter->signaled) {
                break;
            }

            const auto pauseStart =
                std::chrono::steady_clock::now();
            lock.unlock();
            const bool paused =
                NativeDebuggerPauseHostWaitIfNeeded();
            lock.lock();
            if (paused &&
                    (nativeGuestRuntime == nullptr ||
                     nativeDebuggerHostWaitStep ||
                     nativeShutdownRequested.load(
                         std::memory_order_acquire) ||
                     guestProcessExitRequested.load(
                         std::memory_order_acquire))) {
                nativeGuestWaiters.erase(std::remove(
                    nativeGuestWaiters.begin(),
                    nativeGuestWaiters.end(),
                    waiter), nativeGuestWaiters.end());
                return GuestUlockReturn(EINTR, flags);
            }
            if (timeout != 0) {
                deadline += std::chrono::steady_clock::now() -
                    pauseStart;
            }
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
    std::unique_lock<std::recursive_mutex> lock(
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
        lock.unlock();
        NativeDebuggerTransferStopOwner(
            2, 1);
        if (PumpGuestWorkqueue()) {
            jit->HaltExecution(LC32HaltReasonWorkqueue);
        }
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
    lock.unlock();
    NativeDebuggerTransferStopOwner(1, 2);
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

static GuestVmEpochParticipant *
CurrentGuestVmEpochParticipant() {
    return nativeGuestRuntime != nullptr
        ? &nativeGuestRuntime->vmEpochParticipant
        : &mainGuestVmParticipant;
}

static Dynarmic::HaltReason RunGuestJit(
        Dynarmic::A32::Jit *jit) {
    GuestVmEpochGuard guard(
        CurrentGuestVmEpochParticipant());
    return jit->Run();
}

static Dynarmic::HaltReason StepGuestJit(
        Dynarmic::A32::Jit *jit) {
    GuestVmEpochGuard guard(
        CurrentGuestVmEpochParticipant());
    return jit->Step();
}

static void ServiceGuestSVC() {
    GuestVmEpochGuard guard(
        CurrentGuestVmEpochParticipant());
    threadHandle.cb->CallSVC(0x80);
    HandleGuestContextTransition();
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    nativeInitialize
 * Signature: (Z)J
 */
bool Dynarmic_nativeInitialize() {
    std::unique_lock<std::mutex> lifecycleLock(
        nativeLifecycleMutex);
    if (nativeLifecycleState ==
            NativeLifecycleState::Running) {
        return true;
    }
    if (nativeLifecycleState ==
            NativeLifecycleState::ShuttingDown) {
        nativeLifecycleCondition.wait(
            lifecycleLock, [] {
                return nativeLifecycleState !=
                    NativeLifecycleState::ShuttingDown;
            });
    }
    if (nativeLifecycleState ==
            NativeLifecycleState::Destroyed) {
        return false;
    }
    nativeShutdownRequested.store(
        false, std::memory_order_release);
    guestProcessExitRequested.store(
        false, std::memory_order_release);
    guestProcessExitCode.store(
        0, std::memory_order_release);

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
        RegisterGuestVmEpochParticipant(
            &mainGuestVmParticipant);
    }
    nativeLifecycleState =
        NativeLifecycleState::Running;
    lifecycleLock.unlock();
    nativeLifecycleCondition.notify_all();
    return true;
}

static void ReleaseMemoryBackingReference(
        t_memory_backing backing) {
    if (backing == nullptr) {
        return;
    }
    assert(backing->references != 0);
    if (--backing->references != 0) {
        return;
    }
    RetireMemoryBacking(backing);
}

static void ReleaseMemoryPageBacking(
        t_memory_page page) {
    if (page == nullptr) {
        return;
    }
    t_memory_backing backing = page->backing;
    page->backing = nullptr;
    ReleaseMemoryBackingReference(backing);
}

void Dynarmic_nativeDestroy() {
    if (nativeGuestRuntime != nullptr &&
            nativeGuestThreadId > 1) {
        /*
         * A worker cannot join itself. Ask the main host thread to perform the
         * serialized teardown when control returns from guest execution.
         */
        nativeShutdownRequested.store(
            true, std::memory_order_release);
        HaltAllGuestJits(LC32HaltReasonExit);
        InterruptDebuggerMachCalls();
        NotifyNativeDebuggerWaiters();
        NotifyNativeDebuggerCoordinator();
        return;
    }

    {
        std::unique_lock<std::mutex> lock(
            nativeLifecycleMutex);
        if (nativeLifecycleState ==
                NativeLifecycleState::Uninitialized ||
                nativeLifecycleState ==
                    NativeLifecycleState::Destroyed) {
            return;
        }
        if (nativeLifecycleState ==
                NativeLifecycleState::ShuttingDown) {
            nativeLifecycleCondition.wait(lock, [] {
                return nativeLifecycleState ==
                    NativeLifecycleState::Destroyed;
            });
            return;
        }
        nativeLifecycleState =
            NativeLifecycleState::ShuttingDown;
        nativeShutdownRequested.store(
            true, std::memory_order_release);
    }

    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        nativeDebugger.state =
            NativeDebuggerRunState::ShuttingDown;
        debuggerAllStopRequested.store(
            true, std::memory_order_release);
    }
    HaltAllGuestJits(LC32HaltReasonExit);
    DrainDebuggerMachCalls();
    NotifyNativeDebuggerWaiters();
    NotifyNativeDebuggerCoordinator();

    std::vector<NativeGuestJit *> runtimes;
    {
        std::lock_guard<std::mutex> lock(
            nativeGuestJitMutex);
        runtimes = nativeGuestJits;
    }
    for (NativeGuestJit *runtime : runtimes) {
        JoinNativeGuestJit(runtime);
    }
    for (NativeGuestJit *runtime : runtimes) {
        DestroyNativeGuestJit(runtime);
    }

    Dynarmic::A32::Jit *jit = threadHandle.jit;
    DynarmicCallbacks32 *cb = sharedHandle.cb;
    DynarmicCpsr *cpsr = threadHandle.cpsr;
    threadHandle = {};
    sharedHandle.cb = nullptr;
    UnregisterGuestVmEpochParticipant(
        &mainGuestVmParticipant);
    if (jit != nullptr) {
        jit->ClearCache();
        jit->Reset();
    }
    delete cpsr;
    delete jit;
    if (cb != nullptr) {
        cb->destroy();
    }
    delete sharedHandle.fs;
    sharedHandle.fs = nullptr;

    {
        std::lock_guard<std::recursive_mutex> lock(
            guestVmMutex);
        khash_t(memory) *memory = sharedHandle.memory;
        if (memory != nullptr) {
            for (khiter_t k = kh_begin(memory);
                    k < kh_end(memory); ++k) {
                if (kh_exist(memory, k)) {
                    t_memory_page page =
                        kh_value(memory, k);
                    ReleaseMemoryPageBacking(page);
                    free(page);
                }
            }
            kh_destroy(memory, memory);
            sharedHandle.memory = nullptr;
        }
    }
    if (sharedHandle.page_table != nullptr) {
        const size_t tableSize =
            sharedHandle.num_page_table_entries *
            sizeof(void *);
        const int result = munmap(
            sharedHandle.page_table, tableSize);
        if (result != 0) {
            fprintf(stderr,
                "munmap failed[%s->%s:%d]: "
                "page_table=%p, ret=%d\n",
                __FILE__, __func__, __LINE__,
                sharedHandle.page_table, result);
        }
        sharedHandle.page_table = nullptr;
        sharedHandle.num_page_table_entries = 0;
    }
    delete sharedHandle.monitor;
    sharedHandle.monitor = nullptr;

    std::vector<mach_port_t> threadPorts;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        for (const GuestThreadContext &thread :
                guestThreads) {
            if (MACH_PORT_VALID(thread.threadPort)) {
                threadPorts.push_back(
                    thread.threadPort);
            }
        }
        guestThreads.clear();
        guestThreadRegistryInitialized = false;
        guestCurrentThreadId = 1;
        guestNextDebuggerThreadId = 3;
        guestProcessorIdsInUse = 1;
    }
    if (MACH_PORT_VALID(guestWorkqueueThreadPort)) {
        threadPorts.push_back(
            guestWorkqueueThreadPort);
        guestWorkqueueThreadPort =
            MACH_PORT_NULL;
    }
    std::sort(threadPorts.begin(), threadPorts.end());
    threadPorts.erase(std::unique(
        threadPorts.begin(), threadPorts.end()),
        threadPorts.end());
    for (mach_port_t port : threadPorts) {
        (void)mach_port_destroy(
            mach_task_self(), port);
    }
    {
        std::lock_guard<std::mutex> lock(
            nativeGuestWaitMutex);
        nativeGuestWaiters.clear();
    }
    {
        std::lock_guard<std::mutex> lock(
            guestPsynchPrepostMutex);
        guestPsynchPreposts.clear();
    }

    guestDebuggerEnabled.store(
        false, std::memory_order_release);
    debuggerInterruptRequested.store(
        false, std::memory_order_release);
    debuggerAllStopRequested.store(
        false, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        nativeDebugger.state =
            NativeDebuggerRunState::Disabled;
        nativeDebugger.executingWorkers = 0;
        nativeDebugger.mainExecuting = false;
    }
    nativeGuestThreadId = 0;
    nativeShutdownRequested.store(
        false, std::memory_order_release);
    guestProcessExitRequested.store(
        false, std::memory_order_release);
    guestProcessExitCode.store(
        0, std::memory_order_release);

    {
        std::lock_guard<std::mutex> lock(
            nativeLifecycleMutex);
        nativeLifecycleState =
            NativeLifecycleState::Destroyed;
    }
    nativeLifecycleCondition.notify_all();
}

int Dynarmic_munmap(u64 address, u64 size) {
    std::unique_lock<std::recursive_mutex> lock(
        guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    if (!GuestAddressRangeIsValid32(
            address, size)) {
        errno = EINVAL;
        return -1;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    const u64 end = address + size;

    /*
     * Validate the complete range first. munmap has no fallible operation
     * after this point, so a hole must not leave the preceding pages already
     * removed.
     */
    for (u64 vaddr = address; vaddr < end;
            vaddr += DYN_PAGE_SIZE) {
        if (kh_get(memory, memory, vaddr) ==
                kh_end(memory)) {
            fprintf(stderr,
                "mem_unmap failed[%s->%s:%d]: vaddr=%p\n",
                __FILE__, __func__, __LINE__,
                reinterpret_cast<void *>(vaddr));
            errno = ENOMEM;
            return -1;
        }
    }

    for(u64 vaddr = address; vaddr < end;
            vaddr += DYN_PAGE_SIZE) {
        u64 idx = vaddr >> DYN_PAGE_BITS;
        khiter_t k = kh_get(memory, memory, vaddr);
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
    lock.unlock();
    InvalidateAllGuestJits(
        static_cast<u32>(address),
        static_cast<size_t>(size));
    return 0;
}

struct GuestPageReservation {
    u64 address;
    t_memory_page page;
};

static void RollbackGuestPageReservations(
        khash_t(memory) *memory,
        std::vector<GuestPageReservation>
            *reservations) {
    if (reservations == nullptr) {
        return;
    }
    for (auto iterator = reservations->rbegin();
            iterator != reservations->rend();
            ++iterator) {
        const khiter_t entry = kh_get(
            memory, memory, iterator->address);
        if (entry != kh_end(memory) &&
                kh_value(memory, entry) ==
                    iterator->page) {
            kh_del(memory, memory, entry);
        }
        free(iterator->page);
    }
    reservations->clear();
}

static bool AlignGuestAddress(
        u64 address, u64 mask, u64 *alignedAddress) {
    constexpr u64 addressSpaceSize =
        UINT64_C(1) << 32;
    const u64 adjustment =
        (mask + 1 - (address & mask)) & mask;
    if (address >= addressSpaceSize ||
            adjustment >
                addressSpaceSize - address) {
        return false;
    }
    *alignedAddress = address + adjustment;
    return *alignedAddress < addressSpaceSize;
}

static u64 Dynarmic_mem_reserve(
        u64 address, u64 size, bool fixed, u64 mask,
        std::vector<GuestPageReservation>
            *reservations) {
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);

    if (reservations == nullptr ||
            size == 0 ||
            (size & DYN_PAGE_MASK) != 0 ||
            mask < DYN_PAGE_MASK ||
            mask > UINT32_MAX ||
            (mask & (mask + 1)) != 0) {
        errno = EINVAL;
        return UINT64_MAX;
    }
    reservations->clear();
    
    /*
     * Keep anonymous allocations away from low addresses so stray pointers
     * are still easy to diagnose.  Fixed mappings are different: legacy
     * non-PIE ARM executables are linked as low as 0x1000 and must retain
     * those addresses because they have no rebase records.  Preserve only
     * the actual null-page guard for MAP_FIXED mappings.
     */
    if (fixed) {
        if (address < DYN_PAGE_SIZE) {
            printf("Dynarmic_mem_reserve: refusing to reserve the null page\n");
            errno = ENOMEM;
            return UINT64_MAX;
        }
    } else if (address < 0x10000000) {
        address += 0x10000000;
    }

    if (!AlignGuestAddress(
            address, mask, &address) ||
            !GuestAddressRangeIsValid32(
                address, size)) {
        errno = fixed ? EINVAL : ENOMEM;
        return UINT64_MAX;
    }

    khash_t(memory) *memory = sharedHandle.memory;
    const u64 end = address + size;
    if (fixed) {
        for(u64 vaddr = address; vaddr < end;
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
            const u64 candidateEnd =
                address + size;
            for(u64 vaddr = address;
                    vaddr < candidateEnd;
                    vaddr += DYN_PAGE_SIZE) {
                if(kh_get(memory, memory, vaddr) == kh_end(memory)) {
                    continue;
                }
                const u64 next =
                    vaddr + DYN_PAGE_SIZE;
                if (!AlignGuestAddress(
                        next, mask, &address) ||
                        !GuestAddressRangeIsValid32(
                            address, size)) {
                    errno = ENOMEM;
                    return UINT64_MAX;
                }
                collision = true;
                break;
            }
            if(!collision) {
                break;
            }
        }
    }

    try {
        reservations->reserve(
            static_cast<size_t>(
                size / DYN_PAGE_SIZE));
    } catch (const std::exception &) {
        errno = ENOMEM;
        return UINT64_MAX;
    }

    const u64 reservationEnd = address + size;
    for(u64 vaddr = address; vaddr < reservationEnd;
            vaddr += DYN_PAGE_SIZE) {
        khiter_t k = kh_get(
            memory, memory, vaddr);
        if (k != kh_end(memory)) {
            assert(fixed);
            continue;
        }
        t_memory_page page = static_cast<t_memory_page>(
            calloc(1, sizeof(struct memory_page)));
        if (page == nullptr) {
            RollbackGuestPageReservations(
                memory, reservations);
            errno = ENOMEM;
            return UINT64_MAX;
        }
        try {
            reservations->push_back({
                vaddr, page,
            });
        } catch (const std::exception &) {
            free(page);
            RollbackGuestPageReservations(
                memory, reservations);
            errno = ENOMEM;
            return UINT64_MAX;
        }
        int ret = 0;
        k = kh_put(memory, memory, vaddr, &ret);
        if (ret < 0 || k == kh_end(memory)) {
            RollbackGuestPageReservations(
                memory, reservations);
            errno = ENOMEM;
            return UINT64_MAX;
        }
        if (ret == 0) {
            RollbackGuestPageReservations(
                memory, reservations);
            errno = EEXIST;
            return UINT64_MAX;
        }
        kh_value(memory, k) = page;
    }
    
    printf("Dynarmic_mem_reserve: 0x%llx-0x%llx\n", address, address + size);
    return address;
}

u32 Dynarmic_direct_mmap(
        u32 address, u64 size, int protection,
        int flags, void *src, u64 off) {
    std::unique_lock<std::recursive_mutex> lock(
        guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    if (!GuestProtectionIsValid(protection) ||
            !GuestAddressRangeIsValid32(
                address, size)) {
        errno = EINVAL;
        return UINT32_MAX;
    }
    
    khash_t(memory) *memory = sharedHandle.memory;
    std::vector<GuestPageReservation>
        reservations;
    const u64 reservedAddress =
        Dynarmic_mem_reserve(
            address, size, flags & MAP_FIXED,
            DYN_PAGE_MASK, &reservations);
    if(reservedAddress == UINT64_MAX) {
        fprintf(stderr, "reserve failed[%s->%s:%d]: addr=0x%x\n", __FILE__, __func__, __LINE__, address);
        return UINT32_MAX;
    }
    address = static_cast<u32>(reservedAddress);
    
    const u64 end = reservedAddress + size;
    for(u64 vaddr = reservedAddress; vaddr < end;
            vaddr += DYN_PAGE_SIZE) {
        u64 idx = vaddr >> DYN_PAGE_BITS;
        
        void *addr = reinterpret_cast<void *>(
            reinterpret_cast<u64>(src) + off +
                vaddr - reservedAddress);
        t_memory_page page = kh_value(memory, kh_get(memory, memory, vaddr));
        t_memory_backing oldBacking =
            page->backing;
        page->addr = addr;
        page->perms = protection;
        page->enforceDataPermissions =
            (protection & PROT_READ) == 0;
        page->backing = nullptr;
        if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[idx],
                GuestPageTablePointer(page),
                __ATOMIC_RELEASE);
        } else {
            // 0xffffff80001f0000ULL: 0x10000
        }
        ReleaseMemoryBackingReference(
            oldBacking);
    }
    reservations.clear();
    lock.unlock();
    InvalidateAllGuestJits(
        address, static_cast<size_t>(size));
    return address;
}

u32 Dynarmic_mmap(
        u32 address, u64 size, int protection,
        int flags, int fildes, u64 off, u64 mask) {
    std::unique_lock<std::recursive_mutex> lock(
        guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    if (!GuestProtectionIsValid(protection) ||
            !GuestAddressRangeIsValid32(
                address, size)) {
        errno = EINVAL;
        return UINT32_MAX;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    std::vector<GuestPageReservation>
        reservations;
    const u64 reservedAddress =
        Dynarmic_mem_reserve(
            address, size, flags & MAP_FIXED,
            mask, &reservations);
    if(reservedAddress == UINT64_MAX) {
        fprintf(stderr, "reserve failed[%s->%s:%d]: addr=0x%x\n", __FILE__, __func__, __LINE__, address);
        return UINT32_MAX;
    }
    address = static_cast<u32>(reservedAddress);
    
    const int guestProtection = protection;
    const bool debuggerWritableExecutableFile =
        (guestProtection & PROT_EXEC) != 0 &&
        fildes != -1 && size > 0x1000 && off == 0;
    if (debuggerWritableExecutableFile) {
        flags |= MAP_PRIVATE;
        flags &= ~MAP_SHARED;
    }
    
    off_t aligned_off = off & ~(PAGE_SIZE-1);
    const size_t mappingSize = size + (off - aligned_off);
    int hostProtection =
        HostProtectionForGuestPermissions(
            guestProtection);
    /*
     * Keep owned anonymous storage readable/writable so debugger and syscall
     * copyin/copyout helpers never take a host protection fault. Initial
     * read-bearing mappings intentionally retain the historical page-table
     * fast path for dyld/shared-cache performance, so their data permissions
     * are compatibility-mode rather than strict. PROT_NONE/write-only
     * mappings and every explicit mprotect transition use callbacks for
     * strict guest data permissions. Executable file mappings are made
     * private and writable solely so software breakpoints can patch them.
     */
    if ((flags & MAP_ANONYMOUS) != 0) {
        hostProtection |= PROT_READ | PROT_WRITE;
    }
    if (debuggerWritableExecutableFile) {
        hostProtection |= PROT_READ | PROT_WRITE;
    }
    void *mappingAddress = mmap(
        NULL, mappingSize, hostProtection,
        flags & ~MAP_FIXED, fildes, aligned_off);
    if(mappingAddress == MAP_FAILED) {
        fprintf(stderr, "mmap failed[%s->%s:%d]: addr=%p\n", __FILE__, __func__, __LINE__, mappingAddress);
        RollbackGuestPageReservations(
            memory, &reservations);
        return UINT32_MAX;
    }
    t_memory_backing backing =
        static_cast<t_memory_backing>(
            calloc(1, sizeof(struct memory_backing)));
    if (backing == nullptr) {
        (void)munmap(mappingAddress, mappingSize);
        RollbackGuestPageReservations(
            memory, &reservations);
        errno = ENOMEM;
        return UINT32_MAX;
    }
    backing->addr = mappingAddress;
    backing->size = mappingSize;
    backing->references = size / DYN_PAGE_SIZE;
    backing->hostProtection = hostProtection;
    u64 addr = reinterpret_cast<u64>(mappingAddress) +
        (off - aligned_off);
    
    printf("DBG: mmaping host 0x%llx to 0x%x\n", addr, address);
    
    const u64 end = reservedAddress + size;
    for(u64 vaddr = reservedAddress; vaddr < end;
            vaddr += DYN_PAGE_SIZE) {
        u64 idx = vaddr >> DYN_PAGE_BITS;
        
        t_memory_page page = kh_value(memory, kh_get(memory, memory, vaddr));
        t_memory_backing oldBacking =
            page->backing;
        page->addr = (void *)addr;
        page->perms = guestProtection;
        /*
         * Read-only shared-cache ranges are performance-critical and were
         * historically direct-mapped. Keep that initial compatibility path;
         * PROT_NONE/write-only pages and every explicit mprotect transition
         * use callbacks for strict per-4K data permissions.
         */
        page->enforceDataPermissions =
            (guestProtection & PROT_READ) == 0;
        page->backing = backing;
        if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[idx],
                GuestPageTablePointer(page),
                __ATOMIC_RELEASE);
        } else {
            // 0xffffff80001f0000ULL: 0x10000
        }
        ReleaseMemoryBackingReference(
            oldBacking);
        
        addr += DYN_PAGE_SIZE;
    }
    reservations.clear();
    lock.unlock();
    InvalidateAllGuestJits(
        address, static_cast<size_t>(size));
    return address;
}

int Dynarmic_mprotect(u64 address, u64 size, int perms) {
    std::unique_lock<std::recursive_mutex> lock(
        guestVmMutex);
    if(address & DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }
    if(size == 0 || (size & DYN_PAGE_MASK)) {
        errno = EINVAL;
        return -1;
    }
    if (!GuestProtectionIsValid(perms)) {
        errno = EINVAL;
        return -1;
    }
    if (size > UINT64_MAX - address) {
        errno = EINVAL;
        return -1;
    }
    if (!GuestAddressRangeIsValid32(
            address, size)) {
        errno = EINVAL;
        return -1;
    }

    struct ProtectedPage {
        u64 address;
        t_memory_page page;
    };
    struct BackingProtectionUpdate {
        t_memory_backing backing;
        int requiredHostProtection;
    };

    khash_t(memory) *memory = sharedHandle.memory;
    std::vector<ProtectedPage> pages;
    std::vector<BackingProtectionUpdate>
        backingUpdates;
    std::unordered_map<t_memory_backing, size_t>
        backingUpdateIndices;

    try {
        pages.reserve(
            static_cast<size_t>(
                size / DYN_PAGE_SIZE));
        for(u64 vaddr = address;
                vaddr < address + size;
                vaddr += DYN_PAGE_SIZE) {
            khiter_t k = kh_get(
                memory, memory, vaddr);
            if(k == kh_end(memory)) {
                fprintf(stderr,
                    "mem_protect failed[%s->%s:%d]: "
                    "vaddr=%p\n",
                    __FILE__, __func__, __LINE__,
                    reinterpret_cast<void *>(vaddr));
                errno = ENOMEM;
                return -1;
            }
            t_memory_page page =
                kh_value(memory, k);
            pages.push_back({vaddr, page});
            if (page->backing == nullptr) {
                continue;
            }
            const auto insertion =
                backingUpdateIndices.emplace(
                    page->backing,
                    backingUpdates.size());
            if (insertion.second) {
                backingUpdates.push_back({
                    page->backing,
                    page->backing->hostProtection |
                        HostProtectionForGuestPermissions(
                            perms),
                });
            }
        }
    } catch (const std::exception &) {
        errno = ENOMEM;
        return -1;
    }

    /*
     * Remove fast-path pointers before changing permissions. Any new access
     * then enters a callback and waits on guestVmMutex until the operation is
     * committed or rolled back.
     */
    for (const ProtectedPage &protectedPage :
            pages) {
        const u64 index =
            protectedPage.address >> DYN_PAGE_BITS;
        if (sharedHandle.page_table != nullptr &&
                index <
                    sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[index],
                nullptr, __ATOMIC_RELEASE);
        }
    }

    /*
     * Host protections are widened when a guest page gains permissions, but
     * are never narrowed. Per-page guest permissions are enforced by the
     * page table/callback layer. This is intentional: one 16 KiB host page
     * can contain four independently protected 4 KiB guest pages, and
     * revoking the host page could crash another guest thread that already
     * loaded its fast-path pointer.
     */
    for (const BackingProtectionUpdate &update :
            backingUpdates) {
        if (update.requiredHostProtection ==
                update.backing->hostProtection) {
            continue;
        }
        if (mprotect(
                update.backing->addr,
                update.backing->size,
                update.requiredHostProtection) != 0) {
            const int savedErrno = errno;
            for (const ProtectedPage &protectedPage :
                    pages) {
                const u64 index =
                    protectedPage.address >>
                        DYN_PAGE_BITS;
                if (sharedHandle.page_table != nullptr &&
                        index <
                            sharedHandle
                                .num_page_table_entries) {
                    __atomic_store_n(
                        &sharedHandle
                            .page_table[index],
                        GuestPageTablePointer(
                            protectedPage.page),
                        __ATOMIC_RELEASE);
                }
            }
            errno = savedErrno;
            return -1;
        }
        update.backing->hostProtection =
            update.requiredHostProtection;
    }

    for (const ProtectedPage &protectedPage :
            pages) {
        protectedPage.page->perms = perms;
        protectedPage.page->enforceDataPermissions =
            true;
        const u64 index =
            protectedPage.address >> DYN_PAGE_BITS;
        if (sharedHandle.page_table != nullptr &&
                index <
                    sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[index],
                GuestPageTablePointer(
                    protectedPage.page),
                __ATOMIC_RELEASE);
        }
    }
    lock.unlock();
    InvalidateAllGuestJits(
        static_cast<u32>(address),
        static_cast<size_t>(size));
    return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    mem_write
 * Signature: (JJ[B)I
 */
int Dynarmic_mem_1write(u64 address, u64 size, char* src) {
    if (size == 0) {
        return 0;
    }
    if (src == nullptr ||
            !GuestAddressRangeIsValid32(
                address, size)) {
        return 1;
    }
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
    if (size == 0) {
        return 0;
    }
    if (dest == nullptr ||
            !GuestAddressRangeIsValid32(
                address, size)) {
        return 1;
    }
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
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        for (const GuestThreadContext &thread : guestThreads) {
            if (!thread.alive) {
                continue;
            }
            if (thread.debuggerId == 1 ||
                    thread.debuggerId >= 3) {
                append(thread.debuggerId);
            }
        }
    }
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid) {
            append(2);
        }
    }
    return count;
}

gdb_thread_id_t Dynarmic_debugger_current_thread() {
    EnsureGuestThreadRegistry();
    if (NativeDebuggerActive()) {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        return nativeDebugger.stopOwner;
    }
    return guestWorkqueueUpcallActive
        ? 2
        : guestCurrentThreadId;
}

bool Dynarmic_debugger_thread_alive(gdb_thread_id_t thread_id) {
    if (sharedHandle.cb == nullptr ||
            sharedHandle.cb->cpu == nullptr) {
        return false;
    }
    EnsureGuestThreadRegistry();
    if (thread_id == 2) {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        return guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    for (const GuestThreadContext &thread : guestThreads) {
        if (thread.debuggerId == thread_id) {
            return thread.alive;
        }
    }
    return false;
}

bool Dynarmic_debugger_thread_resumable(
        gdb_thread_id_t thread_id) {
    if (!Dynarmic_debugger_thread_alive(thread_id)) {
        return false;
    }
    bool overlayAllowsThread;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        /*
         * The workqueue pseudo-thread overlays the main JIT. Its interrupted
         * context remains readable as thread 1, but cannot execute
         * independently until thread 2 returns and restores it.
         */
        overlayAllowsThread =
            !guestWorkqueueUpcallActive ||
            !guestWorkqueueWaitingContextValid ||
            thread_id != guestWorkqueueWaitingThreadId;
    }
    if (!overlayAllowsThread ||
            NativeGuestThreadsEnabled() ||
            thread_id == 2) {
        return overlayAllowsThread;
    }

    /*
     * A cooperative thread can be selected by LLDB only when its saved
     * context is runnable. The target thread loads that context immediately
     * before executing the resume request.
     */
    std::lock_guard<std::recursive_mutex> threadLock(
        guestThreadMutex);
    for (const GuestThreadContext &thread : guestThreads) {
        if (thread.debuggerId == thread_id) {
            return thread.alive && thread.runnable &&
                (thread_id == guestCurrentThreadId ||
                 thread.savedValid);
        }
    }
    return false;
}

static bool SelectCooperativeDebuggerThread(
        gdb_thread_id_t thread_id) {
    if (NativeGuestThreadsEnabled()) {
        return true;
    }
    EnsureGuestThreadRegistry();
    {
        std::lock_guard<std::recursive_mutex> workqueueLock(
            guestWorkqueueMutex);
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid) {
            return thread_id == 2;
        }
        if (thread_id == 2) {
            return false;
        }
    }

    std::lock_guard<std::recursive_mutex> threadLock(
        guestThreadMutex);
    if (thread_id == guestCurrentThreadId) {
        return true;
    }
    GuestThreadContext *current =
        FindGuestThread(guestCurrentThreadId, true);
    GuestThreadContext *selected =
        FindGuestThread(thread_id, true);
    if (current == nullptr || selected == nullptr ||
            !selected->runnable ||
            !selected->savedValid ||
            threadHandle.jit == nullptr ||
            threadHandle.cb == nullptr) {
        return false;
    }

    SaveGuestContext(current->saved);
    current->savedValid = true;
    LoadGuestContext(selected->saved);
    guestCurrentThreadId = thread_id;
    guestThreadRotationRequested = false;
    guestThreadCurrentRetiring = false;
    return true;
}

bool Dynarmic_debugger_thread_read_reg(
        gdb_thread_id_t thread_id, int regno, u32 *value) {
    if (value == nullptr || regno < 0 || regno > 16) {
        return false;
    }

    std::unique_lock<std::mutex> debuggerLock;
    if (NativeDebuggerActive()) {
        debuggerLock = std::unique_lock<std::mutex>(
            nativeDebugger.mutex);
        if (nativeDebugger.state !=
                NativeDebuggerRunState::Stopped ||
                nativeDebugger.mainExecuting ||
                nativeDebugger.executingWorkers != 0) {
            return false;
        }
    }

    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid &&
                thread_id == 2) {
            Dynarmic::A32::Jit *jit =
                sharedHandle.cb != nullptr
                ? sharedHandle.cb->cpu
                : nullptr;
            if (jit == nullptr) {
                return false;
            }
            *value = regno == 16
                ? static_cast<u32>(jit->Cpsr())
                : jit->Regs()[regno];
            return true;
        }
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid &&
                thread_id ==
                    guestWorkqueueWaitingThreadId) {
            *value = regno == 16
                ? guestWorkqueueWaitingContext.cpsr
                : guestWorkqueueWaitingContext.regs[regno];
            return true;
        }
        if (thread_id == 2) {
            return false;
        }
    }

    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    for (GuestThreadContext &thread : guestThreads) {
        if (thread.debuggerId != thread_id ||
                !thread.alive) {
            continue;
        }
        Dynarmic::A32::Jit *jit = nullptr;
        if (NativeDebuggerActive()) {
            jit = thread_id == 1
                ? (sharedHandle.cb != nullptr
                    ? sharedHandle.cb->cpu
                    : nullptr)
                : (thread.nativeJit != nullptr
                    ? thread.nativeJit->jit
                    : nullptr);
        } else if (thread_id ==
                Dynarmic_debugger_current_thread()) {
            jit = threadHandle.jit;
        }
        if (jit != nullptr) {
            *value = regno == 16
                ? static_cast<u32>(jit->Cpsr())
                : jit->Regs()[regno];
            return true;
        }
        if (thread.savedValid) {
            *value = regno == 16
                ? thread.saved.cpsr
                : thread.saved.regs[regno];
            return true;
        }
        return false;
    }
    return false;
}

bool Dynarmic_debugger_thread_write_reg(
        gdb_thread_id_t thread_id, int regno, u32 value) {
    if (regno < 0 || regno > 16) {
        return false;
    }

    std::unique_lock<std::mutex> debuggerLock;
    if (NativeDebuggerActive()) {
        debuggerLock = std::unique_lock<std::mutex>(
            nativeDebugger.mutex);
        if (nativeDebugger.state !=
                NativeDebuggerRunState::Stopped ||
                nativeDebugger.mainExecuting ||
                nativeDebugger.executingWorkers != 0) {
            return false;
        }
    }

    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid &&
                thread_id == 2) {
            Dynarmic::A32::Jit *jit =
                sharedHandle.cb != nullptr
                ? sharedHandle.cb->cpu
                : nullptr;
            if (jit == nullptr) {
                return false;
            }
            if (regno == 16) {
                jit->SetCpsr(value);
            } else {
                jit->Regs()[regno] = value;
            }
            return true;
        }
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid &&
                thread_id ==
                    guestWorkqueueWaitingThreadId) {
            if (regno == 16) {
                guestWorkqueueWaitingContext.cpsr = value;
            } else {
                guestWorkqueueWaitingContext.regs[regno] =
                    value;
            }
            return true;
        }
        if (thread_id == 2) {
            return false;
        }
    }

    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    for (GuestThreadContext &thread : guestThreads) {
        if (thread.debuggerId != thread_id ||
                !thread.alive) {
            continue;
        }
        Dynarmic::A32::Jit *jit = nullptr;
        if (NativeDebuggerActive()) {
            if (thread.nativeJit != nullptr &&
                    thread.nativeJit->debuggerHostWaitPaused) {
                /*
                 * The stopped host callback has not copied its syscall result
                 * back to the JIT register file yet. Reject writes instead of
                 * reporting success and silently overwriting them on resume.
                 */
                return false;
            }
            jit = thread_id == 1
                ? (sharedHandle.cb != nullptr
                    ? sharedHandle.cb->cpu
                    : nullptr)
                : (thread.nativeJit != nullptr
                    ? thread.nativeJit->jit
                    : nullptr);
        } else if (thread_id ==
                Dynarmic_debugger_current_thread()) {
            jit = threadHandle.jit;
        }
        if (jit != nullptr) {
            if (regno == 16) {
                jit->SetCpsr(value);
            } else {
                jit->Regs()[regno] = value;
            }
            return true;
        }
        if (thread.savedValid) {
            if (regno == 16) {
                thread.saved.cpsr = value;
            } else {
                thread.saved.regs[regno] = value;
            }
            return true;
        }
        return false;
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
        reason = RunGuestJit(cpu);
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
        ServiceGuestSVC();
      }
    } else {
      return LC32HaltReasonTrap;
    }
  UpdateGuestStopSignalForHalt(reason);
  return reason;
}

static void ServiceDeferredGuestSVC() {
    guestDeferredSVC = false;
    ServiceGuestSVC();
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
    if (guestDeferredSVC) {
        ServiceDeferredGuestSVC();
        if (!NativeDebuggerMainContextMayRun()) {
            reason = Dynarmic::HaltReason::Step;
            UpdateGuestStopSignalForHalt(reason);
            return reason;
        }
    }
    for (;;) {
        reason = RunGuestJit(jit);
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
            if (!NativeDebuggerMainContextMayRun()) {
                reason = Dynarmic::HaltReason::Step;
                break;
            }
            continue;
        }
        if (!Dynarmic::Has(reason, LC32HaltReasonSVC)) {
            break;
        }
        const Dynarmic::HaltReason remaining =
            reason & ~LC32HaltReasonSVC;
        if (!!remaining) {
            guestDeferredSVC = true;
            reason = remaining;
            break;
        }
        ServiceDeferredGuestSVC();
        if (!NativeDebuggerMainContextMayRun()) {
            reason = Dynarmic::HaltReason::Step;
            break;
        }
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
    if (guestDeferredSVC) {
        ServiceDeferredGuestSVC();
        reason = Dynarmic::HaltReason::Step;
        guestSingleStepping = false;
        UpdateGuestStopSignalForHalt(reason);
        return reason;
    }
    for (;;) {
        reason = drainInternalWorker
            ? RunGuestJit(jit)
            : StepGuestJit(jit);
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
        const Dynarmic::HaltReason remaining =
            reason & ~LC32HaltReasonSVC;
        if (!!remaining) {
            guestDeferredSVC = true;
            reason = remaining;
            break;
        }
        ServiceDeferredGuestSVC();
        if (!NativeDebuggerMainContextMayRun()) {
            reason = Dynarmic::HaltReason::Step;
            break;
        }
    }
    guestSingleStepping = false;
    UpdateGuestStopSignalForHalt(reason);
    return reason;
}

static bool NativeDebuggerBeginExecution(
        NativeDebuggerResumeMode mode,
        gdb_thread_id_t stepThread,
        bool mainExecuting) {
    const auto requestedStopOwnerLocked =
        [mode, stepThread] {
            const gdb_thread_id_t candidate =
                mode ==
                    NativeDebuggerResumeMode::ContinueAll
                ? 1
                : stepThread;
            return NativeDebuggerNormalizeStopOwnerLocked(
                candidate != 0 ? candidate : 1);
        };
    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        assert(nativeDebugger.executingWorkers == 0);
        assert(nativeDebugger.state ==
            NativeDebuggerRunState::Stopped);
        /*
         * Publish the incoming selection before clearing old JIT halts. The
         * socket reader can queue ^C during this handoff and must attribute
         * the resulting stop to this request, not the previous vCont mode.
         */
        nativeDebugger.resumeMode = mode;
        nativeDebugger.stepThread = stepThread;
        if (nativeDebugger.pendingInterrupt) {
            nativeDebugger.stopOwner =
                requestedStopOwnerLocked();
            nativeDebugger.stopReason =
                LC32HaltReasonInterrupt;
            nativeDebugger.stopSignal = SIGINT;
            nativeDebugger.pendingInterrupt = false;
            nativeDebugger.resumeStarting = false;
            nativeDebugger.mainExecuting = false;
            CommitGuestStopSignal(SIGINT, false);
            return false;
        }
        nativeDebugger.resumeStarting = true;
    }

    /*
     * HaltExecution is level-triggered. A JIT which was already parked when a
     * peer published the previous stop never entered Run() to consume the
     * debugger-pause bit. Keep the coordinator in Stopped/resumeStarting while
     * clearing every acknowledged JIT. A concurrent ^C is queued under the
     * same mutex and cannot be erased by the Stopped-to-Running handoff.
     */
    ClearAllGuestJitHalts(
        LC32HaltReasonDebuggerPause);
    {
        std::lock_guard<std::mutex> lock(nativeDebugger.mutex);
        if (nativeDebugger.pendingInterrupt) {
            nativeDebugger.stopOwner =
                requestedStopOwnerLocked();
            nativeDebugger.stopReason =
                LC32HaltReasonInterrupt;
            nativeDebugger.stopSignal = SIGINT;
            nativeDebugger.pendingInterrupt = false;
            nativeDebugger.resumeStarting = false;
            nativeDebugger.mainExecuting = false;
            CommitGuestStopSignal(SIGINT, false);
            return false;
        }
        nativeDebugger.state =
            NativeDebuggerRunState::Running;
        nativeDebugger.mainExecuting = mainExecuting;
        nativeDebugger.resumeStarting = false;
        ++nativeDebugger.generation;
        debuggerInterruptRequested.store(
            false, std::memory_order_release);
        debuggerAllStopRequested.store(
            false, std::memory_order_release);
    }
    nativeDebugger.condition.notify_all();
    return true;
}

static Dynarmic::HaltReason NativeDebuggerCompleteStop() {
    std::unique_lock<std::mutex> lock(nativeDebugger.mutex);
    nativeDebugger.mainExecuting = false;
    const auto allThreadsStopped = [] {
        return !NativeDebuggerActive() ||
            (nativeDebugger.state !=
                 NativeDebuggerRunState::Running &&
             nativeDebugger.executingWorkers == 0);
    };
    auto nextHostInterrupt =
        std::chrono::steady_clock::now() +
        std::chrono::milliseconds(20);
    while (!allThreadsStopped()) {
        if (nativeDebugger.condition.wait_until(
                lock, nextHostInterrupt) !=
                std::cv_status::timeout) {
            continue;
        }
        /*
         * A waiter can be descheduled between publishing InCall and entering
         * the kernel, longer than the bounded first interrupt burst. Keep
         * retrying until every executing worker acknowledges this all-stop.
         */
        const bool retryHostInterrupt =
            (nativeDebugger.state ==
                 NativeDebuggerRunState::Stopping ||
             nativeDebugger.state ==
                 NativeDebuggerRunState::ShuttingDown) &&
            nativeDebugger.executingWorkers != 0;
        lock.unlock();
        if (retryHostInterrupt) {
            InterruptDebuggerMachCalls();
        }
        lock.lock();
        nextHostInterrupt =
            std::chrono::steady_clock::now() +
            std::chrono::milliseconds(20);
    }
    if (!NativeDebuggerActive()) {
        return LC32HaltReasonTrap;
    }
    if (nativeDebugger.state ==
            NativeDebuggerRunState::Stopping) {
        nativeDebugger.state =
            NativeDebuggerRunState::Stopped;
    }
    guestStopSignal.store(
        nativeDebugger.stopSignal,
        std::memory_order_relaxed);
    const Dynarmic::HaltReason reason =
        nativeDebugger.stopReason;
    lock.unlock();
    nativeDebugger.condition.notify_all();
    return reason;
}

static Dynarmic::HaltReason NativeDebuggerReemitPendingStop() {
    std::lock_guard<std::mutex> lock(nativeDebugger.mutex);
    nativeDebugger.state =
        NativeDebuggerRunState::Stopped;
    nativeDebugger.stopSignal =
        guestStopSignal.load(std::memory_order_relaxed);
    return nativeDebugger.stopReason;
}

Dynarmic::HaltReason Dynarmic_debugger_continue(
        gdb_thread_id_t thread_id) {
    if (!NativeDebuggerActive()) {
        if (ConsumePendingGuestStop()) {
            return LC32HaltReasonTrap;
        }
        if (thread_id == GDB_THREAD_ID_ANY) {
            thread_id =
                Dynarmic_debugger_current_thread();
        }
        if (thread_id != GDB_THREAD_ID_ALL &&
                !Dynarmic_debugger_thread_resumable(
                    thread_id)) {
            CommitGuestStopSignal(SIGTRAP, false);
            return LC32HaltReasonTrap;
        }
        if (thread_id != GDB_THREAD_ID_ALL &&
                !SelectCooperativeDebuggerThread(
                    thread_id)) {
            CommitGuestStopSignal(SIGTRAP, false);
            return LC32HaltReasonTrap;
        }
        const gdb_thread_id_t previousThread =
            cooperativeDebuggerResumeThread;
        cooperativeDebuggerResumeThread = thread_id;
        const Dynarmic::HaltReason reason =
            Dynarmic_emu_1resume();
        cooperativeDebuggerResumeThread =
            previousThread;
        return reason;
    }
    if (ConsumePendingGuestStop()) {
        return NativeDebuggerReemitPendingStop();
    }

    if (thread_id == GDB_THREAD_ID_ANY) {
        thread_id =
            Dynarmic_debugger_current_thread();
    }
    const bool continueAll =
        thread_id == GDB_THREAD_ID_ALL;
    if (!continueAll &&
            !Dynarmic_debugger_thread_resumable(
                thread_id)) {
        CommitGuestStopSignal(SIGTRAP, false);
        return LC32HaltReasonTrap;
    }
    const bool runMain = continueAll ||
        thread_id == 1 || thread_id == 2;
    if (!NativeDebuggerBeginExecution(
        continueAll
            ? NativeDebuggerResumeMode::ContinueAll
            : NativeDebuggerResumeMode::ContinueOne,
        continueAll ? 0 : thread_id,
        runMain)) {
        return NativeDebuggerCompleteStop();
    }
    if (runMain) {
        const gdb_thread_id_t mainOwner =
            ActiveMainDebuggerThread();
        if (NativeDebuggerRepublishPendingStop(
                mainOwner)) {
            return NativeDebuggerCompleteStop();
        }
        const Dynarmic::HaltReason reason =
            Dynarmic_emu_1resume();
        const Dynarmic::HaltReason visibleReason =
            NativeDebuggerVisibleReason(reason);
        if (!!visibleReason) {
            const gdb_thread_id_t owner =
                ActiveMainDebuggerThread();
            (void)NativeDebuggerRequestStop(
                owner, visibleReason);
        } else {
            bool stillRunning;
            {
                std::lock_guard<std::mutex> lock(
                    nativeDebugger.mutex);
                stillRunning =
                    nativeDebugger.state ==
                        NativeDebuggerRunState::Running;
            }
            if (stillRunning) {
                (void)NativeDebuggerRequestStop(
                    ActiveMainDebuggerThread(),
                    LC32HaltReasonTrap,
                    SIGTRAP, false);
            }
        }
    }
    return NativeDebuggerCompleteStop();
}

Dynarmic::HaltReason Dynarmic_debugger_step(
        gdb_thread_id_t thread_id,
        bool continue_other_threads) {
    if (!NativeDebuggerActive()) {
        if (ConsumePendingGuestStop()) {
            return LC32HaltReasonTrap;
        }
        if (thread_id == GDB_THREAD_ID_ANY ||
                thread_id == GDB_THREAD_ID_ALL) {
            thread_id =
                Dynarmic_debugger_current_thread();
        }
        if (!Dynarmic_debugger_thread_resumable(
                thread_id)) {
            CommitGuestStopSignal(SIGTRAP, false);
            return LC32HaltReasonTrap;
        }
        if (!SelectCooperativeDebuggerThread(
                thread_id)) {
            CommitGuestStopSignal(SIGTRAP, false);
            return LC32HaltReasonTrap;
        }
        const gdb_thread_id_t previousThread =
            cooperativeDebuggerResumeThread;
        cooperativeDebuggerResumeThread = thread_id;
        const Dynarmic::HaltReason reason =
            Dynarmic_emu_1step();
        cooperativeDebuggerResumeThread =
            previousThread;
        return reason;
    }
    if (ConsumePendingGuestStop()) {
        return NativeDebuggerReemitPendingStop();
    }
    if (thread_id == GDB_THREAD_ID_ANY ||
            thread_id == GDB_THREAD_ID_ALL) {
        thread_id =
            Dynarmic_debugger_current_thread();
    }
    if (!Dynarmic_debugger_thread_resumable(
            thread_id)) {
        CommitGuestStopSignal(SIGTRAP, false);
        return LC32HaltReasonTrap;
    }

    const bool stepMain =
        thread_id == 1 || thread_id == 2;
    const bool runMain =
        stepMain || continue_other_threads;
    if (!NativeDebuggerBeginExecution(
        continue_other_threads
            ? NativeDebuggerResumeMode::
                StepOneContinueOthers
            : NativeDebuggerResumeMode::StepOne,
        thread_id, runMain)) {
        return NativeDebuggerCompleteStop();
    }
    if (runMain) {
        const gdb_thread_id_t mainOwner =
            ActiveMainDebuggerThread();
        if (NativeDebuggerRepublishPendingStop(
                mainOwner)) {
            return NativeDebuggerCompleteStop();
        }
        const Dynarmic::HaltReason reason =
            stepMain
            ? Dynarmic_emu_1step()
            : Dynarmic_emu_1resume();
        const Dynarmic::HaltReason visibleReason =
            NativeDebuggerVisibleReason(reason);
        if (!!visibleReason || stepMain) {
            const gdb_thread_id_t owner =
                ActiveMainDebuggerThread();
            (void)NativeDebuggerRequestStop(
                owner,
                !!visibleReason
                    ? visibleReason
                    : Dynarmic::HaltReason::Step);
        }
    }
    return NativeDebuggerCompleteStop();
}

void Dynarmic_emu_1set_1debugger_1enabled(bool enabled) {
    if (enabled && NativeGuestThreadsEnabled()) {
        {
            std::lock_guard<std::mutex> lock(
                nativeDebugger.mutex);
            nativeDebugger.state =
                NativeDebuggerRunState::Stopped;
            nativeDebugger.resumeMode =
                NativeDebuggerResumeMode::ContinueAll;
            nativeDebugger.stopOwner = 1;
            nativeDebugger.stepThread = 1;
            nativeDebugger.stopReason =
                LC32HaltReasonTrap;
            nativeDebugger.stopSignal =
                guestStopSignal.load(std::memory_order_relaxed);
            nativeDebugger.executingWorkers = 0;
            nativeDebugger.mainExecuting = false;
            nativeDebugger.resumeStarting = false;
            nativeDebugger.pendingInterrupt = false;
            debuggerAllStopRequested.store(
                true, std::memory_order_release);
        }
        guestDebuggerEnabled.store(
            true, std::memory_order_release);
        nativeDebugger.condition.notify_all();
        return;
    }
    guestDebuggerEnabled.store(
        enabled, std::memory_order_release);
    if (enabled) {
        return;
    }

    debuggerInterruptRequested.store(
        false, std::memory_order_release);
    debuggerAllStopRequested.store(
        false, std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        if (nativeDebugger.state !=
                NativeDebuggerRunState::ShuttingDown) {
            nativeDebugger.state =
                NativeDebuggerRunState::Disabled;
        }
        nativeDebugger.mainExecuting = false;
    }
    nativeDebugger.condition.notify_all();
    NotifyNativeDebuggerWaiters();
}

int Dynarmic_emu_1get_1stop_1signal() {
    if (NativeDebuggerActive()) {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        return nativeDebugger.stopSignal;
    }
    return guestStopSignal.load(std::memory_order_relaxed);
}

int Dynarmic_emu_1get_1exit_1code() {
    return guestProcessExitCode.load(
        std::memory_order_acquire);
}

void Dynarmic_emu_1set_1resume_1signal(int signal) {
    const int pending =
        pendingGuestFatalSignal.load(std::memory_order_relaxed);
    if (pending > 0 &&
            (signal == 0 || signal == pending)) {
        /*
         * A synchronous guest fault cannot be suppressed by lowercase c/s:
         * Dynarmic memory callbacks do not carry an exact instruction PC, so
         * executing here could step from a stale linked-block boundary. Keep
         * reporting the unresolved fault until the debugger changes register
         * or memory state.
         */
        reemitPendingGuestStop.store(true, std::memory_order_relaxed);
        return;
    }

    // A different signal cannot be faithfully delivered by this userland JIT.
    pendingGuestFatalSignal.store(0, std::memory_order_relaxed);
    reemitPendingGuestStop.store(false, std::memory_order_relaxed);
}

void Dynarmic_debugger_resolve_pending_stop() {
    pendingGuestFatalSignal.store(
        0, std::memory_order_relaxed);
    reemitPendingGuestStop.store(
        false, std::memory_order_relaxed);
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    emu_stop
 * Signature: (J)I
 */
int Dynarmic_emu_1stop() {
    if (NativeDebuggerActive()) {
        gdb_thread_id_t owner =
            ActiveMainDebuggerThread();
        {
            std::lock_guard<std::mutex> lock(
                nativeDebugger.mutex);
            if (nativeDebugger.resumeMode !=
                    NativeDebuggerResumeMode::ContinueAll &&
                    nativeDebugger.stepThread != 0) {
                owner = nativeDebugger.stepThread;
            }
        }
        /*
         * The selected worker can retire inside bsdthread_terminate before
         * its host loop publishes the replacement stop. Never expose a stop
         * owner that qfThreadInfo has already dropped.
         */
        if (!Dynarmic_debugger_thread_alive(owner) ||
                !Dynarmic_debugger_thread_resumable(
                    owner)) {
            owner = ActiveMainDebuggerThread();
        }
        if (!Dynarmic_debugger_thread_alive(owner)) {
            owner = 1;
        }
        debuggerInterruptRequested.store(
            true, std::memory_order_release);
        (void)NativeDebuggerRequestStop(
            owner, LC32HaltReasonInterrupt,
            SIGINT, false, true);
        return 0;
    }

    // on_interrupt is invoked by mini-gdbstub's socket-reader thread. That
    // thread has no thread-local dynarmic_thread, so use the JIT published by
    // the shared callbacks instead of threadHandle.jit.
    DynarmicCallbacks32 *callbacks = sharedHandle.cb;
    Dynarmic::A32::Jit *jit = callbacks ? callbacks->cpu : NULL;
    if(jit) {
      debuggerInterruptRequested.store(true, std::memory_order_release);
      jit->HaltExecution(LC32HaltReasonInterrupt);
      InterruptDebuggerMachCalls();
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
