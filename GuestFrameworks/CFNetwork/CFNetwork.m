#import <CFNetwork/CFNetwork.h>
#import <LC32/LC32.h>

#import "LC32CFNetworkBridge.h"

uint32_t LC32CFNetworkDispatch(LC32CFNetworkOpcode opcode,
                               const uint64_t *slots,
                               uint32_t slotCount);

static inline uint64_t LC32CFNetworkHostObject(const void *object) {
    return object ? [(id)object host_self] : 0;
}

#define LC32_CFNETWORK_CALL0(opcode) \
    LC32CFNetworkDispatch((opcode), NULL, 0)
#define LC32_CFNETWORK_CALL(opcode, ...) \
    LC32CFNetworkDispatch((opcode), \
        (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / \
                   sizeof(uint64_t)))
#define LC32_CFNETWORK_U32(value) ((uint64_t)(uint32_t)(value))
#define LC32_CFNETWORK_HOST(value) \
    LC32CFNetworkHostObject((const void *)(value))

/*
 * CFNetwork exports these as real pointer globals, rather than preprocessor
 * aliases.  Keep them guest-native so callers receive ARM32 CFString objects
 * and can use the values directly with the CoreFoundation compatibility
 * layer.  The spellings below are the literal values in the iOS 10.3.3
 * armv7s CFNetwork image.
 */

const CFStringRef kCFHTTPVersion1_0 = CFSTR("HTTP/1.0");
const CFStringRef kCFHTTPVersion1_1 = CFSTR("HTTP/1.1");

const SInt32 kCFStreamErrorDomainHTTP = 4;

const CFStringRef kCFProxyHostNameKey =
    CFSTR("kCFProxyHostNameKey");
const CFStringRef kCFProxyPortNumberKey =
    CFSTR("kCFProxyPortNumberKey");

const CFStringRef kCFStreamNetworkServiceType =
    CFSTR("kCFStreamNetworkServiceType");
const CFStringRef kCFStreamNetworkServiceTypeVoIP =
    CFSTR("kCFStreamNetworkServiceTypeVoIP");

const CFStringRef kCFStreamPropertyHTTPProxy =
    CFSTR("kCFStreamPropertyHTTPProxy");
const CFStringRef kCFStreamPropertyHTTPResponseHeader =
    CFSTR("kCFStreamPropertyHTTPResponseHeader");
const CFStringRef kCFStreamPropertyHTTPShouldAutoredirect =
    CFSTR("kCFStreamPropertyHTTPShouldAutoredirect");

const CFStringRef kCFStreamPropertySSLSettings =
    CFSTR("kCFStreamPropertySSLSettings");
const CFStringRef kCFStreamSSLAllowsAnyRoot =
    CFSTR("kCFStreamSSLAllowsAnyRoot");
const CFStringRef kCFStreamSSLAllowsExpiredCertificates =
    CFSTR("kCFStreamSSLAllowsExpiredCertificates");
const CFStringRef kCFStreamSSLAllowsExpiredRoots =
    CFSTR("kCFStreamSSLAllowsExpiredRoots");
const CFStringRef kCFStreamSSLCertificates =
    CFSTR("kCFStreamSSLCertificates");
const CFStringRef kCFStreamSSLIsServer =
    CFSTR("kCFStreamSSLIsServer");
const CFStringRef kCFStreamSSLLevel =
    CFSTR("kCFStreamSSLLevel");
const CFStringRef kCFStreamSSLPeerName =
    CFSTR("kCFStreamSSLPeerName");
const CFStringRef kCFStreamSSLValidatesCertificateChain =
    CFSTR("kCFStreamSSLValidatesCertificateChain");

Boolean CFHTTPMessageAppendBytes(CFHTTPMessageRef message,
                                 const UInt8 *newBytes,
                                 CFIndex numBytes) {
    if(!message || numBytes < 0 || (numBytes && !newBytes)) return false;
    return LC32_CFNETWORK_CALL(LC32CFNetworkOpHTTPMessageAppendBytes,
        LC32_CFNETWORK_HOST(message),
        LC32_CFNETWORK_U32((uintptr_t)newBytes),
        LC32_CFNETWORK_U32(numBytes)) != 0;
}

CFDictionaryRef CFHTTPMessageCopyAllHeaderFields(
        CFHTTPMessageRef message) {
    return message ? (CFDictionaryRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyAllHeaderFields,
        LC32_CFNETWORK_HOST(message)) : NULL;
}

CFDataRef CFHTTPMessageCopyBody(CFHTTPMessageRef message) {
    return message ? (CFDataRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyBody,
        LC32_CFNETWORK_HOST(message)) : NULL;
}

CFStringRef CFHTTPMessageCopyHeaderFieldValue(
        CFHTTPMessageRef message, CFStringRef headerField) {
    return message && headerField ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyHeaderFieldValue,
        LC32_CFNETWORK_HOST(message),
        LC32_CFNETWORK_HOST(headerField)) : NULL;
}

CFStringRef CFHTTPMessageCopyRequestMethod(CFHTTPMessageRef request) {
    return request ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyRequestMethod,
        LC32_CFNETWORK_HOST(request)) : NULL;
}

CFURLRef CFHTTPMessageCopyRequestURL(CFHTTPMessageRef request) {
    return request ? (CFURLRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyRequestURL,
        LC32_CFNETWORK_HOST(request)) : NULL;
}

CFDataRef CFHTTPMessageCopySerializedMessage(CFHTTPMessageRef message) {
    return message ? (CFDataRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopySerializedMessage,
        LC32_CFNETWORK_HOST(message)) : NULL;
}

CFStringRef CFHTTPMessageCopyVersion(CFHTTPMessageRef message) {
    return message ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyVersion,
        LC32_CFNETWORK_HOST(message)) : NULL;
}

CFHTTPMessageRef CFHTTPMessageCreateEmpty(CFAllocatorRef allocator,
                                           Boolean isRequest) {
    (void)allocator;
    return (CFHTTPMessageRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCreateEmpty,
        LC32_CFNETWORK_U32(isRequest));
}

CFHTTPMessageRef CFHTTPMessageCreateRequest(
        CFAllocatorRef allocator, CFStringRef requestMethod,
        CFURLRef url, CFStringRef httpVersion) {
    (void)allocator;
    if(!requestMethod || !url || !httpVersion) return NULL;
    return (CFHTTPMessageRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCreateRequest,
        LC32_CFNETWORK_HOST(requestMethod),
        LC32_CFNETWORK_HOST(url),
        LC32_CFNETWORK_HOST(httpVersion));
}

CFHTTPMessageRef CFHTTPMessageCreateResponse(
        CFAllocatorRef allocator, CFIndex statusCode,
        CFStringRef statusDescription, CFStringRef httpVersion) {
    (void)allocator;
    if(!httpVersion) return NULL;
    return (CFHTTPMessageRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCreateResponse,
        LC32_CFNETWORK_U32(statusCode),
        LC32_CFNETWORK_HOST(statusDescription),
        LC32_CFNETWORK_HOST(httpVersion));
}

CFIndex CFHTTPMessageGetResponseStatusCode(CFHTTPMessageRef response) {
    return response ? (CFIndex)(int32_t)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageGetResponseStatusCode,
        LC32_CFNETWORK_HOST(response)) : 0;
}

Boolean CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef message) {
    return message && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageIsHeaderComplete,
        LC32_CFNETWORK_HOST(message)) != 0;
}

void CFHTTPMessageSetBody(CFHTTPMessageRef message, CFDataRef bodyData) {
    if(!message || !bodyData) return;
    LC32_CFNETWORK_CALL(LC32CFNetworkOpHTTPMessageSetBody,
        LC32_CFNETWORK_HOST(message), LC32_CFNETWORK_HOST(bodyData));
}

void CFHTTPMessageSetHeaderFieldValue(
        CFHTTPMessageRef message, CFStringRef headerField,
        CFStringRef value) {
    if(!message || !headerField) return;
    LC32_CFNETWORK_CALL(LC32CFNetworkOpHTTPMessageSetHeaderFieldValue,
        LC32_CFNETWORK_HOST(message), LC32_CFNETWORK_HOST(headerField),
        LC32_CFNETWORK_HOST(value));
}

CFDictionaryRef CFNetworkCopySystemProxySettings(void) {
    return (CFDictionaryRef)LC32_CFNETWORK_CALL0(
        LC32CFNetworkOpCopySystemProxySettings);
}

CFArrayRef CFNetworkCopyProxiesForURL(CFURLRef url,
                                      CFDictionaryRef proxySettings) {
    if(!url || !proxySettings) return NULL;
    return (CFArrayRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpCopyProxiesForURL,
        LC32_CFNETWORK_HOST(url),
        LC32_CFNETWORK_HOST(proxySettings));
}

CFReadStreamRef CFReadStreamCreateForHTTPRequest(
        CFAllocatorRef allocator, CFHTTPMessageRef request) {
    (void)allocator;
    return request ? (CFReadStreamRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpReadStreamCreateForHTTPRequest,
        LC32_CFNETWORK_HOST(request)) : NULL;
}
