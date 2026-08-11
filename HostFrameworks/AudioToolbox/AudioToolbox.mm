@import AudioToolbox;
@import Foundation;

#include "../../bridge.h"
#include "../../GuestFrameworks/AudioToolbox/LC32AudioToolboxBridge.h"

#include <objc/message.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

constexpr size_t kMaximumPropertyBytes = 16u * 1024u * 1024u;
constexpr size_t kMaximumAudioBytes = 256u * 1024u * 1024u;
constexpr u32 kMaximumAudioBuffers = 64;

struct ExtAudioFileEntry {
    ExtAudioFileRef file = nullptr;
    std::mutex mutex;
};

struct GuestAudioBuffer {
    u32 channels;
    u32 byteSize;
    u32 data;
};

static_assert(sizeof(GuestAudioBuffer) == 12);
static_assert(offsetof(GuestAudioBuffer, channels) == 0);
static_assert(offsetof(GuestAudioBuffer, byteSize) == 4);
static_assert(offsetof(GuestAudioBuffer, data) == 8);
static_assert(sizeof(AudioStreamBasicDescription) == 40);

std::mutex extAudioFilesMutex;
std::unordered_map<u32, std::shared_ptr<ExtAudioFileEntry>> extAudioFiles;
std::atomic<u32> nextExtAudioFileToken{1};

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
    }
    return static_cast<u32>(kAudio_ParamError);
}
