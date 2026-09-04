#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import <Foundation/Foundation+LC32.h>

const NSUInteger kMCSessionMinimumNumberOfPeers = 2;
const NSUInteger kMCSessionMaximumNumberOfPeers = 8;

LC32_CONST_STR_DECL(__typeof__(MCErrorDomain) MCErrorDomain)

__attribute__((constructor))
static void LC32InitializeMultipeerConnectivityObjectConstants(void) {
    LC32LoadHostFramework("MultipeerConnectivity");
    LC32_CONST_STR_INIT(MCErrorDomain);
}
