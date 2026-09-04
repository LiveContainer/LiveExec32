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
NSString *const AVEncoderAudioQualityKey =
    @"AVEncoderQualityKey";
NSString *const AVFormatIDKey =
    @"AVFormatIDKey";
NSString *const AVLinearPCMBitDepthKey =
    @"AVLinearPCMBitDepthKey";
NSString *const AVLinearPCMIsBigEndianKey =
    @"AVLinearPCMIsBigEndianKey";
NSString *const AVLinearPCMIsFloatKey =
    @"AVLinearPCMIsFloatKey";
NSString *const AVNumberOfChannelsKey =
    @"AVNumberOfChannelsKey";
NSString *const AVSampleRateKey =
    @"AVSampleRateKey";

CGRect AVMakeRectWithAspectRatioInsideRect(
        CGSize aspectRatio, CGRect boundingRect) {
    const CGFloat scale = MIN(
        boundingRect.size.width / aspectRatio.width,
        boundingRect.size.height / aspectRatio.height);
    const CGSize size = CGSizeMake(
        aspectRatio.width * scale, aspectRatio.height * scale);
    return CGRectMake(
        CGRectGetMidX(boundingRect) - size.width / 2,
        CGRectGetMidY(boundingRect) - size.height / 2,
        size.width, size.height);
}
