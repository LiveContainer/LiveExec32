// Exercise the actual guest category with a deterministic native-player bridge.
#import <MediaPlayer/MediaPlayer.h>
#import <LC32/LC32.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#include <stdio.h>

NSString * const MPMoviePlayerPlaybackDidFinishNotification = @"MovieFinished";
NSString * const MPMoviePlayerPlaybackDidFinishReasonUserInfoKey = @"FinishReason";
@implementation UIColor
@end
@implementation UIView
- (void)dealloc { [_backgroundColor release]; [super dealloc]; }
@end
@implementation MPMoviePlayerController
- (void)dealloc { [_backgroundView release]; [super dealloc]; }
@end
@implementation NSObject (LC32MovieTestBridge)
- (uint64_t)host_self { return (uintptr_t)self; }
@end

static unsigned checks, failures, nativeStops;
static unsigned nativeFinishMode; // 0: absent, 1: synchronous, 2: queued by stop.
static unsigned disposedMovies;
@interface LC32DisposableMovie : MPMoviePlayerController
@end
@implementation LC32DisposableMovie
- (void)dealloc { disposedMovies++; [super dealloc]; }
@end

static void check(BOOL condition, const char *name) {
    checks++;
    failures += !condition;
    printf("%s %s\n", condition ? "PASS" : "FAIL", name);
}

static void nativeFinish(MPMoviePlayerController *movie) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPMoviePlayerPlaybackDidFinishNotification object:movie
        userInfo:@{MPMoviePlayerPlaybackDidFinishReasonUserInfoKey:
            @(MPMovieFinishReasonPlaybackEnded)}];
}

uint64_t LC32CachedHostSelector(uint64_t *cache, SEL selector, BOOL superCall) {
    check(!superCall && sel_isEqual(selector, @selector(stop)),
          "forwards exactly the native stop selector");
    return *cache = 1;
}

uint64_t LC32InvokeHostSelector(uint64_t receiver, uint64_t command, ...) {
    check(command == 1, "native stop called");
    nativeStops++;
    MPMoviePlayerController *movie = (id)(uintptr_t)receiver;
    BOOL active = movie.playbackState != MPMoviePlaybackStateStopped;
    movie.playbackState = MPMoviePlaybackStateStopped;
    if(active && nativeFinishMode == 1) nativeFinish(movie);
    if(active && nativeFinishMode == 2) {
        dispatch_async(dispatch_get_main_queue(), ^{ nativeFinish(movie); });
    }
    return 0;
}

static void drainMainQueue(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while(!done && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    check(done, "deferred completion queue drained");
}

int main(void) {
    @autoreleasepool {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        MPMoviePlayerController *movie = [MPMoviePlayerController new];
        movie.backgroundView = [[[UIView alloc] init] autorelease];
        UIColor *color = [[[UIColor alloc] init] autorelease];
        movie.backgroundColor = color;
        check(movie.backgroundView.backgroundColor == color && movie.backgroundColor == color,
              "legacy background color maps to the movie background view");
        movie.backgroundColor = nil;
        check(movie.backgroundView.backgroundColor == nil, "legacy background color accepts nil");
        check(movie.useApplicationAudioSession, "legacy audio session preference defaults to YES");
        movie.useApplicationAudioSession = NO;
        check(!movie.useApplicationAudioSession, "legacy audio session preference round trips NO");
        movie.useApplicationAudioSession = YES;
        check(movie.useApplicationAudioSession, "legacy audio session preference round trips YES");
        __block unsigned finishes = 0;
        __block NSInteger reason = -1;
        __block BOOL reenter = NO;
        id observer = [center addObserverForName:MPMoviePlayerPlaybackDidFinishNotification
            object:movie queue:nil usingBlock:^(NSNotification *notification) {
                finishes++;
                reason = [notification.userInfo[MPMoviePlayerPlaybackDidFinishReasonUserInfoKey]
                    integerValue];
                check(notification.object == movie, "completion preserves player identity");
                if(reenter) [movie stop];
            }];

        movie.playbackState = MPMoviePlaybackStatePlaying;
        [movie stop];
        check(finishes == 0, "fallback waits until guest stop stack unwinds");
        [movie stop];
        drainMainQueue();
        check(finishes == 1 && reason == MPMovieFinishReasonUserExited,
              "missing native finish is delivered once with user-exited reason");
        check(nativeStops == 2, "duplicate stop still forwards, without duplicate completion");

        reenter = YES;
        movie.playbackState = MPMoviePlaybackStatePaused;
        [movie stop];
        drainMainQueue();
        check(finishes == 2, "paused movie finishes once despite reentrant stop");
        reenter = NO;

        for(unsigned mode = 1; mode <= 2; mode++) {
            nativeFinishMode = mode;
            unsigned before = finishes;
            movie.playbackState = MPMoviePlaybackStatePlaying;
            [movie stop];
            drainMainQueue();
            check(finishes == before + 1 && reason == MPMovieFinishReasonPlaybackEnded,
                  "native synchronous or queued completion wins without duplication");
        }
        nativeFinishMode = 0;
        unsigned beforeRestart = finishes;
        movie.playbackState = MPMoviePlaybackStatePlaying;
        [movie stop];
        movie.playbackState = MPMoviePlaybackStatePlaying;
        drainMainQueue();
        check(finishes == beforeRestart, "immediate restart does not finish the new session");
        movie.playbackState = MPMoviePlaybackStateStopped;
        unsigned before = finishes;
        [movie stop];
        drainMainQueue();
        check(finishes == before, "already stopped movie does not manufacture a finish");

        before = finishes;
        MPMoviePlayerController *other = [MPMoviePlayerController new];
        movie.playbackState = MPMoviePlaybackStatePlaying;
        [movie stop];
        nativeFinish(other);
        drainMainQueue();
        check(finishes == before + 1, "another player's finish cannot suppress this completion");
        [other release];

        for(NSInteger state = MPMoviePlaybackStateInterrupted;
            state <= MPMoviePlaybackStateSeekingBackward; state++) {
            before = finishes;
            movie.playbackState = state;
            [movie stop];
            drainMainQueue();
            check(finishes == before + 1, "interrupted or seeking session also completes");
        }
        [movie setMovieControlMode:2];
        check(movie.controlStyle == MPMovieControlStyleNone, "legacy hidden controls retained");
        [movie setMovieControlMode:0];
        check(movie.controlStyle == MPMovieControlStyleDefault, "legacy default controls retained");
        [center removeObserver:observer];
        [movie release];

        @autoreleasepool {
            LC32DisposableMovie *disposable = [LC32DisposableMovie new];
            disposable.playbackState = MPMoviePlaybackStatePlaying;
            [disposable stop];
            [disposable release];
            check(disposedMovies == 0, "queued completion keeps a released player alive");
            drainMainQueue();
        }
        check(disposedMovies == 1, "deferred completion does not leak its player");
    }
    printf("%u/%u movie-stop checks passed\n", checks - failures, checks);
    return failures ? 1 : 0;
}
