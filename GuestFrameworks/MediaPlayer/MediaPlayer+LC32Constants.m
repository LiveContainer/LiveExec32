// Guest constants for MediaPlayer.framework
//
// The generated shim emits Objective-C methods but not the C-level
// extern constants.  Provide the legacy media properties and movie-player
// notifications used by older applications.

#import <MediaPlayer/MediaPlayer.h>

NSString * const MPMediaItemPropertyAlbumArtist = @"albumArtist";
NSString * const MPMediaItemPropertyAlbumTitle = @"albumTitle";
NSString * const MPMediaItemPropertyArtist = @"artist";
NSString * const MPMediaItemPropertyComposer = @"composer";
NSString * const MPMediaItemPropertyGenre = @"genre";
NSString * const MPMediaItemPropertyTitle = @"title";

NSString * const MPMoviePlayerContentPreloadDidFinishNotification =
    @"MPMoviePlayerContentPreloadDidFinishNotification";
NSString * const MPMovieDurationAvailableNotification =
    @"MPMovieDurationAvailableNotification";
NSString * const MPMoviePlayerDidEnterFullscreenNotification =
    @"MPMoviePlayerDidEnterFullscreenNotification";
NSString * const MPMoviePlayerDidExitFullscreenNotification =
    @"MPMoviePlayerDidExitFullscreenNotification";
NSString * const MPMoviePlayerLoadStateDidChangeNotification =
    @"MPMoviePlayerLoadStateDidChangeNotification";
NSString * const MPMoviePlayerPlaybackDidFinishNotification =
    @"MPMoviePlayerPlaybackDidFinishNotification";
NSString * const MPMoviePlayerPlaybackDidFinishReasonUserInfoKey =
    @"MPMoviePlayerPlaybackDidFinishReasonUserInfoKey";
NSString * const MPMoviePlayerPlaybackStateDidChangeNotification =
    @"MPMoviePlayerPlaybackStateDidChangeNotification";
NSString * const MPMoviePlayerScalingModeDidChangeNotification =
    @"MPMoviePlayerScalingModeDidChangeNotification";
NSString * const MPMoviePlayerWillEnterFullscreenNotification =
    @"MPMoviePlayerWillEnterFullscreenNotification";
NSString * const MPMoviePlayerWillExitFullscreenNotification =
    @"MPMoviePlayerWillExitFullscreenNotification";
