#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static int first, second, failures;
static void check(const char *name, BOOL passed) {
    printf("cfnotification-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
static void callback(CFNotificationCenterRef center, void *observer,
        CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)name; (void)object; (void)info;
    (*(int *)observer)++;
}
int main(void) {
    @autoreleasepool {
        CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
        NSObject *sender = [NSObject new];
        CFNotificationCenterAddObserver(center, &first, callback, CFSTR("a"), sender, 0);
        CFNotificationCenterAddObserver(center, &first, callback, CFSTR("b"), sender, 0);
        CFNotificationCenterAddObserver(center, &second, callback, CFSTR("a"), sender, 0);
        CFNotificationCenterPostNotification(center, CFSTR("a"), sender, NULL, true);
        check("delivery", first == 1 && second == 1);
        CFNotificationCenterRemoveObserver(center, &first, CFSTR("a"), sender);
        CFNotificationCenterPostNotification(center, CFSTR("a"), sender, NULL, true);
        CFNotificationCenterPostNotification(center, CFSTR("b"), sender, NULL, true);
        check("filtered-removal", first == 2 && second == 2);
        CFNotificationCenterRemoveEveryObserver(center, &first);
        CFNotificationCenterPostNotification(center, CFSTR("b"), sender, NULL, true);
        CFNotificationCenterPostNotification(center, CFSTR("a"), sender, NULL, true);
        check("remove-every-keeps-other-observer", first == 2 && second == 3);
        CFNotificationCenterRemoveObserver(center, &second, NULL, NULL);
        CFNotificationCenterRemoveEveryObserver(center, &second);
        CFNotificationCenterPostNotification(center, CFSTR("a"), sender, NULL, true);
        check("wildcard-and-repeated-removal", second == 3);
        [sender release];
    }
    return failures ? 1 : 0;
}
