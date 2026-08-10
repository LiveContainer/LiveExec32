#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <math.h>
#include <stdio.h>

@interface NSObject (LC32GuestFPReturnTest)
- (uint64_t)host_self;
@end

extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t object,
                                       uint64_t selector, ...);
extern id LC32HostToGuestObject(uint64_t hostObject);

static id LC32HostValueForKey(id object, NSString *key) {
    const uint64_t hostResult = LC32InvokeHostSelector(
        [object host_self],
        LC32GetHostSelector(@selector(valueForKey:)),
        [key host_self], (uint64_t)0);
    return LC32HostToGuestObject(hostResult);
}

/*
 * KVC runs on the ARM64 host mirror and invokes these guest implementations.
 * That exercises the host-to-guest Objective-C callback path instead of a
 * direct ARM32 objc_msgSend between guest objects.
 */
@interface LC32GuestFloatProbe : NSObject
- (float)lc32FloatValue;
- (double)lc32DoubleValue;
@end

@implementation LC32GuestFloatProbe
- (float)lc32FloatValue {
    return 19.75f;
}

- (double)lc32DoubleValue {
    return 1234.125;
}
@end

@interface LC32GuestCGFloatView : UIView
@end

@implementation LC32GuestCGFloatView
- (CGFloat)alpha {
    return 0.625f;
}
@end

@interface LC32GuestTableDelegateBase : NSObject
    <UITableViewDelegate>
@end

@implementation LC32GuestTableDelegateBase
@end

@interface LC32GuestTableDelegate : LC32GuestTableDelegateBase
    <UITableViewDataSource> {
    NSUInteger heightCallbackCount;
}
- (NSUInteger)heightCallbackCount;
@end

@implementation LC32GuestTableDelegate
- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return [[[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleDefault
        reuseIdentifier:nil] autorelease];
}

- (CGFloat)tableView:(UITableView *)tableView
 heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    heightCallbackCount++;
    return 37.5f;
}

- (NSUInteger)heightCallbackCount {
    return heightCallbackCount;
}
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    LC32GuestFloatProbe *floatProbe = [LC32GuestFloatProbe new];
    NSNumber *boxedFloat =
        LC32HostValueForKey(floatProbe, @"lc32FloatValue");
    const BOOL floatPassed =
        fabsf(boxedFloat.floatValue - 19.75f) < 0.0001f;
    printf("host-callback-float-return: %s\n",
           floatPassed ? "PASS" : "FAIL");

    NSNumber *boxedDouble =
        LC32HostValueForKey(floatProbe, @"lc32DoubleValue");
    const BOOL doublePassed =
        fabs(boxedDouble.doubleValue - 1234.125) < 0.0001;
    printf("host-callback-double-return: %s\n",
           doublePassed ? "PASS" : "FAIL");

    /*
     * CGFloat is `f` in the ARMv7 guest but `d` in the ARM64 UIView method.
     * The native superclass encoding must therefore select a double-returning
     * host IMP while the guest r0 payload is still decoded as a float.
     */
    LC32GuestCGFloatView *view = [LC32GuestCGFloatView new];
    NSNumber *boxedCGFloat = LC32HostValueForKey(view, @"alpha");
    const BOOL cgFloatPassed =
        fabs(boxedCGFloat.doubleValue - 0.625) < 0.0001;
    printf("host-callback-cgfloat-return: %s\n",
           cgFloatPassed ? "PASS" : "FAIL");

    /* UITableViewDelegate declares CGFloat on the host, but the guest class
     * has no native superclass implementation and inherits its protocol
     * adoption from LC32GuestTableDelegateBase. */
    LC32GuestTableDelegate *tableDelegate =
        [LC32GuestTableDelegate new];
    UITableView *tableView = [[UITableView alloc]
        initWithFrame:CGRectMake(0, 0, 320, 480)
        style:UITableViewStylePlain];
    tableView.dataSource = tableDelegate;
    tableView.delegate = tableDelegate;
    [tableView reloadData];
    [tableView layoutIfNeeded];
    const CGRect rowRect = [tableView rectForRowAtIndexPath:
        [NSIndexPath indexPathForRow:0 inSection:0]];
    const BOOL protocolCGFloatPassed =
        tableDelegate.heightCallbackCount > 0 &&
        fabs(rowRect.size.height - 37.5) < 0.0001;
    printf("host-protocol-cgfloat-return: %s\n",
           protocolCGFloatPassed ? "PASS" : "FAIL");

    [tableView release];
    [tableDelegate release];
    [view release];
    [floatProbe release];
    [pool drain];
    return !(floatPassed && doublePassed && cgFloatPassed &&
             protocolCGFloatPassed);
}
