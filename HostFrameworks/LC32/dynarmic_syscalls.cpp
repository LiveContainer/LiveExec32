#include "dynarmic_internal.h"
#include "dynarmic_syscalls.h"
#include "darwin_file_syscalls.h"

#include <poll.h>

extern "C" kern_return_t host_get_io_main(
    host_t host, io_main_t *io_main) __attribute__((weak_import));
extern "C" kern_return_t host_get_io_master(
    host_t host, io_main_t *io_main) __attribute__((weak_import));

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

/*
 * A guest size_t is 32 bits while the native sysctl ABI uses a 64-bit
 * size_t.  In particular, the standard two-call query pattern first passes
 * oldp == NULL and expects *oldlenp to be updated.  Keep the two sizes in
 * separate storage and copy the result back even when no output buffer was
 * supplied.
 */
static constexpr size_t LC32MaximumSysctlStagingBytes = 16 * 1024 * 1024;

struct GuestSysctlStorage {
    u32 guestOldCapacity = 0;
    size_t hostOldCapacity = 0;
    size_t hostOldLength = 0;
    std::vector<char> hostOldBytes;
    std::vector<char> hostNewBytes;
};

static int PrepareGuestSysctlStorage(
        u32 guest_oldp, u32 guest_oldlenp,
        u32 guest_newp, size_t newlen,
        GuestSysctlStorage &storage) {
    if(guest_oldp) {
        if(!guest_oldlenp || Dynarmic_mem_1read(
                guest_oldlenp, sizeof(storage.guestOldCapacity),
                reinterpret_cast<char *>(&storage.guestOldCapacity)) != 0) {
            return EFAULT;
        }

        /*
         * Do not let a corrupt 32-bit capacity force a multi-gigabyte native
         * allocation.  Passing the bounded capacity to the kernel preserves
         * the normal ENOMEM/required-length result for genuinely larger
         * values while allowing ordinary sysctls to succeed.
         */
        storage.hostOldCapacity = std::min<size_t>(
            storage.guestOldCapacity, LC32MaximumSysctlStagingBytes);
        try {
            storage.hostOldBytes.resize(
                std::max<size_t>(storage.hostOldCapacity, 1));
        } catch(const std::exception &) {
            return ENOMEM;
        }
        storage.hostOldLength = storage.hostOldCapacity;
    }

    if(guest_newp) {
        if(newlen > LC32MaximumSysctlStagingBytes) return ENOMEM;
        try {
            storage.hostNewBytes.resize(std::max<size_t>(newlen, 1));
        } catch(const std::exception &) {
            return ENOMEM;
        }
        if(newlen && Dynarmic_mem_1read(
                guest_newp, newlen, storage.hostNewBytes.data()) != 0) {
            return EFAULT;
        }
    }
    return 0;
}

static int CompleteGuestSysctlStorage(
        int syscallResult, u32 guest_oldp, u32 guest_oldlenp,
        GuestSysctlStorage &storage) {
    if(syscallResult == 0 && guest_oldp) {
        const size_t copyLength = std::min({
            storage.hostOldLength,
            storage.hostOldCapacity,
            static_cast<size_t>(storage.guestOldCapacity),
        });
        if(copyLength && Dynarmic_mem_1write(
                guest_oldp, copyLength,
                storage.hostOldBytes.data()) != 0) {
            return EFAULT;
        }
    }

    if(guest_oldlenp) {
        const bool lengthOverflow = storage.hostOldLength > UINT32_MAX;
        u32 guestOldLength = lengthOverflow
            ? UINT32_MAX : static_cast<u32>(storage.hostOldLength);
        if(Dynarmic_mem_1write(
                guest_oldlenp, sizeof(guestOldLength),
                reinterpret_cast<char *>(&guestOldLength)) != 0) {
            return EFAULT;
        }
        if(lengthOverflow && syscallResult == 0) return EOVERFLOW;
    }
    return 0;
}

int guest___sysctl(u32 guest_name, u_int namelen, u32 guest_oldp,
        u32 guest_oldlenp, u32 guest_newp, size_t newlen) {
    // TODO: fake stuff like CPU architecture and KERN_USRSTACK32
    int host_name[0x10];
    if(namelen > sizeof(host_name) / sizeof(host_name[0])) {
        return return_with_carry_direct(EINVAL, true);
    }
    if(namelen && Dynarmic_mem_1read(
            guest_name, sizeof(int) * namelen,
            reinterpret_cast<char *>(host_name)) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    /*
     * KERN_PROC returns a kinfo_proc whose layout contains pointers, longs,
     * timevals, and other ABI-sized fields.  Forwarding an armv7 caller's
     * 492-byte buffer to the arm64 kernel returns ENOMEM (and copying a
     * native result verbatim would be corrupt even if it fit).  Old crash
     * reporters commonly use KERN_PROC_PID only to inspect p_flag, so stage
     * a native query and publish the stable leading armv7 scalar fields.
     * Keep the rest zero until a consumer needs a complete field-by-field
     * kinfo_proc translation.
     */
    constexpr int GuestCtlKern = 1;
    constexpr int GuestKernProc = 14;
    constexpr int GuestKernProcPid = 1;
    constexpr u32 GuestKinfoProc32Size = 492;
    constexpr size_t GuestExternProcFlagOffset = 16;
    constexpr size_t GuestExternProcStatusOffset = 20;
    constexpr size_t GuestExternProcPidOffset = 24;
    constexpr size_t GuestExternProcOriginalParentPidOffset = 28;
    constexpr int GuestProcessFlagLp64 = 0x00000004;
    constexpr int GuestProcessFlagTraced = 0x00000800;
    if(namelen == 4 && host_name[0] == GuestCtlKern &&
            host_name[1] == GuestKernProc &&
            host_name[2] == GuestKernProcPid && !guest_newp && newlen == 0) {
        if(guest_oldp && !guest_oldlenp) {
            return return_with_carry_direct(EFAULT, true);
        }

        u32 guestCapacity = 0;
        if(guest_oldp && Dynarmic_mem_1read(
                guest_oldlenp, sizeof(guestCapacity),
                reinterpret_cast<char *>(&guestCapacity)) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }

        struct kinfo_proc hostProcess = {};
        size_t hostLength = sizeof(hostProcess);
        const int hostResult = syscallRetCarry(
            SYS_sysctl, host_name, namelen,
            &hostProcess, &hostLength, nullptr, 0, 0);
        if(threadHandle.cpsr->hasCarry()) return hostResult;

        u32 guestLength = hostLength == 0
            ? 0 : GuestKinfoProc32Size;
        if(guest_oldlenp && Dynarmic_mem_1write(
                guest_oldlenp, sizeof(guestLength),
                reinterpret_cast<char *>(&guestLength)) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }
        if(!guest_oldp || guestLength == 0) {
            return return_with_carry_direct(0, false);
        }
        if(guestCapacity < guestLength) {
            return return_with_carry_direct(ENOMEM, true);
        }

        std::array<uint8_t, GuestKinfoProc32Size> guestProcess = {};
        int32_t guestFlags = hostProcess.kp_proc.p_flag &
            ~(GuestProcessFlagLp64 | GuestProcessFlagTraced);
        if(guestDebuggerEnabled.load(std::memory_order_acquire)) {
            guestFlags |= GuestProcessFlagTraced;
        }
        const int32_t guestStatus = hostProcess.kp_proc.p_stat;
        const int32_t guestPid = hostProcess.kp_proc.p_pid;
        const int32_t guestOriginalParentPid = hostProcess.kp_proc.p_oppid;
        memcpy(guestProcess.data() + GuestExternProcFlagOffset,
            &guestFlags, sizeof(guestFlags));
        memcpy(guestProcess.data() + GuestExternProcStatusOffset,
            &guestStatus, sizeof(guestStatus));
        memcpy(guestProcess.data() + GuestExternProcPidOffset,
            &guestPid, sizeof(guestPid));
        memcpy(guestProcess.data() +
            GuestExternProcOriginalParentPidOffset,
            &guestOriginalParentPid, sizeof(guestOriginalParentPid));
        if(Dynarmic_mem_1write(
                guest_oldp, guestProcess.size(),
                reinterpret_cast<char *>(guestProcess.data())) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }
        return return_with_carry_direct(0, false);
    }

    GuestSysctlStorage storage;
    const int prepareError = PrepareGuestSysctlStorage(
        guest_oldp, guest_oldlenp, guest_newp, newlen, storage);
    if(prepareError) return return_with_carry_direct(prepareError, true);

    const int result = syscallRetCarry(SYS_sysctl,
        host_name, namelen,
        guest_oldp ? storage.hostOldBytes.data() : nullptr,
        guest_oldlenp ? &storage.hostOldLength : nullptr,
        guest_newp ? storage.hostNewBytes.data() : nullptr, newlen,
        0);

    const int completionError = CompleteGuestSysctlStorage(
        result, guest_oldp, guest_oldlenp, storage);
    if(completionError)
        return return_with_carry_direct(completionError, true);
    return result;
}

int guest___sysctlbyname(u32 guest_name, u_int namelen, u32 guest_oldp,
        u32 guest_oldlenp, u32 guest_newp, size_t newlen) {
    // TODO: fake stuff like CPU architecture and KERN_USRSTACK32
    std::array<char, PATH_MAX> host_name = {};
    if(namelen >= host_name.size()) {
        return return_with_carry_direct(ENAMETOOLONG, true);
    }
    if(namelen != 0 && !read_guest_memory_with_permissions(
            guest_name, host_name.data(), namelen, PROT_READ)) {
        return return_with_carry_direct(EFAULT, true);
    }

    GuestSysctlStorage storage;
    const int prepareError = PrepareGuestSysctlStorage(
        guest_oldp, guest_oldlenp, guest_newp, newlen, storage);
    if(prepareError) return return_with_carry_direct(prepareError, true);

    const int result = syscallRetCarry(SYS_sysctlbyname,
        host_name.data(), namelen,
        guest_oldp ? storage.hostOldBytes.data() : nullptr,
        guest_oldlenp ? &storage.hostOldLength : nullptr,
        guest_newp ? storage.hostNewBytes.data() : nullptr, newlen,
        0);

    const int completionError = CompleteGuestSysctlStorage(
        result, guest_oldp, guest_oldlenp, storage);
    if(completionError)
        return return_with_carry_direct(completionError, true);
    return result;
}

int guest_getattrlist(u32 guest_path, u32 guest_attrList, u32 guest_attrBuf, size_t attrBufSize, unsigned long options) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    struct attrlist host_attrList;
    Dynarmic_mem_1read(guest_attrList, sizeof(struct attrlist), (char *)&host_attrList);
    char *host_attrBuf = (char *)malloc(attrBufSize);
    int result = syscallRetCarry(SYS_getattrlist, host_path, &host_attrList, host_attrBuf, attrBufSize, options, 0,0);
    Dynarmic_mem_1write(guest_attrBuf, attrBufSize, host_attrBuf);
    free(host_attrBuf);
    return result;
}

int guest_shm_open(u32 guest_name, int oflag, int mode) {
    char host_name[PATH_MAX];
    const int copy_error = LC32CopyGuestCString(
        guest_name, host_name);
    if(copy_error != 0) {
        return return_with_carry_direct(copy_error, true);
    }
    printf("LC32: shm_open %s\n", host_name);
    return syscallRetCarry(SYS_shm_open, host_name, oflag, mode);
}

int     guest_pthread_getugid_np(u32 uid, u32 gid) {
    uid_t host_uid, host_gid;
    int result = pthread_getugid_np(&host_uid, &host_gid);
    Dynarmic_current_user_callbacks()->MemoryWrite32(uid, host_uid);
    Dynarmic_current_user_callbacks()->MemoryWrite32(gid, host_gid);
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
    call.guestThreadId = NativeGuestThreadsEnabled()
        ? CurrentGuestThreadId()
        : 0;
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
        return interruptedBeforeCall();
    }

    call.phase.store(
        DebuggerMachCallPhase::InCall, std::memory_order_release);
    if (stopRequested()) {
        finishCall();
        (void)NativeThreadStatePauseHostWaitIfNeeded();
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
        (void)NativeThreadStatePauseHostWaitIfNeeded();
        (void)NativeDebuggerPauseHostWaitIfNeeded();
    }
    return result;
}

void InterruptDebuggerMachCalls() {
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

/*
 * Wake only the host call which belongs to the guest JIT being sampled.
 * This mirrors the debugger interruption protocol without setting any
 * process-wide debugger flags or disturbing unrelated guest pthreads.
 */
void InterruptNativeThreadStateHostCalls(
        gdb_thread_id_t threadId) {
    constexpr unsigned retryCount = 100;
    constexpr useconds_t retryDelayMicroseconds = 1000;

    for (unsigned attempt = 0; attempt < retryCount; ++attempt) {
        std::vector<std::pair<mach_port_t, bool>> threads;
        size_t activeCalls = 0;
        {
            std::lock_guard<std::mutex> lock(
                debuggerMachCallsMutex);
            for (DebuggerMachCall *call : debuggerMachCalls) {
                if (call == nullptr ||
                        call->guestThreadId != threadId ||
                        !MACH_PORT_VALID(call->thread)) {
                    continue;
                }
                const DebuggerMachCallPhase phase =
                    call->phase.load(std::memory_order_acquire);
                if (phase == DebuggerMachCallPhase::Arming ||
                        phase == DebuggerMachCallPhase::InCall) {
                    ++activeCalls;
                    call->interruptRequested.store(
                        true, std::memory_order_release);
                }
                if (phase == DebuggerMachCallPhase::InCall) {
                    auto existing = std::find_if(
                        threads.begin(), threads.end(),
                        [call](const auto &entry) {
                            return entry.first == call->thread;
                        });
                    if (existing != threads.end()) {
                        existing->second |= call->forceAbort;
                    } else if (mach_port_mod_refs(
                            mach_task_self(), call->thread,
                            MACH_PORT_RIGHT_SEND, 1) == KERN_SUCCESS) {
                        threads.push_back({
                            call->thread, call->forceAbort});
                    }
                }
            }
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
        if (activeCalls == 0 || attempt + 1 == retryCount) {
            return;
        }
        usleep(retryDelayMicroseconds);
    }
}

void DrainDebuggerMachCalls() {
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
        if (PumpGuestWorkqueue() ==
                GuestWorkqueuePumpResult::CooperativeTransition) {
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
        const bool nativeWorkqueueMayBlock =
            NativeGuestWorkqueueIsCurrent() &&
            ((option & MACH_RCV_TIMEOUT) == 0 || timeout != 0);
        if (nativeWorkqueueMayBlock) {
            NativeGuestWorkqueueHostBlockEnter();
        }
        result = debugger_aware_mach_msg(host_header, option, 0, rcv_size,
            rcv_name, timeout, notify);
        if (nativeWorkqueueMayBlock) {
            NativeGuestWorkqueueHostBlockExit();
        }
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
            /*
             * host_info returns a variable-length array of 32-bit integers.
             * Marshal the iOS 10 request and reply explicitly so the guest's
             * CountInOut value is not confused with the zeroed reply storage
             * and so future host SDK wire-layout changes cannot leak into the
             * ARM32 ABI.
             */
            struct __attribute__((packed, aligned(4))) HostInfoRequest32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                host_flavor_t flavor;
                mach_msg_type_number_t host_info_outCnt;
            };
            struct __attribute__((packed, aligned(4))) HostInfoReply32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                kern_return_t RetCode;
                mach_msg_type_number_t host_info_outCnt;
                integer_t host_info_out[68];
            };
            static_assert(sizeof(HostInfoRequest32) == 40,
                "unexpected ARM32 host_info request layout");
            static_assert(offsetof(HostInfoReply32, host_info_out) == 40,
                "unexpected ARM32 host_info reply payload offset");
            static_assert(sizeof(HostInfoReply32) == 312,
                "unexpected ARM32 host_info reply layout");

            const auto writeError = [&](kern_return_t errorCode) {
                if (rcv_size < sizeof(mig_reply_error_t)) {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                    result = MACH_RCV_TOO_LARGE;
                    return;
                }
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = errorCode;
            };

            if (send_size != sizeof(HostInfoRequest32)) {
                writeError(MIG_BAD_ARGUMENTS);
                break;
            }

            const auto request =
                *reinterpret_cast<const HostInfoRequest32 *>(host_header);
            constexpr mach_msg_type_number_t MaxHostInfoCount = 68;
            constexpr mach_msg_type_number_t GuestHostBasicInfoOldCount = 5;
            constexpr mach_msg_type_number_t GuestHostBasicInfoCount = 12;
            static_assert(sizeof(host_basic_info_data_t) /
                    sizeof(integer_t) == GuestHostBasicInfoCount,
                "host HOST_BASIC_INFO layout no longer matches iOS 10");
            if (request.host_info_outCnt > MaxHostInfoCount) {
                writeError(MIG_ARRAY_TOO_LARGE);
                break;
            }
            if (request.flavor == HOST_BASIC_INFO &&
                    request.host_info_outCnt <
                        GuestHostBasicInfoOldCount) {
                /*
                 * XNU accepts the original five-word structure, but leaves
                 * CountInOut and the caller's buffer untouched below that
                 * size.
                 */
                writeError(KERN_FAILURE);
                break;
            }

            std::array<integer_t, MaxHostInfoCount> info = {};
            mach_msg_type_number_t count = request.host_info_outCnt;
            const kern_return_t kr = host_info(
                request.Head.msgh_request_port, request.flavor,
                info.data(), &count);
            if (kr != KERN_SUCCESS) {
                writeError(kr);
                break;
            }
            if (count > MaxHostInfoCount ||
                    count > request.host_info_outCnt) {
                writeError(MIG_ARRAY_TOO_LARGE);
                break;
            }
            if (request.flavor == HOST_BASIC_INFO) {
                const mach_msg_type_number_t expectedCount =
                    request.host_info_outCnt >= GuestHostBasicInfoCount
                    ? GuestHostBasicInfoCount
                    : GuestHostBasicInfoOldCount;
                if (count != expectedCount) {
                    writeError(KERN_FAILURE);
                    break;
                }

                auto *basic = reinterpret_cast<host_basic_info_t>(
                    info.data());
                basic->cpu_type = CPU_TYPE_ARM;
                basic->cpu_subtype = CPU_SUBTYPE_ARM_V7S;
                if (count == GuestHostBasicInfoCount) {
                    basic->cpu_threadtype = CPU_THREADTYPE_NONE;
                }
            }

            const mach_msg_size_t replySize =
                offsetof(HostInfoReply32, host_info_out) +
                sizeof(info[0]) * count;
            if (rcv_size < replySize) {
                host_header->msgh_size = replySize;
                result = MACH_RCV_TOO_LARGE;
                break;
            }

            auto *reply = reinterpret_cast<HostInfoReply32 *>(host_header);
            reply->NDR = NDR_record;
            reply->RetCode = KERN_SUCCESS;
            reply->host_info_outCnt = count;
            if (count != 0) {
                memcpy(reply->host_info_out, info.data(),
                    sizeof(info[0]) * count);
            }
            host_header->msgh_size = replySize;
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
            if(host_get_io_main != nullptr) {
                result = host_get_io_main(
                    Mess->In.Head.msgh_request_port,
                    &Mess->Out.io_main.name);
            } else if(host_get_io_master != nullptr) {
                result = host_get_io_master(
                    Mess->In.Head.msgh_request_port,
                    &Mess->Out.io_main.name);
            } else {
                result = KERN_NOT_SUPPORTED;
            }
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
        case 1000: { // clock_get_time
            /*
             * The clock service port returned by host_get_clock_service is a
             * real host port, but forwarding an iOS 10 MIG request would tie
             * the guest to the host SDK's generated wire declarations.  The
             * clock_get_time request is header-only and its ARM32 reply has a
             * fixed 44-byte layout, so invoke the host API and marshal that
             * stable payload explicitly.
             */
            struct __attribute__((packed, aligned(4))) ClockGetTimeReply32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                kern_return_t RetCode;
                mach_timespec_t cur_time;
            };
            static_assert(sizeof(mach_msg_header_t) == 24,
                "unexpected Mach message header layout");
            static_assert(sizeof(ClockGetTimeReply32) == 44,
                "unexpected 32-bit clock_get_time reply layout");

            if (send_size != sizeof(mach_msg_header_t)) {
                if (rcv_size < sizeof(mig_reply_error_t)) {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                    result = MACH_RCV_TOO_LARGE;
                } else {
                    auto *error = reinterpret_cast<mig_reply_error_t *>(
                        host_header);
                    host_header->msgh_size = sizeof(*error);
                    error->NDR = NDR_record;
                    error->RetCode = MIG_BAD_ARGUMENTS;
                }
                break;
            }
            if (rcv_size < sizeof(ClockGetTimeReply32)) {
                host_header->msgh_size = sizeof(ClockGetTimeReply32);
                result = MACH_RCV_TOO_LARGE;
                break;
            }

            auto *reply = reinterpret_cast<ClockGetTimeReply32 *>(
                host_header);
            mach_timespec_t currentTime = {};
            const kern_return_t kr = clock_get_time(
                host_header->msgh_request_port, &currentTime);
            reply->NDR = NDR_record;
            reply->RetCode = kr;
            if (kr == KERN_SUCCESS) {
                reply->cur_time = currentTime;
                host_header->msgh_size = sizeof(*reply);
            } else {
                host_header->msgh_size = sizeof(mig_reply_error_t);
            }
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
        case 3808: { // vm_copy
            /*
             * vm_map.defs uses vm_address_t/vm_size_t, so the iOS 10
             * armv7 request is narrower than the host SDK's LP64 MIG
             * declaration. The addresses name logical guest memory and
             * therefore cannot be forwarded to the host task's vm_copy.
             */
            struct __attribute__((packed, aligned(4))) VmCopyRequest32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                u32 source_address;
                u32 size;
                u32 dest_address;
            };
            static_assert(sizeof(VmCopyRequest32) == 44,
                "unexpected ARM32 vm_copy request layout");
            static_assert(sizeof(mig_reply_error_t) == 36,
                "unexpected vm_copy reply layout");

            if (send_size != sizeof(VmCopyRequest32)) {
                if (rcv_size < sizeof(mig_reply_error_t)) {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                    result = MACH_RCV_TOO_LARGE;
                } else {
                    auto *error = reinterpret_cast<mig_reply_error_t *>(
                        host_header);
                    host_header->msgh_size = sizeof(*error);
                    error->NDR = NDR_record;
                    error->RetCode = MIG_BAD_ARGUMENTS;
                }
                break;
            }
            if (rcv_size < sizeof(mig_reply_error_t)) {
                host_header->msgh_size = sizeof(mig_reply_error_t);
                result = MACH_RCV_TOO_LARGE;
                break;
            }

            const auto request =
                *reinterpret_cast<const VmCopyRequest32 *>(host_header);
            auto *reply = reinterpret_cast<mig_reply_error_t *>(host_header);
            host_header->msgh_size = sizeof(*reply);
            reply->NDR = NDR_record;
            reply->RetCode =
                request.Head.msgh_request_port == mach_task_self()
                    ? CopyGuestVmMemory(
                        request.source_address,
                        request.dest_address,
                        request.size)
                    : KERN_INVALID_ARGUMENT;
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
        case 3402: { // task_threads
            /*
             * Do not forward this request to the host task. LiveExec32 can
             * multiplex several logical guest pthreads onto one host thread,
             * and native-thread mode still needs to hide emulator-only host
             * threads. Return the ports from the guest thread registry in a
             * 32-bit OOL descriptor instead.
             */
            struct __attribute__((packed, aligned(4))) TaskThreadsReply32 {
                mach_msg_header_t Head;
                mach_msg_body_t Body;
                mach_msg_ool_ports_descriptor32_t act_list;
                NDR_record_t NDR;
                mach_msg_type_number_t act_listCnt;
            };
            static_assert(sizeof(TaskThreadsReply32) == 52,
                "unexpected 32-bit task_threads reply layout");

            if (send_size != sizeof(mach_msg_header_t) &&
                    rcv_size < sizeof(mig_reply_error_t)) {
                host_header->msgh_size = sizeof(mig_reply_error_t);
                result = MACH_RCV_TOO_LARGE;
                break;
            }
            if (send_size != sizeof(mach_msg_header_t)) {
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = MIG_BAD_ARGUMENTS;
                break;
            }
            if (rcv_size < sizeof(TaskThreadsReply32)) {
                host_header->msgh_size = sizeof(TaskThreadsReply32);
                result = MACH_RCV_TOO_LARGE;
                break;
            }

            u32 guestThreadPorts = 0;
            mach_msg_type_number_t threadCount = 0;
            const kern_return_t kr =
                host_header->msgh_request_port == mach_task_self()
                    ? CopyGuestTaskThreadPorts(
                        &guestThreadPorts, &threadCount)
                    : KERN_INVALID_ARGUMENT;
            if (kr != KERN_SUCCESS) {
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = kr;
                break;
            }

            auto *reply = reinterpret_cast<TaskThreadsReply32 *>(
                host_header);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(*reply);
            reply->Body.msgh_descriptor_count = 1;
            reply->act_list = {};
            reply->act_list.address = guestThreadPorts;
            reply->act_list.count = threadCount;
            reply->act_list.deallocate = false;
            reply->act_list.copy = MACH_MSG_PHYSICAL_COPY;
            reply->act_list.disposition = MACH_MSG_TYPE_MOVE_SEND;
            reply->act_list.type = MACH_MSG_OOL_PORTS_DESCRIPTOR;
            reply->NDR = NDR_record;
            reply->act_listCnt = threadCount;
            break;
        }
        case 3405: { // task_info
            /*
             * The task_info payload is an array of natural_t, but forwarding
             * the old request to a current kernel would also forward the
             * current SDK's maximum-sized reply union.  Marshal only the
             * TASK_BASIC_INFO_32 flavor used by 32-bit applications so the
             * guest receives the eight-word layout its MIG stub expects.
             */
            struct __attribute__((packed, aligned(4))) TaskInfoRequest32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                task_flavor_t flavor;
                mach_msg_type_number_t task_info_outCnt;
            };
            struct __attribute__((packed, aligned(4))) TaskInfoReply32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                kern_return_t RetCode;
                mach_msg_type_number_t task_info_outCnt;
                integer_t task_info_out[TASK_BASIC_INFO_32_COUNT];
            };
            static_assert(sizeof(TaskInfoRequest32) == 40,
                "unexpected 32-bit task_info request layout");
            static_assert(sizeof(TaskInfoReply32) == 72,
                "unexpected 32-bit TASK_BASIC_INFO_32 reply layout");

            if (send_size != sizeof(TaskInfoRequest32)) {
                if (rcv_size < sizeof(mig_reply_error_t)) {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                    result = MACH_RCV_TOO_LARGE;
                } else {
                    auto *error = reinterpret_cast<mig_reply_error_t *>(
                        host_header);
                    host_header->msgh_size = sizeof(*error);
                    error->NDR = NDR_record;
                    error->RetCode = MIG_BAD_ARGUMENTS;
                }
                break;
            }

            auto *request = reinterpret_cast<TaskInfoRequest32 *>(
                host_header);
            const bool validBasicInfoRequest =
                request->flavor == TASK_BASIC_INFO_32 &&
                request->task_info_outCnt >= TASK_BASIC_INFO_32_COUNT;
            if (!validBasicInfoRequest) {
                if (rcv_size < sizeof(mig_reply_error_t)) {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                    result = MACH_RCV_TOO_LARGE;
                } else {
                    auto *error = reinterpret_cast<mig_reply_error_t *>(
                        host_header);
                    host_header->msgh_size = sizeof(*error);
                    error->NDR = NDR_record;
                    error->RetCode = KERN_INVALID_ARGUMENT;
                }
                break;
            }
            if (rcv_size < sizeof(TaskInfoReply32)) {
                host_header->msgh_size = sizeof(TaskInfoReply32);
                result = MACH_RCV_TOO_LARGE;
                break;
            }

            task_basic_info_32_data_t basicInfo = {};
            mach_msg_type_number_t basicInfoCount =
                TASK_BASIC_INFO_32_COUNT;
            kern_return_t kr = task_info(
                request->Head.msgh_request_port,
                TASK_BASIC_INFO_32,
                reinterpret_cast<task_info_t>(&basicInfo),
                &basicInfoCount);
            if (kr == KERN_SUCCESS &&
                    basicInfoCount != TASK_BASIC_INFO_32_COUNT) {
                kr = KERN_FAILURE;
            }
            if (kr != KERN_SUCCESS) {
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = kr;
                break;
            }

            auto *reply = reinterpret_cast<TaskInfoReply32 *>(host_header);
            reply->NDR = NDR_record;
            reply->RetCode = KERN_SUCCESS;
            reply->task_info_outCnt = TASK_BASIC_INFO_32_COUNT;
            memcpy(reply->task_info_out, &basicInfo, sizeof(basicInfo));
            host_header->msgh_size = sizeof(*reply);
            break;
        }
        case 3603: { // thread_get_state
            /*
             * thread_act.defs uses natural_t arrays, so this wire layout is
             * identical for an ARM32 client even though LiveExec32 itself is
             * built for arm64. Never forward the synthetic guest thread port
             * to the host API: that would expose the emulator pthread's ARM64
             * register file instead of the logical ARM32 context.
             */
            struct __attribute__((packed, aligned(4)))
                ThreadGetStateRequest32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                thread_state_flavor_t flavor;
                mach_msg_type_number_t old_stateCnt;
            };
            struct __attribute__((packed, aligned(4)))
                ThreadGetStateReply32 {
                mach_msg_header_t Head;
                NDR_record_t NDR;
                kern_return_t RetCode;
                mach_msg_type_number_t old_stateCnt;
                u32 old_state[144];
            };
            static_assert(sizeof(ThreadGetStateRequest32) == 40,
                "unexpected 32-bit thread_get_state request layout");
            static_assert(offsetof(
                ThreadGetStateReply32, old_state) == 40,
                "unexpected 32-bit thread_get_state reply layout");

            auto *request = reinterpret_cast<
                ThreadGetStateRequest32 *>(host_header);
            kern_return_t kr = MIG_BAD_ARGUMENTS;
            mach_msg_type_number_t stateCount = 0;
            auto *reply = reinterpret_cast<
                ThreadGetStateReply32 *>(host_header);
            constexpr mach_msg_size_t MinimumSuccessReplySize =
                offsetof(ThreadGetStateReply32, old_state) +
                17 * sizeof(reply->old_state[0]);
            if (send_size != sizeof(*request)) {
                if (rcv_size < sizeof(mig_reply_error_t)) {
                    host_header->msgh_size = sizeof(mig_reply_error_t);
                    result = MACH_RCV_TOO_LARGE;
                } else {
                    auto *error = reinterpret_cast<mig_reply_error_t *>(
                        host_header);
                    host_header->msgh_size = sizeof(*error);
                    error->NDR = NDR_record;
                    error->RetCode = MIG_BAD_ARGUMENTS;
                }
                break;
            }

            THREAD_TRACE(
                "LC32: thread_get_state target=0x%x flavor=%d "
                "capacity=%u\n",
                host_header->msgh_request_port, request->flavor,
                request->old_stateCnt);
            const bool validStateRequest =
                (request->flavor == ARM_THREAD_STATE ||
                 request->flavor == ARM_THREAD_STATE32) &&
                request->old_stateCnt >= 17 &&
                request->old_stateCnt <=
                        sizeof(reply->old_state) /
                            sizeof(reply->old_state[0]);
            if (validStateRequest &&
                    rcv_size < MinimumSuccessReplySize) {
                host_header->msgh_size = MinimumSuccessReplySize;
                result = MACH_RCV_TOO_LARGE;
                break;
            }
            if (!validStateRequest &&
                    rcv_size < sizeof(mig_reply_error_t)) {
                host_header->msgh_size = sizeof(mig_reply_error_t);
                result = MACH_RCV_TOO_LARGE;
                break;
            }
            if (validStateRequest) {
                stateCount = request->old_stateCnt;
                kr = CopyGuestThreadState(
                    host_header->msgh_request_port,
                    request->flavor, request->old_stateCnt,
                    reply->old_state, &stateCount);
            }
            if (kr != KERN_SUCCESS) {
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = kr;
                break;
            }

            const mach_msg_size_t replySize = static_cast<
                mach_msg_size_t>(offsetof(
                    ThreadGetStateReply32, old_state) +
                    sizeof(reply->old_state[0]) * stateCount);
            if (replySize > rcv_size) {
                auto *error = reinterpret_cast<mig_reply_error_t *>(
                    host_header);
                host_header->msgh_size = sizeof(*error);
                error->NDR = NDR_record;
                error->RetCode = MIG_ARRAY_TOO_LARGE;
                break;
            }
            reply->NDR = NDR_record;
            reply->RetCode = KERN_SUCCESS;
            reply->old_stateCnt = stateCount;
            host_header->msgh_size = replySize;
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
            const bool nativeWorkqueueMayBlock =
                NativeGuestWorkqueueIsCurrent() &&
                (option & MACH_RCV_MSG) != 0 &&
                ((option & MACH_RCV_TIMEOUT) == 0 || timeout != 0);
            if (nativeWorkqueueMayBlock) {
                NativeGuestWorkqueueHostBlockEnter();
            }
            result = debugger_aware_mach_msg(host_header, option, send_size,
                rcv_size, rcv_name, timeout, notify);
            if (nativeWorkqueueMayBlock) {
                NativeGuestWorkqueueHostBlockExit();
            }
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
            Dynarmic_current_user_callbacks()->ExceptionRaised(
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

int guest_getdirentries64(int fd, u32 guest_buf, u32 nbytes,
        u32 guest_basep) {
    /* XNU caps one getdirentries64 transfer at 128 MiB. */
    constexpr size_t maximumBufferSize = 128U * 1024U * 1024U;
    const size_t bufferSize = std::min(
        static_cast<size_t>(nbytes), maximumBufferSize);
    std::vector<char> hostBuffer;
    try {
        hostBuffer.resize(bufferSize);
    } catch(const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }

    /* basep is output-only and is a 64-bit off_t in the armv7 ABI. */
    off_t hostPosition = 0;
    const int result = syscallRetCarry(
        SYS_getdirentries64, fd,
        hostBuffer.empty() ? nullptr : hostBuffer.data(),
        bufferSize, &hostPosition, 0, 0, 0);
    if(threadHandle.cpsr->hasCarry()) {
        return result;
    }
    if(result < 0 || static_cast<size_t>(result) > bufferSize) {
        return return_with_carry_direct(EIO, true);
    }
    if((result != 0 && !write_guest_memory_with_permissions(
            guest_buf, hostBuffer.data(), static_cast<size_t>(result),
            PROT_WRITE)) ||
            !write_guest_memory_with_permissions(
                guest_basep, &hostPosition, sizeof(hostPosition),
                PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return return_with_carry_direct(result, false);
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
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
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
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    int result = lstat(host_path, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_statfs64(u32 guest_path, u32 guest_buf) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
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

std::vector<GuestWorkqueueKevent> guestWorkqueueKevents;
std::deque<GuestWorkqueueRequest> guestWorkqueueRequests;
std::recursive_mutex guestWorkqueueMutex;
u32 guestWorkqueueEventManagerPriority;
bool guestWorkqueueUpcallActive;
bool guestWorkqueueRestoreRequested;
thread_local bool guestWorkqueueOverlayCurrent;

static_assert(sizeof(guest_kevent_qos_s) == 72,
    "iOS 10 kevent_qos_s ABI changed");

u32 GuestWorkqueueQosClass(u32 priority) {
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
    {
        std::lock_guard<std::recursive_mutex> lock(
            guestWorkqueueMutex);
        WORKQUEUE_TRACE(
            "LC32: workq_kernreturn op=0x%x item=0x%x arg2=%d "
            "arg3=0x%x active=%d\n",
            options, item, arg2, arg3,
            guestWorkqueueUpcallActive);
    }
    switch (options) {
        case WQOPS_QUEUE_NEWSPISUPP:
            /*
             * libpthread uses this as the dispatch/kevent capability
             * handshake. arg2 is the dispatch queue serial-number offset and
             * bit zero of arg3 requests direct kevent delivery.
             */
            {
                std::lock_guard<std::recursive_mutex> lock(
                    guestWorkqueueMutex);
                guest_workqueue_dispatch_offset = arg2;
                guest_workqueue_kevent_enabled = (arg3 & 1) != 0;
            }
            return return_with_carry_direct(0, false);
        case WQOPS_SET_EVENT_MANAGER_PRIORITY:
            {
                std::lock_guard<std::recursive_mutex> lock(
                    guestWorkqueueMutex);
                guestWorkqueueEventManagerPriority =
                    static_cast<u32>(arg2);
            }
            return return_with_carry_direct(0, false);
        case WQOPS_QUEUE_REQTHREADS: {
            {
                std::lock_guard<std::recursive_mutex> lock(
                    guestWorkqueueMutex);
                if (!guest_workqueue_opened ||
                        arg2 <= 0 || arg2 > 4096) {
                    return return_with_carry_direct(EINVAL, true);
                }
                guestWorkqueueRequests.push_back(
                    {.remaining = arg2,
                     .priority = static_cast<u32>(arg3)});
            }
            /*
             * XNU may start the requested worker before this syscall returns.
             * Start native workers or prepare the cooperative overlay now so
             * dispatch_async does not depend on a later mach_msg receive.
             */
            const GuestWorkqueuePumpResult pumpResult =
                PumpGuestWorkqueue();
            if (pumpResult ==
                    GuestWorkqueuePumpResult::CooperativeTransition &&
                    NativeGuestThreadIsCurrent() &&
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
            std::lock_guard<std::recursive_mutex> lock(
                guestWorkqueueMutex);
            const int error =
                ApplyGuestKeventChanges(item, arg2);
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
        errno = 0;
        if(!sharedHandle.fs->pathGuestToHost(
                guest_path.data(), host_path)) {
            return return_with_carry_direct(
                errno != 0 ? errno : EINVAL, true);
        }
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

static int ReadGuestSocketAddressLength(
        u32 guest_address_len, u32 *requested_len) {
    if (guest_address_len == 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    if (!read_guest_memory_with_permissions(
            guest_address_len, requested_len,
            sizeof(*requested_len), PROT_READ)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return 0;
}

static int CopyOutGuestSocketAddress(
        u32 guest_address, u32 guest_address_len,
        u32 requested_len,
        const std::array<char, SOCK_MAXADDRLEN> &host_address,
        socklen_t host_address_len) {
    std::array<char, SOCK_MAXADDRLEN> guest_address_storage =
        host_address;
    u32 returned_len = host_address_len;
    size_t stored_len = std::min(
        static_cast<size_t>(host_address_len),
        host_address.size());

    constexpr size_t path_offset =
        offsetof(sockaddr_un, sun_path);
    if (host_address_len <= host_address.size() &&
            stored_len >= sizeof(__sockaddr_header) &&
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
        errno = 0;
        if (!sharedHandle.fs->pathHostToGuest(
                host_path.data(), guest_path)) {
            return return_with_carry_direct(
                errno != 0 ? errno : EINVAL, true);
        }
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
             !write_guest_memory_with_permissions(
                 guest_address, guest_address_storage.data(),
                 copy_len, PROT_WRITE))) {
        return return_with_carry_direct(EFAULT, true);
    }
    if (!write_guest_memory_with_permissions(
            guest_address_len, &returned_len,
            sizeof(returned_len), PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return return_with_carry_direct(0, false);
}

static int GuestSocketName(int syscall_number, int socket,
        u32 guest_address, u32 guest_address_len) {
    u32 requested_len = 0;
    const int preparation_error = ReadGuestSocketAddressLength(
        guest_address_len, &requested_len);
    if (preparation_error != 0) {
        return preparation_error;
    }

    std::array<char, SOCK_MAXADDRLEN> host_address = {};
    socklen_t host_address_len = host_address.size();
    const int result = syscallRetCarry(
        syscall_number, socket,
        reinterpret_cast<sockaddr *>(host_address.data()),
        &host_address_len, 0, 0, 0, 0);
    if (threadHandle.cpsr->hasCarry()) {
        return result;
    }
    return CopyOutGuestSocketAddress(
        guest_address, guest_address_len, requested_len,
        host_address, host_address_len);
}

int guest_getsockname(int socket, u32 guest_address,
        u32 guest_address_len) {
    return GuestSocketName(
        SYS_getsockname, socket,
        guest_address, guest_address_len);
}

int guest_getpeername(int socket, u32 guest_address,
        u32 guest_address_len) {
    return GuestSocketName(
        SYS_getpeername, socket,
        guest_address, guest_address_len);
}

int guest_accept(int syscall_number, int socket,
        u32 guest_address, u32 guest_address_len) {
    const bool wants_address = guest_address != 0;
    u32 requested_len = 0;
    if (wants_address) {
        const int preparation_error = ReadGuestSocketAddressLength(
            guest_address_len, &requested_len);
        if (preparation_error != 0) {
            return preparation_error;
        }
    }

    std::array<char, SOCK_MAXADDRLEN> host_address = {};
    socklen_t host_address_len = host_address.size();
    if (GuestThreadCanYieldBeforeBlocking()) {
        const int socket_flags = ::fcntl(socket, F_GETFL);
        if (socket_flags >= 0 && (socket_flags & O_NONBLOCK) == 0) {
            pollfd readiness = {
                .fd = socket,
                .events = POLLIN,
                .revents = 0,
            };
            if (::poll(&readiness, 1, 0) == 0 &&
                    GuestThreadYieldBeforeBlocking()) {
                return return_with_carry_direct(EINTR, true);
            }
        }
    }
    const bool workqueue_may_block =
        NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const int accepted = debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_accept : syscall_number,
                socket,
                wants_address
                    ? reinterpret_cast<sockaddr *>(
                        host_address.data())
                    : nullptr,
                wants_address ? &host_address_len : nullptr,
                0, 0, 0, 0);
        },
        return_with_carry_direct(EINTR, true));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    if (threadHandle.cpsr->hasCarry()) {
        return accepted;
    }

    if (wants_address) {
        const int copyout_result = CopyOutGuestSocketAddress(
            guest_address, guest_address_len, requested_len,
            host_address, host_address_len);
        if (copyout_result != 0) {
            (void)::close(accepted);
            return copyout_result;
        }
    }
    return return_with_carry_direct(accepted, false);
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

int guest_connect(int NR, int socket, u32 guest_address,
        socklen_t address_len) {
    // See https://developer.apple.com/forums/thread/756756?answerId=790507022#790507022
    // sockaddr_un.sun_path has an artificial limit is 104 bytes, however it allows up to 253 bytes
    if (address_len > SOCK_MAXADDRLEN) {
        return return_with_carry_direct(ENAMETOOLONG, true);
    }
    if (address_len < sizeof(__sockaddr_header)) {
        return return_with_carry_direct(EINVAL, true);
    }
    std::array<char, SOCK_MAXADDRLEN> host_address = {};
    if (guest_address == 0 ||
            Dynarmic_mem_1read(
                guest_address, address_len,
                host_address.data()) != 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    constexpr size_t path_offset =
        offsetof(sockaddr_un, sun_path);
    if (address_len > path_offset &&
            reinterpret_cast<const sockaddr *>(
                host_address.data())->sa_family == AF_UNIX &&
            host_address[path_offset] != '\0') {
        std::array<char,
            SOCK_MAXADDRLEN - path_offset + 1> guest_path = {};
        memcpy(guest_path.data(),
            host_address.data() + path_offset,
            address_len - path_offset);

        char host_path[PATH_MAX] = {};
        errno = 0;
        if(!sharedHandle.fs->pathGuestToHost(
                guest_path.data(), host_path)) {
            return return_with_carry_direct(
                errno != 0 ? errno : EINVAL, true);
        }
        const size_t host_path_len = strlen(host_path);
        if (host_path_len > SOCK_MAXADDRLEN - path_offset) {
            return return_with_carry_direct(ENAMETOOLONG, true);
        }
        memset(host_address.data() + path_offset, 0,
            host_address.size() - path_offset);
        memcpy(host_address.data() + path_offset,
            host_path, host_path_len);
        address_len = static_cast<socklen_t>(
            path_offset + host_path_len);
        host_address[0] = static_cast<char>(address_len);
    }

    const bool workqueue_may_block =
        NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const int result = debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_connect : NR,
                socket,
                reinterpret_cast<const sockaddr *>(
                    host_address.data()),
                address_len, 0, 0, 0, 0);
        },
        return_with_carry_direct(EINTR, true));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    return result;
}

int guest_socketpair(int domain, int type, int protocol,
        u32 guest_sockets) {
    int host_sockets[2] = {-1, -1};
    const int result = syscallRetCarry(
        SYS_socketpair, domain, type, protocol,
        host_sockets, 0, 0, 0);
    if (threadHandle.cpsr->hasCarry()) {
        return result;
    }

    if (guest_sockets == 0 ||
            !write_guest_memory_with_permissions(
                guest_sockets, host_sockets,
                sizeof(host_sockets), PROT_WRITE)) {
        (void)close(host_sockets[0]);
        (void)close(host_sockets[1]);
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
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
    int path_error = LC32GuestPathToHost(guest_old, host_old);
    if(path_error == 0) {
        path_error = LC32GuestPathToHost(guest_new, host_new);
    }
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    return syscallRetCarry(SYS_rename, host_old, host_new, 0,0,0,0,0);
}

ssize_t guest_sendto(int NR, int socket, u32 guest_buffer,
        size_t length, int flags, u32 guest_dest_addr,
        socklen_t dest_len) {
    if (length > static_cast<size_t>(INT32_MAX)) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EINVAL, true));
    }
    std::vector<char> host_buffer;
    try {
        host_buffer.resize(length);
    } catch (const std::exception &) {
        return static_cast<ssize_t>(
            return_with_carry_direct(ENOMEM, true));
    }
    if (length != 0 &&
            (guest_buffer == 0 ||
             Dynarmic_mem_1read(
                 guest_buffer, length,
                 host_buffer.data()) != 0)) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }

    std::array<char, SOCK_MAXADDRLEN> host_dest = {};
    const sockaddr *host_dest_pointer = nullptr;
    if (guest_dest_addr != 0) {
        if (dest_len > SOCK_MAXADDRLEN) {
            return static_cast<ssize_t>(
                return_with_carry_direct(
                    ENAMETOOLONG, true));
        }
        if (dest_len < sizeof(__sockaddr_header)) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EINVAL, true));
        }
        if (Dynarmic_mem_1read(
                guest_dest_addr, dest_len,
                host_dest.data()) != 0) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EFAULT, true));
        }
        host_dest_pointer = reinterpret_cast<const sockaddr *>(
            host_dest.data());

        constexpr size_t path_offset =
            offsetof(sockaddr_un, sun_path);
        if (dest_len > path_offset &&
                host_dest_pointer->sa_family == AF_UNIX &&
                host_dest[path_offset] != '\0') {
            std::array<char,
                SOCK_MAXADDRLEN - path_offset + 1> guest_path = {};
            memcpy(guest_path.data(),
                host_dest.data() + path_offset,
                dest_len - path_offset);

            char host_path[PATH_MAX] = {};
            errno = 0;
            if(!sharedHandle.fs->pathGuestToHost(
                    guest_path.data(), host_path)) {
                return static_cast<ssize_t>(
                    return_with_carry_direct(
                        errno != 0 ? errno : EINVAL, true));
            }
            const size_t host_path_len = strlen(host_path);
            if (host_path_len > SOCK_MAXADDRLEN - path_offset) {
                return static_cast<ssize_t>(
                    return_with_carry_direct(
                        ENAMETOOLONG, true));
            }
            memset(host_dest.data() + path_offset, 0,
                host_dest.size() - path_offset);
            memcpy(host_dest.data() + path_offset,
                host_path, host_path_len);
            dest_len = static_cast<socklen_t>(
                path_offset + host_path_len);
            host_dest[0] = static_cast<char>(dest_len);
        }
    }

    const bool workqueue_may_block =
        NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_sendto : NR,
                socket,
                length != 0 ? host_buffer.data() : nullptr,
                length,
                flags,
                host_dest_pointer,
                dest_len, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    return result;
}

struct __attribute__((packed, aligned(4))) GuestIovec32 {
    u32 base;
    u32 length;
};

struct __attribute__((packed, aligned(4))) GuestMsghdr32 {
    u32 name;
    u32 nameLength;
    u32 iov;
    int32_t iovCount;
    u32 control;
    u32 controlLength;
    int32_t flags;
};

static_assert(sizeof(GuestIovec32) == 8,
    "armv7 iovec must be 8 bytes");
static_assert(sizeof(GuestMsghdr32) == 28,
    "armv7 msghdr must be 28 bytes");

ssize_t guest_sendmsg(int NR, int socket,
        u32 guest_message_address, int flags) {
    GuestMsghdr32 guest_message = {};
    if (guest_message_address == 0 ||
            !read_guest_memory_with_permissions(
                guest_message_address, &guest_message,
                sizeof(guest_message), PROT_READ)) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }

    constexpr int32_t maximum_iov_count = 1024;
    if (guest_message.iovCount <= 0 ||
            guest_message.iovCount > maximum_iov_count) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EMSGSIZE, true));
    }

    std::vector<GuestIovec32> guest_iov;
    std::vector<iovec> host_iov;
    std::vector<std::vector<char>> host_payloads;
    try {
        guest_iov.resize(
            static_cast<size_t>(guest_message.iovCount));
        host_iov.resize(
            static_cast<size_t>(guest_message.iovCount));
        host_payloads.resize(
            static_cast<size_t>(guest_message.iovCount));
    } catch (const std::exception &) {
        return static_cast<ssize_t>(
            return_with_carry_direct(ENOMEM, true));
    }
    if (!guest_iov.empty() &&
            (guest_message.iov == 0 ||
             !read_guest_memory_with_permissions(
                 guest_message.iov, guest_iov.data(),
                 guest_iov.size() * sizeof(GuestIovec32),
                 PROT_READ))) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }

    u64 total_payload_length = 0;
    for (size_t index = 0; index < guest_iov.size(); ++index) {
        const GuestIovec32 &guest = guest_iov[index];
        total_payload_length += guest.length;
        if (total_payload_length >
                static_cast<u64>(INT32_MAX)) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EINVAL, true));
        }
        try {
            host_payloads[index].resize(guest.length);
        } catch (const std::exception &) {
            return static_cast<ssize_t>(
                return_with_carry_direct(ENOMEM, true));
        }
        if (guest.length != 0 &&
                (guest.base == 0 ||
                 !read_guest_memory_with_permissions(
                     guest.base, host_payloads[index].data(),
                     guest.length, PROT_READ))) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EFAULT, true));
        }
        host_iov[index].iov_base = guest.length != 0
            ? host_payloads[index].data() : nullptr;
        host_iov[index].iov_len = guest.length;
    }

    std::array<char, SOCK_MAXADDRLEN> host_name = {};
    sockaddr *host_name_pointer = nullptr;
    socklen_t host_name_length = guest_message.nameLength;
    if (guest_message.name != 0) {
        if (host_name_length > SOCK_MAXADDRLEN) {
            return static_cast<ssize_t>(
                return_with_carry_direct(
                    ENAMETOOLONG, true));
        }
        if (host_name_length < sizeof(__sockaddr_header)) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EINVAL, true));
        }
        if (!read_guest_memory_with_permissions(
                guest_message.name, host_name.data(),
                host_name_length, PROT_READ)) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EFAULT, true));
        }
        host_name_pointer = reinterpret_cast<sockaddr *>(
            host_name.data());

        constexpr size_t path_offset =
            offsetof(sockaddr_un, sun_path);
        if (host_name_length > path_offset &&
                host_name_pointer->sa_family == AF_UNIX &&
                host_name[path_offset] != '\0') {
            std::array<char,
                SOCK_MAXADDRLEN - path_offset + 1> guest_path = {};
            memcpy(guest_path.data(),
                host_name.data() + path_offset,
                host_name_length - path_offset);

            char host_path[PATH_MAX] = {};
            errno = 0;
            if(!sharedHandle.fs->pathGuestToHost(
                    guest_path.data(), host_path)) {
                return static_cast<ssize_t>(
                    return_with_carry_direct(
                        errno != 0 ? errno : EINVAL, true));
            }
            const size_t host_path_length = strlen(host_path);
            if (host_path_length >
                    SOCK_MAXADDRLEN - path_offset) {
                return static_cast<ssize_t>(
                    return_with_carry_direct(
                        ENAMETOOLONG, true));
            }
            memset(host_name.data() + path_offset, 0,
                host_name.size() - path_offset);
            memcpy(host_name.data() + path_offset,
                host_path, host_path_length);
            host_name_length = static_cast<socklen_t>(
                path_offset + host_path_length);
            host_name[0] = static_cast<char>(host_name_length);
        }
    }

    constexpr u32 maximum_control_length = 1U << 20;
    u32 staged_control_length = 0;
    if (guest_message.control != 0) {
        if (guest_message.controlLength < sizeof(cmsghdr)) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EINVAL, true));
        }
        if (guest_message.controlLength > maximum_control_length) {
            return static_cast<ssize_t>(
                return_with_carry_direct(EMSGSIZE, true));
        }
        staged_control_length = guest_message.controlLength;
    }
    std::vector<char> host_control;
    try {
        host_control.resize(staged_control_length);
    } catch (const std::exception &) {
        return static_cast<ssize_t>(
            return_with_carry_direct(ENOMEM, true));
    }
    if (!host_control.empty() &&
            (guest_message.control == 0 ||
             !read_guest_memory_with_permissions(
                 guest_message.control, host_control.data(),
                 host_control.size(), PROT_READ))) {
        return static_cast<ssize_t>(
            return_with_carry_direct(EFAULT, true));
    }

    msghdr host_message = {};
    host_message.msg_name = host_name_pointer;
    host_message.msg_namelen = host_name_pointer != nullptr
        ? host_name_length : 0;
    host_message.msg_iov = !host_iov.empty()
        ? host_iov.data() : nullptr;
    host_message.msg_iovlen = guest_message.iovCount;
    host_message.msg_control = !host_control.empty()
        ? host_control.data() : nullptr;
    host_message.msg_controllen =
        static_cast<socklen_t>(host_control.size());
    host_message.msg_flags = guest_message.flags;

    const bool workqueue_may_block =
        NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_sendmsg : NR,
                socket, &host_message, flags,
                0, 0, 0, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    return result;
}

int guest_select(int NR, int descriptor_count,
        u32 guest_read_set, u32 guest_write_set,
        u32 guest_except_set, u32 guest_timeout) {
    if (descriptor_count < 0 || descriptor_count > FD_SETSIZE) {
        return return_with_carry_direct(EINVAL, true);
    }

    timeval_32 original_guest_timeout = {};
    struct timeval original_host_timeout = {};
    const bool has_timeout = guest_timeout != 0;
    if (has_timeout) {
        if (Dynarmic_mem_1read(
                guest_timeout, sizeof(original_guest_timeout),
                reinterpret_cast<char *>(
                    &original_guest_timeout)) != 0) {
            return return_with_carry_direct(EFAULT, true);
        }
        if (original_guest_timeout.tv_sec < 0 ||
                original_guest_timeout.tv_usec < 0 ||
                original_guest_timeout.tv_usec >= 1000000) {
            return return_with_carry_direct(EINVAL, true);
        }
        original_host_timeout.tv_sec =
            original_guest_timeout.tv_sec;
        original_host_timeout.tv_usec =
            original_guest_timeout.tv_usec;
    }

    const size_t fd_bytes = static_cast<size_t>(
        (descriptor_count + __DARWIN_NFDBITS - 1) /
        __DARWIN_NFDBITS) * sizeof(int32_t);
    fd_set original_read = {};
    fd_set original_write = {};
    fd_set original_except = {};
    const auto copy_in_set = [&](u32 guest, fd_set &host) {
        return guest == 0 || fd_bytes == 0 ||
            Dynarmic_mem_1read(
                guest, fd_bytes,
                reinterpret_cast<char *>(&host)) == 0;
    };
    if (!copy_in_set(guest_read_set, original_read) ||
            !copy_in_set(guest_write_set, original_write) ||
            !copy_in_set(guest_except_set, original_except)) {
        return return_with_carry_direct(EFAULT, true);
    }

    fd_set host_read = {};
    fd_set host_write = {};
    fd_set host_except = {};
    struct timeval host_timeout = {};
    const auto invoke_host = [&](const struct timeval *timeout_override) {
        host_read = original_read;
        host_write = original_write;
        host_except = original_except;
        host_timeout = original_host_timeout;
        return syscallRetCarry(
            NativeGuestThreadsEnabled()
                ? SYS_select : NR,
            descriptor_count,
            guest_read_set != 0 ? &host_read : nullptr,
            guest_write_set != 0 ? &host_write : nullptr,
            guest_except_set != 0 ? &host_except : nullptr,
            timeout_override != nullptr
                ? timeout_override
                : (has_timeout ? &host_timeout : nullptr),
            0, 0);
    };

    const bool potentially_blocking = !has_timeout ||
        original_guest_timeout.tv_sec != 0 ||
        original_guest_timeout.tv_usec != 0;
    const bool workqueue_may_block = potentially_blocking &&
        NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const int result = debugger_aware_host_wait(
        [&] { return invoke_host(nullptr); },
        return_with_carry_direct(EINTR, true));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    if (threadHandle.cpsr->hasCarry()) {
        return result;
    }

    const auto copy_out_set = [&](u32 guest, const fd_set &host) {
        return guest == 0 || fd_bytes == 0 ||
            Dynarmic_mem_1write(
                guest, fd_bytes,
                reinterpret_cast<char *>(
                    const_cast<fd_set *>(&host))) == 0;
    };
    if (!copy_out_set(guest_read_set, host_read) ||
            !copy_out_set(guest_write_set, host_write) ||
            !copy_out_set(guest_except_set, host_except)) {
        return return_with_carry_direct(EFAULT, true);
    }
    /* XNU consumes but does not copy its timeval back to user space. */
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

/*
 * Keep the legacy AES character device entirely inside the emulator.  A real
 * host descriptor backed by /dev/null gives the guest an ordinary descriptor
 * lifetime (close, dup and fcntl still work) without depending on the host
 * kernel exposing an AES device with the 32-bit iOS ABI.
 */
static std::mutex guestAesFileDescriptorsMutex;
static std::unordered_set<int> guestAesFileDescriptors;

static bool IsGuestAesFileDescriptor(int fildes) {
    std::lock_guard<std::mutex> lock(
        guestAesFileDescriptorsMutex);
    return guestAesFileDescriptors.count(fildes) != 0;
}

static void RegisterGuestAesFileDescriptor(int fildes) {
    std::lock_guard<std::mutex> lock(
        guestAesFileDescriptorsMutex);
    guestAesFileDescriptors.insert(fildes);
}

int guest_close(int NR, int fildes) {
    std::lock_guard<std::mutex> lock(
        guestAesFileDescriptorsMutex);
    const int result = syscallRetCarry(
        NR, fildes, 0, 0, 0, 0, 0, 0);
    if (!threadHandle.cpsr->hasCarry() && result == 0) {
        guestAesFileDescriptors.erase(fildes);
    }
    return result;
}

int guest_dup(int fildes) {
    std::lock_guard<std::mutex> lock(
        guestAesFileDescriptorsMutex);
    const bool duplicateIsAes =
        guestAesFileDescriptors.count(fildes) != 0;
    const int result = syscallRetCarry(
        SYS_dup, fildes, 0, 0, 0, 0, 0, 0);
    if (!threadHandle.cpsr->hasCarry() &&
            result >= 0 && duplicateIsAes) {
        guestAesFileDescriptors.insert(result);
    }
    return result;
}

int guest_dup2(int source, int destination) {
    std::lock_guard<std::mutex> lock(
        guestAesFileDescriptorsMutex);
    const bool duplicateIsAes =
        guestAesFileDescriptors.count(source) != 0;
    const int result = syscallRetCarry(
        SYS_dup2, source, destination, 0, 0, 0, 0, 0);
    if (!threadHandle.cpsr->hasCarry() && result >= 0) {
        guestAesFileDescriptors.erase(result);
        if (duplicateIsAes) {
            guestAesFileDescriptors.insert(result);
        }
    }
    return result;
}

void CloseAllGuestAesFileDescriptors() {
    std::lock_guard<std::mutex> lock(
        guestAesFileDescriptorsMutex);
    for (int fildes : guestAesFileDescriptors) {
        (void)close(fildes);
    }
    guestAesFileDescriptors.clear();
}

int guest_open(int NR, u32 guest_path, int oflag, int mode) {
    char copied_path[PATH_MAX];
    char host_path[PATH_MAX];
    int path_error = LC32CopyGuestCString(guest_path, copied_path);
    if(path_error == 0 && copied_path[0] == '\0') {
        path_error = ENOENT;
    }
    errno = 0;
    if(path_error == 0 && !sharedHandle.fs->pathGuestToHost(
            copied_path, host_path)) {
        path_error = errno != 0 ? errno : EINVAL;
    }
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    const bool openGuestAesDevice =
        strcmp(copied_path, "/dev/aes_0") == 0;
    const char *openedHostPath = openGuestAesDevice
        ? "/dev/null" : host_path;
    int result = debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                NR, openedHostPath, oflag, mode,
                0, 0, 0, 0);
        },
        return_with_carry_direct(EINTR, true));
    if (openGuestAesDevice && result >= 0 &&
            !threadHandle.cpsr->hasCarry()) {
        RegisterGuestAesFileDescriptor(result);
    }
    return result;
}

static int guest_chdir_with_syscall(int syscall_number, u32 guest_path) {
    char copied_path[PATH_MAX];
    char host_path[PATH_MAX];
    const int copy_error = LC32CopyGuestCString(
        guest_path, copied_path);
    if(copy_error != 0) {
        return return_with_carry_direct(copy_error, true);
    }
    if(copied_path[0] == '\0') {
        return return_with_carry_direct(ENOENT, true);
    }
    if(!sharedHandle.fs->pathGuestToHost(copied_path, host_path)) {
        const int error = errno != 0 ? errno : EINVAL;
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        syscall_number, host_path, 0, 0, 0, 0, 0, 0);
}

int guest_chdir(u32 guest_path) {
    return guest_chdir_with_syscall(SYS_chdir, guest_path);
}

int guest_fchdir(int fildes) {
    return syscallRetCarry(
        SYS_fchdir, fildes, 0, 0, 0, 0, 0, 0);
}

int guest_pthread_chdir(u32 guest_path) {
    /*
     * XNU's private pthread cwd is the closest match for an ARM guest backed
     * by a native host pthread. Cooperative guest pthreads share one host
     * thread, so they necessarily share this override until their scheduler
     * grows per-logical-thread cwd state.
     */
    return guest_chdir_with_syscall(
        SYS___pthread_chdir, guest_path);
}

int guest_pthread_fchdir(int fildes) {
    /* Passing -1 is meaningful: XNU clears the current thread's cwd override
     * and makes subsequent relative lookups use the process cwd again. */
    return syscallRetCarry(
        SYS___pthread_fchdir, fildes, 0, 0, 0, 0, 0, 0);
}

int guest_unlink(u32 guest_path) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    return syscallRetCarry(SYS_unlink, host_path, 0,0,0,0,0,0);
}

int guest_chmod(u32 guest_path, mode_t mode) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    return syscallRetCarry(SYS_chmod, host_path, mode, 0,0,0,0,0);
}

int guest_chown(u32 guest_path, uid_t owner, gid_t group) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    return syscallRetCarry(SYS_chown, host_path, owner, group, 0,0,0,0);
}

int guest_access(u32 guest_path, int mode) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    return syscallRetCarry(SYS_access, host_path, mode, 0,0,0,0,0);
}

int guest_mkdir(u32 guest_path, mode_t mode) {
    char host_path[PATH_MAX];
    const int path_error = LC32GuestPathToHost(guest_path, host_path);
    if(path_error != 0) {
        return return_with_carry_direct(path_error, true);
    }
    return syscallRetCarry(SYS_mkdir, host_path, mode, 0,0,0,0,0);
}

int guest_setxattr(u32 guest_path, u32 guest_name, u32 guest_value,
        size_t size, u_int32_t position, int options) {
    constexpr size_t maximum_staged_xattr_size = 64 * 1024 * 1024;
    char copied_path[PATH_MAX];
    char host_path[PATH_MAX];
    char name[PATH_MAX];
    int error = LC32CopyGuestCString(guest_path, copied_path);
    if(error == 0 && copied_path[0] == '\0') {
        error = ENOENT;
    }
    if(error == 0 && !sharedHandle.fs->pathGuestToHost(
            copied_path, host_path)) {
        error = errno != 0 ? errno : EINVAL;
    }
    if(error == 0) {
        error = LC32CopyGuestCString(guest_name, name);
    }
    if(error != 0) {
        return return_with_carry_direct(error, true);
    }
    if(!guest_value && size != 0) {
        return return_with_carry_direct(EINVAL, true);
    }
    if(size > maximum_staged_xattr_size) {
        return return_with_carry_direct(ENOMEM, true);
    }
    std::vector<uint8_t> value;
    if(size != 0) {
        if(!guest_memory_range_has_permissions(
                guest_value, size, PROT_READ)) {
            return return_with_carry_direct(EFAULT, true);
        }
        try {
            value.resize(size);
        } catch(const std::bad_alloc &) {
            return return_with_carry_direct(ENOMEM, true);
        }
        if(!read_guest_memory_with_permissions(
                guest_value, value.data(), size, PROT_READ)) {
            return return_with_carry_direct(EFAULT, true);
        }
    }

    return syscallRetCarry(
        SYS_setxattr, host_path, name,
        value.empty() ? nullptr : value.data(), size,
        position, options, 0);
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
        ? Dynarmic_current_user_callbacks()->MemoryRead32(guest_set)
        : 0;
    sigset_t host_oldset = 0;
    int result = syscallRetCarry(SYS_sigprocmask, how, guest_set ? &host_set : NULL, &host_oldset, 0,0,0,0);
    if (guest_oldset) {
        Dynarmic_current_user_callbacks()->MemoryWrite32(
            guest_oldset, host_oldset);
    }
    return result;
}

/*
 * Classic iOS corecrypto offloaded sufficiently large AES-CBC operations to
 * /dev/aes_0.  The command numbers contain the exact 32-bit payload sizes:
 *
 *   _IOR ('T', 0x65, 40) = 0x40285465  capability query
 *   _IOWR('T', 0x66, 76) = 0xc04c5466  AES-CBC operation
 *
 * The layouts below were recovered from the armv7 corecrypto shipped in the
 * guest root.  Keep every unknown word so host compiler layout changes cannot
 * silently alter the guest ABI.
 */
static constexpr u32 LC32_AES_GET_INFO = 0x40285465u;
static constexpr u32 LC32_AES_CRYPT = 0xc04c5466u;
static constexpr size_t LC32_AES_BLOCK_SIZE = 16;
static constexpr size_t LC32_AES_MAXIMUM_BYTES_PER_CALL = 64 * 1024;
static constexpr size_t LC32_AES_WORKING_BUFFER_SIZE = 16 * 1024;

struct LC32AESInfo {
    uint8_t reserved0[28];
    uint32_t maximumBytesPerCall;
    uint8_t reserved1[8];
};

struct LC32AESCrypt {
    /* libcorecrypto puts input first for encryption, output first for
     * decryption.  Name these by position so that asymmetry stays explicit. */
    uint32_t firstBuffer;
    uint32_t secondBuffer;
    uint32_t dataLength;
    uint8_t iv[LC32_AES_BLOCK_SIZE];
    uint32_t decrypt;
    uint32_t keyBits;
    uint8_t key[32];
    uint32_t reserved68;
    uint32_t reserved72;
};

static_assert(sizeof(LC32AESInfo) == 40,
    "legacy AES info ioctl ABI must remain 40 bytes");
static_assert(offsetof(LC32AESInfo, maximumBytesPerCall) == 28,
    "legacy AES info quantum must remain at offset 28");
static_assert(sizeof(LC32AESCrypt) == 76,
    "legacy AES crypt ioctl ABI must remain 76 bytes");
static_assert(offsetof(LC32AESCrypt, firstBuffer) == 0 &&
        offsetof(LC32AESCrypt, secondBuffer) == 4 &&
        offsetof(LC32AESCrypt, dataLength) == 8,
    "legacy AES buffer fields must remain at offsets 0, 4, and 8");
static_assert(offsetof(LC32AESCrypt, iv) == 12,
    "legacy AES IV must remain at offset 12");
static_assert(offsetof(LC32AESCrypt, decrypt) == 28,
    "legacy AES direction must remain at offset 28");
static_assert(offsetof(LC32AESCrypt, keyBits) == 32,
    "legacy AES key length must remain at offset 32");
static_assert(offsetof(LC32AESCrypt, key) == 36,
    "legacy AES key must remain at offset 36");
static_assert(offsetof(LC32AESCrypt, reserved68) == 68,
    "legacy AES trailing fields must remain at offset 68");
static_assert(offsetof(LC32AESCrypt, reserved72) == 72,
    "legacy AES final field must remain at offset 72");
static_assert(LC32_AES_MAXIMUM_BYTES_PER_CALL %
        LC32_AES_BLOCK_SIZE == 0,
    "legacy AES quantum must contain complete blocks");
static_assert(LC32_AES_WORKING_BUFFER_SIZE %
        LC32_AES_BLOCK_SIZE == 0,
    "legacy AES working buffer must contain complete blocks");

class LC32ScopedSensitiveWipe {
public:
    LC32ScopedSensitiveWipe(void *bytes, size_t size)
        : bytes(bytes), size(size) {}

    ~LC32ScopedSensitiveWipe() {
        if (bytes != nullptr && size != 0) {
            volatile uint8_t *output =
                static_cast<volatile uint8_t *>(bytes);
            for (size_t index = 0; index < size; ++index) {
                output[index] = 0;
            }
        }
    }

    LC32ScopedSensitiveWipe(
        const LC32ScopedSensitiveWipe &) = delete;
    LC32ScopedSensitiveWipe &operator=(
        const LC32ScopedSensitiveWipe &) = delete;

private:
    void *bytes;
    size_t size;
};

static int GuestAesIoctlError(int error) {
    return return_with_carry_direct(error, true);
}

static bool GuestAesRangesOverlap(
        u32 first, u32 second, size_t size) {
    const u64 firstEnd = static_cast<u64>(first) + size;
    const u64 secondEnd = static_cast<u64>(second) + size;
    return static_cast<u64>(first) < secondEnd &&
        static_cast<u64>(second) < firstEnd;
}

static int guest_aes_ioctl(u32 request, u32 guest_arg) {
    if (request == LC32_AES_GET_INFO) {
        LC32AESInfo info{};
        info.maximumBytesPerCall =
            LC32_AES_MAXIMUM_BYTES_PER_CALL;
        if (guest_arg == 0 ||
                !write_guest_memory_with_permissions(
                    guest_arg, &info, sizeof(info), PROT_WRITE)) {
            return GuestAesIoctlError(EFAULT);
        }
        return return_with_carry_direct(0, false);
    }

    if (request != LC32_AES_CRYPT) {
        return GuestAesIoctlError(ENOTTY);
    }

    LC32AESCrypt crypt{};
    if (guest_arg == 0 ||
            !read_guest_memory_with_permissions(
                guest_arg, &crypt, sizeof(crypt), PROT_READ) ||
            !guest_memory_range_has_permissions(
                guest_arg, sizeof(crypt), PROT_WRITE)) {
        return GuestAesIoctlError(EFAULT);
    }
    LC32ScopedSensitiveWipe cryptWipe(&crypt, sizeof(crypt));

    if (crypt.decrypt > 1 ||
            (crypt.keyBits != 128 && crypt.keyBits != 192 &&
                crypt.keyBits != 256) ||
            crypt.dataLength == 0 ||
            crypt.dataLength % LC32_AES_BLOCK_SIZE != 0 ||
            crypt.dataLength > LC32_AES_MAXIMUM_BYTES_PER_CALL) {
        return GuestAesIoctlError(EINVAL);
    }

    const size_t dataLength = crypt.dataLength;
    const u32 source = crypt.decrypt
        ? crypt.secondBuffer : crypt.firstBuffer;
    const u32 destination = crypt.decrypt
        ? crypt.firstBuffer : crypt.secondBuffer;
    if (!GuestAddressRangeIsValid32(source, dataLength) ||
            !GuestAddressRangeIsValid32(
                destination, dataLength) ||
            !guest_memory_range_has_permissions(
                source, dataLength, PROT_READ) ||
            !guest_memory_range_has_permissions(
                destination, dataLength, PROT_WRITE)) {
        return GuestAesIoctlError(EFAULT);
    }

    /* Exact in-place operation is supported.  Reject shifted overlap because
     * chunked copyout could otherwise overwrite ciphertext that a later chunk
     * has not copied in yet. */
    if (source != destination &&
            GuestAesRangesOverlap(
                source, destination, dataLength)) {
        return GuestAesIoctlError(EINVAL);
    }

    const size_t bufferSize = std::min(
        dataLength, LC32_AES_WORKING_BUFFER_SIZE);
    std::vector<uint8_t> input;
    std::vector<uint8_t> output;
    try {
        input.resize(bufferSize);
        output.resize(bufferSize);
    } catch (const std::bad_alloc &) {
        return GuestAesIoctlError(ENOMEM);
    }
    LC32ScopedSensitiveWipe inputWipe(
        input.data(), input.size());
    LC32ScopedSensitiveWipe outputWipe(
        output.data(), output.size());
    std::array<uint8_t, LC32_AES_BLOCK_SIZE> chainingValue;
    memcpy(chainingValue.data(), crypt.iv, chainingValue.size());
    LC32ScopedSensitiveWipe ivWipe(
        chainingValue.data(), chainingValue.size());

    const CCOperation operation = crypt.decrypt
        ? kCCDecrypt : kCCEncrypt;
    const size_t keySize = crypt.keyBits / 8;
    size_t offset = 0;
    while (offset < dataLength) {
        const size_t chunkLength = std::min(
            dataLength - offset, input.size());
        if (!read_guest_memory_with_permissions(
                static_cast<u64>(source) + offset,
                input.data(), chunkLength, PROT_READ)) {
            return GuestAesIoctlError(EFAULT);
        }

        size_t moved = 0;
        const CCCryptorStatus status = CCCrypt(
            operation, kCCAlgorithmAES, 0,
            crypt.key, keySize, chainingValue.data(),
            input.data(), chunkLength,
            output.data(), output.size(), &moved);
        if (status != kCCSuccess || moved != chunkLength) {
            return GuestAesIoctlError(EIO);
        }

        const uint8_t *nextChainingValue = crypt.decrypt
            ? input.data() + chunkLength - LC32_AES_BLOCK_SIZE
            : output.data() + chunkLength - LC32_AES_BLOCK_SIZE;
        memcpy(chainingValue.data(), nextChainingValue,
            chainingValue.size());

        if (!write_guest_memory_with_permissions(
                static_cast<u64>(destination) + offset,
                output.data(), moved, PROT_WRITE)) {
            return GuestAesIoctlError(EFAULT);
        }
        offset += chunkLength;
    }

    memcpy(crypt.iv, chainingValue.data(), sizeof(crypt.iv));
    if (!write_guest_memory_with_permissions(
            guest_arg, &crypt, sizeof(crypt), PROT_WRITE)) {
        return GuestAesIoctlError(EFAULT);
    }
    return return_with_carry_direct(0, false);
}

int guest_ioctl(int fildes, u32 request, u32 guest_r2) {
    if (IsGuestAesFileDescriptor(fildes)) {
        return guest_aes_ioctl(request, guest_r2);
    }
    if (request == LC32_AES_GET_INFO ||
            request == LC32_AES_CRYPT) {
        /* Preserve EBADF for a closed descriptor and report ENOTTY for an
         * unrelated live descriptor without exposing a 32-bit pointer to the
         * host ioctl ABI. */
        const int descriptorStatus = syscallRetCarry(
            SYS_fcntl, fildes, F_GETFD, 0, 0, 0, 0, 0);
        if (threadHandle.cpsr->hasCarry()) {
            return descriptorStatus;
        }
        return GuestAesIoctlError(ENOTTY);
    }
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
            Dynarmic_current_user_callbacks()->MemoryWrite32(
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
    Dynarmic_current_user_callbacks()->ExceptionRaised(
        0xDEADDEAD, Dynarmic::A32::Exception::Yield);
    return -1;
}

int guest_pthread_sigmask(int how, u32 guest_set, u32 guest_oldset) {
    return GuestThreadSigmask(how, guest_set, guest_oldset);
}

ssize_t guest_readlink(u32 guest_pathname, u32 guest_buf, size_t bufsiz) {
    char copied_path[PATH_MAX];
    char host_pathname[PATH_MAX];
    int error = LC32CopyGuestCString(guest_pathname, copied_path);
    if(error == 0 && copied_path[0] == '\0') {
        error = ENOENT;
    }
    if(error == 0 && !sharedHandle.fs->pathGuestToHost(
            copied_path, host_pathname)) {
        error = errno != 0 ? errno : EINVAL;
    }
    if(error != 0) {
        return return_with_carry_direct(error, true);
    }

    /* readlink does not terminate its output. Stage a complete target so
     * reverse mount translation never examines uninitialized bytes. */
    std::array<char, PATH_MAX + 1> hostTarget = {};
    const int hostResult = syscallRetCarry(
        SYS_readlink, host_pathname, hostTarget.data(), PATH_MAX,
        0, 0, 0, 0);
    if(threadHandle.cpsr->hasCarry()) {
        return hostResult;
    }
    if(hostResult < 0 || hostResult > PATH_MAX) {
        return return_with_carry_direct(EIO, true);
    }
    hostTarget[static_cast<size_t>(hostResult)] = '\0';

    std::array<char, PATH_MAX> guestTarget = {};
    const char *visibleTarget = hostTarget.data();
    if(hostTarget[0] == '/') {
        errno = 0;
        if(!sharedHandle.fs->pathHostToGuest(
                hostTarget.data(), guestTarget.data())) {
            return return_with_carry_direct(
                errno != 0 ? errno : EINVAL, true);
        }
        visibleTarget = guestTarget.data();
    }

    const size_t copyLength = std::min(bufsiz, strlen(visibleTarget));
    if(copyLength != 0 && !write_guest_memory_with_permissions(
            guest_buf, visibleTarget, copyLength, PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return return_with_carry_direct(
        static_cast<int>(copyLength), false);
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
#ifdef F_DUPFD_CLOEXEC
        case F_DUPFD_CLOEXEC:
#endif
        {
            std::lock_guard<std::mutex> lock(
                guestAesFileDescriptorsMutex);
            const bool duplicateIsAes =
                guestAesFileDescriptors.count(fildes) != 0;
            const int result = syscallRetCarry(
                SYS_fcntl, fildes, cmd, guest_r2,
                0, 0, 0, 0);
            if (!threadHandle.cpsr->hasCarry() &&
                    result >= 0 && duplicateIsAes) {
                guestAesFileDescriptors.insert(result);
            }
            return result;
        }
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
        {
            /* fsignatures_t contains native-sized pointer and size fields.
             * Decode dyld's 32-bit ABI explicitly; fs_blob_start is a file
             * offset for F_ADDFILESIGS_RETURN, not a guest pointer. */
            struct GuestFSignatures {
                int64_t fileStart;
                u32 blobStart;
                u32 blobSize;
            } guestSignatures = {};
            static_assert(sizeof(guestSignatures) == 16,
                "unexpected guest fsignatures layout");
            if(!read_guest_memory_with_permissions(
                    guest_r2, &guestSignatures,
                    sizeof(guestSignatures), PROT_READ)) {
                return return_with_carry_direct(EFAULT, true);
            }

            fsignatures_t hostSignatures = {};
            hostSignatures.fs_file_start = guestSignatures.fileStart;
            hostSignatures.fs_blob_start =
                reinterpret_cast<void *>(
                    static_cast<uintptr_t>(
                        guestSignatures.blobStart));
            hostSignatures.fs_blob_size = guestSignatures.blobSize;
            /* Use the public entry point here rather than a raw syscall.
             * Jailbreaks interpose fcntl to trust and, on TXM systems,
             * normalize the signature before asking XNU to attach it. */
            errno = 0;
            const int result = fcntl(
                fildes, cmd, &hostSignatures);
            if(result == -1) {
                const int savedErrno = errno;
                return return_with_carry_direct(
                    savedErrno == 0 ? EIO : savedErrno, true);
            }

            guestSignatures.fileStart =
                hostSignatures.fs_file_start;
            /* XNU exposes only the returned coverage through the off_t
             * field; the pointer and size remain input-only. */
            if(!write_guest_memory_with_permissions(
                    guest_r2, &guestSignatures.fileStart,
                    sizeof(guestSignatures.fileStart), PROT_WRITE)) {
                return return_with_carry_direct(EFAULT, true);
            }
            return return_with_carry_direct(result, false);
        }
        case F_CHECK_LV:
            return 0;
        // r2 is a pointer
        case F_GETPATH: {
            char host_r2[PATH_MAX] = {};
            int result = syscallRetCarry(SYS_fcntl, fildes, cmd, host_r2, 0,0,0,0);
            if(threadHandle.cpsr->hasCarry()) {
                return result;
            }
            char translated_r2[PATH_MAX];
            if(!sharedHandle.fs->pathHostToGuest(host_r2, translated_r2)) {
                const int error = errno != 0 ? errno : EINVAL;
                return return_with_carry_direct(error, true);
            }
            const size_t translated_size = strlen(translated_r2) + 1;
            if(!write_guest_memory_with_permissions(
                    guest_r2, translated_r2, translated_size,
                    PROT_WRITE)) {
                return return_with_carry_direct(EFAULT, true);
            }
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
                Dynarmic_current_user_callbacks()->MemoryRead64(guest_r2);
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
            Dynarmic_current_user_callbacks()->ExceptionRaised(
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
    Dynarmic_current_user_callbacks()->MemoryWrite32(
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

static bool GuestVmRangeHasMappingLocked(
        u64 address, u64 size) {
    if (sharedHandle.memory == nullptr || size == 0 ||
            (address & DYN_PAGE_MASK) != 0 ||
            (size & DYN_PAGE_MASK) != 0 ||
            !GuestAddressRangeIsValid32(address, size)) {
        return false;
    }

    khash_t(memory) *memory = sharedHandle.memory;
    const u64 end = address + size;
    for (u64 page = address; page < end;
            page += DYN_PAGE_SIZE) {
        if (kh_get(memory, memory, page) != kh_end(memory)) {
            return true;
        }
    }
    return false;
}

kern_return_t guest__kernelrpc_mach_vm_allocate_trap(u32 target, u32 guest_address, mach_vm_size_t size, int flags) {
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }

    const bool anywhere = (flags & VM_FLAGS_ANYWHERE) != 0;
    const bool overwrite = (flags & VM_FLAGS_OVERWRITE) != 0;
    const u32 suppliedAddress =
        Dynarmic_current_user_callbacks()->MemoryRead32(guest_address);
    if (anywhere) {
        // Sometimes the address pointer will contain garbage value, change it to 0
        Dynarmic_current_user_callbacks()->MemoryWrite32(
            guest_address, 0);
    }

    if (size == 0) {
        Dynarmic_current_user_callbacks()->MemoryWrite32(
            guest_address, 0);
        return KERN_SUCCESS;
    }
    if (size > UINT64_MAX - DYN_PAGE_MASK) {
        return KERN_NO_SPACE;
    }

    const u64 allocationSize =
        (size + DYN_PAGE_MASK) & ~u64(DYN_PAGE_MASK);
    const u32 requestedAddress = anywhere ? 0 :
        suppliedAddress & ~u32(DYN_PAGE_MASK);
    if (!GuestAddressRangeIsValid32(
            requestedAddress, allocationSize)) {
        return KERN_NO_SPACE;
    }

    u32 result;
    if (!anywhere && !overwrite) {
        /*
         * Unlike mmap(MAP_FIXED), fixed-address vm_allocate does not replace
         * existing mappings unless VM_FLAGS_OVERWRITE was explicitly passed.
         * Keep the collision preflight and mapping atomic so another native
         * guest thread cannot claim a page between the two operations.
         */
        std::lock_guard<std::recursive_mutex> lock(guestVmMutex);
        if (GuestVmRangeHasMappingLocked(
                requestedAddress, allocationSize)) {
            return KERN_NO_SPACE;
        }
        result = Dynarmic_mmap(
            requestedAddress, allocationSize,
            PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED,
            -1, 0);
    } else {
        result = Dynarmic_mmap(
            requestedAddress, allocationSize,
            PROT_READ | PROT_WRITE,
            MAP_PRIVATE | MAP_ANONYMOUS |
                (anywhere ? 0 : MAP_FIXED),
            -1, 0);
    }
    if (result == -1) {
        return KERN_NO_SPACE;
    }
    Dynarmic_current_user_callbacks()->MemoryWrite32(
        guest_address, result);
    return KERN_SUCCESS;
}

kern_return_t guest__kernelrpc_mach_port_construct_trap(mach_port_name_t target, u32 guest_options, u64 context, u32 guest_name) {
    mach_port_options_t host_options;
    mach_port_name_t host_name;
    Dynarmic_mem_1read(guest_options, sizeof(host_options), (char *)&host_options);
    kern_return_t result = _kernelrpc_mach_port_construct_trap(target, &host_options, context, &host_name);
    Dynarmic_current_user_callbacks()->MemoryWrite32(
        guest_name, host_name);
    return result;
}

kern_return_t guest__kernelrpc_mach_port_allocate_trap(mach_port_name_t target, mach_port_right_t right, u32 guest_name) {
    mach_port_name_t host_name;
    kern_return_t result = _kernelrpc_mach_port_allocate_trap(target, right, &host_name);
    Dynarmic_current_user_callbacks()->MemoryWrite32(
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
        Dynarmic_current_user_callbacks()->MemoryRead32(guest_address),
        size, cur_protection, MAP_PRIVATE | MAP_ANONYMOUS,
        -1, 0, mask ?: DYN_PAGE_MASK);
    if (result == -1) {
        return KERN_NO_SPACE;
    }
    Dynarmic_current_user_callbacks()->MemoryWrite32(
        guest_address, result);
    return KERN_SUCCESS;
}

kern_return_t guest__kernelrpc_mach_vm_deallocate_trap(u32 target, vm_address_t address, mach_vm_size_t size) {
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }
    if (size == 0) {
        return KERN_SUCCESS;
    }
    if (size > UINT64_MAX - address) {
        return KERN_INVALID_ARGUMENT;
    }
    const u64 end = static_cast<u64>(address) + size;
    if (end > (UINT64_C(1) << 32) ||
            end > UINT64_MAX - DYN_PAGE_MASK) {
        return KERN_INVALID_ADDRESS;
    }
    /*
     * mach_vm_deallocate rounds an arbitrary byte range out to VM pages.
     * This matters for OOL MIG arrays such as task_threads: callers release
     * count * sizeof(mach_port_t), not the page-rounded backing allocation.
     */
    const u64 alignedAddress =
        static_cast<u64>(address) & ~u64(DYN_PAGE_MASK);
    const u64 alignedEnd =
        (end + DYN_PAGE_MASK) & ~u64(DYN_PAGE_MASK);
    return Dynarmic_munmap(
        alignedAddress, alignedEnd - alignedAddress) == 0
        ? KERN_SUCCESS
        : KERN_FAILURE;
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

namespace {

constexpr u32 LC32CryptIDNoEncryption = 0;
constexpr u32 LC32CryptIDAppEncryption = 1;
constexpr u32 LC32CryptIDModelEncryption = 2;
constexpr u32 LC32CryptIDNullEncryption = 0x10;

struct LC32HostVMRegion {
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_prot_t protection = VM_PROT_NONE;
    vm_prot_t maximumProtection = VM_PROT_NONE;
};

int LC32ErrnoForMachVMResult(kern_return_t result) {
    switch(result) {
        case KERN_INVALID_ADDRESS:
            return EFAULT;
        case KERN_PROTECTION_FAILURE:
            return EACCES;
        case KERN_MEMORY_ERROR:
        case KERN_MEMORY_FAILURE:
            return EIO;
        case KERN_NO_SPACE:
        case KERN_RESOURCE_SHORTAGE:
            return ENOMEM;
        case KERN_INVALID_ARGUMENT:
        default:
            return EINVAL;
    }
}

bool LC32QueryHostVMRegion(
        vm_address_t address, LC32HostVMRegion *result) {
    if(result == nullptr) return false;

    vm_address_t regionAddress = address;
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
    if(objectName != MACH_PORT_NULL) {
        (void)mach_port_deallocate(mach_task_self(), objectName);
    }
    if(regionResult != KERN_SUCCESS ||
            address < regionAddress ||
            address - regionAddress >= regionSize) {
        return false;
    }

    result->address = regionAddress;
    result->size = regionSize;
    result->protection = regionInfo.protection;
    result->maximumProtection = regionInfo.max_protection;
    return true;
}

} // anonymous namespace

int Dynarmic_mremap_encrypted(
        u32 start, u32 length, u32 cryptid,
        u32 cpuType, u32 cpuSubtype,
        const void *hostSource) {
    if((start & DYN_PAGE_MASK) != 0 ||
            !GuestAddressRangeIsValid32(start, length)) {
        return EINVAL;
    }

    switch(cryptid) {
        case LC32CryptIDNoEncryption:
            /* XNU treats an empty LC_ENCRYPTION_INFO as a no-op before
             * looking up the supplied address. */
            return 0;
        case LC32CryptIDAppEncryption:
        case LC32CryptIDModelEncryption:
        case LC32CryptIDNullEncryption:
            break;
        default:
            return EINVAL;
    }

    std::unique_lock<std::recursive_mutex> lock(guestVmMutex);
    khash_t(memory) *memory = sharedHandle.memory;
    if(memory == nullptr) {
        return EFAULT;
    }

    const u64 guestEnd = static_cast<u64>(start) + length;
    const u64 mappedEnd = length == 0
        ? static_cast<u64>(start) + DYN_PAGE_SIZE
        : (guestEnd + DYN_PAGE_MASK) & ~u64(DYN_PAGE_MASK);
    uintptr_t hostStart =
        reinterpret_cast<uintptr_t>(hostSource);
    bool firstPage = hostSource == nullptr;
    for(u64 guestPageAddress = start;
            guestPageAddress < mappedEnd;
            guestPageAddress += DYN_PAGE_SIZE) {
        const khiter_t iterator = kh_get(
            memory, memory, guestPageAddress);
        if(iterator == kh_end(memory)) {
            return EFAULT;
        }
        t_memory_page page = kh_value(memory, iterator);
        if(page == nullptr || page->addr == nullptr) {
            return EFAULT;
        }
        if(length != 0 &&
                cryptid != LC32CryptIDModelEncryption &&
                (page->perms & PROT_EXEC) == 0) {
            return EINVAL;
        }

        if(hostSource == nullptr) {
            const uintptr_t hostPage =
                reinterpret_cast<uintptr_t>(page->addr);
            if(firstPage) {
                hostStart = hostPage;
                firstPage = false;
            } else if(hostPage != hostStart +
                    static_cast<uintptr_t>(
                        guestPageAddress - start)) {
                /* A single native remap must never span unrelated guest
                 * backings merely because their guest addresses are
                 * adjacent. */
                return EINVAL;
            }
        }
    }

    /* A nonzero cryptid with zero length still has to name a mapped vnode in
     * XNU, but it does not install a pager or alter any bytes. The mapped-page
     * validation above preserves the useful part of that contract without
     * creating a zero-sized staging alias. */
    if(length == 0) {
        return 0;
    }

    const uintptr_t hostPageSize = vm_page_size;
    if(hostPageSize == 0 ||
            (hostPageSize & (hostPageSize - 1)) != 0) {
        return EINVAL;
    }
    if((hostStart & (hostPageSize - 1)) != 0) {
        /* Expanding the request backwards to a native-page boundary changes
         * both crypto_start and the vnode backing offset, which can make the
         * FairPlay pager decrypt plaintext preceding a 4K-aligned range. */
        return EINVAL;
    }
    const uintptr_t hostBase = hostStart;
    const size_t leadingBytes = 0;
    const size_t protectedLength = length;
    if(protectedLength > SIZE_MAX - (hostPageSize - 1)) {
        return EINVAL;
    }
    const size_t stagingSize =
        (protectedLength + hostPageSize - 1) & ~(hostPageSize - 1);
    if(hostBase > UINTPTR_MAX - stagingSize) {
        return EINVAL;
    }

    LC32HostVMRegion sourceRegion;
    if(!LC32QueryHostVMRegion(
            static_cast<vm_address_t>(hostBase), &sourceRegion) ||
            sourceRegion.address > hostBase ||
            sourceRegion.size < hostBase - sourceRegion.address ||
            sourceRegion.size - (hostBase - sourceRegion.address) <
                stagingSize) {
        return EFAULT;
    }
    const vm_prot_t stagingRequiredProtection =
        cryptid == LC32CryptIDModelEncryption
            ? VM_PROT_READ
            : VM_PROT_READ | VM_PROT_EXECUTE;
    if((sourceRegion.maximumProtection &
            stagingRequiredProtection) !=
            stagingRequiredProtection) {
        return EACCES;
    }

    std::vector<uint8_t> decryptedBytes;
    try {
        decryptedBytes.resize(length);
    } catch(const std::exception &) {
        return ENOMEM;
    }

    /*
     * Never replace the live guest backing with the protected pager. Besides
     * preserving dyld/debugger writes, the discardable alias retains the
     * original vnode and object offset, which select the license and position
     * the decryption key.
     */
    const bool callerOwnsStagingMapping = hostSource != nullptr;
    vm_address_t stagingAddress = callerOwnsStagingMapping
        ? static_cast<vm_address_t>(hostBase) : 0;
    vm_prot_t stagingProtection = VM_PROT_NONE;
    vm_prot_t stagingMaximumProtection = VM_PROT_NONE;
    kern_return_t vmResult = KERN_SUCCESS;
    if(callerOwnsStagingMapping) {
        stagingProtection = sourceRegion.protection;
        stagingMaximumProtection = sourceRegion.maximumProtection;
    } else {
        vmResult = vm_remap(
            mach_task_self(), &stagingAddress,
            static_cast<vm_size_t>(stagingSize), 0,
            VM_FLAGS_ANYWHERE, mach_task_self(),
            static_cast<vm_address_t>(hostBase), FALSE,
            &stagingProtection, &stagingMaximumProtection,
            VM_INHERIT_NONE);
        if(vmResult != KERN_SUCCESS) {
            return LC32ErrnoForMachVMResult(vmResult);
        }
    }
    const auto releaseStagingMapping = [&] {
        if(!callerOwnsStagingMapping && stagingAddress != 0 && vm_deallocate(
                mach_task_self(), stagingAddress,
                static_cast<vm_size_t>(stagingSize)) != KERN_SUCCESS) {
            fprintf(stderr,
                "LC32: could not release mremap_encrypted staging "
                "mapping at %p\n",
                reinterpret_cast<void *>(stagingAddress));
        }
        stagingAddress = 0;
    };

    if((stagingMaximumProtection &
            stagingRequiredProtection) !=
            stagingRequiredProtection) {
        releaseStagingMapping();
        return EACCES;
    }
    vmResult = vm_protect(
        mach_task_self(), stagingAddress,
        static_cast<vm_size_t>(stagingSize), FALSE,
        stagingRequiredProtection);
    if(vmResult != KERN_SUCCESS) {
        releaseStagingMapping();
        return LC32ErrnoForMachVMResult(vmResult);
    }

    const bool originalCarry = threadHandle.cpsr->hasCarry();
    const int remapResult = syscallRetCarry(
        SYS_mremap_encrypted,
        stagingAddress, protectedLength, cryptid,
        cpuType, cpuSubtype, 0, 0);
    const bool remapFailed = threadHandle.cpsr->hasCarry();
    threadHandle.cpsr->setCarry(originalCarry);
    if(remapFailed) {
        releaseStagingMapping();
        return remapResult;
    }

    /* Fault the protected pager through this task's ordinary RX mapping.
     * A self vm_read_overwrite() takes the out-of-line Mach copy path and can
     * wait indefinitely while FairPlay services the protected object. */
    const auto *protectedBytes = reinterpret_cast<const uint8_t *>(
        stagingAddress + leadingBytes);
    memcpy(decryptedBytes.data(), protectedBytes, length);
    releaseStagingMapping();

    if(ReplaceGuestMemoryRangeWithPrivateCopy(
            start, length, decryptedBytes.data()) != 0) {
        const int savedErrno = errno;
        return savedErrno;
    }
    lock.unlock();
    InvalidateAllGuestJits(start, length);
    return 0;
}

int guest_mremap_encrypted(
        u32 start, u32 length, u32 cryptid,
        u32 cpuType, u32 cpuSubtype) {
    const int error = Dynarmic_mremap_encrypted(
        start, length, cryptid, cpuType, cpuSubtype);
    return return_with_carry_direct(error, error != 0);
}
