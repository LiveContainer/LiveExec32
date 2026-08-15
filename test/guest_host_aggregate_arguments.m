#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <math.h>
#include <stdio.h>

static BOOL LC32CGFloatNear(CGFloat first, CGFloat second) {
    return fabsf(first - second) < 0.0001f;
}

static BOOL LC32TransformNear(CGAffineTransform first,
                              CGAffineTransform second) {
    return LC32CGFloatNear(first.a, second.a) &&
        LC32CGFloatNear(first.b, second.b) &&
        LC32CGFloatNear(first.c, second.c) &&
        LC32CGFloatNear(first.d, second.d) &&
        LC32CGFloatNear(first.tx, second.tx) &&
        LC32CGFloatNear(first.ty, second.ty);
}

static NSUInteger LC32SizeThatFitsCallCount;
static CGSize LC32SizeThatFitsInput;
static NSUInteger LC32LeftViewRectCallCount;
static CGRect LC32LeftViewRectInput;
static NSUInteger LC32PointInsideCallCount;
static CGPoint LC32PointInsideInput;
static UIEvent *LC32PointInsideEvent;

@interface LC32SizeThatFitsProbe : UIView
@end

@interface LC32RectReturningTextFieldProbe : UITextField
@end

@interface LC32PointInsideProbe : UIView
@end

@implementation LC32PointInsideProbe
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    LC32PointInsideCallCount++;
    LC32PointInsideInput = point;
    LC32PointInsideEvent = event;
    return point.x >= 0 && point.y >= 0 &&
        point.x < self.bounds.size.width &&
        point.y < self.bounds.size.height;
}
@end

@implementation LC32RectReturningTextFieldProbe
- (CGRect)leftViewRectForBounds:(CGRect)bounds {
    LC32LeftViewRectCallCount++;
    LC32LeftViewRectInput = bounds;
    return CGRectMake(bounds.origin.x + 7.25f,
                      bounds.origin.y + 5.5f,
                      31.25f, 18.5f);
}
@end

@implementation LC32SizeThatFitsProbe
- (CGSize)sizeThatFits:(CGSize)size {
    LC32SizeThatFitsCallCount++;
    LC32SizeThatFitsInput = size;
    return CGSizeMake(73.25f, 41.5f);
}
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    UIView *root = [[UIView alloc]
        initWithFrame:CGRectMake(0, 0, 512, 512)];
    UIView *source = [[UIView alloc]
        initWithFrame:CGRectMake(17, 29, 80, 60)];
    UIView *destination = [[UIView alloc]
        initWithFrame:CGRectMake(101, 211, 70, 50)];
    [root addSubview:source];
    [root addSubview:destination];
    const CGPoint converted = [source
        convertPoint:CGPointMake(3.25f, 4.5f)
        toView:destination];
    const BOOL hfaObjectPassed =
        LC32CGFloatNear(converted.x, -80.75f) &&
        LC32CGFloatNear(converted.y, -177.5f);
    printf("guest-host-aggregate-hfa-trailing-object: %s\n",
        hfaObjectPassed ? "PASS" : "FAIL");

    UIView *transformView = [[UIView alloc]
        initWithFrame:CGRectMake(0, 0, 120, 80)];
    const CGAffineTransform sent = {
        1.25f, -2.5f, 3.75f, -4.125f, 91.5f, -72.25f
    };
    transformView.transform = sent;
    const CGAffineTransform received = transformView.transform;
    const BOOL indirectPassed = LC32TransformNear(received, sent);
    printf("guest-host-aggregate-large-indirect: %s\n",
        indirectPassed ? "PASS" : "FAIL");

    LC32SizeThatFitsProbe *probe = [[LC32SizeThatFitsProbe alloc]
        initWithFrame:CGRectMake(7, 11, 91, 53)];
    [root addSubview:probe];
    [probe sizeToFit];
    const CGSize fitted = probe.bounds.size;
    const BOOL callbackPassed = LC32SizeThatFitsCallCount == 1 &&
        isfinite(LC32SizeThatFitsInput.width) &&
        isfinite(LC32SizeThatFitsInput.height) &&
        LC32CGFloatNear(fitted.width, 73.25f) &&
        LC32CGFloatNear(fitted.height, 41.5f);
    printf("host-guest-aggregate-cgsize-in-out: %s\n",
        callbackPassed ? "PASS" : "FAIL");

    LC32RectReturningTextFieldProbe *textField =
        [[LC32RectReturningTextFieldProbe alloc]
            initWithFrame:CGRectMake(13, 17, 180, 48)];
    UIView *leftView = [[UIView alloc]
        initWithFrame:CGRectMake(0, 0, 3, 3)];
    textField.leftView = leftView;
    textField.leftViewMode = UITextFieldViewModeAlways;
    [root addSubview:textField];
    [textField setNeedsLayout];
    [textField layoutIfNeeded];
    const CGRect leftFrame = leftView.frame;
    const BOOL rectCallbackPassed = LC32LeftViewRectCallCount > 0 &&
        isfinite(LC32LeftViewRectInput.size.width) &&
        isfinite(LC32LeftViewRectInput.size.height) &&
        LC32CGFloatNear(leftFrame.origin.x,
            LC32LeftViewRectInput.origin.x + 7.25f) &&
        LC32CGFloatNear(leftFrame.origin.y,
            LC32LeftViewRectInput.origin.y + 5.5f) &&
        LC32CGFloatNear(leftFrame.size.width, 31.25f) &&
        LC32CGFloatNear(leftFrame.size.height, 18.5f);
    printf("host-guest-aggregate-cgrect-in-out: %s\n",
        rectCallbackPassed ? "PASS" : "FAIL");

    LC32PointInsideProbe *pointProbe = [[LC32PointInsideProbe alloc]
        initWithFrame:CGRectMake(0, 0, 100, 80)];
    const CGPoint hitPoint = CGPointMake(23.25f, 37.5f);
    UIView *hitView = [pointProbe hitTest:hitPoint withEvent:nil];
    const BOOL pointCallbackPassed =
        LC32PointInsideCallCount == 1 &&
        LC32CGFloatNear(LC32PointInsideInput.x, hitPoint.x) &&
        LC32CGFloatNear(LC32PointInsideInput.y, hitPoint.y) &&
        LC32PointInsideEvent == nil && hitView == pointProbe;
    printf("host-guest-aggregate-cgpoint-object: %s\n",
        pointCallbackPassed ? "PASS" : "FAIL");

    [pointProbe release];
    [leftView release];
    [textField release];
    [probe release];
    [transformView release];
    [source release];
    [destination release];
    [root release];
    [pool drain];
    return hfaObjectPassed && indirectPassed && callbackPassed &&
        rectCallbackPassed && pointCallbackPassed ? 0 : 1;
}
