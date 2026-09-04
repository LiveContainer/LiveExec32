#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Public Core Animation constants are objects owned by the native framework.
 * Give each exported guest pointer a stable proxy and bind it to the exact
 * host value at load time; spelling the symbol name as a string is not always
 * equivalent to the framework's value.
 */
#define LC32_QUARTZCORE_PUBLIC_STRING_CONSTANTS(X) \
    X(kCAAlignmentCenter) \
    X(kCAAlignmentJustified) \
    X(kCAAlignmentLeft) \
    X(kCAAlignmentNatural) \
    X(kCAAlignmentRight) \
    X(kCAAnimationCubic) \
    X(kCAAnimationCubicPaced) \
    X(kCAAnimationDiscrete) \
    X(kCAAnimationLinear) \
    X(kCAAnimationPaced) \
    X(kCAAnimationRotateAuto) \
    X(kCAAnimationRotateAutoReverse) \
    X(kCAContentsFormatGray8Uint) \
    X(kCAContentsFormatRGBA16Float) \
    X(kCAContentsFormatRGBA8Uint) \
    X(kCAEmitterBehaviorAlignToMotion) \
    X(kCAEmitterBehaviorAttractor) \
    X(kCAEmitterBehaviorColorOverLife) \
    X(kCAEmitterBehaviorDrag) \
    X(kCAEmitterBehaviorLight) \
    X(kCAEmitterBehaviorSimpleAttractor) \
    X(kCAEmitterBehaviorValueOverLife) \
    X(kCAEmitterBehaviorWave) \
    X(kCAEmitterLayerAdditive) \
    X(kCAEmitterLayerBackToFront) \
    X(kCAEmitterLayerCircle) \
    X(kCAEmitterLayerCuboid) \
    X(kCAEmitterLayerLine) \
    X(kCAEmitterLayerOldestFirst) \
    X(kCAEmitterLayerOldestLast) \
    X(kCAEmitterLayerOutline) \
    X(kCAEmitterLayerPoint) \
    X(kCAEmitterLayerPoints) \
    X(kCAEmitterLayerRectangle) \
    X(kCAEmitterLayerSphere) \
    X(kCAEmitterLayerSurface) \
    X(kCAEmitterLayerUnordered) \
    X(kCAEmitterLayerVolume) \
    X(kCAFillRuleEvenOdd) \
    X(kCAFillRuleNonZero) \
    X(kCAFilterLinear) \
    X(kCAFilterNearest) \
    X(kCAFilterTrilinear) \
    X(kCAGradientLayerAxial) \
    X(kCALineCapButt) \
    X(kCALineCapRound) \
    X(kCALineCapSquare) \
    X(kCALineJoinBevel) \
    X(kCALineJoinMiter) \
    X(kCALineJoinRound) \
    X(kCAOnOrderIn) \
    X(kCAOnOrderOut) \
    X(kCAScrollBoth) \
    X(kCAScrollHorizontally) \
    X(kCAScrollNone) \
    X(kCAScrollVertically) \
    X(kCATransactionAnimationDuration) \
    X(kCATransactionAnimationTimingFunction) \
    X(kCATransactionCompletionBlock) \
    X(kCATransition) \
    X(kCATruncationEnd) \
    X(kCATruncationMiddle) \
    X(kCATruncationNone) \
    X(kCATruncationStart) \
    X(kCAValueFunctionRotateX) \
    X(kCAValueFunctionRotateY) \
    X(kCAValueFunctionRotateZ) \
    X(kCAValueFunctionScale) \
    X(kCAValueFunctionScaleX) \
    X(kCAValueFunctionScaleY) \
    X(kCAValueFunctionScaleZ) \
    X(kCAValueFunctionTranslate) \
    X(kCAValueFunctionTranslateX) \
    X(kCAValueFunctionTranslateY) \
    X(kCAValueFunctionTranslateZ)

#define LC32_DECLARE_QUARTZCORE_CONSTANT(name) \
    LC32_CONST_STR_DECL(NSString *const name)
LC32_QUARTZCORE_PUBLIC_STRING_CONSTANTS(
    LC32_DECLARE_QUARTZCORE_CONSTANT)
#undef LC32_DECLARE_QUARTZCORE_CONSTANT

__attribute__((constructor))
static void LC32InitializeQuartzCorePublicConstants(void) {
#define LC32_INITIALIZE_QUARTZCORE_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_QUARTZCORE_PUBLIC_STRING_CONSTANTS(
        LC32_INITIALIZE_QUARTZCORE_CONSTANT)
#undef LC32_INITIALIZE_QUARTZCORE_CONSTANT
}
