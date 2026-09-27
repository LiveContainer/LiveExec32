#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#include <stdio.h>

static unsigned deallocations;
static unsigned ordinaryDeallocations;
@interface LC32StoreDelegate : NSObject <SKProductsRequestDelegate>
@end

@interface LC32OrdinaryStoreDelegate : NSObject <SKProductsRequestDelegate>
@end
@implementation LC32OrdinaryStoreDelegate
- (void)productsRequest:(SKProductsRequest *)request
    didReceiveResponse:(SKProductsResponse *)response {}
- (void)dealloc { ++ordinaryDeallocations; [super dealloc]; }
@end
@implementation LC32StoreDelegate
- (id)retain { return self; }
- (NSUInteger)retainCount { return NSUIntegerMax; }
- (id)autorelease { return self; }
- (void)productsRequest:(SKProductsRequest *)request
    didReceiveResponse:(SKProductsResponse *)response {}
- (void)dealloc { ++deallocations; [super dealloc]; }
@end

int main(void) {
    @autoreleasepool {
        LC32StoreDelegate *delegate = [[LC32StoreDelegate alloc] init];
        SKProductsRequest *request = [[SKProductsRequest alloc]
            initWithProductIdentifiers:[NSSet setWithObject:@"lc32.test"]];
        request.delegate = delegate;
        BOOL valid = deallocations == 0 && request.delegate == delegate;
        request.delegate = nil;
        valid &= deallocations == 0 && request.delegate == nil;
        printf("storekit-nonretaining-delegate: %s\n", valid ? "PASS" : "FAIL");
        LC32OrdinaryStoreDelegate *ordinary;
        BOOL ordinaryValid;
        // NSAutoreleasePool drains the paired native pool as well as guest
        // temporaries created while returning the weak delegate.
        NSAutoreleasePool *getterPool = [NSAutoreleasePool new];
        ordinary = [[LC32OrdinaryStoreDelegate alloc] init];
        request.delegate = ordinary;
        ordinaryValid = request.delegate == ordinary;
        [getterPool drain];
        [ordinary release];
        ordinaryValid &= ordinaryDeallocations == 1 && request.delegate == nil;
        printf("storekit-weak-delegate-zeroing: %s (%u deallocations)\n",
            ordinaryValid ? "PASS" : "FAIL", ordinaryDeallocations);
        [request release];
        // Deliberately retain the singleton's original ownership until exit.
        return !(valid && ordinaryValid);
    }
}
