#import <GameKit/GameKit.h>

/*
 * Native GameKit is available to the host, but forwarding a guest block to
 * it requires a dedicated ARM32/ARM64 block ABI bridge.  Keep legacy games
 * running without Game Center until that bridge exists: finish authentication
 * locally as unavailable and ensure block-taking leaderboard fallbacks stay
 * entirely in guest code.
 */
@implementation GKLocalPlayer (LC32BlockCompatibility)

- (void)setAuthenticateHandler:(void (^)(UIViewController *, NSError *))handler {
    (void)handler;
}

- (BOOL)isAuthenticated {
    return NO;
}

- (void)loadDefaultLeaderboardCategoryIDWithCompletionHandler:
        (void (^)(NSString *, NSError *))completionHandler {
    if(completionHandler) completionHandler(nil, nil);
}

- (void)loadDefaultLeaderboardIdentifierWithCompletionHandler:
        (void (^)(NSString *, NSError *))completionHandler {
    if(completionHandler) completionHandler(nil, nil);
}

@end
