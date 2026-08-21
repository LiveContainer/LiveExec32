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
NSString * const MPMoviePlayerPlaybackDidFinishNotification =
    @"MPMoviePlayerPlaybackDidFinishNotification";
