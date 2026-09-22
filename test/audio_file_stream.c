#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(value, label) do { \
    const int passed = !!(value); \
    printf("%s %s\n", passed ? "PASS" : "FAIL", label); \
    if(!passed) failures++; \
} while(0)

enum { frames = 512, pcmBytes = frames * 2, waveBytes = 44 + pcmBytes };
static unsigned char wave[waveBytes];

typedef struct {
    AudioFileStreamID stream;
    AudioStreamBasicDescription format;
    unsigned char output[pcmBytes];
    UInt32 outputSize;
    unsigned properties, packets, descriptions;
    int gotFormat, closeInCallback, closed;
    uint32_t cookie;
} State;

static void put16(unsigned char *p, uint16_t v) {
    p[0] = v; p[1] = v >> 8;
}
static void put32(unsigned char *p, uint32_t v) {
    put16(p, v); put16(p + 2, v >> 16);
}

static void property_callback(void *data, AudioFileStreamID stream,
        AudioFileStreamPropertyID property, AudioFileStreamPropertyFlags *flags) {
    State *s = data;
    CHECK(s->cookie == 0x1234abcd && s->stream == stream,
          "stream-property-callback-client-and-handle");
    s->properties++;
    // Exercises the writable ARM32 pointer supplied to the callback.
    *flags |= kAudioFileStreamPropertyFlag_CacheProperty;
    if(s->closeInCallback) {
        OSStatus status = AudioFileStreamClose(stream);
        CHECK(status == noErr, "stream-close-inside-property-callback");
        s->closed = 1;
        return;
    }
    if(property == kAudioFileStreamProperty_DataFormat) {
        struct { Boolean value; unsigned char canary[3]; } writable =
            {0xff, {0xa5, 0xa5, 0xa5}};
        UInt32 size = 0;
        OSStatus status = AudioFileStreamGetPropertyInfo(stream, property,
            &size, &writable.value);
        CHECK(status == noErr && size == sizeof(s->format),
              "stream-property-info-reentrant");
        CHECK(writable.value == 0 && writable.canary[0] == 0xa5 &&
              writable.canary[1] == 0xa5 && writable.canary[2] == 0xa5,
              "stream-property-info-Boolean-is-one-byte");
        size = sizeof(s->format);
        status = AudioFileStreamGetProperty(stream, property, &size, &s->format);
        CHECK(status == noErr && size == sizeof(s->format),
              "stream-get-format-inside-callback");
        s->gotFormat = status == noErr;
    }
}

static void packets_callback(void *data, UInt32 size, UInt32 packets,
        const void *bytes, AudioStreamPacketDescription *descriptions) {
    State *s = data;
    CHECK(s->cookie == 0x1234abcd && bytes && packets,
          "stream-packets-callback-arguments");
    s->packets++;
    if(descriptions) {
        s->descriptions++;
        for(UInt32 i = 0; i < packets; i++) {
            CHECK(descriptions[i].mStartOffset >= 0 &&
                  (uint64_t)descriptions[i].mStartOffset +
                  descriptions[i].mDataByteSize <= size,
                  "stream-packet-description-offset-and-size");
        }
    }
    if(s->outputSize + size <= sizeof(s->output))
        memcpy(s->output + s->outputSize, bytes, size);
    s->outputSize += size;
}

static int open_stream(State *s, AudioFileTypeID hint) {
    s->cookie = 0x1234abcd;
    OSStatus status = AudioFileStreamOpen(s, property_callback,
        packets_callback, hint, &s->stream);
    CHECK(status == noErr && s->stream, "stream-open");
    return status == noErr && s->stream;
}

static void test_format_list(State *s) {
    UInt32 size = 0;
    OSStatus status = AudioFileStreamGetPropertyInfo(s->stream,
        kAudioFileStreamProperty_FormatList, &size, NULL);
    if(status != noErr) {
        printf("SKIP stream-format-list: native parser status %d\n", (int)status);
        return;
    }
    CHECK(size && size % sizeof(AudioFormatListItem) == 0,
          "stream-format-list-guest-stride");
    if(size < sizeof(AudioFormatListItem)) return;
    unsigned char *list = calloc(1, size + 4);
    CHECK(list != NULL, "stream-format-list-allocation");
    if(!list) return;
    memset(list + size, 0xa5, 4);
    UInt32 capacity = size;
    status = AudioFileStreamGetProperty(s->stream,
        kAudioFileStreamProperty_FormatList, &size, list);
    CHECK(status == noErr && size <= capacity &&
          ((AudioFormatListItem *)list)->mASBD.mSampleRate == s->format.mSampleRate &&
          list[capacity] == 0xa5 && list[capacity + 3] == 0xa5,
          "stream-format-list-ABI-copy");
    free(list);
}

static void test_wave(int fragmented) {
    State s = {0};
    if(!open_stream(&s, kAudioFileWAVEType)) return;
    for(unsigned offset = 0; offset < sizeof(wave);) {
        unsigned size = fragmented ? 37 : sizeof(wave);
        if(size > sizeof(wave) - offset) size = sizeof(wave) - offset;
        OSStatus status = AudioFileStreamParseBytes(s.stream, size,
            wave + offset, 0);
        CHECK(status == noErr, "stream-parse-WAV");
        offset += size;
    }
    CHECK(s.properties && s.packets && s.gotFormat &&
          s.format.mSampleRate == 22050 && s.format.mChannelsPerFrame == 1 &&
          s.format.mBitsPerChannel == 16, "stream-WAV-format");
    CHECK(s.outputSize == pcmBytes &&
          memcmp(s.output, wave + 44, pcmBytes) == 0,
          fragmented ? "stream-fragmented-PCM-copy" : "stream-whole-PCM-copy");

    struct { UInt64 bytes; uint32_t canary; } count = {0, 0xfeedface};
    UInt32 size = sizeof(count.bytes);
    OSStatus status = AudioFileStreamGetProperty(s.stream,
        kAudioFileStreamProperty_AudioDataByteCount, &size, &count.bytes);
    CHECK(status == noErr && size == 8 && count.bytes == pcmBytes &&
          count.canary == 0xfeedface, "stream-64-bit-byte-count");

    test_format_list(&s);
    struct { AudioFramePacketTranslation value; uint32_t canary; } translation =
        {{7, 0, 0}, 0xfeedface};
    size = sizeof(translation.value);
    status = AudioFileStreamGetProperty(s.stream,
        kAudioFileStreamProperty_FrameToPacket, &size, &translation.value);
    if(status == noErr) {
        CHECK(size == sizeof(translation.value) &&
              translation.value.mPacket == 7 && translation.canary == 0xfeedface,
              "stream-frame-packet-translation-ABI");
    } else {
        printf("SKIP stream-frame-packet-translation: native status %d\n", (int)status);
    }

    AudioFileStreamSeekFlags flags = 0;
    struct { SInt64 offset; uint32_t canary; } seek = {-1, 0xfeedface};
    status = AudioFileStreamSeek(s.stream, 7, &seek.offset, &flags);
    CHECK(status == noErr && seek.offset == 14 && seek.canary == 0xfeedface,
          "stream-seek-copyback");
    flags = 0;
    status = AudioFileStreamSeek(s.stream, (SInt64)1 << 32, &seek.offset, &flags);
    CHECK(status != noErr || seek.offset == ((SInt64)1 << 33),
          "stream-seek-does-not-truncate-64-bit-offset");

    UInt32 ready = 0;
    status = AudioFileStreamSetProperty(s.stream,
        kAudioFileStreamProperty_ReadyToProducePackets, sizeof(ready), &ready);
    CHECK(status != noErr, "stream-native-read-only-property-error");
    size = sizeof(ready);
    status = AudioFileStreamGetProperty(s.stream, 'xxxx', &size, &ready);
    CHECK(status != noErr, "stream-unknown-property-error");
    status = AudioFileStreamClose(s.stream);
    CHECK(status == noErr, "stream-close");
#if defined(__arm__)
    status = AudioFileStreamClose(s.stream);
    CHECK(status != noErr, "stream-stale-token-rejected");
    status = AudioFileStreamParseBytes(s.stream, sizeof(wave), wave, 0);
    CHECK(status != noErr, "stream-parse-after-close-rejected");
#endif
}

static void *parse_on_worker(void *unused) {
    (void)unused;
    test_wave(1);
    return NULL;
}

int main(int argc, char **argv) {
    memcpy(wave, "RIFF", 4); put32(wave + 4, waveBytes - 8);
    memcpy(wave + 8, "WAVEfmt ", 8); put32(wave + 16, 16);
    put16(wave + 20, 1); put16(wave + 22, 1); put32(wave + 24, 22050);
    put32(wave + 28, 44100); put16(wave + 32, 2); put16(wave + 34, 16);
    memcpy(wave + 36, "data", 4); put32(wave + 40, pcmBytes);
    for(unsigned i = 0; i < pcmBytes; i++) wave[44 + i] = (i * 17) & 255;
    test_wave(0);
    pthread_t worker;
    int status = pthread_create(&worker, NULL, parse_on_worker, NULL);
    CHECK(status == 0, "stream-worker-thread-create");
    if(status == 0) {
        status = pthread_join(worker, NULL);
        CHECK(status == 0, "stream-worker-thread-join");
    }
#if defined(__arm__)
    State closing = {.closeInCallback = 1};
    if(open_stream(&closing, kAudioFileWAVEType)) {
        OSStatus status = AudioFileStreamParseBytes(closing.stream,
            sizeof(wave), wave, 0);
        CHECK(status == noErr && closing.closed && closing.properties == 1 &&
              closing.packets == 0, "stream-deferred-close-no-late-callbacks");
    }
#endif
    // Optional compressed fixture (e.g. ADTS) exercises non-null packet
    // descriptions and multiple callback batches without an audio output device.
    if(argc == 2) {
        FILE *file = fopen(argv[1], "rb");
        CHECK(file != NULL, "stream-compressed-fixture-open");
        State s = {0};
        if(file && open_stream(&s, kAudioFileAAC_ADTSType)) {
            unsigned char bytes[257];
            size_t size;
            while((size = fread(bytes, 1, sizeof(bytes), file))) {
                OSStatus status = AudioFileStreamParseBytes(s.stream, size, bytes, 0);
                CHECK(status == noErr, "stream-compressed-parse");
            }
            CHECK(s.packets && s.descriptions && s.gotFormat,
                  "stream-compressed-packet-descriptions");
            test_format_list(&s);
            OSStatus status = AudioFileStreamClose(s.stream);
            CHECK(status == noErr, "stream-compressed-close");
        }
        if(file) fclose(file);
    }
    printf("audio-file-stream: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures != 0;
}
