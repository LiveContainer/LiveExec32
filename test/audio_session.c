#include <AudioToolbox/AudioToolbox.h>

#include <stdint.h>
#include <stdio.h>

static int check_status(const char *name, OSStatus actual,
                        OSStatus expected) {
    const int passed = actual == expected;
    printf("%s: %s (actual=%d expected=%d)\n", name,
        passed ? "PASS" : "FAIL", (int)actual, (int)expected);
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int passed = 1;

    passed &= check_status("audio-session-initialize",
        AudioSessionInitialize(NULL, NULL, NULL, NULL), noErr);

    UInt32 category = kAudioSessionCategory_PlayAndRecord;
    OSStatus categoryStatus = AudioSessionSetProperty(
        kAudioSessionProperty_AudioCategory,
        sizeof(category), &category);
    passed &= check_status("audio-session-set-category",
        categoryStatus, noErr);

    if(categoryStatus == noErr) {
        UInt32 returnedCategory = 0;
        UInt32 returnedSize = sizeof(returnedCategory);
        OSStatus getStatus = AudioSessionGetProperty(
            kAudioSessionProperty_AudioCategory,
            &returnedSize, &returnedCategory);
        const int roundTrip = getStatus == noErr &&
            returnedSize == sizeof(returnedCategory) &&
            returnedCategory == category;
        passed &= roundTrip;
        printf("audio-session-category-roundtrip: %s "
               "(status=%d size=%u value=0x%08x)\n",
            roundTrip ? "PASS" : "FAIL", (int)getStatus,
            (unsigned)returnedSize, (unsigned)returnedCategory);
    }

    OSStatus invalidSizeStatus = AudioSessionSetProperty(
        kAudioSessionProperty_AudioCategory,
        sizeof(category) - 1, &category);
    passed &= check_status("audio-session-invalid-category-size",
        invalidSizeStatus, kAudioSessionBadPropertySizeError);

    passed &= check_status("audio-session-null-data",
        AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,
            sizeof(category), NULL),
        kAudio_ParamError);

    CFNumberRef inputSource = NULL;
    passed &= check_status("audio-session-object-setter-safe",
        AudioSessionSetProperty(kAudioSessionProperty_InputSource,
            sizeof(inputSource), &inputSource),
        kAudioSessionUnsupportedPropertyError);

    OSStatus activeStatus = AudioSessionSetActive(true);
    passed &= check_status("audio-session-set-active",
        activeStatus, noErr);
    if(activeStatus == noErr) {
        passed &= check_status("audio-session-set-inactive",
            AudioSessionSetActive(false), noErr);
    }

    return !passed;
}
