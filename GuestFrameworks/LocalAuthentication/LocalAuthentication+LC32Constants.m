#import <LocalAuthentication/LocalAuthentication.h>

NSString *const LC32_LAErrorDomain
    __asm__("_LAErrorDomain") = @"com.apple.LocalAuthentication";
const NSTimeInterval LC32_LATouchIDMaximumReuseDuration
    __asm__("_LATouchIDAuthenticationMaximumAllowableReuseDuration") = 300.0;
