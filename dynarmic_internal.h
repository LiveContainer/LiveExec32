#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstdarg>
#include <cstdio>
#include <deque>
#include <exception>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <assert.h>
#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <libgen.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

#include <CommonCrypto/CommonCryptor.h>

#include <mach/arm/thread_status.h>
#include <mach/clock.h>
#include <mach/host_info.h>
#include <mach/mach_time.h>
#include <mach/mig_errors.h>
#include <mach/task_info.h>
#include <mach/thread_act.h>
#include <mach/vm_map.h>
#include <mach/vm_page_size.h>
#include <mach/vm_region.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>

#include <sys/attr.h>
#include <sys/errno.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysctl.h>
#include <sys/un.h>
#include <sys/xattr.h>

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

#define msgh_request_port msgh_remote_port
#define msgh_reply_port msgh_local_port

#if defined(__GNUC__)
#define LC32_DYNARMIC_HIDDEN __attribute__((visibility("hidden")))
#else
#define LC32_DYNARMIC_HIDDEN
#endif

inline constexpr Dynarmic::HaltReason LC32HaltReasonThreadState =
    Dynarmic::HaltReason::UserDefined8;
inline constexpr u64 LC32NativeGuestRunSliceTicks = 1ULL << 18;

extern "C" void abort_with_reason(
    uint32_t reason_namespace, uint64_t reason_code,
    const char *reason_string, uint64_t reason_flags)
    __attribute__((noreturn, cold));
extern "C" const char *__crashreporter_info__;

inline constexpr uint32_t LC32_OS_REASON_LIBSYSTEM = 18;
inline constexpr uint32_t LC32_OS_REASON_MAX_VALID_NAMESPACE = 47;
inline constexpr uint64_t LC32_GUEST_CRASH_REASON_CODE = 2;
inline constexpr size_t LC32_OS_REASON_STRING_MAX = 1023;
inline constexpr size_t LC32_GUEST_ERROR_IN_COMPACT_REASON_MAX = 280;
inline constexpr size_t LC32_FULL_CRASH_REPORT_MAX = 2 * 1024 * 1024;
inline constexpr size_t LC32_CRASH_ANNOTATIONS_MAX = 16;
inline constexpr size_t LC32_CRASH_ANNOTATION_BYTES_MAX = 64 * 1024;
inline constexpr uint32_t LC32_CRASH_SYMBOLS_MAX = 256 * 1024;

#pragma GCC visibility push(hidden)

struct GuestAbortMetadata {
    bool valid = false;
    uint32_t reasonNamespace = 0;
    uint64_t reasonCode = 0;
    uint32_t payloadSize = 0;
    uint64_t reasonFlags = 0;
    std::string reason;
};

enum class NativeLifecycleState : uint8_t {
    Uninitialized,
    Running,
    ShuttingDown,
    Destroyed,
};

struct GuestVmEpochParticipant {
    uint64_t epoch = 0;
    size_t activeDepth = 0;
    bool registered = false;
};

struct RetiredMemoryBacking {
    t_memory_backing backing = nullptr;
    uint64_t retirementEpoch = 0;
};

class GuestVmEpochGuard {
public:
    explicit GuestVmEpochGuard(GuestVmEpochParticipant *participant);
    ~GuestVmEpochGuard();
    GuestVmEpochGuard(const GuestVmEpochGuard &) = delete;
    GuestVmEpochGuard &operator=(const GuestVmEpochGuard &) = delete;

private:
    GuestVmEpochParticipant *participant;
};

struct GuestStopRequest {
    int signal = SIGTRAP;
    bool pending = false;
    bool valid = false;
};

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
    gdb_thread_id_t guestThreadId = 0;
    bool forceAbort = false;
};

enum class GuestWorkqueuePumpResult : uint8_t {
    None,
    CooperativeTransition,
    NativeWorkerStarted,
};

struct DebuggerSoftwareBreakpoint {
    u32 address;
    size_t kind;
    std::array<uint8_t, sizeof(uint32_t)> original;
    std::array<uint8_t, sizeof(uint32_t)> trap;
};

struct GuestSoftwareTracepoint {
    u32 address;
    size_t kind;
    std::array<uint8_t, sizeof(uint32_t)> original;
    bool fired;
};

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

struct GuestCrashAnnotation {
    std::string imageName;
    std::string message;
    uint64_t abortCause = 0;
};

extern std::atomic<int> guestStopSignal;
extern std::atomic<int> pendingGuestFatalSignal;
extern std::atomic<bool> reemitPendingGuestStop;
extern std::atomic<bool> guestDebuggerEnabled;
extern std::atomic<bool> debuggerInterruptRequested;
extern std::atomic<bool> debuggerAllStopRequested;
extern std::atomic<bool> debuggerSessionUnwindRequested;
extern std::atomic<void (*)(void)> debuggerStopRunLoopNotifier;
extern std::atomic<bool> nativeShutdownRequested;
extern std::atomic<bool> guestProcessExitRequested;
extern std::atomic<int> guestProcessExitCode;
extern std::atomic<bool> guestCrashTerminationStarted;
extern std::recursive_mutex guestVmMutex;
extern std::mutex guestMappingMutex;
extern thread_local GuestAbortMetadata pendingGuestAbortMetadata;
extern thread_local std::string pendingGuestCrashMessage;
extern std::mutex nativeLifecycleMutex;
extern std::condition_variable nativeLifecycleCondition;
extern NativeLifecycleState nativeLifecycleState;
extern GuestVmEpochParticipant mainGuestVmParticipant;
extern thread_local GuestStopRequest currentGuestStopRequest;
extern std::mutex debuggerMachCallsMutex;
extern std::vector<DebuggerMachCall *> debuggerMachCalls;
extern thread_local bool guestSingleStepping;
extern thread_local bool guestDeferredSVC;
extern std::vector<DebuggerSoftwareBreakpoint> debuggerSoftwareBreakpoints;
extern std::mutex guestSoftwareTracepointsMutex;
extern std::vector<GuestSoftwareTracepoint> guestSoftwareTracepoints;

std::string FormatString(const char *format, va_list arguments);
void SetPendingGuestCrashMessage(const char *format, ...);
void SetPendingGuestCrashMessageIfEmpty(const char *format, ...);
void RegisterGuestVmEpochParticipant(GuestVmEpochParticipant *participant);
void UnregisterGuestVmEpochParticipant(GuestVmEpochParticipant *participant);
void RetireMemoryBacking(t_memory_backing backing);
bool NativeGuestThreadsEnabled();
int NormalizeGuestStopSignal(int signal);
void CommitGuestStopSignal(int signal, bool pending);
void RecordGuestStopSignal(int signal, bool pending);
void ClearCurrentGuestStopRequest();
GuestStopRequest CurrentGuestStopRequestForReason(
    Dynarmic::HaltReason reason);
bool ConsumePendingGuestStop();
void UpdateGuestStopSignalForHalt(Dynarmic::HaltReason reason);
int FindGuestMapping(u32 loadAddress);
void RemoveGuestMapping(u32 loadAddress);
void ResetGuestCallbackExecutor();
void NotifyGuestCallbackExecutorWaiter();
void StopGuestCallbackExecutor();
void GuestCallbackExecutorThreadExited(gdb_thread_id_t threadId);
u32 ServiceGuestCallbackExecutorWait(u32 guestDescriptor);
u32 ServiceGuestCallbackExecutorComplete(u32 identifier);
u32 GuestSigaltstack(u32 guestStack, u32 guestOldStack);
void CloseAllGuestAesFileDescriptors();

extern "C" __attribute__((visibility("default"))) int return_with_carry(
    int result, bool carry);
extern "C" __attribute__((visibility("default"))) int return_with_carry_direct(
    int result, bool carry);
extern "C" LC32_DYNARMIC_HIDDEN int syscallRetCarry(
    long syscall, ...);

DynarmicCallbacks32 *CreateDynarmicCallbacks32(
    khash_t(memory) *memory);
void DestroyDynarmicCallbacks32(DynarmicCallbacks32 *callbacks);
Dynarmic::A32::UserCallbacks *DynarmicCallbacks32UserCallbacks(
    DynarmicCallbacks32 *callbacks);
const std::shared_ptr<DynarmicCP15> &DynarmicCallbacks32CP15(
    DynarmicCallbacks32 *callbacks);
void DynarmicCallbacks32SetPageTable(
    DynarmicCallbacks32 *callbacks, size_t entryCount,
    void **pageTable);
void DynarmicCallbacks32BindJit(
    DynarmicCallbacks32 *callbacks, Dynarmic::A32::Jit *jit,
    DynarmicCpsr *cpsr);
Dynarmic::A32::Jit *DynarmicCallbacks32Jit(
    DynarmicCallbacks32 *callbacks);

struct NativeGuestJit;
struct GuestThreadContext;
struct NativeThreadStateSlot;
struct GuestWorkqueueJob;

bool NativeDebuggerActive();
bool GuestCallbackExecutorDebuggerStepPending();
Dynarmic::HaltReason NativeDebuggerVisibleReason(
    Dynarmic::HaltReason reason);
gdb_thread_id_t NativeDebuggerNormalizeStopOwnerLocked(
    gdb_thread_id_t owner);
void NativeDebuggerTransferStopOwner(
    gdb_thread_id_t previousOwner,
    gdb_thread_id_t replacementOwner);
bool NativeDebuggerRequestStop(
    gdb_thread_id_t owner, Dynarmic::HaltReason reason,
    int forcedSignal = 0, bool forcedPendingSignal = false,
    bool queueWhileStopped = false);
bool NativeDebuggerRepublishPendingStop(gdb_thread_id_t owner);
void NativeDebuggerSetWorkerExecutingLocked(
    NativeGuestJit *runtime, bool executing);
bool NativeDebuggerRunsThreadLocked(gdb_thread_id_t threadId);
bool NativeDebuggerStepsThreadLocked(gdb_thread_id_t threadId);
bool ConsumeNativeDebuggerHostWaitStep(uint64_t commandGeneration);
gdb_thread_id_t ActiveMainDebuggerThread();
bool NativeDebuggerMainContextMayRun();
bool NativeThreadStatePauseHostWaitIfNeeded();
bool NativeThreadStatePauseRequestedForCurrent();
void NativeGuestHostCallEnter();
void NativeGuestHostCallExit();
void NativeGuestCallbackRegisterAccessBegin();
void NativeGuestCallbackRegisterAccessEnd();
bool ConsumeNativeThreadStateHalt(Dynarmic::HaltReason &reason);
void NativeThreadStateOwnerExited(NativeThreadStateSlot &slot);
void ResetNativeThreadStateSlot(NativeThreadStateSlot &slot);
bool NativeDebuggerPauseHostWaitIfNeeded();
void NotifyNativeDebuggerWaiters();
void NotifyNativeDebuggerCoordinator();
gdb_thread_id_t CurrentGuestThreadId();
void SaveGuestContext(context32 &context);
void LoadGuestContext(const context32 &context);
void EnsureGuestThreadRegistry();
GuestThreadContext *FindGuestThread(
    gdb_thread_id_t debuggerId, bool requireAlive = false);
size_t LiveGuestThreadCount();
u64 AllocateGuestThreadSelfId();
GuestThreadContext *NextGuestThread();
mach_port_t AllocateGuestThreadPort();
kern_return_t CopyGuestTaskThreadPorts(
    u32 *guestAddress, mach_msg_type_number_t *count);
kern_return_t CopyGuestThreadState(
    mach_port_t target, thread_state_flavor_t flavor,
    mach_msg_type_number_t capacity, u32 *state,
    mach_msg_type_number_t *count);

template <typename Function>
auto InvokeNativeGuestHostCall(Function &&function)
        -> decltype(function()) {
    NativeGuestHostCallEnter();
    struct ExitScope {
        ~ExitScope() {
            NativeGuestHostCallExit();
        }
    } exitScope;
    return function();
}

template <typename Result, typename Function>
Result debugger_aware_host_wait(
        Function &&function, Result interruptedResult) {
    if (!guestDebuggerEnabled.load(std::memory_order_acquire) &&
            !NativeGuestThreadsEnabled()) {
        return function();
    }

    DebuggerMachCall call;
    call.thread = pthread_mach_thread_np(pthread_self());
    call.guestThreadId = NativeGuestThreadsEnabled()
        ? CurrentGuestThreadId()
        : 0;
    call.forceAbort = true;
    call.phase.store(
        DebuggerMachCallPhase::Arming,
        std::memory_order_release);
    {
        std::lock_guard<std::mutex> lock(debuggerMachCallsMutex);
        debuggerMachCalls.push_back(&call);
    }
    const auto finishCall = [&call] {
        call.phase.store(
            DebuggerMachCallPhase::Completing,
            std::memory_order_release);
        {
            std::lock_guard<std::mutex> lock(debuggerMachCallsMutex);
            debuggerMachCalls.erase(std::remove(
                debuggerMachCalls.begin(), debuggerMachCalls.end(),
                &call), debuggerMachCalls.end());
        }
        call.phase.store(
            DebuggerMachCallPhase::Idle,
            std::memory_order_release);
    };
    const auto stopRequested = [&call] {
        return call.interruptRequested.load(std::memory_order_acquire) ||
            NativeThreadStatePauseRequestedForCurrent() ||
            debuggerInterruptRequested.load(std::memory_order_acquire) ||
            debuggerAllStopRequested.load(std::memory_order_acquire) ||
            nativeShutdownRequested.load(std::memory_order_acquire) ||
            guestProcessExitRequested.load(std::memory_order_acquire);
    };

    if (stopRequested()) {
        finishCall();
        (void)NativeThreadStatePauseHostWaitIfNeeded();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
        return interruptedResult;
    }
    call.phase.store(
        DebuggerMachCallPhase::InCall,
        std::memory_order_release);
    if (stopRequested()) {
        finishCall();
        (void)NativeThreadStatePauseHostWaitIfNeeded();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
        return interruptedResult;
    }

    Result result = function();
    finishCall();
    if (stopRequested()) {
        (void)NativeThreadStatePauseHostWaitIfNeeded();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
    }
    return result;
}

std::vector<GuestImageSnapshot> SnapshotGuestImages();
std::vector<GuestCrashAnnotation> CollectGuestCrashAnnotations(
    const std::vector<GuestImageSnapshot> &images);
void symbolicate_call_stack(
    symbolicated_call *callStack, int callStackLen,
    const std::vector<GuestImageSnapshot> &images);
int HostProtectionForGuestPermissions(int permissions);
void *GuestPageTablePointer(
    u64 guestPageAddress, const t_memory_page page);
char *get_memory_page_with_permissions(
    u64 vaddr, int requiredPermissions);
bool GuestAddressRangeIsValid32(u64 address, u64 size);
kern_return_t CopyGuestVmMemory(
    u32 source, u32 destination, u32 size);
bool GuestProtectionIsValid(int protection);
bool guest_memory_range_has_permissions(
    u64 address, size_t size, int requiredPermissions);
bool read_guest_memory_with_permissions(
    u64 address, void *destination, size_t size,
    int requiredPermissions);
std::string CopyGuestCStringForCrash(
    u64 guestAddress, size_t maximumLength);
bool write_guest_memory_with_permissions(
    u64 address, const void *source, size_t size,
    int requiredPermissions);
int guest_kevent(
    int kqueueDescriptor, u32 guestChanges, int changeCount,
    u32 guestEvents, int eventCount, u32 guestTimeout);

#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
#ifndef LC32_GUEST_MEMORY_WATCH_FORCE_CALLBACKS
#define LC32_GUEST_MEMORY_WATCH_FORCE_CALLBACKS 1
#endif
inline constexpr u64 guestMemoryWatchAddress =
    static_cast<u64>(LC32_GUEST_MEMORY_WATCH_ADDRESS);
inline constexpr bool guestMemoryWatchForceCallbacks =
    LC32_GUEST_MEMORY_WATCH_FORCE_CALLBACKS != 0;
static_assert(guestMemoryWatchAddress <=
        UINT32_MAX - sizeof(u32) + 1,
    "LC32_GUEST_MEMORY_WATCH_ADDRESS must name a 32-bit guest word");
void ConfigureGuestMemoryWatch();
bool GuestMemoryWatchOverlaps(u64 address, size_t size);
bool GuestMemoryWatchContainsPage(u64 guestPageAddress);
bool SnapshotGuestMemoryWatchLocked(u32 *value);
void LogGuestMemoryWatchConsistency(const char *reason);
void LogGuestMemoryWatchConsistencyLocked(const char *reason);
void LogGuestMemoryWatchWriteLocked(
    const char *operation, u64 address, size_t size,
    bool hadOldValue, u32 oldValue);
#endif

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

#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    u32 oldWatchedValue = 0;
    const bool hadOldWatchedValue =
        GuestMemoryWatchOverlaps(address, sizeof(T)) &&
        SnapshotGuestMemoryWatchLocked(&oldWatchedValue);
#endif
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
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    LogGuestMemoryWatchWriteLocked(
        "exclusive", address, sizeof(T),
        hadOldWatchedValue, oldWatchedValue);
#endif
    return ExclusiveGuestWriteResult::Committed;
}

GuestWorkqueuePumpResult PumpGuestWorkqueue();
bool HandleGuestWorkqueueTransition();
bool GuestWorkqueueTransitionPending();
bool HandleGuestThreadTransition();
bool GuestThreadTransitionPending();
bool HandleGuestContextTransition();
bool GuestContextTransitionPending();
bool GuestThreadCanYieldBeforeBlocking();
bool GuestThreadYieldBeforeBlocking();
void GuestThreadRequestRotation();
bool NativeGuestThreadIsCurrent();
bool NativeGuestWorkqueueIsCurrent();
void NativeGuestWorkqueueHostBlockEnter();
void NativeGuestWorkqueueHostBlockExit();
bool GuestWorkqueueActiveForCurrentThread();
void InvalidateAllGuestJits(u32 address, size_t size);
extern "C" bool ConsumeGuestSoftwareTracepoint(
    u32 pc, Dynarmic::A32::Jit *cpu);
extern "C" int ValidateGuestMunmapRange(u64 address, u64 size);
void HaltAllGuestJits(Dynarmic::HaltReason reason);
void ClearAllGuestJitHalts(Dynarmic::HaltReason reason);
void InterruptDebuggerMachCalls();
void InterruptNativeThreadStateHostCalls(gdb_thread_id_t threadId);
void DrainDebuggerMachCalls();
void ScheduleMainGuestWorkqueueTransition();
void DestroyNativeGuestJit(NativeGuestJit *runtime);
void JoinNativeGuestJit(NativeGuestJit *runtime);
bool StartNativeGuestWorkqueueWorker(const GuestWorkqueueJob &job);

u32 GuestBsdthreadCreate(
    u32 function, u32 argument, u32 stack, u32 pthread, u32 flags);
u32 GuestBsdthreadTerminate(
    u32 freeAddress, u32 freeSize, mach_port_t threadPort,
    mach_port_t joinSemaphore);
u64 GuestCurrentThreadSelfId();
mach_port_t GuestCurrentSyntheticThreadPort();
int GuestThreadSigmask(int how, u32 guestSet, u32 guestOldSet);
u32 GuestPsynchMutexWait(
    u32 mutex, u32 mgen, u32 ugen, u32 flags);
u32 GuestPsynchMutexDrop(
    u32 mutex, u32 mgen, u32 ugen, u32 flags);
u32 GuestPsynchConditionWait(
    u32 condition, u32 conditionSequence,
    u32 conditionSSequence, u32 mutex,
    int64_t timeoutSeconds, u32 timeoutNanoseconds);
u32 GuestPsynchConditionSignal(
    u32 condition, u32 conditionSequence,
    u32 conditionSSequence, u32 conditionUOrDifference,
    mach_port_t targetThread, bool broadcast);
u32 GuestPsynchRwWait(
    u32 rwlock, u32 lgen, u32 rwSequence, bool write);
u32 GuestPsynchRwUnlock(
    u32 rwlock, u32 lgen, u32 ugen, u32 rwSequence);
u32 GuestUlockWait(
    u32 operation, u32 address, u64 value, u32 timeout);
u32 GuestUlockWake(
    u32 operation, u32 address, u64 wakeValue);

inline constexpr size_t MaxNativeGuestProcessors = 64;

enum class GuestThreadWaitKind : uint8_t {
    None,
    Mutex,
    Condition,
    Rwlock,
    Ulock,
};

enum class GuestRwlockWaitType : uint8_t {
    None,
    Read,
    Write,
};

inline constexpr u32 GuestPsynchCountIncrement = 0x100u;
inline constexpr u32 GuestPsynchCountMask = 0xffffff00u;
inline constexpr u32 GuestPsynchBitMask = 0xffu;
inline constexpr u32 GuestPsynchRwKernelBit = 0x01u;
inline constexpr u32 GuestPsynchRwExclusiveBit = 0x02u;
inline constexpr u32 GuestPsynchRwWriterBit = 0x04u;
inline constexpr u32 GuestPsynchRwSequenceSavedWriterBit = 0x04u;
inline constexpr u32 GuestPsynchRwOverlapBit = 0x40u;
inline constexpr u32 GuestPthreadPolicyFlagsMask = 0x1c0u;
inline constexpr u32 GuestPthreadMutexPolicyFirstFit = 0x080u;

inline bool GuestPsynchMutexIsFirstFit(u32 flags) {
    return (flags & GuestPthreadPolicyFlagsMask) ==
        GuestPthreadMutexPolicyFirstFit;
}

inline bool GuestPsynchSequenceLower(u32 lhs, u32 rhs) {
    lhs &= GuestPsynchCountMask;
    rhs &= GuestPsynchCountMask;
    if (lhs < rhs) {
        return rhs - lhs < GuestPsynchCountMask / 2;
    }
    return lhs - rhs > GuestPsynchCountMask / 2;
}

inline bool GuestPsynchSequenceLowerOrEqual(u32 lhs, u32 rhs) {
    return (lhs & GuestPsynchCountMask) ==
            (rhs & GuestPsynchCountMask) ||
        GuestPsynchSequenceLower(lhs, rhs);
}

inline size_t GuestPsynchSequenceDistance(u32 newer, u32 older) {
    return static_cast<size_t>(
        (((newer & GuestPsynchCountMask) -
          (older & GuestPsynchCountMask)) &
         GuestPsynchCountMask) /
        GuestPsynchCountIncrement);
}

struct NativeThreadStateSlot {
    std::mutex mutex;
    std::condition_variable condition;
    std::mutex registerAccessMutex;
    uint64_t nextGeneration = 0;
    uint64_t requestedGeneration = 0;
    uint64_t acknowledgedGeneration = 0;
    uint64_t releasedGeneration = 0;
    context32 snapshot = {};
    bool snapshotValid = false;
    bool ownerExited = false;
    size_t hostCallDepth = 0;
    size_t hostCallQuiescenceDepth = 0;
    size_t guestCallbackDepth = 0;
    bool hostRegistersQuiescent = false;
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
    bool debuggerHostCallQuiescent = false;
    bool hostThreadCreated = false;
    bool exited = false;
    bool workqueue = false;
    std::atomic<bool> workqueueHostBlocked{false};
    std::atomic<bool> workqueueCompensationPending{false};
    u32 workqueuePriority = 0;
    size_t threadStateUsers = 0;
    NativeThreadStateSlot threadState;
    mach_port_t joinSemaphore = MACH_PORT_NULL;
};

struct GuestThreadContext {
    gdb_thread_id_t debuggerId = 0;
    u64 threadSelfId = 0;
    u32 pthreadAddress = 0;
    mach_port_t threadPort = MACH_PORT_NULL;
    u32 allocationAddress = 0;
    u32 allocationSize = 0;
    u32 retirementFreeAddress = 0;
    u32 retirementFreeSize = 0;
    context32 saved = {};
    u32 signalMask = 0;
    u32 alternateSignalStackPointer = 0;
    u32 alternateSignalStackSize = 0;
    int32_t alternateSignalStackFlags = SS_DISABLE;
    GuestThreadWaitKind waitKind = GuestThreadWaitKind::None;
    u32 waitAddress = 0;
    u32 wakeResult = 0;
    u64 waitSequence = 0;
    u32 mutexSequence = 0;
    u32 conditionSequence = 0;
    GuestRwlockWaitType rwlockWaitType = GuestRwlockWaitType::None;
    u32 rwlockSequence = 0;
    bool savedValid = false;
    bool alive = false;
    bool runnable = false;
    bool workqueue = false;
    NativeGuestJit *nativeJit = nullptr;
};

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
    NativeDebuggerRunState state = NativeDebuggerRunState::Disabled;
    NativeDebuggerResumeMode resumeMode =
        NativeDebuggerResumeMode::ContinueAll;
    gdb_thread_id_t stopOwner = 1;
    gdb_thread_id_t stepThread = 1;
    Dynarmic::HaltReason stopReason = LC32HaltReasonTrap;
    int stopSignal = SIGTRAP;
    uint64_t generation = 0;
    size_t executingWorkers = 0;
    bool mainExecuting = false;
    bool resumeStarting = false;
    bool pendingInterrupt = false;
};

struct GuestMutexPrepost {
    u32 address;
    u32 sequence;
    size_t count;
};

struct GuestConditionPrepost {
    u32 address;
    u32 throughSequence;
    size_t count;
};

struct NativeGuestWaiter {
    GuestThreadWaitKind kind = GuestThreadWaitKind::None;
    u32 address = 0;
    uint8_t ulockOpcode = 0;
    GuestRwlockWaitType rwlockWaitType = GuestRwlockWaitType::None;
    u32 rwlockSequence = 0;
    u32 mutexSequence = 0;
    u32 conditionSequence = 0;
    mach_port_t threadPort = MACH_PORT_NULL;
    u32 wakeResult = 0;
    u64 sequence = 0;
    bool signaled = false;
    std::condition_variable condition;
};

struct NativeGuestRwlockUnlock {
    u32 address = 0;
    u32 lgen = 0;
    u32 rwSequence = 0;
    size_t expectedWaiters = 0;
};

struct NativeGuestRwlockOverlap {
    u32 address = 0;
    u32 lastSequence = 0;
    u32 nextSequence = 0;
};

struct GuestWorkqueueKevent {
    guest_kevent_qos_s event;
    bool enabled;
    bool triggered;
};

struct GuestWorkqueueRequest {
    int remaining;
    u32 priority;
};

inline constexpr u32 GuestWorkqueueGuardSize = DYN_PAGE_SIZE;
inline constexpr u32 GuestWorkqueueStackSize = 0x80000;
inline constexpr size_t GuestWorkqueueEventCapacity = 16;
inline constexpr size_t GuestWorkqueueMessageCapacity = 32 * 1024;

struct GuestWorkqueueDelivery {
    guest_kevent_qos_s event = {};
    std::vector<uint8_t> message;
    bool eventManager = false;
};

struct GuestWorkqueueJob {
    GuestWorkqueueDelivery delivery;
    u32 priority = 0;
    bool hasDelivery = false;
};

inline constexpr size_t MaxNativeGuestWorkqueueWorkers = 4;

struct GuestWorkqueuePendingUpcall {
    u32 eventList;
    u32 eventCount;
    u32 stackPointer;
    u32 flags;
    bool valid;
};

class NativeGuestWorkqueueHostBlockScope {
public:
    NativeGuestWorkqueueHostBlockScope() = default;
    NativeGuestWorkqueueHostBlockScope(
        const NativeGuestWorkqueueHostBlockScope &) = delete;
    NativeGuestWorkqueueHostBlockScope &operator=(
        const NativeGuestWorkqueueHostBlockScope &) = delete;

    void Enter() {
        if (active || !NativeGuestWorkqueueIsCurrent()) {
            return;
        }
        active = true;
        NativeGuestWorkqueueHostBlockEnter();
    }

    ~NativeGuestWorkqueueHostBlockScope() {
        if (active) {
            NativeGuestWorkqueueHostBlockExit();
        }
    }

private:
    bool active = false;
};

extern NativeThreadStateSlot mainNativeThreadState;
extern std::recursive_mutex guestThreadMutex;
extern std::deque<GuestThreadContext> guestThreads;
extern gdb_thread_id_t guestCurrentThreadId;
extern gdb_thread_id_t guestNextDebuggerThreadId;
extern u64 guestNextThreadSelfId;
extern bool guestThreadRegistryInitialized;
extern bool guestThreadRotationRequested;
extern bool guestThreadCurrentRetiring;
extern std::atomic<u64> guestNextWaitSequence;
extern uint64_t guestProcessorIdsInUse;
extern thread_local gdb_thread_id_t nativeGuestThreadId;
extern thread_local bool nativeGuestThreadRetiring;
extern thread_local NativeGuestJit *nativeGuestRuntime;
extern thread_local size_t nativeGuestWorkqueueHostBlockDepth;
extern thread_local bool nativeDebuggerHostWaitStep;
extern thread_local uint64_t nativeDebuggerHostWaitStepGeneration;
extern thread_local size_t nativeDebuggerMainCallbackStopDepth;
extern thread_local gdb_thread_id_t cooperativeDebuggerResumeThread;
extern std::mutex nativeGuestJitMutex;
extern std::condition_variable nativeGuestJitCondition;
extern std::vector<NativeGuestJit *> nativeGuestJits;
extern NativeDebuggerCoordinator nativeDebugger;
extern std::mutex guestPsynchPrepostMutex;
extern std::vector<GuestMutexPrepost> guestMutexPreposts;
extern std::vector<GuestConditionPrepost> guestConditionPreposts;
extern std::mutex nativeGuestWaitMutex;
extern std::vector<std::shared_ptr<NativeGuestWaiter>> nativeGuestWaiters;
extern std::vector<NativeGuestRwlockUnlock> nativeGuestRwlockUnlocks;
extern std::vector<NativeGuestRwlockOverlap> nativeGuestRwlockOverlaps;

extern __attribute__((visibility("default")))
    u32 guest_bsdthread_thread_start;
extern __attribute__((visibility("default")))
    u32 guest_bsdthread_wqthread_start;
extern __attribute__((visibility("default")))
    int guest_bsdthread_pthread_size;
extern __attribute__((visibility("default")))
    bool guest_workqueue_opened;
extern __attribute__((visibility("default")))
    u32 guest_bsdthread_tsd_offset;
extern std::vector<GuestWorkqueueKevent> guestWorkqueueKevents;
extern std::deque<GuestWorkqueueRequest> guestWorkqueueRequests;
extern std::recursive_mutex guestWorkqueueMutex;
extern u32 guestWorkqueueEventManagerPriority;
extern bool guestWorkqueueUpcallActive;
extern bool guestWorkqueueRestoreRequested;
extern thread_local bool guestWorkqueueOverlayCurrent;

extern u32 guestWorkqueueAllocation;
extern u32 guestWorkqueueAllocationSize;
extern u32 guestWorkqueuePthread;
extern u32 guestWorkqueueStackBottom;
extern mach_port_t guestWorkqueueThreadPort;
extern bool guestWorkqueueWorkerInitialized;
extern std::mutex guestNativeWorkqueuePumpMutex;
extern std::deque<GuestWorkqueueJob> guestNativeWorkqueuePendingJobs;
extern GuestWorkqueuePendingUpcall guestWorkqueuePendingUpcall;
extern context32 guestWorkqueueWaitingContext;
extern bool guestWorkqueueWaitingContextValid;
extern gdb_thread_id_t guestWorkqueueWaitingThreadId;
extern u64 guestWorkqueueThreadSelfId;
extern u32 guestWorkqueueSignalMask;

u32 GuestWorkqueueQosClass(u32 priority);

bool ParkCurrentGuestThread(
    GuestThreadWaitKind kind, u32 address, u32 wakeResult,
    GuestRwlockWaitType rwlockWaitType = GuestRwlockWaitType::None,
    u32 rwlockSequence = 0, u32 conditionSequence = 0,
    u32 mutexSequence = 0);
size_t WakeGuestThreads(
    GuestThreadWaitKind kind, u32 address, bool wakeAll,
    mach_port_t targetThread = MACH_PORT_NULL);
size_t WakeGuestMutexThread(
    u32 address, u32 targetSequence, bool firstFit);
size_t WakeGuestConditionThreads(
    u32 address, u32 throughSequence, bool wakeAll,
    mach_port_t targetThread = MACH_PORT_NULL);
u32 GrantCooperativeGuestRwlockThreads(
    u32 address, size_t *wokenCount);
void RecordGuestMutexPrepost(u32 address, u32 sequence);
bool ConsumeGuestMutexPrepost(
    u32 address, u32 sequence, bool firstFit);
void RecordGuestConditionSignalPrepost(
    u32 address, u32 throughSequence);
void RecordGuestConditionBroadcastPrepost(
    u32 address, u32 throughSequence, size_t count);
bool ConsumeGuestConditionPrepost(
    u32 address, u32 conditionSequence);

bool EnsureGuestWorkqueueWorker();
bool PrepareGuestWorkqueueUpcall(
    const GuestWorkqueueDelivery *delivery, u32 priority);
bool NextGuestWorkqueueEvent(GuestWorkqueueDelivery &delivery);

#pragma GCC visibility pop
