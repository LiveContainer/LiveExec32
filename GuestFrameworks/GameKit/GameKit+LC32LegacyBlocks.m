#import <GameKit/GameKit.h>
#import <LC32/LC32.h>

/*
 * Some games built with early Apple LLVM versions set BLOCK_HAS_SIGNATURE on
 * these callbacks while leaving the descriptor's signature pointer null.
 * GameKit already specifies each callback ABI, so capture the legacy block in
 * a current-compiler wrapper whose descriptor the generic host bridge can
 * parse.  Invoking the captured block in guest code does not inspect its
 * descriptor, and the wrapper's copy helper preserves its normal lifetime.
 */

@implementation GKAchievement (LC32LegacyBlockCompatibility)

- (void)reportAchievementWithCompletionHandler:
        (void (^)(NSError *error))completionHandler {
    void (^typedHandler)(NSError *) = nil;
    if(completionHandler) {
        typedHandler = ^(NSError *error) {
            completionHandler(error);
        };
    }

    /* Modern GameKit replaces the deprecated instance API with this batch
     * class method.  Preserve the legacy one-achievement behavior. */
    [GKAchievement reportAchievements:@[self]
                 withCompletionHandler:typedHandler];
}

@end

@implementation GKLocalPlayer (LC32LegacyBlockCompatibility)

- (void)authenticateWithCompletionHandler:
        (void (^)(NSError *error))completionHandler {
    void (^typedHandler)(NSError *) = nil;
    if(completionHandler) {
        typedHandler = ^(NSError *error) {
            completionHandler(error);
        };
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    LC32InvokeHostSelector(
        self.host_self, LC32CachedHostSelector(&hostCommand, _cmd, NO),
        [typedHandler host_self], (uint64_t)0);
}

@end

@implementation GKMatchmaker (LC32LegacyBlockCompatibility)

- (void)setInviteHandler:
        (void (^)(GKInvite *acceptedInvite,
                  NSArray *playerIDsToInvite))inviteHandler {
    void (^typedHandler)(GKInvite *, NSArray *) = nil;
    if(inviteHandler) {
        typedHandler = ^(GKInvite *acceptedInvite,
                         NSArray *playerIDsToInvite) {
            inviteHandler(acceptedInvite, playerIDsToInvite);
        };
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    LC32InvokeHostSelector(
        self.host_self, LC32CachedHostSelector(&hostCommand, _cmd, NO),
        [typedHandler host_self], (uint64_t)0);
}

@end

@implementation GKVoiceChat (LC32LegacyBlockCompatibility)

- (void)setPlayerStateUpdateHandler:
        (void (^)(NSString *playerID,
                  GKVoiceChatPlayerState state))playerStateUpdateHandler {
    void (^typedHandler)(NSString *, GKVoiceChatPlayerState) = nil;
    if(playerStateUpdateHandler) {
        typedHandler = ^(NSString *playerID, GKVoiceChatPlayerState state) {
            playerStateUpdateHandler(playerID, state);
        };
    }

    static uint64_t hostCommand __attribute__((aligned(8)));
    LC32InvokeHostSelector(
        self.host_self, LC32CachedHostSelector(&hostCommand, _cmd, NO),
        [typedHandler host_self], (uint64_t)0);
}

@end
