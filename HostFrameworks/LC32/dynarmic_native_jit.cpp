
#include "dynarmic_internal.h"

void InvalidateAllGuestJits(
        u32 address, size_t size) {
    if (size == 0) {
        return;
    }
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? DynarmicCallbacks32Jit(sharedHandle.cb)
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

void ScheduleMainGuestWorkqueueTransition() {
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? DynarmicCallbacks32Jit(sharedHandle.cb)
        : nullptr;
    if (mainJit != nullptr) {
        mainJit->HaltExecution(LC32HaltReasonWorkqueue);
    }
    /* A normal workqueue request does not set a debugger-wide stop flag, so
     * InterruptDebuggerMachCalls would deliberately do nothing here. Wake
     * only the main guest JIT's published host wait. */
    InterruptNativeThreadStateHostCalls(1);
}

void HaltAllGuestJits(
        Dynarmic::HaltReason reason) {
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? DynarmicCallbacks32Jit(sharedHandle.cb)
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

void ClearAllGuestJitHalts(
        Dynarmic::HaltReason reason) {
    Dynarmic::A32::Jit *mainJit =
        sharedHandle.cb != nullptr
        ? DynarmicCallbacks32Jit(sharedHandle.cb)
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

Dynarmic::HaltReason NativeDebuggerVisibleReason(
        Dynarmic::HaltReason reason) {
    return reason & ~(LC32HaltReasonDebuggerPause |
                      LC32HaltReasonThreadState);
}

static bool NativeDebuggerStopOwnerAlive(
        gdb_thread_id_t owner) {
    if (owner == 1) {
        return sharedHandle.cb != nullptr &&
            DynarmicCallbacks32Jit(sharedHandle.cb) != nullptr;
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
gdb_thread_id_t NativeDebuggerNormalizeStopOwnerLocked(
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

void NativeDebuggerTransferStopOwner(
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

bool NativeDebuggerRequestStop(
        gdb_thread_id_t owner,
        Dynarmic::HaltReason reason,
        int forcedSignal,
        bool forcedPendingSignal,
        bool queueWhileStopped) {
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
    /*
     * The guest main thread may be parked inside the host UIApplicationMain
     * run loop, whose blocking mach_msg is not tracked by debuggerMachCalls.
     * Wake the run loop so its armed block can unwind the host call and let
     * the main JIT return to the coordinator. Harmless when the main thread
     * is executing guest code (no run loop is running).
     */
    if (void (*notifier)(void) =
            debuggerStopRunLoopNotifier.load(
                std::memory_order_acquire)) {
        notifier();
    }
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
bool NativeDebuggerRepublishPendingStop(
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
        CreateDynarmicCallbacks32(sharedHandle.memory);

    Dynarmic::A32::UserConfig config;
    config.callbacks =
        DynarmicCallbacks32UserCallbacks(runtime->callbacks);
    config.coprocessors[15] = DynarmicCallbacks32CP15(runtime->callbacks);
    config.processor_id = processorId;
    config.global_monitor = sharedHandle.monitor;
    config.always_little_endian = false;
    config.wall_clock_cntpct = true;
    config.check_halt_on_memory_access = true;
    config.define_unpredictable_behaviour = true;
    // A separate cache is required for every JIT. Keep the experiment's
    // per-pthread footprint well below Dynarmic's 128 MiB default.
    config.code_cache_size = 16 * 1024 * 1024;

    DynarmicCallbacks32SetPageTable(
        runtime->callbacks,
        sharedHandle.num_page_table_entries,
        sharedHandle.page_table);
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
        DestroyDynarmicCallbacks32(runtime->callbacks);
        delete runtime;
        return nullptr;
    }

    DynarmicCallbacks32BindJit(
        runtime->callbacks, runtime->jit,
        runtime->cpsr);
    runtime->jit->Regs() = initial.regs;
    runtime->jit->ExtRegs() = initial.extRegs;
    runtime->jit->SetCpsr(initial.cpsr);
    runtime->jit->SetFpscr(initial.fpscr);
    DynarmicCallbacks32CP15(runtime->callbacks)->uro = initial.uro;
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

void DestroyNativeGuestJit(
        NativeGuestJit *runtime) {
    if (runtime == nullptr) {
        return;
    }
    {
        std::unique_lock<std::mutex> lock(
            nativeGuestJitMutex);
        nativeGuestJits.erase(std::remove(
            nativeGuestJits.begin(), nativeGuestJits.end(),
            runtime), nativeGuestJits.end());
        nativeGuestJitCondition.wait(lock, [runtime] {
            return runtime->threadStateUsers == 0;
        });
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
    DestroyDynarmicCallbacks32(runtime->callbacks);
    delete runtime;
}

void JoinNativeGuestJit(
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

    u32 retirementFreeAddress = 0;
    u32 retirementFreeSize = 0;
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
                retirementFreeAddress =
                    thread->retirementFreeAddress;
                retirementFreeSize =
                    thread->retirementFreeSize;
                thread->retirementFreeAddress = 0;
                thread->retirementFreeSize = 0;
                thread->threadPort = MACH_PORT_NULL;
                thread->alive = false;
                thread->runnable = false;
                thread->savedValid = false;
                thread->nativeJit = nullptr;
            }
        }
        NativeDebuggerTransferStopOwner(
            start->debuggerId, 1);
        GuestCallbackExecutorThreadExited(
            start->debuggerId);
        if (MACH_PORT_VALID(leftoverPort)) {
            (void)mach_port_destroy(
                mach_task_self(), leftoverPort);
        }

        /*
         * The pool may own bridge autorelease tokens whose dealloc methods
         * release guest references.  This logical guest thread is already
         * retired and its Exit halt is still latched, so advertising its JIT
         * here could partially execute a fresh guest callback before the halt
         * is observed.  Make direct guest entry unavailable before the pool
         * pops; bridge releases will use the callback executor or the existing
         * deferred-release queue instead.
        */
        threadHandle = {};
        if (runtime->workqueue &&
                !nativeShutdownRequested.load(
                    std::memory_order_acquire) &&
                !guestProcessExitRequested.load(
                    std::memory_order_acquire)) {
            runtime->workqueueHostBlocked.store(
                false, std::memory_order_release);
            runtime->workqueueCompensationPending.store(
                false, std::memory_order_release);
            /* The registry no longer counts this worker. Fill the newly
             * available bounded slot before publishing runtime->exited; a
             * pump must never reap and pthread_join its own host thread. */
            (void)PumpGuestWorkqueue();
        }
    }

    /*
     * bsdthread_terminate executes on this guest stack.  Dynarmic may still
     * finish the translated block containing the SVC after the callback asks
     * it to halt, and draining the host autorelease pool above may re-enter
     * guest destructors on the same worker.  Release the stack only after
     * both have fully unwound, but before pthread_join can observe exit.
     */
    if (retirementFreeAddress != 0 &&
            retirementFreeSize != 0 &&
            Dynarmic_munmap(
                retirementFreeAddress,
                retirementFreeSize) != 0) {
        fprintf(stderr,
            "LC32: deferred native thread unmap "
            "failed guest-thread=%llu free=0x%x+0x%x "
            "errno=%d\n",
            start->debuggerId,
            retirementFreeAddress,
            retirementFreeSize, errno);
    }

    nativeGuestThreadId = 0;
    nativeGuestThreadRetiring = false;
    nativeGuestRuntime = nullptr;
    runtime->hostMachThread = MACH_PORT_NULL;
    NativeThreadStateOwnerExited(runtime->threadState);

    const auto signalJoinSemaphore = [](
            mach_port_t semaphore, gdb_thread_id_t debuggerId) {
        if (!MACH_PORT_VALID(semaphore)) {
            return;
        }
        const kern_return_t result =
            semaphore_signal_trap(semaphore);
        if (result != KERN_SUCCESS) {
            fprintf(stderr,
                "LC32: native guest-thread=%llu join "
                "semaphore 0x%x failed: 0x%x\n",
                debuggerId, semaphore, result);
        }
    };

    /*
     * A completed one-shot worker otherwise keeps its joinable host pthread
     * and 16 MiB JIT cache until another guest thread is created. Serialize
     * with creation and teardown before deciding ownership: Running means no
     * reaper or destroy pass can have claimed this runtime. A shutdown keeps
     * the existing joinable path so Dynarmic_nativeDestroy can wait for us.
     */
    std::unique_lock<std::mutex> lifecycleLock(
        nativeLifecycleMutex);
    if (nativeLifecycleState == NativeLifecycleState::Running &&
            runtime->hostThreadCreated &&
            pthread_equal(runtime->hostThread, pthread_self())) {
        const int detachResult = pthread_detach(pthread_self());
        if (detachResult == 0) {
            const mach_port_t joinSemaphore = runtime->joinSemaphore;
            const gdb_thread_id_t debuggerId = runtime->debuggerId;
            runtime->joinSemaphore = MACH_PORT_NULL;
            runtime->hostThreadCreated = false;
            DestroyNativeGuestJit(runtime);
            signalJoinSemaphore(joinSemaphore, debuggerId);
            return nullptr;
        }
        fprintf(stderr,
            "LC32: pthread_detach guest-thread=%llu failed: %d (%s)\n",
            runtime->debuggerId, detachResult,
            strerror(detachResult));
    }
    lifecycleLock.unlock();

    {
        std::lock_guard<std::mutex> lock(
            nativeGuestJitMutex);
        runtime->exited = true;
    }
    nativeGuestJitCondition.notify_all();
    if (MACH_PORT_VALID(runtime->joinSemaphore)) {
        signalJoinSemaphore(
            runtime->joinSemaphore, runtime->debuggerId);
        runtime->joinSemaphore = MACH_PORT_NULL;
    }
    return nullptr;
}

bool StartNativeGuestWorkqueueWorker(
        const GuestWorkqueueJob &job) {
    EnsureGuestThreadRegistry();
    if (!NativeGuestThreadsEnabled() ||
            guest_bsdthread_wqthread_start == 0 ||
            guest_bsdthread_pthread_size <= 0 ||
            guest_bsdthread_tsd_offset >=
                static_cast<u32>(guest_bsdthread_pthread_size)) {
        return false;
    }

    std::unique_lock<std::mutex> lifecycleLock(
        nativeLifecycleMutex);
    if (nativeLifecycleState != NativeLifecycleState::Running ||
            nativeShutdownRequested.load(
                std::memory_order_acquire) ||
            guestProcessExitRequested.load(
                std::memory_order_acquire)) {
        return false;
    }
    /* Joining an exited peer here both releases its code cache and makes its
     * processor ID available before this worker reserves another one. */
    ReapExitedNativeGuestJits();

    gdb_thread_id_t debuggerId = 0;
    size_t processorId = 0;
    u32 signalMask = 0;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        debuggerId = guestNextDebuggerThreadId++;
        for (const GuestThreadContext &thread : guestThreads) {
            if (thread.debuggerId == 1 && thread.alive) {
                signalMask = thread.signalMask;
                break;
            }
        }
        for (size_t candidate = 1;
                candidate < MaxNativeGuestProcessors;
                ++candidate) {
            const uint64_t bit = uint64_t{1} << candidate;
            if ((guestProcessorIdsInUse & bit) == 0) {
                guestProcessorIdsInUse |= bit;
                processorId = candidate;
                break;
            }
        }
    }
    if (processorId == 0) {
        return false;
    }
    const auto releaseProcessor = [processorId] {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        guestProcessorIdsInUse &=
            ~(uint64_t{1} << processorId);
    };

    const u64 pthreadSize64 =
        (static_cast<u64>(guest_bsdthread_pthread_size) +
         DYN_PAGE_MASK) & ~static_cast<u64>(DYN_PAGE_MASK);
    if (pthreadSize64 == 0 ||
            pthreadSize64 > UINT32_MAX -
                GuestWorkqueueGuardSize -
                GuestWorkqueueStackSize) {
        releaseProcessor();
        return false;
    }
    const u32 allocationSize =
        GuestWorkqueueGuardSize + GuestWorkqueueStackSize +
        static_cast<u32>(pthreadSize64);
    const u32 allocationAddress = Dynarmic_mmap(
        0, allocationSize, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (allocationAddress == UINT32_MAX) {
        releaseProcessor();
        return false;
    }
    const auto releaseAllocation = [=] {
        (void)Dynarmic_munmap(
            allocationAddress, allocationSize);
    };
    if (Dynarmic_mprotect(
            allocationAddress, GuestWorkqueueGuardSize,
            PROT_NONE) != 0) {
        releaseAllocation();
        releaseProcessor();
        return false;
    }

    const u32 stackBottom =
        allocationAddress + GuestWorkqueueGuardSize;
    const u32 pthreadAddress =
        stackBottom + GuestWorkqueueStackSize;
    const u32 eventList = pthreadAddress -
        static_cast<u32>(GuestWorkqueueEventCapacity *
                         sizeof(guest_kevent_qos_s));
    const u32 messageBuffer = eventList -
        static_cast<u32>(GuestWorkqueueMessageCapacity);
    const u32 stackPointer = (messageBuffer - 16) & ~0xfu;

    const mach_port_t threadPort = AllocateGuestThreadPort();
    if (!MACH_PORT_VALID(threadPort)) {
        releaseAllocation();
        releaseProcessor();
        return false;
    }
    const auto releasePort = [threadPort] {
        (void)mach_port_destroy(
            mach_task_self(), threadPort);
    };

    u32 priority = job.priority;
    u32 eventListArgument = 0;
    u32 eventCount = 0;
    u32 upcallFlags =
        WQ_FLAG_THREAD_NEWSPI | WQ_FLAG_THREAD_TSD_BASE_SET;
    if (job.hasDelivery) {
        guest_kevent_qos_s event = job.delivery.event;
        if (job.delivery.message.size() >
                GuestWorkqueueMessageCapacity) {
            releasePort();
            releaseAllocation();
            releaseProcessor();
            return false;
        }
        if (!job.delivery.message.empty()) {
            if (Dynarmic_mem_1write(
                    messageBuffer, job.delivery.message.size(),
                    reinterpret_cast<char *>(const_cast<uint8_t *>(
                        job.delivery.message.data()))) != 0) {
                releasePort();
                releaseAllocation();
                releaseProcessor();
                return false;
            }
            event.ext[0] = messageBuffer;
            event.ext[1] = job.delivery.message.size();
        }
        if (Dynarmic_mem_1write(
                eventList, sizeof(event),
                reinterpret_cast<char *>(&event)) != 0) {
            releasePort();
            releaseAllocation();
            releaseProcessor();
            return false;
        }
        eventListArgument = eventList;
        eventCount = 1;
        upcallFlags |= WQ_FLAG_THREAD_KEVENT;
        if (job.delivery.eventManager) {
            upcallFlags |= WQ_FLAG_THREAD_EVENT_MANAGER;
        }
    }
    if ((priority & PTHREAD_PRIORITY_OVERCOMMIT_FLAG) != 0) {
        upcallFlags |= WQ_FLAG_THREAD_OVERCOMMIT;
    }
    upcallFlags |= GuestWorkqueueQosClass(priority);

    context32 initial = {};
    initial.cpsr = (guest_bsdthread_wqthread_start & 1) != 0
        ? 0x00000030
        : 0x000001d0;
    initial.regs[Reg::R0] = pthreadAddress;
    initial.regs[Reg::R1] = threadPort;
    initial.regs[Reg::R2] = stackBottom;
    initial.regs[Reg::R3] = eventListArgument;
    initial.regs[Reg::R4] = upcallFlags;
    initial.regs[Reg::R5] = eventCount;
    initial.regs[Reg::SP] = stackPointer;
    initial.regs[Reg::PC] =
        guest_bsdthread_wqthread_start & ~1u;
    initial.uro = pthreadAddress + guest_bsdthread_tsd_offset;

    NativeGuestJit *runtime =
        CreateNativeGuestJit(initial, processorId);
    if (runtime == nullptr) {
        releasePort();
        releaseAllocation();
        releaseProcessor();
        return false;
    }
    runtime->debuggerId = debuggerId;
    runtime->workqueue = true;
    runtime->workqueuePriority = priority;

    GuestThreadContext thread = {};
    thread.debuggerId = debuggerId;
    thread.threadSelfId = AllocateGuestThreadSelfId();
    thread.pthreadAddress = pthreadAddress;
    thread.threadPort = threadPort;
    thread.allocationAddress = allocationAddress;
    thread.allocationSize = allocationSize;
    /* If guest cleanup faults before bsdthread_terminate supplies its range,
     * the host runtime still owns and eventually releases this allocation. */
    thread.retirementFreeAddress = allocationAddress;
    thread.retirementFreeSize = allocationSize;
    thread.saved = initial;
    thread.signalMask = signalMask;
    thread.savedValid = true;
    thread.alive = true;
    thread.runnable = true;
    thread.workqueue = true;
    thread.nativeJit = runtime;
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestThreadMutex);
        guestThreads.push_back(std::move(thread));
    }

    auto *start = new NativeGuestThreadStart{
        .debuggerId = debuggerId,
        .runtime = runtime,
    };
    pthread_t hostThread;
    const int createResult = pthread_create(
        &hostThread, nullptr, RunNativeGuestThread, start);
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
        NativeThreadStateOwnerExited(runtime->threadState);
        DestroyNativeGuestJit(runtime);
        releasePort();
        releaseAllocation();
        return false;
    }
    runtime->hostThread = hostThread;
    runtime->hostThreadCreated = true;
    {
        std::lock_guard<std::mutex> lock(runtime->startMutex);
        runtime->startAllowed = true;
    }
    runtime->startCondition.notify_one();
    fprintf(stderr,
        "LC32: native workqueue guest-thread=%llu pthread=0x%x "
        "port=0x%x pc=0x%x sp=0x%x flags=0x%x\n",
        debuggerId, pthreadAddress, threadPort,
        initial.regs[Reg::PC], initial.regs[Reg::SP],
        upcallFlags);
    return true;
}

u32 GuestBsdthreadCreate(
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
            NativeThreadStateOwnerExited(runtime->threadState);
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

u32 GuestBsdthreadTerminate(
        u32 freeAddress, u32 freeSize, mach_port_t threadPort,
        mach_port_t joinSemaphore) {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread() &&
            !NativeGuestWorkqueueIsCurrent()) {
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
            ValidateGuestMunmapRange(
                freeAddress, freeSize) != 0) {
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
        if (freeAddress != 0 && freeSize != 0) {
            current->retirementFreeAddress = freeAddress;
            current->retirementFreeSize = freeSize;
        }
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
        if (threadHandle.jit != nullptr) {
            /*
             * SVCs are normally serviced after Run() has returned.  Keep the
             * exit halt level-triggered so the JIT cannot execute the syscall
             * epilogue on the stack bsdthread_terminate just released.
             */
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
        if (threadHandle.jit != nullptr) {
            threadHandle.jit->HaltExecution(
                LC32HaltReasonExit);
        }
    } else if (threadHandle.jit != nullptr) {
        /* Run() is usually already stopped for the SVC.  Publish a
         * level-triggered scheduler halt before returning to its loop. */
        threadHandle.jit->HaltExecution(
            LC32HaltReasonWorkqueue);
    }
    return return_with_carry_direct(0, false);
}

void GuestThreadRequestRotation() {
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

bool GuestThreadCanYieldBeforeBlocking() {
    EnsureGuestThreadRegistry();
    if (NativeGuestThreadIsCurrent()) {
        return false;
    }
    return !GuestWorkqueueActiveForCurrentThread() &&
        NextGuestThread() != nullptr;
}

bool GuestThreadYieldBeforeBlocking() {
    if (!GuestThreadCanYieldBeforeBlocking()) {
        return false;
    }
    if (!guestSingleStepping) {
        guestThreadRotationRequested = true;
    }
    return true;
}

bool GuestThreadTransitionPending() {
    if (NativeGuestThreadIsCurrent()) {
        return false;
    }
    return guestThreadRotationRequested;
}

bool HandleGuestThreadTransition() {
    if (NativeGuestThreadIsCurrent()) {
        return false;
    }
    u32 retirementFreeAddress = 0;
    u32 retirementFreeSize = 0;
    {
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
        } else {
            retirementFreeAddress =
                current->retirementFreeAddress;
            retirementFreeSize =
                current->retirementFreeSize;
            current->retirementFreeAddress = 0;
            current->retirementFreeSize = 0;
        }
        LoadGuestContext(next->saved);
        THREAD_TRACE(
            "LC32: switched guest-thread %llu -> %llu pc=0x%x\n",
            guestCurrentThreadId, next->debuggerId,
            threadHandle.jit->Regs()[Reg::PC]);
        guestCurrentThreadId = next->debuggerId;
        guestThreadRotationRequested = false;
        guestThreadCurrentRetiring = false;
    }
    /* The JIT now uses the next thread's stack and register context. */
    if (retirementFreeAddress != 0 &&
            retirementFreeSize != 0 &&
            Dynarmic_munmap(
                retirementFreeAddress,
                retirementFreeSize) != 0) {
        fprintf(stderr,
            "LC32: deferred cooperative thread unmap "
            "failed free=0x%x+0x%x errno=%d\n",
            retirementFreeAddress,
            retirementFreeSize, errno);
    }
    return true;
}

u64 GuestCurrentThreadSelfId() {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread() &&
            !NativeGuestWorkqueueIsCurrent()) {
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

mach_port_t GuestCurrentSyntheticThreadPort() {
    EnsureGuestThreadRegistry();
    if (GuestWorkqueueActiveForCurrentThread() &&
            !NativeGuestWorkqueueIsCurrent()) {
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

int GuestThreadSigmask(
        int how, u32 guestSet, u32 guestOldSet) {
    EnsureGuestThreadRegistry();
    const bool cooperativeWorkqueue =
        GuestWorkqueueActiveForCurrentThread() &&
        !NativeGuestWorkqueueIsCurrent();
    std::recursive_mutex &mutex = cooperativeWorkqueue
        ? guestWorkqueueMutex
        : guestThreadMutex;
    std::lock_guard<std::recursive_mutex> lock(mutex);
    u32 *mask = nullptr;
    if (cooperativeWorkqueue) {
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

bool NativeGuestThreadIsCurrent() {
    return NativeGuestThreadsEnabled() &&
        nativeGuestThreadId != 0;
}

bool NativeGuestWorkqueueIsCurrent() {
    return NativeGuestThreadIsCurrent() &&
        nativeGuestRuntime != nullptr &&
        nativeGuestRuntime->workqueue;
}

void NativeGuestWorkqueueHostBlockEnter() {
    if (!NativeGuestWorkqueueIsCurrent()) {
        return;
    }
    if (nativeGuestWorkqueueHostBlockDepth++ != 0) {
        return;
    }
    nativeGuestRuntime->workqueueHostBlocked.store(
        true, std::memory_order_release);
    nativeGuestRuntime->workqueueCompensationPending.store(
        true, std::memory_order_release);
    /*
     * XNU compensates for a constrained workqueue thread which blocks in the
     * kernel.  Without that compensation a single requested root worker can
     * sleep in libnotify while unrelated dispatch work remains queued.
     */
    (void)PumpGuestWorkqueue();
}

void NativeGuestWorkqueueHostBlockExit() {
    if (!NativeGuestWorkqueueIsCurrent() ||
            nativeGuestWorkqueueHostBlockDepth == 0) {
        return;
    }
    if (--nativeGuestWorkqueueHostBlockDepth == 0) {
        nativeGuestRuntime->workqueueCompensationPending.store(
            false, std::memory_order_release);
        nativeGuestRuntime->workqueueHostBlocked.store(
            false, std::memory_order_release);
    }
}

bool GuestWorkqueueActiveForCurrentThread() {
    if (NativeGuestThreadIsCurrent()) {
        return NativeGuestWorkqueueIsCurrent() ||
            guestWorkqueueOverlayCurrent;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    return guestWorkqueueUpcallActive;
}
