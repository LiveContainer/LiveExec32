@import AudioToolbox;
@import Foundation;

#include "bridge.h"
#include "../../GuestFrameworks/AudioToolbox/LC32AudioToolboxBridge.h"

#include <objc/message.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <new>
#include <unordered_map>
#include <vector>

namespace {

constexpr size_t kMaximumPropertyBytes = 16u * 1024u * 1024u;
constexpr size_t kMaximumAudioBytes = 256u * 1024u * 1024u;
constexpr u32 kMaximumAudioBuffers = 64;
constexpr u32 kRemoteIOOutputBufferCount = 3;
constexpr u32 kRemoteIOOutputPrimeBufferCount = 2;
constexpr u32 kRemoteIOOutputMaximumFrames = 4096;
constexpr u32 kRemoteIOOutputMaximumChannels = 32;
constexpr size_t kRemoteIOOutputMaximumBufferBytes =
    16u * 1024u * 1024u;

class AudioToolboxGuestHostCallQuiescence {
public:
    AudioToolboxGuestHostCallQuiescence()
        : active_(Dynarmic_guest_host_call_quiescence_begin()) {}

    ~AudioToolboxGuestHostCallQuiescence() {
        if(active_) Dynarmic_guest_host_call_quiescence_end();
    }

    AudioToolboxGuestHostCallQuiescence(
        const AudioToolboxGuestHostCallQuiescence &) = delete;
    AudioToolboxGuestHostCallQuiescence &operator=(
        const AudioToolboxGuestHostCallQuiescence &) = delete;

private:
    bool active_;
};

struct ExtAudioFileEntry {
    ExtAudioFileRef file = nullptr;
    std::mutex mutex;
};

struct AudioFileCallbackContext {
    u32 guestClientData = 0;
    u32 guestReadFunction = 0;
    u32 guestWriteFunction = 0;
    u32 guestGetSizeFunction = 0;
    u32 guestSetSizeFunction = 0;
};

struct AudioFileEntry {
    AudioFileID file = nullptr;
    std::unique_ptr<AudioFileCallbackContext> callbackContext;
    std::mutex mutex;
};

struct GuestAudioBuffer {
    u32 channels;
    u32 byteSize;
    u32 data;
};

struct GuestAudioStreamPacketDescription {
    int64_t startOffset;
    u32 variableFramesInPacket;
    u32 dataByteSize;
};

struct GuestAudioQueueBuffer {
    u32 audioDataBytesCapacity;
    u32 audioData;
    u32 audioDataByteSize;
    u32 userData;
    u32 packetDescriptionCapacity;
    u32 packetDescriptions;
    u32 packetDescriptionCount;
};

struct GuestAudioQueueInputCallbackStorage {
    AudioTimeStamp timeStamp;
    u32 packetCount;
    u32 packetDescriptions;
};

struct AudioQueueBufferEntry {
    AudioQueueBufferRef nativeBuffer = nullptr;
    u32 guestBuffer = 0;
    u32 guestAudioData = 0;
    u32 audioDataCapacity = 0;
    u32 guestPacketDescriptions = 0;
    u32 packetDescriptionCapacity = 0;
    u32 guestCallbackStorage = 0;
    std::mutex stateMutex;
    bool outputEnqueued = false;
};

enum class AudioQueueDirection : uint8_t {
    Input,
    Output,
};

struct AudioQueueEntry;

struct AudioQueuePropertyListenerEntry {
    std::weak_ptr<AudioQueueEntry> queueEntry;
    uintptr_t nativeCookie = 0;
    AudioQueuePropertyID property = 0;
    u32 guestCallback = 0;
    u32 guestCallbackThunk = 0;
    u32 guestUserData = 0;
    std::atomic<bool> enabled{true};
    std::atomic<bool> removing{false};
};

struct AudioQueueEntry {
    AudioQueueRef queue = nullptr;
    u32 token = 0;
    AudioQueueDirection direction = AudioQueueDirection::Input;
    u32 guestCallback = 0;
    u32 guestCallbackThunk = 0;
    u32 guestUserData = 0;
    std::atomic<bool> disposed{false};
    std::mutex stateMutex;
    std::condition_variable stateCondition;
    u32 activeUsers = 0;
    u32 activeCallbacks = 0;
    bool disposing = false;
    std::mutex buffersMutex;
    std::unordered_map<u32, std::shared_ptr<AudioQueueBufferEntry>>
        buffersByGuest;
    std::unordered_map<AudioQueueBufferRef,
        std::shared_ptr<AudioQueueBufferEntry>> buffersByNative;
    std::mutex listenersMutex;
    std::vector<std::shared_ptr<AudioQueuePropertyListenerEntry>> listeners;
    std::mutex timelinesMutex;
    std::unordered_map<u32, AudioQueueTimelineRef> timelines;
    u32 nextTimelineToken = 1;
};

enum class RemoteIOOutputBufferState : uint8_t {
    Free,
    Filling,
    Enqueued,
};

struct RemoteIOOutputBufferEntry {
    AudioQueueBufferRef buffer = nullptr;
    RemoteIOOutputBufferState state = RemoteIOOutputBufferState::Free;
};

struct RemoteIOOutputEntry {
    AudioQueueRef queue = nullptr;
    u32 token = 0;
    AudioStreamBasicDescription guestFormat = {};
    AudioStreamBasicDescription nativeFormat = {};
    u32 framesPerQuantum = 0;
    u32 guestBytesPerFrame = 0;
    u32 nativeBytesPerFrame = 0;
    u32 nativeBufferBytes = 0;
    u32 submitTimeoutMilliseconds = 100;
    bool nonInterleaved = false;
    RemoteIOOutputBufferEntry buffers[kRemoteIOOutputBufferCount];
    std::mutex mutex;
    std::condition_variable condition;
    u32 activeUsers = 0;
    u32 activeCallbacks = 0;
    bool disposing = false;
};

static_assert(sizeof(GuestAudioBuffer) == 12);
static_assert(offsetof(GuestAudioBuffer, channels) == 0);
static_assert(offsetof(GuestAudioBuffer, byteSize) == 4);
static_assert(offsetof(GuestAudioBuffer, data) == 8);
static_assert(sizeof(AudioStreamBasicDescription) == 40);
static_assert(sizeof(GuestAudioStreamPacketDescription) == 16);
static_assert(sizeof(AudioStreamPacketDescription) == 16);
static_assert(offsetof(GuestAudioStreamPacketDescription, startOffset) == 0);
static_assert(offsetof(GuestAudioStreamPacketDescription,
    variableFramesInPacket) == 8);
static_assert(offsetof(GuestAudioStreamPacketDescription, dataByteSize) == 12);
static_assert(offsetof(AudioStreamPacketDescription, mStartOffset) == 0);
static_assert(offsetof(AudioStreamPacketDescription,
    mVariableFramesInPacket) == 8);
static_assert(offsetof(AudioStreamPacketDescription, mDataByteSize) == 12);
static_assert(sizeof(GuestAudioQueueBuffer) == 28);
static_assert(offsetof(GuestAudioQueueBuffer, audioDataBytesCapacity) == 0);
static_assert(offsetof(GuestAudioQueueBuffer, audioData) == 4);
static_assert(offsetof(GuestAudioQueueBuffer, audioDataByteSize) == 8);
static_assert(offsetof(GuestAudioQueueBuffer, userData) == 12);
static_assert(offsetof(GuestAudioQueueBuffer,
    packetDescriptionCapacity) == 16);
static_assert(offsetof(GuestAudioQueueBuffer, packetDescriptions) == 20);
static_assert(offsetof(GuestAudioQueueBuffer, packetDescriptionCount) == 24);
static_assert(sizeof(AudioTimeStamp) == 64);
static_assert(offsetof(GuestAudioQueueInputCallbackStorage,
    packetCount) == 64);
static_assert(offsetof(GuestAudioQueueInputCallbackStorage,
    packetDescriptions) == 68);
static_assert(sizeof(GuestAudioQueueInputCallbackStorage) == 72);

std::mutex extAudioFilesMutex;
std::unordered_map<u32, std::shared_ptr<ExtAudioFileEntry>> extAudioFiles;
std::atomic<u32> nextExtAudioFileToken{1};

std::mutex audioFilesMutex;
std::unordered_map<u32, std::shared_ptr<AudioFileEntry>> audioFiles;
std::atomic<u32> nextAudioFileToken{1};

std::mutex audioQueuesMutex;
std::unordered_map<u32, std::shared_ptr<AudioQueueEntry>> audioQueues;
std::vector<std::shared_ptr<AudioQueueEntry>> quarantinedAudioQueues;
std::atomic<u32> nextAudioQueueToken{1};
std::mutex audioQueuePropertyListenersMutex;
std::unordered_map<uintptr_t,
    std::shared_ptr<AudioQueuePropertyListenerEntry>>
    audioQueuePropertyListeners;
uintptr_t nextAudioQueuePropertyListenerCookie = 1;
thread_local std::unordered_map<u32, u32>
    audioQueueGuestCallbacksOnCurrentThread;

std::mutex remoteIOOutputsMutex;
std::unordered_map<u32, std::shared_ptr<RemoteIOOutputEntry>>
    remoteIOOutputs;
std::vector<std::shared_ptr<RemoteIOOutputEntry>>
    quarantinedRemoteIOOutputs;
std::atomic<u32> nextRemoteIOOutputToken{1};

bool ReadAudioToolboxCall(u32 guestAddress, LC32AudioToolboxCall &call) {
    struct {
        u32 version;
        u32 slotCount;
    } header = {};
    if(!guestAddress ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
           reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32AudioToolboxABIVersion ||
       header.slotCount > LC32AudioToolboxMaxSlots) {
        return false;
    }
    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    const uint64_t slotsAddress = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32AudioToolboxCall, slots);
    if(slotsAddress > UINT32_MAX ||
       slotsAddress + byteCount > static_cast<uint64_t>(UINT32_MAX) + 1)
        return false;
    return !byteCount || Dynarmic_mem_1read(
        static_cast<u32>(slotsAddress), byteCount,
        reinterpret_cast<char *>(call.slots)) == 0;
}

bool RequireSlots(const LC32AudioToolboxCall &call, u32 count) {
    return call.slotCount == count;
}

u32 SlotU32(const LC32AudioToolboxCall &call, size_t index) {
    return static_cast<u32>(call.slots[index]);
}

template<typename T>
T SlotHostObject(const LC32AudioToolboxCall &call, size_t index) {
    return reinterpret_cast<T>(
        static_cast<uintptr_t>(call.slots[index]));
}

bool ReadGuestU32(u32 address, u32 &value) {
    return address && address <= UINT32_MAX - sizeof(value) + 1 &&
        Dynarmic_mem_1read(address, sizeof(value),
        reinterpret_cast<char *>(&value)) == 0;
}

bool WriteGuestU32(u32 address, u32 value) {
    return address && address <= UINT32_MAX - sizeof(value) + 1 &&
        Dynarmic_mem_1write(address, sizeof(value),
        reinterpret_cast<char *>(&value)) == 0;
}

bool ReadGuestBytes(u32 address, size_t byteCount, void *bytes) {
    if(!byteCount) return true;
    return address && bytes &&
        static_cast<uint64_t>(address) + byteCount <=
            static_cast<uint64_t>(UINT32_MAX) + 1 &&
        Dynarmic_mem_1read(address, byteCount,
            reinterpret_cast<char *>(bytes)) == 0;
}

bool WriteGuestBytes(u32 address, size_t byteCount, const void *bytes) {
    if(!byteCount) return true;
    return address && bytes &&
        static_cast<uint64_t>(address) + byteCount <=
            static_cast<uint64_t>(UINT32_MAX) + 1 &&
        Dynarmic_mem_1write(address, byteCount,
            const_cast<char *>(reinterpret_cast<const char *>(bytes))) == 0;
}

u32 AllocateGuestAudioFileCallbackBytes(u32 byteCount) {
    if(!byteCount || !Dynarmic_guest_thread_is_registered()) return 0;
    static std::atomic<u32> guestMallocFunction{0};
    u32 function = guestMallocFunction.load(std::memory_order_acquire);
    if(!function) {
        const u32 resolved = guest_dlsym("malloc");
        if(!resolved) return 0;
        if(guestMallocFunction.compare_exchange_strong(function, resolved,
                std::memory_order_release, std::memory_order_acquire)) {
            function = resolved;
        }
    }
    u32 arguments[] = {byteCount};
    return static_cast<u32>(LC32InvokeGuestC(
        function, false, 1, arguments));
}

class GuestAudioFileCallbackStorage {
public:
    explicit GuestAudioFileCallbackStorage(u32 payloadBytes) {
        const uint64_t alignedPayload =
            (static_cast<uint64_t>(payloadBytes) + 7u) & ~uint64_t{7};
        const uint64_t totalBytes = alignedPayload + sizeof(uint64_t);
        if(totalBytes > UINT32_MAX) return;

        allocation_ = AllocateGuestAudioFileCallbackBytes(
            static_cast<u32>(totalBytes));
        if(!allocation_ ||
           static_cast<uint64_t>(allocation_) + totalBytes >
               static_cast<uint64_t>(UINT32_MAX) + 1) {
            if(allocation_) guest_free(allocation_);
            allocation_ = 0;
            return;
        }
        payload_ = allocation_;
        actualCount_ = static_cast<u32>(
            static_cast<uint64_t>(allocation_) + alignedPayload);
        if(!WriteGuestU32(actualCount_, 0)) {
            guest_free(allocation_);
            allocation_ = 0;
            payload_ = 0;
            actualCount_ = 0;
        }
    }

    ~GuestAudioFileCallbackStorage() {
        if(allocation_ && Dynarmic_guest_thread_is_registered())
            guest_free(allocation_);
    }

    explicit operator bool() const { return allocation_ != 0; }
    u32 payload() const { return payload_; }
    u32 actualCount() const { return actualCount_; }

private:
    u32 allocation_ = 0;
    u32 payload_ = 0;
    u32 actualCount_ = 0;
};

OSStatus AudioFileReadCallbackBridge(
        void *rawContext, SInt64 position, UInt32 requestCount,
        void *buffer, UInt32 *actualCount) {
    if(actualCount) *actualCount = 0;
    AudioFileCallbackContext *context =
        static_cast<AudioFileCallbackContext *>(rawContext);
    if(!context || !context->guestReadFunction || !actualCount ||
       (requestCount && !buffer) || requestCount > kMaximumAudioBytes ||
       !Dynarmic_guest_thread_is_registered()) {
        return kAudio_ParamError;
    }

    GuestAudioFileCallbackStorage storage(requestCount);
    if(!storage) return kAudio_MemFullError;
    const uint64_t positionBits = static_cast<uint64_t>(position);
    /* Darwin's ARM32 ABI packs the SInt64 second argument into r1:r2.
     * requestCount then occupies r3 and the pointer arguments start on the
     * stack. This differs from the 8-byte core-register alignment used by
     * generic AAPCS32 implementations. */
    u32 arguments[] = {
        context->guestClientData,
        static_cast<u32>(positionBits),
        static_cast<u32>(positionBits >> 32),
        requestCount,
        storage.payload(),
        storage.actualCount(),
    };
    const OSStatus status = static_cast<OSStatus>(LC32InvokeGuestC(
        context->guestReadFunction, false,
        sizeof(arguments) / sizeof(arguments[0]), arguments));

    u32 returnedBytes = 0;
    if(!ReadGuestU32(storage.actualCount(), returnedBytes) ||
       returnedBytes > requestCount ||
       (returnedBytes &&
        !ReadGuestBytes(storage.payload(), returnedBytes, buffer))) {
        return kAudio_ParamError;
    }
    *actualCount = returnedBytes;
    return status;
}

OSStatus AudioFileWriteCallbackBridge(
        void *rawContext, SInt64 position, UInt32 requestCount,
        const void *buffer, UInt32 *actualCount) {
    if(actualCount) *actualCount = 0;
    AudioFileCallbackContext *context =
        static_cast<AudioFileCallbackContext *>(rawContext);
    if(!context || !context->guestWriteFunction || !actualCount ||
       (requestCount && !buffer) || requestCount > kMaximumAudioBytes ||
       !Dynarmic_guest_thread_is_registered()) {
        return kAudio_ParamError;
    }

    GuestAudioFileCallbackStorage storage(requestCount);
    if(!storage || (requestCount &&
            !WriteGuestBytes(storage.payload(), requestCount, buffer))) {
        return kAudio_MemFullError;
    }
    const uint64_t positionBits = static_cast<uint64_t>(position);
    u32 arguments[] = {
        context->guestClientData,
        static_cast<u32>(positionBits),
        static_cast<u32>(positionBits >> 32),
        requestCount,
        storage.payload(),
        storage.actualCount(),
    };
    const OSStatus status = static_cast<OSStatus>(LC32InvokeGuestC(
        context->guestWriteFunction, false,
        sizeof(arguments) / sizeof(arguments[0]), arguments));

    u32 returnedBytes = 0;
    if(!ReadGuestU32(storage.actualCount(), returnedBytes) ||
       returnedBytes > requestCount) {
        return kAudio_ParamError;
    }
    *actualCount = returnedBytes;
    return status;
}

SInt64 AudioFileGetSizeCallbackBridge(void *rawContext) {
    AudioFileCallbackContext *context =
        static_cast<AudioFileCallbackContext *>(rawContext);
    if(!context || !context->guestGetSizeFunction ||
       !Dynarmic_guest_thread_is_registered()) {
        return -1;
    }
    u32 arguments[] = {context->guestClientData};
    return static_cast<SInt64>(LC32InvokeGuestC(
        context->guestGetSizeFunction, true, 1, arguments));
}

OSStatus AudioFileSetSizeCallbackBridge(void *rawContext, SInt64 size) {
    AudioFileCallbackContext *context =
        static_cast<AudioFileCallbackContext *>(rawContext);
    if(!context || !context->guestSetSizeFunction ||
       !Dynarmic_guest_thread_is_registered()) {
        return kAudio_ParamError;
    }
    const uint64_t sizeBits = static_cast<uint64_t>(size);
    u32 arguments[] = {
        context->guestClientData,
        static_cast<u32>(sizeBits),
        static_cast<u32>(sizeBits >> 32),
    };
    return static_cast<OSStatus>(LC32InvokeGuestC(
        context->guestSetSizeFunction, false,
        sizeof(arguments) / sizeof(arguments[0]), arguments));
}

bool InvokeGuestAudioQueueFunction(u32 function, const u32 *arguments,
                                   size_t argumentCount) {
    if(!function || !arguments || argumentCount == 0 ||
       argumentCount > LC32_GUEST_BLOCK_CALLBACK_MAX_ARGUMENTS) {
        return false;
    }
    if(Dynarmic_guest_thread_is_registered()) {
        (void)LC32InvokeGuestC(function, false,
            static_cast<int>(argumentCount),
            const_cast<u32 *>(arguments));
        return true;
    }

    LC32GuestBlockCallbackDescriptor descriptor = {};
    descriptor.kind = LC32GuestBlockCallbackKindFunction;
    descriptor.guestInvoke = function;
    descriptor.argumentCount = static_cast<u32>(argumentCount);
    descriptor.resultKind = LC32GuestBlockValueVoid;
    for(size_t index = 0; index < argumentCount; ++index) {
        descriptor.arguments[index].kind =
            LC32GuestBlockValueUnsigned32;
        descriptor.arguments[index].value = arguments[index];
    }
    return Dynarmic_submit_guest_function_callback(&descriptor);
}

std::shared_ptr<AudioQueueEntry> FindAudioQueue(u32 token) {
    std::lock_guard<std::mutex> lock(audioQueuesMutex);
    const auto iterator = audioQueues.find(token);
    return iterator == audioQueues.end() ? nullptr : iterator->second;
}

std::shared_ptr<AudioQueueEntry> TakeAudioQueue(u32 token) {
    std::lock_guard<std::mutex> lock(audioQueuesMutex);
    const auto iterator = audioQueues.find(token);
    if(iterator == audioQueues.end()) return nullptr;
    auto entry = iterator->second;
    audioQueues.erase(iterator);
    return entry;
}

u32 AllocateAudioQueueToken() {
    for(size_t attempt = 0; attempt < UINT32_MAX; ++attempt) {
        const u32 token = nextAudioQueueToken.fetch_add(
            1, std::memory_order_relaxed);
        if(!token) continue;
        std::lock_guard<std::mutex> lock(audioQueuesMutex);
        if(audioQueues.find(token) == audioQueues.end()) return token;
    }
    return 0;
}

bool PublishAudioQueue(const std::shared_ptr<AudioQueueEntry> &entry) {
    if(!entry || !entry->token || !entry->queue) return false;
    std::lock_guard<std::mutex> lock(audioQueuesMutex);
    return audioQueues.emplace(entry->token, entry).second;
}

void QuarantineAudioQueue(const std::shared_ptr<AudioQueueEntry> &entry) {
    if(!entry) return;
    std::lock_guard<std::mutex> lock(audioQueuesMutex);
    /* A failed native disposal can retain the callback context. Preserve only
     * those exceptional entries for process life; successful, quiescent
     * disposals are released normally. */
    quarantinedAudioQueues.push_back(entry);
}

std::shared_ptr<RemoteIOOutputEntry> FindRemoteIOOutput(u32 token) {
    std::lock_guard<std::mutex> lock(remoteIOOutputsMutex);
    const auto iterator = remoteIOOutputs.find(token);
    return iterator == remoteIOOutputs.end() ? nullptr : iterator->second;
}

std::shared_ptr<RemoteIOOutputEntry> TakeRemoteIOOutput(u32 token) {
    std::lock_guard<std::mutex> lock(remoteIOOutputsMutex);
    const auto iterator = remoteIOOutputs.find(token);
    if(iterator == remoteIOOutputs.end()) return nullptr;
    auto entry = iterator->second;
    remoteIOOutputs.erase(iterator);
    return entry;
}

u32 AllocateRemoteIOOutputToken() {
    for(size_t attempt = 0; attempt < UINT32_MAX; ++attempt) {
        const u32 token = nextRemoteIOOutputToken.fetch_add(
            1, std::memory_order_relaxed);
        if(!token) continue;
        std::lock_guard<std::mutex> lock(remoteIOOutputsMutex);
        if(remoteIOOutputs.find(token) == remoteIOOutputs.end())
            return token;
    }
    return 0;
}

bool PublishRemoteIOOutput(
        const std::shared_ptr<RemoteIOOutputEntry> &entry) {
    if(!entry || !entry->token || !entry->queue) return false;
    std::lock_guard<std::mutex> lock(remoteIOOutputsMutex);
    return remoteIOOutputs.emplace(entry->token, entry).second;
}

void QuarantineRemoteIOOutput(
        const std::shared_ptr<RemoteIOOutputEntry> &entry) {
    if(!entry) return;
    std::lock_guard<std::mutex> lock(remoteIOOutputsMutex);
    quarantinedRemoteIOOutputs.push_back(entry);
}

bool PublishAudioQueuePropertyListener(
        const std::shared_ptr<AudioQueuePropertyListenerEntry> &listener) {
    if(!listener) return false;
    std::lock_guard<std::mutex> lock(audioQueuePropertyListenersMutex);
    /* Never reuse a cookie. A callback delayed past removal can therefore
     * only miss this registry, never resolve to a newer listener (ABA). */
    if(!nextAudioQueuePropertyListenerCookie) return false;
    const uintptr_t cookie = nextAudioQueuePropertyListenerCookie++;
    listener->nativeCookie = cookie;
    if(audioQueuePropertyListeners.emplace(cookie, listener).second)
        return true;
    listener->nativeCookie = 0;
    return false;
}

std::shared_ptr<AudioQueuePropertyListenerEntry>
FindAudioQueuePropertyListener(uintptr_t cookie) {
    if(!cookie) return nullptr;
    std::lock_guard<std::mutex> lock(audioQueuePropertyListenersMutex);
    const auto iterator = audioQueuePropertyListeners.find(cookie);
    return iterator == audioQueuePropertyListeners.end()
        ? nullptr : iterator->second;
}

void UnpublishAudioQueuePropertyListener(
        const std::shared_ptr<AudioQueuePropertyListenerEntry> &listener) {
    if(!listener || !listener->nativeCookie) return;
    std::lock_guard<std::mutex> lock(audioQueuePropertyListenersMutex);
    const auto iterator = audioQueuePropertyListeners.find(
        listener->nativeCookie);
    if(iterator != audioQueuePropertyListeners.end() &&
       iterator->second == listener) {
        audioQueuePropertyListeners.erase(iterator);
    }
}

void ClearAudioQueuePropertyListeners(
        const std::shared_ptr<AudioQueueEntry> &entry) {
    if(!entry) return;
    std::vector<std::shared_ptr<AudioQueuePropertyListenerEntry>> listeners;
    {
        std::lock_guard<std::mutex> lock(entry->listenersMutex);
        listeners.swap(entry->listeners);
    }
    for(const auto &listener : listeners) {
        if(!listener) continue;
        listener->enabled.store(false, std::memory_order_release);
        UnpublishAudioQueuePropertyListener(listener);
    }
}

class AudioQueueUse {
public:
    explicit AudioQueueUse(const std::shared_ptr<AudioQueueEntry> &entry)
        : entry_(entry) {
        Begin();
    }

    ~AudioQueueUse() {
        AudioQueueEntry *entry = entry_.get();
        if(!active_ || !entry) return;
        std::lock_guard<std::mutex> lock(entry->stateMutex);
        if(entry->activeUsers) --entry->activeUsers;
        if(entry->disposing || entry->activeUsers == 0)
            entry->stateCondition.notify_all();
    }

    explicit operator bool() const { return active_; }
    AudioQueueRef queue() const { return queue_; }

private:
    void Begin() {
        AudioQueueEntry *entry = entry_.get();
        if(!entry) return;
        std::lock_guard<std::mutex> lock(entry->stateMutex);
        if(entry->disposed.load(std::memory_order_relaxed) ||
           entry->disposing || !entry->queue) return;
        ++entry->activeUsers;
        queue_ = entry->queue;
        active_ = true;
    }

    std::shared_ptr<AudioQueueEntry> entry_;
    AudioQueueRef queue_ = nullptr;
    bool active_ = false;
};

class AudioQueueCallbackUse {
public:
    explicit AudioQueueCallbackUse(AudioQueueEntry *entry) : entry_(entry) {
        if(!entry_) return;
        std::lock_guard<std::mutex> lock(entry_->stateMutex);
        if(entry_->disposed.load(std::memory_order_relaxed) ||
           entry_->disposing || !entry_->queue) return;
        ++entry_->activeCallbacks;
        active_ = true;
    }

    ~AudioQueueCallbackUse() {
        if(!active_ || !entry_) return;
        std::lock_guard<std::mutex> lock(entry_->stateMutex);
        if(entry_->activeCallbacks) --entry_->activeCallbacks;
        entry_->stateCondition.notify_all();
    }

    explicit operator bool() const { return active_; }

private:
    AudioQueueEntry *entry_ = nullptr;
    bool active_ = false;
};

bool AudioQueueGuestCallbackIsOnCurrentThread(u32 token) {
    if(!token) return false;
    const auto iterator =
        audioQueueGuestCallbacksOnCurrentThread.find(token);
    return iterator != audioQueueGuestCallbacksOnCurrentThread.end() &&
        iterator->second != 0;
}

void ClearAudioQueueBuffers(const std::shared_ptr<AudioQueueEntry> &entry) {
    if(!entry) return;
    std::lock_guard<std::mutex> lock(entry->buffersMutex);
    entry->buffersByGuest.clear();
    entry->buffersByNative.clear();
}

void ClearAudioQueueTimelines(
        const std::shared_ptr<AudioQueueEntry> &entry) {
    if(!entry) return;
    std::lock_guard<std::mutex> lock(entry->timelinesMutex);
    /* AudioQueueDispose owns and disposes every remaining native timeline. */
    entry->timelines.clear();
}

void MarkOutputAudioQueueBuffersAvailable(
        const std::shared_ptr<AudioQueueEntry> &entry) {
    if(!entry || entry->direction != AudioQueueDirection::Output) return;
    std::vector<std::shared_ptr<AudioQueueBufferEntry>> buffers;
    {
        std::lock_guard<std::mutex> lock(entry->buffersMutex);
        buffers.reserve(entry->buffersByGuest.size());
        for(const auto &item : entry->buffersByGuest)
            buffers.push_back(item.second);
    }
    for(const auto &buffer : buffers) {
        if(!buffer) continue;
        std::lock_guard<std::mutex> lock(buffer->stateMutex);
        buffer->outputEnqueued = false;
    }
}

void ScheduleDeferredAudioQueueStop(
        std::shared_ptr<AudioQueueEntry> entry,
        Boolean immediate) {
    dispatch_async(dispatch_get_global_queue(
            DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        {
            std::unique_lock<std::mutex> lock(entry->stateMutex);
            entry->stateCondition.wait(lock, [&] {
                return entry->activeCallbacks == 0 ||
                    entry->disposed.load(std::memory_order_relaxed) ||
                    entry->disposing;
            });
            if(entry->disposed.load(std::memory_order_relaxed) ||
               entry->disposing) return;
        }

        AudioQueueUse queueUse(entry);
        if(!queueUse) return;
        const OSStatus status = AudioQueueStop(queueUse.queue(), immediate);
        if(status == noErr && immediate)
            MarkOutputAudioQueueBuffersAvailable(entry);
        if(status != noErr) {
            fprintf(stderr,
                "LC32: deferred AudioQueueStop failed with status %d\n",
                static_cast<int>(status));
        }
    });
}

void ScheduleDeferredAudioQueueDispose(
        std::shared_ptr<AudioQueueEntry> entry,
        Boolean immediate, u32 guestCleanupThunk) {
    dispatch_async(dispatch_get_global_queue(
            DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        AudioQueueRef queue = nullptr;
        {
            std::unique_lock<std::mutex> lock(entry->stateMutex);
            entry->stateCondition.wait(lock, [&] {
                return entry->activeCallbacks == 0 &&
                    entry->activeUsers == 0;
            });
            queue = entry->queue;
        }

        ClearAudioQueuePropertyListeners(entry);
        const OSStatus status = queue
            ? AudioQueueDispose(queue, immediate)
            : kAudio_ParamError;
        ClearAudioQueueTimelines(entry);
        {
            std::lock_guard<std::mutex> lock(entry->stateMutex);
            entry->queue = nullptr;
        }
        ClearAudioQueueBuffers(entry);
        const u32 cleanupArguments[] = { entry->token };
        if(!InvokeGuestAudioQueueFunction(guestCleanupThunk,
                cleanupArguments,
                sizeof(cleanupArguments) / sizeof(cleanupArguments[0]))) {
            fprintf(stderr,
                "LC32: could not release deferred guest AudioQueue "
                "allocations for queue 0x%x\n", entry->token);
        }
        if(status != noErr) {
            fprintf(stderr,
                "LC32: deferred AudioQueueDispose failed with status %d\n",
                static_cast<int>(status));
            QuarantineAudioQueue(entry);
        }
    });
}

std::shared_ptr<AudioQueueBufferEntry> FindAudioQueueBuffer(
        const std::shared_ptr<AudioQueueEntry> &entry, u32 guestBuffer) {
    if(!entry) return nullptr;
    std::lock_guard<std::mutex> lock(entry->buffersMutex);
    const auto iterator = entry->buffersByGuest.find(guestBuffer);
    return iterator == entry->buffersByGuest.end()
        ? nullptr : iterator->second;
}

void AudioQueueInputCallbackBridge(
        void *rawEntry, AudioQueueRef, AudioQueueBufferRef nativeBuffer,
        const AudioTimeStamp *startTime, UInt32 packetCount,
        const AudioStreamPacketDescription *packetDescriptions) {
    AudioQueueEntry *entry = static_cast<AudioQueueEntry *>(rawEntry);
    if(!entry || !nativeBuffer) return;
    AudioQueueCallbackUse callbackUse(entry);
    if(!callbackUse) return;

    std::shared_ptr<AudioQueueBufferEntry> buffer;
    {
        std::lock_guard<std::mutex> lock(entry->buffersMutex);
        const auto iterator = entry->buffersByNative.find(nativeBuffer);
        if(iterator == entry->buffersByNative.end()) return;
        buffer = iterator->second;
    }
    if(!buffer || nativeBuffer->mAudioDataByteSize >
            buffer->audioDataCapacity) {
        fprintf(stderr,
            "LC32: AudioQueue input callback exceeded guest buffer "
            "capacity (bytes=%u/%u)\n",
            nativeBuffer->mAudioDataByteSize, buffer->audioDataCapacity);
        return;
    }

    if(nativeBuffer->mAudioDataByteSize &&
       !WriteGuestBytes(buffer->guestAudioData,
            nativeBuffer->mAudioDataByteSize, nativeBuffer->mAudioData)) {
        fprintf(stderr,
            "LC32: could not copy AudioQueue input data to guest buffer "
            "0x%x\n", buffer->guestBuffer);
        return;
    }
    const AudioStreamPacketDescription *descriptions = packetDescriptions
        ? packetDescriptions : nativeBuffer->mPacketDescriptions;
    if(descriptions && packetCount > buffer->packetDescriptionCapacity) {
        fprintf(stderr,
            "LC32: AudioQueue input callback exceeded guest packet "
            "capacity (packets=%u/%u)\n", packetCount,
            buffer->packetDescriptionCapacity);
        return;
    }
    if(descriptions && packetCount &&
       !WriteGuestBytes(buffer->guestPacketDescriptions,
            static_cast<size_t>(packetCount) *
                sizeof(AudioStreamPacketDescription), descriptions)) {
        fprintf(stderr,
            "LC32: could not copy AudioQueue packet descriptions to "
            "guest buffer 0x%x\n", buffer->guestBuffer);
        return;
    }
    if(!WriteGuestU32(buffer->guestBuffer +
            offsetof(GuestAudioQueueBuffer, audioDataByteSize),
            nativeBuffer->mAudioDataByteSize) ||
       !WriteGuestU32(buffer->guestBuffer +
            offsetof(GuestAudioQueueBuffer, packetDescriptionCount),
            descriptions ? packetCount : 0)) {
        return;
    }

    GuestAudioQueueInputCallbackStorage storage = {};
    if(startTime) storage.timeStamp = *startTime;
    storage.packetCount = packetCount;
    storage.packetDescriptions = descriptions && packetCount
        ? buffer->guestPacketDescriptions : 0;
    if(!WriteGuestBytes(buffer->guestCallbackStorage,
            sizeof(storage), &storage)) {
        return;
    }

    const u32 arguments[] = {
        entry->guestCallback,
        entry->guestUserData,
        entry->token,
        buffer->guestBuffer,
        buffer->guestCallbackStorage,
    };
    if(!InvokeGuestAudioQueueFunction(
            entry->guestCallbackThunk, arguments,
            sizeof(arguments) / sizeof(arguments[0]))) {
        fprintf(stderr,
            "LC32: could not deliver AudioQueue input callback 0x%x\n",
            entry->guestCallback);
    }
}

void AudioQueueOutputCallbackBridge(
        void *rawEntry, AudioQueueRef, AudioQueueBufferRef nativeBuffer) {
    AudioQueueEntry *entry = static_cast<AudioQueueEntry *>(rawEntry);
    if(!entry || !nativeBuffer) return;
    AudioQueueCallbackUse callbackUse(entry);
    if(!callbackUse) return;

    std::shared_ptr<AudioQueueBufferEntry> buffer;
    {
        std::lock_guard<std::mutex> lock(entry->buffersMutex);
        const auto iterator = entry->buffersByNative.find(nativeBuffer);
        if(iterator == entry->buffersByNative.end()) return;
        buffer = iterator->second;
    }
    if(!buffer) return;
    {
        std::lock_guard<std::mutex> lock(buffer->stateMutex);
        buffer->outputEnqueued = false;
    }

    const u32 arguments[] = {
        entry->guestCallback,
        entry->guestUserData,
        entry->token,
        buffer->guestBuffer,
    };
    if(!InvokeGuestAudioQueueFunction(
            entry->guestCallbackThunk, arguments,
            sizeof(arguments) / sizeof(arguments[0]))) {
        fprintf(stderr,
            "LC32: could not deliver AudioQueue output callback 0x%x\n",
            entry->guestCallback);
    }
}

void AudioQueuePropertyListenerBridge(
        void *rawListener, AudioQueueRef,
        AudioQueuePropertyID property) {
    auto listener = FindAudioQueuePropertyListener(
        reinterpret_cast<uintptr_t>(rawListener));
    if(!listener || !listener->enabled.load(std::memory_order_acquire) ||
       property != listener->property) {
        return;
    }

    auto entry = listener->queueEntry.lock();
    AudioQueueCallbackUse callbackUse(entry.get());
    if(!callbackUse ||
       !listener->enabled.load(std::memory_order_acquire)) {
        return;
    }

    const u32 arguments[] = {
        listener->guestCallback,
        listener->guestUserData,
        entry->token,
        property,
    };
    if(!InvokeGuestAudioQueueFunction(
            listener->guestCallbackThunk, arguments,
            sizeof(arguments) / sizeof(arguments[0]))) {
        fprintf(stderr,
            "LC32: could not deliver AudioQueue property callback 0x%x\n",
            listener->guestCallback);
    }
}

bool IsRawExtAudioFileProperty(ExtAudioFilePropertyID property) {
    switch(property) {
        case kExtAudioFileProperty_FileDataFormat:
        case kExtAudioFileProperty_FileChannelLayout:
        case kExtAudioFileProperty_ClientDataFormat:
        case kExtAudioFileProperty_ClientChannelLayout:
        case kExtAudioFileProperty_CodecManufacturer:
        case kExtAudioFileProperty_FileMaxPacketSize:
        case kExtAudioFileProperty_ClientMaxPacketSize:
        case kExtAudioFileProperty_FileLengthFrames:
        case kExtAudioFileProperty_IOBufferSizeBytes:
        case kExtAudioFileProperty_PacketTable:
            return true;
        default:
            return false;
    }
}

bool IsAudioSessionObjectProperty(AudioSessionPropertyID property) {
    switch(property) {
        case kAudioSessionProperty_AudioRoute:
        case kAudioSessionProperty_InputSources:
        case kAudioSessionProperty_OutputDestinations:
        case kAudioSessionProperty_InputSource:
        case kAudioSessionProperty_OutputDestination:
        case kAudioSessionProperty_AudioRouteDescription:
            return true;
        default:
            return false;
    }
}

std::once_flag nativeAudioSessionInitializationOnce;
OSStatus nativeAudioSessionInitializationStatus =
    kAudioSessionInitializationError;

OSStatus EnsureNativeAudioSessionInitialized() {
    std::call_once(nativeAudioSessionInitializationOnce, [] {
        OSStatus status = AudioSessionInitialize(
            nullptr, nullptr, nullptr, nullptr);
        /*
         * LiveContainer or an Objective-C AVAudioSession user may have already
         * initialized the process-wide legacy session. It is still usable by
         * the forwarded C API in that case.
         */
        if(status == kAudioSessionAlreadyInitialized) status = noErr;
        nativeAudioSessionInitializationStatus = status;
    });
    return nativeAudioSessionInitializationStatus;
}

id SharedAVAudioSession();

OSStatus SetNativeAudioSessionActive(BOOL active) {
    id session = SharedAVAudioSession();
    SEL selector = sel_registerName("setActive:error:");
    if(session && [session respondsToSelector:selector]) {
        NSError *error = nil;
        const BOOL succeeded =
            reinterpret_cast<BOOL (*)(id, SEL, BOOL, NSError **)>(
                objc_msgSend)(session, selector, active, &error);
        if(succeeded) return noErr;
        return error ? static_cast<OSStatus>(error.code)
                     : kAudioSessionUnspecifiedError;
    }

    return AudioSessionSetActive(active);
}

OSStatus DispatchAudioSessionSetActive(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 1)) return kAudio_ParamError;
    const OSStatus initializationStatus =
        EnsureNativeAudioSessionInitialized();
    if(initializationStatus != noErr) return initializationStatus;

    return SetNativeAudioSessionActive(SlotU32(call, 0) != 0);
}

OSStatus DispatchAudioSessionSetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 3)) return kAudio_ParamError;

    const AudioSessionPropertyID property = SlotU32(call, 0);
    const u32 dataSize = SlotU32(call, 1);
    const u32 guestData = SlotU32(call, 2);
    if(dataSize > kMaximumPropertyBytes || (dataSize && !guestData))
        return kAudio_ParamError;

    /*
     * ARM32 object-valued properties contain a four-byte guest proxy, not a
     * native CFTypeRef. The YouTube properties handled here are scalar; reject
     * object properties explicitly until they receive typed conversion.
     */
    if(IsAudioSessionObjectProperty(property) ||
       property == kAudioSessionProperty_AudioRouteChange) {
        return kAudioSessionUnsupportedPropertyError;
    }

    std::vector<uint8_t> bytes(dataSize ? dataSize : 1);
    if(dataSize && !ReadGuestBytes(guestData, dataSize, bytes.data()))
        return kAudio_ParamError;

    /* Modern hosts may reject this deprecated iOS property with 'what'.
     * The RemoteIO compatibility unit consumes it locally to choose its
     * render quantum, so preserve the iOS 10 success contract for valid
     * durations rather than making host AudioSession support a prerequisite. */
    if(property ==
            kAudioSessionProperty_PreferredHardwareIOBufferDuration) {
        if(dataSize != sizeof(Float32))
            return kAudioSessionBadPropertySizeError;
        Float32 duration = 0;
        memcpy(&duration, bytes.data(), sizeof(duration));
        return duration > 0.0f && duration <= 1.0f
            ? noErr : kAudio_ParamError;
    }

    const OSStatus initializationStatus =
        EnsureNativeAudioSessionInitialized();
    if(initializationStatus != noErr) return initializationStatus;
    return AudioSessionSetProperty(property, dataSize,
        dataSize ? bytes.data() : nullptr);
}

OSStatus WriteAudioSessionValue(const LC32AudioToolboxCall &call,
                                const void *value, u32 valueSize) {
    u32 requestedSize = 0;
    if(!ReadGuestU32(SlotU32(call, 1), requestedSize) ||
       !WriteGuestU32(SlotU32(call, 1), valueSize)) {
        return kAudio_ParamError;
    }
    if(requestedSize < valueSize || (valueSize && !SlotU32(call, 2)))
        return kAudioSessionBadPropertySizeError;
    if(valueSize && Dynarmic_mem_1write(SlotU32(call, 2), valueSize,
            const_cast<char *>(reinterpret_cast<const char *>(value))) != 0) {
        return kAudio_ParamError;
    }
    return noErr;
}

id SharedAVAudioSession() {
    Class cls = NSClassFromString(@"AVAudioSession");
    SEL selector = sel_registerName("sharedInstance");
    if(!cls || ![cls respondsToSelector:selector]) return nil;
    return reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(cls, selector);
}

NSString *LegacyAudioRouteFromAVAudioSession(id session) {
    SEL currentRouteSelector = sel_registerName("currentRoute");
    if(!session || ![session respondsToSelector:currentRouteSelector])
        return nil;
    id route = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(
        session, currentRouteSelector);
    SEL outputsSelector = sel_registerName("outputs");
    if(!route || ![route respondsToSelector:outputsSelector]) return nil;
    NSArray *outputs = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(
        route, outputsSelector);
    id output = outputs.firstObject;
    SEL portTypeSelector = sel_registerName("portType");
    if(!output || ![output respondsToSelector:portTypeSelector]) return nil;
    NSString *portType = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(
        output, portTypeSelector);
    if([portType isEqualToString:@"Headphones"]) return @"Headphone";
    if([portType isEqualToString:@"HeadsetMic"]) return @"Headset";
    return portType;
}

OSStatus DispatchObservedAudioSessionProperty(
        const LC32AudioToolboxCall &call, bool &handled) {
    handled = true;
    id session = SharedAVAudioSession();
    if(!session) {
        handled = false;
        return kAudioSessionNotInitialized;
    }

    switch(SlotU32(call, 0)) {
        case kAudioSessionProperty_OtherAudioIsPlaying: {
            SEL selector = sel_registerName("isOtherAudioPlaying");
            if(![session respondsToSelector:selector]) break;
            const u32 value = reinterpret_cast<BOOL (*)(id, SEL)>(
                objc_msgSend)(session, selector) ? 1 : 0;
            return WriteAudioSessionValue(call, &value, sizeof(value));
        }
        case kAudioSessionProperty_CurrentHardwareOutputVolume: {
            SEL selector = sel_registerName("outputVolume");
            if(![session respondsToSelector:selector]) break;
            const float value = reinterpret_cast<float (*)(id, SEL)>(
                objc_msgSend)(session, selector);
            return WriteAudioSessionValue(call, &value, sizeof(value));
        }
        case kAudioSessionProperty_AudioRoute: {
            NSString *route = LegacyAudioRouteFromAVAudioSession(session);
            if(!route) break;
            const u32 guestRoute = route.guest_self;
            return WriteAudioSessionValue(
                call, &guestRoute, sizeof(guestRoute));
        }
        default:
            handled = false;
            return kAudioSessionUnsupportedPropertyError;
    }

    handled = false;
    return kAudioSessionUnsupportedPropertyError;
}

OSStatus DispatchAudioSessionGetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 3) || !SlotU32(call, 1))
        return kAudio_ParamError;

    bool handled = false;
    const OSStatus observedStatus =
        DispatchObservedAudioSessionProperty(call, handled);
    if(handled) return observedStatus;

    const OSStatus initializationStatus =
        EnsureNativeAudioSessionInitialized();
    if(initializationStatus != noErr) return initializationStatus;

    const AudioSessionPropertyID property = SlotU32(call, 0);
    u32 requestedSize = 0;
    if(!ReadGuestU32(SlotU32(call, 1), requestedSize) ||
       requestedSize > kMaximumPropertyBytes)
        return kAudio_ParamError;

    if(IsAudioSessionObjectProperty(property)) {
        CFTypeRef object = nullptr;
        UInt32 hostSize = sizeof(object);
        const OSStatus status =
            AudioSessionGetProperty(property, &hostSize, &object);
        if(status != noErr) return status;
        const u32 guestObject = object ? [(id)object guest_self] : 0;
        return WriteAudioSessionValue(
            call, &guestObject, sizeof(guestObject));
    }

    std::vector<uint8_t> bytes(requestedSize ? requestedSize : 1);
    UInt32 returnedSize = requestedSize;
    const OSStatus status = AudioSessionGetProperty(property,
        &returnedSize, requestedSize ? bytes.data() : nullptr);
    if(!WriteGuestU32(SlotU32(call, 1), returnedSize))
        return kAudio_ParamError;
    if(status == noErr && returnedSize) {
        if(returnedSize > requestedSize || !SlotU32(call, 2) ||
           Dynarmic_mem_1write(SlotU32(call, 2), returnedSize,
               reinterpret_cast<char *>(bytes.data())) != 0) {
            return kAudio_ParamError;
        }
    }
    return status;
}

void RemoteIOOutputCallback(void *rawEntry, AudioQueueRef queue,
                            AudioQueueBufferRef nativeBuffer) {
    const uintptr_t rawToken = reinterpret_cast<uintptr_t>(rawEntry);
    if(rawToken == 0 || rawToken > UINT32_MAX || !nativeBuffer) return;
    auto entry = FindRemoteIOOutput(static_cast<u32>(rawToken));
    if(!entry) return;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        ++entry->activeCallbacks;
        if(!entry->disposing && queue == entry->queue) {
            for(auto &candidate : entry->buffers) {
                if(candidate.buffer != nativeBuffer) continue;
                if(candidate.state ==
                        RemoteIOOutputBufferState::Enqueued) {
                    candidate.state = RemoteIOOutputBufferState::Free;
                }
                break;
            }
        }
        --entry->activeCallbacks;
    }
    entry->condition.notify_all();
}

class RemoteIOOutputUse {
public:
    explicit RemoteIOOutputUse(
            const std::shared_ptr<RemoteIOOutputEntry> &entry)
        : entry_(entry) {
        if(!entry_) return;
        std::lock_guard<std::mutex> lock(entry_->mutex);
        if(entry_->disposing || !entry_->queue) return;
        ++entry_->activeUsers;
        active_ = true;
    }

    ~RemoteIOOutputUse() {
        if(!active_ || !entry_) return;
        {
            std::lock_guard<std::mutex> lock(entry_->mutex);
            if(entry_->activeUsers) --entry_->activeUsers;
        }
        entry_->condition.notify_all();
    }

    explicit operator bool() const { return active_; }

private:
    std::shared_ptr<RemoteIOOutputEntry> entry_;
    bool active_ = false;
};

OSStatus ConfigureRemoteIOOutputEntry(
        RemoteIOOutputEntry &entry,
        const AudioStreamBasicDescription &inputFormat,
        u32 framesPerQuantum) {
    if(inputFormat.mFormatID != kAudioFormatLinearPCM ||
       !(inputFormat.mSampleRate >= 1.0 &&
         inputFormat.mSampleRate <= 384000.0) ||
       inputFormat.mChannelsPerFrame == 0 ||
       inputFormat.mChannelsPerFrame > kRemoteIOOutputMaximumChannels ||
       inputFormat.mBytesPerFrame == 0 ||
       framesPerQuantum == 0 ||
       framesPerQuantum > kRemoteIOOutputMaximumFrames) {
        return kAudioUnitErr_FormatNotSupported;
    }

    AudioStreamBasicDescription guestFormat = inputFormat;
    guestFormat.mReserved = 0;
    if(guestFormat.mFramesPerPacket == 0)
        guestFormat.mFramesPerPacket = 1;
    if(guestFormat.mFramesPerPacket != 1)
        return kAudioUnitErr_FormatNotSupported;
    const uint64_t expectedGuestPacketBytes =
        static_cast<uint64_t>(guestFormat.mBytesPerFrame) *
        guestFormat.mFramesPerPacket;
    if(expectedGuestPacketBytes > UINT32_MAX ||
       (guestFormat.mBytesPerPacket != 0 &&
        guestFormat.mBytesPerPacket != expectedGuestPacketBytes)) {
        return kAudioUnitErr_FormatNotSupported;
    }
    guestFormat.mBytesPerPacket =
        static_cast<u32>(expectedGuestPacketBytes);

    const bool nonInterleaved =
        (guestFormat.mFormatFlags &
            kAudioFormatFlagIsNonInterleaved) != 0;
    const uint64_t nativeBytesPerFrame =
        static_cast<uint64_t>(guestFormat.mBytesPerFrame) *
        (nonInterleaved ? guestFormat.mChannelsPerFrame : 1u);
    const uint64_t nativeBufferBytes =
        nativeBytesPerFrame * framesPerQuantum;
    if(nativeBytesPerFrame == 0 || nativeBytesPerFrame > UINT32_MAX ||
       nativeBufferBytes == 0 ||
       nativeBufferBytes > kRemoteIOOutputMaximumBufferBytes) {
        return kAudioUnitErr_FormatNotSupported;
    }

    AudioStreamBasicDescription nativeFormat = guestFormat;
    nativeFormat.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved;
    nativeFormat.mBytesPerFrame = static_cast<u32>(nativeBytesPerFrame);
    nativeFormat.mBytesPerPacket = nativeFormat.mBytesPerFrame;

    entry.guestFormat = guestFormat;
    entry.nativeFormat = nativeFormat;
    entry.framesPerQuantum = framesPerQuantum;
    entry.guestBytesPerFrame = guestFormat.mBytesPerFrame;
    entry.nativeBytesPerFrame = nativeFormat.mBytesPerFrame;
    entry.nativeBufferBytes = static_cast<u32>(nativeBufferBytes);
    entry.nonInterleaved = nonInterleaved;
    const double timeoutMilliseconds =
        3000.0 * framesPerQuantum / guestFormat.mSampleRate;
    entry.submitTimeoutMilliseconds = static_cast<u32>(
        timeoutMilliseconds < 100.0 ? 100.0 :
        timeoutMilliseconds > 500.0 ? 500.0 :
        timeoutMilliseconds + 0.5);
    return noErr;
}

OSStatus DestroyRemoteIOOutput(
        const std::shared_ptr<RemoteIOOutputEntry> &entry) {
    if(!entry) return kAudioUnitErr_Uninitialized;
    AudioToolboxGuestHostCallQuiescence quiescence;
    AudioQueueRef queue = nullptr;
    {
        std::unique_lock<std::mutex> lock(entry->mutex);
        entry->disposing = true;
        entry->condition.notify_all();
        entry->condition.wait(lock, [&] {
            return entry->activeUsers == 0;
        });
        queue = entry->queue;
    }
    if(!queue) return kAudioUnitErr_Uninitialized;

    const OSStatus stopStatus = AudioQueueStop(queue, true);
    {
        std::unique_lock<std::mutex> lock(entry->mutex);
        entry->condition.wait(lock, [&] {
            return entry->activeCallbacks == 0;
        });
    }
    const OSStatus disposeStatus = AudioQueueDispose(queue, true);
    {
        std::unique_lock<std::mutex> lock(entry->mutex);
        entry->condition.wait(lock, [&] {
            return entry->activeCallbacks == 0;
        });
        if(disposeStatus == noErr) {
            entry->queue = nullptr;
        }
    }
    if(disposeStatus != noErr) {
        QuarantineRemoteIOOutput(entry);
        return disposeStatus;
    }
    return stopStatus == kAudioQueueErr_InvalidRunState
        ? noErr : stopStatus;
}

OSStatus DispatchRemoteIOOutputStart(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 3) || !SlotU32(call, 0) ||
       !SlotU32(call, 2) || !WriteGuestU32(SlotU32(call, 2), 0)) {
        return kAudio_ParamError;
    }

    AudioStreamBasicDescription format = {};
    if(!ReadGuestBytes(SlotU32(call, 0), sizeof(format), &format))
        return kAudio_ParamError;
    std::shared_ptr<RemoteIOOutputEntry> entry;
    try {
        entry = std::make_shared<RemoteIOOutputEntry>();
    } catch(const std::bad_alloc &) {
        return kAudio_MemFullError;
    }
    OSStatus status = ConfigureRemoteIOOutputEntry(
        *entry, format, SlotU32(call, 1));
    if(status != noErr) return status;

    entry->token = AllocateRemoteIOOutputToken();
    if(!entry->token) return kAudio_MemFullError;

    AudioQueueRef queue = nullptr;
    {
        AudioToolboxGuestHostCallQuiescence quiescence;
        status = AudioQueueNewOutput(&entry->nativeFormat,
            RemoteIOOutputCallback,
            reinterpret_cast<void *>(
                static_cast<uintptr_t>(entry->token)),
            nullptr, nullptr, 0, &queue);
    }
    if(status != noErr) return status;
    entry->queue = queue;
    for(auto &buffer : entry->buffers) {
        {
            AudioToolboxGuestHostCallQuiescence quiescence;
            status = AudioQueueAllocateBuffer(
                queue, entry->nativeBufferBytes, &buffer.buffer);
        }
        if(status != noErr) {
            OSStatus disposeStatus;
            {
                AudioToolboxGuestHostCallQuiescence quiescence;
                disposeStatus = AudioQueueDispose(queue, true);
            }
            if(disposeStatus != noErr) QuarantineRemoteIOOutput(entry);
            return status;
        }
    }

    for(u32 index = 0; index < kRemoteIOOutputPrimeBufferCount; ++index) {
        AudioQueueBufferRef buffer = entry->buffers[index].buffer;
        if(!buffer || buffer->mAudioDataBytesCapacity <
                entry->nativeBufferBytes || !buffer->mAudioData) {
            status = kAudio_ParamError;
            break;
        }
        memset(buffer->mAudioData, 0, entry->nativeBufferBytes);
        buffer->mAudioDataByteSize = entry->nativeBufferBytes;
        entry->buffers[index].state =
            RemoteIOOutputBufferState::Enqueued;
        {
            AudioToolboxGuestHostCallQuiescence quiescence;
            status = AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr);
        }
        if(status != noErr) {
            entry->buffers[index].state =
                RemoteIOOutputBufferState::Free;
            break;
        }
    }
    if(status != noErr) {
        OSStatus disposeStatus;
        {
            AudioToolboxGuestHostCallQuiescence quiescence;
            disposeStatus = AudioQueueDispose(queue, true);
        }
        if(disposeStatus != noErr) QuarantineRemoteIOOutput(entry);
        return status;
    }

    if(!PublishRemoteIOOutput(entry)) {
        OSStatus disposeStatus;
        {
            AudioToolboxGuestHostCallQuiescence quiescence;
            disposeStatus = AudioQueueDispose(queue, true);
        }
        if(disposeStatus != noErr) QuarantineRemoteIOOutput(entry);
        return kAudio_MemFullError;
    }
    {
        AudioToolboxGuestHostCallQuiescence quiescence;
        status = AudioQueueStart(queue, nullptr);
    }
    if(status != noErr ||
       !WriteGuestU32(SlotU32(call, 2), entry->token)) {
        (void)TakeRemoteIOOutput(entry->token);
        const OSStatus destroyStatus = DestroyRemoteIOOutput(entry);
        if(status != noErr) return status;
        (void)destroyStatus;
        return kAudio_ParamError;
    }
    return noErr;
}

OSStatus DispatchRemoteIOOutputSubmit(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    auto entry = FindRemoteIOOutput(SlotU32(call, 0));
    RemoteIOOutputUse outputUse(entry);
    if(!outputUse) return kAudioUnitErr_Uninitialized;
    if(SlotU32(call, 2) != entry->framesPerQuantum)
        return kAudio_ParamError;
    const bool silence = SlotU32(call, 3) != 0;
    const u32 expectedBufferCount = entry->nonInterleaved
        ? entry->guestFormat.mChannelsPerFrame : 1u;

    GuestAudioBuffer guestBuffers[kRemoteIOOutputMaximumChannels] = {};
    u32 guestBufferCount = expectedBufferCount;
    if(!silence) {
        const u32 guestList = SlotU32(call, 1);
        u32 returnedBufferCount = 0;
        if(!ReadGuestU32(guestList, returnedBufferCount) ||
           returnedBufferCount != guestBufferCount) {
            return kAudio_ParamError;
        }
        const uint64_t buffersAddress =
            static_cast<uint64_t>(guestList) + sizeof(u32);
        const size_t buffersBytes =
            guestBufferCount * sizeof(GuestAudioBuffer);
        if(buffersAddress > UINT32_MAX ||
           buffersAddress + buffersBytes >
               static_cast<uint64_t>(UINT32_MAX) + 1 ||
           !ReadGuestBytes(static_cast<u32>(buffersAddress),
               buffersBytes, guestBuffers)) {
            return kAudio_ParamError;
        }
    }

    RemoteIOOutputBufferEntry *selected = nullptr;
    {
        AudioToolboxGuestHostCallQuiescence quiescence;
        std::unique_lock<std::mutex> lock(entry->mutex);
        const auto deadline = std::chrono::steady_clock::now() +
            std::chrono::milliseconds(entry->submitTimeoutMilliseconds);
        const bool available = entry->condition.wait_until(
            lock, deadline, [&] {
                if(entry->disposing) return true;
                for(const auto &buffer : entry->buffers) {
                    if(buffer.state ==
                            RemoteIOOutputBufferState::Free) {
                        return true;
                    }
                }
                return false;
            });
        if(!available) return kAudioUnitErr_RenderTimeout;
        if(entry->disposing || !entry->queue)
            return kAudioUnitErr_Uninitialized;
        for(auto &buffer : entry->buffers) {
            if(buffer.state != RemoteIOOutputBufferState::Free) continue;
            buffer.state = RemoteIOOutputBufferState::Filling;
            selected = &buffer;
            break;
        }
    }
    const auto releaseSelected = [&] {
        if(!selected) return;
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(selected->state == RemoteIOOutputBufferState::Filling ||
           selected->state == RemoteIOOutputBufferState::Enqueued) {
            selected->state = RemoteIOOutputBufferState::Free;
        }
        entry->condition.notify_all();
    };
    if(!selected || !selected->buffer || !selected->buffer->mAudioData ||
       selected->buffer->mAudioDataBytesCapacity <
            entry->nativeBufferBytes) {
        releaseSelected();
        return kAudio_ParamError;
    }

    uint8_t *nativeBytes = static_cast<uint8_t *>(
        selected->buffer->mAudioData);
    bool copied = true;
    if(silence) {
        memset(nativeBytes, 0, entry->nativeBufferBytes);
    } else if(!entry->nonInterleaved) {
        const GuestAudioBuffer &guest = guestBuffers[0];
        copied = guest.channels == entry->guestFormat.mChannelsPerFrame &&
            guest.byteSize >= entry->nativeBufferBytes && guest.data &&
            ReadGuestBytes(guest.data, entry->nativeBufferBytes,
                nativeBytes);
    } else {
        const size_t channelBytes =
            static_cast<size_t>(entry->guestBytesPerFrame) *
            entry->framesPerQuantum;
        const size_t totalGuestBytes = channelBytes * guestBufferCount;
        std::vector<uint8_t> planarBytes;
        try {
            planarBytes.resize(totalGuestBytes);
        } catch(const std::bad_alloc &) {
            releaseSelected();
            return kAudio_MemFullError;
        }
        for(size_t channel = 0;
                copied && channel < guestBufferCount; ++channel) {
            const GuestAudioBuffer &guest = guestBuffers[channel];
            copied = guest.channels == 1 &&
                guest.byteSize >= channelBytes && guest.data &&
                ReadGuestBytes(guest.data, channelBytes,
                    planarBytes.data() + channel * channelBytes);
        }
        if(copied) {
            for(u32 frame = 0; frame < entry->framesPerQuantum; ++frame) {
                for(size_t channel = 0;
                        channel < guestBufferCount; ++channel) {
                    memcpy(nativeBytes +
                            (static_cast<size_t>(frame) *
                                guestBufferCount + channel) *
                                entry->guestBytesPerFrame,
                        planarBytes.data() + channel * channelBytes +
                            static_cast<size_t>(frame) *
                                entry->guestBytesPerFrame,
                        entry->guestBytesPerFrame);
                }
            }
        }
    }

    if(!copied) {
        releaseSelected();
        return kAudio_ParamError;
    }

    selected->buffer->mAudioDataByteSize = entry->nativeBufferBytes;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(entry->disposing || !entry->queue) {
            selected->state = RemoteIOOutputBufferState::Free;
            entry->condition.notify_all();
            return kAudioUnitErr_Uninitialized;
        }
        selected->state = RemoteIOOutputBufferState::Enqueued;
    }
    OSStatus status;
    {
        AudioToolboxGuestHostCallQuiescence quiescence;
        status = AudioQueueEnqueueBuffer(
            entry->queue, selected->buffer, 0, nullptr);
    }
    if(status != noErr) {
        releaseSelected();
    }
    return status;
}

OSStatus DispatchRemoteIOOutputStop(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 1) || !SlotU32(call, 0))
        return kAudio_ParamError;
    auto entry = TakeRemoteIOOutput(SlotU32(call, 0));
    return entry ? DestroyRemoteIOOutput(entry)
                 : kAudioUnitErr_Uninitialized;
}

std::shared_ptr<ExtAudioFileEntry> FindExtAudioFile(u32 token) {
    std::lock_guard<std::mutex> lock(extAudioFilesMutex);
    const auto iterator = extAudioFiles.find(token);
    return iterator == extAudioFiles.end() ? nullptr : iterator->second;
}

u32 InsertExtAudioFile(ExtAudioFileRef file) {
    if(!file) return 0;
    auto entry = std::make_shared<ExtAudioFileEntry>();
    entry->file = file;
    std::lock_guard<std::mutex> lock(extAudioFilesMutex);
    for(size_t attempt = 0; attempt < UINT32_MAX; ++attempt) {
        u32 token = nextExtAudioFileToken.fetch_add(1,
            std::memory_order_relaxed);
        if(token == 0) continue;
        if(extAudioFiles.emplace(token, entry).second) return token;
    }
    return 0;
}

std::shared_ptr<ExtAudioFileEntry> TakeExtAudioFile(u32 token) {
    std::lock_guard<std::mutex> lock(extAudioFilesMutex);
    const auto iterator = extAudioFiles.find(token);
    if(iterator == extAudioFiles.end()) return nullptr;
    auto entry = iterator->second;
    extAudioFiles.erase(iterator);
    return entry;
}

std::shared_ptr<AudioFileEntry> FindAudioFile(u32 token) {
    std::lock_guard<std::mutex> lock(audioFilesMutex);
    const auto iterator = audioFiles.find(token);
    return iterator == audioFiles.end() ? nullptr : iterator->second;
}

u32 InsertAudioFile(
        AudioFileID file,
        std::unique_ptr<AudioFileCallbackContext> callbackContext = {}) {
    if(!file) return 0;
    auto entry = std::make_shared<AudioFileEntry>();
    entry->file = file;
    entry->callbackContext = std::move(callbackContext);
    std::lock_guard<std::mutex> lock(audioFilesMutex);
    for(size_t attempt = 0; attempt < UINT32_MAX; ++attempt) {
        u32 token = nextAudioFileToken.fetch_add(1,
            std::memory_order_relaxed);
        if(token == 0) continue;
        if(audioFiles.emplace(token, entry).second) return token;
    }
    return 0;
}

std::shared_ptr<AudioFileEntry> TakeAudioFile(u32 token) {
    std::lock_guard<std::mutex> lock(audioFilesMutex);
    const auto iterator = audioFiles.find(token);
    if(iterator == audioFiles.end()) return nullptr;
    auto entry = iterator->second;
    audioFiles.erase(iterator);
    return entry;
}

OSStatus PublishAudioFile(
        AudioFileID file, u32 guestOutAudioFile,
        std::unique_ptr<AudioFileCallbackContext> callbackContext = {}) {
    const u32 token = InsertAudioFile(file, std::move(callbackContext));
    if(token && WriteGuestU32(guestOutAudioFile, token)) return noErr;

    auto entry = token ? TakeAudioFile(token) : nullptr;
    if(entry) {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(entry->file) {
            AudioFileClose(entry->file);
            entry->file = nullptr;
        }
    } else if(file) {
        AudioFileClose(file);
    }
    return kAudio_ParamError;
}

OSStatus DispatchAudioFileGetPropertyInfo(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    auto entry = FindAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    UInt32 dataSize = 0;
    UInt32 isWritable = 0;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFileGetPropertyInfo(entry->file, SlotU32(call, 1),
            &dataSize, &isWritable);
    }
    if(status != noErr) return status;
    if((SlotU32(call, 2) &&
            !WriteGuestU32(SlotU32(call, 2), dataSize)) ||
       (SlotU32(call, 3) &&
            !WriteGuestU32(SlotU32(call, 3), isWritable))) {
        return kAudio_ParamError;
    }
    return noErr;
}

OSStatus DispatchAudioFileGetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    auto entry = FindAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 requestedSize = 0;
    if(!ReadGuestU32(SlotU32(call, 2), requestedSize) ||
       requestedSize > kMaximumPropertyBytes ||
       (requestedSize && !SlotU32(call, 3))) {
        return kAudio_ParamError;
    }

    std::vector<uint8_t> bytes(requestedSize ? requestedSize : 1);
    UInt32 returnedSize = requestedSize;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFileGetProperty(entry->file, SlotU32(call, 1),
            &returnedSize, requestedSize ? bytes.data() : nullptr);
    }

    if(!WriteGuestU32(SlotU32(call, 2), returnedSize))
        return kAudio_ParamError;
    if(status == noErr && returnedSize) {
        if(returnedSize > requestedSize ||
           Dynarmic_mem_1write(SlotU32(call, 3), returnedSize,
               reinterpret_cast<char *>(bytes.data())) != 0) {
            return kAudio_ParamError;
        }
    }
    return status;
}

OSStatus DispatchAudioFileReadBytes(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 5)) return kAudio_ParamError;
    auto entry = FindAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 requestedBytes = 0;
    if(!ReadGuestU32(SlotU32(call, 3), requestedBytes) ||
       requestedBytes > kMaximumAudioBytes ||
       (requestedBytes && !SlotU32(call, 4))) {
        return kAudio_ParamError;
    }

    std::vector<uint8_t> bytes(requestedBytes ? requestedBytes : 1);
    UInt32 returnedBytes = requestedBytes;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFileReadBytes(entry->file,
            static_cast<Boolean>(SlotU32(call, 1)),
            static_cast<SInt64>(call.slots[2]), &returnedBytes,
            requestedBytes ? bytes.data() : nullptr);
    }

    if(!WriteGuestU32(SlotU32(call, 3), returnedBytes))
        return kAudio_ParamError;
    if(status == noErr && returnedBytes) {
        if(returnedBytes > requestedBytes ||
           Dynarmic_mem_1write(SlotU32(call, 4), returnedBytes,
               reinterpret_cast<char *>(bytes.data())) != 0) {
            return kAudio_ParamError;
        }
    }
    return status;
}

OSStatus AudioFilePacketSizeUpperBound(
        const std::shared_ptr<AudioFileEntry> &entry,
        UInt32 &packetSize) {
    UInt32 propertySize = sizeof(packetSize);
    OSStatus status = AudioFileGetProperty(entry->file,
        kAudioFilePropertyPacketSizeUpperBound, &propertySize, &packetSize);
    if(status == noErr && propertySize == sizeof(packetSize)) return noErr;

    packetSize = 0;
    propertySize = sizeof(packetSize);
    status = AudioFileGetProperty(entry->file,
        kAudioFilePropertyMaximumPacketSize, &propertySize, &packetSize);
    if(status == noErr && propertySize != sizeof(packetSize))
        return kAudio_ParamError;
    return status;
}

OSStatus DispatchAudioFileReadPackets(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 7) || !SlotU32(call, 2) ||
       !SlotU32(call, 5)) return kAudio_ParamError;
    auto entry = FindAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 requestedPackets = 0;
    if(!ReadGuestU32(SlotU32(call, 5), requestedPackets))
        return kAudio_ParamError;

    UInt32 packetSize = 0;
    bool returnsPacketDescriptions = false;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFilePacketSizeUpperBound(entry, packetSize);
        if(status == noErr && SlotU32(call, 3)) {
            AudioStreamBasicDescription format = {};
            UInt32 formatSize = sizeof(format);
            status = AudioFileGetProperty(entry->file,
                kAudioFilePropertyDataFormat, &formatSize, &format);
            if(status == noErr && formatSize != sizeof(format))
                status = kAudio_ParamError;
            returnsPacketDescriptions = status == noErr &&
                format.mBytesPerPacket == 0;
        }
    }
    if(status != noErr) return status;
    if(requestedPackets && packetSize == 0) return kAudio_ParamError;
    if(packetSize && requestedPackets > kMaximumAudioBytes / packetSize)
        return kAudio_ParamError;
    const size_t bufferCapacity =
        static_cast<size_t>(packetSize) * requestedPackets;
    if(bufferCapacity && !SlotU32(call, 6)) return kAudio_ParamError;

    std::vector<uint8_t> bytes(bufferCapacity ? bufferCapacity : 1);
    std::vector<AudioStreamPacketDescription> packetDescriptions;
    if(returnsPacketDescriptions) {
        if(requestedPackets >
            kMaximumAudioBytes / sizeof(AudioStreamPacketDescription)) {
            return kAudio_ParamError;
        }
        packetDescriptions.resize(requestedPackets);
    }

    UInt32 returnedBytes = 0;
    UInt32 returnedPackets = requestedPackets;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFileReadPackets(entry->file,
            static_cast<Boolean>(SlotU32(call, 1)), &returnedBytes,
            packetDescriptions.empty() ? nullptr : packetDescriptions.data(),
            static_cast<SInt64>(call.slots[4]), &returnedPackets,
            bufferCapacity ? bytes.data() : nullptr);
    }

    if(returnedBytes > bufferCapacity || returnedPackets > requestedPackets ||
       !WriteGuestU32(SlotU32(call, 2), returnedBytes) ||
       !WriteGuestU32(SlotU32(call, 5), returnedPackets)) {
        return kAudio_ParamError;
    }
    if(returnedBytes && Dynarmic_mem_1write(SlotU32(call, 6), returnedBytes,
            reinterpret_cast<char *>(bytes.data())) != 0) {
        return kAudio_ParamError;
    }
    if(!packetDescriptions.empty() && returnedPackets) {
        const size_t descriptorBytes = static_cast<size_t>(returnedPackets) *
            sizeof(GuestAudioStreamPacketDescription);
        if(Dynarmic_mem_1write(SlotU32(call, 3), descriptorBytes,
                reinterpret_cast<char *>(packetDescriptions.data())) != 0) {
            return kAudio_ParamError;
        }
    }
    return status;
}

OSStatus DispatchAudioFileReadPacketData(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 7) || !SlotU32(call, 2) ||
       !SlotU32(call, 5)) {
        return kAudio_ParamError;
    }
    auto entry = FindAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 requestedBytes = 0;
    u32 requestedPackets = 0;
    if(!ReadGuestU32(SlotU32(call, 2), requestedBytes) ||
       !ReadGuestU32(SlotU32(call, 5), requestedPackets) ||
       requestedBytes > kMaximumAudioBytes ||
       (requestedBytes && !SlotU32(call, 6)) ||
       (SlotU32(call, 3) && requestedPackets >
            kMaximumAudioBytes /
                sizeof(AudioStreamPacketDescription))) {
        return kAudio_ParamError;
    }

    std::vector<uint8_t> bytes(requestedBytes ? requestedBytes : 1);
    std::vector<AudioStreamPacketDescription> packetDescriptions;
    if(SlotU32(call, 3)) packetDescriptions.resize(requestedPackets);

    UInt32 returnedBytes = requestedBytes;
    UInt32 returnedPackets = requestedPackets;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFileReadPacketData(entry->file,
            static_cast<Boolean>(SlotU32(call, 1)), &returnedBytes,
            packetDescriptions.empty() ? nullptr : packetDescriptions.data(),
            static_cast<SInt64>(call.slots[4]), &returnedPackets,
            requestedBytes ? bytes.data() : nullptr);
    }

    if(returnedBytes > requestedBytes ||
       returnedPackets > requestedPackets ||
       !WriteGuestU32(SlotU32(call, 2), returnedBytes) ||
       !WriteGuestU32(SlotU32(call, 5), returnedPackets) ||
       (returnedBytes && !WriteGuestBytes(
            SlotU32(call, 6), returnedBytes, bytes.data()))) {
        return kAudio_ParamError;
    }
    if(!packetDescriptions.empty() && returnedPackets) {
        const size_t descriptorBytes =
            static_cast<size_t>(returnedPackets) *
                sizeof(GuestAudioStreamPacketDescription);
        if(!WriteGuestBytes(SlotU32(call, 3), descriptorBytes,
                packetDescriptions.data())) {
            return kAudio_ParamError;
        }
    }
    return status;
}

OSStatus DispatchAudioFileWriteBytes(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 5) || !SlotU32(call, 3))
        return kAudio_ParamError;
    auto entry = FindAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 requestedBytes = 0;
    if(!ReadGuestU32(SlotU32(call, 3), requestedBytes) ||
       requestedBytes > kMaximumAudioBytes ||
       (requestedBytes && !SlotU32(call, 4))) {
        return kAudio_ParamError;
    }
    std::vector<uint8_t> bytes(requestedBytes);
    if(requestedBytes && Dynarmic_mem_1read(SlotU32(call, 4),
            requestedBytes, reinterpret_cast<char *>(bytes.data())) != 0) {
        return kAudio_ParamError;
    }

    UInt32 writtenBytes = requestedBytes;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = AudioFileWriteBytes(entry->file,
            static_cast<Boolean>(SlotU32(call, 1)),
            static_cast<SInt64>(call.slots[2]), &writtenBytes,
            requestedBytes ? bytes.data() : nullptr);
    }
    if(writtenBytes > requestedBytes ||
       !WriteGuestU32(SlotU32(call, 3), writtenBytes)) {
        return kAudio_ParamError;
    }
    return status;
}

OSStatus DispatchExtAudioFileGetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    if(!IsRawExtAudioFileProperty(SlotU32(call, 1)))
        return kExtAudioFileError_InvalidProperty;
    auto entry = FindExtAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 requestedSize = 0;
    if(!ReadGuestU32(SlotU32(call, 2), requestedSize) ||
       requestedSize > kMaximumPropertyBytes ||
       (requestedSize && !SlotU32(call, 3))) {
        return kAudio_ParamError;
    }
    std::vector<uint8_t> bytes(requestedSize ? requestedSize : 1);
    UInt32 returnedSize = requestedSize;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = ExtAudioFileGetProperty(entry->file, SlotU32(call, 1),
            &returnedSize, requestedSize ? bytes.data() : nullptr);
    }
    if(!WriteGuestU32(SlotU32(call, 2), returnedSize))
        return kAudio_ParamError;
    if(status == noErr && returnedSize) {
        if(returnedSize > requestedSize ||
           Dynarmic_mem_1write(SlotU32(call, 3), returnedSize,
               reinterpret_cast<char *>(bytes.data())) != 0) {
            return kAudio_ParamError;
        }
    }
    return status;
}

OSStatus DispatchExtAudioFileSetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    if(!IsRawExtAudioFileProperty(SlotU32(call, 1)))
        return kExtAudioFileError_InvalidProperty;
    auto entry = FindExtAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;
    const u32 byteCount = SlotU32(call, 2);
    if(byteCount > kMaximumPropertyBytes ||
       (byteCount && !SlotU32(call, 3))) return kAudio_ParamError;
    std::vector<uint8_t> bytes(byteCount);
    if(byteCount && Dynarmic_mem_1read(SlotU32(call, 3), byteCount,
            reinterpret_cast<char *>(bytes.data())) != 0)
        return kAudio_ParamError;

    std::lock_guard<std::mutex> lock(entry->mutex);
    if(!entry->file) return kAudio_ParamError;
    return ExtAudioFileSetProperty(entry->file, SlotU32(call, 1),
        byteCount, byteCount ? bytes.data() : nullptr);
}

OSStatus DispatchExtAudioFileRead(const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 3)) return kAudio_ParamError;
    auto entry = FindExtAudioFile(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    u32 frameCount = 0;
    u32 bufferCount = 0;
    if(!ReadGuestU32(SlotU32(call, 1), frameCount) ||
       !ReadGuestU32(SlotU32(call, 2), bufferCount) ||
       bufferCount == 0 || bufferCount > kMaximumAudioBuffers) {
        return kAudio_ParamError;
    }

    std::vector<GuestAudioBuffer> guestBuffers(bufferCount);
    const size_t guestBytes = guestBuffers.size() * sizeof(GuestAudioBuffer);
    const uint64_t guestBuffersAddress =
        static_cast<uint64_t>(SlotU32(call, 2)) + sizeof(u32);
    if(guestBuffersAddress > UINT32_MAX ||
       guestBuffersAddress + guestBytes >
           static_cast<uint64_t>(UINT32_MAX) + 1 ||
       Dynarmic_mem_1read(static_cast<u32>(guestBuffersAddress), guestBytes,
            reinterpret_cast<char *>(guestBuffers.data())) != 0) {
        return kAudio_ParamError;
    }

    size_t totalAudioBytes = 0;
    std::vector<std::vector<uint8_t>> storage(bufferCount);
    const size_t hostListSize = offsetof(AudioBufferList, mBuffers) +
        static_cast<size_t>(bufferCount) * sizeof(AudioBuffer);
    auto hostListStorage = std::make_unique<uint8_t[]>(hostListSize);
    memset(hostListStorage.get(), 0, hostListSize);
    AudioBufferList *hostList =
        reinterpret_cast<AudioBufferList *>(hostListStorage.get());
    hostList->mNumberBuffers = bufferCount;
    for(u32 index = 0; index < bufferCount; ++index) {
        const GuestAudioBuffer &guest = guestBuffers[index];
        if(guest.byteSize > kMaximumAudioBytes - totalAudioBytes ||
           (guest.byteSize && (!guest.data ||
            static_cast<uint64_t>(guest.data) + guest.byteSize >
                static_cast<uint64_t>(UINT32_MAX) + 1)))
            return kAudio_ParamError;
        totalAudioBytes += guest.byteSize;
        storage[index].resize(guest.byteSize);
        hostList->mBuffers[index].mNumberChannels = guest.channels;
        hostList->mBuffers[index].mDataByteSize = guest.byteSize;
        hostList->mBuffers[index].mData = guest.byteSize
            ? storage[index].data() : nullptr;
    }

    UInt32 returnedFrames = frameCount;
    OSStatus status;
    {
        std::lock_guard<std::mutex> lock(entry->mutex);
        if(!entry->file) return kAudio_ParamError;
        status = ExtAudioFileRead(entry->file, &returnedFrames, hostList);
    }
    if(!WriteGuestU32(SlotU32(call, 1), returnedFrames))
        return kAudio_ParamError;
    for(u32 index = 0; index < bufferCount; ++index) {
        const u32 returnedBytes = hostList->mBuffers[index].mDataByteSize;
        if(returnedBytes > guestBuffers[index].byteSize)
            return kAudio_ParamError;
        const u32 guestBufferAddress = static_cast<u32>(
            guestBuffersAddress + index * sizeof(GuestAudioBuffer));
        if(!WriteGuestU32(guestBufferAddress + offsetof(GuestAudioBuffer, byteSize),
                          returnedBytes)) return kAudio_ParamError;
        if(status == noErr && returnedBytes &&
           Dynarmic_mem_1write(guestBuffers[index].data, returnedBytes,
               reinterpret_cast<char *>(storage[index].data())) != 0) {
            return kAudio_ParamError;
        }
    }
    return status;
}

bool IsRawAudioQueueProperty(AudioQueuePropertyID property) {
    switch(property) {
        case kAudioQueueProperty_IsRunning:
        case kAudioQueueProperty_MagicCookie:
        case kAudioQueueProperty_MaximumOutputPacketSize:
        case kAudioQueueProperty_StreamDescription:
        case kAudioQueueProperty_ChannelLayout:
        case kAudioQueueProperty_EnableLevelMetering:
        case kAudioQueueProperty_CurrentLevelMeter:
        case kAudioQueueProperty_CurrentLevelMeterDB:
            return true;
        default:
            return false;
    }
}

OSStatus DispatchAudioQueueNew(
        const LC32AudioToolboxCall &call,
        AudioQueueDirection direction) {
    if(!RequireSlots(call, 8) || !SlotU32(call, 0) ||
       !SlotU32(call, 1) || !SlotU32(call, 2) ||
       !SlotU32(call, 7) || !WriteGuestU32(SlotU32(call, 7), 0)) {
        return kAudio_ParamError;
    }

    AudioStreamBasicDescription format = {};
    if(!ReadGuestBytes(SlotU32(call, 0), sizeof(format), &format))
        return kAudio_ParamError;

    /*
     * Older iOS AudioQueue implementations ignored mReserved, and some old
     * clients (including this YouTube build) did not initialize it.  Modern
     * simulator AudioToolbox preserves the garbage value until RemoteIO is
     * started, where it fails with the private status -66628.  Reserved ASBD
     * fields are required to be zero at an API boundary.
     */
    format.mReserved = 0;

    auto entry = std::make_shared<AudioQueueEntry>();
    entry->token = AllocateAudioQueueToken();
    entry->direction = direction;
    entry->guestCallback = SlotU32(call, 1);
    entry->guestCallbackThunk = SlotU32(call, 2);
    entry->guestUserData = SlotU32(call, 3);
    if(!entry->token) return kAudio_MemFullError;

    AudioQueueRef queue = nullptr;
    OSStatus status = noErr;
    if(direction == AudioQueueDirection::Input) {
        status = AudioQueueNewInput(&format,
            AudioQueueInputCallbackBridge, entry.get(),
            SlotHostObject<CFRunLoopRef>(call, 4),
            SlotHostObject<CFStringRef>(call, 5), SlotU32(call, 6),
            &queue);
    } else {
        status = AudioQueueNewOutput(&format,
            AudioQueueOutputCallbackBridge, entry.get(),
            SlotHostObject<CFRunLoopRef>(call, 4),
            SlotHostObject<CFStringRef>(call, 5), SlotU32(call, 6),
            &queue);
    }
    if(status != noErr) return status;
    entry->queue = queue;

    const bool published = PublishAudioQueue(entry);
    if(!published || !WriteGuestU32(SlotU32(call, 7), entry->token)) {
        if(published) (void)TakeAudioQueue(entry->token);
        {
            std::lock_guard<std::mutex> lock(entry->stateMutex);
            entry->disposing = true;
            entry->disposed.store(true, std::memory_order_release);
        }
        const OSStatus disposeStatus = AudioQueueDispose(queue, true);
        {
            std::lock_guard<std::mutex> lock(entry->stateMutex);
            entry->queue = nullptr;
        }
        if(disposeStatus != noErr) QuarantineAudioQueue(entry);
        return kAudio_ParamError;
    }
    return noErr;
}

OSStatus DispatchAudioQueueNewInput(
        const LC32AudioToolboxCall &call) {
    return DispatchAudioQueueNew(call, AudioQueueDirection::Input);
}

OSStatus DispatchAudioQueueNewOutput(
        const LC32AudioToolboxCall &call) {
    return DispatchAudioQueueNew(call, AudioQueueDirection::Output);
}

OSStatus DispatchAudioQueueAllocateBuffer(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 7)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;
    AudioQueueRef queue = queueUse.queue();

    const u32 byteCapacity = SlotU32(call, 1);
    const u32 packetCapacity = SlotU32(call, 2);
    const u32 guestBuffer = SlotU32(call, 3);
    const u32 guestAudioData = SlotU32(call, 4);
    const u32 guestPacketDescriptions = SlotU32(call, 5);
    const u32 guestCallbackStorage = SlotU32(call, 6);
    if(byteCapacity > kMaximumAudioBytes ||
       packetCapacity > kMaximumAudioBytes /
            sizeof(AudioStreamPacketDescription) ||
       !guestBuffer || (byteCapacity && !guestAudioData) ||
       (packetCapacity && !guestPacketDescriptions) ||
       !guestCallbackStorage) {
        return kAudio_ParamError;
    }

    GuestAudioQueueBuffer mirror = {};
    if(!ReadGuestBytes(guestBuffer, sizeof(mirror), &mirror) ||
       mirror.audioDataBytesCapacity != byteCapacity ||
       mirror.audioData != guestAudioData ||
       mirror.audioDataByteSize != 0 ||
       mirror.packetDescriptionCapacity != packetCapacity ||
       mirror.packetDescriptions != guestPacketDescriptions ||
       mirror.packetDescriptionCount != 0) {
        return kAudioQueueErr_InvalidBuffer;
    }

    AudioQueueBufferRef nativeBuffer = nullptr;
    const OSStatus status = packetCapacity
        ? AudioQueueAllocateBufferWithPacketDescriptions(queue,
            byteCapacity, packetCapacity, &nativeBuffer)
        : AudioQueueAllocateBuffer(queue, byteCapacity, &nativeBuffer);
    if(status != noErr) return status;

    auto buffer = std::make_shared<AudioQueueBufferEntry>();
    buffer->nativeBuffer = nativeBuffer;
    buffer->guestBuffer = guestBuffer;
    buffer->guestAudioData = guestAudioData;
    buffer->audioDataCapacity = byteCapacity;
    buffer->guestPacketDescriptions = guestPacketDescriptions;
    buffer->packetDescriptionCapacity = packetCapacity;
    buffer->guestCallbackStorage = guestCallbackStorage;
    bool inserted = false;
    {
        std::lock_guard<std::mutex> lock(entry->buffersMutex);
        if(!entry->disposed.load(std::memory_order_acquire)) {
            const auto guestResult =
                entry->buffersByGuest.emplace(guestBuffer, buffer);
            if(guestResult.second) {
                const auto nativeResult =
                    entry->buffersByNative.emplace(nativeBuffer, buffer);
                if(nativeResult.second) {
                    inserted = true;
                } else {
                    entry->buffersByGuest.erase(guestResult.first);
                }
            }
        }
    }
    if(!inserted) {
        (void)AudioQueueFreeBuffer(queue, nativeBuffer);
        return kAudioQueueErr_InvalidBuffer;
    }
    return noErr;
}

OSStatus DispatchAudioQueueEnqueueBuffer(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    auto buffer = FindAudioQueueBuffer(entry, SlotU32(call, 1));
    if(!queueUse || !buffer) {
        fprintf(stderr,
            "LC32: AudioQueueEnqueueBuffer rejected unknown queue/buffer "
            "(queue=0x%x buffer=0x%x queue-found=%d buffer-found=%d)\n",
            SlotU32(call, 0), SlotU32(call, 1), entry != nullptr,
            buffer != nullptr);
        return kAudioQueueErr_InvalidBuffer;
    }
    AudioQueueRef queue = queueUse.queue();

    GuestAudioQueueBuffer mirror = {};
    if(!ReadGuestBytes(buffer->guestBuffer, sizeof(mirror), &mirror) ||
       mirror.audioDataBytesCapacity != buffer->audioDataCapacity ||
       mirror.audioData != buffer->guestAudioData ||
       mirror.audioDataByteSize > buffer->audioDataCapacity ||
       mirror.packetDescriptionCapacity !=
            buffer->packetDescriptionCapacity ||
       mirror.packetDescriptions != buffer->guestPacketDescriptions) {
        fprintf(stderr,
            "LC32: AudioQueueEnqueueBuffer rejected guest mirror "
            "0x%x (bytes-capacity=%u/%u data=0x%x/0x%x bytes=%u "
            "packet-capacity=%u/%u descriptions=0x%x/0x%x "
            "packet-count=%u)\n",
            buffer->guestBuffer,
            mirror.audioDataBytesCapacity, buffer->audioDataCapacity,
            mirror.audioData, buffer->guestAudioData,
            mirror.audioDataByteSize,
            mirror.packetDescriptionCapacity,
            buffer->packetDescriptionCapacity,
            mirror.packetDescriptions,
            buffer->guestPacketDescriptions,
            mirror.packetDescriptionCount);
        return kAudioQueueErr_InvalidBuffer;
    }

    if(entry->direction == AudioQueueDirection::Input) {
        if(SlotU32(call, 2) || SlotU32(call, 3))
            return kAudio_ParamError;
        /* Input queues treat enqueued buffers as empty writable capacity. The
         * guest mirror retains the previous capture until the next callback.
         */
        buffer->nativeBuffer->mAudioDataByteSize = 0;
        buffer->nativeBuffer->mPacketDescriptionCount = 0;
        return AudioQueueEnqueueBuffer(
            queue, buffer->nativeBuffer, 0, nullptr);
    }

    std::unique_lock<std::mutex> bufferLock(buffer->stateMutex);
    if(buffer->outputEnqueued) {
        return kAudioQueueErr_BufferInQueue;
    }
    buffer->outputEnqueued = true;

    const u32 packetCount = SlotU32(call, 2);
    const u32 guestPacketDescriptions = SlotU32(call, 3);
    const bool hasEmbeddedStorage =
        buffer->packetDescriptionCapacity != 0 &&
        buffer->guestPacketDescriptions != 0 &&
        buffer->nativeBuffer->mPacketDescriptions != nullptr;
    const bool externalReferencesEmbedded = hasEmbeddedStorage &&
        packetCount != 0 &&
        guestPacketDescriptions == buffer->guestPacketDescriptions;
    const bool useEmbeddedDescriptions = hasEmbeddedStorage &&
        (packetCount == 0 || externalReferencesEmbedded);
    const u32 embeddedPacketCount = useEmbeddedDescriptions
        ? (externalReferencesEmbedded
            ? packetCount : mirror.packetDescriptionCount)
        : 0;
    const u32 externalPacketCount = useEmbeddedDescriptions
        ? 0 : packetCount;
    if((packetCount && !guestPacketDescriptions) ||
       packetCount > kMaximumPropertyBytes /
            sizeof(AudioStreamPacketDescription) ||
       embeddedPacketCount > buffer->packetDescriptionCapacity) {
        buffer->outputEnqueued = false;
        return kAudio_ParamError;
    }

    std::unique_ptr<AudioStreamPacketDescription[]> packetDescriptions;
    if(externalPacketCount) {
        packetDescriptions.reset(new(std::nothrow)
            AudioStreamPacketDescription[externalPacketCount]);
        if(!packetDescriptions) {
            buffer->outputEnqueued = false;
            return kAudio_MemFullError;
        }
    }
    if((mirror.audioDataByteSize &&
        !ReadGuestBytes(buffer->guestAudioData,
            mirror.audioDataByteSize, buffer->nativeBuffer->mAudioData)) ||
       (externalPacketCount &&
        !ReadGuestBytes(guestPacketDescriptions,
            static_cast<size_t>(externalPacketCount) *
                sizeof(AudioStreamPacketDescription),
            packetDescriptions.get())) ||
       (embeddedPacketCount &&
        (!buffer->nativeBuffer->mPacketDescriptions ||
         !ReadGuestBytes(buffer->guestPacketDescriptions,
            static_cast<size_t>(embeddedPacketCount) *
                sizeof(AudioStreamPacketDescription),
            buffer->nativeBuffer->mPacketDescriptions)))) {
        buffer->outputEnqueued = false;
        return kAudio_ParamError;
    }

    buffer->nativeBuffer->mAudioDataByteSize = mirror.audioDataByteSize;
    buffer->nativeBuffer->mPacketDescriptionCount = embeddedPacketCount;
    const OSStatus status = AudioQueueEnqueueBuffer(queue,
        buffer->nativeBuffer, externalPacketCount,
        packetDescriptions.get());
    if(status != noErr) buffer->outputEnqueued = false;
    return status;
}

OSStatus DispatchAudioQueueFreeBuffer(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 2)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    auto buffer = FindAudioQueueBuffer(entry, SlotU32(call, 1));
    if(!queueUse || !buffer) return kAudioQueueErr_InvalidBuffer;
    AudioQueueRef queue = queueUse.queue();
    std::unique_lock<std::mutex> bufferLock(buffer->stateMutex);
    if(entry->direction == AudioQueueDirection::Output &&
       buffer->outputEnqueued) {
        return kAudioQueueErr_BufferInQueue;
    }

    const OSStatus status = AudioQueueFreeBuffer(
        queue, buffer->nativeBuffer);
    if(status != noErr) return status;
    std::lock_guard<std::mutex> lock(entry->buffersMutex);
    const auto guestIterator =
        entry->buffersByGuest.find(buffer->guestBuffer);
    if(guestIterator != entry->buffersByGuest.end() &&
       guestIterator->second == buffer) {
        entry->buffersByGuest.erase(guestIterator);
    }
    const auto nativeIterator =
        entry->buffersByNative.find(buffer->nativeBuffer);
    if(nativeIterator != entry->buffersByNative.end() &&
       nativeIterator->second == buffer) {
        entry->buffersByNative.erase(nativeIterator);
    }
    return noErr;
}

OSStatus DispatchAudioQueueGetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4) || !SlotU32(call, 3))
        return kAudio_ParamError;
    const AudioQueuePropertyID property = SlotU32(call, 1);
    if(!IsRawAudioQueueProperty(property))
        return kAudioQueueErr_InvalidProperty;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;
    AudioQueueRef queue = queueUse.queue();

    u32 requestedSize = 0;
    if(!ReadGuestU32(SlotU32(call, 3), requestedSize) ||
       requestedSize > kMaximumPropertyBytes ||
       (requestedSize && !SlotU32(call, 2))) {
        return kAudio_ParamError;
    }
    std::vector<uint8_t> bytes(requestedSize ? requestedSize : 1);
    UInt32 returnedSize = requestedSize;
    const OSStatus status = AudioQueueGetProperty(queue, property,
        requestedSize ? bytes.data() : nullptr, &returnedSize);
    if(!WriteGuestU32(SlotU32(call, 3), returnedSize))
        return kAudio_ParamError;
    if(status == noErr && returnedSize &&
       (returnedSize > requestedSize ||
        !WriteGuestBytes(SlotU32(call, 2), returnedSize, bytes.data()))) {
        return kAudio_ParamError;
    }
    return status;
}

OSStatus DispatchAudioQueueSetProperty(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4)) return kAudio_ParamError;
    const AudioQueuePropertyID property = SlotU32(call, 1);
    if(!IsRawAudioQueueProperty(property))
        return kAudioQueueErr_InvalidProperty;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;
    AudioQueueRef queue = queueUse.queue();

    const u32 byteCount = SlotU32(call, 3);
    if(byteCount > kMaximumPropertyBytes ||
       (byteCount && !SlotU32(call, 2))) return kAudio_ParamError;
    std::vector<uint8_t> bytes(byteCount);
    if(byteCount && !ReadGuestBytes(
            SlotU32(call, 2), byteCount, bytes.data())) {
        return kAudio_ParamError;
    }
    return AudioQueueSetProperty(queue, property, byteCount
        ? bytes.data() : nullptr, byteCount);
}

OSStatus DispatchAudioQueueSetParameter(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 3)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    static_assert(sizeof(AudioQueueParameterValue) == sizeof(u32));
    const u32 valueBits = SlotU32(call, 2);
    AudioQueueParameterValue value = 0;
    memcpy(&value, &valueBits, sizeof(value));
    return AudioQueueSetParameter(
        queueUse.queue(), SlotU32(call, 1), value);
}

OSStatus DispatchAudioQueueCallbackScope(
        const LC32AudioToolboxCall &call, bool entering) {
    if(!RequireSlots(call, 1) || !SlotU32(call, 0))
        return kAudio_ParamError;
    const u32 token = SlotU32(call, 0);
    if(entering) {
        ++audioQueueGuestCallbacksOnCurrentThread[token];
        return noErr;
    }

    const auto iterator =
        audioQueueGuestCallbacksOnCurrentThread.find(token);
    if(iterator == audioQueueGuestCallbacksOnCurrentThread.end() ||
       iterator->second == 0) {
        return kAudio_ParamError;
    }
    if(iterator->second > 1) {
        --iterator->second;
    } else {
        audioQueueGuestCallbacksOnCurrentThread.erase(iterator);
    }
    return noErr;
}

OSStatus DispatchAudioQueueAddPropertyListener(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 5) || !SlotU32(call, 2) ||
       !SlotU32(call, 3)) {
        return kAudio_ParamError;
    }
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    auto listener = std::make_shared<AudioQueuePropertyListenerEntry>();
    listener->queueEntry = entry;
    listener->property = SlotU32(call, 1);
    listener->guestCallback = SlotU32(call, 2);
    listener->guestCallbackThunk = SlotU32(call, 3);
    listener->guestUserData = SlotU32(call, 4);
    if(!PublishAudioQueuePropertyListener(listener))
        return kAudio_MemFullError;

    const OSStatus status = AudioQueueAddPropertyListener(
        queueUse.queue(), listener->property,
        AudioQueuePropertyListenerBridge,
        reinterpret_cast<void *>(listener->nativeCookie));
    if(status == noErr) {
        std::lock_guard<std::mutex> lock(entry->listenersMutex);
        entry->listeners.push_back(listener);
    } else {
        listener->enabled.store(false, std::memory_order_release);
        UnpublishAudioQueuePropertyListener(listener);
    }
    return status;
}

OSStatus DispatchAudioQueueRemovePropertyListener(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4) || !SlotU32(call, 2))
        return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    std::shared_ptr<AudioQueuePropertyListenerEntry> listener;
    {
        std::lock_guard<std::mutex> lock(entry->listenersMutex);
        for(const auto &candidate : entry->listeners) {
            if(!candidate ||
               !candidate->enabled.load(std::memory_order_acquire) ||
               candidate->property != SlotU32(call, 1) ||
               candidate->guestCallback != SlotU32(call, 2) ||
               candidate->guestUserData != SlotU32(call, 3)) {
                continue;
            }
            bool expected = false;
            if(!candidate->removing.compare_exchange_strong(expected, true,
                    std::memory_order_acq_rel,
                    std::memory_order_acquire)) {
                return kAudio_ParamError;
            }
            listener = candidate;
            break;
        }
    }
    if(!listener) return kAudio_ParamError;

    const OSStatus status = AudioQueueRemovePropertyListener(
        queueUse.queue(), listener->property,
        AudioQueuePropertyListenerBridge,
        reinterpret_cast<void *>(listener->nativeCookie));
    if(status != noErr) {
        listener->removing.store(false, std::memory_order_release);
        return status;
    }

    listener->enabled.store(false, std::memory_order_release);
    UnpublishAudioQueuePropertyListener(listener);
    {
        std::lock_guard<std::mutex> lock(entry->listenersMutex);
        for(auto iterator = entry->listeners.begin();
                iterator != entry->listeners.end(); ++iterator) {
            if(*iterator == listener) {
                entry->listeners.erase(iterator);
                break;
            }
        }
    }
    return noErr;
}

OSStatus DispatchAudioQueuePrime(const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 3)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    UInt32 preparedFrames = 0;
    const u32 guestPreparedFrames = SlotU32(call, 2);
    if(guestPreparedFrames &&
       !WriteGuestU32(guestPreparedFrames, preparedFrames)) {
        return kAudio_ParamError;
    }
    const OSStatus status = AudioQueuePrime(queueUse.queue(),
        SlotU32(call, 1), guestPreparedFrames ? &preparedFrames : nullptr);
    if(guestPreparedFrames &&
       !WriteGuestU32(guestPreparedFrames, preparedFrames)) {
        return kAudio_ParamError;
    }
    return status;
}

OSStatus DispatchAudioQueueDeviceGetCurrentTime(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 2) || !SlotU32(call, 1))
        return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;
    AudioQueueRef queue = queueUse.queue();
    AudioTimeStamp timeStamp = {};
    const OSStatus status =
        AudioQueueDeviceGetCurrentTime(queue, &timeStamp);
    if(status == noErr && !WriteGuestBytes(
            SlotU32(call, 1), sizeof(timeStamp), &timeStamp)) {
        return kAudio_ParamError;
    }
    return status;
}

OSStatus DispatchAudioQueueCreateTimeline(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 2) || !SlotU32(call, 1) ||
       !WriteGuestU32(SlotU32(call, 1), 0)) {
        return kAudio_ParamError;
    }
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    AudioQueueTimelineRef timeline = nullptr;
    const OSStatus status =
        AudioQueueCreateTimeline(queueUse.queue(), &timeline);
    if(status != noErr) return status;
    if(!timeline) return kAudio_ParamError;

    u32 token = 0;
    {
        std::lock_guard<std::mutex> lock(entry->timelinesMutex);
        for(size_t attempt = 0; attempt < UINT32_MAX; ++attempt) {
            const u32 candidate = entry->nextTimelineToken++;
            if(!candidate) continue;
            if(entry->timelines.emplace(candidate, timeline).second) {
                token = candidate;
                break;
            }
        }
    }
    if(!token || !WriteGuestU32(SlotU32(call, 1), token)) {
        if(token) {
            std::lock_guard<std::mutex> lock(entry->timelinesMutex);
            entry->timelines.erase(token);
        }
        (void)AudioQueueDisposeTimeline(queueUse.queue(), timeline);
        return token ? kAudio_ParamError : kAudio_MemFullError;
    }
    return noErr;
}

OSStatus DispatchAudioQueueDisposeTimeline(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 2) || !SlotU32(call, 1))
        return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    std::lock_guard<std::mutex> lock(entry->timelinesMutex);
    const auto iterator = entry->timelines.find(SlotU32(call, 1));
    if(iterator == entry->timelines.end()) return kAudio_ParamError;
    const OSStatus status = AudioQueueDisposeTimeline(
        queueUse.queue(), iterator->second);
    if(status == noErr) entry->timelines.erase(iterator);
    return status;
}

OSStatus DispatchAudioQueueGetCurrentTime(
        const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4) ||
       (!SlotU32(call, 2) && !SlotU32(call, 3)) ||
       (!SlotU32(call, 1) && SlotU32(call, 3))) {
        return kAudio_ParamError;
    }
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;

    AudioTimeStamp timeStamp = {};
    Boolean discontinuity = false;
    OSStatus status = noErr;
    if(SlotU32(call, 1)) {
        std::lock_guard<std::mutex> lock(entry->timelinesMutex);
        const auto iterator = entry->timelines.find(SlotU32(call, 1));
        if(iterator == entry->timelines.end()) return kAudio_ParamError;
        status = AudioQueueGetCurrentTime(queueUse.queue(),
            iterator->second,
            SlotU32(call, 2) ? &timeStamp : nullptr,
            SlotU32(call, 3) ? &discontinuity : nullptr);
    } else {
        status = AudioQueueGetCurrentTime(queueUse.queue(), nullptr,
            SlotU32(call, 2) ? &timeStamp : nullptr, nullptr);
    }
    if(status != noErr) return status;
    if((SlotU32(call, 2) && !WriteGuestBytes(
            SlotU32(call, 2), sizeof(timeStamp), &timeStamp)) ||
       (SlotU32(call, 3) && !WriteGuestBytes(
            SlotU32(call, 3), sizeof(discontinuity), &discontinuity))) {
        return kAudio_ParamError;
    }
    return noErr;
}

OSStatus DispatchAudioQueueStart(const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 2)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;
    AudioQueueRef queue = queueUse.queue();
    AudioTimeStamp timeStamp = {};
    const AudioTimeStamp *startTime = nullptr;
    if(SlotU32(call, 1)) {
        if(!ReadGuestBytes(SlotU32(call, 1), sizeof(timeStamp), &timeStamp))
            return kAudio_ParamError;
        startTime = &timeStamp;
    }
    /*
     * Some pre-AVAudioSession clients relied on the old input AudioQueue path
     * to reactivate a session after configuring its legacy category.  Current
     * simulator AudioToolbox instead returns the private status -66628 while
     * the session remains inactive.  Starting an input queue is itself an
     * explicit request to record, so restore the legacy behavior immediately
     * before asking the native queue to start.
     */
    if(entry->direction == AudioQueueDirection::Input) {
        const OSStatus initializationStatus =
            EnsureNativeAudioSessionInitialized();
        if(initializationStatus != noErr) return initializationStatus;
        const OSStatus activationStatus = SetNativeAudioSessionActive(YES);
        if(activationStatus != noErr) {
            fprintf(stderr,
                "LC32: could not activate audio session before input "
                "AudioQueueStart: status=%d\n",
                static_cast<int>(activationStatus));
            return activationStatus;
        }
    }

    const OSStatus status = AudioQueueStart(queue, startTime);
    if(status != noErr) {
        OSStatus converterError = noErr;
        UInt32 converterErrorSize = sizeof(converterError);
        const OSStatus converterPropertyStatus = AudioQueueGetProperty(
            queue, kAudioQueueProperty_ConverterError,
            &converterError, &converterErrorSize);
        fprintf(stderr,
            "LC32: AudioQueueStart failed: status=%d "
            "converter-property=%d converter-error=%d\n",
            static_cast<int>(status),
            static_cast<int>(converterPropertyStatus),
            static_cast<int>(converterError));
    }
    return status;
}

OSStatus DispatchAudioQueueStop(const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 2)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;
    const Boolean immediate = static_cast<Boolean>(SlotU32(call, 1));
    {
        std::lock_guard<std::mutex> lock(entry->stateMutex);
        if(entry->disposed.load(std::memory_order_relaxed) ||
           entry->disposing || !entry->queue) return kAudio_ParamError;
        if(entry->activeCallbacks &&
           AudioQueueGuestCallbackIsOnCurrentThread(SlotU32(call, 0))) {
            ScheduleDeferredAudioQueueStop(entry, immediate);
            return noErr;
        }
    }
    AudioQueueUse queueUse(entry);
    if(!queueUse) return kAudio_ParamError;
    const OSStatus status = AudioQueueStop(queueUse.queue(), immediate);
    if(status == noErr && immediate)
        MarkOutputAudioQueueBuffersAvailable(entry);
    return status;
}

OSStatus DispatchAudioQueuePause(const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 1)) return kAudio_ParamError;
    auto entry = FindAudioQueue(SlotU32(call, 0));
    AudioQueueUse queueUse(entry);
    return queueUse ? AudioQueuePause(queueUse.queue()) : kAudio_ParamError;
}

OSStatus DispatchAudioQueueDispose(const LC32AudioToolboxCall &call) {
    if(!RequireSlots(call, 4) || !SlotU32(call, 2) ||
       !SlotU32(call, 3) ||
       !WriteGuestU32(SlotU32(call, 2),
            LC32AudioQueueDisposeTerminalNone)) {
        return kAudio_ParamError;
    }
    auto entry = TakeAudioQueue(SlotU32(call, 0));
    if(!entry) return kAudio_ParamError;

    const Boolean immediate = static_cast<Boolean>(SlotU32(call, 1));
    AudioQueueRef queue = nullptr;
    bool deferred = false;
    {
        std::unique_lock<std::mutex> lock(entry->stateMutex);
        if(entry->disposing ||
           entry->disposed.load(std::memory_order_relaxed) ||
           !entry->queue) {
            (void)WriteGuestU32(SlotU32(call, 2),
                LC32AudioQueueDisposeTerminalQuarantineMirrors);
            lock.unlock();
            QuarantineAudioQueue(entry);
            return kAudio_ParamError;
        }
        deferred = entry->activeCallbacks != 0 &&
            AudioQueueGuestCallbackIsOnCurrentThread(SlotU32(call, 0));
        const u32 terminal = deferred
            ? LC32AudioQueueDisposeTerminalDeferredCleanup
            : LC32AudioQueueDisposeTerminalReleaseMirrors;
        if(!WriteGuestU32(SlotU32(call, 2), terminal)) {
            lock.unlock();
            if(!PublishAudioQueue(entry)) QuarantineAudioQueue(entry);
            return kAudio_ParamError;
        }
        entry->disposing = true;
        entry->disposed.store(true, std::memory_order_release);
        if(!deferred) {
            entry->stateCondition.wait(lock, [&] {
                return entry->activeUsers == 0 &&
                    entry->activeCallbacks == 0;
            });
        }
        queue = entry->queue;
    }

    if(deferred) {
        ClearAudioQueueBuffers(entry);
        ScheduleDeferredAudioQueueDispose(
            entry, immediate, SlotU32(call, 3));
        return noErr;
    }

    ClearAudioQueuePropertyListeners(entry);
    const OSStatus status = queue
        ? AudioQueueDispose(queue, immediate)
        : kAudio_ParamError;
    ClearAudioQueueTimelines(entry);
    {
        std::lock_guard<std::mutex> lock(entry->stateMutex);
        entry->queue = nullptr;
    }
    ClearAudioQueueBuffers(entry);
    if(status != noErr) QuarantineAudioQueue(entry);
    return status;
}

} // namespace

extern "C" u32 LC32_AudioToolbox_Dispatch(u32 opcode, u32 guestCall, u32) {
    LC32AudioToolboxCall call;
    if(!ReadAudioToolboxCall(guestCall, call))
        return static_cast<u32>(kAudio_ParamError);

    switch(static_cast<LC32AudioToolboxOpcode>(opcode)) {
        case LC32AudioToolboxOpExtAudioFileOpenURL: {
            if(!RequireSlots(call, 2) || !SlotU32(call, 1))
                return static_cast<u32>(kAudio_ParamError);
            ExtAudioFileRef file = nullptr;
            const OSStatus status = ExtAudioFileOpenURL(
                SlotHostObject<CFURLRef>(call, 0), &file);
            if(status != noErr) return static_cast<u32>(status);
            const u32 token = InsertExtAudioFile(file);
            if(!token || !WriteGuestU32(SlotU32(call, 1), token)) {
                auto entry = token ? TakeExtAudioFile(token) : nullptr;
                if(entry) {
                    std::lock_guard<std::mutex> lock(entry->mutex);
                    if(entry->file) {
                        ExtAudioFileDispose(entry->file);
                        entry->file = nullptr;
                    }
                } else {
                    ExtAudioFileDispose(file);
                }
                return static_cast<u32>(kAudio_ParamError);
            }
            return static_cast<u32>(noErr);
        }
        case LC32AudioToolboxOpExtAudioFileDispose: {
            if(!RequireSlots(call, 1))
                return static_cast<u32>(kAudio_ParamError);
            auto entry = TakeExtAudioFile(SlotU32(call, 0));
            if(!entry) return static_cast<u32>(kAudio_ParamError);
            std::lock_guard<std::mutex> lock(entry->mutex);
            if(!entry->file) return static_cast<u32>(kAudio_ParamError);
            const OSStatus status = ExtAudioFileDispose(entry->file);
            entry->file = nullptr;
            return static_cast<u32>(status);
        }
        case LC32AudioToolboxOpExtAudioFileGetProperty:
            return static_cast<u32>(DispatchExtAudioFileGetProperty(call));
        case LC32AudioToolboxOpExtAudioFileSetProperty:
            return static_cast<u32>(DispatchExtAudioFileSetProperty(call));
        case LC32AudioToolboxOpExtAudioFileRead:
            return static_cast<u32>(DispatchExtAudioFileRead(call));
        case LC32AudioToolboxOpExtAudioFileSeek: {
            if(!RequireSlots(call, 2))
                return static_cast<u32>(kAudio_ParamError);
            auto entry = FindExtAudioFile(SlotU32(call, 0));
            if(!entry) return static_cast<u32>(kAudio_ParamError);
            std::lock_guard<std::mutex> lock(entry->mutex);
            if(!entry->file)
                return static_cast<u32>(kAudio_ParamError);
            return static_cast<u32>(ExtAudioFileSeek(entry->file,
                static_cast<SInt64>(call.slots[1])));
        }
        case LC32AudioToolboxOpAudioSessionGetProperty:
            return static_cast<u32>(
                DispatchAudioSessionGetProperty(call));
        case LC32AudioToolboxOpAudioSessionSetActive:
            return static_cast<u32>(
                DispatchAudioSessionSetActive(call));
        case LC32AudioToolboxOpAudioSessionSetProperty:
            return static_cast<u32>(
                DispatchAudioSessionSetProperty(call));
        case LC32AudioToolboxOpAudioFileOpenURL: {
            if(!RequireSlots(call, 4) || !SlotU32(call, 3))
                return static_cast<u32>(kAudio_ParamError);
            AudioFileID file = nullptr;
            const OSStatus status = AudioFileOpenURL(
                SlotHostObject<CFURLRef>(call, 0),
                static_cast<AudioFilePermissions>(SlotU32(call, 1)),
                SlotU32(call, 2), &file);
            if(status != noErr) return static_cast<u32>(status);
            return static_cast<u32>(
                PublishAudioFile(file, SlotU32(call, 3)));
        }
        case LC32AudioToolboxOpAudioFileOpenWithCallbacks: {
            if(!RequireSlots(call, 7) || !SlotU32(call, 1) ||
               !SlotU32(call, 3) || !SlotU32(call, 6) ||
               !WriteGuestU32(SlotU32(call, 6), 0)) {
                return static_cast<u32>(kAudio_ParamError);
            }
            auto context = std::make_unique<AudioFileCallbackContext>();
            context->guestClientData = SlotU32(call, 0);
            context->guestReadFunction = SlotU32(call, 1);
            context->guestWriteFunction = SlotU32(call, 2);
            context->guestGetSizeFunction = SlotU32(call, 3);
            context->guestSetSizeFunction = SlotU32(call, 4);

            AudioFileID file = nullptr;
            const OSStatus status = AudioFileOpenWithCallbacks(
                context.get(), AudioFileReadCallbackBridge,
                context->guestWriteFunction
                    ? AudioFileWriteCallbackBridge : nullptr,
                AudioFileGetSizeCallbackBridge,
                context->guestSetSizeFunction
                    ? AudioFileSetSizeCallbackBridge : nullptr,
                SlotU32(call, 5), &file);
            if(status != noErr) return static_cast<u32>(status);
            return static_cast<u32>(PublishAudioFile(
                file, SlotU32(call, 6), std::move(context)));
        }
        case LC32AudioToolboxOpAudioFileGetProperty:
            return static_cast<u32>(DispatchAudioFileGetProperty(call));
        case LC32AudioToolboxOpAudioFileReadBytes:
            return static_cast<u32>(DispatchAudioFileReadBytes(call));
        case LC32AudioToolboxOpAudioFileClose: {
            if(!RequireSlots(call, 1))
                return static_cast<u32>(kAudio_ParamError);
            auto entry = TakeAudioFile(SlotU32(call, 0));
            if(!entry) return static_cast<u32>(kAudio_ParamError);
            std::lock_guard<std::mutex> lock(entry->mutex);
            if(!entry->file) return static_cast<u32>(kAudio_ParamError);
            const OSStatus status = AudioFileClose(entry->file);
            entry->file = nullptr;
            return static_cast<u32>(status);
        }
        case LC32AudioToolboxOpAudioFileCreateWithURL: {
            if(!RequireSlots(call, 5) || !SlotHostObject<CFURLRef>(call, 0) ||
               !SlotU32(call, 2) ||
               !SlotU32(call, 4)) {
                return static_cast<u32>(kAudio_ParamError);
            }
            AudioStreamBasicDescription format = {};
            if(Dynarmic_mem_1read(SlotU32(call, 2), sizeof(format),
                    reinterpret_cast<char *>(&format)) != 0) {
                return static_cast<u32>(kAudio_ParamError);
            }
            AudioFileID file = nullptr;
            const OSStatus status = AudioFileCreateWithURL(
                SlotHostObject<CFURLRef>(call, 0), SlotU32(call, 1),
                &format, SlotU32(call, 3), &file);
            if(status != noErr) return static_cast<u32>(status);
            return static_cast<u32>(
                PublishAudioFile(file, SlotU32(call, 4)));
        }
        case LC32AudioToolboxOpAudioFileGetPropertyInfo:
            return static_cast<u32>(
                DispatchAudioFileGetPropertyInfo(call));
        case LC32AudioToolboxOpAudioFileReadPackets:
            return static_cast<u32>(
                DispatchAudioFileReadPackets(call));
        case LC32AudioToolboxOpAudioFileReadPacketData:
            return static_cast<u32>(
                DispatchAudioFileReadPacketData(call));
        case LC32AudioToolboxOpAudioFileWriteBytes:
            return static_cast<u32>(
                DispatchAudioFileWriteBytes(call));
        case LC32AudioToolboxOpAudioQueueNewInput:
            return static_cast<u32>(DispatchAudioQueueNewInput(call));
        case LC32AudioToolboxOpAudioQueueNewOutput:
            return static_cast<u32>(DispatchAudioQueueNewOutput(call));
        case LC32AudioToolboxOpAudioQueueAllocateBuffer:
            return static_cast<u32>(
                DispatchAudioQueueAllocateBuffer(call));
        case LC32AudioToolboxOpAudioQueueEnqueueBuffer:
            return static_cast<u32>(
                DispatchAudioQueueEnqueueBuffer(call));
        case LC32AudioToolboxOpAudioQueueFreeBuffer:
            return static_cast<u32>(DispatchAudioQueueFreeBuffer(call));
        case LC32AudioToolboxOpAudioQueueGetProperty:
            return static_cast<u32>(DispatchAudioQueueGetProperty(call));
        case LC32AudioToolboxOpAudioQueueSetProperty:
            return static_cast<u32>(DispatchAudioQueueSetProperty(call));
        case LC32AudioToolboxOpAudioQueueSetParameter:
            return static_cast<u32>(
                DispatchAudioQueueSetParameter(call));
        case LC32AudioToolboxOpAudioQueueAddPropertyListener:
            return static_cast<u32>(
                DispatchAudioQueueAddPropertyListener(call));
        case LC32AudioToolboxOpAudioQueueRemovePropertyListener:
            return static_cast<u32>(
                DispatchAudioQueueRemovePropertyListener(call));
        case LC32AudioToolboxOpAudioQueuePrime:
            return static_cast<u32>(DispatchAudioQueuePrime(call));
        case LC32AudioToolboxOpAudioQueueCallbackEnter:
            return static_cast<u32>(
                DispatchAudioQueueCallbackScope(call, true));
        case LC32AudioToolboxOpAudioQueueCallbackLeave:
            return static_cast<u32>(
                DispatchAudioQueueCallbackScope(call, false));
        case LC32AudioToolboxOpAudioQueueDeviceGetCurrentTime:
            return static_cast<u32>(
                DispatchAudioQueueDeviceGetCurrentTime(call));
        case LC32AudioToolboxOpAudioQueueCreateTimeline:
            return static_cast<u32>(
                DispatchAudioQueueCreateTimeline(call));
        case LC32AudioToolboxOpAudioQueueDisposeTimeline:
            return static_cast<u32>(
                DispatchAudioQueueDisposeTimeline(call));
        case LC32AudioToolboxOpAudioQueueGetCurrentTime:
            return static_cast<u32>(
                DispatchAudioQueueGetCurrentTime(call));
        case LC32AudioToolboxOpAudioQueueStart:
            return static_cast<u32>(DispatchAudioQueueStart(call));
        case LC32AudioToolboxOpAudioQueueStop:
            return static_cast<u32>(DispatchAudioQueueStop(call));
        case LC32AudioToolboxOpAudioQueuePause:
            return static_cast<u32>(DispatchAudioQueuePause(call));
        case LC32AudioToolboxOpAudioQueueDispose:
            return static_cast<u32>(DispatchAudioQueueDispose(call));
        case LC32AudioToolboxOpRemoteIOOutputStart:
            return static_cast<u32>(DispatchRemoteIOOutputStart(call));
        case LC32AudioToolboxOpRemoteIOOutputSubmit:
            return static_cast<u32>(DispatchRemoteIOOutputSubmit(call));
        case LC32AudioToolboxOpRemoteIOOutputStop:
            return static_cast<u32>(DispatchRemoteIOOutputStop(call));
    }
    return static_cast<u32>(kAudio_ParamError);
}
