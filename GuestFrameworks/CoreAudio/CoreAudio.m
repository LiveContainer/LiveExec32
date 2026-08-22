// Compatibility shell for CoreAudio.framework.
//
// Some legacy applications carry a strong CoreAudio load command while all
// of their audio API imports are provided by AudioToolbox, OpenAL, or
// AVFoundation.  Supplying the framework identity avoids loading the original
// iOS framework and its private dependency graph until an application needs a
// CoreAudio symbol that can be bridged deliberately.

void LC32CoreAudioCompatibilityStub(void) {
}
