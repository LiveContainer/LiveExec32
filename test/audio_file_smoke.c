#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if(argc != 2) {
        fprintf(stderr, "usage: %s file.caf\n", argv[0]);
        return 2;
    }

    const UInt8 *path = (const UInt8 *)argv[1];
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, path, (CFIndex)strlen((const char *)path), false);
    AudioFileID file = NULL;
    OSStatus openStatus = url
        ? AudioFileOpenURL(url, kAudioFileReadPermission, 0, &file)
        : kAudio_ParamError;

    AudioStreamBasicDescription format = {};
    UInt32 formatSize = sizeof(format);
    OSStatus formatStatus = file
        ? AudioFileGetProperty(file, kAudioFilePropertyDataFormat,
            &formatSize, &format)
        : kAudio_ParamError;

    UInt64 byteCount = 0;
    UInt32 byteCountSize = sizeof(byteCount);
    OSStatus byteCountStatus = file
        ? AudioFileGetProperty(file, kAudioFilePropertyAudioDataByteCount,
            &byteCountSize, &byteCount)
        : kAudio_ParamError;

    UInt8 bytes[256] = {};
    UInt32 bytesToRead = byteCount < sizeof(bytes)
        ? (UInt32)byteCount : (UInt32)sizeof(bytes);
    OSStatus readStatus = file && bytesToRead
        ? AudioFileReadBytes(file, false, 0, &bytesToRead, bytes)
        : kAudio_ParamError;
    OSStatus closeStatus = file ? AudioFileClose(file) : kAudio_ParamError;
    if(url) CFRelease(url);

    const int passed = openStatus == noErr && formatStatus == noErr &&
        formatSize == sizeof(format) && byteCountStatus == noErr &&
        byteCountSize == sizeof(byteCount) && byteCount > 0 &&
        readStatus == noErr && bytesToRead > 0 && closeStatus == noErr;
    printf("audio-file-open-property-read-close: %s\n",
        passed ? "PASS" : "FAIL");
    if(!passed) {
        printf("statuses: open=%d format=%d count=%d read=%d close=%d "
               "byteCount=%llu bytesRead=%u\n",
            (int)openStatus, (int)formatStatus, (int)byteCountStatus,
            (int)readStatus, (int)closeStatus,
            (unsigned long long)byteCount, (unsigned int)bytesToRead);
    }
    return !passed;
}
