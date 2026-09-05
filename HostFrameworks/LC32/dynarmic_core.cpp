#include "dynarmic_internal.h"

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
    for (;;) {
        Dynarmic::HaltReason reason;
        {
            GuestVmEpochGuard guard(
                CurrentGuestVmEpochParticipant());
            reason = jit->Run();
        }
        if (!!reason ||
                NativeThreadStatePauseRequestedForCurrent()) {
            return reason;
        }
        /* Cycle-budget expiration is an internal scheduling boundary. */
    }
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
    DynarmicCallbacks32UserCallbacks(
        threadHandle.cb)->CallSVC(0x80);
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
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    ConfigureGuestMemoryWatch();
#endif
    ResetGuestCallbackExecutor();
    ResetNativeThreadStateSlot(mainNativeThreadState);

    sharedHandle.memory = kh_init(memory);
    if(sharedHandle.memory == NULL) {
        fprintf(stderr, "kh_init memory failed\n");
        abort();
        return 0;
    }
    InvalidateGuestMemoryLookupCaches();
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
        DynarmicCallbacks32 *callbacks =
            CreateDynarmicCallbacks32(sharedHandle.memory);

        Dynarmic::A32::UserConfig config;
        config.callbacks =
            DynarmicCallbacks32UserCallbacks(callbacks);
        config.coprocessors[15] = DynarmicCallbacks32CP15(callbacks);
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
            DynarmicCallbacks32SetPageTable(
                callbacks,
                sharedHandle.num_page_table_entries,
                sharedHandle.page_table);

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
        DynarmicCallbacks32BindJit(
            callbacks, threadHandle.jit,
            threadHandle.cpsr);
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
        StopGuestCallbackExecutor();
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
    StopGuestCallbackExecutor();

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
    CloseAllGuestAesFileDescriptors();

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
    DestroyDynarmicCallbacks32(cb);
    delete sharedHandle.fs;
    sharedHandle.fs = nullptr;

    {
        std::lock_guard<std::recursive_mutex> lock(
            guestVmMutex);
        khash_t(memory) *memory = sharedHandle.memory;
        if (memory != nullptr) {
            InvalidateGuestMemoryLookupCaches();
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
            /*
             * The main-thread entry names the borrowed port returned by
             * pthread_mach_thread_np().  All other registry ports are
             * synthetic receive rights allocated by AllocateGuestThreadPort.
             * Destroying the borrowed pthread port violates its Mach-port
             * guard on iOS (EXC_GUARD/GUARD_EXC_MOD_REFS).
             */
            if (thread.debuggerId != 1 &&
                    MACH_PORT_VALID(thread.threadPort)) {
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
        nativeGuestRwlockUnlocks.clear();
        nativeGuestRwlockOverlaps.clear();
    }
    {
        std::lock_guard<std::mutex> lock(
            guestPsynchPrepostMutex);
        guestMutexPreposts.clear();
        guestConditionPreposts.clear();
    }
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        guestNativeWorkqueuePendingJobs.clear();
    }

    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        nativeDebugger.state =
            NativeDebuggerRunState::Disabled;
        nativeDebugger.executingWorkers = 0;
        nativeDebugger.mainExecuting = false;
    }
    nativeGuestThreadId = 0;
    nativeGuestWorkqueueHostBlockDepth = 0;
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

static int ValidateGuestMunmapRangeLocked(
        u64 address, u64 size) {
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
    return 0;
}

int ValidateGuestMunmapRange(
        u64 address, u64 size) {
    std::lock_guard<std::recursive_mutex> lock(
        guestVmMutex);
    return ValidateGuestMunmapRangeLocked(address, size);
}

int Dynarmic_munmap(u64 address, u64 size) {
    std::unique_lock<std::recursive_mutex> lock(
        guestVmMutex);
    if (ValidateGuestMunmapRangeLocked(address, size) != 0) {
        return -1;
    }
    khash_t(memory) *memory = sharedHandle.memory;
    const u64 end = address + size;

#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    if (GuestMemoryWatchOverlaps(
            address, static_cast<size_t>(size))) {
        const u32 pc = threadHandle.jit != nullptr
            ? threadHandle.jit->Regs()[Reg::PC] : 0;
        const u32 lr = threadHandle.jit != nullptr
            ? threadHandle.jit->Regs()[Reg::LR] : 0;
        fprintf(stderr,
            "LC32 guest memory watch mapping: op=munmap "
            "range=0x%08llx+0x%llx pc=%08x lr=%08x "
            "host_thread=%u\n",
            address, size, pc, lr,
            pthread_mach_thread_np(pthread_self()));
        if (threadHandle.jit != nullptr) {
            u32 framePointer = threadHandle.jit->Regs()[7];
            fprintf(stderr,
                "LC32 guest memory watch munmap frames:");
            for (unsigned frame = 0;
                    frame < 16 && framePointer != 0;
                    ++frame) {
                if ((framePointer & 3) != 0 ||
                        framePointer > UINT32_MAX - 8) {
                    fprintf(stderr, " invalid-fp=%08x", framePointer);
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
                    fprintf(stderr, " unreadable-fp=%08x", framePointer);
                    break;
                }
                fprintf(stderr, " %08x", returnAddress);
                if (nextFramePointer == framePointer) {
                    fprintf(stderr, " cyclic");
                    break;
                }
                framePointer = nextFramePointer;
            }
            fprintf(stderr, "\n");
        }
        LogGuestMemoryWatchConsistencyLocked("before munmap");
    }
#endif

    InvalidateGuestMemoryLookupCaches();
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
    InvalidateGuestMemoryLookupCaches();

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
                GuestPageTablePointer(vaddr, page),
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
        int flags, int fildes, u64 off, u64 mask,
        bool purgable) {
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
    void *mappingAddress = MAP_FAILED;
    if (purgable) {
        /*
         * mmap() creates a non-purgeable VM object. Guest mach_vm_allocate
         * requests carrying VM_FLAGS_PURGABLE therefore need a real Mach VM
         * allocation, otherwise their subsequent vm_purgable_control trap
         * would always fail with KERN_INVALID_ARGUMENT.
         */
        if ((flags & MAP_ANONYMOUS) == 0 || fildes != -1 ||
                aligned_off != 0) {
            errno = EINVAL;
        } else {
            vm_address_t purgableAddress = 0;
            const kern_return_t result = vm_allocate(
                mach_task_self(), &purgableAddress, mappingSize,
                VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE);
            if (result == KERN_SUCCESS) {
                mappingAddress = reinterpret_cast<void *>(
                    purgableAddress);
            } else {
                errno = result == KERN_NO_SPACE ||
                        result == KERN_RESOURCE_SHORTAGE
                    ? ENOMEM : EINVAL;
            }
        }
    } else {
        mappingAddress = mmap(
            NULL, mappingSize, hostProtection,
            flags & ~MAP_FIXED, fildes, aligned_off);
    }
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

#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    if (GuestMemoryWatchOverlaps(
            reservedAddress, static_cast<size_t>(size))) {
        const u32 pc = threadHandle.jit != nullptr
            ? threadHandle.jit->Regs()[Reg::PC] : 0;
        const u32 lr = threadHandle.jit != nullptr
            ? threadHandle.jit->Regs()[Reg::LR] : 0;
        fprintf(stderr,
            "LC32 guest memory watch mapping: op=mmap "
            "range=0x%08llx+0x%llx prot=0x%x flags=0x%x "
            "pc=%08x lr=%08x host_thread=%u\n",
            reservedAddress, size, guestProtection, flags,
            pc, lr, pthread_mach_thread_np(pthread_self()));
    }
#endif

    const u64 end = reservedAddress + size;
    InvalidateGuestMemoryLookupCaches();
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
                GuestPageTablePointer(vaddr, page),
                __ATOMIC_RELEASE);
        } else {
            // 0xffffff80001f0000ULL: 0x10000
        }
        ReleaseMemoryBackingReference(
            oldBacking);

        addr += DYN_PAGE_SIZE;
    }
    reservations.clear();
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    if (GuestMemoryWatchOverlaps(
            reservedAddress, static_cast<size_t>(size))) {
        LogGuestMemoryWatchConsistencyLocked("after mmap");
    }
#endif
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
    InvalidateGuestMemoryLookupCaches();
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
                            protectedPage.address,
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
                    protectedPage.address,
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
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    const u64 originalAddress = address;
    const size_t originalSize = static_cast<size_t>(size);
    u32 oldWatchedValue = 0;
    const bool hadOldWatchedValue =
        GuestMemoryWatchOverlaps(address, originalSize) &&
        SnapshotGuestMemoryWatchLocked(&oldWatchedValue);
#endif
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
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
    LogGuestMemoryWatchWriteLocked(
        "raw", originalAddress, originalSize,
        hadOldWatchedValue, oldWatchedValue);
#endif
    return 0;
}

int ReplaceGuestMemoryRangeWithPrivateCopy(
        u32 address, size_t size, const void *source) {
    if(size == 0) return 0;
    if(source == nullptr || (address & DYN_PAGE_MASK) != 0 ||
            !GuestAddressRangeIsValid32(address, size) ||
            size > SIZE_MAX - DYN_PAGE_MASK) {
        errno = EINVAL;
        return -1;
    }

    const size_t mappedSize =
        (size + DYN_PAGE_MASK) & ~size_t(DYN_PAGE_MASK);
    struct ReplacedPage {
        u32 address;
        t_memory_page page;
    };
    std::vector<ReplacedPage> pages;
    try {
        pages.reserve(mappedSize / DYN_PAGE_SIZE);
    } catch(const std::exception &) {
        errno = ENOMEM;
        return -1;
    }

    std::unique_lock<std::recursive_mutex> lock(guestVmMutex);
    khash_t(memory) *memory = sharedHandle.memory;
    if(memory == nullptr) {
        errno = EFAULT;
        return -1;
    }
    for(size_t offset = 0; offset < mappedSize;
            offset += DYN_PAGE_SIZE) {
        const u64 pageAddress =
            static_cast<u64>(address) + offset;
        const khiter_t iterator = kh_get(
            memory, memory, pageAddress);
        if(iterator == kh_end(memory)) {
            errno = EFAULT;
            return -1;
        }
        t_memory_page page = kh_value(memory, iterator);
        if(page == nullptr || page->addr == nullptr) {
            errno = EFAULT;
            return -1;
        }
        const size_t pageOffset = offset;
        const size_t replacementBytes =
            size - pageOffset < DYN_PAGE_SIZE ?
                size - pageOffset : DYN_PAGE_SIZE;
        if(replacementBytes < DYN_PAGE_SIZE &&
                page->backing != nullptr &&
                (page->backing->hostProtection & PROT_READ) == 0) {
            errno = EACCES;
            return -1;
        }
        try {
            pages.push_back({
                static_cast<u32>(pageAddress), page,
            });
        } catch(const std::exception &) {
            errno = ENOMEM;
            return -1;
        }
    }

    void *privateMapping = mmap(
        nullptr, mappedSize,
        PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if(privateMapping == MAP_FAILED) return -1;

    t_memory_backing privateBacking =
        static_cast<t_memory_backing>(
            calloc(1, sizeof(struct memory_backing)));
    if(privateBacking == nullptr) {
        const int savedErrno = errno;
        (void)munmap(privateMapping, mappedSize);
        errno = savedErrno == 0 ? ENOMEM : savedErrno;
        return -1;
    }

    auto *privateBytes = static_cast<uint8_t *>(privateMapping);
    for(size_t index = 0; index < pages.size(); ++index) {
        const size_t pageOffset = index * DYN_PAGE_SIZE;
        const size_t replacementBytes =
            size - pageOffset < DYN_PAGE_SIZE ?
                size - pageOffset : DYN_PAGE_SIZE;
        const size_t preservedBytes =
            DYN_PAGE_SIZE - replacementBytes;
        if(preservedBytes != 0) {
            memcpy(privateBytes + pageOffset + replacementBytes,
                static_cast<const uint8_t *>(
                    pages[index].page->addr) + replacementBytes,
                preservedBytes);
        }
    }
    memcpy(privateBytes, source, size);

    privateBacking->addr = privateMapping;
    privateBacking->size = mappedSize;
    privateBacking->references = pages.size();
    privateBacking->hostProtection = PROT_READ | PROT_WRITE;

    /* Every replacement page is complete before it becomes visible. Old
     * owned backings use the guest-VM epoch retirement path, so a JIT that
     * already loaded an old direct pointer cannot observe freed memory. */
    InvalidateGuestMemoryLookupCaches();
    for(const ReplacedPage &entry : pages) {
        const u64 pageTableIndex =
            entry.address >> DYN_PAGE_BITS;
        if(sharedHandle.page_table != nullptr &&
                pageTableIndex <
                    sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[pageTableIndex],
                nullptr, __ATOMIC_RELEASE);
        }
    }
    for(size_t index = 0; index < pages.size(); ++index) {
        const ReplacedPage &entry = pages[index];
        t_memory_backing oldBacking = entry.page->backing;
        entry.page->addr = privateBytes + index * DYN_PAGE_SIZE;
        entry.page->backing = privateBacking;
        ReleaseMemoryBackingReference(oldBacking);
    }
    for(const ReplacedPage &entry : pages) {
        const u64 pageTableIndex =
            entry.address >> DYN_PAGE_BITS;
        if(sharedHandle.page_table != nullptr &&
                pageTableIndex <
                    sharedHandle.num_page_table_entries) {
            __atomic_store_n(
                &sharedHandle.page_table[pageTableIndex],
                GuestPageTablePointer(entry.address, entry.page),
                __ATOMIC_RELEASE);
        }
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

bool Dynarmic_guest_tracepoint_set(u64 address) {
    if (address > UINT32_MAX) {
        return false;
    }
    const bool thumb = (address & 1u) != 0;
    const u32 guestAddress = static_cast<u32>(address) & ~1u;
    const size_t kind = thumb
        ? sizeof(uint16_t) : sizeof(uint32_t);

    std::lock_guard<std::mutex> lock(
        guestSoftwareTracepointsMutex);
    for (const GuestSoftwareTracepoint &tracepoint :
         guestSoftwareTracepoints) {
        if (tracepoint.address == guestAddress) {
            return tracepoint.kind == kind;
        }
    }
    for (const DebuggerSoftwareBreakpoint &breakpoint :
         debuggerSoftwareBreakpoints) {
        if (DebuggerRangesOverlap(
                guestAddress, kind,
                breakpoint.address, breakpoint.kind)) {
            return false;
        }
    }

    GuestSoftwareTracepoint tracepoint = {
        .address = guestAddress,
        .kind = kind,
        .original = {},
        .fired = false,
    };
    if (Dynarmic_mem_1read(
            guestAddress, kind,
            reinterpret_cast<char *>(
                tracepoint.original.data())) != 0) {
        return false;
    }

    const uint32_t trap = thumb ? 0xBE00u : 0xE1200070u;
    guestSoftwareTracepoints.push_back(tracepoint);
    if (DebuggerWritePhysicalMemory(
            guestAddress, kind,
            reinterpret_cast<const char *>(&trap)) != 0) {
        guestSoftwareTracepoints.pop_back();
        return false;
    }
    InvalidateAllGuestJits(guestAddress, kind);
    return true;
}

bool ConsumeGuestSoftwareTracepoint(
        u32 pc, Dynarmic::A32::Jit *cpu) {
    const u32 guestAddress = pc & ~1u;
    GuestSoftwareTracepoint tracepoint = {};
    {
        std::lock_guard<std::mutex> lock(
            guestSoftwareTracepointsMutex);
        auto it = std::find_if(
            guestSoftwareTracepoints.begin(),
            guestSoftwareTracepoints.end(),
            [guestAddress](const GuestSoftwareTracepoint &candidate) {
                return candidate.address == guestAddress;
            });
        if (it == guestSoftwareTracepoints.end()) {
            return false;
        }
        if (!it->fired) {
            if (DebuggerWritePhysicalMemory(
                    guestAddress, it->kind,
                    reinterpret_cast<const char *>(
                        it->original.data())) != 0) {
                fprintf(stderr,
                    "LC32 guest tracepoint 0x%08x: failed to restore "
                    "the original instruction\n",
                    guestAddress);
                return false;
            }
            it->fired = true;
        }
        tracepoint = *it;
    }

    // Only the first JIT to arrive owns the trace event.  Keep the fired
    // record as a tombstone: another native guest JIT may already have
    // translated the old BKPT and arrive after the physical bytes were
    // restored but before it processes its queued invalidation.
    static std::mutex loggedTracepointsMutex;
    static std::unordered_set<u32> loggedTracepoints;
    bool shouldLog = false;
    {
        std::lock_guard<std::mutex> lock(loggedTracepointsMutex);
        shouldLog = loggedTracepoints.insert(guestAddress).second;
    }
    if (shouldLog) {
        const auto &registers = cpu->Regs();
        fprintf(stderr,
            "LC32 guest tracepoint 0x%08x "
            "r0=%08x r1=%08x r2=%08x r3=%08x "
            "sp=%08x lr=%08x cpsr=%08x host_thread=%u\n",
            guestAddress,
            registers[Reg::R0], registers[Reg::R1],
            registers[Reg::R2], registers[Reg::R3],
            registers[Reg::SP], registers[Reg::LR], cpu->Cpsr(),
            pthread_mach_thread_np(pthread_self()));
        std::array<u32, 10> r0Words = {};
        if (registers[Reg::R0] != 0 &&
                Dynarmic_mem_1read(
                    registers[Reg::R0], sizeof(r0Words),
                    reinterpret_cast<char *>(r0Words.data())) == 0) {
            fprintf(stderr,
                "LC32 guest tracepoint 0x%08x r0_words="
                "%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x\n",
                guestAddress,
                r0Words[0], r0Words[1], r0Words[2], r0Words[3],
                r0Words[4], r0Words[5], r0Words[6], r0Words[7],
                r0Words[8], r0Words[9]);

#ifdef LC32_TRACE_GUEST_TRACEPOINT_ISA
            std::array<u32, 8> r0IsaWords = {};
            if (r0Words[0] != 0 &&
                    Dynarmic_mem_1read(
                        r0Words[0], sizeof(r0IsaWords),
                        reinterpret_cast<char *>(
                            r0IsaWords.data())) == 0) {
                fprintf(stderr,
                    "LC32 guest tracepoint 0x%08x r0_isa=%08x "
                    "isa_words=%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x\n",
                    guestAddress, r0Words[0],
                    r0IsaWords[0], r0IsaWords[1],
                    r0IsaWords[2], r0IsaWords[3],
                    r0IsaWords[4], r0IsaWords[5],
                    r0IsaWords[6], r0IsaWords[7]);
            }
#endif
        }
        std::array<u32, 10> r2Words = {};
        if (registers[Reg::R2] != 0 &&
                Dynarmic_mem_1read(
                    registers[Reg::R2], sizeof(r2Words),
                    reinterpret_cast<char *>(r2Words.data())) == 0) {
            fprintf(stderr,
                "LC32 guest tracepoint 0x%08x r2_words="
                "%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x\n",
                guestAddress,
                r2Words[0], r2Words[1], r2Words[2], r2Words[3],
                r2Words[4], r2Words[5], r2Words[6], r2Words[7],
                r2Words[8], r2Words[9]);
        }
        std::array<u32, 6> r3Words = {};
        if (registers[Reg::R3] != 0 &&
                Dynarmic_mem_1read(
                    registers[Reg::R3], sizeof(r3Words),
                    reinterpret_cast<char *>(r3Words.data())) == 0) {
            fprintf(stderr,
                "LC32 guest tracepoint 0x%08x r3_words="
                "%08x,%08x,%08x,%08x,%08x,%08x\n",
                guestAddress,
                r3Words[0], r3Words[1], r3Words[2],
                r3Words[3], r3Words[4], r3Words[5]);
        }
        std::array<u32, 12> stackWords = {};
        if (registers[Reg::SP] != 0 &&
                Dynarmic_mem_1read(
                    registers[Reg::SP], sizeof(stackWords),
                    reinterpret_cast<char *>(stackWords.data())) == 0) {
            fprintf(stderr,
                "LC32 guest tracepoint 0x%08x stack_words="
                "%08x,%08x,%08x,%08x,%08x,%08x,%08x,%08x,"
                "%08x,%08x,%08x,%08x\n",
                guestAddress,
                stackWords[0], stackWords[1], stackWords[2],
                stackWords[3], stackWords[4], stackWords[5],
                stackWords[6], stackWords[7], stackWords[8],
                stackWords[9], stackWords[10], stackWords[11]);
        }
    }

    // Dynarmic reports the PC after executing BKPT.  Replay the instruction
    // that the tracepoint temporarily replaced, and force every guest JIT to
    // discard translations that contain the trap.
    cpu->Regs()[Reg::PC] = guestAddress;
    InvalidateAllGuestJits(
        guestAddress, tracepoint.kind);
    return true;
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

    {
        std::lock_guard<std::mutex> lock(
            guestSoftwareTracepointsMutex);
        for (const GuestSoftwareTracepoint &tracepoint :
             guestSoftwareTracepoints) {
            if (DebuggerRangesOverlap(
                    guestAddress, kind,
                    tracepoint.address,
                    tracepoint.kind)) {
                return false;
            }
        }
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

/*
 * A software breakpoint is physical guest code patched with BKPT.  Leaving
 * the debugger must therefore be transactional with respect to execution:
 * restore every reachable site while the target is still all-stop, retain
 * failed records so the caller can refuse to run with a planted trap, and
 * invalidate every JIT which may have translated either byte sequence.
 */
bool Dynarmic_debugger_remove_all_breakpoints() {
    bool restoredAll = true;
    for (auto it = debuggerSoftwareBreakpoints.begin();
         it != debuggerSoftwareBreakpoints.end();) {
        if (DebuggerWritePhysicalMemory(
                it->address, it->kind,
                reinterpret_cast<const char *>(
                    it->original.data())) != 0) {
            restoredAll = false;
            ++it;
            continue;
        }
        InvalidateAllGuestJits(it->address, it->kind);
        it = debuggerSoftwareBreakpoints.erase(it);
    }
    return restoredAll && debuggerSoftwareBreakpoints.empty();
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
            DynarmicCallbacks32Jit(sharedHandle.cb) == nullptr) {
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
                ? DynarmicCallbacks32Jit(sharedHandle.cb)
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
                    ? DynarmicCallbacks32Jit(sharedHandle.cb)
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
                ? DynarmicCallbacks32Jit(sharedHandle.cb)
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
                    (thread.nativeJit->debuggerHostWaitPaused ||
                     thread.nativeJit->debuggerHostCallQuiescent)) {
                /*
                 * The stopped host callback has not copied its syscall or
                 * selector result back to the JIT register file yet. Reject
                 * writes instead of reporting success and silently
                 * overwriting them on resume.
                 */
                return false;
            }
            jit = thread_id == 1
                ? (sharedHandle.cb != nullptr
                    ? DynarmicCallbacks32Jit(sharedHandle.cb)
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
      DynarmicCallbacks32CP15(cb).get()->uro = value;
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
        if (ConsumeNativeThreadStateHalt(reason) && !reason) {
          continue;
        }
        if (Dynarmic::Has(
                reason, Dynarmic::HaltReason::CacheInvalidation)) {
          reason = reason &
              ~Dynarmic::HaltReason::CacheInvalidation;
          if (!reason) {
            continue;
          }
        }
        if (Dynarmic::Has(reason, LC32HaltReasonWorkqueue)) {
          const bool transitionPending =
              GuestContextTransitionPending();
          if (transitionPending &&
                  !HandleGuestContextTransition()) {
            reason = LC32HaltReasonTrap;
            break;
          }
          /*
           * HaltExecution is level-triggered. A native guest worker can
           * prepare a workqueue upcall and halt the main JIT while the main
           * thread is inside an SVC callback. ServiceGuestSVC installs that
           * upcall before Run() observes the halt, leaving a stale
           * Workqueue bit behind. It is only an error when a transition is
           * still pending but cannot be applied.
           */
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
        if (nativeGuestThreadRetiring) {
          reason = LC32HaltReasonExit;
          break;
        }
      }
    } else {
      return LC32HaltReasonTrap;
    }
  if (!nativeGuestThreadRetiring) {
    UpdateGuestStopSignalForHalt(reason);
  }
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
        if (nativeGuestThreadRetiring) {
            return LC32HaltReasonExit;
        }
        if (!NativeDebuggerMainContextMayRun()) {
            reason = Dynarmic::HaltReason::Step;
            UpdateGuestStopSignalForHalt(reason);
            return reason;
        }
    }
    for (;;) {
        reason = RunGuestJit(jit);
        if (ConsumeNativeThreadStateHalt(reason) && !reason) {
            continue;
        }
        if (Dynarmic::Has(
                reason, Dynarmic::HaltReason::CacheInvalidation)) {
            reason = reason &
                ~Dynarmic::HaltReason::CacheInvalidation;
            if (!reason) {
                continue;
            }
        }
        if (Dynarmic::Has(reason, LC32HaltReasonWorkqueue)) {
            const bool transitionPending =
                GuestContextTransitionPending();
            if (transitionPending &&
                    !HandleGuestContextTransition()) {
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
        if (nativeGuestThreadRetiring) {
            reason = LC32HaltReasonExit;
            break;
        }
        if (!NativeDebuggerMainContextMayRun()) {
            reason = Dynarmic::HaltReason::Step;
            break;
        }
    }
    if (!nativeGuestThreadRetiring) {
        UpdateGuestStopSignalForHalt(reason);
    }
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
        reason = nativeGuestThreadRetiring
            ? LC32HaltReasonExit
            : Dynarmic::HaltReason::Step;
        guestSingleStepping = false;
        if (!nativeGuestThreadRetiring) {
            UpdateGuestStopSignalForHalt(reason);
        }
        return reason;
    }
    for (;;) {
        reason = drainInternalWorker
            ? RunGuestJit(jit)
            : StepGuestJit(jit);
        if (ConsumeNativeThreadStateHalt(reason) && !reason) {
            continue;
        }
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
            const bool transitionPending =
                GuestContextTransitionPending();
            if (transitionPending &&
                    !HandleGuestContextTransition()) {
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
            if (!transitionPending) {
                continue;
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
        if (nativeGuestThreadRetiring) {
            reason = LC32HaltReasonExit;
            break;
        }
        if (!NativeDebuggerMainContextMayRun()) {
            reason = Dynarmic::HaltReason::Step;
            break;
        }
    }
    guestSingleStepping = false;
    if (!nativeGuestThreadRetiring) {
        UpdateGuestStopSignalForHalt(reason);
    }
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

bool Dynarmic_debugger_begin_main_callback_stop(
        Dynarmic::HaltReason reason) {
    /*
     * The normal protocol owner is synchronously below Dynarmic_emu_resume()
     * on this same host thread.  Completing the stop here is safe only for
     * the shared main JIT.  A native worker doing this would wait for its own
     * executingWorkers acknowledgement and deadlock, as well as compete for
     * the single RSP packet queue.
     */
    if (!NativeDebuggerActive() ||
            threadHandle.jit == nullptr ||
            sharedHandle.cb == nullptr ||
            threadHandle.jit != DynarmicCallbacks32Jit(sharedHandle.cb)) {
        return false;
    }

    NativeDebuggerRunState state;
    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        state = nativeDebugger.state;
    }
    if (state != NativeDebuggerRunState::Running &&
            state != NativeDebuggerRunState::Stopping) {
        return false;
    }
    if (state == NativeDebuggerRunState::Running) {
        (void)NativeDebuggerRequestStop(
            ActiveMainDebuggerThread(), reason);
    }
    (void)NativeDebuggerCompleteStop();

    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        if (!NativeDebuggerActive() ||
                nativeDebugger.state !=
                    NativeDebuggerRunState::Stopped) {
            return false;
        }
    }
    ++nativeDebuggerMainCallbackStopDepth;
    return true;
}

void Dynarmic_debugger_end_main_callback_stop() {
    if (nativeDebuggerMainCallbackStopDepth != 0) {
        --nativeDebuggerMainCallbackStopDepth;
    }
}

void Dynarmic_debugger_request_main_callback_step_out() {
    if (!NativeDebuggerActive() ||
            threadHandle.jit == nullptr ||
            sharedHandle.cb == nullptr ||
            threadHandle.jit != DynarmicCallbacks32Jit(sharedHandle.cb)) {
        return;
    }
    (void)NativeDebuggerRequestStop(
        ActiveMainDebuggerThread(),
        Dynarmic::HaltReason::Step,
        SIGTRAP, false);
}

void Dynarmic_debugger_request_main_session_unwind() {
    if (threadHandle.jit == nullptr ||
            sharedHandle.cb == nullptr ||
            threadHandle.jit != DynarmicCallbacks32Jit(sharedHandle.cb)) {
        return;
    }
    debuggerSessionUnwindRequested.store(
        true, std::memory_order_release);
    /* Planted only after the stopped reverse callback has run through its
     * normal return and the outer register context has been restored. */
    threadHandle.jit->HaltExecution(
        LC32HaltReasonDebuggerPause);
    if (void (*notifier)(void) =
            debuggerStopRunLoopNotifier.load(
                std::memory_order_acquire)) {
        notifier();
    }
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
        if (nativeDebuggerMainCallbackStopDepth != 0 &&
                Dynarmic::Has(
                    reason,
                    LC32HaltReasonRetFromGuest)) {
            /* The preserved host caller, not the all-stop coordinator, owns
             * this private callback boundary.  Keep the coordinator Running
             * and let the nested protocol frame return without a fake stop. */
            return reason;
        }
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
    uint64_t commandGeneration;
    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        commandGeneration = nativeDebugger.generation;
    }
    if (runMain) {
        const gdb_thread_id_t mainOwner =
            ActiveMainDebuggerThread();
        if (NativeDebuggerRepublishPendingStop(
                mainOwner)) {
            return NativeDebuggerCompleteStop();
        }
        Dynarmic::HaltReason reason =
            stepMain
            ? Dynarmic_emu_1step()
            : Dynarmic_emu_1resume();
        if (nativeDebuggerMainCallbackStopDepth != 0 &&
                Dynarmic::Has(
                    reason,
                    LC32HaltReasonRetFromGuest)) {
            return reason;
        }

        bool enforceOriginalStep = stepMain;
        if (stepMain) {
            const gdb_thread_id_t mainOwner =
                ActiveMainDebuggerThread();
            bool commandSuperseded;
            bool latestCommandRunsMain;
            {
                std::lock_guard<std::mutex> lock(
                    nativeDebugger.mutex);
                commandSuperseded =
                    nativeDebugger.generation !=
                        commandGeneration;
                latestCommandRunsMain =
                    nativeDebugger.state ==
                        NativeDebuggerRunState::Running &&
                    NativeDebuggerRunsThreadLocked(
                        mainOwner);
            }
            if (commandSuperseded) {
                /* A nested callback stop serviced a newer c/s command while
                 * this old step frame was inside its host call.  Never
                 * publish the old step's fallback stop after a nested c. */
                enforceOriginalStep = false;
                const Dynarmic::HaltReason visible =
                    NativeDebuggerVisibleReason(reason);
                if (latestCommandRunsMain &&
                        (!visible || visible ==
                            Dynarmic::HaltReason::Step)) {
                    reason = Dynarmic_emu_1resume();
                    if (nativeDebuggerMainCallbackStopDepth != 0 &&
                            Dynarmic::Has(
                                reason,
                                LC32HaltReasonRetFromGuest)) {
                        return reason;
                    }
                }
            }
        }
        const Dynarmic::HaltReason visibleReason =
            NativeDebuggerVisibleReason(reason);
        if (!!visibleReason || enforceOriginalStep) {
            const gdb_thread_id_t owner =
                ActiveMainDebuggerThread();
            (void)NativeDebuggerRequestStop(
                owner,
                !!visibleReason
                    ? visibleReason
                    : Dynarmic::HaltReason::Step);
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

void Dynarmic_emu_1set_1debugger_1enabled(bool enabled) {
    /* A fresh enable or the outer owner's final disable consumes any
     * callback-terminal request left for the UIKit run-loop shim. */
    debuggerSessionUnwindRequested.store(
        false, std::memory_order_release);
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
        NotifyGuestCallbackExecutorWaiter();
        return;
    }
    if (enabled) {
        guestDebuggerEnabled.store(
            true, std::memory_order_release);
        return;
    }

    if (NativeGuestThreadsEnabled()) {
        /*
         * Debugger all-stop is level-triggered on every JIT.  A worker which
         * parked without re-entering Run() still owns the pause bit, so clear
         * it while guestDebuggerEnabled keeps all workers behind the stopped
         * coordinator.  Only then publish Disabled and release them; raw
         * post-detach resume must not immediately rediscover the old stop.
         */
        ClearAllGuestJitHalts(
            LC32HaltReasonDebuggerPause);
    }
    {
        std::lock_guard<std::mutex> lock(
            nativeDebugger.mutex);
        if (nativeDebugger.state !=
                NativeDebuggerRunState::ShuttingDown) {
            nativeDebugger.state =
                NativeDebuggerRunState::Disabled;
        }
        nativeDebugger.mainExecuting = false;
        debuggerInterruptRequested.store(
            false, std::memory_order_release);
        debuggerAllStopRequested.store(
            false, std::memory_order_release);
        /* Final release: worker predicates may run after this store. */
        guestDebuggerEnabled.store(
            false, std::memory_order_release);
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
    Dynarmic::A32::Jit *jit =
        DynarmicCallbacks32Jit(callbacks);
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
    DynarmicCallbacks32CP15(cb).get()->uro = ctx->uro;
    NativeGuestCallbackRegisterAccessEnd();
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_save
 * Signature: (JJ)V
 */
void Dynarmic_context_1save(t_context32 ctx) {
    NativeGuestCallbackRegisterAccessBegin();
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    ctx->regs = jit->Regs();
    ctx->extRegs = jit->ExtRegs();
    ctx->cpsr = jit->Cpsr();
    ctx->fpscr = jit->Fpscr();

    DynarmicCallbacks32 *cb = threadHandle.cb;
    ctx->uro = DynarmicCallbacks32CP15(cb).get()->uro;
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
