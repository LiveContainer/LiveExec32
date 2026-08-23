#import <LC32/LC32.h>
#import <Security/Security.h>

#import "LC32SecurityBridge.h"

#include <pthread.h>
#include <string.h>

static pthread_once_t LC32SecurityDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32SecurityDispatcherAddress;

static void LC32SecurityResolveDispatcher(void) {
    LC32SecurityDispatcherAddress =
        LC32Dlsym("LC32_Security_Dispatch", YES);
}

uint32_t LC32SecurityDispatch(LC32SecurityOpcode opcode,
                              const uint64_t *slots,
                              uint32_t slotCount,
                              OSStatus *status) {
    if(status) *status = errSecUnimplemented;
    if(slotCount > LC32SecurityMaxSlots) {
        if(status) *status = errSecParam;
        return 0;
    }

    pthread_once(&LC32SecurityDispatcherOnce,
                 LC32SecurityResolveDispatcher);
    if(!LC32SecurityDispatcherAddress) return 0;

    LC32SecurityCall call = {
        .version = LC32SecurityABIVersion,
        .slotCount = slotCount,
        .status = errSecUnimplemented,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    const uint32_t guestResult = LC32InvokeHostCRet32(
        LC32SecurityDispatcherAddress, (uint32_t)opcode,
        (uint32_t)(uintptr_t)&call);
    if(status) *status = call.status;
    return guestResult;
}
