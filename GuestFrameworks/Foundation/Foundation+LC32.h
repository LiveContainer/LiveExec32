#import <LC32/LC32.h>
#import <Foundation/Foundation.h>

/*
 * Each exported pointer must name a distinct guest Objective-C object.  Keep
 * the complete ARM32 constant-string representation even though a normally
 * available native constant is resolved through LC32's host-object registry.
 * If an older host OS does not export a newer constant, the remaining fields
 * are populated with the symbol's spelling and the proxy can safely take the
 * ordinary lazy constant-string bridge path.
 */
#if __has_feature(objc_arc)
#define LC32_CONST_STR_ID(POINTER) (__bridge id)(POINTER)
#else
#define LC32_CONST_STR_ID(POINTER) (id)(POINTER)
#endif

#define LC32_CONST_STR_DECL(NAME) \
    NAME = LC32_CONST_STR_ID((&(LC32ConstantStringProxy){ \
        __CFConstantStringClassReference, 0x7c8, NULL, 0 \
    }));
#define LC32_CONST_STR_INIT(NAME) \
    LC32BindHostObjectConstant((id)NAME, #NAME)

extern int __CFConstantStringClassReference[];
