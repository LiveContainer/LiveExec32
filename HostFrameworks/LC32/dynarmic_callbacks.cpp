#include "dynarmic_internal.h"
#include "dynarmic_syscalls.h"
#include "crash_exception.h"

namespace {
struct GuestCrashExceptionPayload {
    std::string report;
    std::string fallbackReason;
    uint32_t fallbackNamespace;
    uint64_t fallbackCode;
};
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

[[noreturn]] static void ThrowGuestCrashExceptionPayload(
        const GuestAbortMetadata &metadata,
        std::string fullReport,
        std::string compactReason) {
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

    /* DumpCrashReport catches this private transport value before its broad
     * failure handlers, then raises the Objective-C exception from that
     * handler. An NSException raised here would otherwise be swallowed by
     * the catch (...) which protects report construction. */
    throw GuestCrashExceptionPayload{
        std::move(fullReport), std::move(compactReason),
        reasonNamespace, reasonCode};
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
        if (isBkpt && ConsumeGuestSoftwareTracepoint(pc, cpu)) {
            return;
        }
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
#ifdef LC32_GUEST_MEMORY_WATCH_ADDRESS
        LogGuestMemoryWatchConsistency("crash");
#endif
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
        } catch (const GuestCrashExceptionPayload &crash) {
            dumpingBacktrace = false;
            LC32ThrowGuestCrashException(
                crash.report.data(), crash.report.size(),
                crash.fallbackNamespace, crash.fallbackCode,
                crash.fallbackReason.c_str());
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
        ThrowGuestCrashExceptionPayload(
            abortMetadata, std::move(report), std::move(compactReason));
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
            case SYS_getpid: // 20
            case SYS_setuid: // 23
            case SYS_getuid: // 24
            case SYS_geteuid: // 25
            case SYS_getppid: // 39
            case SYS_getegid: // 43
            case SYS_getgid: // 47
            case SYS_socket: // 97
            case SYS_issetugid: // 327
                cpu->Regs()[0] = syscallRetCarry(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                cpsr->setCarry(false); // FIXME: mach_reply_port sets carry to true, idk why
                break;
            case -18: { // _kernelrpc_mach_port_deallocate_trap
                const u64 result = syscallRetCarry(
                    (long)NR, cpu->Regs()[0], cpu->Regs()[1]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
            } break;
            // direct call returning a 64-bit value
            case -3: { // mach_absolute_time
                const u64 result = mach_absolute_time();
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                cpsr->setCarry(false);
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
                StopGuestCallbackExecutor();
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
            case SYS_close: // 6
            case SYS_close_nocancel: // 399
                cpu->Regs()[0] = guest_close(
                    NR, static_cast<int>(cpu->Regs()[0]));
                break;
            case SYS_dup: // 41
                cpu->Regs()[0] = guest_dup(
                    static_cast<int>(cpu->Regs()[0]));
                break;
            case SYS_dup2: // 90
                cpu->Regs()[0] = guest_dup2(
                    static_cast<int>(cpu->Regs()[0]),
                    static_cast<int>(cpu->Regs()[1]));
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
            case SYS_sigaltstack: // 53
                cpu->Regs()[0] = GuestSigaltstack(
                    cpu->Regs()[0], cpu->Regs()[1]);
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
            case SYS_connect: // 98
            case SYS_connect_nocancel: // 409
                cpu->Regs()[0] = guest_connect(
                    NR, static_cast<int>(cpu->Regs()[0]),
                    cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_select: // 93
            case SYS_select_nocancel: // 407
                /* The armv7 wrapper places timeval * in r4. */
                cpu->Regs()[0] = guest_select(
                    NR, static_cast<int>(cpu->Regs()[0]),
                    cpu->Regs()[1], cpu->Regs()[2],
                    cpu->Regs()[3], cpu->Regs()[4]);
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
            case SYS_sendto: // 133
            case SYS_sendto_nocancel: // 413
                /* The armv7 wrapper places destination/length in r4/r5. */
                cpu->Regs()[0] = static_cast<u32>(guest_sendto(
                    NR, static_cast<int>(cpu->Regs()[0]),
                    cpu->Regs()[1], cpu->Regs()[2],
                    static_cast<int>(cpu->Regs()[3]),
                    cpu->Regs()[4], cpu->Regs()[5]));
                break;
            case SYS_socketpair: // 135
                cpu->Regs()[0] = guest_socketpair(
                    static_cast<int>(cpu->Regs()[0]),
                    static_cast<int>(cpu->Regs()[1]),
                    static_cast<int>(cpu->Regs()[2]),
                    cpu->Regs()[3]);
                break;
            case SYS_sendmsg: // 28
            case SYS_sendmsg_nocancel: // 402
                cpu->Regs()[0] = static_cast<u32>(guest_sendmsg(
                    NR, static_cast<int>(cpu->Regs()[0]),
                    cpu->Regs()[1],
                    static_cast<int>(cpu->Regs()[2])));
                break;
            case SYS_mkdir: // 136
                cpu->Regs()[0] = guest_mkdir(
                    cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case SYS_setxattr: // 236
                /* libsystem_kernel's ARM wrapper moves arguments five and
                 * six (position and options) from the caller stack into
                 * r4/r5 before issuing the SVC. */
                cpu->Regs()[0] = guest_setxattr(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2], cpu->Regs()[3],
                    cpu->Regs()[4], cpu->Regs()[5]);
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
            case 307: { // psynch_rw_wrlock
                const bool tracePsynchRw =
                    getenv("LC32_TRACE_PSYNCH_RW") != nullptr;
                if(tracePsynchRw) {
                    fprintf(stderr,
                        "LC32: psynch_rw enter tid=%llu nr=%d "
                        "r0=%08x r1=%08x r2=%08x r3=%08x "
                        "r4=%08x r5=%08x r6=%08x\n",
                        CurrentGuestThreadId(), NR,
                        cpu->Regs()[0], cpu->Regs()[1],
                        cpu->Regs()[2], cpu->Regs()[3],
                        cpu->Regs()[4], cpu->Regs()[5],
                        cpu->Regs()[6]);
                    fflush(stderr);
                }
                cpu->Regs()[0] =
                    GuestPsynchRwWait(
                        cpu->Regs()[0], cpu->Regs()[1],
                        cpu->Regs()[3], NR != 306);
                if(tracePsynchRw) {
                    fprintf(stderr,
                        "LC32: psynch_rw return tid=%llu nr=%d "
                        "result=%08x carry=%u\n",
                        CurrentGuestThreadId(), NR,
                        cpu->Regs()[0], cpsr->hasCarry());
                    fflush(stderr);
                }
                break;
            }
            case 301: // psynch_mutexwait
                cpu->Regs()[0] = GuestPsynchMutexWait(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2], cpu->Regs()[5]);
                break;
            case 302: // psynch_mutexdrop
                cpu->Regs()[0] = GuestPsynchMutexDrop(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2], cpu->Regs()[5]);
                break;
            case 303: // psynch_cvbroad
                cpu->Regs()[0] = GuestPsynchConditionSignal(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2], cpu->Regs()[3],
                    MACH_PORT_NULL, true);
                break;
            case 304: // psynch_cvsignal
                cpu->Regs()[0] = GuestPsynchConditionSignal(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2], cpu->Regs()[3],
                    static_cast<mach_port_t>(cpu->Regs()[4]),
                    false);
                break;
            case 305: { // psynch_cvwait
                /* The ARMv7 syscall veneer saves r4-r6/r8.  Relative
                 * timeout seconds and nanoseconds are therefore at the
                 * original arguments' stack slots, sp+32 and sp+40. */
                const u32 stack = cpu->Regs()[Reg::SP];
                const u64 timeoutSecondsBits =
                    static_cast<u64>(MemoryRead32(
                        stack + 32, false)) |
                    (static_cast<u64>(MemoryRead32(
                        stack + 36, false)) << 32);
                cpu->Regs()[0] = GuestPsynchConditionWait(
                    cpu->Regs()[0], cpu->Regs()[1],
                    cpu->Regs()[2], cpu->Regs()[4],
                    static_cast<int64_t>(timeoutSecondsBits),
                    MemoryRead32(stack + 40, false));
                break;
            }
            case 308: // psynch_rw_unlock
            case 309: { // psynch_rw_unlock2
                const bool tracePsynchRw =
                    getenv("LC32_TRACE_PSYNCH_RW") != nullptr;
                if(tracePsynchRw) {
                    fprintf(stderr,
                        "LC32: psynch_rw enter tid=%llu nr=%d "
                        "r0=%08x r1=%08x r2=%08x r3=%08x "
                        "r4=%08x r5=%08x r6=%08x\n",
                        CurrentGuestThreadId(), NR,
                        cpu->Regs()[0], cpu->Regs()[1],
                        cpu->Regs()[2], cpu->Regs()[3],
                        cpu->Regs()[4], cpu->Regs()[5],
                        cpu->Regs()[6]);
                    fflush(stderr);
                }
                cpu->Regs()[0] =
                    GuestPsynchRwUnlock(
                        cpu->Regs()[0], cpu->Regs()[1],
                        cpu->Regs()[2], cpu->Regs()[3]);
                if(tracePsynchRw) {
                    fprintf(stderr,
                        "LC32: psynch_rw return tid=%llu nr=%d "
                        "result=%08x carry=%u\n",
                        CurrentGuestThreadId(), NR,
                        cpu->Regs()[0], cpsr->hasCarry());
                    fflush(stderr);
                }
                break;
            }
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
            case SYS_kqueue: // 362
                /*
                 * Guest file descriptors are native descriptors throughout
                 * the syscall bridge. kqueue has no arguments, so unlike
                 * kevent there are no pointer-width-dependent structures to
                 * translate here.
                 */
                cpu->Regs()[0] = syscallRetCarry(
                    SYS_kqueue, 0, 0, 0, 0, 0, 0, 0);
                break;
            case SYS_kevent: // 363
                /* r4/r5 hold arguments five and six in the armv7 SVC ABI. */
                cpu->Regs()[0] = guest_kevent(
                    static_cast<int>(cpu->Regs()[0]),
                    cpu->Regs()[1], static_cast<int>(cpu->Regs()[2]),
                    cpu->Regs()[3], static_cast<int>(cpu->Regs()[4]),
                    cpu->Regs()[5]);
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
                        !NativeGuestWorkqueueIsCurrent() &&
                        cpu->Regs()[0] == 0 &&
                        (operation == WQOPS_THREAD_RETURN ||
                         operation == WQOPS_THREAD_KEVENT_RETURN)) {
                    /*
                     * A cooperative worker overlays the main JIT, so restore
                     * its saved context instead of returning on the worker
                     * stack. A one-shot native worker intentionally receives
                     * a zero return: iOS 10 libpthread then follows its
                     * thexit path and performs normal pthread cleanup before
                     * bsdthread_terminate retires the host-backed JIT.
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
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return hostCall(cpu->Regs()[2], cpu->Regs()[3],
                        cpu->Regs()[Reg::SP]);
                });
                cpu->Regs()[0] = result;
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
                u64 result = InvokeNativeGuestHostCall([&] {
                    return LC32InvokeHostSelector(
                        host_self, host_cmd, cpu->Regs()[Reg::SP]);
                });
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
                u64 result = InvokeNativeGuestHostCall([&] {
                    return LC32GetHostObject(
                        cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                });
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
                u64 result = InvokeNativeGuestHostCall([&] {
                    return LC32InvokeHostNSStringFormat(
                        host_self, host_selector, host_format, host_locale,
                        guest_arguments, options);
                });
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
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32CopyHostStringUTF8(
                        host_object, cpu->Regs()[2], cpu->Regs()[3]);
                });
                cpu->Regs()[0] = result;
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
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32CopyHostDataBytes(
                        host_object, cpu->Regs()[2], cpu->Regs()[3],
                        offset);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1013: { // LC32CopyHostStringBytes
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u64 host_object = (u64)cpu->Regs()[0] |
                    ((u64)cpu->Regs()[1] << 32);
                const u32 guest_output = cpu->Regs()[3];
                const u32 capacity =
                    Dynarmic_current_user_callbacks()->MemoryRead32(
                        cpu->Regs()[Reg::SP]);
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32CopyHostStringBytes(
                        host_object, cpu->Regs()[2], guest_output,
                        capacity);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1014: { // LC32HostStringRangeOfString
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                LC32FoundationStringRangeRequest request = {};
                const u32 guestRequest = cpu->Regs()[0];
                u64 result = (u64)INT32_MAX;
                if(guestRequest && Dynarmic_mem_1read(
                        guestRequest, sizeof(request),
                        reinterpret_cast<char *>(&request)) == 0 &&
                        request.version ==
                            LC32FoundationStringRangeABIVersion &&
                        request.byteSize == sizeof(request) &&
                        request.variant <=
                            LC32FoundationStringRangeWithLocale) {
                    result = InvokeNativeGuestHostCall([&] {
                        return LC32HostStringRangeOfString(&request);
                    });
                } else {
                    fprintf(stderr,
                            "LC32: invalid NSString range bridge request\n");
                }
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1020: { // LC32CopyHostCString
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u64 host_cstring = (u64)cpu->Regs()[0] |
                    ((u64)cpu->Regs()[1] << 32);
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32CopyHostCString(
                        host_cstring, cpu->Regs()[2], cpu->Regs()[3]);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1015: { // LC32CreateHostBlock
                if(cpu->IsExecuting()) {
                    // Copying a stack block and creating a native block both
                    // call back into guest/host runtimes. Leave the SVC before
                    // performing that nested work.
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u64 result = InvokeNativeGuestHostCall([&] {
                    return LC32CreateHostBlock(cpu->Regs()[0]);
                });
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1016: { // LC32GuestObjectForOwnedHostObjectAddress
                if(cpu->IsExecuting()) {
                    // Proxy conversion invokes guest Objective-C helpers.
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u64 hostObject = (u64)cpu->Regs()[0] |
                    ((u64)cpu->Regs()[1] << 32);
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32GuestObjectForOwnedHostObjectAddress(
                        hostObject);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1017: { // LC32GuestCallbackExecutorWait
                if(cpu->IsExecuting()) {
                    // The host wait and the later callback must happen only
                    // after this JIT callback has unwound.
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return ServiceGuestCallbackExecutorWait(
                        cpu->Regs()[0]);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1018: { // LC32GuestCallbackExecutorComplete
                cpu->Regs()[0] = ServiceGuestCallbackExecutorComplete(
                    cpu->Regs()[0]);
                break;
            }
            case 1019: { // LC32TryRetainHostWeakReference
                if(cpu->IsExecuting()) {
                    // Native objc_loadWeakRetained may initialize/custom-dispatch.
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32TryRetainHostWeakReference(
                        cpu->Regs()[0]);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1021: { // LC32FinishHostWeakRetain
                if(cpu->IsExecuting()) {
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32FinishHostWeakRetain(
                        cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                });
                cpu->Regs()[0] = result;
                break;
            }
            case 1022: { // LC32LookupHostMapping
                const u64 result = LC32LookupHostMapping(cpu->Regs()[0]);
                cpu->Regs()[0] = static_cast<u32>(result);
                cpu->Regs()[1] = static_cast<u32>(result >> 32);
                break;
            }
            case 1023: { // LC32UpdateHostMapping
                if(cpu->IsExecuting()) {
                    /* Publishing may initialize native Objective-C weak
                     * storage, so unwind the JIT before entering libobjc. */
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                const u32 guestObject = cpu->Regs()[0];
                const auto operation =
                    static_cast<LC32HostMappingOperation>(cpu->Regs()[1]);
                const u64 hostObject = static_cast<u64>(cpu->Regs()[2]) |
                    (static_cast<u64>(cpu->Regs()[3]) << 32);
                const u32 result = InvokeNativeGuestHostCall([&] {
                    return LC32UpdateHostMapping(
                        guestObject, operation, hostObject);
                });
                cpu->Regs()[0] = result;
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
        return NativeGuestThreadsEnabled()
            ? LC32NativeGuestRunSliceTicks
            : 0x10000000000ULL;
    }

    khash_t(memory) *memory = NULL;
    size_t num_page_table_entries;
    void **page_table = NULL;
    Dynarmic::A32::Jit *cpu;
    DynarmicCpsr *cpsr;
    std::shared_ptr<DynarmicCP15> cp15;
};

DynarmicCallbacks32 *CreateDynarmicCallbacks32(
        khash_t(memory) *memory) {
    return new DynarmicCallbacks32(memory);
}

void DestroyDynarmicCallbacks32(
        DynarmicCallbacks32 *callbacks) {
    if (callbacks != nullptr) {
        callbacks->destroy();
    }
}

Dynarmic::A32::UserCallbacks *DynarmicCallbacks32UserCallbacks(
        DynarmicCallbacks32 *callbacks) {
    return callbacks;
}

const std::shared_ptr<DynarmicCP15> &DynarmicCallbacks32CP15(
        DynarmicCallbacks32 *callbacks) {
    static const std::shared_ptr<DynarmicCP15> empty;
    return callbacks != nullptr ? callbacks->cp15 : empty;
}

void DynarmicCallbacks32SetPageTable(
        DynarmicCallbacks32 *callbacks, size_t entryCount,
        void **pageTable) {
    if (callbacks == nullptr) {
        return;
    }
    callbacks->num_page_table_entries = entryCount;
    callbacks->page_table = pageTable;
}

void DynarmicCallbacks32BindJit(
        DynarmicCallbacks32 *callbacks,
        Dynarmic::A32::Jit *jit, DynarmicCpsr *cpsr) {
    if (callbacks == nullptr) {
        return;
    }
    callbacks->cpu = jit;
    callbacks->cpsr = cpsr;
}

Dynarmic::A32::Jit *DynarmicCallbacks32Jit(
        DynarmicCallbacks32 *callbacks) {
    return callbacks != nullptr ? callbacks->cpu : nullptr;
}

static Dynarmic::A32::UserCallbacks *CurrentUserCallbacks() {
    return threadHandle.cb != nullptr
        ? static_cast<Dynarmic::A32::UserCallbacks *>(
            threadHandle.cb)
        : sharedHandle.ucb;
}

Dynarmic::A32::UserCallbacks *Dynarmic_current_user_callbacks() {
    return CurrentUserCallbacks();
}
