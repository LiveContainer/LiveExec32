#import <AudioToolbox/AudioToolbox.h>
#import <LC32/LC32.h>

#include <pthread.h>
#include <stdint.h>
#include <string.h>

#import "LC32AudioToolboxBridge.h"

/* Deprecated AudioSession route dictionary values retained for old apps. */
const CFStringRef kAudioSessionInputRoute_BuiltInMic =
    CFSTR("MicrophoneBuiltIn");
const CFStringRef kAudioSession_AudioRouteKey_Inputs =
    CFSTR("RouteDetailedDescription_Inputs");
const CFStringRef kAudioSession_AudioRouteKey_Type =
    CFSTR("RouteDetailedDescription_PortType");

static pthread_once_t LC32AudioToolboxDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32AudioToolboxDispatcherAddress;

static void LC32AudioToolboxResolveDispatcher(void) {
    LC32AudioToolboxDispatcherAddress =
        LC32Dlsym("LC32_AudioToolbox_Dispatch", YES);
}

static uint32_t LC32AudioToolboxDispatch(LC32AudioToolboxOpcode opcode,
                                         const uint64_t *slots,
                                         uint32_t slotCount) {
    if(slotCount > LC32AudioToolboxMaxSlots) return (uint32_t)kAudio_ParamError;
    pthread_once(&LC32AudioToolboxDispatcherOnce,
        LC32AudioToolboxResolveDispatcher);
    if(!LC32AudioToolboxDispatcherAddress) return (uint32_t)kAudio_ParamError;

    LC32AudioToolboxCall call = {
        .version = LC32AudioToolboxABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32AudioToolboxDispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}

#define LC32_AUDIO_CALL(opcode, ...) \
    LC32AudioToolboxDispatch((opcode), (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / sizeof(uint64_t)))
#define LC32_AUDIO_U32(value) ((uint64_t)(uint32_t)(value))

// TODO: stub

OSStatus AudioServicesCreateSystemSoundID(CFURLRef inFileURL, SystemSoundID *outSystemSoundID) {
    //static hostAddr = host_dlsym("AudioServicesCreateSystemSoundID");
    return 0;
}

OSStatus AudioServicesDisposeSystemSoundID(SystemSoundID inSystemSoundID) {
    return 0;
}

void AudioServicesPlaySystemSound(SystemSoundID inSystemSoundID) {
    
}

OSStatus AudioQueueAddPropertyListener(AudioQueueRef inAQ, AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void * inUserData) {
    return 0;
}

OSStatus AudioServicesSetProperty(AudioServicesPropertyID inPropertyID, UInt32 inSpecifierSize, const void * inSpecifier, UInt32 inPropertyDataSize, const void * inPropertyData) {
    return 0;
}

OSStatus AudioQueueAllocateBuffer(AudioQueueRef inAQ, UInt32 inBufferByteSize, AudioQueueBufferRef * outBuffer) {
    return 0;
}

OSStatus AudioQueueDispose(AudioQueueRef inAQ, Boolean inImmediate) {
    return 0;
}

OSStatus AudioQueueEnqueueBuffer(AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs, const AudioStreamPacketDescription * inPacketDescs) {
    return 0;
}

OSStatus AudioQueueFreeBuffer(AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    return 0;
}

OSStatus AudioQueueGetProperty(AudioQueueRef inAQ, AudioQueuePropertyID inID, void * outData, UInt32 * ioDataSize) {
    return 0;
}

OSStatus AudioQueueNewInput(const AudioStreamBasicDescription * inFormat, AudioQueueInputCallback inCallbackProc, void * inUserData, CFRunLoopRef inCallbackRunLoop, CFStringRef inCallbackRunLoopMode, UInt32 inFlags, AudioQueueRef * outAQ) {
    return 0;
}

OSStatus AudioQueuePause(AudioQueueRef inAQ) {
    return 0;
}

OSStatus AudioQueueSetProperty(AudioQueueRef inAQ, AudioQueuePropertyID inID, const void * inData, UInt32 inDataSize);
OSStatus AudioQueueStart(AudioQueueRef inAQ, const AudioTimeStamp * inStartTime) {
    return 0;
}

OSStatus AudioQueueStop(AudioQueueRef inAQ, Boolean inImmediate) {
    return 0;
}

OSStatus AudioSessionInitialize(CFRunLoopRef inRunLoop, CFStringRef inRunLoopMode, AudioSessionInterruptionListener inInterruptionListener, void * inClientData) {
    return 0; // deprecated
}
OSStatus AudioSessionSetActive(Boolean active) {
    return 0; // deprecated
}

OSStatus AudioSessionSetProperty(AudioSessionPropertyID inID, UInt32 inDataSize, const void * inData) {
    return 0; // deprecated
}

OSStatus AudioSessionAddPropertyListener(
        AudioSessionPropertyID inID,
        AudioSessionPropertyListener inProc,
        void *inClientData) {
    /*
     * Modern AVAudioSession notifications cover the properties used by old
     * applications.  Keep registration source-compatible for now; forwarding
     * the callback itself requires a host-to-guest trampoline and is added
     * independently of the legacy API's basic availability.
     */
    (void)inID;
    (void)inProc;
    (void)inClientData;
    return noErr;
}

OSStatus AudioSessionRemovePropertyListener(AudioSessionPropertyID inID) {
    (void)inID;
    return noErr;
}

OSStatus AudioSessionRemovePropertyListenerWithUserData(
        AudioSessionPropertyID inID,
        AudioSessionPropertyListener inProc,
        void *inClientData) {
    (void)inID;
    (void)inProc;
    (void)inClientData;
    return noErr;
}

OSStatus AudioSessionGetProperty(AudioSessionPropertyID property,
                                 UInt32 *ioDataSize,
                                 void *outData) {
    if(!ioDataSize) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioSessionGetProperty,
        LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)ioDataSize),
        LC32_AUDIO_U32((uintptr_t)outData));
}

#pragma mark Audio File Services

OSStatus AudioFileOpenURL(CFURLRef fileURL,
                          AudioFilePermissions permissions,
                          AudioFileTypeID fileTypeHint,
                          AudioFileID *outAudioFile) {
    if(!fileURL || !outAudioFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileOpenURL,
        [(id)fileURL host_self], LC32_AUDIO_U32(permissions),
        LC32_AUDIO_U32(fileTypeHint),
        LC32_AUDIO_U32((uintptr_t)outAudioFile));
}

OSStatus AudioFileGetProperty(AudioFileID audioFile,
                              AudioFilePropertyID property,
                              UInt32 *ioDataSize,
                              void *outData) {
    if(!audioFile || !ioDataSize) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileGetProperty,
        LC32_AUDIO_U32((uintptr_t)audioFile),
        LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)ioDataSize),
        LC32_AUDIO_U32((uintptr_t)outData));
}

OSStatus AudioFileReadBytes(AudioFileID audioFile,
                            Boolean useCache,
                            SInt64 startingByte,
                            UInt32 *ioNumBytes,
                            void *outBuffer) {
    if(!audioFile || !ioNumBytes) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileReadBytes,
        LC32_AUDIO_U32((uintptr_t)audioFile), LC32_AUDIO_U32(useCache),
        (uint64_t)startingByte,
        LC32_AUDIO_U32((uintptr_t)ioNumBytes),
        LC32_AUDIO_U32((uintptr_t)outBuffer));
}

OSStatus AudioFileClose(AudioFileID audioFile) {
    if(!audioFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpAudioFileClose,
        LC32_AUDIO_U32((uintptr_t)audioFile));
}

#pragma mark Extended Audio File Services

OSStatus ExtAudioFileOpenURL(CFURLRef url, ExtAudioFileRef *outFile) {
    if(!url || !outFile) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileOpenURL,
        [(id)url host_self], LC32_AUDIO_U32((uintptr_t)outFile));
}

OSStatus ExtAudioFileDispose(ExtAudioFileRef file) {
    if(!file) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileDispose,
        LC32_AUDIO_U32((uintptr_t)file));
}

OSStatus ExtAudioFileGetProperty(ExtAudioFileRef file,
                                 ExtAudioFilePropertyID property,
                                 UInt32 *ioDataSize,
                                 void *outData) {
    if(!file || !ioDataSize) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileGetProperty,
        LC32_AUDIO_U32((uintptr_t)file), LC32_AUDIO_U32(property),
        LC32_AUDIO_U32((uintptr_t)ioDataSize),
        LC32_AUDIO_U32((uintptr_t)outData));
}

OSStatus ExtAudioFileSetProperty(ExtAudioFileRef file,
                                 ExtAudioFilePropertyID property,
                                 UInt32 dataSize,
                                 const void *data) {
    if(!file || (dataSize && !data)) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileSetProperty,
        LC32_AUDIO_U32((uintptr_t)file), LC32_AUDIO_U32(property),
        LC32_AUDIO_U32(dataSize), LC32_AUDIO_U32((uintptr_t)data));
}

OSStatus ExtAudioFileRead(ExtAudioFileRef file,
                          UInt32 *ioNumberFrames,
                          AudioBufferList *ioData) {
    if(!file || !ioNumberFrames || !ioData) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileRead,
        LC32_AUDIO_U32((uintptr_t)file),
        LC32_AUDIO_U32((uintptr_t)ioNumberFrames),
        LC32_AUDIO_U32((uintptr_t)ioData));
}

OSStatus ExtAudioFileSeek(ExtAudioFileRef file, SInt64 frameOffset) {
    if(!file) return kAudio_ParamError;
    return (OSStatus)LC32_AUDIO_CALL(
        LC32AudioToolboxOpExtAudioFileSeek,
        LC32_AUDIO_U32((uintptr_t)file),
        (uint64_t)frameOffset);
}
