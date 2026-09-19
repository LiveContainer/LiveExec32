#import <MediaPlayer/MediaPlayer.h>
#import <LC32/LC32.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

/*
 * iPhone OS 2.x exposed this compatibility selector before controlStyle was
 * public. The iOS 10 implementation treats mode 2 as hidden and every other
 * value as the default embedded controls, so express it through the public
 * property instead of requiring the private selector on the current host.
 */
@interface MPMoviePlayerController (LC32MovieControlMode)
- (void)setMovieControlMode:(NSInteger)mode;
- (UIColor *)backgroundColor;
- (void)setBackgroundColor:(UIColor *)color;
@end

@implementation MPMoviePlayerController (LC32MovieControlMode)
- (UIColor *)backgroundColor {
    return self.backgroundView.backgroundColor;
}

- (void)setBackgroundColor:(UIColor *)color {
    self.backgroundView.backgroundColor = color;
}

- (BOOL)useApplicationAudioSession {
    NSNumber *preference = objc_getAssociatedObject(self, @selector(useApplicationAudioSession));
    return preference ? preference.boolValue : YES;
}

- (void)setUseApplicationAudioSession:(BOOL)useApplicationAudioSession {
    // Modern movie playback shares the application's session. Preserve the
    // removed legacy preference without changing the application's category.
    objc_setAssociatedObject(self, @selector(useApplicationAudioSession),
        @(useApplicationAudioSession), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setMovieControlMode:(NSInteger)mode {
    self.controlStyle = mode == 2
        ? MPMovieControlStyleNone
        : MPMovieControlStyleDefault;
}

- (void)stop {
    // Current hosts discard the player on stop without finishing the legacy
    // playback session. Guests that release their movie view from the finish
    // notification otherwise leave an opaque, stopped view over their renderer.
    BOOL active = self.playbackState != MPMoviePlaybackStateStopped;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    __block BOOL finished = NO;
    id observer = active ? [center
        addObserverForName:MPMoviePlayerPlaybackDidFinishNotification
        object:self queue:nil usingBlock:^(NSNotification *notification) {
            (void)notification;
            finished = YES;
        }] : nil;

    [self retain]; // A native finish observer may release the guest's owner.
    static uint64_t hostCommand __attribute__((aligned(8)));
    uint64_t command = LC32CachedHostSelector(&hostCommand, _cmd, NO);
    LC32InvokeHostSelector(self.host_self, command, (uint64_t)0);
    if(active) {
        // Let native completion queued by stop win, and let the guest's stop
        // stack unwind before observers are allowed to dispose of its owner.
        dispatch_async(dispatch_get_main_queue(), ^{
            [center removeObserver:observer];
            if(!finished && self.playbackState == MPMoviePlaybackStateStopped) {
                [center postNotificationName:MPMoviePlayerPlaybackDidFinishNotification
                    object:self userInfo:@{MPMoviePlayerPlaybackDidFinishReasonUserInfoKey:
                        @(MPMovieFinishReasonUserExited)}];
            }
        });
    }
    [self release];
}
@end
