#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdio.h>

#if __has_feature(objc_arc)
#error This file tests manual-reference-counted outlet ownership.
#endif

@interface NSObject (LC32KVCIvarOwnership)
- (uint64_t)host_self;
@end
extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...);
extern BOOL LC32TestARCIvarOwnership(void);

// ARC's @autoreleasepool drains only the guest pool, not native return leases.
void *LC32TestCreateNativePool(void) { return [NSAutoreleasePool new]; }
void LC32TestDrainNativePool(void *pool) { [(NSAutoreleasePool *)pool drain]; }

void LC32TestSetHostValue(id owner, id value, NSString *key) {
    LC32InvokeHostSelector([owner host_self],
        LC32GetHostSelector(@selector(setValue:forKey:)),
        [value host_self], [key host_self], (uint64_t)0);
}

static unsigned checks, failures;
BOOL LC32TestIvarCheck(const char *name, BOOL passed) {
    ++checks;
    if(!passed) ++failures;
    printf("kvc-ivar-%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed;
}

@interface LC32MRCOutletOwner : NSObject {
    id _outlet;
    Class selectedClass;
}
- (id)outletValue;
- (Class)selectedClassValue;
@end
@implementation LC32MRCOutletOwner
- (id)outletValue { return _outlet; }
- (Class)selectedClassValue { return selectedClass; }
- (void)dealloc { [_outlet release]; [super dealloc]; }
@end
@interface LC32InheritedOutletOwner : LC32MRCOutletOwner
@end
@implementation LC32InheritedOutletOwner
@end

@interface LC32AssignSetterOwner : NSObject {
    id assignedValue;
    unsigned setterCalls;
}
- (void)setAssignedValue:(id)value;
- (unsigned)setterCalls;
@end
@implementation LC32AssignSetterOwner
- (void)setAssignedValue:(id)value { assignedValue = value; ++setterCalls; }
- (unsigned)setterCalls { return setterCalls; }
@end

// The controller and its bare MRC outlet each own the same native UIView,
// exactly as a nib's UIViewController view + outlet connections do.
@interface LC32OutletController : UIViewController {
    UIView *containerView;
}
@end
@implementation LC32OutletController
- (void)dealloc { [containerView release]; [super dealloc]; }
@end

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    NSAutoreleasePool *nativePool = [NSAutoreleasePool new];
    @autoreleasepool {
        LC32InheritedOutletOwner *owner = [LC32InheritedOutletOwner new];
        NSObject *first = [NSObject new], *second = [NSObject new];
        const NSUInteger firstBefore = first.retainCount;
        const NSUInteger secondBefore = second.retainCount;
        LC32TestSetHostValue(owner, first, @"_outlet");
        LC32TestIvarCheck("mrc-inherited-literal-outlet-retains",
            owner.outletValue == first && first.retainCount == firstBefore + 1);
        const NSUInteger assignedCount = first.retainCount;
        LC32TestSetHostValue(owner, first, @"outlet");
        LC32TestIvarCheck("self-assignment-balanced",
            owner.outletValue == first && first.retainCount == assignedCount);
        LC32TestSetHostValue(owner, second, @"outlet");
        LC32TestIvarCheck("replacement-releases-old-retains-new",
            first.retainCount == firstBefore &&
            second.retainCount == secondBefore + 1 && owner.outletValue == second);
        LC32TestSetHostValue(owner, nil, @"_outlet");
        LC32TestIvarCheck("nil-clears-and-releases",
            owner.outletValue == nil && second.retainCount == secondBefore);
        LC32TestSetHostValue(owner, NSObject.class, @"selectedClass");
        LC32TestIvarCheck("class-ivar", owner.selectedClassValue == NSObject.class);
        [owner release];

        LC32AssignSetterOwner *custom = [LC32AssignSetterOwner new];
        LC32TestSetHostValue(custom, first, @"assignedValue");
        LC32TestIvarCheck("real-assign-setter-preserved",
            custom.setterCalls == 1 && first.retainCount == firstBefore);
        [custom release];
        [first release];
        [second release];

        NSAutoreleasePool *controllerPool = [NSAutoreleasePool new];
        @autoreleasepool {
            LC32OutletController *controller = [LC32OutletController new];
            UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
            controller.view = view;
            const NSUInteger before = view.retainCount;
            LC32TestSetHostValue(controller, view, @"containerView");
            const BOOL owned = LC32TestIvarCheck("controller-outlet-has-own-reference",
                view.retainCount == before + 1);
            // A failing baseline must report the missing retain without
            // dereferencing the freed view during native superclass teardown.
            if(!owned) LC32TestSetHostValue(controller, nil, @"containerView");
            [view release];
            [controller release];
        }
        [controllerPool drain];
        LC32TestIvarCheck("controller-outlet-teardown", YES);
        LC32TestARCIvarOwnership();
    }
    [nativePool drain];
    printf("kvc-ivar-ownership: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
