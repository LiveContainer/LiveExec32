#import <Foundation/Foundation.h>

#include <stdio.h>

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    id value = nil;

    @try {
        value = [NSMutableString stringWithUTF8String:NULL];
        printf("foundation-null-utf8: returned %s\n",
            value ? "object" : "nil");
    } @catch(NSException *exception) {
        printf("foundation-null-utf8: threw %s\n",
            [[exception name] UTF8String]);
    }

    [pool drain];
    return 0;
}
