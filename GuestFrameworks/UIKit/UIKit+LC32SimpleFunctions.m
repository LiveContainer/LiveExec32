#import <UIKit/UIKit.h>
#import <LC32/LC32.h>

#include <pthread.h>
#include <ctype.h>
#include <stdlib.h>

#define LC32_UIKIT_RET32_NOARG(returnType, name, fallback) \
    static pthread_once_t LC32_##name##Once = PTHREAD_ONCE_INIT; \
    static uint64_t LC32_##name##Address; \
    static void LC32Resolve_##name(void) { \
        LC32_##name##Address = LC32Dlsym(#name, YES); \
    } \
    returnType name(void) { \
        pthread_once(&LC32_##name##Once, LC32Resolve_##name); \
        return LC32_##name##Address \
            ? (returnType)LC32InvokeHostCRet32(LC32_##name##Address) \
            : (returnType)(fallback); \
    }

LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityDarkerSystemColorsEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsAssistiveTouchRunning, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsBoldTextEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsClosedCaptioningEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsGrayscaleEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsInvertColorsEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsMonoAudioEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsReduceMotionEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsReduceTransparencyEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsShakeToUndoEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsSpeakScreenEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsSpeakSelectionEnabled, NO)
LC32_UIKIT_RET32_NOARG(BOOL,
    UIAccessibilityIsSwitchControlRunning, NO)
LC32_UIKIT_RET32_NOARG(UIAccessibilityHearingDeviceEar,
    UIAccessibilityHearingDevicePairedEar,
    UIAccessibilityHearingDeviceEarNone)

#undef LC32_UIKIT_RET32_NOARG

static pthread_once_t LC32RegisterZoomConflictOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32RegisterZoomConflictAddress;

static void LC32ResolveRegisterZoomConflict(void) {
    LC32RegisterZoomConflictAddress = LC32Dlsym(
        "UIAccessibilityRegisterGestureConflictWithZoom", YES);
}

void UIAccessibilityRegisterGestureConflictWithZoom(void) {
    pthread_once(&LC32RegisterZoomConflictOnce,
        LC32ResolveRegisterZoomConflict);
    if(LC32RegisterZoomConflictAddress) {
        (void)LC32InvokeHostCRet32(LC32RegisterZoomConflictAddress);
    }
}

static pthread_once_t LC32UIKitPublicCallsOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32ConvertAccessibilityFrameAddress;
static uint64_t LC32ConvertAccessibilityPathAddress;
static uint64_t LC32AccessibilityFocusedElementAddress;
static uint64_t LC32AccessibilityZoomFocusChangedAddress;
static uint64_t LC32GuidedAccessRestrictionStateAddress;
static uint64_t LC32VideoCompatibleWithSavedPhotosAddress;

static void LC32ResolveUIKitPublicCalls(void) {
    LC32ConvertAccessibilityFrameAddress = LC32Dlsym(
        "LC32_UIKit_UIAccessibilityConvertFrameToScreenCoordinates", YES);
    LC32ConvertAccessibilityPathAddress = LC32Dlsym(
        "LC32_UIKit_UIAccessibilityConvertPathToScreenCoordinates", YES);
    LC32AccessibilityFocusedElementAddress = LC32Dlsym(
        "LC32_UIKit_UIAccessibilityFocusedElement", YES);
    LC32AccessibilityZoomFocusChangedAddress = LC32Dlsym(
        "LC32_UIKit_UIAccessibilityZoomFocusChanged", YES);
    LC32GuidedAccessRestrictionStateAddress = LC32Dlsym(
        "LC32_UIKit_UIGuidedAccessRestrictionStateForIdentifier", YES);
    LC32VideoCompatibleWithSavedPhotosAddress = LC32Dlsym(
        "LC32_UIKit_UIVideoAtPathIsCompatibleWithSavedPhotosAlbum", YES);
}

static uint32_t LC32UIKitPublicFloatBits(CGFloat value) {
    union {
        float value;
        uint32_t bits;
    } converted = { .value = (float)value };
    return converted.bits;
}

static void LC32UIKitSplitHostObject(id object,
        uint32_t *low, uint32_t *high) {
    const uint64_t hostObject = [object host_self];
    *low = (uint32_t)hostObject;
    *high = (uint32_t)(hostObject >> 32);
}

CGRect UIAccessibilityConvertFrameToScreenCoordinates(
        CGRect rect, UIView *view) {
    pthread_once(&LC32UIKitPublicCallsOnce, LC32ResolveUIKitPublicCalls);
    if(!LC32ConvertAccessibilityFrameAddress || !view) return rect;

    CGRect result = CGRectZero;
    uint32_t viewLow;
    uint32_t viewHigh;
    LC32UIKitSplitHostObject(view, &viewLow, &viewHigh);
    const uint32_t wroteResult = LC32InvokeHostCRet32(
        LC32ConvertAccessibilityFrameAddress,
        (uint32_t)(uintptr_t)&result,
        LC32UIKitPublicFloatBits(rect.origin.x),
        LC32UIKitPublicFloatBits(rect.origin.y),
        LC32UIKitPublicFloatBits(rect.size.width),
        LC32UIKitPublicFloatBits(rect.size.height),
        viewLow, viewHigh);
    return wroteResult ? result : rect;
}

UIBezierPath *UIAccessibilityConvertPathToScreenCoordinates(
        UIBezierPath *path, UIView *view) {
    pthread_once(&LC32UIKitPublicCallsOnce, LC32ResolveUIKitPublicCalls);
    if(!LC32ConvertAccessibilityPathAddress || !path || !view) return path;

    uint32_t pathLow;
    uint32_t pathHigh;
    uint32_t viewLow;
    uint32_t viewHigh;
    LC32UIKitSplitHostObject(path, &pathLow, &pathHigh);
    LC32UIKitSplitHostObject(view, &viewLow, &viewHigh);
    const uint32_t guestPath = LC32InvokeHostCRet32(
        LC32ConvertAccessibilityPathAddress,
        pathLow, pathHigh, viewLow, viewHigh);
    return (__bridge UIBezierPath *)(void *)(uintptr_t)guestPath;
}

id UIAccessibilityFocusedElement(
        NSString *assistiveTechnologyIdentifier) {
    pthread_once(&LC32UIKitPublicCallsOnce, LC32ResolveUIKitPublicCalls);
    if(!LC32AccessibilityFocusedElementAddress) return nil;

    uint32_t identifierLow;
    uint32_t identifierHigh;
    LC32UIKitSplitHostObject(assistiveTechnologyIdentifier,
        &identifierLow, &identifierHigh);
    const uint32_t guestElement = LC32InvokeHostCRet32(
        LC32AccessibilityFocusedElementAddress,
        identifierLow, identifierHigh);
    return (__bridge id)(void *)(uintptr_t)guestElement;
}

void UIAccessibilityZoomFocusChanged(
        UIAccessibilityZoomType type, CGRect frame, UIView *view) {
    pthread_once(&LC32UIKitPublicCallsOnce, LC32ResolveUIKitPublicCalls);
    if(!LC32AccessibilityZoomFocusChangedAddress || !view) return;

    uint32_t viewLow;
    uint32_t viewHigh;
    LC32UIKitSplitHostObject(view, &viewLow, &viewHigh);
    (void)LC32InvokeHostCRet32(
        LC32AccessibilityZoomFocusChangedAddress,
        (uint32_t)type,
        LC32UIKitPublicFloatBits(frame.origin.x),
        LC32UIKitPublicFloatBits(frame.origin.y),
        LC32UIKitPublicFloatBits(frame.size.width),
        LC32UIKitPublicFloatBits(frame.size.height),
        viewLow, viewHigh);
}

UIGuidedAccessRestrictionState
UIGuidedAccessRestrictionStateForIdentifier(
        NSString *restrictionIdentifier) {
    pthread_once(&LC32UIKitPublicCallsOnce, LC32ResolveUIKitPublicCalls);
    if(!LC32GuidedAccessRestrictionStateAddress || !restrictionIdentifier) {
        return UIGuidedAccessRestrictionStateAllow;
    }

    uint32_t identifierLow;
    uint32_t identifierHigh;
    LC32UIKitSplitHostObject(restrictionIdentifier,
        &identifierLow, &identifierHigh);
    return (UIGuidedAccessRestrictionState)LC32InvokeHostCRet32(
        LC32GuidedAccessRestrictionStateAddress,
        identifierLow, identifierHigh);
}

BOOL UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(NSString *videoPath) {
    pthread_once(&LC32UIKitPublicCallsOnce, LC32ResolveUIKitPublicCalls);
    if(!LC32VideoCompatibleWithSavedPhotosAddress || !videoPath) return NO;

    uint32_t pathLow;
    uint32_t pathHigh;
    LC32UIKitSplitHostObject(videoPath, &pathLow, &pathHigh);
    return (BOOL)LC32InvokeHostCRet32(
        LC32VideoCompatibleWithSavedPhotosAddress, pathLow, pathHigh);
}

CTTextAlignment NSTextAlignmentToCTTextAlignment(
        NSTextAlignment alignment) {
    switch(alignment) {
        case NSTextAlignmentCenter: return kCTTextAlignmentCenter;
        case NSTextAlignmentRight: return kCTTextAlignmentRight;
        case NSTextAlignmentJustified: return kCTTextAlignmentJustified;
        case NSTextAlignmentNatural: return kCTTextAlignmentNatural;
        case NSTextAlignmentLeft:
        default: return kCTTextAlignmentLeft;
    }
}

NSTextAlignment NSTextAlignmentFromCTTextAlignment(
        CTTextAlignment alignment) {
    switch(alignment) {
        case kCTTextAlignmentCenter: return NSTextAlignmentCenter;
        case kCTTextAlignmentRight: return NSTextAlignmentRight;
        case kCTTextAlignmentJustified: return NSTextAlignmentJustified;
        case kCTTextAlignmentNatural: return NSTextAlignmentNatural;
        case kCTTextAlignmentLeft:
        default: return NSTextAlignmentLeft;
    }
}

static BOOL LC32ScanCGFloatList(NSString *string, char opening,
        char closing, CGFloat *values, size_t count) {
    const char *cursor = string.UTF8String;
    if(!cursor) return NO;
    while(isspace((unsigned char)*cursor)) ++cursor;
    if(*cursor++ != opening) return NO;

    for(size_t index = 0; index < count; ++index) {
        while(isspace((unsigned char)*cursor)) ++cursor;
        char *end = NULL;
        const float value = strtof(cursor, &end);
        if(end == cursor) return NO;
        values[index] = value;
        cursor = end;
        while(isspace((unsigned char)*cursor)) ++cursor;
        if(index + 1 < count && *cursor++ != ',') return NO;
    }

    while(isspace((unsigned char)*cursor)) ++cursor;
    if(*cursor++ != closing) return NO;
    while(isspace((unsigned char)*cursor)) ++cursor;
    return *cursor == '\0';
}

CGAffineTransform CGAffineTransformFromString(NSString *string) {
    CGFloat values[6];
    if(!LC32ScanCGFloatList(string, '[', ']', values, 6)) {
        return CGAffineTransformIdentity;
    }
    return CGAffineTransformMake(values[0], values[1], values[2],
        values[3], values[4], values[5]);
}

NSString *NSStringFromCGAffineTransform(CGAffineTransform transform) {
    return [NSString stringWithFormat:@"[%g, %g, %g, %g, %g, %g]",
        (double)transform.a, (double)transform.b,
        (double)transform.c, (double)transform.d,
        (double)transform.tx, (double)transform.ty];
}

UIEdgeInsets UIEdgeInsetsFromString(NSString *string) {
    CGFloat values[4];
    if(!LC32ScanCGFloatList(string, '{', '}', values, 4)) {
        return UIEdgeInsetsZero;
    }
    return UIEdgeInsetsMake(values[0], values[1], values[2], values[3]);
}

NSString *NSStringFromUIEdgeInsets(UIEdgeInsets insets) {
    return [NSString stringWithFormat:@"{%g, %g, %g, %g}",
        (double)insets.top, (double)insets.left,
        (double)insets.bottom, (double)insets.right];
}

BOOL UIFloatRangeIsEqualToRange(
        UIFloatRange first, UIFloatRange second) {
    return first.minimum == second.minimum &&
        first.maximum == second.maximum;
}

BOOL UIFloatRangeIsInfinite(UIFloatRange range) {
    return UIFloatRangeIsEqualToRange(range, UIFloatRangeInfinite);
}

CGPoint CGPointFromString(NSString *string) {
    const CGSize size = CGSizeFromString(string);
    return CGPointMake(size.width, size.height);
}

CGVector CGVectorFromString(NSString *string) {
    const CGSize size = CGSizeFromString(string);
    return CGVectorMake(size.width, size.height);
}

UIOffset UIOffsetFromString(NSString *string) {
    const CGSize size = CGSizeFromString(string);
    return UIOffsetMake(size.width, size.height);
}

NSString *NSStringFromCGVector(CGVector vector) {
    return NSStringFromCGSize(CGSizeMake(vector.dx, vector.dy));
}

NSString *NSStringFromUIOffset(UIOffset offset) {
    return NSStringFromCGSize(CGSizeMake(
        offset.horizontal, offset.vertical));
}

void UIRectClip(CGRect rect) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if(context) CGContextClipToRect(context, rect);
}

void UIRectFillUsingBlendMode(CGRect rect, CGBlendMode blendMode) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if(!context) return;
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, blendMode);
    CGContextFillRect(context, rect);
    CGContextRestoreGState(context);
}

void UIRectFrame(CGRect rect) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if(context) CGContextStrokeRect(context, rect);
}

void UIRectFrameUsingBlendMode(CGRect rect, CGBlendMode blendMode) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if(!context) return;
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, blendMode);
    CGContextStrokeRect(context, rect);
    CGContextRestoreGState(context);
}
