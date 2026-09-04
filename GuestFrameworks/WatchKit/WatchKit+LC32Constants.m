#import <WatchKit/WatchKit.h>
#import <Foundation/Foundation+LC32.h>

LC32_CONST_STR_DECL(__typeof__(WatchKitErrorDomain) WatchKitErrorDomain)

__attribute__((constructor))
static void LC32InitializeWatchKitObjectConstants(void) {
    LC32LoadHostFramework("WatchKit");
    LC32_CONST_STR_INIT(WatchKitErrorDomain);
}
