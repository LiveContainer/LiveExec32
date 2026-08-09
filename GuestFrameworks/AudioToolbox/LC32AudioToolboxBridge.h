#ifndef LC32_AUDIO_TOOLBOX_BRIDGE_H
#define LC32_AUDIO_TOOLBOX_BRIDGE_H

#include <stdint.h>

enum {
    LC32AudioToolboxABIVersion = 1,
    LC32AudioToolboxMaxSlots = 6,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32AudioToolboxMaxSlots];
} LC32AudioToolboxCall;

typedef enum : uint32_t {
    LC32AudioToolboxOpExtAudioFileOpenURL = 1,
    LC32AudioToolboxOpExtAudioFileDispose = 2,
    LC32AudioToolboxOpExtAudioFileGetProperty = 3,
    LC32AudioToolboxOpExtAudioFileSetProperty = 4,
    LC32AudioToolboxOpExtAudioFileRead = 5,
} LC32AudioToolboxOpcode;

#endif
