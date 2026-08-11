#import <AdSupport/AdSupport.h>

@implementation ASIdentifierManager

+ (ASIdentifierManager *)sharedManager {
    static ASIdentifierManager *manager;
    @synchronized(self) {
        if(!manager) manager = [[self alloc] init];
    }
    return manager;
}

- (NSUUID *)advertisingIdentifier {
    static NSUUID *identifier;
    @synchronized([ASIdentifierManager class]) {
        if(!identifier) {
            identifier = [[NSUUID alloc] initWithUUIDString:
                @"00000000-0000-0000-0000-000000000000"];
        }
    }
    return identifier;
}

- (BOOL)isAdvertisingTrackingEnabled {
    return NO;
}

@end
