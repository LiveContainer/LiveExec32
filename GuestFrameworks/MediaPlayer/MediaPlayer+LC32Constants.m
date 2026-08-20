// Guest constants for MediaPlayer.framework
//
// The generated shim emits Objective-C methods but not the C-level
// extern constants.  Provide the legacy movie player's finish notification.

#import <MediaPlayer/MediaPlayer.h>

NSString * const MPMoviePlayerPlaybackDidFinishNotification =
    @"MPMoviePlayerPlaybackDidFinishNotification";
