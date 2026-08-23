#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static IMP navigationOriginal;
static IMP backButtonOriginal;
static IMP buttonBackgroundOriginal;
static volatile int32_t navigationMetrics;
static volatile uint32_t backButtonState;
static volatile int32_t backButtonMetrics;
static volatile uint32_t buttonBackgroundState;
static volatile int32_t buttonBackgroundMetrics;

static void navigationSetter(id self, SEL selector, UIImage *image,
                             UIBarMetrics metrics) {
    navigationMetrics = (int32_t)metrics;
    ((void (*)(id, SEL, UIImage *, UIBarMetrics))navigationOriginal)(
        self, selector, image, metrics);
}

static void backButtonSetter(id self, SEL selector, UIImage *image,
                             UIControlState state, UIBarMetrics metrics) {
    backButtonState = (uint32_t)state;
    backButtonMetrics = (int32_t)metrics;
    ((void (*)(id, SEL, UIImage *, UIControlState, UIBarMetrics))
        backButtonOriginal)(self, selector, image, state, metrics);
}

static void buttonBackgroundSetter(id self, SEL selector, UIImage *image,
                                   UIControlState state,
                                   UIBarMetrics metrics) {
    buttonBackgroundState = (uint32_t)state;
    buttonBackgroundMetrics = (int32_t)metrics;
    ((void (*)(id, SEL, UIImage *, UIControlState, UIBarMetrics))
        buttonBackgroundOriginal)(self, selector, image, state, metrics);
}

static int report(const char *name, int passed) {
    printf("uikit-appearance-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    @autoreleasepool {
        Class appearanceClass = NSClassFromString(@"_UIAppearance");
        Method navigationMethod = class_getInstanceMethod(appearanceClass,
            @selector(setBackgroundImage:forBarMetrics:));
        Method backButtonMethod = class_getInstanceMethod(appearanceClass,
            @selector(setBackButtonBackgroundImage:forState:barMetrics:));
        Method buttonBackgroundMethod = class_getInstanceMethod(
            appearanceClass,
            @selector(setBackgroundImage:forState:barMetrics:));

        const int encodingsPassed =
            navigationMethod != NULL && backButtonMethod != NULL &&
            buttonBackgroundMethod != NULL &&
            strcmp(method_getTypeEncoding(navigationMethod),
                   "v16@0:4@8i12") == 0 &&
            strcmp(method_getTypeEncoding(backButtonMethod),
                   "v20@0:4@8I12i16") == 0 &&
            strcmp(method_getTypeEncoding(buttonBackgroundMethod),
                   "v20@0:4@8I12i16") == 0;

        if (encodingsPassed) {
            navigationOriginal = method_setImplementation(
                navigationMethod, (IMP)navigationSetter);
            backButtonOriginal = method_setImplementation(
                backButtonMethod, (IMP)backButtonSetter);
            buttonBackgroundOriginal = method_setImplementation(
                buttonBackgroundMethod, (IMP)buttonBackgroundSetter);
        }

        UINavigationBar *navigationAppearance =
            [UINavigationBar appearance];
        UIBarButtonItem *buttonAppearance =
            [UIBarButtonItem
                appearanceWhenContainedIn:UINavigationBar.class, nil];

        const int proxiesPassed =
            navigationAppearance != nil && buttonAppearance != nil;
        if (encodingsPassed && proxiesPassed) {
            [navigationAppearance setBackgroundImage:nil
                forBarMetrics:(UIBarMetrics)1];
            [buttonAppearance setBackButtonBackgroundImage:nil
                forState:UIControlStateHighlighted
                barMetrics:UIBarMetricsDefault];
            [buttonAppearance setBackgroundImage:nil
                forState:UIControlStateSelected
                barMetrics:(UIBarMetrics)1];
        }

        const int argumentsPassed =
            navigationMetrics == 1 &&
            backButtonState == (uint32_t)UIControlStateHighlighted &&
            backButtonMetrics == (int32_t)UIBarMetricsDefault &&
            buttonBackgroundState == (uint32_t)UIControlStateSelected &&
            buttonBackgroundMetrics == 1;

        if (encodingsPassed) {
            method_setImplementation(navigationMethod, navigationOriginal);
            method_setImplementation(backButtonMethod, backButtonOriginal);
            method_setImplementation(buttonBackgroundMethod,
                                     buttonBackgroundOriginal);
        }

        int passed = report("armv7-encodings", encodingsPassed);
        passed &= report("proxy-forwarding", proxiesPassed);
        passed &= report("argument-placement", argumentsPassed);
        printf("uikit-appearance-regression: %s\n",
            passed ? "PASS" : "FAIL");
        return !passed;
    }
}
