#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int report_status(const char *name, OSStatus status) {
    const int passed = status == noErr;
    printf("%s: %s (%d)\n", name, passed ? "PASS" : "FAIL",
        (int)status);
    return passed;
}

int main(int argc, char **argv) {
    if(argc != 2) {
        fprintf(stderr, "usage: %s output.caf\n", argv[0]);
        return 2;
    }

    const UInt8 *path = (const UInt8 *)argv[1];
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, path, (CFIndex)strlen((const char *)path), false);
    if(!url) {
        puts("audio-file-create-url: FAIL");
        return 1;
    }

    AudioStreamBasicDescription format = {};
    format.mSampleRate = 8000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger |
        kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 2;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;

    AudioFileID created = NULL;
    OSStatus createStatus = AudioFileCreateWithURL(url,
        kAudioFileCAFType, &format, kAudioFileFlags_EraseFile, &created);

    UInt32 propertySize = 0;
    UInt32 isWritable = UINT32_MAX;
    OSStatus propertyInfoStatus = created
        ? AudioFileGetPropertyInfo(created, kAudioFilePropertyDataFormat,
            &propertySize, &isWritable)
        : kAudio_ParamError;
    OSStatus nullablePropertyInfoStatus = created
        ? AudioFileGetPropertyInfo(created, kAudioFilePropertyDataFormat,
            NULL, NULL)
        : kAudio_ParamError;

    const int16_t samples[] = {-32768, -1234, 1234, 32767};
    UInt32 bytesToWrite = sizeof(samples);
    OSStatus writeStatus = created
        ? AudioFileWriteBytes(created, false, 0, &bytesToWrite, samples)
        : kAudio_ParamError;
    OSStatus createCloseStatus = created
        ? AudioFileClose(created) : kAudio_ParamError;

    AudioFileID opened = NULL;
    OSStatus openStatus = AudioFileOpenURL(url, kAudioFileReadPermission,
        kAudioFileCAFType, &opened);
    int16_t returnedSamples[4] = {};
    AudioStreamPacketDescription descriptions[4];
    memset(descriptions, 0xa5, sizeof(descriptions));
    AudioStreamPacketDescription expectedDescriptions[4];
    memcpy(expectedDescriptions, descriptions, sizeof(descriptions));
    UInt32 returnedBytes = UINT32_MAX;
    UInt32 packets = 4;
    OSStatus readPacketsStatus = opened
        ? AudioFileReadPackets(opened, false, &returnedBytes, descriptions,
            0, &packets, returnedSamples)
        : kAudio_ParamError;
    OSStatus openCloseStatus = opened
        ? AudioFileClose(opened) : kAudio_ParamError;
    CFRelease(url);

    int passed = 1;
    passed &= report_status("audio-file-create", createStatus);
    passed &= report_status("audio-file-property-info", propertyInfoStatus);
    passed &= propertySize == sizeof(AudioStreamBasicDescription);
    printf("audio-file-property-info-size: %s (%u)\n",
        propertySize == sizeof(AudioStreamBasicDescription) ? "PASS" : "FAIL",
        (unsigned int)propertySize);
    passed &= report_status("audio-file-property-info-null-outputs",
        nullablePropertyInfoStatus);
    passed &= report_status("audio-file-write-bytes", writeStatus);
    passed &= bytesToWrite == sizeof(samples);
    printf("audio-file-write-count: %s (%u)\n",
        bytesToWrite == sizeof(samples) ? "PASS" : "FAIL",
        (unsigned int)bytesToWrite);
    passed &= report_status("audio-file-created-close", createCloseStatus);
    passed &= report_status("audio-file-reopen", openStatus);
    const int readPacketsSucceeded = readPacketsStatus == noErr ||
        readPacketsStatus == kAudioFileEndOfFileError;
    passed &= readPacketsSucceeded;
    printf("audio-file-read-packets: %s (%d)\n",
        readPacketsSucceeded ? "PASS" : "FAIL", (int)readPacketsStatus);
    const int packetDataMatches = returnedBytes == sizeof(samples) &&
        packets == 4 && !memcmp(returnedSamples, samples, sizeof(samples));
    passed &= packetDataMatches;
    printf("audio-file-read-packet-data: %s (bytes=%u packets=%u)\n",
        packetDataMatches ? "PASS" : "FAIL", (unsigned int)returnedBytes,
        (unsigned int)packets);
    const int cbrDescriptionsUntouched =
        !memcmp(descriptions, expectedDescriptions, sizeof(descriptions));
    passed &= cbrDescriptionsUntouched;
    printf("audio-file-cbr-descriptions-untouched: %s\n",
        cbrDescriptionsUntouched ? "PASS" : "FAIL");
    passed &= report_status("audio-file-opened-close", openCloseStatus);
    return !passed;
}
