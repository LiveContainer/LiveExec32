#import "block_bridge.h"

#import "bridge.h"

#include <dispatch/dispatch.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <pthread.h>
#include <unordered_map>

extern "C" id objc_autorelease(id object);
extern "C" id objc_retain(id object);
extern "C" void objc_release(id object);

namespace {

struct GuestBlockLiteral32 {
    u32 isa;
    u32 flags;
    u32 reserved;
    u32 invoke;
    u32 descriptor;
};

constexpr u32 BlockHasCopyDispose = 1U << 25;
constexpr u32 BlockHasSignature = 1U << 30;
constexpr size_t MaxLogicalArguments = 5;
constexpr size_t MaxHostArgumentSlots = 8;
constexpr size_t MaxGuestArgumentWords = 16;

static pthread_once_t GuestBlockTraceOnce = PTHREAD_ONCE_INIT;
static bool GuestBlockTraceIsEnabled;
static std::atomic<u64> GuestBlockTraceSequence{0};

static void InitializeGuestBlockTrace() {
    const char *value = getenv("LC32_BLOCK_TRACE");
    GuestBlockTraceIsEnabled =
        value != nullptr && value[0] != '\0' && strcmp(value, "0") != 0;
}

static bool GuestBlockTraceEnabled() {
    pthread_once(&GuestBlockTraceOnce, InitializeGuestBlockTrace);
    return GuestBlockTraceIsEnabled;
}

enum class BlockValueKind : uint32_t {
    Void = LC32GuestBlockValueVoid,
    Object = LC32GuestBlockValueObject,
    SignedChar = LC32GuestBlockValueSignedChar,
    Signed32 = LC32GuestBlockValueSigned32,
    Unsigned32 = LC32GuestBlockValueUnsigned32,
    Signed64 = LC32GuestBlockValueSigned64,
    Unsigned64 = LC32GuestBlockValueUnsigned64,
    Range = LC32GuestBlockValueRange,
    CharPointer = LC32GuestBlockValueCharPointer,
};

struct BlockSignature {
    BlockValueKind result = BlockValueKind::Void;
    std::array<BlockValueKind, MaxLogicalArguments> arguments = {};
    size_t argumentCount = 0;
    size_t hostArgumentSlots = 0;
};

class GuestBlockContext {
public:
    GuestBlockContext(u32 block, const GuestBlockLiteral32 &literal,
                      const BlockSignature &signature,
                      const char *encoding)
        : block(block), literal(literal), signature(signature) {
        strlcpy(this->encoding, encoding, sizeof(this->encoding));
    }

    ~GuestBlockContext() { LC32ReleaseGuestBlock(block); }

    u32 block;
    GuestBlockLiteral32 literal;
    BlockSignature signature;
    char encoding[128] = {};
};

static void TraceGuestBlockCreation(u32 originalBlock, u32 copiedBlock,
                                    const GuestBlockLiteral32 &literal,
                                    const char *encoding) {
    if(!GuestBlockTraceEnabled()) return;

    u32 blockSize = 0;
    if(literal.descriptor) {
        (void)Dynarmic_mem_1read(
            literal.descriptor + sizeof(u32), sizeof(blockSize),
            reinterpret_cast<char *>(&blockSize));
    }
    blockSize = std::min<u32>(blockSize, 64);
    std::array<u32, 16> words = {};
    if(blockSize) {
        (void)Dynarmic_mem_1read(
            copiedBlock, blockSize, reinterpret_cast<char *>(words.data()));
    }

    const u64 sequence = GuestBlockTraceSequence.fetch_add(
        1, std::memory_order_relaxed);
    fprintf(stderr,
        "LC32 block[%llu]: create original=0x%08x copy=0x%08x "
        "invoke=0x%08x flags=0x%08x descriptor=0x%08x size=%u "
        "signature=%s words=",
        (unsigned long long)sequence, originalBlock, copiedBlock,
        literal.invoke, literal.flags, literal.descriptor, blockSize,
        encoding ?: "(null)");
    for(size_t index = 0; index < blockSize / sizeof(u32); index++) {
        fprintf(stderr, "%s%08x", index ? "," : "", words[index]);
    }
    fputc('\n', stderr);
    fflush(stderr);
}

static void TraceGuestBlockInvocation(const char *event,
                                      const GuestBlockContext &context,
                                      const u64 *hostArguments,
                                      u64 result = 0) {
    if(!GuestBlockTraceEnabled()) return;
    const u64 sequence = GuestBlockTraceSequence.fetch_add(
        1, std::memory_order_relaxed);
    NSOperationQueue *operationQueue = NSOperationQueue.currentQueue;
    const char *queueLabel = dispatch_queue_get_label(
        DISPATCH_CURRENT_QUEUE_LABEL);
    fprintf(stderr,
        "LC32 block[%llu]: %s guest=0x%08x invoke=0x%08x "
        "signature=%s registered=%d thread=%p main=%d "
        "dispatch=%s operationQueue=%p operationMain=%d",
        (unsigned long long)sequence, event, context.block,
        context.literal.invoke, context.encoding,
        Dynarmic_guest_thread_is_registered(), (void *)pthread_self(),
        pthread_main_np(), queueLabel ?: "", operationQueue,
        operationQueue != nil &&
            operationQueue == NSOperationQueue.mainQueue);
    if(hostArguments) {
        fputs(" args=", stderr);
        for(size_t index = 0;
                index < context.signature.hostArgumentSlots; index++) {
            fprintf(stderr, "%s0x%016llx", index ? "," : "",
                    (unsigned long long)hostArguments[index]);
        }
    }
    if(!strcmp(event, "return")) {
        fprintf(stderr, " result=0x%016llx", (unsigned long long)result);
    }
    fputc('\n', stderr);
    fflush(stderr);
}

static bool ReadCString(u32 address, char *output, size_t capacity) {
    if(!address || !output || capacity < 2) return false;
    for(size_t index = 0; index + 1 < capacity; index++) {
        if(Dynarmic_mem_1read(address + (u32)index, 1,
                output + index) != 0) {
            output[0] = '\0';
            return false;
        }
        if(output[index] == '\0') return true;
    }
    output[capacity - 1] = '\0';
    return false;
}

static void SkipQualifiers(const char *&cursor) {
    while(*cursor && strchr("rnNoORVA", *cursor)) cursor++;
}

static void SkipOffset(const char *&cursor) {
    while(*cursor >= '0' && *cursor <= '9') cursor++;
}

static bool ConsumeObjectType(const char *&cursor, bool requireBlock) {
    SkipQualifiers(cursor);
    if(*cursor++ != '@') return false;
    if(requireBlock) {
        if(*cursor++ != '?') return false;
    } else {
        if(*cursor == '?') cursor++;
        if(*cursor == '"') {
            cursor++;
            while(*cursor && *cursor != '"') {
                if(*cursor == '\\' && cursor[1]) cursor++;
                cursor++;
            }
            if(*cursor++ != '"') return false;
        }
    }
    return true;
}

static bool ConsumeRangeType(const char *&cursor) {
    static constexpr const char *Encodings[] = {
        "{_NSRange=II}",
        "{NSRange=II}",
        "{_CFRange=ll}",
        "{CFRange=ll}",
    };
    for(const char *encoding : Encodings) {
        const size_t length = strlen(encoding);
        if(strncmp(cursor, encoding, length) == 0) {
            cursor += length;
            return true;
        }
    }
    return false;
}

static bool ConsumeValueType(const char *&cursor, bool allowVoid,
                             BlockValueKind &kind) {
    SkipQualifiers(cursor);
    switch(*cursor) {
        case 'v':
            if(!allowVoid) return false;
            kind = BlockValueKind::Void;
            cursor++;
            return true;
        case '@':
        case '#':
            if(*cursor == '#') {
                cursor++;
            } else if(!ConsumeObjectType(cursor, false)) {
                return false;
            }
            kind = BlockValueKind::Object;
            return true;
        case 'B':
        case 'c':
            kind = BlockValueKind::SignedChar;
            cursor++;
            return true;
        case 'i':
        case 'l':
        case 's':
            kind = BlockValueKind::Signed32;
            cursor++;
            return true;
        case 'C':
        case 'I':
        case 'L':
        case 'S':
            kind = BlockValueKind::Unsigned32;
            cursor++;
            return true;
        case 'q':
            kind = BlockValueKind::Signed64;
            cursor++;
            return true;
        case 'Q':
            kind = BlockValueKind::Unsigned64;
            cursor++;
            return true;
        case '*':
            kind = BlockValueKind::CharPointer;
            cursor++;
            return true;
        case '^': {
            cursor++;
            SkipQualifiers(cursor);
            if(*cursor != 'B' && *cursor != 'c' && *cursor != 'C') {
                return false;
            }
            cursor++;
            kind = BlockValueKind::CharPointer;
            return true;
        }
        case '{':
            if(!ConsumeRangeType(cursor)) return false;
            kind = BlockValueKind::Range;
            return true;
        default:
            return false;
    }
}

static bool ParseBlockSignature(const char *encoding,
                                BlockSignature &signature) {
    const char *cursor = encoding;
    if(!ConsumeValueType(cursor, true, signature.result)) return false;
    if(signature.result == BlockValueKind::Range ||
       signature.result == BlockValueKind::CharPointer) {
        return false;
    }
    SkipOffset(cursor);
    if(!ConsumeObjectType(cursor, true)) return false;
    SkipOffset(cursor);

    while(*cursor) {
        if(signature.argumentCount == MaxLogicalArguments) return false;
        BlockValueKind kind;
        if(!ConsumeValueType(cursor, false, kind)) return false;
        signature.arguments[signature.argumentCount++] = kind;
        signature.hostArgumentSlots +=
            kind == BlockValueKind::Range ? 2 : 1;
        if(signature.hostArgumentSlots > MaxHostArgumentSlots) return false;
        SkipOffset(cursor);
    }
    return true;
}

class GuestCharPointerStorage {
public:
    GuestCharPointerStorage() {
        originalStackPointer = threadHandle.jit->Regs()[Reg::SP];
    }

    ~GuestCharPointerStorage() {
        for(size_t index = 0; index < count; index++) {
            char value = 0;
            if(Dynarmic_mem_1read(entries[index].guestPointer,
                    sizeof(value), &value) == 0) {
                *entries[index].hostPointer = value;
            }
        }
        threadHandle.jit->Regs()[Reg::SP] = originalStackPointer;
    }

    bool Add(char *hostPointer, u32 &guestPointer) {
        if(!hostPointer) {
            guestPointer = 0;
            return true;
        }
        if(count == entries.size()) return false;

        u32 &stackPointer = threadHandle.jit->Regs()[Reg::SP];
        stackPointer -= sizeof(u64);
        const char value = *hostPointer;
        if(Dynarmic_mem_1write(stackPointer, sizeof(value),
                const_cast<char *>(&value)) != 0) {
            return false;
        }
        entries[count++] = {hostPointer, stackPointer};
        guestPointer = stackPointer;
        return true;
    }

private:
    struct Entry {
        char *hostPointer = nullptr;
        u32 guestPointer = 0;
    };

    u32 originalStackPointer = 0;
    std::array<Entry, MaxLogicalArguments> entries = {};
    size_t count = 0;
};

static id HostObjectForGuestResult(u32 guestObject) {
    if(!guestObject) return nil;
    const u32 selector = guest_sel_registerName("host_self");
    if(!selector) return nil;
    u32 arguments[] = {guestObject, selector};
    return reinterpret_cast<id>(static_cast<uintptr_t>(
        guest_objc_msgSend(2, arguments)));
}

static u64 NormalizeGuestResult(BlockValueKind kind, u64 result) {
    switch(kind) {
        case BlockValueKind::Void:
            return 0;
        case BlockValueKind::Object:
            return reinterpret_cast<u64>(objc_autorelease(objc_retain(
                HostObjectForGuestResult(static_cast<u32>(result)))));
        case BlockValueKind::SignedChar:
            return static_cast<u64>(static_cast<int64_t>(
                static_cast<int8_t>(result)));
        case BlockValueKind::Signed32:
            return static_cast<u64>(static_cast<int64_t>(
                static_cast<int32_t>(result)));
        case BlockValueKind::Unsigned32:
            return static_cast<u32>(result);
        case BlockValueKind::Signed64:
        case BlockValueKind::Unsigned64:
            return result;
        case BlockValueKind::Range:
        case BlockValueKind::CharPointer:
            return 0;
    }
}

static bool NarrowRangeElement(u64 value, bool location, u32 &result) {
    if(location && value == UINT64_MAX) {
        result = UINT32_MAX;
        return true;
    }
    if(value > UINT32_MAX) return false;
    result = static_cast<u32>(value);
    return true;
}

struct TypedCallbackCompletion {
    LC32GuestBlockCallbackDescriptor expected = {};
    LC32GuestBlockCallbackDescriptor completed = {};
    bool received = false;
    bool retainedObjectResult = false;
};

static std::mutex TypedCallbackCompletionMutex;
static std::unordered_map<u64, TypedCallbackCompletion *>
    TypedCallbackCompletions;
static std::atomic<u64> NextTypedCallbackToken{1};

class TypedCallbackRegistration {
public:
    explicit TypedCallbackRegistration(TypedCallbackCompletion &completion)
        : completion(completion) {
        do {
            token = NextTypedCallbackToken.fetch_add(
                1, std::memory_order_relaxed);
        } while(token == 0);
        std::lock_guard<std::mutex> lock(TypedCallbackCompletionMutex);
        TypedCallbackCompletions[token] = &completion;
    }

    ~TypedCallbackRegistration() {
        id retainedResult = nil;
        {
            std::lock_guard<std::mutex> lock(TypedCallbackCompletionMutex);
            TypedCallbackCompletions.erase(token);
            if(completion.retainedObjectResult) {
                retainedResult = reinterpret_cast<id>(
                    static_cast<uintptr_t>(completion.completed.result));
                completion.retainedObjectResult = false;
            }
        }
        objc_release(retainedResult);
    }

    u64 Token() const { return token; }

    bool CopyCompleted(LC32GuestBlockCallbackDescriptor &descriptor) {
        std::lock_guard<std::mutex> lock(TypedCallbackCompletionMutex);
        if(!completion.received) return false;
        descriptor = completion.completed;
        return true;
    }

    id TakeObjectResult() {
        std::lock_guard<std::mutex> lock(TypedCallbackCompletionMutex);
        if(!completion.retainedObjectResult) return nil;
        completion.retainedObjectResult = false;
        return reinterpret_cast<id>(static_cast<uintptr_t>(
            completion.completed.result));
    }

private:
    TypedCallbackCompletion &completion;
    u64 token = 0;
};

static bool SameCallbackShape(
        const LC32GuestBlockCallbackDescriptor &expected,
        const LC32GuestBlockCallbackDescriptor &completed) {
    if(completed.kind != LC32GuestBlockCallbackKindInvoke ||
       completed.identifier != expected.identifier ||
       completed.guestBlock != expected.guestBlock ||
       completed.guestInvoke != expected.guestInvoke ||
       completed.argumentCount != expected.argumentCount ||
       completed.resultKind != expected.resultKind ||
       completed.completionToken != expected.completionToken) {
        return false;
    }
    for(size_t index = 0; index < expected.argumentCount; index++) {
        const LC32GuestBlockCallbackArgument &input =
            expected.arguments[index];
        const LC32GuestBlockCallbackArgument &output =
            completed.arguments[index];
        if(output.kind != input.kind || output.reserved != 0) return false;
        if(input.kind != LC32GuestBlockValueCharPointer &&
           (output.value != input.value || output.value2 != input.value2)) {
            return false;
        }
        if(input.kind == LC32GuestBlockValueCharPointer &&
           output.value2 != input.value2) return false;
    }
    return true;
}

static u32 CompleteTypedGuestBlock(u32 guestDescriptor) {
    LC32GuestBlockCallbackDescriptor completed = {};
    if(!guestDescriptor || Dynarmic_mem_1read(
            guestDescriptor, sizeof(completed),
            reinterpret_cast<char *>(&completed)) != 0 ||
       !completed.completionToken) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(TypedCallbackCompletionMutex);
    auto iterator = TypedCallbackCompletions.find(
        completed.completionToken);
    if(iterator == TypedCallbackCompletions.end()) return 0;

    TypedCallbackCompletion &completion = *iterator->second;
    LC32GuestBlockCallbackDescriptor expected = completion.expected;
    expected.identifier = completed.identifier;
    if(!SameCallbackShape(expected, completed)) {
        fprintf(stderr,
            "LC32: rejecting malformed typed callback completion 0x%llx\n",
            completed.completionToken);
        return 0;
    }

    if(completed.resultKind == LC32GuestBlockValueObject &&
       completed.result) {
        objc_retain(reinterpret_cast<id>(static_cast<uintptr_t>(
            completed.result)));
        completion.retainedObjectResult = true;
    }
    completion.completed = completed;
    completion.received = true;
    return 1;
}

static u64 InvokeGuestBlockDirect(const GuestBlockContext &context,
                                  const u64 *hostArguments) {
    std::array<u32, MaxGuestArgumentWords> guestArguments = {};
    size_t guestWordCount = 1;
    size_t hostSlot = 0;
    guestArguments[0] = context.block;
    GuestCharPointerStorage pointerStorage;

    for(size_t index = 0; index < context.signature.argumentCount; index++) {
        const BlockValueKind kind = context.signature.arguments[index];
        if(kind == BlockValueKind::Signed64 ||
           kind == BlockValueKind::Unsigned64) {
            if(guestWordCount + 2 > guestArguments.size()) return 0;
            const u64 value = hostArguments[hostSlot++];
            guestArguments[guestWordCount++] = static_cast<u32>(value);
            guestArguments[guestWordCount++] = static_cast<u32>(value >> 32);
            continue;
        }
        if(kind == BlockValueKind::Range) {
            if(guestWordCount + 2 > guestArguments.size()) return 0;
            u32 location = 0;
            u32 length = 0;
            if(!NarrowRangeElement(hostArguments[hostSlot++], true,
                    location) ||
               !NarrowRangeElement(hostArguments[hostSlot++], false,
                    length)) {
                fprintf(stderr,
                    "LC32: NSRange argument of guest block 0x%x does not "
                    "fit ARM32\n", context.block);
                return 0;
            }
            guestArguments[guestWordCount++] = location;
            guestArguments[guestWordCount++] = length;
            continue;
        }
        if(guestWordCount == guestArguments.size()) return 0;

        u32 value = 0;
        switch(kind) {
            case BlockValueKind::Object: {
                id object = reinterpret_cast<id>(static_cast<uintptr_t>(
                    hostArguments[hostSlot++]));
                value = object ? [object guest_self] : 0;
                break;
            }
            case BlockValueKind::SignedChar:
            case BlockValueKind::Signed32:
            case BlockValueKind::Unsigned32:
                value = static_cast<u32>(hostArguments[hostSlot++]);
                break;
            case BlockValueKind::CharPointer: {
                char *hostPointer = reinterpret_cast<char *>(
                    static_cast<uintptr_t>(hostArguments[hostSlot++]));
                if(!pointerStorage.Add(hostPointer, value)) return 0;
                break;
            }
            default:
                return 0;
        }
        guestArguments[guestWordCount++] = value;
    }

    const bool returns64 =
        context.signature.result == BlockValueKind::Signed64 ||
        context.signature.result == BlockValueKind::Unsigned64;
    const u64 result = LC32InvokeGuestC(
        context.literal.invoke, returns64,
        static_cast<int>(guestWordCount), guestArguments.data());
    return NormalizeGuestResult(context.signature.result, result);
}

static u64 InvokeGuestBlock(const GuestBlockContext &context,
                            const u64 *hostArguments) {
    TraceGuestBlockInvocation("invoke", context, hostArguments);
    if(Dynarmic_guest_thread_is_registered()) {
        const u64 result = InvokeGuestBlockDirect(context, hostArguments);
        TraceGuestBlockInvocation("return", context, nullptr, result);
        return result;
    }

    LC32GuestBlockCallbackDescriptor descriptor = {};
    descriptor.kind = LC32GuestBlockCallbackKindInvoke;
    descriptor.guestBlock = context.block;
    descriptor.guestInvoke = context.literal.invoke;
    descriptor.argumentCount =
        static_cast<uint32_t>(context.signature.argumentCount);
    descriptor.resultKind = static_cast<uint32_t>(context.signature.result);

    size_t hostSlot = 0;
    for(size_t index = 0; index < context.signature.argumentCount; index++) {
        const BlockValueKind kind = context.signature.arguments[index];
        LC32GuestBlockCallbackArgument &argument =
            descriptor.arguments[index];
        argument.kind = static_cast<uint32_t>(kind);
        if(kind == BlockValueKind::Range) {
            u32 location = 0;
            u32 length = 0;
            if(!NarrowRangeElement(hostArguments[hostSlot++], true,
                    location) ||
               !NarrowRangeElement(hostArguments[hostSlot++], false,
                    length)) {
                fprintf(stderr,
                    "LC32: NSRange argument of guest block 0x%x does not "
                    "fit ARM32\n", context.block);
                return 0;
            }
            argument.value = location;
            argument.value2 = length;
            continue;
        }

        const u64 value = hostArguments[hostSlot++];
        if(kind == BlockValueKind::Object) {
            argument.value = value;
        } else if(kind == BlockValueKind::CharPointer) {
            char *pointer = reinterpret_cast<char *>(
                static_cast<uintptr_t>(value));
            argument.value = pointer ? static_cast<uint8_t>(*pointer) : 0;
            argument.value2 = pointer != nullptr;
        } else {
            argument.value = value;
        }
    }

    for(size_t index = 0; index < context.signature.argumentCount; index++) {
        LC32GuestBlockCallbackArgument &argument =
            descriptor.arguments[index];
        if(argument.kind == LC32GuestBlockValueObject) {
            argument.value = reinterpret_cast<uintptr_t>(objc_retain(
                reinterpret_cast<id>(static_cast<uintptr_t>(
                    argument.value))));
        }
    }

    TypedCallbackCompletion completion;
    TypedCallbackRegistration registration(completion);
    descriptor.completionToken = registration.Token();
    completion.expected = descriptor;
    const bool invoked =
        Dynarmic_submit_guest_block_callback(&descriptor);
    for(size_t index = 0; index < context.signature.argumentCount; index++) {
        if(descriptor.arguments[index].kind ==
                LC32GuestBlockValueObject) {
            objc_release(reinterpret_cast<id>(static_cast<uintptr_t>(
                descriptor.arguments[index].value)));
        }
    }
    if(!invoked) {
        fprintf(stderr,
            "LC32: guest block 0x%x rejected on an unregistered "
            "host thread\n", context.block);
        return 0;
    }

    LC32GuestBlockCallbackDescriptor completed = {};
    if(!registration.CopyCompleted(completed)) {
        fprintf(stderr,
            "LC32: guest block 0x%x completed without typed result data\n",
            context.block);
        return 0;
    }

    hostSlot = 0;
    for(size_t index = 0; index < context.signature.argumentCount; index++) {
        const BlockValueKind kind = context.signature.arguments[index];
        if(kind == BlockValueKind::Range) {
            hostSlot += 2;
        } else {
            if(kind == BlockValueKind::CharPointer && hostArguments[hostSlot]) {
                *reinterpret_cast<char *>(static_cast<uintptr_t>(
                    hostArguments[hostSlot])) = static_cast<char>(
                        completed.arguments[index].value);
            }
            hostSlot++;
        }
    }

    if(context.signature.result == BlockValueKind::Object) {
        const u64 result = reinterpret_cast<u64>(objc_autorelease(
            registration.TakeObjectResult()));
        TraceGuestBlockInvocation("return", context, nullptr, result);
        return result;
    }
    const u64 result = NormalizeGuestResult(
        context.signature.result, completed.result);
    TraceGuestBlockInvocation("return", context, nullptr, result);
    return result;
}

static id CreateRawHostBlock(
        std::shared_ptr<GuestBlockContext> context) {
    id nativeBlock = nil;
    switch(context->signature.hostArgumentSlots) {
        case 0: {
            nativeBlock = [^u64 {
                return InvokeGuestBlock(*context, nullptr);
            } copy];
            break;
        }
        case 1: {
            nativeBlock = [^u64(u64 argument0) {
                const u64 arguments[] = {argument0};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 2: {
            nativeBlock = [^u64(u64 argument0, u64 argument1) {
                const u64 arguments[] = {argument0, argument1};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 3: {
            nativeBlock = [^u64(u64 argument0, u64 argument1,
                                u64 argument2) {
                const u64 arguments[] = {
                    argument0, argument1, argument2};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 4: {
            nativeBlock = [^u64(u64 argument0, u64 argument1,
                                u64 argument2, u64 argument3) {
                const u64 arguments[] = {
                    argument0, argument1, argument2, argument3};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 5: {
            nativeBlock = [^u64(u64 argument0, u64 argument1,
                                u64 argument2, u64 argument3,
                                u64 argument4) {
                const u64 arguments[] = {argument0, argument1, argument2,
                    argument3, argument4};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 6: {
            nativeBlock = [^u64(u64 argument0, u64 argument1,
                                u64 argument2, u64 argument3,
                                u64 argument4, u64 argument5) {
                const u64 arguments[] = {argument0, argument1, argument2,
                    argument3, argument4, argument5};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 7: {
            nativeBlock = [^u64(u64 argument0, u64 argument1,
                                u64 argument2, u64 argument3,
                                u64 argument4, u64 argument5,
                                u64 argument6) {
                const u64 arguments[] = {argument0, argument1, argument2,
                    argument3, argument4, argument5, argument6};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
        case 8: {
            nativeBlock = [^u64(u64 argument0, u64 argument1,
                                u64 argument2, u64 argument3,
                                u64 argument4, u64 argument5,
                                u64 argument6, u64 argument7) {
                const u64 arguments[] = {argument0, argument1, argument2,
                    argument3, argument4, argument5, argument6, argument7};
                return InvokeGuestBlock(*context, arguments);
            } copy];
            break;
        }
    }
    return nativeBlock;
}

} // namespace

extern "C" u32 LC32CompleteTypedGuestBlock(
        u32 guestDescriptor, u32, u32) {
    return CompleteTypedGuestBlock(guestDescriptor);
}

extern "C" u64 LC32CreateHostBlock(u32 guestBlock) {
    const u32 copiedGuestBlock = LC32CopyGuestBlock(guestBlock);
    if(!copiedGuestBlock) return 0;

    GuestBlockLiteral32 literal = {};
    if(Dynarmic_mem_1read(copiedGuestBlock, sizeof(literal),
            reinterpret_cast<char *>(&literal)) != 0 ||
       !literal.invoke || !literal.descriptor ||
       !(literal.flags & BlockHasSignature)) {
        fprintf(stderr,
            "LC32: cannot bridge guest block 0x%x without a readable "
            "invoke pointer and signature\n", copiedGuestBlock);
        LC32ReleaseGuestBlock(copiedGuestBlock);
        return 0;
    }

    u32 signatureAddress = 0;
    const u32 signatureOffset = 8 +
        ((literal.flags & BlockHasCopyDispose) ? 8 : 0);
    char encoding[128] = {};
    if(Dynarmic_mem_1read(literal.descriptor + signatureOffset,
            sizeof(signatureAddress),
            reinterpret_cast<char *>(&signatureAddress)) != 0 ||
       !ReadCString(signatureAddress, encoding, sizeof(encoding))) {
        fprintf(stderr,
            "LC32: cannot read signature for guest block 0x%x\n",
            copiedGuestBlock);
        LC32ReleaseGuestBlock(copiedGuestBlock);
        return 0;
    }

    BlockSignature signature;
    if(!ParseBlockSignature(encoding, signature)) {
        fprintf(stderr,
            "LC32: unsupported guest block signature %s at 0x%x\n",
            encoding, copiedGuestBlock);
        LC32ReleaseGuestBlock(copiedGuestBlock);
        return 0;
    }

    TraceGuestBlockCreation(
        guestBlock, copiedGuestBlock, literal, encoding);

    std::shared_ptr<GuestBlockContext> context =
        std::make_shared<GuestBlockContext>(
            copiedGuestBlock, literal, signature, encoding);
    id nativeBlock = CreateRawHostBlock(context);
    if(!nativeBlock) return 0;

    [nativeBlock setGuest_self:copiedGuestBlock];
#if __has_feature(objc_arc)
    void *retainedBlock = (__bridge_retained void *)nativeBlock;
    return (u64)objc_autorelease((__bridge id)retainedBlock);
#else
    return (u64)[nativeBlock autorelease];
#endif
}

/* Focused integration hook used by test/block_bridge.m. The guest supplies a
 * real ARM32 block; invoking its native wrapper on a global queue exercises
 * the same unregistered-host-thread path used by Foundation completion APIs. */
extern "C" u32 LC32TestInvokeTypedGuestBlockOnWorker(
        u32 guestBlock, u32 testKind, u32) {
    id nativeBlock = reinterpret_cast<id>(static_cast<uintptr_t>(
        LC32CreateHostBlock(guestBlock)));
    if(!nativeBlock) return 0;
    objc_retain(nativeBlock);

    __block bool passed = false;
    dispatch_sync(dispatch_get_global_queue(
            DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            switch(testKind) {
                case 1: {
                    using Callback = int32_t (^)(id, uint64_t, BOOL *);
                    BOOL stop = NO;
                    const int32_t result = ((Callback)nativeBlock)(
                        @"worker", UINT64_C(0x1122334455667788), &stop);
                    passed = result == -37 && stop;
                    break;
                }
                case 2: {
                    using Callback = id (^)(id, id, id, id, int64_t);
                    id first = @"first";
                    id result = ((Callback)nativeBlock)(first, @"second",
                        @"third", @"fourth",
                        -INT64_C(0x102030405060708));
                    passed = result == first;
                    if(!passed) {
                        fprintf(stderr,
                            "LC32 block test: five-argument result=%p "
                            "expected=%p\n", result, first);
                    }
                    break;
                }
                case 3: {
                    using Callback = uint64_t (^)(int64_t, uint64_t);
                    const uint64_t result = ((Callback)nativeBlock)(
                        -INT64_C(0x102030405060708),
                        UINT64_C(0xfedcba9876543210));
                    passed = result == UINT64_C(0x8877665544332211);
                    if(!passed) {
                        fprintf(stderr,
                            "LC32 block test: unsigned-64 result=0x%llx\n",
                            result);
                    }
                    break;
                }
                case 4: {
                    using Callback = int64_t (^)(int32_t);
                    const int64_t result = ((Callback)nativeBlock)(-19);
                    passed = result == -INT64_C(0x11223344556677);
                    break;
                }
            }
        }
    });
    objc_release(nativeBlock);
    return passed;
}
