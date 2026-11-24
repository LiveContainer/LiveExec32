#include <OpenAL/OpenAL.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static unsigned checks, failures;
#define CHECK(value, name) do { ++checks; if(!(value)) { ++failures; \
    printf("FAIL %s\n", name); } else printf("PASS %s\n", name); } while(0)
static ALint property(ALuint source, ALenum name) {
    ALint value = -1;
    alGetSourcei(source, name, &value);
    return value;
}
static void wait_ms(unsigned ms) {
    struct timespec duration = {ms / 1000, (ms % 1000) * 1000000L};
    while(nanosleep(&duration, &duration)) {}
}

int main(void) {
    ALCdevice *device = alcOpenDevice(NULL);
    ALCcontext *context = device ? alcCreateContext(device, NULL) : NULL;
    if(!context || !alcMakeContextCurrent(context)) return 2;
    CHECK(!alcCloseDevice(device), "live-context-prevents-device-close");
    ALuint source = 0, buffers[3] = {0};
    alGenSources(1, &source);
    alGenBuffers(3, buffers);
    int16_t pcm[800] = {0}; // 100 ms per buffer
    for(unsigned i = 0; i < 3; ++i)
        alBufferData(buffers[i], AL_FORMAT_MONO16, pcm, sizeof(pcm), 8000);
    CHECK(alGetError() == AL_NO_ERROR, "create-pcm-and-source");
    alSourceQueueBuffers(source, 2, buffers);
    CHECK(property(source, AL_SOURCE_TYPE) == AL_STREAMING, "streaming-type");
    CHECK(property(source, AL_BUFFERS_QUEUED) == 2, "queued-count");
    ALuint invalidBatch[] = {source, UINT32_MAX};
    alDeleteSources(2, invalidBatch);
    CHECK(alGetError() == AL_INVALID_NAME && alIsSource(source), "delete-source-batch-atomic");
    ALuint removed[2] = {0};
    alSourceUnqueueBuffers(source, 1, removed);
    CHECK(alGetError() == AL_INVALID_VALUE && property(source, AL_BUFFERS_QUEUED) == 2,
          "reject-unprocessed-unqueue-atomically");
    alSourcePlay(source);
    alSourcePause(source);
    CHECK(property(source, AL_SOURCE_STATE) == AL_PAUSED, "pause-state");
    wait_ms(250);
    CHECK(property(source, AL_BUFFERS_PROCESSED) == 0, "pause-preserves-queue");
    alSourcePlay(source);
    wait_ms(350);
    CHECK(property(source, AL_SOURCE_STATE) == AL_STOPPED, "stream-finishes-without-polling");
    CHECK(property(source, AL_BUFFERS_PROCESSED) == 2, "processed-count");
    alDeleteBuffers(1, buffers);
    CHECK(alGetError() == AL_INVALID_OPERATION && alIsBuffer(buffers[0]), "attached-buffer-retained");
    alSourceUnqueueBuffers(source, 2, removed);
    CHECK(removed[0] == buffers[0] && removed[1] == buffers[1], "fifo-unqueue");
    CHECK(property(source, AL_BUFFERS_QUEUED) == 0, "empty-queue");
    alSourceQueueBuffers(source, 1, buffers + 2);
    alSourcePlay(source);
    alSourceStop(source);
    CHECK(property(source, AL_BUFFERS_PROCESSED) == 1, "stop-processes-queue");
    alSourceRewind(source);
    CHECK(property(source, AL_SOURCE_STATE) == AL_INITIAL &&
          property(source, AL_BUFFERS_PROCESSED) == 0, "rewind-resets-queue");
    alSourcei(source, AL_BUFFER, 0);
    alSourcei(source, AL_BUFFER, buffers[0]);
    alSourcei(source, AL_LOOPING, AL_TRUE);
    alSourcePlay(source);
    wait_ms(250);
    CHECK(property(source, AL_SOURCE_STATE) == AL_PLAYING &&
          property(source, AL_BUFFERS_PROCESSED) == 0, "looping-does-not-finish");
    alSourcei(source, AL_BUFFER, buffers[1]);
    CHECK(alGetError() == AL_INVALID_OPERATION && property(source, AL_BUFFER) == (ALint)buffers[0],
          "cannot-rebind-playing-source");
    alSourceStop(source);
    alSourcei(source, AL_LOOPING, AL_FALSE);
    alSourcef(source, AL_PITCH, 0.1f);
    alSourcePlay(source);
    alcSuspendContext(context);
    ALfloat before = 0, after = 0;
    alGetSourcef(source, AL_SEC_OFFSET, &before);
    wait_ms(150);
    alGetSourcef(source, AL_SEC_OFFSET, &after);
    CHECK(fabsf(after - before) < 0.01f, "suspended-context-clock-stops");
    alcProcessContext(context);
    alSourcePause(source);
    alSourcef(source, AL_SEC_OFFSET, 0.05f);
    CHECK(property(source, AL_SAMPLE_OFFSET) == 400, "sample-offset-conversion");
    CHECK(property(source, AL_BYTE_OFFSET) == 800, "byte-offset-conversion");
    alSourceStop(source);
    alSourcef(source, AL_SEC_OFFSET, 0.05f);
    alSourcePlay(source);
    alSourcePause(source);
    alGetSourcef(source, AL_SEC_OFFSET, &after);
    CHECK(after >= 0.05f && after < 0.09f, "stopped-seek-applied-on-play");
    alSourcef(source, AL_GAIN, NAN);
    CHECK(alGetError() == AL_INVALID_VALUE && alGetError() == AL_NO_ERROR, "error-consumed-once");
    alSourcef(source, AL_PITCH, -1);
    alSourcei(UINT32_MAX, AL_BUFFER, 0);
    CHECK(alGetError() == AL_INVALID_VALUE && alGetError() == AL_NO_ERROR, "first-error-sticky");
    alSourceStop(source);
    alSourcei(source, AL_BUFFER, 0);
    alSourceQueueBuffers(source, 1, buffers);
    alBufferData(buffers[1], AL_FORMAT_MONO16, pcm, sizeof(pcm), 16000);
    alSourceQueueBuffers(source, 1, buffers + 1);
    CHECK(alGetError() == AL_INVALID_OPERATION && property(source, AL_BUFFERS_QUEUED) == 1,
          "mismatched-queue-format-rejected");

    ALCcontext *other = alcCreateContext(device, NULL);
    CHECK(other && alcMakeContextCurrent(other), "second-context");
    CHECK(!alIsSource(source) && alIsBuffer(buffers[0]), "sources-local-buffers-device-shared");
    ALuint otherSource = 0;
    alGenSources(1, &otherSource);
    alSourcei(otherSource, AL_BUFFER, buffers[0]);
    alDeleteSources(1, &otherSource);
    alcMakeContextCurrent(context);
    alcDestroyContext(other);
    CHECK(!alcMakeContextCurrent(other) && alcGetCurrentContext() == context, "stale-context-rejected");
    alDeleteSources(1, &source);
    CHECK(!alIsSource(source), "deleted-source-invalid");
    alDeleteBuffers(3, buffers);
    CHECK(!alIsBuffer(buffers[0]), "deleted-buffer-invalid");
    CHECK(alGetError() == AL_NO_ERROR, "final-al-error");
    alcMakeContextCurrent(NULL);
    alcDestroyContext(context);
    CHECK(alcCloseDevice(device), "close-device");
    printf("OpenAL streaming: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
