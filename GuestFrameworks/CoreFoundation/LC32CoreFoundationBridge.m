#import <CoreFoundation/CoreFoundation+LC32.h>

#include <pthread.h>
#include <string.h>

static pthread_once_t LC32CoreFoundationDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32CoreFoundationDispatcherAddress;

static void LC32CoreFoundationResolveDispatcher(void) {
    LC32CoreFoundationDispatcherAddress =
        LC32Dlsym("LC32_CoreFoundation_Dispatch", YES);
}

uint32_t LC32CoreFoundationDispatch(LC32CoreFoundationOpcode opcode,
                                    const uint64_t *slots,
                                    uint32_t slotCount) {
    if(slotCount > LC32CoreFoundationMaxSlots) return 0;
    pthread_once(&LC32CoreFoundationDispatcherOnce,
                 LC32CoreFoundationResolveDispatcher);
    if(!LC32CoreFoundationDispatcherAddress) return 0;

    LC32CoreFoundationCall call = {
        .version = LC32CoreFoundationABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32CoreFoundationDispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}
