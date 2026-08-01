#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation+LC32.h>

LC32_CONST_STR_DECL(NSString * const kCAFillModeBoth)
LC32_CONST_STR_DECL(NSString * const kCAFillModeBackwards)
LC32_CONST_STR_DECL(NSString * const kCAFillModeForwards)
LC32_CONST_STR_DECL(NSString * const kCAFillModeRemoved)

LC32_CONST_STR_DECL(NSString * const kCAGravityCenter)
LC32_CONST_STR_DECL(NSString * const kCAGravityTop)
LC32_CONST_STR_DECL(NSString * const kCAGravityLeft)
LC32_CONST_STR_DECL(NSString * const kCAGravityRight)
LC32_CONST_STR_DECL(NSString * const kCAGravityBottom)
LC32_CONST_STR_DECL(NSString * const kCAGravityTopLeft)
LC32_CONST_STR_DECL(NSString * const kCAGravityTopRight)
LC32_CONST_STR_DECL(NSString * const kCAGravityBottomLeft)
LC32_CONST_STR_DECL(NSString * const kCAGravityBottomRight)
LC32_CONST_STR_DECL(NSString * const kCAGravityResize)
LC32_CONST_STR_DECL(NSString * const kCAGravityResizeAspect)
LC32_CONST_STR_DECL(NSString * const kCAGravityResizeAspectFill)

LC32_CONST_STR_DECL(NSString * const kCAMediaTimingFunctionLinear)
LC32_CONST_STR_DECL(NSString * const kCAMediaTimingFunctionEaseIn)
LC32_CONST_STR_DECL(NSString * const kCAMediaTimingFunctionEaseOut)
LC32_CONST_STR_DECL(NSString * const kCAMediaTimingFunctionEaseInEaseOut)
LC32_CONST_STR_DECL(NSString * const kCAMediaTimingFunctionDefault)

LC32_CONST_STR_DECL(NSString * const kCATransitionFade);
LC32_CONST_STR_DECL(NSString * const kCATransitionMoveIn);
LC32_CONST_STR_DECL(NSString * const kCATransitionPush);
LC32_CONST_STR_DECL(NSString * const kCATransitionReveal);

__attribute__((constructor)) void QuartzCoreInit() {
    LC32_CONST_STR_INIT(kCAFillModeBoth);
    LC32_CONST_STR_INIT(kCAFillModeBackwards);
    LC32_CONST_STR_INIT(kCAFillModeForwards);
    LC32_CONST_STR_INIT(kCAFillModeRemoved);

    LC32_CONST_STR_INIT(kCAGravityCenter);
    LC32_CONST_STR_INIT(kCAGravityTop);
    LC32_CONST_STR_INIT(kCAGravityLeft);
    LC32_CONST_STR_INIT(kCAGravityRight);
    LC32_CONST_STR_INIT(kCAGravityBottom);
    LC32_CONST_STR_INIT(kCAGravityTopLeft);
    LC32_CONST_STR_INIT(kCAGravityTopRight);
    LC32_CONST_STR_INIT(kCAGravityBottomLeft);
    LC32_CONST_STR_INIT(kCAGravityBottomRight);
    LC32_CONST_STR_INIT(kCAGravityResize);
    LC32_CONST_STR_INIT(kCAGravityResizeAspect);
    LC32_CONST_STR_INIT(kCAGravityResizeAspectFill);

    LC32_CONST_STR_INIT(kCAMediaTimingFunctionLinear);
    LC32_CONST_STR_INIT(kCAMediaTimingFunctionEaseIn);
    LC32_CONST_STR_INIT(kCAMediaTimingFunctionEaseOut);
    LC32_CONST_STR_INIT(kCAMediaTimingFunctionEaseInEaseOut);
    LC32_CONST_STR_INIT(kCAMediaTimingFunctionDefault);

    LC32_CONST_STR_INIT(kCATransitionFade);
    LC32_CONST_STR_INIT(kCATransitionMoveIn);
    LC32_CONST_STR_INIT(kCATransitionPush);
    LC32_CONST_STR_INIT(kCATransitionReveal);
}
