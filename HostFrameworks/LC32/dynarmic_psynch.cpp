/* nativeGuestWaitMutex must be held by the following rwlock helpers. */
#include "dynarmic_internal.h"

static bool TryHandleNativeGuestRwlockOverlapLocked(
        u32 address, u32 lgen, u32 rwSequence,
        u32 *updateResult) {
    auto overlapIt = std::find_if(
        nativeGuestRwlockOverlaps.begin(),
        nativeGuestRwlockOverlaps.end(),
        [address](const NativeGuestRwlockOverlap &overlap) {
            return overlap.address == address;
        });
    if (overlapIt == nativeGuestRwlockOverlaps.end() ||
            (rwSequence &
                GuestPsynchRwSequenceSavedWriterBit) != 0 ||
            (lgen & GuestPsynchRwWriterBit) != 0 ||
            (!GuestPsynchSequenceLowerOrEqual(
                    rwSequence, overlapIt->nextSequence) &&
             !GuestPsynchSequenceLowerOrEqual(
                    rwSequence, overlapIt->lastSequence))) {
        return false;
    }

    overlapIt->nextSequence += GuestPsynchCountIncrement;
    *updateResult = GuestPsynchCountIncrement |
        (overlapIt->nextSequence & GuestPsynchBitMask) |
        GuestPsynchRwOverlapBit;
    return true;
}

static bool TryGrantNativeGuestRwlockLocked(
        u32 address, u32 *updateResult = nullptr) {
    auto unlockIt = std::find_if(
        nativeGuestRwlockUnlocks.begin(),
        nativeGuestRwlockUnlocks.end(),
        [address](const NativeGuestRwlockUnlock &unlock) {
            return unlock.address == address;
        });
    if (unlockIt == nativeGuestRwlockUnlocks.end()) {
        return false;
    }

    /* Mirror the kernel's find_seq_till gate: an unlock owes
     * expectedWaiters grants, and only waiters whose generation is
     * at-or-before the unlocker's lgen count toward that debt.  Waiters
     * that raced ahead (newer generations) are not owed by this unlock,
     * so they must not trigger it. */
    size_t eligible = 0;
    for (const auto &waiter : nativeGuestWaiters) {
        if (!waiter->signaled &&
                waiter->kind == GuestThreadWaitKind::Rwlock &&
                waiter->address == address &&
                waiter->rwlockWaitType !=
                    GuestRwlockWaitType::None &&
                GuestPsynchSequenceLowerOrEqual(
                    waiter->rwlockSequence, unlockIt->lgen)) {
            eligible++;
        }
    }
    if (eligible < unlockIt->expectedWaiters) {
        return false;
    }

    /* Once the unlock is owed and enough eligible waiters have arrived,
     * every waiter at this address participates in the grant.  Mirror
     * kwq_handle_unlock/ksyn_wakeupreaders: with no writer queued, wake
     * ALL readers regardless of generation; a reader that raced ahead of
     * the unlocker's lgen must still be released. */
    std::vector<std::shared_ptr<NativeGuestWaiter>> waiters;
    for (const auto &waiter : nativeGuestWaiters) {
        if (!waiter->signaled &&
                waiter->kind == GuestThreadWaitKind::Rwlock &&
                waiter->address == address &&
                waiter->rwlockWaitType !=
                    GuestRwlockWaitType::None) {
            waiters.push_back(waiter);
        }
    }
    if (waiters.empty()) {
        return false;
    }

    nativeGuestRwlockOverlaps.erase(std::remove_if(
        nativeGuestRwlockOverlaps.begin(),
        nativeGuestRwlockOverlaps.end(),
        [address](const NativeGuestRwlockOverlap &overlap) {
            return overlap.address == address;
        }), nativeGuestRwlockOverlaps.end());

    std::shared_ptr<NativeGuestWaiter> lowest =
        waiters.front();
    std::shared_ptr<NativeGuestWaiter> lowestWriter;
    for (const auto &waiter : waiters) {
        if (GuestPsynchSequenceLower(
                waiter->rwlockSequence,
                lowest->rwlockSequence)) {
            lowest = waiter;
        }
        if (waiter->rwlockWaitType ==
                    GuestRwlockWaitType::Write &&
                (!lowestWriter || GuestPsynchSequenceLower(
                    waiter->rwlockSequence,
                    lowestWriter->rwlockSequence))) {
            lowestWriter = waiter;
        }
    }

    std::vector<std::shared_ptr<NativeGuestWaiter>> granted;
    if (lowest->rwlockWaitType ==
            GuestRwlockWaitType::Write) {
        granted.push_back(lowest);
    } else {
        for (const auto &waiter : waiters) {
            if (waiter->rwlockWaitType !=
                    GuestRwlockWaitType::Read) {
                continue;
            }
            if (!lowestWriter || GuestPsynchSequenceLower(
                    waiter->rwlockSequence,
                    lowestWriter->rwlockSequence)) {
                granted.push_back(waiter);
            }
        }
    }

    const bool writerGrant = granted.size() == 1 &&
        granted.front()->rwlockWaitType ==
            GuestRwlockWaitType::Write;
    const bool writerRemains = std::any_of(
        nativeGuestWaiters.begin(), nativeGuestWaiters.end(),
        [&granted, address](
                const std::shared_ptr<NativeGuestWaiter> &waiter) {
            return !waiter->signaled &&
                waiter->kind == GuestThreadWaitKind::Rwlock &&
                waiter->address == address &&
                waiter->rwlockWaitType ==
                    GuestRwlockWaitType::Write &&
                std::find(granted.begin(), granted.end(), waiter) ==
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
    if (!writerGrant && !writerRemains) {
        nativeGuestRwlockOverlaps.push_back({
            .address = address,
            .lastSequence = unlockIt->rwSequence,
            .nextSequence =
                (unlockIt->rwSequence & GuestPsynchCountMask) +
                update,
        });
    }
    for (const auto &waiter : granted) {
        waiter->wakeResult = update;
        waiter->signaled = true;
        waiter->condition.notify_one();
    }
    if (updateResult != nullptr) {
        *updateResult = update;
    }
    nativeGuestRwlockUnlocks.erase(unlockIt);
    return true;
}

static u32 PostNativeGuestRwlockUnlockLocked(
        u32 address, u32 lgen, u32 ugen, u32 rwSequence) {
    const size_t expected = GuestPsynchSequenceDistance(
        lgen, ugen);
    if (expected == 0) {
        return 0;
    }

    auto unlockIt = std::find_if(
        nativeGuestRwlockUnlocks.begin(),
        nativeGuestRwlockUnlocks.end(),
        [address](const NativeGuestRwlockUnlock &unlock) {
            return unlock.address == address;
        });
    const NativeGuestRwlockUnlock unlock = {
        .address = address,
        .lgen = lgen,
        .rwSequence = rwSequence,
        .expectedWaiters = expected,
    };
    if (unlockIt == nativeGuestRwlockUnlocks.end()) {
        nativeGuestRwlockUnlocks.push_back(unlock);
    } else {
        *unlockIt = unlock;
    }

    u32 update = 0;
    const bool granted =
        TryGrantNativeGuestRwlockLocked(address, &update);
    if (getenv("LC32_DEBUG_RWLOCK")) {
        size_t waiters = 0, writers = 0, readers = 0;
        for (const auto &w : nativeGuestWaiters) {
            if (!w->signaled && w->kind == GuestThreadWaitKind::Rwlock &&
                    w->address == address) {
                waiters++;
                if (w->rwlockWaitType == GuestRwlockWaitType::Write) {
                    writers++;
                } else {
                    readers++;
                }
            }
        }
        fprintf(stderr,
            "LC32 rw debug: unlock addr=0x%x lgen=%x ugen=%x "
            "rw=%x expected=%zu waiters=%zu(read=%zu wr=%zu) "
            "granted=%d update=%x\n",
            address, lgen, ugen, rwSequence, expected,
            waiters, readers, writers, granted ? 1 : 0, update);
        fflush(stderr);
    }
    if (granted) {
        return update;
    }
    /* Apple records the missing waiter generations as a prepost. */
    return lgen;
}

static u32 WaitNativeGuestThread(
        GuestThreadWaitKind kind, u32 address,
        u32 wakeResult,
        u32 mutexSequence = 0,
        bool mutexFirstFit = false,
        GuestRwlockWaitType rwlockWaitType =
            GuestRwlockWaitType::None,
        u32 rwlockSequence = 0,
        u32 rwlockStateSequence = 0,
        u32 conditionSequence = 0,
        u32 conditionSSequence = 0,
        int64_t timeoutSeconds = 0,
        u32 timeoutNanoseconds = 0) {
    const u32 relativeNanoseconds =
        timeoutNanoseconds & 0x3fffffffu;
    const bool hasConditionTimeout =
        kind == GuestThreadWaitKind::Condition &&
        (timeoutSeconds != 0 || relativeNanoseconds != 0);
    if (kind == GuestThreadWaitKind::Condition &&
            (timeoutSeconds < 0 ||
             relativeNanoseconds >= 1000000000u)) {
        return return_with_carry_direct(EINVAL, true);
    }
    NativeGuestWorkqueueHostBlockScope workqueueBlock;
    auto waiter = std::make_shared<NativeGuestWaiter>();
    waiter->kind = kind;
    waiter->address = address;
    waiter->threadPort = GuestCurrentSyntheticThreadPort();
    waiter->wakeResult = wakeResult;
    waiter->mutexSequence = mutexSequence;
    waiter->rwlockWaitType = rwlockWaitType;
    waiter->rwlockSequence = rwlockSequence;
    waiter->conditionSequence = conditionSequence;

    std::unique_lock<std::mutex> lock(nativeGuestWaitMutex);
    if (kind == GuestThreadWaitKind::Rwlock &&
            rwlockWaitType == GuestRwlockWaitType::Read) {
        u32 overlapUpdate = 0;
        if (TryHandleNativeGuestRwlockOverlapLocked(
                address, rwlockSequence,
                rwlockStateSequence, &overlapUpdate)) {
            return return_with_carry_direct(
                static_cast<int>(overlapUpdate), false);
        }
    }
    if (kind == GuestThreadWaitKind::Condition &&
            ConsumeGuestConditionPrepost(
                address, conditionSequence)) {
        return return_with_carry_direct(
            static_cast<int>(GuestPsynchCountIncrement), false);
    }
    if (kind == GuestThreadWaitKind::Mutex &&
            ConsumeGuestMutexPrepost(
                address, mutexSequence, mutexFirstFit)) {
        return return_with_carry_direct(
            static_cast<int>(wakeResult), false);
    }
    waiter->sequence = guestNextWaitSequence.fetch_add(
        1, std::memory_order_relaxed);
    nativeGuestWaiters.push_back(waiter);
    if (kind == GuestThreadWaitKind::Rwlock) {
        (void)TryGrantNativeGuestRwlockLocked(address);
    }
    if (getenv("LC32_DEBUG_RWLOCK") &&
            kind == GuestThreadWaitKind::Rwlock) {
        size_t pendingUnlocks = 0;
        for (const auto &u : nativeGuestRwlockUnlocks) {
            if (u.address == address) pendingUnlocks++;
        }
        fprintf(stderr,
            "LC32 rw debug: wait addr=0x%x type=%d lgen=%x "
            "rw=%x signaled=%d pendingUnlocks=%zu\n",
            address, (int)rwlockWaitType, rwlockSequence,
            rwlockStateSequence, waiter->signaled ? 1 : 0,
            pendingUnlocks);
        fflush(stderr);
    }
    if (!waiter->signaled) {
        lock.unlock();
        workqueueBlock.Enter();
        lock.lock();
    }
    bool timedOut = false;
    auto deadline = std::chrono::steady_clock::time_point::max();
    if (hasConditionTimeout) {
        const auto now = std::chrono::steady_clock::now();
        const auto maximumSeconds =
            std::chrono::duration_cast<std::chrono::seconds>(
                std::chrono::steady_clock::time_point::max() - now);
        if (timeoutSeconds >= maximumSeconds.count()) {
            deadline = std::chrono::steady_clock::time_point::max();
        } else {
            deadline = now + std::chrono::seconds(timeoutSeconds) +
                std::chrono::nanoseconds(relativeNanoseconds);
        }
    }
    while (!waiter->signaled) {
        const auto wakePredicate = [&] {
            return waiter->signaled ||
                NativeThreadStatePauseRequestedForCurrent() ||
                debuggerAllStopRequested.load(
                    std::memory_order_acquire) ||
                nativeShutdownRequested.load(
                    std::memory_order_acquire) ||
                guestProcessExitRequested.load(
                    std::memory_order_acquire);
        };
        if (hasConditionTimeout) {
            if (!waiter->condition.wait_until(
                    lock, deadline, wakePredicate)) {
                timedOut = true;
                break;
            }
        } else {
            waiter->condition.wait(lock, wakePredicate);
        }
        if (waiter->signaled) {
            break;
        }
        const auto pauseStart =
            std::chrono::steady_clock::now();
        lock.unlock();
        (void)NativeThreadStatePauseHostWaitIfNeeded();
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
        if (hasConditionTimeout) {
            deadline += std::chrono::steady_clock::now() -
                pauseStart;
        }
    }
    nativeGuestWaiters.erase(std::remove(
        nativeGuestWaiters.begin(), nativeGuestWaiters.end(),
        waiter), nativeGuestWaiters.end());
    if (timedOut) {
        int error = ETIMEDOUT;
        if (GuestPsynchSequenceDistance(
                conditionSequence, conditionSSequence) <= 1) {
            /* ECVCERORR tells libpthread that this timeout consumed the last
             * outstanding generation, allowing it to reset the CV state. */
            error |= 0x100;
        }
        return return_with_carry_direct(error, true);
    }
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

/* nativeGuestWaitMutex must be held. */
static size_t WakeNativeGuestMutexThreadLocked(
        u32 address, u32 targetSequence, bool firstFit) {
    std::shared_ptr<NativeGuestWaiter> selected;
    for (const auto &waiter : nativeGuestWaiters) {
        if (waiter->signaled ||
                waiter->kind != GuestThreadWaitKind::Mutex ||
                waiter->address != address ||
                (!firstFit &&
                 waiter->mutexSequence != targetSequence)) {
            continue;
        }
        if (!selected || waiter->sequence < selected->sequence) {
            selected = waiter;
        }
    }
    if (!selected) {
        return 0;
    }
    selected->signaled = true;
    selected->condition.notify_one();
    return 1;
}

/* nativeGuestWaitMutex must be held. */
static size_t WakeNativeGuestConditionThreadsLocked(
        u32 address, u32 throughSequence, bool wakeAll,
        mach_port_t targetThread = MACH_PORT_NULL) {
    size_t count = 0;
    for (;;) {
        std::shared_ptr<NativeGuestWaiter> selected;
        for (const auto &waiter : nativeGuestWaiters) {
            if (waiter->signaled ||
                    waiter->kind !=
                        GuestThreadWaitKind::Condition ||
                    waiter->address != address ||
                    !GuestPsynchSequenceLowerOrEqual(
                        waiter->conditionSequence,
                        throughSequence) ||
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
        /* See psynch_cvcontinue: a waiter already present in the kernel
         * receives zero.  Returning INC here would let registered waiters
         * consume the generations reserved for waiters still racing into
         * psynch_cvwait. */
        selected->wakeResult = 0;
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

u32 GuestPsynchMutexWait(
        u32 mutex, u32 mgen, u32 ugen, u32 flags) {
    const u32 lockSequence = mgen & GuestPsynchCountMask;
    const bool firstFit = GuestPsynchMutexIsFirstFit(flags);
    const u32 wakeResult = lockSequence |
        GuestPsynchRwKernelBit | GuestPsynchRwExclusiveBit;
#ifdef LC32_TRACE_PSYNCH_MUTEX
    fprintf(stderr,
        "LC32: psynch_mutexwait tid=%llu addr=%08x "
        "mgen=%08x ugen=%08x flags=%08x policy=%s\n",
        static_cast<unsigned long long>(
            CurrentGuestThreadId()),
        mutex, mgen, ugen, flags,
        firstFit ? "firstfit" : "fairshare");
    fflush(stderr);
#endif
    if (NativeGuestThreadIsCurrent()) {
        return WaitNativeGuestThread(
            GuestThreadWaitKind::Mutex, mutex, wakeResult,
            lockSequence, firstFit);
    }
    if (ConsumeGuestMutexPrepost(
            mutex, lockSequence, firstFit)) {
        return return_with_carry_direct(
            static_cast<int>(wakeResult), false);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Mutex, mutex, wakeResult,
            GuestRwlockWaitType::None, 0, 0,
            lockSequence)) {
        return return_with_carry_direct(0, false);
    }
    return return_with_carry_direct(EINTR, true);
}

u32 GuestPsynchMutexDrop(
        u32 mutex, u32 mgen, u32 ugen, u32 flags) {
    const bool firstFit = GuestPsynchMutexIsFirstFit(flags);
    /* XNU fair-share mutexdrop grants U+1 exactly.  First-fit instead
     * signals the oldest waiter and keeps an address-wide prepost. */
    const u32 targetSequence = firstFit
        ? mgen & GuestPsynchCountMask
        : (ugen + GuestPsynchCountIncrement) &
            GuestPsynchCountMask;
    const bool native = NativeGuestThreadIsCurrent();
    size_t woken;
    if (native) {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        woken = WakeNativeGuestMutexThreadLocked(
            mutex, targetSequence, firstFit);
        if (woken == 0) {
            RecordGuestMutexPrepost(mutex, targetSequence);
        }
    } else {
        woken = WakeGuestMutexThread(
            mutex, targetSequence, firstFit);
    }
    if (!native && woken == 0) {
        RecordGuestMutexPrepost(mutex, targetSequence);
    }
#ifdef LC32_TRACE_PSYNCH_MUTEX
    fprintf(stderr,
        "LC32: psynch_mutexdrop tid=%llu addr=%08x "
        "mgen=%08x ugen=%08x target=%08x flags=%08x "
        "policy=%s action=%s\n",
        static_cast<unsigned long long>(
            CurrentGuestThreadId()),
        mutex, mgen, ugen, targetSequence, flags,
        firstFit ? "firstfit" : "fairshare",
        woken != 0 ? "wake" : "prepost");
    fflush(stderr);
#endif
    return return_with_carry_direct(0, false);
}

u32 GuestPsynchConditionWait(
        u32 condition, u32 conditionSequence,
        u32 conditionSSequence, u32 mutex,
        int64_t timeoutSeconds, u32 timeoutNanoseconds) {
    if (mutex != 0) {
        if (NativeGuestThreadIsCurrent()) {
            (void)WakeNativeGuestThreads(
                GuestThreadWaitKind::Mutex, mutex, false);
        } else {
            (void)WakeGuestThreads(
                GuestThreadWaitKind::Mutex, mutex, false);
        }
    }
    if (NativeGuestThreadIsCurrent()) {
        return WaitNativeGuestThread(
            GuestThreadWaitKind::Condition, condition, 0,
            0, false, GuestRwlockWaitType::None, 0, 0,
            conditionSequence, conditionSSequence,
            timeoutSeconds, timeoutNanoseconds);
    }
    if (ConsumeGuestConditionPrepost(
            condition, conditionSequence)) {
        return return_with_carry_direct(
            static_cast<int>(GuestPsynchCountIncrement), false);
    }
    if (timeoutSeconds != 0 ||
            (timeoutNanoseconds & 0x3fffffffu) != 0) {
        /* Cooperative mode has no independent timer source.  Mirroring the
         * ulock fallback, return a timeout instead of parking forever. */
        int error = ETIMEDOUT;
        if (GuestPsynchSequenceDistance(
                conditionSequence, conditionSSequence) <= 1) {
            error |= 0x100;
        }
        return return_with_carry_direct(error, true);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Condition, condition, 0,
            GuestRwlockWaitType::None, 0,
            conditionSequence)) {
        return return_with_carry_direct(0, false);
    }
    return return_with_carry_direct(EINTR, true);
}

u32 GuestPsynchConditionSignal(
        u32 condition, u32 conditionSequence,
        u32 conditionSSequence, u32 conditionUOrDifference,
        mach_port_t targetThread, bool broadcast) {
    const u32 throughSequence =
        conditionSequence & GuestPsynchCountMask;
    const size_t outstanding = GuestPsynchSequenceDistance(
        conditionSequence, conditionSSequence);
    const bool native = NativeGuestThreadIsCurrent();
    size_t woken;
    if (native) {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        woken = WakeNativeGuestConditionThreadsLocked(
            condition, throughSequence, broadcast,
            targetThread);
        if (!MACH_PORT_VALID(targetThread)) {
            if (broadcast) {
                const size_t missing = outstanding > woken
                    ? outstanding - woken : 0;
                RecordGuestConditionBroadcastPrepost(
                    condition, throughSequence, missing);
            } else if (woken == 0) {
                RecordGuestConditionSignalPrepost(
                    condition, throughSequence);
            }
        }
    } else {
        woken = WakeGuestConditionThreads(
            condition, throughSequence, broadcast,
            targetThread);
    }
    if (MACH_PORT_VALID(targetThread) && woken == 0) {
        return return_with_carry_direct(ESRCH, true);
    }
    bool hasPrepost = false;
    if (!native && !MACH_PORT_VALID(targetThread)) {
        if (broadcast) {
            const size_t missing = outstanding > woken
                ? outstanding - woken : 0;
            RecordGuestConditionBroadcastPrepost(
                condition, throughSequence, missing);
            hasPrepost = missing != 0;
        } else if (woken == 0) {
            RecordGuestConditionSignalPrepost(
                condition, throughSequence);
            hasPrepost = true;
        }
    } else if (!MACH_PORT_VALID(targetThread)) {
        hasPrepost = broadcast
            ? outstanding > woken
            : woken == 0;
    }
    const u64 update =
        static_cast<u64>(woken) * GuestPsynchCountIncrement;
    u32 updateBits = static_cast<u32>(std::min<u64>(
        update, GuestPsynchCountMask));
    if (hasPrepost) {
        updateBits |= 0x02u; /* PTH_RWS_CV_PBIT */
    } else if (outstanding != 0 && woken >= outstanding) {
        updateBits |= 0x01u; /* PTH_RWS_CV_CBIT */
    }
    (void)conditionUOrDifference;
    return return_with_carry_direct(
        static_cast<int>(updateBits), false);
}

u32 GuestPsynchRwWait(
        u32 rwlock, u32 lgen, u32 rwSequence,
        bool write) {
    const GuestRwlockWaitType waitType = write
        ? GuestRwlockWaitType::Write
        : GuestRwlockWaitType::Read;
    if (NativeGuestThreadIsCurrent()) {
        return WaitNativeGuestThread(
            GuestThreadWaitKind::Rwlock, rwlock, 0,
            0, false, waitType, lgen, rwSequence);
    }
    if (ParkCurrentGuestThread(
            GuestThreadWaitKind::Rwlock, rwlock, 0,
            waitType, lgen)) {
        return return_with_carry_direct(0, false);
    }
    return return_with_carry_direct(EINTR, true);
}

u32 GuestPsynchRwUnlock(
        u32 rwlock, u32 lgen, u32 ugen,
        u32 rwSequence) {
    if (NativeGuestThreadIsCurrent()) {
        std::lock_guard<std::mutex> lock(nativeGuestWaitMutex);
        return return_with_carry_direct(
            static_cast<int>(PostNativeGuestRwlockUnlockLocked(
                rwlock, lgen, ugen, rwSequence)), false);
    }
    size_t woken = 0;
    const u32 update = GrantCooperativeGuestRwlockThreads(
        rwlock, &woken);
    if (woken == 0) {
        /* Cooperative threads cannot race into their wait SVC while another
         * guest thread is executing, so no rwlock prepost is necessary. */
        return return_with_carry_direct(
            static_cast<int>(lgen), false);
    }
    return return_with_carry_direct(
        static_cast<int>(update), false);
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

u32 GuestUlockWait(
        u32 operation, u32 address, u64 value, u32 timeout) {
    const uint8_t opcode =
        static_cast<uint8_t>(operation & GuestUlOpcodeMask);
    const u32 flags = operation & ~GuestUlOpcodeMask;
    if (!GuestUlockOpcodeValid(opcode) ||
            (flags & ~GuestUlfWaitMask) != 0) {
        return GuestUlockReturn(EINVAL, flags);
    }

    if (NativeGuestThreadIsCurrent()) {
        NativeGuestWorkqueueHostBlockScope workqueueBlock;
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
        lock.unlock();
        workqueueBlock.Enter();
        lock.lock();
        bool woke = true;
        auto deadline = std::chrono::steady_clock::now() +
            std::chrono::microseconds(timeout);
        while (!waiter->signaled) {
            if (timeout == 0) {
                waiter->condition.wait(lock, [&] {
                    return waiter->signaled ||
                        NativeThreadStatePauseRequestedForCurrent() ||
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
                            NativeThreadStatePauseRequestedForCurrent() ||
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
            (void)NativeThreadStatePauseHostWaitIfNeeded();
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

u32 GuestUlockWake(
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
