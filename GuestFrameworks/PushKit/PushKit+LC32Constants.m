#import <PushKit/PushKit.h>
#import <Foundation/Foundation+LC32.h>

/* Push types are native string-enum objects, not guest string copies. */
LC32_CONST_STR_DECL(PKPushType const PKPushTypeComplication)
LC32_CONST_STR_DECL(PKPushType const PKPushTypeVoIP)

__attribute__((constructor)) static void LC32InitializePushKitConstants(void) {
    LC32LoadHostFramework("PushKit");
    LC32_CONST_STR_INIT(PKPushTypeComplication);
    LC32_CONST_STR_INIT(PKPushTypeVoIP);
}
