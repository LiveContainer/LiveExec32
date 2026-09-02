#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdio.h>

int main(void) {
    @autoreleasepool {
        /* A non-nil payload exercises conversion of the guest object proxy
         * into the split 64-bit host pointer consumed by the typed wrapper. */
        UIAccessibilityPostNotification(
            UIAccessibilityLayoutChangedNotification,
            @"LC32 accessibility bridge");
    }
    puts("uikit-accessibility-post: PASS");
    return 0;
}
