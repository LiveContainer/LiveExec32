@import Darwin;
@import OpenAL;

#include "bridge.h"
#include "../../OpenALBridge/LC32OpenALProtocol.h"

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

namespace {

constexpr size_t kMaxGuestTransfer = 256u * 1024u * 1024u;
constexpr size_t kMaxGuestString = 64u * 1024u;
constexpr size_t kMaxContextAttributeWords = 257u;
constexpr uint32_t kHandleIndexBits = 20u;
constexpr uint32_t kHandleIndexMask = (1u << kHandleIndexBits) - 1u;
constexpr uint32_t kHandleGenerationMask =
    (1u << (32u - kHandleIndexBits)) - 1u;

enum class HandleKind : uint8_t {
    Device,
    Context,
};

struct HandleEntry {
    void *pointer = nullptr;
    HandleKind kind = HandleKind::Device;
    uint32_t generation = 1;
    ALenum captureFormat = AL_NONE;
};

std::mutex gHandleMutex;
std::vector<HandleEntry> gHandles;
std::unordered_map<void *, uint32_t> gDeviceTokens;
std::unordered_map<void *, uint32_t> gContextTokens;
std::atomic<uint32_t> gSilentCurrentContextToken{0};

static bool UseSilentSimulatorContext() {
    // Permit testing native Simulator audio after Apple fixes the RemoteIO
    // failure, and permit forcing the crash-safe path on other host setups.
    if (const char *overrideValue =
            getenv("LC32_OPENAL_SILENT_CONTEXT")) {
        return overrideValue[0] != '\0' &&
               strcmp(overrideValue, "0") != 0;
    }
#if TARGET_OS_SIMULATOR
    return true;
#else
    // LiveExec32 is built as an iPhoneOS binary and then converted to a dylib
    // for LiveContainer, so TARGET_OS_SIMULATOR remains false in that path.
    // CoreSimulator supplies these variables to every launched application.
    static const bool isSimulator =
        getenv("SIMULATOR_UDID") != nullptr ||
        getenv("SIMULATOR_DEVICE_NAME") != nullptr;
    return isSimulator;
#endif
}

static std::unordered_map<void *, uint32_t> &ReverseHandles(HandleKind kind) {
    return kind == HandleKind::Device ? gDeviceTokens : gContextTokens;
}

static uint32_t MakeHandleToken(size_t index, uint32_t generation) {
    if (index + 1u > kHandleIndexMask) return 0;
    return ((generation & kHandleGenerationMask) << kHandleIndexBits) |
           static_cast<uint32_t>(index + 1u);
}

static bool DecodeHandleToken(uint32_t token, size_t *index,
                              uint32_t *generation) {
    const uint32_t encodedIndex = token & kHandleIndexMask;
    if (encodedIndex == 0) return false;
    *index = encodedIndex - 1u;
    *generation = token >> kHandleIndexBits;
    return *generation != 0;
}

static uint32_t RegisterHandle(void *pointer, HandleKind kind,
                               ALenum captureFormat = AL_NONE) {
    if (pointer == nullptr) return 0;
    std::lock_guard<std::mutex> lock(gHandleMutex);
    auto &reverse = ReverseHandles(kind);
    auto existing = reverse.find(pointer);
    if (existing != reverse.end()) {
        size_t index = 0;
        uint32_t generation = 0;
        if (DecodeHandleToken(existing->second, &index, &generation) &&
            index < gHandles.size()) {
            if (captureFormat != AL_NONE) {
                gHandles[index].captureFormat = captureFormat;
            }
            return existing->second;
        }
        reverse.erase(existing);
    }

    size_t index = 0;
    for (; index < gHandles.size(); index++) {
        if (gHandles[index].pointer == nullptr) break;
    }
    if (index == gHandles.size()) {
        if (index + 1u > kHandleIndexMask) return 0;
        gHandles.emplace_back();
    }

    HandleEntry &entry = gHandles[index];
    if (entry.generation == 0 ||
        entry.generation > kHandleGenerationMask) {
        entry.generation = 1;
    }
    entry.pointer = pointer;
    entry.kind = kind;
    entry.captureFormat = captureFormat;
    const uint32_t token = MakeHandleToken(index, entry.generation);
    reverse[pointer] = token;
    return token;
}

static bool LookupHandle(uint32_t token, HandleKind kind, void **pointer,
                         ALenum *captureFormat = nullptr) {
    if (token == 0) {
        *pointer = nullptr;
        if (captureFormat != nullptr) *captureFormat = AL_NONE;
        return true;
    }

    size_t index = 0;
    uint32_t generation = 0;
    if (!DecodeHandleToken(token, &index, &generation)) return false;
    std::lock_guard<std::mutex> lock(gHandleMutex);
    if (index >= gHandles.size()) return false;
    const HandleEntry &entry = gHandles[index];
    if (entry.pointer == nullptr || entry.kind != kind ||
        entry.generation != generation) {
        return false;
    }
    *pointer = entry.pointer;
    if (captureFormat != nullptr) *captureFormat = entry.captureFormat;
    return true;
}

static void ForgetHandle(uint32_t token, HandleKind kind) {
    size_t index = 0;
    uint32_t generation = 0;
    if (!DecodeHandleToken(token, &index, &generation)) return;
    std::lock_guard<std::mutex> lock(gHandleMutex);
    if (index >= gHandles.size()) return;
    HandleEntry &entry = gHandles[index];
    if (entry.pointer == nullptr || entry.kind != kind ||
        entry.generation != generation) {
        return;
    }
    ReverseHandles(kind).erase(entry.pointer);
    entry.pointer = nullptr;
    entry.captureFormat = AL_NONE;
    entry.generation = (entry.generation % kHandleGenerationMask) + 1u;
}

static bool ReadGuest(uint32_t address, void *destination, size_t size) {
    if (size == 0) return true;
    if (address == 0 || destination == nullptr || size > kMaxGuestTransfer) {
        return false;
    }
    return Dynarmic_mem_1read(address, size,
                             static_cast<char *>(destination)) == 0;
}

static bool WriteGuest(uint32_t address, const void *source, size_t size) {
    if (size == 0) return true;
    if (address == 0 || source == nullptr || size > kMaxGuestTransfer) {
        return false;
    }
    return Dynarmic_mem_1write(address, size,
                              const_cast<char *>(
                                  static_cast<const char *>(source))) == 0;
}

template <typename T>
static bool TransferSize(int64_t count, size_t *size) {
    if (count < 0 ||
        static_cast<uint64_t>(count) >
            kMaxGuestTransfer / sizeof(T)) {
        return false;
    }
    *size = static_cast<size_t>(count) * sizeof(T);
    return true;
}

template <typename T>
static bool ReadGuestArray(uint32_t address, int64_t count,
                           std::vector<T> *values) {
    size_t size = 0;
    if (!TransferSize<T>(count, &size)) return false;
    values->resize(static_cast<size_t>(count));
    return size == 0 || ReadGuest(address, values->data(), size);
}

template <typename T>
static bool WriteGuestArray(uint32_t address,
                            const std::vector<T> &values) {
    size_t size = 0;
    if (!TransferSize<T>(values.size(), &size)) return false;
    return size == 0 || WriteGuest(address, values.data(), size);
}

static bool ReadGuestCString(uint32_t address, std::string *string,
                             bool nullAllowed = false) {
    string->clear();
    if (address == 0) return nullAllowed;
    for (size_t offset = 0; offset < kMaxGuestString; offset++) {
        if (offset > UINT32_MAX - address) {
            string->clear();
            return false;
        }
        char character = 0;
        if (!ReadGuest(address + static_cast<uint32_t>(offset),
                       &character, sizeof(character))) {
            string->clear();
            return false;
        }
        if (character == '\0') return true;
        string->push_back(character);
    }
    string->clear();
    return false;
}

static ALfloat WordToFloat(uint32_t word) {
    ALfloat value = 0.0f;
    static_assert(sizeof(value) == sizeof(word), "unexpected ALfloat size");
    memcpy(&value, &word, sizeof(value));
    return value;
}

static uint32_t FloatToWord(ALfloat value) {
    uint32_t word = 0;
    memcpy(&word, &value, sizeof(word));
    return word;
}

static void SetDoubleResult(LC32OpenALPacket *packet, ALdouble value) {
    uint64_t bits = 0;
    static_assert(sizeof(bits) == sizeof(value), "unexpected ALdouble size");
    memcpy(&bits, &value, sizeof(bits));
    packet->words[0] = static_cast<uint32_t>(bits);
    packet->words[1] = static_cast<uint32_t>(bits >> 32u);
}

static size_t ListenerVectorCount(ALenum parameter) {
    if (parameter == AL_ORIENTATION) return 6;
    if (parameter == AL_POSITION || parameter == AL_VELOCITY) return 3;
    return 1;
}

static size_t SourceVectorCount(ALenum parameter) {
    if (parameter == AL_POSITION || parameter == AL_VELOCITY ||
        parameter == AL_DIRECTION) {
        return 3;
    }
    return 1;
}

static bool IsALCStringList(ALCenum parameter, bool nullDevice) {
    if (!nullDevice) return false;
    if (parameter == ALC_DEVICE_SPECIFIER) {
        return alcIsExtensionPresent(nullptr, "ALC_ENUMERATION_EXT") ==
               ALC_TRUE;
    }
    if (parameter == ALC_ALL_DEVICES_SPECIFIER) {
        return alcIsExtensionPresent(nullptr, "ALC_ENUMERATE_ALL_EXT") ==
               ALC_TRUE;
    }
    if (parameter == ALC_CAPTURE_DEVICE_SPECIFIER) {
        return alcIsExtensionPresent(nullptr, "ALC_EXT_CAPTURE") == ALC_TRUE;
    }
    return false;
}

static size_t HostStringSize(const char *string, bool stringList) {
    if (string == nullptr) return 0;
    if (!stringList) {
        const size_t length = strnlen(string, kMaxGuestString);
        return length == kMaxGuestString ? 0 : length + 1u;
    }

    bool previousWasNull = false;
    for (size_t index = 0; index < kMaxGuestString; index++) {
        const bool isNull = string[index] == '\0';
        if (isNull && previousWasNull) return index + 1u;
        previousWasNull = isNull;
    }
    return 0;
}

static void CopyStringResult(LC32OpenALPacket *packet, const char *string,
                             bool stringList, uint32_t destinationWord,
                             uint32_t capacityWord) {
    const uint32_t destination = packet->words[destinationWord];
    const size_t capacity = packet->words[capacityWord];
    const size_t required = HostStringSize(string, stringList);
    if (required != 0 && destination != 0 && capacity >= required) {
        if (!WriteGuest(destination, string, required)) {
            packet->words[0] = 0;
            return;
        }
    }
    packet->words[0] = required <= UINT32_MAX
        ? static_cast<uint32_t>(required) : 0;
}

static bool ReadContextAttributes(uint32_t address,
                                  std::vector<ALCint> *attributes) {
    attributes->clear();
    if (address == 0) return true;
    for (size_t index = 0; index < kMaxContextAttributeWords; index++) {
        const size_t offset = index * sizeof(ALCint);
        if (offset > UINT32_MAX - address) {
            attributes->clear();
            return false;
        }
        ALCint value = 0;
        if (!ReadGuest(address + static_cast<uint32_t>(offset),
                       &value, sizeof(value))) {
            attributes->clear();
            return false;
        }
        attributes->push_back(value);
        if (value == 0) return (index % 2u) == 0u;
    }
    attributes->clear();
    return false;
}

static size_t BytesPerCaptureSample(ALenum format) {
    switch (format) {
        case AL_FORMAT_MONO8: return 1;
        case AL_FORMAT_MONO16: return 2;
        case AL_FORMAT_STEREO8: return 2;
        case AL_FORMAT_STEREO16: return 4;
        default: return 0;
    }
}

static ALCdevice *DeviceForToken(uint32_t token, bool *valid,
                                 ALenum *captureFormat = nullptr) {
    void *pointer = nullptr;
    *valid = LookupHandle(token, HandleKind::Device,
                          &pointer, captureFormat);
    return static_cast<ALCdevice *>(pointer);
}

static ALCcontext *ContextForToken(uint32_t token, bool *valid) {
    void *pointer = nullptr;
    *valid = LookupHandle(token, HandleKind::Context, &pointer);
    return static_cast<ALCcontext *>(pointer);
}

} // namespace

extern "C" __attribute__((visibility("default")))
uint32_t LC32_OpenAL_Dispatch(uint32_t opcode, uint32_t guestPacket,
                             uint32_t) {
    LC32OpenALPacket packet = {};
    if (!ReadGuest(guestPacket, &packet, sizeof(packet))) return 0;

    uint32_t *const w = packet.words;
    bool valid = false;

    switch (opcode) {
        case LC32_OPENAL_OP_alEnable:
            alEnable(static_cast<ALenum>(w[0]));
            break;
        case LC32_OPENAL_OP_alDisable:
            alDisable(static_cast<ALenum>(w[0]));
            break;
        case LC32_OPENAL_OP_alIsEnabled:
            w[0] = alIsEnabled(static_cast<ALenum>(w[0]));
            break;
        case LC32_OPENAL_OP_alGetString: {
            const char *string = alGetString(static_cast<ALenum>(w[0]));
            CopyStringResult(&packet, string, false,
                LC32_OPENAL_AL_GET_STRING_DESTINATION_WORD,
                LC32_OPENAL_AL_GET_STRING_CAPACITY_WORD);
            break;
        }
        case LC32_OPENAL_OP_alGetBooleanv: {
            ALboolean value = AL_FALSE;
            alGetBooleanv(static_cast<ALenum>(w[0]), &value);
            if (!WriteGuest(w[1], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetIntegerv: {
            ALint value = 0;
            alGetIntegerv(static_cast<ALenum>(w[0]), &value);
            if (!WriteGuest(w[1], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetFloatv: {
            ALfloat value = 0;
            alGetFloatv(static_cast<ALenum>(w[0]), &value);
            if (!WriteGuest(w[1], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetDoublev: {
            ALdouble value = 0;
            alGetDoublev(static_cast<ALenum>(w[0]), &value);
            if (!WriteGuest(w[1], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetBoolean:
            w[0] = alGetBoolean(static_cast<ALenum>(w[0]));
            break;
        case LC32_OPENAL_OP_alGetInteger:
            w[0] = static_cast<uint32_t>(
                alGetInteger(static_cast<ALenum>(w[0])));
            break;
        case LC32_OPENAL_OP_alGetFloat:
            w[0] = FloatToWord(alGetFloat(static_cast<ALenum>(w[0])));
            break;
        case LC32_OPENAL_OP_alGetDouble:
            SetDoubleResult(&packet,
                            alGetDouble(static_cast<ALenum>(w[0])));
            break;
        case LC32_OPENAL_OP_alGetError:
            w[0] = alGetError();
            break;
        case LC32_OPENAL_OP_alIsExtensionPresent: {
            std::string name;
            w[0] = ReadGuestCString(w[0], &name)
                ? alIsExtensionPresent(name.c_str()) : AL_FALSE;
            break;
        }
        case LC32_OPENAL_OP_alGetProcAddress: {
            std::string name;
            w[0] = ReadGuestCString(w[0], &name) &&
                   alGetProcAddress(name.c_str()) != nullptr;
            break;
        }
        case LC32_OPENAL_OP_alGetEnumValue: {
            std::string name;
            w[0] = ReadGuestCString(w[0], &name)
                ? static_cast<uint32_t>(alGetEnumValue(name.c_str())) : 0;
            break;
        }
        case LC32_OPENAL_OP_alListenerf:
            alListenerf(static_cast<ALenum>(w[0]), WordToFloat(w[1]));
            break;
        case LC32_OPENAL_OP_alListener3f:
            alListener3f(static_cast<ALenum>(w[0]), WordToFloat(w[1]),
                         WordToFloat(w[2]), WordToFloat(w[3]));
            break;
        case LC32_OPENAL_OP_alListenerfv: {
            std::vector<ALfloat> values;
            if (!ReadGuestArray(w[1], ListenerVectorCount(w[0]), &values))
                return 0;
            alListenerfv(static_cast<ALenum>(w[0]), values.data());
            break;
        }
        case LC32_OPENAL_OP_alListeneri:
            alListeneri(static_cast<ALenum>(w[0]),
                        static_cast<ALint>(w[1]));
            break;
        case LC32_OPENAL_OP_alListener3i:
            alListener3i(static_cast<ALenum>(w[0]),
                static_cast<ALint>(w[1]), static_cast<ALint>(w[2]),
                static_cast<ALint>(w[3]));
            break;
        case LC32_OPENAL_OP_alListeneriv: {
            std::vector<ALint> values;
            if (!ReadGuestArray(w[1], ListenerVectorCount(w[0]), &values))
                return 0;
            alListeneriv(static_cast<ALenum>(w[0]), values.data());
            break;
        }
        case LC32_OPENAL_OP_alGetListenerf: {
            ALfloat value = 0;
            alGetListenerf(static_cast<ALenum>(w[0]), &value);
            if (!WriteGuest(w[1], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetListener3f: {
            ALfloat values[3] = {};
            alGetListener3f(static_cast<ALenum>(w[0]),
                            &values[0], &values[1], &values[2]);
            for (size_t i = 0; i < 3; i++)
                if (!WriteGuest(w[i + 1], &values[i], sizeof(values[i])))
                    return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetListenerfv: {
            std::vector<ALfloat> values(ListenerVectorCount(w[0]));
            alGetListenerfv(static_cast<ALenum>(w[0]), values.data());
            if (!WriteGuestArray(w[1], values)) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetListeneri: {
            ALint value = 0;
            alGetListeneri(static_cast<ALenum>(w[0]), &value);
            if (!WriteGuest(w[1], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetListener3i: {
            ALint values[3] = {};
            alGetListener3i(static_cast<ALenum>(w[0]),
                            &values[0], &values[1], &values[2]);
            for (size_t i = 0; i < 3; i++)
                if (!WriteGuest(w[i + 1], &values[i], sizeof(values[i])))
                    return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetListeneriv: {
            std::vector<ALint> values(ListenerVectorCount(w[0]));
            alGetListeneriv(static_cast<ALenum>(w[0]), values.data());
            if (!WriteGuestArray(w[1], values)) return 0;
            break;
        }

        case LC32_OPENAL_OP_alGenSources: {
            const ALsizei count = static_cast<ALsizei>(w[0]);
            size_t ignored = 0;
            if (!TransferSize<ALuint>(count, &ignored)) return 0;
            std::vector<ALuint> sources(static_cast<size_t>(count));
            alGenSources(count, sources.data());
            if (!WriteGuestArray(w[1], sources)) return 0;
            break;
        }
        case LC32_OPENAL_OP_alDeleteSources: {
            const ALsizei count = static_cast<ALsizei>(w[0]);
            std::vector<ALuint> sources;
            if (!ReadGuestArray(w[1], count, &sources)) return 0;
            alDeleteSources(count, sources.data());
            break;
        }
        case LC32_OPENAL_OP_alIsSource:
            w[0] = alIsSource(static_cast<ALuint>(w[0]));
            break;
        case LC32_OPENAL_OP_alSourcef:
            alSourcef(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                      WordToFloat(w[2]));
            break;
        case LC32_OPENAL_OP_alSource3f:
            alSource3f(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                       WordToFloat(w[2]), WordToFloat(w[3]),
                       WordToFloat(w[4]));
            break;
        case LC32_OPENAL_OP_alSourcefv: {
            std::vector<ALfloat> values;
            if (!ReadGuestArray(w[2], SourceVectorCount(w[1]), &values))
                return 0;
            alSourcefv(static_cast<ALuint>(w[0]),
                       static_cast<ALenum>(w[1]), values.data());
            break;
        }
        case LC32_OPENAL_OP_alSourcei:
            alSourcei(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                      static_cast<ALint>(w[2]));
            break;
        case LC32_OPENAL_OP_alSource3i:
            alSource3i(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                static_cast<ALint>(w[2]), static_cast<ALint>(w[3]),
                static_cast<ALint>(w[4]));
            break;
        case LC32_OPENAL_OP_alSourceiv: {
            std::vector<ALint> values;
            if (!ReadGuestArray(w[2], SourceVectorCount(w[1]), &values))
                return 0;
            alSourceiv(static_cast<ALuint>(w[0]),
                       static_cast<ALenum>(w[1]), values.data());
            break;
        }
        case LC32_OPENAL_OP_alGetSourcef: {
            ALfloat value = 0;
            alGetSourcef(static_cast<ALuint>(w[0]),
                         static_cast<ALenum>(w[1]), &value);
            if (!WriteGuest(w[2], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetSource3f: {
            ALfloat values[3] = {};
            alGetSource3f(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]),
                          &values[0], &values[1], &values[2]);
            for (size_t i = 0; i < 3; i++)
                if (!WriteGuest(w[i + 2], &values[i], sizeof(values[i])))
                    return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetSourcefv: {
            std::vector<ALfloat> values(SourceVectorCount(w[1]));
            alGetSourcefv(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]), values.data());
            if (!WriteGuestArray(w[2], values)) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetSourcei: {
            ALint value = 0;
            alGetSourcei(static_cast<ALuint>(w[0]),
                         static_cast<ALenum>(w[1]), &value);
            if (!WriteGuest(w[2], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetSource3i: {
            ALint values[3] = {};
            alGetSource3i(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]),
                          &values[0], &values[1], &values[2]);
            for (size_t i = 0; i < 3; i++)
                if (!WriteGuest(w[i + 2], &values[i], sizeof(values[i])))
                    return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetSourceiv: {
            std::vector<ALint> values(SourceVectorCount(w[1]));
            alGetSourceiv(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]), values.data());
            if (!WriteGuestArray(w[2], values)) return 0;
            break;
        }
        case LC32_OPENAL_OP_alSourcePlayv:
        case LC32_OPENAL_OP_alSourceStopv:
        case LC32_OPENAL_OP_alSourceRewindv:
        case LC32_OPENAL_OP_alSourcePausev: {
            const ALsizei count = static_cast<ALsizei>(w[0]);
            std::vector<ALuint> sources;
            if (!ReadGuestArray(w[1], count, &sources)) return 0;
            if (opcode == LC32_OPENAL_OP_alSourcePlayv)
                alSourcePlayv(count, sources.data());
            else if (opcode == LC32_OPENAL_OP_alSourceStopv)
                alSourceStopv(count, sources.data());
            else if (opcode == LC32_OPENAL_OP_alSourceRewindv)
                alSourceRewindv(count, sources.data());
            else
                alSourcePausev(count, sources.data());
            break;
        }
        case LC32_OPENAL_OP_alSourcePlay:
            alSourcePlay(static_cast<ALuint>(w[0]));
            break;
        case LC32_OPENAL_OP_alSourceStop:
            alSourceStop(static_cast<ALuint>(w[0]));
            break;
        case LC32_OPENAL_OP_alSourceRewind:
            alSourceRewind(static_cast<ALuint>(w[0]));
            break;
        case LC32_OPENAL_OP_alSourcePause:
            alSourcePause(static_cast<ALuint>(w[0]));
            break;
        case LC32_OPENAL_OP_alSourceQueueBuffers:
        case LC32_OPENAL_OP_alSourceUnqueueBuffers: {
            const ALuint source = static_cast<ALuint>(w[0]);
            const ALsizei count = static_cast<ALsizei>(w[1]);
            if (opcode == LC32_OPENAL_OP_alSourceQueueBuffers) {
                std::vector<ALuint> buffers;
                if (!ReadGuestArray(w[2], count, &buffers)) return 0;
                alSourceQueueBuffers(source, count, buffers.data());
            } else {
                size_t ignored = 0;
                if (!TransferSize<ALuint>(count, &ignored)) return 0;
                std::vector<ALuint> buffers(static_cast<size_t>(count));
                alSourceUnqueueBuffers(source, count, buffers.data());
                if (!WriteGuestArray(w[2], buffers)) return 0;
            }
            break;
        }
        case LC32_OPENAL_OP_alGenBuffers: {
            const ALsizei count = static_cast<ALsizei>(w[0]);
            size_t ignored = 0;
            if (!TransferSize<ALuint>(count, &ignored)) return 0;
            std::vector<ALuint> buffers(static_cast<size_t>(count));
            alGenBuffers(count, buffers.data());
            if (!WriteGuestArray(w[1], buffers)) return 0;
            break;
        }
        case LC32_OPENAL_OP_alDeleteBuffers: {
            const ALsizei count = static_cast<ALsizei>(w[0]);
            std::vector<ALuint> buffers;
            if (!ReadGuestArray(w[1], count, &buffers)) return 0;
            alDeleteBuffers(count, buffers.data());
            break;
        }
        case LC32_OPENAL_OP_alIsBuffer:
            w[0] = alIsBuffer(static_cast<ALuint>(w[0]));
            break;
        case LC32_OPENAL_OP_alBufferData: {
            const ALsizei size = static_cast<ALsizei>(w[3]);
            size_t byteCount = 0;
            if (!TransferSize<uint8_t>(size, &byteCount)) return 0;
            std::vector<uint8_t> bytes;
            if (!ReadGuestArray(w[2], size, &bytes)) return 0;
            alBufferData(static_cast<ALuint>(w[0]),
                         static_cast<ALenum>(w[1]), bytes.data(), size,
                         static_cast<ALsizei>(w[4]));
            break;
        }
        case LC32_OPENAL_OP_alBufferf:
            alBufferf(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                      WordToFloat(w[2]));
            break;
        case LC32_OPENAL_OP_alBuffer3f:
            alBuffer3f(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                       WordToFloat(w[2]), WordToFloat(w[3]),
                       WordToFloat(w[4]));
            break;
        case LC32_OPENAL_OP_alBufferfv: {
            ALfloat value = 0;
            if (!ReadGuest(w[2], &value, sizeof(value))) return 0;
            alBufferfv(static_cast<ALuint>(w[0]),
                       static_cast<ALenum>(w[1]), &value);
            break;
        }
        case LC32_OPENAL_OP_alBufferi:
            alBufferi(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                      static_cast<ALint>(w[2]));
            break;
        case LC32_OPENAL_OP_alBuffer3i:
            alBuffer3i(static_cast<ALuint>(w[0]), static_cast<ALenum>(w[1]),
                static_cast<ALint>(w[2]), static_cast<ALint>(w[3]),
                static_cast<ALint>(w[4]));
            break;
        case LC32_OPENAL_OP_alBufferiv: {
            ALint value = 0;
            if (!ReadGuest(w[2], &value, sizeof(value))) return 0;
            alBufferiv(static_cast<ALuint>(w[0]),
                       static_cast<ALenum>(w[1]), &value);
            break;
        }
        case LC32_OPENAL_OP_alGetBufferf: {
            ALfloat value = 0;
            alGetBufferf(static_cast<ALuint>(w[0]),
                         static_cast<ALenum>(w[1]), &value);
            if (!WriteGuest(w[2], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetBuffer3f: {
            ALfloat values[3] = {};
            alGetBuffer3f(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]),
                          &values[0], &values[1], &values[2]);
            for (size_t i = 0; i < 3; i++)
                if (!WriteGuest(w[i + 2], &values[i], sizeof(values[i])))
                    return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetBufferfv: {
            ALfloat value = 0;
            alGetBufferfv(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]), &value);
            if (!WriteGuest(w[2], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetBufferi: {
            ALint value = 0;
            alGetBufferi(static_cast<ALuint>(w[0]),
                         static_cast<ALenum>(w[1]), &value);
            if (!WriteGuest(w[2], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetBuffer3i: {
            ALint values[3] = {};
            alGetBuffer3i(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]),
                          &values[0], &values[1], &values[2]);
            for (size_t i = 0; i < 3; i++)
                if (!WriteGuest(w[i + 2], &values[i], sizeof(values[i])))
                    return 0;
            break;
        }
        case LC32_OPENAL_OP_alGetBufferiv: {
            ALint value = 0;
            alGetBufferiv(static_cast<ALuint>(w[0]),
                          static_cast<ALenum>(w[1]), &value);
            if (!WriteGuest(w[2], &value, sizeof(value))) return 0;
            break;
        }
        case LC32_OPENAL_OP_alDopplerFactor:
            alDopplerFactor(WordToFloat(w[0]));
            break;
        case LC32_OPENAL_OP_alDopplerVelocity:
            alDopplerVelocity(WordToFloat(w[0]));
            break;
        case LC32_OPENAL_OP_alSpeedOfSound:
            alSpeedOfSound(WordToFloat(w[0]));
            break;
        case LC32_OPENAL_OP_alDistanceModel:
            alDistanceModel(static_cast<ALenum>(w[0]));
            break;

        case LC32_OPENAL_OP_alcCreateContext: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            if (!valid || device == nullptr) {
                w[0] = 0;
                break;
            }
            std::vector<ALCint> attributes;
            if (!ReadContextAttributes(w[1], &attributes)) {
                w[0] = 0;
                break;
            }
            ALCcontext *context = alcCreateContext(
                device, attributes.empty() ? nullptr : attributes.data());
            w[0] = RegisterHandle(context, HandleKind::Context);
            if (context != nullptr && w[0] == 0) alcDestroyContext(context);
            break;
        }
        case LC32_OPENAL_OP_alcMakeContextCurrent: {
            const uint32_t token = w[0];
            ALCcontext *context = ContextForToken(token, &valid);
            if (UseSilentSimulatorContext()) {
                // Simulator RemoteIO can synchronously time out and abort while
                // making Apple's OpenAL context current from LiveContainer.
                // Keep guest-visible ALC bookkeeping coherent without
                // activating the host audio device. This is deliberately a
                // crash-avoidance fallback, not an audio backend: native AL
                // calls have no current context and fail/no-op safely.
                if (valid) gSilentCurrentContextToken.store(token);
                w[0] = valid ? ALC_TRUE : ALC_FALSE;
            } else {
                w[0] = valid ? alcMakeContextCurrent(context) : ALC_FALSE;
            }
            break;
        }
        case LC32_OPENAL_OP_alcProcessContext: {
            ALCcontext *context = ContextForToken(w[0], &valid);
            if (!UseSilentSimulatorContext() && valid && context != nullptr)
                alcProcessContext(context);
            break;
        }
        case LC32_OPENAL_OP_alcSuspendContext: {
            ALCcontext *context = ContextForToken(w[0], &valid);
            if (!UseSilentSimulatorContext() && valid && context != nullptr)
                alcSuspendContext(context);
            break;
        }
        case LC32_OPENAL_OP_alcDestroyContext: {
            const uint32_t token = w[0];
            ALCcontext *context = ContextForToken(token, &valid);
            if (valid && context != nullptr) {
                alcDestroyContext(context);
                ForgetHandle(token, HandleKind::Context);
                if (UseSilentSimulatorContext()) {
                    uint32_t expected = token;
                    gSilentCurrentContextToken.compare_exchange_strong(
                        expected, 0);
                }
            }
            break;
        }
        case LC32_OPENAL_OP_alcGetCurrentContext:
            if (UseSilentSimulatorContext()) {
                const uint32_t token = gSilentCurrentContextToken.load();
                ALCcontext *context = ContextForToken(token, &valid);
                if (token != 0 && (!valid || context == nullptr)) {
                    uint32_t expected = token;
                    gSilentCurrentContextToken.compare_exchange_strong(
                        expected, 0);
                    w[0] = 0;
                } else {
                    w[0] = token;
                }
            } else {
                w[0] = RegisterHandle(alcGetCurrentContext(),
                                      HandleKind::Context);
            }
            break;
        case LC32_OPENAL_OP_alcGetContextsDevice: {
            ALCcontext *context = ContextForToken(w[0], &valid);
            w[0] = valid && context != nullptr
                ? RegisterHandle(alcGetContextsDevice(context),
                                 HandleKind::Device)
                : 0;
            break;
        }
        case LC32_OPENAL_OP_alcOpenDevice: {
            std::string name;
            const bool hasName = w[0] != 0;
            if (!ReadGuestCString(w[0], &name, true)) {
                w[0] = 0;
                break;
            }
            ALCdevice *device = alcOpenDevice(hasName ? name.c_str() : nullptr);
            w[0] = RegisterHandle(device, HandleKind::Device);
            if (device != nullptr && w[0] == 0) alcCloseDevice(device);
            break;
        }
        case LC32_OPENAL_OP_alcCloseDevice: {
            const uint32_t token = w[0];
            ALCdevice *device = DeviceForToken(token, &valid);
            const ALCboolean result = valid && device != nullptr
                ? alcCloseDevice(device) : ALC_FALSE;
            if (result == ALC_TRUE) ForgetHandle(token, HandleKind::Device);
            w[0] = result;
            break;
        }
        case LC32_OPENAL_OP_alcGetError: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            w[0] = valid ? static_cast<uint32_t>(alcGetError(device))
                         : ALC_INVALID_DEVICE;
            break;
        }
        case LC32_OPENAL_OP_alcIsExtensionPresent: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            std::string name;
            w[0] = valid && ReadGuestCString(w[1], &name)
                ? alcIsExtensionPresent(device, name.c_str()) : ALC_FALSE;
            break;
        }
        case LC32_OPENAL_OP_alcGetProcAddress: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            std::string name;
            w[0] = valid && ReadGuestCString(w[1], &name) &&
                   alcGetProcAddress(device, name.c_str()) != nullptr;
            break;
        }
        case LC32_OPENAL_OP_alcGetEnumValue: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            std::string name;
            w[0] = valid && ReadGuestCString(w[1], &name)
                ? static_cast<uint32_t>(alcGetEnumValue(device, name.c_str()))
                : 0;
            break;
        }
        case LC32_OPENAL_OP_alcGetString: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            if (!valid) {
                w[0] = 0;
                break;
            }
            const ALCenum parameter = static_cast<ALCenum>(w[1]);
            const char *string = alcGetString(device, parameter);
            CopyStringResult(&packet, string,
                IsALCStringList(parameter, device == nullptr),
                LC32_OPENAL_ALC_GET_STRING_DESTINATION_WORD,
                LC32_OPENAL_ALC_GET_STRING_CAPACITY_WORD);
            break;
        }
        case LC32_OPENAL_OP_alcGetIntegerv: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            const ALCsizei count = static_cast<ALCsizei>(w[2]);
            size_t ignored = 0;
            if (!valid || !TransferSize<ALCint>(count, &ignored)) return 0;
            std::vector<ALCint> values(static_cast<size_t>(count));
            alcGetIntegerv(device, static_cast<ALCenum>(w[1]),
                           count, values.data());
            if (!WriteGuestArray(w[3], values)) return 0;
            break;
        }
        case LC32_OPENAL_OP_alcCaptureOpenDevice: {
            std::string name;
            const bool hasName = w[0] != 0;
            if (!ReadGuestCString(w[0], &name, true)) {
                w[0] = 0;
                break;
            }
            const ALenum format = static_cast<ALenum>(w[2]);
            ALCdevice *device = alcCaptureOpenDevice(
                hasName ? name.c_str() : nullptr,
                static_cast<ALCuint>(w[1]), format,
                static_cast<ALCsizei>(w[3]));
            w[0] = RegisterHandle(device, HandleKind::Device, format);
            if (device != nullptr && w[0] == 0)
                alcCaptureCloseDevice(device);
            break;
        }
        case LC32_OPENAL_OP_alcCaptureCloseDevice: {
            const uint32_t token = w[0];
            ALCdevice *device = DeviceForToken(token, &valid);
            const ALCboolean result = valid && device != nullptr
                ? alcCaptureCloseDevice(device) : ALC_FALSE;
            if (result == ALC_TRUE) ForgetHandle(token, HandleKind::Device);
            w[0] = result;
            break;
        }
        case LC32_OPENAL_OP_alcCaptureStart: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            if (valid && device != nullptr) alcCaptureStart(device);
            break;
        }
        case LC32_OPENAL_OP_alcCaptureStop: {
            ALCdevice *device = DeviceForToken(w[0], &valid);
            if (valid && device != nullptr) alcCaptureStop(device);
            break;
        }
        case LC32_OPENAL_OP_alcCaptureSamples: {
            ALenum format = AL_NONE;
            ALCdevice *device = DeviceForToken(w[0], &valid, &format);
            const ALCsizei samples = static_cast<ALCsizei>(w[2]);
            const size_t bytesPerSample = BytesPerCaptureSample(format);
            if (!valid || device == nullptr || samples < 0 ||
                bytesPerSample == 0 ||
                static_cast<uint64_t>(samples) >
                    kMaxGuestTransfer / bytesPerSample) {
                return 0;
            }
            std::vector<uint8_t> bytes(
                static_cast<size_t>(samples) * bytesPerSample);
            alcCaptureSamples(device, bytes.data(), samples);
            if (!WriteGuestArray(w[1], bytes)) return 0;
            break;
        }
        default:
            return 0;
    }

    return WriteGuest(guestPacket, &packet, sizeof(packet)) ? 1u : 0u;
}

#pragma clang diagnostic pop
