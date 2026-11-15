#import <Foundation/Foundation.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(__arm__)
@interface NSObject (LC32FloatingIvarTest)
- (uint64_t)host_self;
@end
extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...);
extern id LC32HostToGuestObject(uint64_t object);
#endif

static unsigned checks, failures;
static void check(const char *name, BOOL passed) {
    ++checks;
    if(!passed) ++failures;
    printf("kvc-floating-%s: %s\n", name, passed ? "PASS" : "FAIL");
}

// Deliberately no properties or accessors: native KVC must use the synthetic
// mirror accessors to reach these guest ivars, as with Forlorn's zoomValue.
@interface LC32FloatingIvars : NSObject {
@public
    uint32_t beforeFloat;
    float zoomValue;
    uint32_t afterFloat;
    double preciseValue;
    uint32_t afterDouble;
    float _offset;
    double _duration;
}
@end
@implementation LC32FloatingIvars
@end

@interface LC32InheritedFloatingIvars : LC32FloatingIvars
@end
@implementation LC32InheritedFloatingIvars
@end

// Reuse the selector with a different width and offset in an unrelated class.
@interface LC32OtherFloatingIvars : NSObject {
@public
    uint64_t padding[3];
    double zoomValue;
}
@end
@implementation LC32OtherFloatingIvars
@end

@interface LC32RealFloatingAccessors : NSObject {
@public
    float zoomValue;
    unsigned setterCalls;
}
- (void)setZoomValue:(float)value;
- (float)zoomValue;
@end
@implementation LC32RealFloatingAccessors
- (void)setZoomValue:(float)value { zoomValue = value * 2; ++setterCalls; }
- (float)zoomValue { return zoomValue + 1; }
@end

#if defined(__arm__)
static NSInvocation *hostInvocation(id owner, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    // The guest class has no actual method for a synthetic mirror accessor.
    uint64_t signature = LC32InvokeHostSelector([owner host_self],
        LC32GetHostSelector(@selector(methodSignatureForSelector:)),
        LC32GetHostSelector(selector), (uint64_t)0);
    NSMethodSignature *method = LC32HostToGuestObject(signature);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:method];
    invocation.target = owner;
    invocation.selector = selector;
    return invocation;
}

static void checkRawAccessors(LC32FloatingIvars *owner) {
    const uint32_t floats[] = {0xc19e0000, 0x80000000, 0x7fc01234, 1};
    const uint64_t doubles[] = {
        UINT64_C(0xc093488000000000), UINT64_C(0x8000000000000000),
        UINT64_C(0x7ff800000000cafe), UINT64_C(0x3ff0000000000001)
    };
    NSInvocation *floatSetter = hostInvocation(owner, @"setZoomValue:");
    NSInvocation *floatGetter = hostInvocation(owner, @"zoomValue");
    NSInvocation *doubleSetter = hostInvocation(owner, @"setPreciseValue:");
    NSInvocation *doubleGetter = hostInvocation(owner, @"preciseValue");
    for(unsigned i = 0; i < sizeof(floats) / sizeof(*floats); ++i) {
        uint32_t actual = 0, returned = 0;
        [floatSetter setArgument:(void *)&floats[i] atIndex:2];
        [floatSetter invoke];
        memcpy(&actual, &owner->zoomValue, sizeof(actual));
        [floatGetter invoke];
        [floatGetter getReturnValue:&returned];
        check("float-accessor-bits", actual == floats[i] && returned == floats[i]);
    }
    for(unsigned i = 0; i < sizeof(doubles) / sizeof(*doubles); ++i) {
        uint64_t actual = 0, returned = 0;
        [doubleSetter setArgument:(void *)&doubles[i] atIndex:2];
        [doubleSetter invoke];
        memcpy(&actual, &owner->preciseValue, sizeof(actual));
        [doubleGetter invoke];
        [doubleGetter getReturnValue:&returned];
        check("double-accessor-bits", actual == doubles[i] && returned == doubles[i]);
    }
}
#endif

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    LC32InheritedFloatingIvars *owner = [LC32InheritedFloatingIvars new];
    owner->beforeFloat = 0x12345678;
    owner->afterFloat = 0x89abcdef;
    owner->afterDouble = 0xa5a5a5a5;
    [owner setValue:@1.25f forKey:@"zoomValue"];
    check("inherited-float-set", owner->zoomValue == 1.25f);
    owner->zoomValue = -19.125f;
    check("inherited-float-get", [[owner valueForKey:@"zoomValue"] floatValue] == -19.125f);
    const double precise = 1.0000000000000002;
    [owner setValue:[NSNumber numberWithDouble:precise] forKey:@"preciseValue"];
    check("double-set-precision", owner->preciseValue == precise);
    owner->preciseValue = -123456.875;
    check("double-get", [[owner valueForKey:@"preciseValue"] doubleValue] == -123456.875);

    [owner setValue:@2.5f forKey:@"offset"];
    check("underscore-float-logical", owner->_offset == 2.5f &&
        [[owner valueForKey:@"offset"] floatValue] == 2.5f);
    [owner setValue:@(-3.75f) forKey:@"_offset"];
    check("underscore-float-literal", owner->_offset == -3.75f &&
        [[owner valueForKey:@"_offset"] floatValue] == -3.75f);
    [owner setValue:@4.125 forKey:@"duration"];
    check("underscore-double-logical", owner->_duration == 4.125 &&
        [[owner valueForKey:@"duration"] doubleValue] == 4.125);
    [owner setValue:[NSNumber numberWithDouble:precise] forKey:@"_duration"];
    check("underscore-double-literal", owner->_duration == precise &&
        [[owner valueForKey:@"_duration"] doubleValue] == precise);

    LC32OtherFloatingIvars *other = [LC32OtherFloatingIvars new];
    [other setValue:[NSNumber numberWithDouble:precise] forKey:@"zoomValue"];
    check("per-class-binding", other->zoomValue == precise &&
        [[other valueForKey:@"zoomValue"] doubleValue] == precise &&
        owner->zoomValue == -19.125f);
    LC32RealFloatingAccessors *custom = [LC32RealFloatingAccessors new];
    [custom setValue:@3.5f forKey:@"zoomValue"];
    check("real-setter-preserved", custom->zoomValue == 7 && custom->setterCalls == 1);
    check("real-getter-preserved", [[custom valueForKey:@"zoomValue"] floatValue] == 8);
#if defined(__arm__)
    checkRawAccessors(owner);
#endif
    check("adjacent-ivars-intact", owner->beforeFloat == 0x12345678 &&
        owner->afterFloat == 0x89abcdef && owner->afterDouble == 0xa5a5a5a5);
    [custom release];
    [other release];
    [owner release];
    [pool drain];
    printf("kvc-floating-ivars: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
