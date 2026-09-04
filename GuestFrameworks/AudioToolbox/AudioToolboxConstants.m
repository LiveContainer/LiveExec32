// Guest-native public AudioToolbox string constants.

#import <AudioToolbox/AudioToolbox.h>

#define LC32_AUDIO_STRING(name, value) \
    const CFStringRef name = CFSTR(value)

LC32_AUDIO_STRING(kAudioComponentInstanceInvalidationNotification, "com.apple.coreaudio.AudioComponentInstanceInvalidated");
LC32_AUDIO_STRING(kAudioComponentRegistrationsChangedNotification, "com.apple.coreaudio.AudioComponentRegistrationsChanged");
LC32_AUDIO_STRING(kAudioSessionInputRoute_BluetoothHFP, "MicrophoneBluetooth");
LC32_AUDIO_STRING(kAudioSessionInputRoute_BuiltInMic, "MicrophoneBuiltIn");
LC32_AUDIO_STRING(kAudioSessionInputRoute_HeadsetMic, "MicrophoneWired");
LC32_AUDIO_STRING(kAudioSessionInputRoute_LineIn, "LineIn");
LC32_AUDIO_STRING(kAudioSessionInputRoute_USBAudio, "USBInput");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_AirPlay, "AirPlay");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_BluetoothA2DP, "BluetoothA2DPOutput");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_BluetoothHFP, "BluetoothHFPOutput");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_BuiltInReceiver, "Receiver");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_BuiltInSpeaker, "Speaker");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_HDMI, "HDMIOutput");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_Headphones, "Headphones");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_LineOut, "LineOut");
LC32_AUDIO_STRING(kAudioSessionOutputRoute_USBAudio, "USBOutput");
LC32_AUDIO_STRING(kAudioSession_AudioRouteChangeKey_CurrentRouteDescription, "ActiveAudioRouteDidChange_NewDetailedRoute");
LC32_AUDIO_STRING(kAudioSession_AudioRouteChangeKey_PreviousRouteDescription, "ActiveAudioRouteDidChange_OldDetailedRoute");
LC32_AUDIO_STRING(kAudioSession_AudioRouteKey_Inputs, "RouteDetailedDescription_Inputs");
LC32_AUDIO_STRING(kAudioSession_AudioRouteKey_Outputs, "RouteDetailedDescription_Outputs");
LC32_AUDIO_STRING(kAudioSession_AudioRouteKey_Type, "RouteDetailedDescription_PortType");
LC32_AUDIO_STRING(kAudioSession_InputSourceKey_Description, "input source name");
LC32_AUDIO_STRING(kAudioSession_InputSourceKey_ID, "input source ID");
LC32_AUDIO_STRING(kAudioSession_OutputDestinationKey_Description, "output destination name");
LC32_AUDIO_STRING(kAudioSession_OutputDestinationKey_ID, "output destination ID");
LC32_AUDIO_STRING(kAudioSession_RouteChangeKey_Reason, "OutputDeviceDidChange_Reason");

#undef LC32_AUDIO_STRING
