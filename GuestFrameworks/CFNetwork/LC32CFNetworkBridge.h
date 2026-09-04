#ifndef LC32_CFNETWORK_BRIDGE_H
#define LC32_CFNETWORK_BRIDGE_H

#include <stdint.h>

enum {
    LC32CFNetworkABIVersion = 1,
    LC32CFNetworkMaxSlots = 6,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32CFNetworkMaxSlots];
} LC32CFNetworkCall;

typedef enum : uint32_t {
    LC32CFNetworkOpHTTPMessageAppendBytes = 1,
    LC32CFNetworkOpHTTPMessageCopyAllHeaderFields = 2,
    LC32CFNetworkOpHTTPMessageCopyBody = 3,
    LC32CFNetworkOpHTTPMessageCopyHeaderFieldValue = 4,
    LC32CFNetworkOpHTTPMessageCopyRequestMethod = 5,
    LC32CFNetworkOpHTTPMessageCopyRequestURL = 6,
    LC32CFNetworkOpHTTPMessageCopySerializedMessage = 7,
    LC32CFNetworkOpHTTPMessageCopyVersion = 8,
    LC32CFNetworkOpHTTPMessageCreateEmpty = 9,
    LC32CFNetworkOpHTTPMessageCreateRequest = 10,
    LC32CFNetworkOpHTTPMessageCreateResponse = 11,
    LC32CFNetworkOpHTTPMessageGetResponseStatusCode = 12,
    LC32CFNetworkOpHTTPMessageIsHeaderComplete = 13,
    LC32CFNetworkOpHTTPMessageSetBody = 14,
    LC32CFNetworkOpHTTPMessageSetHeaderFieldValue = 15,
    LC32CFNetworkOpCopySystemProxySettings = 16,
    LC32CFNetworkOpReadStreamCreateForHTTPRequest = 17,
    LC32CFNetworkOpCopyProxiesForURL = 18,
    LC32CFNetworkOpHTTPMessageCopyResponseStatusLine = 19,
    LC32CFNetworkOpHTTPMessageCreateCopy = 20,
    LC32CFNetworkOpHTTPMessageGetTypeID = 21,
    LC32CFNetworkOpHTTPMessageIsRequest = 22,
    LC32CFNetworkOpHTTPAuthenticationGetTypeID = 23,
    LC32CFNetworkOpHTTPAuthenticationCreateFromResponse = 24,
    LC32CFNetworkOpHTTPAuthenticationAppliesToRequest = 25,
    LC32CFNetworkOpHTTPAuthenticationRequiresOrderedRequests = 26,
    LC32CFNetworkOpHTTPAuthenticationCopyRealm = 27,
    LC32CFNetworkOpHTTPAuthenticationCopyDomains = 28,
    LC32CFNetworkOpHTTPAuthenticationCopyMethod = 29,
    LC32CFNetworkOpHTTPAuthenticationRequiresUserNameAndPassword = 30,
    LC32CFNetworkOpHTTPAuthenticationRequiresAccountDomain = 31,
    LC32CFNetworkOpHTTPAuthenticationIsValid = 32,
    LC32CFNetworkOpHTTPMessageAddAuthentication = 33,
    LC32CFNetworkOpHTTPMessageApplyCredentials = 34,
    LC32CFNetworkOpHTTPMessageApplyCredentialDictionary = 35,
    LC32CFNetworkOpHostGetTypeID = 36,
    LC32CFNetworkOpHostCreateWithName = 37,
    LC32CFNetworkOpHostCreateWithAddress = 38,
    LC32CFNetworkOpHostCreateCopy = 39,
    LC32CFNetworkOpHostGetAddressing = 40,
    LC32CFNetworkOpHostGetNames = 41,
    LC32CFNetworkOpHostGetReachability = 42,
    LC32CFNetworkOpNetServiceGetTypeID = 43,
    LC32CFNetworkOpNetServiceCreate = 44,
    LC32CFNetworkOpNetServiceCreateCopy = 45,
    LC32CFNetworkOpNetServiceGetDomain = 46,
    LC32CFNetworkOpNetServiceGetType = 47,
    LC32CFNetworkOpNetServiceGetName = 48,
    LC32CFNetworkOpNetServiceGetTargetHost = 49,
    LC32CFNetworkOpNetServiceGetPortNumber = 50,
    LC32CFNetworkOpNetServiceGetAddressing = 51,
    LC32CFNetworkOpNetServiceGetTXTData = 52,
    LC32CFNetworkOpNetServiceSetTXTData = 53,
    LC32CFNetworkOpNetServiceCreateDictionaryWithTXTData = 54,
    LC32CFNetworkOpNetServiceCreateTXTDataWithDictionary = 55,
    LC32CFNetworkOpCopyProxiesForAutoConfigurationScript = 56,
    LC32CFNetworkOpReadStreamCreateForStreamedHTTPRequest = 57,
} LC32CFNetworkOpcode;

#endif
