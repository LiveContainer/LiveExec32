#import <GameKit/GameKit.h>

NSString *GKErrorDomain = @"GKErrorDomain";
NSString *GKGameSessionErrorDomain = @"GKGameSessionErrorDomain";
NSString *GKPlayerAuthenticationDidChangeNotificationName =
    @"GKPlayerAuthenticationDidChangeNotificationName";
NSString *GKPlayerDidChangeNotificationName =
    @"GKPlayerDidChangeNotificationName";
NSString *const GKSessionErrorDomain =
    @"com.apple.gamekit.GKSessionErrorDomain";
NSString *const GKVoiceChatServiceErrorDomain =
    @"GKVoiceChatServiceErrorDomain";

/* iOS 10.3 documents a week for turns and a day for exchanges. */
NSTimeInterval GKTurnTimeoutDefault = 7.0 * 24.0 * 60.0 * 60.0;
NSTimeInterval GKTurnTimeoutNone = 0.0;
NSTimeInterval GKExchangeTimeoutDefault = 24.0 * 60.0 * 60.0;
NSTimeInterval GKExchangeTimeoutNone = 0.0;
