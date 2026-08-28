#include "dynarmic_internal.h"

bool GuestContextTransitionPending() {
    return GuestWorkqueueTransitionPending() ||
        GuestThreadTransitionPending();
}

bool HandleGuestContextTransition() {
    if (GuestWorkqueueTransitionPending()) {
        return HandleGuestWorkqueueTransition();
    }
    return HandleGuestThreadTransition();
}

GuestWorkqueuePumpResult PumpGuestWorkqueue() {
    if (NativeGuestThreadsEnabled()) {
        std::lock_guard<std::mutex> pumpLock(
            guestNativeWorkqueuePumpMutex);
        bool startedWorker = false;
        for (;;) {
            size_t activeWorkers = 0;
            size_t blockedWorkers = 0;
            u32 compensationPriority = 0;
            gdb_thread_id_t compensationThreadId = 0;
            {
                std::lock_guard<std::recursive_mutex> threadLock(
                    guestThreadMutex);
                for (const GuestThreadContext &thread : guestThreads) {
                    if (!thread.alive || !thread.workqueue ||
                            thread.nativeJit == nullptr) {
                        continue;
                    }
                    ++activeWorkers;
                    if (thread.nativeJit->workqueueHostBlocked.load(
                            std::memory_order_acquire)) {
                        ++blockedWorkers;
                        if (compensationThreadId == 0 &&
                                thread.nativeJit->
                                    workqueueCompensationPending.load(
                                        std::memory_order_acquire)) {
                            compensationPriority =
                                thread.nativeJit->workqueuePriority;
                            compensationThreadId = thread.debuggerId;
                        }
                    }
                }
            }
            if (activeWorkers >= MaxNativeGuestWorkqueueWorkers) {
                break;
            }

            GuestWorkqueueJob job;
            bool haveJob = false;
            bool retryJobOnFailure = false;
            {
                std::lock_guard<std::recursive_mutex> workqueueLock(
                    guestWorkqueueMutex);
                if (!guest_workqueue_opened) {
                    break;
                }
                if (!guestNativeWorkqueuePendingJobs.empty()) {
                    job = std::move(
                        guestNativeWorkqueuePendingJobs.front());
                    guestNativeWorkqueuePendingJobs.pop_front();
                    haveJob = true;
                    retryJobOnFailure = true;
                } else {
                    while (!guestWorkqueueRequests.empty() &&
                            guestWorkqueueRequests.front().remaining <= 0) {
                        guestWorkqueueRequests.pop_front();
                    }
                    if (!guestWorkqueueRequests.empty()) {
                        GuestWorkqueueRequest &request =
                            guestWorkqueueRequests.front();
                        job.priority = request.priority;
                        --request.remaining;
                        if (request.remaining <= 0) {
                            guestWorkqueueRequests.pop_front();
                        }
                        haveJob = true;
                        retryJobOnFailure = true;
                    } else {
                        GuestWorkqueueDelivery delivery;
                        if (NextGuestWorkqueueEvent(delivery)) {
                            job.priority = delivery.eventManager
                                ? guestWorkqueueEventManagerPriority
                                : static_cast<u32>(delivery.event.qos);
                            job.delivery = std::move(delivery);
                            job.hasDelivery = true;
                            haveJob = true;
                            retryJobOnFailure = true;
                        } else if (activeWorkers != 0 &&
                                blockedWorkers == activeWorkers &&
                                compensationThreadId != 0) {
                            /* XNU's workqueue scheduler compensates when all
                             * constrained workers are asleep in the kernel.
                             * Enter another root worker even though dispatch
                             * requested only the worker which is now blocked. */
                            job.priority = compensationPriority;
                            haveJob = true;
                        }
                    }
                }
            }
            if (!haveJob) {
                break;
            }

            if (!StartNativeGuestWorkqueueWorker(job)) {
                /* A direct-kevent job may already own a Mach message removed
                 * from its receive right. Keep the complete immutable job in
                 * userspace so a transient JIT/thread failure loses nothing. */
                if (retryJobOnFailure) {
                    std::lock_guard<std::recursive_mutex> workqueueLock(
                        guestWorkqueueMutex);
                    guestNativeWorkqueuePendingJobs.push_front(
                        std::move(job));
                }
                break;
            }
            if (compensationThreadId != 0) {
                std::lock_guard<std::recursive_mutex> threadLock(
                    guestThreadMutex);
                if (GuestThreadContext *blockedThread =
                        FindGuestThread(compensationThreadId, true);
                        blockedThread != nullptr &&
                        blockedThread->workqueue &&
                        blockedThread->nativeJit != nullptr) {
                    blockedThread->nativeJit->
                        workqueueCompensationPending.store(
                            false, std::memory_order_release);
                }
            }
            startedWorker = true;
        }
        return startedWorker
            ? GuestWorkqueuePumpResult::NativeWorkerStarted
            : GuestWorkqueuePumpResult::None;
    }

    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    if (guestWorkqueueUpcallActive || !guest_workqueue_opened) {
        return GuestWorkqueuePumpResult::None;
    }
    /*
     * Allocate the worker before consuming a request or Mach message.  A
     * setup failure must leave the work available for a later attempt.
     */
    if (!EnsureGuestWorkqueueWorker()) {
        return GuestWorkqueuePumpResult::None;
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
            return GuestWorkqueuePumpResult::None;
        }
        --request.remaining;
        return GuestWorkqueuePumpResult::CooperativeTransition;
    }

    GuestWorkqueueDelivery delivery;
    if (!NextGuestWorkqueueEvent(delivery)) {
        return GuestWorkqueuePumpResult::None;
    }
    WORKQUEUE_TRACE(
        "LC32: pumping event ident=0x%llx filter=%d data=0x%llx\n",
        delivery.event.ident, delivery.event.filter,
        static_cast<uint64_t>(delivery.event.data));
    return PrepareGuestWorkqueueUpcall(&delivery, 0)
        ? GuestWorkqueuePumpResult::CooperativeTransition
        : GuestWorkqueuePumpResult::None;
}

bool HandleGuestWorkqueueTransition() {
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
        if (PumpGuestWorkqueue() ==
                GuestWorkqueuePumpResult::CooperativeTransition) {
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
    DynarmicCallbacks32CP15(callbacks)->uro =
        guestWorkqueuePthread + guest_bsdthread_tsd_offset;

    guestWorkqueueWorkerInitialized = true;
    guestWorkqueueUpcallActive = true;
    guestWorkqueueOverlayCurrent = true;
    WORKQUEUE_TRACE(
        "LC32: entered workqueue upcall pc=0x%x self=0x%x "
        "tsd=0x%x flags=0x%x\n",
        jit->Regs()[Reg::PC], guestWorkqueuePthread,
        DynarmicCallbacks32CP15(callbacks)->uro, upcall.flags);
    lock.unlock();
    NativeDebuggerTransferStopOwner(1, 2);
    return true;
}

bool GuestWorkqueueTransitionPending() {
    if (NativeGuestThreadIsCurrent() &&
            CurrentGuestThreadId() != 1) {
        return false;
    }
    std::lock_guard<std::recursive_mutex> lock(
        guestWorkqueueMutex);
    return guestWorkqueuePendingUpcall.valid ||
        guestWorkqueueRestoreRequested;
}
