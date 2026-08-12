#ifndef LC32_CFNETWORK_BRIDGE_H
#define LC32_CFNETWORK_BRIDGE_H

#include <stdint.h>

enum {
    LC32CFNetworkABIVersion = 1,
    LC32CFNetworkMaxSlots = 4,
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
} LC32CFNetworkOpcode;

#endif
