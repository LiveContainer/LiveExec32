#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <stdio.h>

static unsigned failures;
static void check(BOOL passed, const char *name) {
    printf("legacy-nib-class-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        Class legacy = NSClassFromString(@"UIRoundedRectButton");
        check(legacy && [legacy isSubclassOfClass:UIButton.class], "registered-button");
        if(!legacy) return 1;

        // A repeated install must preserve an existing class and its methods.
        IMP initializer = class_getMethodImplementation(legacy, @selector(initWithCoder:));
        [NSClassFromString(@"LC32LegacyNibClasses") performSelector:@selector(load)];
        check(NSClassFromString(@"UIRoundedRectButton") == legacy &&
              class_getMethodImplementation(legacy, @selector(initWithCoder:)) == initializer,
              "existing-class-preserved");
        check(NSClassFromString(@"LC32UnknownNibClass") == Nil, "no-generic-fallback");

        UIButton *source = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        source.frame = CGRectMake(10, 20, 75, 33);
        [source setTitle:@"Set" forState:UIControlStateNormal];
        [source setTitle:@"Pressed" forState:UIControlStateHighlighted];
        source.enabled = NO;
        source.selected = YES;
        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *encoder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [encoder setClassName:@"UIRoundedRectButton" forClass:source.class];
        [encoder encodeObject:source forKey:NSKeyedArchiveRootObjectKey];
        [encoder finishEncoding];

        NSKeyedUnarchiver *decoder = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        UIButton *decoded = [decoder decodeObjectForKey:NSKeyedArchiveRootObjectKey];
        [decoder finishDecoding];
        check([decoded isKindOfClass:legacy], "archived-name-resolved");
        check(decoded.buttonType == source.buttonType, "rounded-button-type");
        check([[decoded titleForState:UIControlStateNormal] isEqualToString:@"Set"] &&
              [[decoded titleForState:UIControlStateHighlighted] isEqualToString:@"Pressed"],
              "stateful-content");
        check(!decoded.enabled && decoded.selected, "control-state");
        check(CGRectEqualToRect(decoded.frame, source.frame), "frame");
        printf("legacy-nib-classes: %u failures\n", failures);
    }
    return failures ? 1 : 0;
}
