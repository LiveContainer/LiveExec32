#import <NewsstandKit/NewsstandKit.h>
#import <Foundation/Foundation+LC32.h>

/* Preserve the native notification object's identity across the bridge. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const NKIssueDownloadCompletedNotification)

__attribute__((constructor)) static void LC32InitializeNewsstandKitConstants(void) {
    LC32LoadHostFramework("NewsstandKit");
    LC32_CONST_STR_INIT(NKIssueDownloadCompletedNotification);
}

#pragma clang diagnostic pop
