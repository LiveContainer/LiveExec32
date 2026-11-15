#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <string.h>

// Deliberately do not link CoreTelephony. Forlorn discovers it at runtime.
@interface NSObject (LC32TelephonyLookupTest)
- (id)subscriberCellularProvider;
@end

int main(void) {
    @autoreleasepool {
        NSBundle *bundle = [NSBundle bundleWithPath:
            @"/System/Library/Frameworks/CoreTelephony.framework"];
        if(!bundle) {
            puts("bundle guest class lookup: SKIP (native bundle unavailable)");
            return 77;
        }
        Class cls = [bundle classNamed:@"CTTelephonyNetworkInfo"];
        if(!cls || strcmp(class_getName(cls), "CTTelephonyNetworkInfo")) {
            printf("bundle guest class lookup: FAIL (received %s)\n",
                cls ? class_getName(cls) : "nil");
            return 1;
        }
        id info = [[cls alloc] init];
        BOOL valid = info && [info respondsToSelector:@selector(subscriberCellularProvider)];
        if(valid) (void)[info subscriberCellularProvider]; // nil carrier is normal.
        valid = valid && [bundle classNamed:@"CTTelephonyNetworkInfo"] == cls &&
            [bundle classNamed:@"LC32NonexistentCarrier"] == Nil;
        [info release];
        puts(valid ? "bundle guest class lookup: PASS" : "bundle guest class lookup: FAIL");
        return !valid;
    }
}
