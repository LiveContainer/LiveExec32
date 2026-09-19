#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, MPMoviePlaybackState) {
    MPMoviePlaybackStateStopped, MPMoviePlaybackStatePlaying,
    MPMoviePlaybackStatePaused, MPMoviePlaybackStateInterrupted,
    MPMoviePlaybackStateSeekingForward, MPMoviePlaybackStateSeekingBackward
};
typedef NS_ENUM(NSInteger, MPMovieControlStyle) {
    MPMovieControlStyleNone, MPMovieControlStyleEmbedded,
    MPMovieControlStyleFullscreen, MPMovieControlStyleDefault = MPMovieControlStyleEmbedded
};
typedef NS_ENUM(NSInteger, MPMovieFinishReason) {
    MPMovieFinishReasonPlaybackEnded, MPMovieFinishReasonPlaybackError,
    MPMovieFinishReasonUserExited
};
extern NSString * const MPMoviePlayerPlaybackDidFinishNotification;
extern NSString * const MPMoviePlayerPlaybackDidFinishReasonUserInfoKey;
@interface MPMoviePlayerController : NSObject
@property(nonatomic) MPMoviePlaybackState playbackState;
@property(nonatomic) MPMovieControlStyle controlStyle;
@end
@interface MPMoviePlayerController (PlaybackAPI)
- (void)stop;
- (void)setMovieControlMode:(NSInteger)mode;
@end
