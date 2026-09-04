#import <ReplayKit/ReplayKit.h>
#import <Foundation/Foundation+LC32.h>

/* Preserve the native NSError domain object's identity across the bridge. */
LC32_CONST_STR_DECL(NSString *const RPRecordingErrorDomain)

__attribute__((constructor)) static void LC32InitializeReplayKitConstants(void) {
    LC32LoadHostFramework("ReplayKit");
    LC32_CONST_STR_INIT(RPRecordingErrorDomain);
}
