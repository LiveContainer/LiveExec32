#include "dynarmic_internal.h"

std::atomic<int> guestStopSignal{SIGTRAP};
std::atomic<int> pendingGuestFatalSignal{0};
std::atomic<bool> reemitPendingGuestStop{false};
std::atomic<bool> guestDebuggerEnabled{false};
std::atomic<bool> debuggerInterruptRequested{false};
std::atomic<bool> debuggerAllStopRequested{false};
/*
 * D/EOF can be handled inside a reverse callback while the outer protocol
 * frame is suspended below UIApplicationMain.  This one-shot condition asks
 * the UIKit shim to return to the outer JIT so that frame can observe the
 * nested protocol's terminal marker and close its sole socket reader.
 */
std::atomic<bool> debuggerSessionUnwindRequested{false};
/*
 * Registered by the host UIKit shim while the guest main thread is parked
 * inside the host UIApplicationMain run loop. When an all-stop is requested
 * (worker crash, ^C, breakpoint) the run loop's blocking mach_msg is not one
 * of the guest SVC waits tracked by debuggerMachCalls, so the coordinator
 * cannot abort it. The notifier wakes the main run loop; its block unwinds
 * the run loop via an Objective-C exception caught by the shim, returning
 * control to the guest JIT so the stop reply can be delivered.
 */
std::atomic<void (*)(void)> debuggerStopRunLoopNotifier{nullptr};
std::atomic<bool> nativeShutdownRequested{false};
std::atomic<bool> guestProcessExitRequested{false};
std::atomic<int> guestProcessExitCode{0};
std::atomic<bool> guestCrashTerminationStarted{false};
std::recursive_mutex guestVmMutex;
std::mutex guestMappingMutex;
thread_local GuestAbortMetadata pendingGuestAbortMetadata;
thread_local std::string pendingGuestCrashMessage;

std::string FormatString(const char *format, va_list arguments) {
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

void SetPendingGuestCrashMessage(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    pendingGuestCrashMessage = FormatString(format, arguments);
    va_end(arguments);
}

void SetPendingGuestCrashMessageIfEmpty(const char *format, ...) {
    if (!pendingGuestCrashMessage.empty()) {
        return;
    }
    va_list arguments;
    va_start(arguments, format);
    pendingGuestCrashMessage = FormatString(format, arguments);
    va_end(arguments);
}

std::mutex nativeLifecycleMutex;
std::condition_variable nativeLifecycleCondition;
NativeLifecycleState nativeLifecycleState =
    NativeLifecycleState::Uninitialized;

static std::mutex guestVmEpochMutex;
static uint64_t guestVmEpoch = 1;
GuestVmEpochParticipant mainGuestVmParticipant;
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

void RegisterGuestVmEpochParticipant(
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

void UnregisterGuestVmEpochParticipant(
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

void RetireMemoryBacking(
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

GuestVmEpochGuard::GuestVmEpochGuard(
        GuestVmEpochParticipant *participant)
    : participant(participant) {
    if (participant == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(guestVmEpochMutex);
    assert(participant->registered);
    if (participant->activeDepth++ == 0) {
        participant->epoch = guestVmEpoch;
    }
}

GuestVmEpochGuard::~GuestVmEpochGuard() {
    if (participant == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(guestVmEpochMutex);
    assert(participant->activeDepth != 0);
    if (--participant->activeDepth == 0) {
        ReclaimRetiredMemoryBackingsLocked();
    }
}

/*
 * A native guest thread must not publish process-wide signal state until it
 * wins the all-stop coordinator. Otherwise two simultaneous faults can make
 * LLDB report one thread with another thread's signal (and a losing SIGTRAP
 * can incorrectly clear a winning fatal signal's replay state).
 */
thread_local GuestStopRequest currentGuestStopRequest;

static bool NativeGuestThreadsRequested() {
    static const bool requested = [] {
        const char *value = getenv("NATIVE_GUEST_THREADS");
        return value != nullptr && value[0] != '\0' &&
            strcmp(value, "0") != 0;
    }();
    return requested;
}

bool NativeGuestThreadsEnabled() {
    return NativeGuestThreadsRequested();
}

/*
 * Compile-time diagnostic for tracking corruption of one guest word.
 * Dynarmic's
 * normal page-table path intentionally bypasses MemoryWrite* callbacks, so a
 * watched page must remain unpublished there for the duration of the run.
 * The authoritative khash mapping remains present and services callbacks.
 */
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
void ConfigureGuestMemoryWatch() {
    fprintf(stderr,
        "LC32: watching guest writes at 0x%08llx-0x%08llx "
        "(%s page-table callbacks)\n",
        guestMemoryWatchAddress,
        guestMemoryWatchAddress + sizeof(u32),
        guestMemoryWatchForceCallbacks ? "forcing" : "not forcing");
}

bool GuestMemoryWatchOverlaps(u64 address, size_t size) {
    return size != 0 &&
        address < guestMemoryWatchAddress + sizeof(u32) &&
        guestMemoryWatchAddress < address + size;
}

bool GuestMemoryWatchContainsPage(u64 guestPageAddress) {
    if (!guestMemoryWatchForceCallbacks) {
        return false;
    }
    const u64 watchedStart =
        guestMemoryWatchAddress & ~u64(DYN_PAGE_MASK);
    const u64 watchedEnd =
        (guestMemoryWatchAddress + sizeof(u32) - 1) &
        ~u64(DYN_PAGE_MASK);
    const u64 page = guestPageAddress & ~u64(DYN_PAGE_MASK);
    return page == watchedStart || page == watchedEnd;
}
#endif

std::mutex debuggerMachCallsMutex;
std::vector<DebuggerMachCall *> debuggerMachCalls;

namespace {

enum class GuestCallbackExecutorState : uint8_t {
    Unavailable,
    Starting,
    Ready,
    Failed,
    Stopping,
};

struct GuestCallbackJob {
    LC32GuestBlockCallbackDescriptor descriptor = {};
    bool delivered = false;
    bool completed = false;
    bool canceled = false;
    std::condition_variable condition;
};

static std::mutex guestCallbackExecutorMutex;
static std::condition_variable guestCallbackExecutorCondition;
static std::deque<std::shared_ptr<GuestCallbackJob>> guestCallbackJobs;
static std::shared_ptr<GuestCallbackJob> guestCallbackActiveJob;
static GuestCallbackExecutorState guestCallbackExecutorState =
    GuestCallbackExecutorState::Unavailable;
static gdb_thread_id_t guestCallbackExecutorThreadId;
static uint32_t guestCallbackNextIdentifier = 1;

static void CancelQueuedGuestCallbacksLocked() {
    for(const std::shared_ptr<GuestCallbackJob> &job :
            guestCallbackJobs) {
        job->canceled = true;
        job->condition.notify_all();
    }
    guestCallbackJobs.clear();
}

} // anonymous namespace

void ResetGuestCallbackExecutor() {
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    CancelQueuedGuestCallbacksLocked();
    if(guestCallbackActiveJob) {
        guestCallbackActiveJob->canceled = true;
        guestCallbackActiveJob->condition.notify_all();
        guestCallbackActiveJob.reset();
    }
    guestCallbackExecutorState =
        GuestCallbackExecutorState::Unavailable;
    guestCallbackExecutorThreadId = 0;
    guestCallbackNextIdentifier = 1;
    guestCallbackExecutorCondition.notify_all();
}

void NotifyGuestCallbackExecutorWaiter() {
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    guestCallbackExecutorCondition.notify_all();
}

void StopGuestCallbackExecutor() {
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(guestCallbackExecutorState ==
            GuestCallbackExecutorState::Unavailable) {
        return;
    }
    guestCallbackExecutorState =
        GuestCallbackExecutorState::Stopping;
    CancelQueuedGuestCallbacksLocked();
    guestCallbackExecutorCondition.notify_all();
}

void GuestCallbackExecutorThreadExited(
        gdb_thread_id_t threadId) {
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(threadId != guestCallbackExecutorThreadId) return;

    const bool expected = guestCallbackExecutorState ==
        GuestCallbackExecutorState::Stopping;
    guestCallbackExecutorThreadId = 0;
    if(guestCallbackActiveJob) {
        guestCallbackActiveJob->canceled = true;
        guestCallbackActiveJob->condition.notify_all();
        guestCallbackActiveJob.reset();
    }
    CancelQueuedGuestCallbacksLocked();
    guestCallbackExecutorState = expected
        ? GuestCallbackExecutorState::Stopping
        : GuestCallbackExecutorState::Failed;
    guestCallbackExecutorCondition.notify_all();
    if(!expected &&
            !nativeShutdownRequested.load(
                std::memory_order_acquire) &&
            !guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        fprintf(stderr,
            "LC32: guest callback executor thread exited unexpectedly\n");
    }
}

static bool SubmitGuestCallback(
        const LC32GuestBlockCallbackDescriptor &input) {
    auto job = std::make_shared<GuestCallbackJob>();
    job->descriptor = input;

    std::unique_lock<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(guestCallbackExecutorState ==
            GuestCallbackExecutorState::Starting) {
        const bool ready = guestCallbackExecutorCondition.wait_for(
            lock, std::chrono::seconds(5), [] {
                return guestCallbackExecutorState !=
                    GuestCallbackExecutorState::Starting;
            });
        if(!ready) {
            fprintf(stderr,
                "LC32: timed out starting guest callback executor\n");
            return false;
        }
    }
    if(guestCallbackExecutorState !=
            GuestCallbackExecutorState::Ready ||
            nativeShutdownRequested.load(
                std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        return false;
    }

    uint32_t identifier = guestCallbackNextIdentifier++;
    if(identifier == 0) identifier = guestCallbackNextIdentifier++;
    job->descriptor.identifier = identifier;
    guestCallbackJobs.push_back(job);
    guestCallbackExecutorCondition.notify_one();
    job->condition.wait(lock, [&] {
        return job->completed || job->canceled;
    });
    /* A delivered release may have run even if its worker exits before the
     * completion SVC. Treat that as consumed to prefer a teardown-only leak
     * over issuing _Block_release twice. Invocation callers still require an
     * explicit completion acknowledgement. */
    return job->completed ||
        (job->delivered &&
         job->descriptor.kind ==
             LC32GuestBlockCallbackKindRelease);
}

u32 ServiceGuestCallbackExecutorWait(u32 guestDescriptor) {
    if(!guestDescriptor || !NativeGuestThreadIsCurrent() ||
            CurrentGuestThreadId() <= 1) {
        return LC32GuestBlockCallbackWaitResultStop;
    }

    std::unique_lock<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(guestCallbackExecutorState ==
            GuestCallbackExecutorState::Starting) {
        guestCallbackExecutorThreadId = CurrentGuestThreadId();
        guestCallbackExecutorState =
            GuestCallbackExecutorState::Ready;
        guestCallbackExecutorCondition.notify_all();
    } else if(guestCallbackExecutorState !=
                  GuestCallbackExecutorState::Ready ||
              guestCallbackExecutorThreadId !=
                  CurrentGuestThreadId()) {
        return LC32GuestBlockCallbackWaitResultStop;
    }

    while(guestCallbackJobs.empty() &&
            guestCallbackExecutorState ==
                GuestCallbackExecutorState::Ready &&
            !nativeShutdownRequested.load(
                std::memory_order_acquire) &&
            !guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        guestCallbackExecutorCondition.wait(lock, [] {
            return !guestCallbackJobs.empty() ||
                guestCallbackExecutorState !=
                    GuestCallbackExecutorState::Ready ||
                NativeThreadStatePauseRequestedForCurrent() ||
                debuggerAllStopRequested.load(
                    std::memory_order_acquire) ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire) ||
                guestProcessExitRequested.load(
                    std::memory_order_acquire);
        });
        if(!guestCallbackJobs.empty()) break;

        lock.unlock();
        (void)NativeThreadStatePauseHostWaitIfNeeded();
        const bool paused =
            NativeDebuggerPauseHostWaitIfNeeded();
        lock.lock();
        if(paused && GuestCallbackExecutorDebuggerStepPending()) {
            return LC32GuestBlockCallbackWaitResultRetry;
        }
    }

    if(guestCallbackExecutorState !=
            GuestCallbackExecutorState::Ready ||
            nativeShutdownRequested.load(
                std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        return LC32GuestBlockCallbackWaitResultStop;
    }
    if(guestCallbackJobs.empty()) {
        return LC32GuestBlockCallbackWaitResultRetry;
    }

    std::shared_ptr<GuestCallbackJob> job =
        guestCallbackJobs.front();
    guestCallbackJobs.pop_front();
    guestCallbackActiveJob = job;
    const LC32GuestBlockCallbackDescriptor descriptor =
        job->descriptor;
    lock.unlock();

    if(Dynarmic_mem_1write(
            guestDescriptor, sizeof(descriptor),
            reinterpret_cast<char *>(
                const_cast<LC32GuestBlockCallbackDescriptor *>(
                    &descriptor))) != 0) {
        lock.lock();
        job->canceled = true;
        job->condition.notify_all();
        guestCallbackActiveJob.reset();
        return LC32GuestBlockCallbackWaitResultRetry;
    }
    lock.lock();
    job->delivered = true;
    return LC32GuestBlockCallbackWaitResultJob;
}

u32 ServiceGuestCallbackExecutorComplete(u32 identifier) {
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(guestCallbackExecutorThreadId !=
            CurrentGuestThreadId() ||
            !guestCallbackActiveJob ||
            guestCallbackActiveJob->descriptor.identifier !=
                identifier) {
        return 0;
    }

    guestCallbackActiveJob->completed = true;
    guestCallbackActiveJob->condition.notify_all();
    guestCallbackActiveJob.reset();
    return guestCallbackExecutorState ==
               GuestCallbackExecutorState::Ready &&
           !nativeShutdownRequested.load(
               std::memory_order_acquire) &&
           !guestProcessExitRequested.load(
               std::memory_order_acquire);
}
bool Dynarmic_guest_thread_is_registered() {
    return threadHandle.jit != nullptr && threadHandle.cb != nullptr;
}

bool Dynarmic_submit_guest_block_callback(
        const LC32GuestBlockCallbackDescriptor *descriptor) {
    if(descriptor == nullptr ||
            descriptor->kind !=
                LC32GuestBlockCallbackKindInvoke ||
            descriptor->argumentCount >
                LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS ||
            Dynarmic_guest_thread_is_registered()) {
        return false;
    }
    return SubmitGuestCallback(*descriptor);
}

bool Dynarmic_submit_guest_function_callback(
        const LC32GuestBlockCallbackDescriptor *descriptor) {
    if(descriptor == nullptr ||
            descriptor->kind !=
                LC32GuestBlockCallbackKindFunction ||
            descriptor->resultKind !=
                LC32GuestBlockValueVoid ||
            descriptor->argumentCount == 0 ||
            descriptor->argumentCount >
                LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS ||
            Dynarmic_guest_thread_is_registered()) {
        return false;
    }
    return SubmitGuestCallback(*descriptor);
}

bool Dynarmic_submit_guest_block_release(u32 guestBlock) {
    if(!guestBlock || Dynarmic_guest_thread_is_registered()) {
        return false;
    }
    LC32GuestBlockCallbackDescriptor descriptor = {};
    descriptor.kind = LC32GuestBlockCallbackKindRelease;
    descriptor.guestBlock = guestBlock;
    return SubmitGuestCallback(descriptor);
}

u32 LC32GuestCallbackExecutorSupported(
        u32, u32, u32) {
    if(!NativeGuestThreadsEnabled() ||
            sharedHandle.guest_LC32InvokeGuestC == 0) {
        return 0;
    }
    {
        std::lock_guard<std::mutex> lifecycleLock(
            nativeLifecycleMutex);
        if(nativeLifecycleState !=
                NativeLifecycleState::Running ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire)) {
            return 0;
        }
    }
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(guestCallbackExecutorState !=
            GuestCallbackExecutorState::Unavailable) {
        return 0;
    }
    guestCallbackExecutorState =
        GuestCallbackExecutorState::Starting;
    return 1;
}

u32 LC32GuestCallbackExecutorCreationResult(
        u32 error, u32, u32) {
    std::lock_guard<std::mutex> lock(
        guestCallbackExecutorMutex);
    if(guestCallbackExecutorState !=
            GuestCallbackExecutorState::Starting) {
        return 0;
    }
    if(error != 0) {
        guestCallbackExecutorState =
            GuestCallbackExecutorState::Failed;
        fprintf(stderr,
            "LC32: guest callback executor pthread_create failed: %u (%s)\n",
            error, strerror(static_cast<int>(error)));
    }
    guestCallbackExecutorCondition.notify_all();
    return error == 0;
}

thread_local bool guestSingleStepping;
thread_local bool guestDeferredSVC;
std::vector<DebuggerSoftwareBreakpoint> debuggerSoftwareBreakpoints;
std::mutex guestSoftwareTracepointsMutex;
std::vector<GuestSoftwareTracepoint> guestSoftwareTracepoints;

int NormalizeGuestStopSignal(int signal) {
    if (signal <= 0 || signal >= NSIG) {
        return SIGABRT;
    }
    return signal;
}

void CommitGuestStopSignal(int signal, bool pending) {
    signal = NormalizeGuestStopSignal(signal);
    guestStopSignal.store(signal, std::memory_order_relaxed);
    if (!pending) {
        pendingGuestFatalSignal.store(0, std::memory_order_relaxed);
        reemitPendingGuestStop.store(false, std::memory_order_relaxed);
    } else {
        pendingGuestFatalSignal.store(signal, std::memory_order_relaxed);
    }
}

void RecordGuestStopSignal(int signal, bool pending) {
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

void ClearCurrentGuestStopRequest() {
    currentGuestStopRequest = {};
}

GuestStopRequest CurrentGuestStopRequestForReason(
        Dynarmic::HaltReason reason) {
    GuestStopRequest request = currentGuestStopRequest;
    if (request.valid) {
        return request;
    }

    const Dynarmic::HaltReason visibleReason =
        reason & ~(LC32HaltReasonDebuggerPause |
                   LC32HaltReasonThreadState);
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

bool ConsumePendingGuestStop() {
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

void UpdateGuestStopSignalForHalt(Dynarmic::HaltReason reason) {
    const Dynarmic::HaltReason visibleReason =
        reason & ~(LC32HaltReasonDebuggerPause |
                   LC32HaltReasonThreadState);
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

int FindGuestMapping(u32 loadAddress) {
    for (int i = 0; i < guestMappingLen; ++i) {
        if (guestMappings[i].start == loadAddress) {
            return i;
        }
    }
    return -1;
}

void RemoveGuestMapping(u32 loadAddress) {
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

extern "C"
int return_with_carry(int result, bool carry) {
    threadHandle.cpsr->setCarry(carry);
    return carry ? errno : result;
}

extern "C"
bool LC32DebuggerActive() {
    return NativeDebuggerActive();
}

extern "C"
bool LC32DebuggerAllStopRequested() {
    return debuggerAllStopRequested.load(std::memory_order_acquire);
}

extern "C"
bool LC32DebuggerSessionUnwindRequested() {
    return debuggerSessionUnwindRequested.load(
        std::memory_order_acquire);
}

extern "C"
void LC32SetDebuggerStopRunLoopNotifier(
        void (*notifier)(void)) {
    debuggerStopRunLoopNotifier.store(
        notifier, std::memory_order_release);
}

extern "C"
int return_with_carry_direct(int result, bool carry) {
    threadHandle.cpsr->setCarry(carry);
    return result;
}

extern "C"
__attribute__((visibility("hidden")))
int syscallRetCarry(long syscall, ...);
__asm__(" \
.private_extern _syscallRetCarry \n \
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
