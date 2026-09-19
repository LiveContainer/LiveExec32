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
@interface UIColor : NSObject
@end
@interface UIView : NSObject
@property(nonatomic, retain) UIColor *backgroundColor;
@end
@interface MPMoviePlayerController : NSObject
@property(nonatomic) MPMoviePlaybackState playbackState;
@property(nonatomic) MPMovieControlStyle controlStyle;
@property(nonatomic, retain) UIView *backgroundView;
@end
@interface MPMoviePlayerController (PlaybackAPI)
- (void)stop;
- (void)setMovieControlMode:(NSInteger)mode;
@property(nonatomic, retain) UIColor *backgroundColor;
@property(nonatomic) BOOL useApplicationAudioSession;
@end
