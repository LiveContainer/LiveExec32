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

const SInt32 kCFStreamErrorDomainFTP = 6;
const SInt32 kCFStreamErrorDomainHTTP = 4;
const SInt32 kCFStreamErrorDomainNetDB = 12;
const SInt32 kCFStreamErrorDomainSystemConfiguration = 13;
const SInt32 kCFStreamErrorDomainMach = 11;
const SInt32 kCFStreamErrorDomainNetServices = 10;
const CFIndex kCFStreamErrorDomainWinSock = 7;
const CFStringRef kCFErrorDomainCFNetwork =
    CFSTR("kCFErrorDomainCFNetwork");

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

CFStringRef CFHTTPMessageCopyResponseStatusLine(
        CFHTTPMessageRef response) {
    return response ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCopyResponseStatusLine,
        LC32_CFNETWORK_HOST(response)) : NULL;
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

CFHTTPMessageRef CFHTTPMessageCreateCopy(CFAllocatorRef allocator,
                                         CFHTTPMessageRef message) {
    (void)allocator;
    return message ? (CFHTTPMessageRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageCreateCopy,
        LC32_CFNETWORK_HOST(message)) : NULL;
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

CFTypeID CFHTTPMessageGetTypeID(void) {
    return (CFTypeID)LC32_CFNETWORK_CALL0(
        LC32CFNetworkOpHTTPMessageGetTypeID);
}

Boolean CFHTTPMessageIsHeaderComplete(CFHTTPMessageRef message) {
    return message && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageIsHeaderComplete,
        LC32_CFNETWORK_HOST(message)) != 0;
}

Boolean CFHTTPMessageIsRequest(CFHTTPMessageRef message) {
    return message && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageIsRequest,
        LC32_CFNETWORK_HOST(message)) != 0;
}

CFTypeID CFHTTPAuthenticationGetTypeID(void) {
    return (CFTypeID)LC32_CFNETWORK_CALL0(
        LC32CFNetworkOpHTTPAuthenticationGetTypeID);
}

CFHTTPAuthenticationRef CFHTTPAuthenticationCreateFromResponse(
        CFAllocatorRef allocator, CFHTTPMessageRef response) {
    (void)allocator;
    return response ? (CFHTTPAuthenticationRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationCreateFromResponse,
        LC32_CFNETWORK_HOST(response)) : NULL;
}

Boolean CFHTTPAuthenticationAppliesToRequest(
        CFHTTPAuthenticationRef authentication,
        CFHTTPMessageRef request) {
    return authentication && request && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationAppliesToRequest,
        LC32_CFNETWORK_HOST(authentication),
        LC32_CFNETWORK_HOST(request)) != 0;
}

Boolean CFHTTPAuthenticationRequiresOrderedRequests(
        CFHTTPAuthenticationRef authentication) {
    return authentication && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationRequiresOrderedRequests,
        LC32_CFNETWORK_HOST(authentication)) != 0;
}

CFStringRef CFHTTPAuthenticationCopyRealm(
        CFHTTPAuthenticationRef authentication) {
    return authentication ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationCopyRealm,
        LC32_CFNETWORK_HOST(authentication)) : NULL;
}

CFArrayRef CFHTTPAuthenticationCopyDomains(
        CFHTTPAuthenticationRef authentication) {
    return authentication ? (CFArrayRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationCopyDomains,
        LC32_CFNETWORK_HOST(authentication)) : NULL;
}

CFStringRef CFHTTPAuthenticationCopyMethod(
        CFHTTPAuthenticationRef authentication) {
    return authentication ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationCopyMethod,
        LC32_CFNETWORK_HOST(authentication)) : NULL;
}

Boolean CFHTTPAuthenticationRequiresUserNameAndPassword(
        CFHTTPAuthenticationRef authentication) {
    return authentication && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationRequiresUserNameAndPassword,
        LC32_CFNETWORK_HOST(authentication)) != 0;
}

Boolean CFHTTPAuthenticationRequiresAccountDomain(
        CFHTTPAuthenticationRef authentication) {
    return authentication && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationRequiresAccountDomain,
        LC32_CFNETWORK_HOST(authentication)) != 0;
}

Boolean CFHTTPAuthenticationIsValid(
        CFHTTPAuthenticationRef authentication, CFStreamError *error) {
    return authentication && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPAuthenticationIsValid,
        LC32_CFNETWORK_HOST(authentication),
        LC32_CFNETWORK_U32((uintptr_t)error)) != 0;
}

Boolean CFHTTPMessageAddAuthentication(
        CFHTTPMessageRef request,
        CFHTTPMessageRef authenticationFailureResponse,
        CFStringRef username, CFStringRef password,
        CFStringRef authenticationScheme, Boolean forProxy) {
    if(!request || !username || !password) return false;
    return LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageAddAuthentication,
        LC32_CFNETWORK_HOST(request),
        LC32_CFNETWORK_HOST(authenticationFailureResponse),
        LC32_CFNETWORK_HOST(username),
        LC32_CFNETWORK_HOST(password),
        LC32_CFNETWORK_HOST(authenticationScheme),
        LC32_CFNETWORK_U32(forProxy)) != 0;
}

Boolean CFHTTPMessageApplyCredentials(
        CFHTTPMessageRef request, CFHTTPAuthenticationRef authentication,
        CFStringRef username, CFStringRef password,
        CFStreamError *error) {
    if(!request || !authentication) return false;
    return LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageApplyCredentials,
        LC32_CFNETWORK_HOST(request),
        LC32_CFNETWORK_HOST(authentication),
        LC32_CFNETWORK_HOST(username),
        LC32_CFNETWORK_HOST(password),
        LC32_CFNETWORK_U32((uintptr_t)error)) != 0;
}

Boolean CFHTTPMessageApplyCredentialDictionary(
        CFHTTPMessageRef request, CFHTTPAuthenticationRef authentication,
        CFDictionaryRef credentialDictionary, CFStreamError *error) {
    if(!request || !authentication || !credentialDictionary) return false;
    return LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHTTPMessageApplyCredentialDictionary,
        LC32_CFNETWORK_HOST(request),
        LC32_CFNETWORK_HOST(authentication),
        LC32_CFNETWORK_HOST(credentialDictionary),
        LC32_CFNETWORK_U32((uintptr_t)error)) != 0;
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

CFArrayRef CFNetworkCopyProxiesForAutoConfigurationScript(
        CFStringRef proxyAutoConfigurationScript, CFURLRef targetURL,
        CFErrorRef *error) {
    if(!proxyAutoConfigurationScript || !targetURL) {
        if(error) *error = NULL;
        return NULL;
    }
    return (CFArrayRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpCopyProxiesForAutoConfigurationScript,
        LC32_CFNETWORK_HOST(proxyAutoConfigurationScript),
        LC32_CFNETWORK_HOST(targetURL),
        LC32_CFNETWORK_U32((uintptr_t)error));
}

CFReadStreamRef CFReadStreamCreateForHTTPRequest(
        CFAllocatorRef allocator, CFHTTPMessageRef request) {
    (void)allocator;
    return request ? (CFReadStreamRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpReadStreamCreateForHTTPRequest,
        LC32_CFNETWORK_HOST(request)) : NULL;
}

CFReadStreamRef CFReadStreamCreateForStreamedHTTPRequest(
        CFAllocatorRef allocator, CFHTTPMessageRef requestHeaders,
        CFReadStreamRef requestBody) {
    (void)allocator;
    return requestHeaders && requestBody ?
        (CFReadStreamRef)LC32_CFNETWORK_CALL(
            LC32CFNetworkOpReadStreamCreateForStreamedHTTPRequest,
            LC32_CFNETWORK_HOST(requestHeaders),
            LC32_CFNETWORK_HOST(requestBody)) : NULL;
}

CFTypeID CFHostGetTypeID(void) {
    return (CFTypeID)LC32_CFNETWORK_CALL0(LC32CFNetworkOpHostGetTypeID);
}

CFHostRef CFHostCreateWithName(CFAllocatorRef allocator,
                               CFStringRef hostname) {
    (void)allocator;
    return hostname ? (CFHostRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHostCreateWithName,
        LC32_CFNETWORK_HOST(hostname)) : NULL;
}

CFHostRef CFHostCreateWithAddress(CFAllocatorRef allocator,
                                  CFDataRef address) {
    (void)allocator;
    return address ? (CFHostRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHostCreateWithAddress,
        LC32_CFNETWORK_HOST(address)) : NULL;
}

CFHostRef CFHostCreateCopy(CFAllocatorRef allocator, CFHostRef host) {
    (void)allocator;
    return host ? (CFHostRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHostCreateCopy,
        LC32_CFNETWORK_HOST(host)) : NULL;
}

CFArrayRef CFHostGetAddressing(CFHostRef host,
                                Boolean *hasBeenResolved) {
    return host ? (CFArrayRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHostGetAddressing,
        LC32_CFNETWORK_HOST(host),
        LC32_CFNETWORK_U32((uintptr_t)hasBeenResolved)) : NULL;
}

CFArrayRef CFHostGetNames(CFHostRef host, Boolean *hasBeenResolved) {
    return host ? (CFArrayRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHostGetNames,
        LC32_CFNETWORK_HOST(host),
        LC32_CFNETWORK_U32((uintptr_t)hasBeenResolved)) : NULL;
}

CFDataRef CFHostGetReachability(CFHostRef host,
                                Boolean *hasBeenResolved) {
    return host ? (CFDataRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpHostGetReachability,
        LC32_CFNETWORK_HOST(host),
        LC32_CFNETWORK_U32((uintptr_t)hasBeenResolved)) : NULL;
}

CFTypeID CFNetServiceGetTypeID(void) {
    return (CFTypeID)LC32_CFNETWORK_CALL0(
        LC32CFNetworkOpNetServiceGetTypeID);
}

CFNetServiceRef CFNetServiceCreate(CFAllocatorRef allocator,
                                   CFStringRef domain,
                                   CFStringRef serviceType,
                                   CFStringRef name, SInt32 port) {
    (void)allocator;
    if(!domain || !serviceType || !name) return NULL;
    return (CFNetServiceRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceCreate,
        LC32_CFNETWORK_HOST(domain),
        LC32_CFNETWORK_HOST(serviceType),
        LC32_CFNETWORK_HOST(name),
        LC32_CFNETWORK_U32(port));
}

CFNetServiceRef CFNetServiceCreateCopy(CFAllocatorRef allocator,
                                       CFNetServiceRef service) {
    (void)allocator;
    return service ? (CFNetServiceRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceCreateCopy,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

CFStringRef CFNetServiceGetDomain(CFNetServiceRef service) {
    return service ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetDomain,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

CFStringRef CFNetServiceGetType(CFNetServiceRef service) {
    return service ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetType,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

CFStringRef CFNetServiceGetName(CFNetServiceRef service) {
    return service ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetName,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

CFStringRef CFNetServiceGetTargetHost(CFNetServiceRef service) {
    return service ? (CFStringRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetTargetHost,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

SInt32 CFNetServiceGetPortNumber(CFNetServiceRef service) {
    return service ? (SInt32)(int32_t)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetPortNumber,
        LC32_CFNETWORK_HOST(service)) : -1;
}

CFArrayRef CFNetServiceGetAddressing(CFNetServiceRef service) {
    return service ? (CFArrayRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetAddressing,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

CFDataRef CFNetServiceGetTXTData(CFNetServiceRef service) {
    return service ? (CFDataRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceGetTXTData,
        LC32_CFNETWORK_HOST(service)) : NULL;
}

Boolean CFNetServiceSetTXTData(CFNetServiceRef service,
                               CFDataRef txtRecord) {
    return service && txtRecord && LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceSetTXTData,
        LC32_CFNETWORK_HOST(service),
        LC32_CFNETWORK_HOST(txtRecord)) != 0;
}

CFDictionaryRef CFNetServiceCreateDictionaryWithTXTData(
        CFAllocatorRef allocator, CFDataRef txtRecord) {
    (void)allocator;
    return txtRecord ? (CFDictionaryRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceCreateDictionaryWithTXTData,
        LC32_CFNETWORK_HOST(txtRecord)) : NULL;
}

CFDataRef CFNetServiceCreateTXTDataWithDictionary(
        CFAllocatorRef allocator, CFDictionaryRef keyValuePairs) {
    (void)allocator;
    return keyValuePairs ? (CFDataRef)LC32_CFNETWORK_CALL(
        LC32CFNetworkOpNetServiceCreateTXTDataWithDictionary,
        LC32_CFNETWORK_HOST(keyValuePairs)) : NULL;
}
