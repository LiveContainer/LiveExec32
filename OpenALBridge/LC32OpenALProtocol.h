#ifndef LC32_OPENAL_PROTOCOL_H
#define LC32_OPENAL_PROTOCOL_H

#include <stdint.h>

/*
 * Wire protocol shared by the armv7 guest shim and the arm64 host bridge.
 * Every field is an explicitly-sized word; do not put pointers, enums, bools,
 * floats, or native structs in this packet.  Arguments occupy words[] in API
 * declaration order.  Pointers and ALC handles are guest u32 values, and float
 * values are their IEEE-754 bit patterns.  A scalar result replaces words[0];
 * a 64-bit/double result replaces words[0..1], little-endian low word first.
 */
#define LC32_OPENAL_PACKET_WORD_COUNT 8u

typedef struct LC32OpenALPacket {
    uint32_t words[LC32_OPENAL_PACKET_WORD_COUNT];
} LC32OpenALPacket;

typedef uint32_t LC32OpenALOpcode;

enum {
    LC32_OPENAL_OP_INVALID = 0,

    LC32_OPENAL_OP_alEnable = 1,
    LC32_OPENAL_OP_alDisable,
    LC32_OPENAL_OP_alIsEnabled,
    LC32_OPENAL_OP_alGetString,
    LC32_OPENAL_OP_alGetBooleanv,
    LC32_OPENAL_OP_alGetIntegerv,
    LC32_OPENAL_OP_alGetFloatv,
    LC32_OPENAL_OP_alGetDoublev,
    LC32_OPENAL_OP_alGetBoolean,
    LC32_OPENAL_OP_alGetInteger,
    LC32_OPENAL_OP_alGetFloat,
    LC32_OPENAL_OP_alGetDouble,
    LC32_OPENAL_OP_alGetError,
    LC32_OPENAL_OP_alIsExtensionPresent,
    LC32_OPENAL_OP_alGetProcAddress,
    LC32_OPENAL_OP_alGetEnumValue,
    LC32_OPENAL_OP_alListenerf,
    LC32_OPENAL_OP_alListener3f,
    LC32_OPENAL_OP_alListenerfv,
    LC32_OPENAL_OP_alListeneri,
    LC32_OPENAL_OP_alListener3i,
    LC32_OPENAL_OP_alListeneriv,
    LC32_OPENAL_OP_alGetListenerf,
    LC32_OPENAL_OP_alGetListener3f,
    LC32_OPENAL_OP_alGetListenerfv,
    LC32_OPENAL_OP_alGetListeneri,
    LC32_OPENAL_OP_alGetListener3i,
    LC32_OPENAL_OP_alGetListeneriv,
    LC32_OPENAL_OP_alGenSources,
    LC32_OPENAL_OP_alDeleteSources,
    LC32_OPENAL_OP_alIsSource,
    LC32_OPENAL_OP_alSourcef,
    LC32_OPENAL_OP_alSource3f,
    LC32_OPENAL_OP_alSourcefv,
    LC32_OPENAL_OP_alSourcei,
    LC32_OPENAL_OP_alSource3i,
    LC32_OPENAL_OP_alSourceiv,
    LC32_OPENAL_OP_alGetSourcef,
    LC32_OPENAL_OP_alGetSource3f,
    LC32_OPENAL_OP_alGetSourcefv,
    LC32_OPENAL_OP_alGetSourcei,
    LC32_OPENAL_OP_alGetSource3i,
    LC32_OPENAL_OP_alGetSourceiv,
    LC32_OPENAL_OP_alSourcePlayv,
    LC32_OPENAL_OP_alSourceStopv,
    LC32_OPENAL_OP_alSourceRewindv,
    LC32_OPENAL_OP_alSourcePausev,
    LC32_OPENAL_OP_alSourcePlay,
    LC32_OPENAL_OP_alSourceStop,
    LC32_OPENAL_OP_alSourceRewind,
    LC32_OPENAL_OP_alSourcePause,
    LC32_OPENAL_OP_alSourceQueueBuffers,
    LC32_OPENAL_OP_alSourceUnqueueBuffers,
    LC32_OPENAL_OP_alGenBuffers,
    LC32_OPENAL_OP_alDeleteBuffers,
    LC32_OPENAL_OP_alIsBuffer,
    LC32_OPENAL_OP_alBufferData,
    LC32_OPENAL_OP_alBufferf,
    LC32_OPENAL_OP_alBuffer3f,
    LC32_OPENAL_OP_alBufferfv,
    LC32_OPENAL_OP_alBufferi,
    LC32_OPENAL_OP_alBuffer3i,
    LC32_OPENAL_OP_alBufferiv,
    LC32_OPENAL_OP_alGetBufferf,
    LC32_OPENAL_OP_alGetBuffer3f,
    LC32_OPENAL_OP_alGetBufferfv,
    LC32_OPENAL_OP_alGetBufferi,
    LC32_OPENAL_OP_alGetBuffer3i,
    LC32_OPENAL_OP_alGetBufferiv,
    LC32_OPENAL_OP_alDopplerFactor,
    LC32_OPENAL_OP_alDopplerVelocity,
    LC32_OPENAL_OP_alSpeedOfSound,
    LC32_OPENAL_OP_alDistanceModel,

    LC32_OPENAL_OP_alcCreateContext,
    LC32_OPENAL_OP_alcMakeContextCurrent,
    LC32_OPENAL_OP_alcProcessContext,
    LC32_OPENAL_OP_alcSuspendContext,
    LC32_OPENAL_OP_alcDestroyContext,
    LC32_OPENAL_OP_alcGetCurrentContext,
    LC32_OPENAL_OP_alcGetContextsDevice,
    LC32_OPENAL_OP_alcOpenDevice,
    LC32_OPENAL_OP_alcCloseDevice,
    LC32_OPENAL_OP_alcGetError,
    LC32_OPENAL_OP_alcIsExtensionPresent,
    LC32_OPENAL_OP_alcGetProcAddress,
    LC32_OPENAL_OP_alcGetEnumValue,
    LC32_OPENAL_OP_alcGetString,
    LC32_OPENAL_OP_alcGetIntegerv,
    LC32_OPENAL_OP_alcCaptureOpenDevice,
    LC32_OPENAL_OP_alcCaptureCloseDevice,
    LC32_OPENAL_OP_alcCaptureStart,
    LC32_OPENAL_OP_alcCaptureStop,
    LC32_OPENAL_OP_alcCaptureSamples,

    LC32_OPENAL_OP_COUNT
};

/*
 * String operations use a retryable two-phase form rather than returning a
 * host pointer.  alGetString inputs are [param, destination, capacity].
 * alcGetString inputs are [device-token, param, destination, capacity].
 * The dispatcher always returns the required byte count (including the final
 * NUL, or both NULs for device lists) in words[0].  A zero destination/capacity
 * is the size query.  The guest retries after growing its thread-local buffer.
 */
#define LC32_OPENAL_AL_GET_STRING_DESTINATION_WORD 1u
#define LC32_OPENAL_AL_GET_STRING_CAPACITY_WORD    2u
#define LC32_OPENAL_ALC_GET_STRING_DESTINATION_WORD 2u
#define LC32_OPENAL_ALC_GET_STRING_CAPACITY_WORD    3u

#if defined(__cplusplus)
static_assert(sizeof(uint32_t) == 4, "OpenAL protocol requires 32-bit words");
static_assert(sizeof(LC32OpenALPacket) == 32, "OpenAL packet layout changed");
static_assert(LC32_OPENAL_OP_COUNT == 94, "OpenAL opcode table changed");
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(uint32_t) == 4, "OpenAL protocol requires 32-bit words");
_Static_assert(sizeof(LC32OpenALPacket) == 32, "OpenAL packet layout changed");
_Static_assert(LC32_OPENAL_OP_COUNT == 94, "OpenAL opcode table changed");
#else
typedef char LC32OpenALUInt32MustBeFourBytes[(sizeof(uint32_t) == 4) ? 1 : -1];
typedef char LC32OpenALPacketMustBe32Bytes[(sizeof(LC32OpenALPacket) == 32) ? 1 : -1];
typedef char LC32OpenALMustHave93Opcodes[(LC32_OPENAL_OP_COUNT == 94) ? 1 : -1];
#endif

#endif /* LC32_OPENAL_PROTOCOL_H */
