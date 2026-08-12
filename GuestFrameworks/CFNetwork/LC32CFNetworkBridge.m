#import <LC32/LC32.h>

#import "LC32CFNetworkBridge.h"

#include <pthread.h>
#include <string.h>

static pthread_once_t LC32CFNetworkDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32CFNetworkDispatcherAddress;

static void LC32CFNetworkResolveDispatcher(void) {
    LC32CFNetworkDispatcherAddress =
        LC32Dlsym("LC32_CFNetwork_Dispatch", YES);
}

uint32_t LC32CFNetworkDispatch(LC32CFNetworkOpcode opcode,
                               const uint64_t *slots,
                               uint32_t slotCount) {
    if(slotCount > LC32CFNetworkMaxSlots) return 0;
    pthread_once(&LC32CFNetworkDispatcherOnce,
                 LC32CFNetworkResolveDispatcher);
    if(!LC32CFNetworkDispatcherAddress) return 0;

    LC32CFNetworkCall call = {
        .version = LC32CFNetworkABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32CFNetworkDispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}
