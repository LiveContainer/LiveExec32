#import <Foundation/Foundation.h>

#include <stdint.h>
#include <stdio.h>

@interface LC32KVOObserver : NSObject {
@public
    NSUInteger _notifications;
    void *_expectedContext;
    BOOL _contextMatched;
    BOOL _objectMatched;
    BOOL _changeMatched;
}
@end

@implementation LC32KVOObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    _notifications++;
    _contextMatched = context == _expectedContext;
    _objectMatched = [object isKindOfClass:[NSOperationQueue class]];
    _changeMatched = [keyPath isEqualToString:@"maxConcurrentOperationCount"] &&
        [change objectForKey:NSKeyValueChangeKindKey] != nil &&
        [change objectForKey:NSKeyValueChangeNewKey] != nil;
}
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    LC32KVOObserver *observer = [[LC32KVOObserver alloc] init];
    uint32_t contextToken = UINT32_C(0x4b564f32);
    observer->_expectedContext = &contextToken;

    [queue addObserver:observer
            forKeyPath:@"maxConcurrentOperationCount"
               options:NSKeyValueObservingOptionInitial |
                       NSKeyValueObservingOptionNew
               context:&contextToken];

    const BOOL initialPassed = observer->_notifications == 1 &&
        observer->_contextMatched && observer->_objectMatched &&
        observer->_changeMatched;
    printf("kvo-initial-context: %s\n",
           initialPassed ? "PASS" : "FAIL");

    queue.maxConcurrentOperationCount = 2;
    const BOOL updatePassed = observer->_notifications >= 2 &&
        observer->_contextMatched && observer->_objectMatched &&
        observer->_changeMatched;
    printf("kvo-update: %s\n", updatePassed ? "PASS" : "FAIL");

    [queue removeObserver:observer
               forKeyPath:@"maxConcurrentOperationCount"
                  context:&contextToken];
    [observer release];
    [queue release];
    [pool drain];
    return !(initialPassed && updatePassed);
}
