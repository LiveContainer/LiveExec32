#import <AVFoundation/AVFoundation.h>

/*
 * The generated AVFoundation shim only emits Objective-C classes.  Legacy
 * binaries also bind these framework-owned NSString constants eagerly, so
 * provide their iOS 6-compatible values in the guest image.
 */
NSString *const AVLayerVideoGravityResizeAspect =
    @"AVLayerVideoGravityResizeAspect";
NSString *const AVMediaCharacteristicLegible =
    @"AVMediaCharacteristicLegible";
NSString *const AVPlayerItemDidPlayToEndTimeNotification =
    @"AVPlayerItemDidPlayToEndTimeNotification";
NSString *const AVAudioSessionInterruptionNotification =
    @"AVAudioSessionInterruptionNotification";
NSString *const AVAudioSessionInterruptionOptionKey =
    @"AVAudioSessionInterruptionOptionKey";
NSString *const AVAudioSessionInterruptionTypeKey =
    @"AVAudioSessionInterruptionTypeKey";
