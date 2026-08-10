#include <OpenAL/OpenAL.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(CONDITION, LABEL) do {                                      \
    if (CONDITION) {                                                       \
        printf("PASS %s\n", LABEL);                                      \
    } else {                                                              \
        fprintf(stderr, "FAIL %s\n", LABEL);                            \
        failures++;                                                       \
    }                                                                     \
} while (0)

static int al_ok(const char *label) {
    ALenum error = alGetError();
    if (error == AL_NO_ERROR) {
        printf("PASS %s\n", label);
        return 1;
    }
    fprintf(stderr, "FAIL %s (OpenAL error 0x%x)\n", label, error);
    failures++;
    return 0;
}

int main(void) {
    void *coreProc = alGetProcAddress("alGetError");
    void *alcCoreProc = alcGetProcAddress(NULL, "alcGetError");
    alBufferDataStaticProcPtr staticBuffer =
        (alBufferDataStaticProcPtr)alGetProcAddress("alBufferDataStatic");
    CHECK(coreProc == (void *)(uintptr_t)&alGetError,
          "al-core-proc-address-is-guest");
    CHECK(alcCoreProc == (void *)(uintptr_t)&alcGetError,
          "alc-core-proc-address-is-guest");
    CHECK(staticBuffer != NULL, "static-buffer-extension-proc");
    CHECK(alIsExtensionPresent("AL_EXT_STATIC_BUFFER") == AL_TRUE,
          "static-buffer-extension-advertised");
    CHECK(alcGetCurrentContext() == NULL, "initial-current-context");

    const ALCchar *defaultDevice =
        alcGetString(NULL, ALC_DEFAULT_DEVICE_SPECIFIER);
    CHECK(defaultDevice != NULL, "alc-string-guest-buffer");
    CHECK(alGetEnumValue("AL_GAIN") == AL_GAIN, "al-enum-name-copy");
    CHECK(alcGetEnumValue(NULL, "ALC_FREQUENCY") == ALC_FREQUENCY,
          "alc-enum-name-copy");

    ALCdevice *device = alcOpenDevice(NULL);
    if (device == NULL) {
        ALCenum error = alcGetError(NULL);
        printf("SKIP OpenAL default device unavailable (ALC error 0x%x)\n",
               error);
        return failures == 0 ? 0 : 1;
    }

    const ALCint attributes[] = {
        ALC_FREQUENCY, 22050,
        0
    };
    ALCcontext *context = alcCreateContext(device, attributes);
    CHECK(context != NULL, "create-context");
    if (context == NULL) {
        alcCloseDevice(device);
        return 1;
    }

    CHECK(alcMakeContextCurrent(context) == ALC_TRUE,
          "make-context-current");
    CHECK(alcGetCurrentContext() == context, "current-context-token");
    CHECK(alcMakeContextCurrent(
              (ALCcontext *)(uintptr_t)UINT32_C(0x12345678)) == ALC_FALSE,
          "reject-invalid-context-token");
    CHECK(alcGetCurrentContext() == context,
          "invalid-context-preserves-current");
    CHECK(alcGetContextsDevice(context) == device,
          "context-device-token");

    const ALchar *version = alGetString(AL_VERSION);
    const ALchar *vendor = alGetString(AL_VENDOR);
    CHECK(version != NULL && version[0] != '\0', "version-string-copy");
    CHECK(vendor != NULL && vendor[0] != '\0', "vendor-string-copy");

    ALuint buffer = 0;
    ALuint source = 0;
    alGenBuffers(1, &buffer);
    alGenSources(1, &source);
    if (!al_ok("generate-buffer-source")) goto cleanup;
    CHECK(buffer != 0 && alIsBuffer(buffer), "buffer-id-roundtrip");
    CHECK(source != 0 && alIsSource(source), "source-id-roundtrip");

    int16_t pcm[256];
    for (size_t i = 0; i < sizeof(pcm) / sizeof(pcm[0]); i++) {
        pcm[i] = (int16_t)((i & 16) ? 1200 : -1200);
    }
    alBufferData(buffer, AL_FORMAT_MONO16, pcm, sizeof(pcm), 22050);
    if (!al_ok("buffer-data-copy")) goto cleanup;

    ALint size = 0;
    ALint frequency = 0;
    ALint bits = 0;
    ALint channels = 0;
    alGetBufferi(buffer, AL_SIZE, &size);
    alGetBufferi(buffer, AL_FREQUENCY, &frequency);
    alGetBufferi(buffer, AL_BITS, &bits);
    alGetBufferi(buffer, AL_CHANNELS, &channels);
    CHECK(size == (ALint)sizeof(pcm), "buffer-size-copyback");
    CHECK(frequency == 22050, "buffer-frequency-copyback");
    CHECK(bits == 16 && channels == 1, "buffer-format-copyback");

    alSource3f(source, AL_POSITION, 1.25f, -2.5f, 3.75f);
    ALfloat x = 0.0f;
    ALfloat y = 0.0f;
    ALfloat z = 0.0f;
    alGetSource3f(source, AL_POSITION, &x, &y, &z);
    CHECK(fabsf(x - 1.25f) < 0.0001f &&
          fabsf(y + 2.5f) < 0.0001f &&
          fabsf(z - 3.75f) < 0.0001f,
          "source-float-triplet-copyback");

    const ALfloat orientation[6] = {0.0f, 0.0f, -1.0f,
                                    0.0f, 1.0f, 0.0f};
    ALfloat orientationOut[6] = {};
    alListenerfv(AL_ORIENTATION, orientation);
    alGetListenerfv(AL_ORIENTATION, orientationOut);
    CHECK(memcmp(orientation, orientationOut, sizeof(orientation)) == 0,
          "listener-six-float-vector");

    alDopplerFactor(1.25f);
    ALdouble doppler = alGetDouble(AL_DOPPLER_FACTOR);
    CHECK(fabs(doppler - 1.25) < 0.000001, "double-return");

    alSourcei(source, AL_BUFFER, (ALint)buffer);
    alSourcePlay(source);
    ALint state = 0;
    alGetSourcei(source, AL_SOURCE_STATE, &state);
    CHECK(state == AL_PLAYING || state == AL_STOPPED,
          "source-play-state");
    alSourceStop(source);
    alSourcei(source, AL_BUFFER, AL_NONE);
    al_ok("source-play-stop");

    if (staticBuffer != NULL) {
        staticBuffer((ALint)buffer, AL_FORMAT_MONO16,
                     pcm, sizeof(pcm), 22050);
        al_ok("static-buffer-copy-semantics");
    }

cleanup:
    if (source != 0) alDeleteSources(1, &source);
    if (buffer != 0) alDeleteBuffers(1, &buffer);
    alcMakeContextCurrent(NULL);
    alcDestroyContext(context);
    CHECK(alcCloseDevice(device) == ALC_TRUE, "close-device");

    printf("OpenAL bridge smoke: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
