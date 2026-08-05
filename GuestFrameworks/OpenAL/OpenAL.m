#import <OpenAL/OpenAL.h>
#import <LC32/LC32.h>

#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "../../OpenALBridge/LC32OpenALProtocol.h"

#if UINTPTR_MAX > UINT32_MAX
#error "The OpenAL guest shim must be compiled for a 32-bit target"
#endif

typedef struct {
    char *bytes;
    uint32_t capacity;
} LC32OpenALStringBuffer;

static __thread LC32OpenALStringBuffer LC32OpenALALStringBuffer;
static __thread LC32OpenALStringBuffer LC32OpenALALCStringBuffer;

static pthread_once_t LC32OpenALDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32OpenALDispatcher;

static void LC32OpenALResolveDispatcher(void) {
    LC32OpenALDispatcher = LC32Dlsym("LC32_OpenAL_Dispatch", YES);
}

static uint64_t LC32OpenALHostDispatcher(void) {
    pthread_once(&LC32OpenALDispatcherOnce, LC32OpenALResolveDispatcher);
    return LC32OpenALDispatcher;
}

static void LC32OpenALDispatch(LC32OpenALOpcode opcode,
                               LC32OpenALPacket *packet) {
    uint64_t dispatcher = LC32OpenALHostDispatcher();
    if (!dispatcher) {
        packet->words[0] = 0;
        packet->words[1] = 0;
        return;
    }

    LC32InvokeHostCRet32(dispatcher, opcode, (uint32_t)(uintptr_t)packet);
}

static uint32_t LC32OpenALPointerWord(const void *pointer) {
    return (uint32_t)(uintptr_t)pointer;
}

static uint32_t LC32OpenALFloatWord(ALfloat value) {
    union {
        ALfloat value;
        uint32_t word;
    } bits = { .value = value };
    return bits.word;
}

static ALfloat LC32OpenALFloatResult(uint32_t word) {
    union {
        uint32_t word;
        ALfloat value;
    } bits = { .word = word };
    return bits.value;
}

static ALdouble LC32OpenALDoubleResult(uint32_t low, uint32_t high) {
    union {
        uint64_t bits;
        ALdouble value;
    } result = { .bits = ((uint64_t)high << 32) | low };
    return result.value;
}

static const char *LC32OpenALCopyString(LC32OpenALOpcode opcode,
                                        uint32_t argument0,
                                        uint32_t argument1,
                                        uint32_t argumentCount,
                                        LC32OpenALStringBuffer *buffer) {
    for (unsigned attempt = 0; attempt != 4; ++attempt) {
        LC32OpenALPacket packet = {{0}};
        packet.words[0] = argument0;
        if (argumentCount == 2) {
            packet.words[1] = argument1;
        }
        packet.words[argumentCount] = LC32OpenALPointerWord(buffer->bytes);
        packet.words[argumentCount + 1] = buffer->capacity;
        LC32OpenALDispatch(opcode, &packet);

        uint32_t required = packet.words[0];
        if (!required) {
            return NULL;
        }
        if (buffer->bytes && required <= buffer->capacity) {
            return buffer->bytes;
        }

        char *grown = realloc(buffer->bytes, required);
        if (!grown) {
            return NULL;
        }
        buffer->bytes = grown;
        buffer->capacity = required;
    }
    return NULL;
}

static void *LC32OpenALLookupALProc(const char *name);
static void *LC32OpenALLookupALCProc(const char *name);

#define LC32_OPENAL_PACKET() LC32OpenALPacket packet = {{0}}
#define LC32_OPENAL_CALL(OP) LC32OpenALDispatch(LC32_OPENAL_OP_##OP, &packet)
#define LC32_OPENAL_WORD(VALUE) ((uint32_t)(VALUE))
#define LC32_OPENAL_PTR(VALUE) LC32OpenALPointerWord((const void *)(VALUE))
#define LC32_OPENAL_FLOAT(VALUE) LC32OpenALFloatWord((VALUE))

#define LC32_OPENAL_VOID1(NAME, T0, A0, W0) \
    void NAME(T0 A0) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); \
        LC32_OPENAL_CALL(NAME); \
    }

#define LC32_OPENAL_VOID2(NAME, T0, A0, W0, T1, A1, W1) \
    void NAME(T0 A0, T1 A1) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        LC32_OPENAL_CALL(NAME); \
    }

#define LC32_OPENAL_VOID3(NAME, T0, A0, W0, T1, A1, W1, T2, A2, W2) \
    void NAME(T0 A0, T1 A1, T2 A2) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        packet.words[2] = (W2); LC32_OPENAL_CALL(NAME); \
    }

#define LC32_OPENAL_VOID4(NAME, T0, A0, W0, T1, A1, W1, T2, A2, W2, T3, A3, W3) \
    void NAME(T0 A0, T1 A1, T2 A2, T3 A3) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        packet.words[2] = (W2); packet.words[3] = (W3); LC32_OPENAL_CALL(NAME); \
    }

#define LC32_OPENAL_VOID5(NAME, T0, A0, W0, T1, A1, W1, T2, A2, W2, T3, A3, W3, T4, A4, W4) \
    void NAME(T0 A0, T1 A1, T2 A2, T3 A3, T4 A4) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        packet.words[2] = (W2); packet.words[3] = (W3); packet.words[4] = (W4); \
        LC32_OPENAL_CALL(NAME); \
    }

#define LC32_OPENAL_RET0(RETURN, NAME) \
    RETURN NAME(void) { \
        LC32_OPENAL_PACKET(); LC32_OPENAL_CALL(NAME); return (RETURN)packet.words[0]; \
    }

#define LC32_OPENAL_RET1(RETURN, NAME, T0, A0, W0) \
    RETURN NAME(T0 A0) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); LC32_OPENAL_CALL(NAME); \
        return (RETURN)packet.words[0]; \
    }

#define LC32_OPENAL_RET2(RETURN, NAME, T0, A0, W0, T1, A1, W1) \
    RETURN NAME(T0 A0, T1 A1) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        LC32_OPENAL_CALL(NAME); return (RETURN)packet.words[0]; \
    }

#define LC32_OPENAL_PTRRET0(RETURN, NAME) \
    RETURN NAME(void) { \
        LC32_OPENAL_PACKET(); LC32_OPENAL_CALL(NAME); \
        return (RETURN)(uintptr_t)packet.words[0]; \
    }

#define LC32_OPENAL_PTRRET1(RETURN, NAME, T0, A0, W0) \
    RETURN NAME(T0 A0) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); LC32_OPENAL_CALL(NAME); \
        return (RETURN)(uintptr_t)packet.words[0]; \
    }

#define LC32_OPENAL_PTRRET2(RETURN, NAME, T0, A0, W0, T1, A1, W1) \
    RETURN NAME(T0 A0, T1 A1) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        LC32_OPENAL_CALL(NAME); return (RETURN)(uintptr_t)packet.words[0]; \
    }

#define LC32_OPENAL_PTRRET4(RETURN, NAME, T0, A0, W0, T1, A1, W1, T2, A2, W2, T3, A3, W3) \
    RETURN NAME(T0 A0, T1 A1, T2 A2, T3 A3) { \
        LC32_OPENAL_PACKET(); packet.words[0] = (W0); packet.words[1] = (W1); \
        packet.words[2] = (W2); packet.words[3] = (W3); LC32_OPENAL_CALL(NAME); \
        return (RETURN)(uintptr_t)packet.words[0]; \
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_OPENAL_VOID1(alEnable, ALenum, capability, LC32_OPENAL_WORD(capability))
LC32_OPENAL_VOID1(alDisable, ALenum, capability, LC32_OPENAL_WORD(capability))
LC32_OPENAL_RET1(ALboolean, alIsEnabled, ALenum, capability, LC32_OPENAL_WORD(capability))

const ALchar *alGetString(ALenum param) {
    /* Expose only the extension whose guest entry point is implemented below. */
    if (param == AL_EXTENSIONS) {
        return "AL_EXT_STATIC_BUFFER";
    }
    return LC32OpenALCopyString(LC32_OPENAL_OP_alGetString,
                                LC32_OPENAL_WORD(param), 0, 1,
                                &LC32OpenALALStringBuffer);
}

LC32_OPENAL_VOID2(alGetBooleanv, ALenum, param, LC32_OPENAL_WORD(param), ALboolean *, data, LC32_OPENAL_PTR(data))
LC32_OPENAL_VOID2(alGetIntegerv, ALenum, param, LC32_OPENAL_WORD(param), ALint *, data, LC32_OPENAL_PTR(data))
LC32_OPENAL_VOID2(alGetFloatv, ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, data, LC32_OPENAL_PTR(data))
LC32_OPENAL_VOID2(alGetDoublev, ALenum, param, LC32_OPENAL_WORD(param), ALdouble *, data, LC32_OPENAL_PTR(data))
LC32_OPENAL_RET1(ALboolean, alGetBoolean, ALenum, param, LC32_OPENAL_WORD(param))
LC32_OPENAL_RET1(ALint, alGetInteger, ALenum, param, LC32_OPENAL_WORD(param))

ALfloat alGetFloat(ALenum param) {
    LC32_OPENAL_PACKET();
    packet.words[0] = LC32_OPENAL_WORD(param);
    LC32_OPENAL_CALL(alGetFloat);
    return LC32OpenALFloatResult(packet.words[0]);
}

ALdouble alGetDouble(ALenum param) {
    LC32_OPENAL_PACKET();
    packet.words[0] = LC32_OPENAL_WORD(param);
    LC32_OPENAL_CALL(alGetDouble);
    return LC32OpenALDoubleResult(packet.words[0], packet.words[1]);
}

LC32_OPENAL_RET0(ALenum, alGetError)

ALboolean alIsExtensionPresent(const ALchar *extname) {
    return extname && strcmp(extname, "AL_EXT_STATIC_BUFFER") == 0;
}

void *alGetProcAddress(const ALchar *fname) {
    return LC32OpenALLookupALProc(fname);
}

LC32_OPENAL_RET1(ALenum, alGetEnumValue, const ALchar *, ename, LC32_OPENAL_PTR(ename))

LC32_OPENAL_VOID2(alListenerf, ALenum, param, LC32_OPENAL_WORD(param), ALfloat, value, LC32_OPENAL_FLOAT(value))
LC32_OPENAL_VOID4(alListener3f, ALenum, param, LC32_OPENAL_WORD(param), ALfloat, value1, LC32_OPENAL_FLOAT(value1), ALfloat, value2, LC32_OPENAL_FLOAT(value2), ALfloat, value3, LC32_OPENAL_FLOAT(value3))
LC32_OPENAL_VOID2(alListenerfv, ALenum, param, LC32_OPENAL_WORD(param), const ALfloat *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID2(alListeneri, ALenum, param, LC32_OPENAL_WORD(param), ALint, value, LC32_OPENAL_WORD(value))
LC32_OPENAL_VOID4(alListener3i, ALenum, param, LC32_OPENAL_WORD(param), ALint, value1, LC32_OPENAL_WORD(value1), ALint, value2, LC32_OPENAL_WORD(value2), ALint, value3, LC32_OPENAL_WORD(value3))
LC32_OPENAL_VOID2(alListeneriv, ALenum, param, LC32_OPENAL_WORD(param), const ALint *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID2(alGetListenerf, ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, value, LC32_OPENAL_PTR(value))
LC32_OPENAL_VOID4(alGetListener3f, ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, value1, LC32_OPENAL_PTR(value1), ALfloat *, value2, LC32_OPENAL_PTR(value2), ALfloat *, value3, LC32_OPENAL_PTR(value3))
LC32_OPENAL_VOID2(alGetListenerfv, ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID2(alGetListeneri, ALenum, param, LC32_OPENAL_WORD(param), ALint *, value, LC32_OPENAL_PTR(value))
LC32_OPENAL_VOID4(alGetListener3i, ALenum, param, LC32_OPENAL_WORD(param), ALint *, value1, LC32_OPENAL_PTR(value1), ALint *, value2, LC32_OPENAL_PTR(value2), ALint *, value3, LC32_OPENAL_PTR(value3))
LC32_OPENAL_VOID2(alGetListeneriv, ALenum, param, LC32_OPENAL_WORD(param), ALint *, values, LC32_OPENAL_PTR(values))

LC32_OPENAL_VOID2(alGenSources, ALsizei, n, LC32_OPENAL_WORD(n), ALuint *, sources, LC32_OPENAL_PTR(sources))
LC32_OPENAL_VOID2(alDeleteSources, ALsizei, n, LC32_OPENAL_WORD(n), const ALuint *, sources, LC32_OPENAL_PTR(sources))
LC32_OPENAL_RET1(ALboolean, alIsSource, ALuint, sid, LC32_OPENAL_WORD(sid))
LC32_OPENAL_VOID3(alSourcef, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat, value, LC32_OPENAL_FLOAT(value))
LC32_OPENAL_VOID5(alSource3f, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat, value1, LC32_OPENAL_FLOAT(value1), ALfloat, value2, LC32_OPENAL_FLOAT(value2), ALfloat, value3, LC32_OPENAL_FLOAT(value3))
LC32_OPENAL_VOID3(alSourcefv, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), const ALfloat *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID3(alSourcei, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALint, value, LC32_OPENAL_WORD(value))
LC32_OPENAL_VOID5(alSource3i, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALint, value1, LC32_OPENAL_WORD(value1), ALint, value2, LC32_OPENAL_WORD(value2), ALint, value3, LC32_OPENAL_WORD(value3))
LC32_OPENAL_VOID3(alSourceiv, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), const ALint *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID3(alGetSourcef, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, value, LC32_OPENAL_PTR(value))
LC32_OPENAL_VOID5(alGetSource3f, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, value1, LC32_OPENAL_PTR(value1), ALfloat *, value2, LC32_OPENAL_PTR(value2), ALfloat *, value3, LC32_OPENAL_PTR(value3))
LC32_OPENAL_VOID3(alGetSourcefv, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID3(alGetSourcei, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALint *, value, LC32_OPENAL_PTR(value))
LC32_OPENAL_VOID5(alGetSource3i, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALint *, value1, LC32_OPENAL_PTR(value1), ALint *, value2, LC32_OPENAL_PTR(value2), ALint *, value3, LC32_OPENAL_PTR(value3))
LC32_OPENAL_VOID3(alGetSourceiv, ALuint, sid, LC32_OPENAL_WORD(sid), ALenum, param, LC32_OPENAL_WORD(param), ALint *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID2(alSourcePlayv, ALsizei, ns, LC32_OPENAL_WORD(ns), const ALuint *, sids, LC32_OPENAL_PTR(sids))
LC32_OPENAL_VOID2(alSourceStopv, ALsizei, ns, LC32_OPENAL_WORD(ns), const ALuint *, sids, LC32_OPENAL_PTR(sids))
LC32_OPENAL_VOID2(alSourceRewindv, ALsizei, ns, LC32_OPENAL_WORD(ns), const ALuint *, sids, LC32_OPENAL_PTR(sids))
LC32_OPENAL_VOID2(alSourcePausev, ALsizei, ns, LC32_OPENAL_WORD(ns), const ALuint *, sids, LC32_OPENAL_PTR(sids))
LC32_OPENAL_VOID1(alSourcePlay, ALuint, sid, LC32_OPENAL_WORD(sid))
LC32_OPENAL_VOID1(alSourceStop, ALuint, sid, LC32_OPENAL_WORD(sid))
LC32_OPENAL_VOID1(alSourceRewind, ALuint, sid, LC32_OPENAL_WORD(sid))
LC32_OPENAL_VOID1(alSourcePause, ALuint, sid, LC32_OPENAL_WORD(sid))
LC32_OPENAL_VOID3(alSourceQueueBuffers, ALuint, sid, LC32_OPENAL_WORD(sid), ALsizei, numEntries, LC32_OPENAL_WORD(numEntries), const ALuint *, bids, LC32_OPENAL_PTR(bids))
LC32_OPENAL_VOID3(alSourceUnqueueBuffers, ALuint, sid, LC32_OPENAL_WORD(sid), ALsizei, numEntries, LC32_OPENAL_WORD(numEntries), ALuint *, bids, LC32_OPENAL_PTR(bids))

LC32_OPENAL_VOID2(alGenBuffers, ALsizei, n, LC32_OPENAL_WORD(n), ALuint *, buffers, LC32_OPENAL_PTR(buffers))
LC32_OPENAL_VOID2(alDeleteBuffers, ALsizei, n, LC32_OPENAL_WORD(n), const ALuint *, buffers, LC32_OPENAL_PTR(buffers))
LC32_OPENAL_RET1(ALboolean, alIsBuffer, ALuint, bid, LC32_OPENAL_WORD(bid))
LC32_OPENAL_VOID5(alBufferData, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, format, LC32_OPENAL_WORD(format), const ALvoid *, data, LC32_OPENAL_PTR(data), ALsizei, size, LC32_OPENAL_WORD(size), ALsizei, freq, LC32_OPENAL_WORD(freq))
LC32_OPENAL_VOID3(alBufferf, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat, value, LC32_OPENAL_FLOAT(value))
LC32_OPENAL_VOID5(alBuffer3f, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat, value1, LC32_OPENAL_FLOAT(value1), ALfloat, value2, LC32_OPENAL_FLOAT(value2), ALfloat, value3, LC32_OPENAL_FLOAT(value3))
LC32_OPENAL_VOID3(alBufferfv, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), const ALfloat *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID3(alBufferi, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALint, value, LC32_OPENAL_WORD(value))
LC32_OPENAL_VOID5(alBuffer3i, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALint, value1, LC32_OPENAL_WORD(value1), ALint, value2, LC32_OPENAL_WORD(value2), ALint, value3, LC32_OPENAL_WORD(value3))
LC32_OPENAL_VOID3(alBufferiv, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), const ALint *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID3(alGetBufferf, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, value, LC32_OPENAL_PTR(value))
LC32_OPENAL_VOID5(alGetBuffer3f, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, value1, LC32_OPENAL_PTR(value1), ALfloat *, value2, LC32_OPENAL_PTR(value2), ALfloat *, value3, LC32_OPENAL_PTR(value3))
LC32_OPENAL_VOID3(alGetBufferfv, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALfloat *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID3(alGetBufferi, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALint *, value, LC32_OPENAL_PTR(value))
LC32_OPENAL_VOID5(alGetBuffer3i, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALint *, value1, LC32_OPENAL_PTR(value1), ALint *, value2, LC32_OPENAL_PTR(value2), ALint *, value3, LC32_OPENAL_PTR(value3))
LC32_OPENAL_VOID3(alGetBufferiv, ALuint, bid, LC32_OPENAL_WORD(bid), ALenum, param, LC32_OPENAL_WORD(param), ALint *, values, LC32_OPENAL_PTR(values))
LC32_OPENAL_VOID1(alDopplerFactor, ALfloat, value, LC32_OPENAL_FLOAT(value))
LC32_OPENAL_VOID1(alDopplerVelocity, ALfloat, value, LC32_OPENAL_FLOAT(value))
LC32_OPENAL_VOID1(alSpeedOfSound, ALfloat, value, LC32_OPENAL_FLOAT(value))
LC32_OPENAL_VOID1(alDistanceModel, ALenum, distanceModel, LC32_OPENAL_WORD(distanceModel))

LC32_OPENAL_PTRRET2(ALCcontext *, alcCreateContext, ALCdevice *, device, LC32_OPENAL_PTR(device), const ALCint *, attrlist, LC32_OPENAL_PTR(attrlist))
LC32_OPENAL_RET1(ALCboolean, alcMakeContextCurrent, ALCcontext *, context, LC32_OPENAL_PTR(context))
LC32_OPENAL_VOID1(alcProcessContext, ALCcontext *, context, LC32_OPENAL_PTR(context))
LC32_OPENAL_VOID1(alcSuspendContext, ALCcontext *, context, LC32_OPENAL_PTR(context))
LC32_OPENAL_VOID1(alcDestroyContext, ALCcontext *, context, LC32_OPENAL_PTR(context))
LC32_OPENAL_PTRRET0(ALCcontext *, alcGetCurrentContext)
LC32_OPENAL_PTRRET1(ALCdevice *, alcGetContextsDevice, ALCcontext *, context, LC32_OPENAL_PTR(context))
LC32_OPENAL_PTRRET1(ALCdevice *, alcOpenDevice, const ALCchar *, devicename, LC32_OPENAL_PTR(devicename))
LC32_OPENAL_RET1(ALCboolean, alcCloseDevice, ALCdevice *, device, LC32_OPENAL_PTR(device))
LC32_OPENAL_RET1(ALCenum, alcGetError, ALCdevice *, device, LC32_OPENAL_PTR(device))

ALCboolean alcIsExtensionPresent(ALCdevice *device, const ALCchar *extname) {
    (void)device;
    (void)extname;
    return ALC_FALSE;
}

void *alcGetProcAddress(ALCdevice *device, const ALCchar *funcname) {
    (void)device;
    return LC32OpenALLookupALCProc(funcname);
}

LC32_OPENAL_RET2(ALCenum, alcGetEnumValue, ALCdevice *, device, LC32_OPENAL_PTR(device), const ALCchar *, enumname, LC32_OPENAL_PTR(enumname))

const ALCchar *alcGetString(ALCdevice *device, ALCenum param) {
    /* No ALC extension entry points are bridged yet, so advertise none. */
    if (param == ALC_EXTENSIONS) {
        return "";
    }
    return LC32OpenALCopyString(LC32_OPENAL_OP_alcGetString,
                                LC32_OPENAL_PTR(device), LC32_OPENAL_WORD(param), 2,
                                &LC32OpenALALCStringBuffer);
}

LC32_OPENAL_VOID4(alcGetIntegerv, ALCdevice *, device, LC32_OPENAL_PTR(device), ALCenum, param, LC32_OPENAL_WORD(param), ALCsizei, size, LC32_OPENAL_WORD(size), ALCint *, data, LC32_OPENAL_PTR(data))
LC32_OPENAL_PTRRET4(ALCdevice *, alcCaptureOpenDevice, const ALCchar *, devicename, LC32_OPENAL_PTR(devicename), ALCuint, frequency, LC32_OPENAL_WORD(frequency), ALCenum, format, LC32_OPENAL_WORD(format), ALCsizei, buffersize, LC32_OPENAL_WORD(buffersize))
LC32_OPENAL_RET1(ALCboolean, alcCaptureCloseDevice, ALCdevice *, device, LC32_OPENAL_PTR(device))
LC32_OPENAL_VOID1(alcCaptureStart, ALCdevice *, device, LC32_OPENAL_PTR(device))
LC32_OPENAL_VOID1(alcCaptureStop, ALCdevice *, device, LC32_OPENAL_PTR(device))
LC32_OPENAL_VOID3(alcCaptureSamples, ALCdevice *, device, LC32_OPENAL_PTR(device), ALCvoid *, buffer, LC32_OPENAL_PTR(buffer), ALCsizei, samples, LC32_OPENAL_WORD(samples))

/* The extension promises static storage; the bridge deliberately copies it. */
void alBufferDataStatic(ALint bid, ALenum format, const ALvoid *data,
                        ALsizei size, ALsizei freq) {
    alBufferData((ALuint)bid, format, data, size, freq);
}

#define LC32_OPENAL_PROC(NAME) \
    if (strcmp(name, #NAME) == 0) return (void *)(uintptr_t)&NAME

static void *LC32OpenALLookupALProc(const char *name) {
    if (!name) return NULL;
    LC32_OPENAL_PROC(alEnable);
    LC32_OPENAL_PROC(alDisable);
    LC32_OPENAL_PROC(alIsEnabled);
    LC32_OPENAL_PROC(alGetString);
    LC32_OPENAL_PROC(alGetBooleanv);
    LC32_OPENAL_PROC(alGetIntegerv);
    LC32_OPENAL_PROC(alGetFloatv);
    LC32_OPENAL_PROC(alGetDoublev);
    LC32_OPENAL_PROC(alGetBoolean);
    LC32_OPENAL_PROC(alGetInteger);
    LC32_OPENAL_PROC(alGetFloat);
    LC32_OPENAL_PROC(alGetDouble);
    LC32_OPENAL_PROC(alGetError);
    LC32_OPENAL_PROC(alIsExtensionPresent);
    LC32_OPENAL_PROC(alGetProcAddress);
    LC32_OPENAL_PROC(alGetEnumValue);
    LC32_OPENAL_PROC(alListenerf);
    LC32_OPENAL_PROC(alListener3f);
    LC32_OPENAL_PROC(alListenerfv);
    LC32_OPENAL_PROC(alListeneri);
    LC32_OPENAL_PROC(alListener3i);
    LC32_OPENAL_PROC(alListeneriv);
    LC32_OPENAL_PROC(alGetListenerf);
    LC32_OPENAL_PROC(alGetListener3f);
    LC32_OPENAL_PROC(alGetListenerfv);
    LC32_OPENAL_PROC(alGetListeneri);
    LC32_OPENAL_PROC(alGetListener3i);
    LC32_OPENAL_PROC(alGetListeneriv);
    LC32_OPENAL_PROC(alGenSources);
    LC32_OPENAL_PROC(alDeleteSources);
    LC32_OPENAL_PROC(alIsSource);
    LC32_OPENAL_PROC(alSourcef);
    LC32_OPENAL_PROC(alSource3f);
    LC32_OPENAL_PROC(alSourcefv);
    LC32_OPENAL_PROC(alSourcei);
    LC32_OPENAL_PROC(alSource3i);
    LC32_OPENAL_PROC(alSourceiv);
    LC32_OPENAL_PROC(alGetSourcef);
    LC32_OPENAL_PROC(alGetSource3f);
    LC32_OPENAL_PROC(alGetSourcefv);
    LC32_OPENAL_PROC(alGetSourcei);
    LC32_OPENAL_PROC(alGetSource3i);
    LC32_OPENAL_PROC(alGetSourceiv);
    LC32_OPENAL_PROC(alSourcePlayv);
    LC32_OPENAL_PROC(alSourceStopv);
    LC32_OPENAL_PROC(alSourceRewindv);
    LC32_OPENAL_PROC(alSourcePausev);
    LC32_OPENAL_PROC(alSourcePlay);
    LC32_OPENAL_PROC(alSourceStop);
    LC32_OPENAL_PROC(alSourceRewind);
    LC32_OPENAL_PROC(alSourcePause);
    LC32_OPENAL_PROC(alSourceQueueBuffers);
    LC32_OPENAL_PROC(alSourceUnqueueBuffers);
    LC32_OPENAL_PROC(alGenBuffers);
    LC32_OPENAL_PROC(alDeleteBuffers);
    LC32_OPENAL_PROC(alIsBuffer);
    LC32_OPENAL_PROC(alBufferData);
    LC32_OPENAL_PROC(alBufferf);
    LC32_OPENAL_PROC(alBuffer3f);
    LC32_OPENAL_PROC(alBufferfv);
    LC32_OPENAL_PROC(alBufferi);
    LC32_OPENAL_PROC(alBuffer3i);
    LC32_OPENAL_PROC(alBufferiv);
    LC32_OPENAL_PROC(alGetBufferf);
    LC32_OPENAL_PROC(alGetBuffer3f);
    LC32_OPENAL_PROC(alGetBufferfv);
    LC32_OPENAL_PROC(alGetBufferi);
    LC32_OPENAL_PROC(alGetBuffer3i);
    LC32_OPENAL_PROC(alGetBufferiv);
    LC32_OPENAL_PROC(alDopplerFactor);
    LC32_OPENAL_PROC(alDopplerVelocity);
    LC32_OPENAL_PROC(alSpeedOfSound);
    LC32_OPENAL_PROC(alDistanceModel);
    LC32_OPENAL_PROC(alBufferDataStatic);
    return NULL;
}

static void *LC32OpenALLookupALCProc(const char *name) {
    if (!name) return NULL;
    LC32_OPENAL_PROC(alcCreateContext);
    LC32_OPENAL_PROC(alcMakeContextCurrent);
    LC32_OPENAL_PROC(alcProcessContext);
    LC32_OPENAL_PROC(alcSuspendContext);
    LC32_OPENAL_PROC(alcDestroyContext);
    LC32_OPENAL_PROC(alcGetCurrentContext);
    LC32_OPENAL_PROC(alcGetContextsDevice);
    LC32_OPENAL_PROC(alcOpenDevice);
    LC32_OPENAL_PROC(alcCloseDevice);
    LC32_OPENAL_PROC(alcGetError);
    LC32_OPENAL_PROC(alcIsExtensionPresent);
    LC32_OPENAL_PROC(alcGetProcAddress);
    LC32_OPENAL_PROC(alcGetEnumValue);
    LC32_OPENAL_PROC(alcGetString);
    LC32_OPENAL_PROC(alcGetIntegerv);
    LC32_OPENAL_PROC(alcCaptureOpenDevice);
    LC32_OPENAL_PROC(alcCaptureCloseDevice);
    LC32_OPENAL_PROC(alcCaptureStart);
    LC32_OPENAL_PROC(alcCaptureStop);
    LC32_OPENAL_PROC(alcCaptureSamples);
    return NULL;
}

#pragma clang diagnostic pop
