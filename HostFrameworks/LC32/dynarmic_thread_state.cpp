#include "dynarmic_internal.h"

NativeThreadStateSlot mainNativeThreadState;
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
thread_local size_t nativeGuestWorkqueueHostBlockDepth;
thread_local bool nativeDebuggerHostWaitStep;
thread_local uint64_t nativeDebuggerHostWaitStepGeneration;
thread_local size_t nativeDebuggerMainCallbackStopDepth;
thread_local gdb_thread_id_t cooperativeDebuggerResumeThread =
    GDB_THREAD_ID_ALL;

std::mutex nativeGuestJitMutex;
std::condition_variable nativeGuestJitCondition;
std::vector<NativeGuestJit *> nativeGuestJits;
NativeDebuggerCoordinator nativeDebugger;

bool GuestCallbackExecutorDebuggerStepPending() {
    return nativeDebuggerHostWaitStep;
}

std::mutex guestPsynchPrepostMutex;
std::vector<GuestMutexPrepost> guestMutexPreposts;
std::vector<GuestConditionPrepost> guestConditionPreposts;

std::mutex nativeGuestWaitMutex;
std::vector<std::shared_ptr<NativeGuestWaiter>> nativeGuestWaiters;
std::vector<NativeGuestRwlockUnlock> nativeGuestRwlockUnlocks;
std::vector<NativeGuestRwlockOverlap> nativeGuestRwlockOverlaps;

bool NativeDebuggerActive() {
    return NativeGuestThreadsEnabled() &&
        guestDebuggerEnabled.load(std::memory_order_acquire);
}

void NativeDebuggerSetWorkerExecutingLocked(
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

bool NativeDebuggerRunsThreadLocked(
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

bool NativeDebuggerStepsThreadLocked(
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

bool ConsumeNativeDebuggerHostWaitStep(
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
    {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        for (const auto &waiter : nativeGuestWaiters) {
            waiter->condition.notify_all();
        }
    }
    NotifyGuestCallbackExecutorWaiter();
}

void NotifyNativeDebuggerCoordinator() {
    nativeDebugger.condition.notify_all();
}

u32 guestWorkqueueAllocation;
u32 guestWorkqueueAllocationSize;
u32 guestWorkqueuePthread;
u32 guestWorkqueueStackBottom;
mach_port_t guestWorkqueueThreadPort;
bool guestWorkqueueWorkerInitialized;
std::mutex guestNativeWorkqueuePumpMutex;
std::deque<GuestWorkqueueJob> guestNativeWorkqueuePendingJobs;
GuestWorkqueuePendingUpcall guestWorkqueuePendingUpcall;
context32 guestWorkqueueWaitingContext;
bool guestWorkqueueWaitingContextValid;
gdb_thread_id_t guestWorkqueueWaitingThreadId;
u64 guestWorkqueueThreadSelfId;
u32 guestWorkqueueSignalMask;

gdb_thread_id_t ActiveMainDebuggerThread() {
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    return guestWorkqueueUpcallActive &&
        guestWorkqueueWaitingContextValid
        ? 2
        : 1;
}

bool NativeDebuggerMainContextMayRun() {
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
    context.uro = DynarmicCallbacks32CP15(callbacks)->uro;
}

static NativeThreadStateSlot *CurrentNativeThreadStateSlot() {
    if (!NativeGuestThreadsEnabled() || nativeGuestThreadId == 0) {
        return nullptr;
    }
    return nativeGuestRuntime != nullptr
        ? &nativeGuestRuntime->threadState
        : &mainNativeThreadState;
}

/*
 * Generic Objective-C/C host calls are not necessarily backed by one of the
 * interruptible Mach waits tracked elsewhere in this file.  Once an outer
 * host call has published a quiescent register file, it can stop counting as
 * an executing worker without forcing the native call to return.  This is
 * safe only until either the call returns or native code re-enters the guest.
 */
static void NativeDebuggerParkQuiescentHostCall() {
    NativeGuestJit *runtime = nativeGuestRuntime;
    if (runtime == nullptr || !NativeDebuggerActive()) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        if (runtime->debuggerHostCallQuiescent) {
            return;
        }
        runtime->debuggerHostCallQuiescent = true;
        NativeDebuggerSetWorkerExecutingLocked(
            runtime, false);
    }
    nativeDebugger.condition.notify_all();
}

/*
 * Keep the guest register file untouched while an all-stop is closed.  A
 * selected single-step first lets the native call copy its result out, then
 * reuses the existing host-wait handoff to unwind the old Jit::Run and issue
 * one real Jit::Step from the post-SVC PC.
 */
static bool NativeDebuggerResumeQuiescentHostCall(
        bool prepareDeferredStep) {
    NativeGuestJit *runtime = nativeGuestRuntime;
    if (runtime == nullptr) {
        return true;
    }

    std::unique_lock<std::mutex> lock(nativeDebugger.mutex);
    if (!runtime->debuggerHostCallQuiescent) {
        return true;
    }
    nativeDebugger.condition.wait(lock, [runtime] {
        return !NativeDebuggerActive() ||
            nativeGuestThreadRetiring ||
            nativeShutdownRequested.load(
                std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire) ||
            nativeDebugger.state ==
                NativeDebuggerRunState::ShuttingDown ||
            (nativeDebugger.state ==
                NativeDebuggerRunState::Running &&
             NativeDebuggerRunsThreadLocked(
                 runtime->debuggerId));
    });

    runtime->debuggerHostCallQuiescent = false;
    if (!NativeDebuggerActive() ||
            nativeGuestThreadRetiring ||
            nativeShutdownRequested.load(
                std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire) ||
            nativeDebugger.state ==
                NativeDebuggerRunState::ShuttingDown) {
        nativeDebuggerHostWaitStep = false;
        nativeDebuggerHostWaitStepGeneration = 0;
        return false;
    }

    if (prepareDeferredStep) {
        nativeDebuggerHostWaitStep =
            NativeDebuggerStepsThreadLocked(
                runtime->debuggerId);
        nativeDebuggerHostWaitStepGeneration =
            nativeDebuggerHostWaitStep
            ? nativeDebugger.generation
            : 0;
        if (nativeDebuggerHostWaitStep &&
                runtime->jit != nullptr) {
            runtime->jit->HaltExecution(
                LC32HaltReasonDebuggerPause);
        }
    }
    NativeDebuggerSetWorkerExecutingLocked(runtime, true);
    return true;
}

/*
 * A deferred host call runs after Jit::Run has returned. Track its outer
 * scope here, but leave argument marshalling counted as guest work. The
 * bridge publishes the stable register interval only around the exact native
 * invocation; a nested host-to-guest callback temporarily revokes it before
 * saving or changing registers.
 */
void NativeGuestHostCallEnter() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(
        slot->registerAccessMutex);
    ++slot->hostCallDepth;
    /* Argument marshalling is still guest work.  The bridge explicitly
     * publishes quiescence only around the actual native invocation. */
    slot->hostRegistersQuiescent = false;
}

void NativeGuestHostCallExit() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(
        slot->registerAccessMutex);
    assert(slot->hostCallDepth != 0);
    /* A host-to-guest callback may contain a nested host call while the
     * outer native invocation's quiescence scope remains on its stack. */
    assert(slot->hostCallQuiescenceDepth <
        slot->hostCallDepth);
    --slot->hostCallDepth;
    /* The host return value has not yet been written to the guest JIT. */
    slot->hostRegistersQuiescent = false;
}

extern "C"
bool Dynarmic_guest_host_call_quiescence_begin() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return false;
    }

    bool registersQuiescent;
    {
        std::lock_guard<std::mutex> lock(
            slot->registerAccessMutex);
        if (slot->hostCallDepth == 0) {
            return false;
        }
        ++slot->hostCallQuiescenceDepth;
        slot->hostRegistersQuiescent =
            slot->guestCallbackDepth == 0;
        registersQuiescent =
            slot->hostRegistersQuiescent;
    }
    if (registersQuiescent) {
        NativeDebuggerParkQuiescentHostCall();
    }
    return true;
}

extern "C"
void Dynarmic_guest_host_call_quiescence_end() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return;
    }

    bool registersQuiescent;
    {
        std::lock_guard<std::mutex> lock(
            slot->registerAccessMutex);
        assert(slot->hostCallQuiescenceDepth != 0);
        registersQuiescent =
            slot->guestCallbackDepth == 0 &&
            slot->hostRegistersQuiescent;
    }
    if (registersQuiescent) {
        /* Copyout after the native call belongs to an open guest epoch. */
        (void)NativeDebuggerResumeQuiescentHostCall(true);
    }
    {
        std::lock_guard<std::mutex> lock(
            slot->registerAccessMutex);
        assert(slot->hostCallQuiescenceDepth != 0);
        --slot->hostCallQuiescenceDepth;
        slot->hostRegistersQuiescent = false;
    }
}

void NativeGuestCallbackRegisterAccessBegin() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return;
    }
    /* A reverse callback is guest execution, so it must own an open epoch. */
    (void)NativeDebuggerResumeQuiescentHostCall(false);
    {
        std::lock_guard<std::mutex> lock(
            slot->registerAccessMutex);
        ++slot->guestCallbackDepth;
        slot->hostRegistersQuiescent = false;
    }
}

void NativeGuestCallbackRegisterAccessEnd() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return;
    }
    bool registersQuiescent;
    {
        std::lock_guard<std::mutex> lock(
            slot->registerAccessMutex);
        assert(slot->guestCallbackDepth != 0);
        --slot->guestCallbackDepth;
        slot->hostRegistersQuiescent =
            slot->hostCallQuiescenceDepth != 0 &&
            slot->guestCallbackDepth == 0;
        registersQuiescent =
            slot->hostRegistersQuiescent;
    }
    if (registersQuiescent) {
        NativeDebuggerParkQuiescentHostCall();
    }
}

static bool TryCopyQuiescentNativeThreadState(
        NativeThreadStateSlot &slot,
        Dynarmic::A32::Jit *jit,
        DynarmicCallbacks32 *callbacks,
        context32 &snapshot) {
    if (jit == nullptr || callbacks == nullptr) {
        return false;
    }
    std::lock_guard<std::mutex> lock(
        slot.registerAccessMutex);
    if (!slot.hostRegistersQuiescent ||
            slot.hostCallDepth == 0 ||
            slot.hostCallQuiescenceDepth == 0 ||
            slot.guestCallbackDepth != 0) {
        return false;
    }
    snapshot.regs = jit->Regs();
    snapshot.extRegs = jit->ExtRegs();
    snapshot.cpsr = jit->Cpsr();
    snapshot.fpscr = jit->Fpscr();
    snapshot.uro = DynarmicCallbacks32CP15(callbacks)->uro;
    return true;
}

bool NativeThreadStatePauseRequestedForCurrent() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return false;
    }
    std::lock_guard<std::mutex> lock(slot->mutex);
    return slot->requestedGeneration >
        slot->releasedGeneration;
}

/*
 * Called only by the host pthread which owns this JIT, either after Run()
 * observes the private halt or while that same pthread is inside an
 * interruptible syscall callback.  Consequently SaveGuestContext never
 * races Dynarmic execution.
 */
static bool PublishNativeThreadStateAndWaitIfNeeded() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return false;
    }

    std::unique_lock<std::mutex> lock(slot->mutex);
    bool paused = false;
    while (slot->requestedGeneration >
            slot->releasedGeneration &&
            !slot->ownerExited &&
            !nativeGuestThreadRetiring &&
            !nativeShutdownRequested.load(
                std::memory_order_acquire) &&
            !guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        const uint64_t generation =
            slot->requestedGeneration;
        if (slot->acknowledgedGeneration < generation) {
            SaveGuestContext(slot->snapshot);
            slot->snapshotValid = true;
            slot->acknowledgedGeneration = generation;
        }
        paused = true;
        slot->condition.notify_all();
        slot->condition.wait(lock, [slot, generation] {
            return slot->releasedGeneration >= generation ||
                slot->ownerExited ||
                nativeGuestThreadRetiring ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire) ||
                guestProcessExitRequested.load(
                    std::memory_order_acquire);
        });
    }

    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if (jit != nullptr) {
        jit->ClearHalt(LC32HaltReasonThreadState);
    }
    lock.unlock();
    return paused;
}

/*
 * Two guest pthreads can ask for each other's state at the same time (objc's
 * cache collector normally serializes this, but the Mach ABI does not).  A
 * requester is already outside Jit::Run with stable registers, so it may
 * acknowledge an incoming request without parking immediately.  It remains
 * in the outgoing request loop, then waits for the incoming request's release
 * before returning to guest execution.
 */
static bool AcknowledgeNestedNativeThreadStateRequest() {
    NativeThreadStateSlot *slot =
        CurrentNativeThreadStateSlot();
    if (slot == nullptr) {
        return false;
    }
    std::lock_guard<std::mutex> lock(slot->mutex);
    if (slot->requestedGeneration <=
            slot->releasedGeneration ||
            slot->acknowledgedGeneration >=
                slot->requestedGeneration ||
            slot->ownerExited) {
        return false;
    }
    SaveGuestContext(slot->snapshot);
    slot->snapshotValid = true;
    slot->acknowledgedGeneration =
        slot->requestedGeneration;
    slot->condition.notify_all();
    return true;
}

bool NativeThreadStatePauseHostWaitIfNeeded() {
    if (!NativeThreadStatePauseRequestedForCurrent()) {
        return false;
    }
    return PublishNativeThreadStateAndWaitIfNeeded();
}

bool ConsumeNativeThreadStateHalt(
        Dynarmic::HaltReason &reason) {
    const bool hasHalt = Dynarmic::Has(
        reason, LC32HaltReasonThreadState);
    if (!hasHalt &&
            !NativeThreadStatePauseRequestedForCurrent()) {
        return false;
    }
    const bool paused =
        PublishNativeThreadStateAndWaitIfNeeded();
    reason = reason & ~LC32HaltReasonThreadState;
    return hasHalt || paused;
}

void NativeThreadStateOwnerExited(
        NativeThreadStateSlot &slot) {
    std::lock_guard<std::mutex> lock(slot.mutex);
    slot.ownerExited = true;
    slot.releasedGeneration = std::max(
        slot.releasedGeneration,
        slot.requestedGeneration);
    slot.condition.notify_all();
}

void ResetNativeThreadStateSlot(
        NativeThreadStateSlot &slot) {
    {
        std::lock_guard<std::mutex> lock(slot.mutex);
        slot.nextGeneration = 0;
        slot.requestedGeneration = 0;
        slot.acknowledgedGeneration = 0;
        slot.releasedGeneration = 0;
        slot.snapshot = {};
        slot.snapshotValid = false;
        slot.ownerExited = false;
        slot.condition.notify_all();
    }
    {
        std::lock_guard<std::mutex> lock(
            slot.registerAccessMutex);
        slot.hostCallDepth = 0;
        slot.hostCallQuiescenceDepth = 0;
        slot.guestCallbackDepth = 0;
        slot.hostRegistersQuiescent = false;
    }
}

static bool PinNativeGuestJitForThreadState(
        NativeGuestJit *runtime) {
    if (runtime == nullptr) {
        return false;
    }
    std::lock_guard<std::mutex> lock(nativeGuestJitMutex);
    if (runtime->exited ||
            std::find(nativeGuestJits.begin(),
                nativeGuestJits.end(), runtime) ==
                nativeGuestJits.end()) {
        return false;
    }
    ++runtime->threadStateUsers;
    return true;
}

static void UnpinNativeGuestJitForThreadState(
        NativeGuestJit *runtime) {
    if (runtime == nullptr) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(nativeGuestJitMutex);
        assert(runtime->threadStateUsers != 0);
        --runtime->threadStateUsers;
    }
    nativeGuestJitCondition.notify_all();
}

static kern_return_t RequestNativeThreadStateSnapshot(
        NativeThreadStateSlot &slot,
        Dynarmic::A32::Jit *jit,
        DynarmicCallbacks32 *callbacks,
        NativeGuestJit *pinnedRuntime,
        gdb_thread_id_t hostCallThreadId,
        context32 &snapshot) {
    const auto finish = [pinnedRuntime](kern_return_t result) {
        (void)PublishNativeThreadStateAndWaitIfNeeded();
        UnpinNativeGuestJitForThreadState(pinnedRuntime);
        return result;
    };
    if (jit == nullptr || callbacks == nullptr) {
        return finish(KERN_FAILURE);
    }

    if (TryCopyQuiescentNativeThreadState(
            slot, jit, callbacks, snapshot)) {
        return finish(KERN_SUCCESS);
    }

    if (NativeDebuggerActive()) {
        bool copiedStoppedState = false;
        {
            std::lock_guard<std::mutex> debuggerLock(
                nativeDebugger.mutex);
            const bool targetExecuting =
                pinnedRuntime != nullptr
                ? pinnedRuntime->debuggerExecuting
                : nativeDebugger.mainExecuting;
            if (!targetExecuting) {
                snapshot.regs = jit->Regs();
                snapshot.extRegs = jit->ExtRegs();
                snapshot.cpsr = jit->Cpsr();
                snapshot.fpscr = jit->Fpscr();
                snapshot.uro = DynarmicCallbacks32CP15(callbacks)->uro;
                copiedStoppedState = true;
            }
        }
        if (copiedStoppedState) {
            return finish(KERN_SUCCESS);
        }
    }

    std::unique_lock<std::mutex> lock(slot.mutex);
    while (slot.requestedGeneration >
            slot.releasedGeneration &&
            !slot.ownerExited &&
            !nativeShutdownRequested.load(
                std::memory_order_acquire) &&
            !guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        lock.unlock();
        if (TryCopyQuiescentNativeThreadState(
                slot, jit, callbacks, snapshot)) {
            return finish(KERN_SUCCESS);
        }
        (void)AcknowledgeNestedNativeThreadStateRequest();
        lock.lock();
        (void)slot.condition.wait_for(
            lock, std::chrono::milliseconds(20));
    }
    if (slot.ownerExited ||
            nativeShutdownRequested.load(
                std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        lock.unlock();
        return finish(KERN_FAILURE);
    }

    uint64_t generation = ++slot.nextGeneration;
    if (generation == 0) {
        generation = ++slot.nextGeneration;
    }
    slot.requestedGeneration = generation;
    slot.snapshotValid = false;
    jit->HaltExecution(LC32HaltReasonThreadState);
    lock.unlock();

    NotifyNativeDebuggerWaiters();
    InterruptNativeThreadStateHostCalls(hostCallThreadId);

    lock.lock();
    bool capturedQuiescentState = false;
    for (;;) {
        lock.unlock();
        context32 quiescentSnapshot = {};
        const bool quiescent =
            TryCopyQuiescentNativeThreadState(
                slot, jit, callbacks,
                quiescentSnapshot);
        (void)AcknowledgeNestedNativeThreadStateRequest();
        lock.lock();
        if (quiescent &&
                slot.requestedGeneration == generation &&
                slot.releasedGeneration < generation) {
            snapshot = quiescentSnapshot;
            capturedQuiescentState = true;
            break;
        }
        if (slot.acknowledgedGeneration >= generation &&
                slot.snapshotValid) {
            snapshot = slot.snapshot;
            break;
        }
        if (slot.ownerExited ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire) ||
                guestProcessExitRequested.load(
                    std::memory_order_acquire) ||
                debuggerAllStopRequested.load(
                    std::memory_order_acquire)) {
            break;
        }
        if (slot.condition.wait_for(
                lock, std::chrono::milliseconds(20)) ==
                std::cv_status::timeout) {
            lock.unlock();
            NotifyNativeDebuggerWaiters();
            InterruptNativeThreadStateHostCalls(
                hostCallThreadId);
            lock.lock();
        }
    }

    const bool succeeded =
        capturedQuiescentState ||
        (slot.acknowledgedGeneration >= generation &&
         slot.snapshotValid);
    slot.releasedGeneration = std::max(
        slot.releasedGeneration, generation);
    /* Serialize clearing the old level-triggered bit with the next request. */
    jit->ClearHalt(LC32HaltReasonThreadState);
    slot.condition.notify_all();
    lock.unlock();
    return finish(succeeded ? KERN_SUCCESS : KERN_ABORTED);
}

void LoadGuestContext(const context32 &context) {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    DynarmicCallbacks32 *callbacks = threadHandle.cb;
    jit->Regs() = context.regs;
    jit->ExtRegs() = context.extRegs;
    jit->SetCpsr(context.cpsr);
    jit->SetFpscr(context.fpscr);
    DynarmicCallbacks32CP15(callbacks)->uro = context.uro;
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
        gdb_thread_id_t debuggerId, bool requireAlive) {
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

struct GuestSignalStack32 {
    u32 stackPointer;
    u32 stackSize;
    int32_t flags;
};
static_assert(sizeof(GuestSignalStack32) == 12);

u32 GuestSigaltstack(u32 guestStack, u32 guestOldStack) {
    /* XNU preserves OLDMINSIGSTKSZ for the syscall ABI even though the
     * public SDK's modern MINSIGSTKSZ is larger. */
    constexpr u32 GuestMinimumSignalStackSize = 8 * 1024;

    GuestSignalStack32 requested = {};
    if(guestStack && Dynarmic_mem_1read(
            guestStack, sizeof(requested),
            reinterpret_cast<char *>(&requested)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    if(guestStack && requested.flags != 0 &&
            requested.flags != SS_DISABLE) {
        return return_with_carry_direct(EINVAL, true);
    }
    if(guestStack && requested.flags == 0 &&
            requested.stackSize < GuestMinimumSignalStackSize) {
        return return_with_carry_direct(ENOMEM, true);
    }

    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
    GuestThreadContext *thread =
        FindGuestThread(CurrentGuestThreadId(), true);
    if(!thread) {
        return return_with_carry_direct(ESRCH, true);
    }

    GuestSignalStack32 previous = {
        .stackPointer = thread->alternateSignalStackPointer,
        .stackSize = thread->alternateSignalStackSize,
        .flags = thread->alternateSignalStackFlags,
    };
    if(guestOldStack && Dynarmic_mem_1write(
            guestOldStack, sizeof(previous),
            reinterpret_cast<char *>(&previous)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    if(!guestStack) {
        return return_with_carry_direct(0, false);
    }
    if((thread->alternateSignalStackFlags & SS_ONSTACK) != 0) {
        return return_with_carry_direct(
            requested.flags == SS_DISABLE ? EINVAL : EPERM, true);
    }

    if(requested.flags == SS_DISABLE) {
        /* Darwin preserves the configured address and size while disabled. */
        thread->alternateSignalStackFlags = SS_DISABLE;
    } else {
        thread->alternateSignalStackPointer = requested.stackPointer;
        thread->alternateSignalStackSize = requested.stackSize;
        thread->alternateSignalStackFlags = 0;
    }
    return return_with_carry_direct(0, false);
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

kern_return_t CopyGuestTaskThreadPorts(
        u32 *guestAddress, mach_msg_type_number_t *count) {
    if (guestAddress == nullptr || count == nullptr) {
        return KERN_INVALID_ARGUMENT;
    }
    *guestAddress = 0;
    *count = 0;
    EnsureGuestThreadRegistry();

    std::vector<mach_port_t> ports;
    kern_return_t retainResult = KERN_SUCCESS;
    const auto alreadyAdded = [&ports](mach_port_t port) {
        return std::find(ports.begin(), ports.end(), port) !=
            ports.end();
    };
    const auto retainExistingPort = [&](mach_port_t port) {
        if (!MACH_PORT_VALID(port) || alreadyAdded(port)) {
            return KERN_SUCCESS;
        }
        const kern_return_t result = mach_port_mod_refs(
            mach_task_self(), port, MACH_PORT_RIGHT_SEND, 1);
        if (result == KERN_SUCCESS) {
            ports.push_back(port);
        }
        return result;
    };

    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        for (const GuestThreadContext &thread : guestThreads) {
            if (!thread.alive) {
                continue;
            }
            if (MACH_PORT_VALID(thread.threadPort)) {
                retainResult = retainExistingPort(thread.threadPort);
            } else if (thread.debuggerId == 1) {
                /*
                 * Cooperative mode does not keep a synthetic port for the
                 * main thread: thread_self_trap normally falls through to
                 * this host thread. pthread_mach_thread_np identifies that
                 * port, and retainExistingPort supplies the extra send-right
                 * reference transferred by task_threads.
                 */
                const mach_port_t mainPort =
                    pthread_mach_thread_np(pthread_self());
                if (!MACH_PORT_VALID(mainPort)) {
                    retainResult = KERN_FAILURE;
                } else {
                    retainResult = retainExistingPort(mainPort);
                }
            }
            if (retainResult != KERN_SUCCESS) {
                break;
            }
        }
    }
    if (retainResult == KERN_SUCCESS) {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        if (guestWorkqueueUpcallActive &&
                guestWorkqueueWaitingContextValid &&
                MACH_PORT_VALID(guestWorkqueueThreadPort)) {
            retainResult = retainExistingPort(
                guestWorkqueueThreadPort);
        }
    }

    const auto releasePorts = [&ports] {
        for (mach_port_t port : ports) {
            (void)mach_port_deallocate(
                mach_task_self(), port);
        }
    };
    if (retainResult != KERN_SUCCESS || ports.empty()) {
        releasePorts();
        return retainResult != KERN_SUCCESS
            ? retainResult
            : KERN_FAILURE;
    }
    if (ports.size() > UINT32_MAX / sizeof(mach_port_t)) {
        releasePorts();
        return KERN_RESOURCE_SHORTAGE;
    }

    const size_t byteCount = ports.size() * sizeof(mach_port_t);
    const size_t allocationSize =
        (byteCount + DYN_PAGE_MASK) & ~size_t(DYN_PAGE_MASK);
    const u32 allocation = Dynarmic_mmap(
        0, allocationSize, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (allocation == UINT32_MAX) {
        releasePorts();
        return KERN_RESOURCE_SHORTAGE;
    }
    if (Dynarmic_mem_1write(
            allocation, byteCount,
            reinterpret_cast<char *>(ports.data())) != 0) {
        (void)Dynarmic_munmap(allocation, allocationSize);
        releasePorts();
        return KERN_MEMORY_ERROR;
    }

    *guestAddress = allocation;
    *count = static_cast<mach_msg_type_number_t>(ports.size());
    THREAD_TRACE(
        "LC32: task_threads returned %u guest threads at 0x%x\n",
        *count, *guestAddress);
    return KERN_SUCCESS;
}

kern_return_t CopyGuestThreadState(
        mach_port_t target, thread_state_flavor_t flavor,
        mach_msg_type_number_t capacity, u32 *state,
        mach_msg_type_number_t *count) {
    constexpr mach_msg_type_number_t ArmThreadStateWordCount = 17;
    if (!MACH_PORT_VALID(target) || state == nullptr || count == nullptr ||
            (flavor != ARM_THREAD_STATE &&
             flavor != ARM_THREAD_STATE32) ||
            capacity < ArmThreadStateWordCount) {
        return KERN_INVALID_ARGUMENT;
    }

    EnsureGuestThreadRegistry();
    context32 snapshot = {};
    bool found = false;
    bool workqueueActive = false;
    gdb_thread_id_t waitingThreadId = 0;
    context32 waitingContext = {};
    NativeThreadStateSlot *nativeSlot = nullptr;
    Dynarmic::A32::Jit *nativeJit = nullptr;
    DynarmicCallbacks32 *nativeCallbacks = nullptr;
    NativeGuestJit *pinnedRuntime = nullptr;
    gdb_thread_id_t hostCallThreadId = 0;

    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        workqueueActive = guestWorkqueueUpcallActive &&
            guestWorkqueueWaitingContextValid;
        if (workqueueActive) {
            waitingThreadId = guestWorkqueueWaitingThreadId;
            waitingContext = guestWorkqueueWaitingContext;
            if (target == guestWorkqueueThreadPort) {
                /*
                 * In cooperative mode the active workqueue owns the shared
                 * JIT. Native mode may call this routine concurrently from a
                 * different guest pthread, so only read the JIT when this
                 * host thread actually owns the workqueue overlay.
                 */
                if (!NativeGuestThreadsEnabled() ||
                        guestWorkqueueOverlayCurrent) {
                    SaveGuestContext(snapshot);
                    found = true;
                } else {
                    nativeSlot = &mainNativeThreadState;
                    nativeJit = sharedHandle.cb != nullptr
                        ? DynarmicCallbacks32Jit(sharedHandle.cb)
                        : nullptr;
                    nativeCallbacks = sharedHandle.cb;
                    hostCallThreadId = 1;
                }
            }
        }
    }

    if (!found) {
        const mach_port_t cooperativeMainPort =
            !NativeGuestThreadsEnabled()
            ? pthread_mach_thread_np(pthread_self())
            : MACH_PORT_NULL;
        std::lock_guard<std::recursive_mutex> lock(guestThreadMutex);
        for (const GuestThreadContext &thread : guestThreads) {
            if (!thread.alive) {
                continue;
            }
            const bool targetMatches =
                thread.threadPort == target ||
                (thread.debuggerId == 1 &&
                 !MACH_PORT_VALID(thread.threadPort) &&
                 target == cooperativeMainPort);
            if (!targetMatches) {
                continue;
            }

            if (workqueueActive &&
                    waitingThreadId == thread.debuggerId) {
                snapshot = waitingContext;
                found = true;
                break;
            }
            if (thread.debuggerId == CurrentGuestThreadId()) {
                SaveGuestContext(snapshot);
                found = true;
                break;
            }
            if (NativeGuestThreadsEnabled()) {
                hostCallThreadId = thread.debuggerId;
                if (thread.debuggerId == 1) {
                    nativeSlot = &mainNativeThreadState;
                    nativeJit = sharedHandle.cb != nullptr
                        ? DynarmicCallbacks32Jit(sharedHandle.cb)
                        : nullptr;
                    nativeCallbacks = sharedHandle.cb;
                } else if (thread.nativeJit != nullptr &&
                        PinNativeGuestJitForThreadState(
                            thread.nativeJit)) {
                    pinnedRuntime = thread.nativeJit;
                    nativeSlot = &pinnedRuntime->threadState;
                    nativeJit = pinnedRuntime->jit;
                    nativeCallbacks = pinnedRuntime->callbacks;
                }
                break;
            }
            if (thread.savedValid) {
                snapshot = thread.saved;
                found = true;
            }
            break;
        }
    }

    if (!found && nativeSlot != nullptr) {
        const kern_return_t result =
            RequestNativeThreadStateSnapshot(
                *nativeSlot, nativeJit, nativeCallbacks,
                pinnedRuntime,
                hostCallThreadId, snapshot);
        pinnedRuntime = nullptr;
        if (result != KERN_SUCCESS) {
            return result;
        }
        found = true;
    }

    if (!found) {
        return KERN_INVALID_ARGUMENT;
    }

    static_assert(std::tuple_size<decltype(snapshot.regs)>::value == 16,
        "ARM32 context must contain r0-r15");
    memcpy(state, snapshot.regs.data(), sizeof(snapshot.regs));
    state[16] = snapshot.cpsr;
    *count = ArmThreadStateWordCount;
    return KERN_SUCCESS;
}

bool ParkCurrentGuestThread(
        GuestThreadWaitKind kind, u32 address, u32 wakeResult,
        GuestRwlockWaitType rwlockWaitType,
        u32 rwlockSequence,
        u32 conditionSequence,
        u32 mutexSequence) {
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
    current->mutexSequence = mutexSequence;
    current->conditionSequence = conditionSequence;
    current->rwlockWaitType = rwlockWaitType;
    current->rwlockSequence = rwlockSequence;
    if (NextGuestThread() == nullptr) {
        current->runnable = true;
        current->waitKind = GuestThreadWaitKind::None;
        current->waitAddress = 0;
        current->wakeResult = 0;
        current->waitSequence = 0;
        current->mutexSequence = 0;
        current->conditionSequence = 0;
        current->rwlockWaitType =
            GuestRwlockWaitType::None;
        current->rwlockSequence = 0;
        return false;
    }
    guestThreadRotationRequested = true;
    return true;
}

size_t WakeGuestThreads(
        GuestThreadWaitKind kind, u32 address, bool wakeAll,
        mach_port_t targetThread) {
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
        selected->mutexSequence = 0;
        selected->conditionSequence = 0;
        selected->rwlockWaitType =
            GuestRwlockWaitType::None;
        selected->rwlockSequence = 0;
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

size_t WakeGuestMutexThread(
        u32 address, u32 targetSequence, bool firstFit) {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    GuestThreadContext *selected = nullptr;
    for (GuestThreadContext &thread : guestThreads) {
        if (!thread.alive || thread.runnable ||
                thread.waitKind != GuestThreadWaitKind::Mutex ||
                thread.waitAddress != address ||
                (!firstFit &&
                 thread.mutexSequence != targetSequence)) {
            continue;
        }
        if (selected == nullptr ||
                thread.waitSequence < selected->waitSequence) {
            selected = &thread;
        }
    }
    if (selected == nullptr) {
        return 0;
    }

    selected->runnable = true;
    selected->waitKind = GuestThreadWaitKind::None;
    selected->waitAddress = 0;
    selected->waitSequence = 0;
    selected->mutexSequence = 0;
    selected->conditionSequence = 0;
    selected->rwlockWaitType = GuestRwlockWaitType::None;
    selected->rwlockSequence = 0;
    if (selected->savedValid) {
        selected->saved.regs[Reg::R0] = selected->wakeResult;
        selected->saved.cpsr &=
            ~(static_cast<u32>(1) << CARRY_BIT);
    }
    selected->wakeResult = 0;
    return 1;
}

size_t WakeGuestConditionThreads(
        u32 address, u32 throughSequence, bool wakeAll,
        mach_port_t targetThread) {
    EnsureGuestThreadRegistry();
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    size_t count = 0;
    for (;;) {
        GuestThreadContext *selected = nullptr;
        for (GuestThreadContext &thread : guestThreads) {
            if (!thread.alive || thread.runnable ||
                    thread.waitKind !=
                        GuestThreadWaitKind::Condition ||
                    thread.waitAddress != address ||
                    !GuestPsynchSequenceLowerOrEqual(
                        thread.conditionSequence,
                        throughSequence) ||
                    (MACH_PORT_VALID(targetThread) &&
                     thread.threadPort != targetThread)) {
                continue;
            }
            if (selected == nullptr ||
                    thread.waitSequence <
                        selected->waitSequence) {
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
        selected->mutexSequence = 0;
        selected->conditionSequence = 0;
        if (selected->savedValid) {
            /* A registered CV waiter returns zero.  The signal syscall's
             * update count advances S; only a late prepost returns INC. */
            selected->saved.regs[Reg::R0] = 0;
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

u32 GrantCooperativeGuestRwlockThreads(
        u32 address, size_t *wokenCount) {
    std::lock_guard<std::recursive_mutex> lock(
        guestThreadMutex);
    std::vector<GuestThreadContext *> candidates;
    for (GuestThreadContext &thread : guestThreads) {
        if (thread.alive && !thread.runnable &&
                thread.waitKind == GuestThreadWaitKind::Rwlock &&
                thread.waitAddress == address &&
                thread.rwlockWaitType !=
                    GuestRwlockWaitType::None) {
            candidates.push_back(&thread);
        }
    }
    if (candidates.empty()) {
        if (wokenCount != nullptr) {
            *wokenCount = 0;
        }
        return 0;
    }

    GuestThreadContext *lowest = candidates.front();
    GuestThreadContext *lowestWriter = nullptr;
    for (GuestThreadContext *thread : candidates) {
        if (GuestPsynchSequenceLower(
                thread->rwlockSequence,
                lowest->rwlockSequence)) {
            lowest = thread;
        }
        if (thread->rwlockWaitType ==
                    GuestRwlockWaitType::Write &&
                (lowestWriter == nullptr ||
                 GuestPsynchSequenceLower(
                    thread->rwlockSequence,
                    lowestWriter->rwlockSequence))) {
            lowestWriter = thread;
        }
    }

    std::vector<GuestThreadContext *> granted;
    if (lowest->rwlockWaitType ==
            GuestRwlockWaitType::Write) {
        granted.push_back(lowest);
    } else {
        for (GuestThreadContext *thread : candidates) {
            if (thread->rwlockWaitType !=
                    GuestRwlockWaitType::Read) {
                continue;
            }
            if (lowestWriter == nullptr ||
                    GuestPsynchSequenceLower(
                        thread->rwlockSequence,
                        lowestWriter->rwlockSequence)) {
                granted.push_back(thread);
            }
        }
    }

    const bool writerGrant = granted.size() == 1 &&
        granted.front()->rwlockWaitType ==
            GuestRwlockWaitType::Write;
    const bool writerRemains = std::any_of(
        candidates.begin(), candidates.end(),
        [&granted](const GuestThreadContext *thread) {
            return thread->rwlockWaitType ==
                    GuestRwlockWaitType::Write &&
                std::find(granted.begin(), granted.end(), thread) ==
                    granted.end();
        });
    u32 update = writerGrant
        ? GuestPsynchCountIncrement |
            GuestPsynchRwKernelBit |
            GuestPsynchRwExclusiveBit
        : static_cast<u32>(granted.size()) *
            GuestPsynchCountIncrement;
    if (writerRemains) {
        update |= GuestPsynchRwKernelBit |
            GuestPsynchRwWriterBit;
    }

    for (GuestThreadContext *thread : granted) {
        thread->runnable = true;
        thread->waitKind = GuestThreadWaitKind::None;
        thread->waitAddress = 0;
        thread->waitSequence = 0;
        thread->mutexSequence = 0;
        thread->conditionSequence = 0;
        thread->rwlockWaitType =
            GuestRwlockWaitType::None;
        thread->rwlockSequence = 0;
        if (thread->savedValid) {
            thread->saved.regs[Reg::R0] = update;
            thread->saved.cpsr &=
                ~(static_cast<u32>(1) << CARRY_BIT);
        }
        thread->wakeResult = 0;
    }
    if (wokenCount != nullptr) {
        *wokenCount = granted.size();
    }
    return update;
}

void RecordGuestMutexPrepost(
        u32 address, u32 sequence) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    sequence &= GuestPsynchCountMask;
    for (GuestMutexPrepost &prepost : guestMutexPreposts) {
        if (prepost.address == address &&
                prepost.sequence == sequence) {
            ++prepost.count;
            return;
        }
    }
    guestMutexPreposts.push_back({
        .address = address,
        .sequence = sequence,
        .count = 1,
    });
}

bool ConsumeGuestMutexPrepost(
        u32 address, u32 sequence, bool firstFit) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    sequence &= GuestPsynchCountMask;
    for (auto it = guestMutexPreposts.begin();
            it != guestMutexPreposts.end(); ++it) {
        if (it->address != address ||
                (!firstFit && it->sequence != sequence)) {
            continue;
        }
        if (--it->count == 0) {
            guestMutexPreposts.erase(it);
        }
        return true;
    }
    return false;
}

void RecordGuestConditionSignalPrepost(
        u32 address, u32 throughSequence) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    throughSequence &= GuestPsynchCountMask;
    for (GuestConditionPrepost &prepost :
            guestConditionPreposts) {
        if (prepost.address == address &&
                prepost.throughSequence == throughSequence) {
            ++prepost.count;
            return;
        }
    }
    guestConditionPreposts.push_back({
        .address = address,
        .throughSequence = throughSequence,
        .count = 1,
    });
}

void RecordGuestConditionBroadcastPrepost(
        u32 address, u32 throughSequence, size_t count) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    throughSequence &= GuestPsynchCountMask;

    /* One XNU broadcast marker subsumes older signal/broadcast preposts. */
    guestConditionPreposts.erase(std::remove_if(
        guestConditionPreposts.begin(),
        guestConditionPreposts.end(),
        [address, throughSequence](
                const GuestConditionPrepost &prepost) {
            return prepost.address == address &&
                GuestPsynchSequenceLowerOrEqual(
                    prepost.throughSequence,
                    throughSequence);
        }), guestConditionPreposts.end());
    if (count != 0) {
        guestConditionPreposts.push_back({
            .address = address,
            .throughSequence = throughSequence,
            .count = count,
        });
    }
}

bool ConsumeGuestConditionPrepost(
        u32 address, u32 conditionSequence) {
    std::lock_guard<std::mutex> lock(
        guestPsynchPrepostMutex);
    conditionSequence &= GuestPsynchCountMask;
    auto selected = guestConditionPreposts.end();
    for (auto it = guestConditionPreposts.begin();
            it != guestConditionPreposts.end(); ++it) {
        if (it->address != address ||
                !GuestPsynchSequenceLowerOrEqual(
                    conditionSequence,
                    it->throughSequence)) {
            continue;
        }
        if (selected == guestConditionPreposts.end() ||
                GuestPsynchSequenceLower(
                    it->throughSequence,
                    selected->throughSequence)) {
            selected = it;
        }
    }
    if (selected == guestConditionPreposts.end()) {
        return false;
    }
    if (--selected->count == 0) {
        guestConditionPreposts.erase(selected);
    }
    return true;
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
