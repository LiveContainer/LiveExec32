#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        // Ensure UIKit is loaded even though the two compatibility classes
        // deliberately have no declaration in the original guest SDK.
        (void)[UIKeyCommand class];
        Class element = NSClassFromString(@"UIMenuElement");
        Class command = NSClassFromString(@"UICommand");
        BOOL valid = element && command &&
            class_getSuperclass(element) == NSObject.class &&
            class_getSuperclass(command) == element &&
            class_getInstanceMethod(element, sel_registerName("initWithHostSelf:")) &&
            class_getInstanceMethod(command, @selector(methodSignatureForSelector:));
        printf("uikit-menu-class-hierarchy: %s\n", valid ? "PASS" : "FAIL");
        return !valid;
    }
}
