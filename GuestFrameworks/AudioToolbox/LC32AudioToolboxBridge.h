#ifndef LC32_AUDIO_TOOLBOX_BRIDGE_H
#define LC32_AUDIO_TOOLBOX_BRIDGE_H

#include <stdint.h>

enum {
    LC32AudioToolboxABIVersion = 1,
    LC32AudioToolboxMaxSlots = 8,
    LC32AudioQueueDisposeTerminalNone = 0,
    LC32AudioQueueDisposeTerminalReleaseMirrors = 1,
    /* The host has detached every native buffer mirror and will ask the
     * guest cleanup thunk to release the guest allocations once callbacks
     * and native disposal have both quiesced. */
    LC32AudioQueueDisposeTerminalDeferredCleanup = 2,
    /* Reserved for an inconsistent/failed host lifecycle where native code
     * may still retain raw callback state and guest mirrors must stay alive. */
    LC32AudioQueueDisposeTerminalQuarantineMirrors = 3,
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
    LC32AudioToolboxOpExtAudioFileSeek = 6,
    LC32AudioToolboxOpAudioSessionGetProperty = 7,
    LC32AudioToolboxOpAudioFileOpenURL = 8,
    LC32AudioToolboxOpAudioFileGetProperty = 9,
    LC32AudioToolboxOpAudioFileReadBytes = 10,
    LC32AudioToolboxOpAudioFileClose = 11,
    LC32AudioToolboxOpAudioFileCreateWithURL = 12,
    LC32AudioToolboxOpAudioFileGetPropertyInfo = 13,
    LC32AudioToolboxOpAudioFileReadPackets = 14,
    LC32AudioToolboxOpAudioFileWriteBytes = 15,
    LC32AudioToolboxOpAudioQueueNewInput = 16,
    LC32AudioToolboxOpAudioQueueAllocateBuffer = 17,
    LC32AudioToolboxOpAudioQueueEnqueueBuffer = 18,
    LC32AudioToolboxOpAudioQueueFreeBuffer = 19,
    LC32AudioToolboxOpAudioQueueGetProperty = 20,
    LC32AudioToolboxOpAudioQueueSetProperty = 21,
    LC32AudioToolboxOpAudioQueueDeviceGetCurrentTime = 22,
    LC32AudioToolboxOpAudioQueueStart = 23,
    LC32AudioToolboxOpAudioQueueStop = 24,
    LC32AudioToolboxOpAudioQueuePause = 25,
    LC32AudioToolboxOpAudioQueueDispose = 26,
    LC32AudioToolboxOpAudioSessionSetActive = 27,
    LC32AudioToolboxOpAudioSessionSetProperty = 28,
    LC32AudioToolboxOpAudioQueueNewOutput = 29,
    LC32AudioToolboxOpAudioQueueSetParameter = 30,
    LC32AudioToolboxOpAudioQueueAddPropertyListener = 31,
    LC32AudioToolboxOpAudioQueueRemovePropertyListener = 32,
    LC32AudioToolboxOpAudioQueuePrime = 33,
    /* Propagate logical callback scope across the serialized guest callback
     * executor, whose host pthread differs from the native AudioQueue thread. */
    LC32AudioToolboxOpAudioQueueCallbackEnter = 34,
    LC32AudioToolboxOpAudioQueueCallbackLeave = 35,
    LC32AudioToolboxOpAudioFileOpenWithCallbacks = 36,
    LC32AudioToolboxOpAudioFileReadPacketData = 37,
    LC32AudioToolboxOpAudioQueueCreateTimeline = 38,
    LC32AudioToolboxOpAudioQueueDisposeTimeline = 39,
    LC32AudioToolboxOpAudioQueueGetCurrentTime = 40,
    /* Private RemoteIO compatibility sink. The guest invokes the emulated
     * render callback; a host-only AudioQueue consumes the resulting PCM so
     * no emulated code ever runs on CoreAudio's callback thread. */
    LC32AudioToolboxOpRemoteIOOutputStart = 41,
    LC32AudioToolboxOpRemoteIOOutputSubmit = 42,
    LC32AudioToolboxOpRemoteIOOutputStop = 43,
} LC32AudioToolboxOpcode;

#endif
