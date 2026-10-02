#import <SystemConfiguration/SystemConfiguration.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <LC32/LC32.h>
#import "LC32SystemConfigurationBridge.h"
#include <pthread.h>

static uint64_t dispatcher;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void resolveDispatcher(void) {
    dispatcher = LC32Dlsym("LC32_SystemConfiguration_Copy", YES);
}

static CFTypeRef copyQuery(LC32SCOpcode opcode, CFTypeRef object,
                          CFStringEncoding *encoding) {
    pthread_once(&once, resolveDispatcher);
    if(!dispatcher) { LC32SCSetError(kSCStatusFailed); return NULL; }
    LC32SCCopyCall call = {
        .version = 1, .status = kSCStatusFailed,
        .object = object ? [(id)object host_self] : 0,
    };
    uint32_t result = LC32InvokeHostCRet32(dispatcher, (uint32_t)opcode,
                                         (uint32_t)(uintptr_t)&call);
    LC32SCSetError(call.status);
    if(result && encoding) *encoding = call.encoding;
    return (CFTypeRef)(uintptr_t)result;
}

// These historical dynamic-store getters accept NULL for an implicit session.
// No configuration writes or subscription/session objects are implemented here.
CFStringRef SCDynamicStoreCopyComputerName(SCDynamicStoreRef store,
                                          CFStringEncoding *encoding) {
    return copyQuery(LC32SCOpCopyComputerName, store, encoding);
}
CFStringRef SCDynamicStoreCopyLocalHostName(SCDynamicStoreRef store) {
    return copyQuery(LC32SCOpCopyLocalHostName, store, NULL);
}
CFStringRef SCDynamicStoreCopyLocation(SCDynamicStoreRef store) {
    return copyQuery(LC32SCOpCopyLocation, store, NULL);
}
CFDictionaryRef SCDynamicStoreCopyProxies(SCDynamicStoreRef store) {
    return copyQuery(LC32SCOpCopyProxies, store, NULL);
}
CFArrayRef CNCopySupportedInterfaces(void) {
    return copyQuery(LC32SCOpCopySupportedInterfaces, NULL, NULL);
}
CFDictionaryRef CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    if(!interfaceName) { LC32SCSetError(kSCStatusInvalidArgument); return NULL; }
    return copyQuery(LC32SCOpCopyCurrentNetworkInfo, interfaceName, NULL);
}
