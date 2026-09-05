// Guest-native public CFNetwork string constants. Values are taken
// from Apple's iOS 10.3 CFNetwork image to preserve its legacy ABI.

#import <CFNetwork/CFNetwork.h>
#import <Foundation/Foundation+LC32.h>

#include <stdint.h>

/* Exporting the legacy ABI necessarily references deprecated declarations. */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define LC32_CFNETWORK_OBJECT_CONSTANTS(X) \
    X(NSHTTPCookieOriginURL) \
    X(NSHTTPCookieVersion) \
    X(NSHTTPCookieComment) \
    X(NSHTTPCookieCommentURL) \
    X(NSHTTPCookieDiscard) \
    X(NSHTTPCookieMaximumAge) \
    X(NSHTTPCookiePort) \
    X(NSHTTPCookieManagerAcceptPolicyChangedNotification) \
    X(NSHTTPCookieManagerCookiesChangedNotification) \
    X(NSURLProtectionSpaceHTTP) \
    X(NSURLProtectionSpaceHTTPS) \
    X(NSURLProtectionSpaceFTP) \
    X(NSURLProtectionSpaceHTTPProxy) \
    X(NSURLProtectionSpaceHTTPSProxy) \
    X(NSURLProtectionSpaceFTPProxy) \
    X(NSURLProtectionSpaceSOCKSProxy) \
    X(NSURLAuthenticationMethodDefault) \
    X(NSURLAuthenticationMethodHTTPBasic) \
    X(NSURLAuthenticationMethodHTTPDigest) \
    X(NSURLAuthenticationMethodHTMLForm) \
    X(NSURLAuthenticationMethodNTLM) \
    X(NSURLAuthenticationMethodNegotiate) \
    X(NSURLAuthenticationMethodClientCertificate) \
    X(NSURLCredentialStorageChangedNotification) \
    X(NSURLCredentialStorageRemoveSynchronizableCredentials) \
    X(NSNetServicesErrorCode) \
    X(NSNetServicesErrorDomain) \
    X(NSURLSessionDownloadTaskResumeData)

#define LC32_DECLARE_CFNETWORK_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_CFNETWORK_OBJECT_CONSTANTS(LC32_DECLARE_CFNETWORK_OBJECT_CONSTANT)
#undef LC32_DECLARE_CFNETWORK_OBJECT_CONSTANT

const NSHTTPCookiePropertyKey NSHTTPCookieName = @"Name";
const NSHTTPCookiePropertyKey NSHTTPCookieValue = @"Value";
const NSHTTPCookiePropertyKey NSHTTPCookieDomain = @"Domain";
const NSHTTPCookiePropertyKey NSHTTPCookiePath = @"Path";
const NSHTTPCookiePropertyKey NSHTTPCookieSecure = @"Secure";
const NSHTTPCookiePropertyKey NSHTTPCookieExpires = @"Expires";
NSString * const NSURLAuthenticationMethodServerTrust =
    @"NSURLAuthenticationMethodServerTrust";

const int64_t NSURLSessionTransferSizeUnknown = -1LL;
const float NSURLSessionTaskPriorityDefault = 0.5f;
const float NSURLSessionTaskPriorityLow = 0.0f;
const float NSURLSessionTaskPriorityHigh = 1.0f;

__attribute__((constructor))
static void LC32InitializeCFNetworkObjectConstants(void) {
#define LC32_INITIALIZE_CFNETWORK_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_INIT(name);
    LC32_CFNETWORK_OBJECT_CONSTANTS(
        LC32_INITIALIZE_CFNETWORK_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_CFNETWORK_OBJECT_CONSTANT
}

#define LC32_CFNETWORK_STRING(name, value) \
    const CFStringRef name = CFSTR(value)

LC32_CFNETWORK_STRING(kCFDNSServiceFailureKey, "kCFDNSServiceFailureKey");
LC32_CFNETWORK_STRING(kCFErrorDomainWinSock, "kCFErrorDomainWinSock");
LC32_CFNETWORK_STRING(kCFFTPResourceGroup, "kCFFTPResourceGroup");
LC32_CFNETWORK_STRING(kCFFTPResourceLink, "kCFFTPResourceLink");
LC32_CFNETWORK_STRING(kCFFTPResourceModDate, "kCFFTPResourceModDate");
LC32_CFNETWORK_STRING(kCFFTPResourceMode, "kCFFTPResourceMode");
LC32_CFNETWORK_STRING(kCFFTPResourceName, "kCFFTPResourceName");
LC32_CFNETWORK_STRING(kCFFTPResourceOwner, "kCFFTPResourceOwner");
LC32_CFNETWORK_STRING(kCFFTPResourceSize, "kCFFTPResourceSize");
LC32_CFNETWORK_STRING(kCFFTPResourceType, "kCFFTPResourceType");
LC32_CFNETWORK_STRING(kCFFTPStatusCodeKey, "kCFFTPStatusCodeKey");
LC32_CFNETWORK_STRING(kCFGetAddrInfoFailureKey, "kCFGetAddrInfoFailureKey");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationAccountDomain, "kCFHTTPAuthenticationAccountDomain");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationPassword, "kCFHTTPAuthenticationPassword");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationSchemeBasic, "Basic");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationSchemeDigest, "Digest");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationSchemeNTLM, "NTLM");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationSchemeNegotiate, "Negotiate");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationSchemeNegotiate2, "Nego2");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationSchemeXMobileMeAuthToken, "X-MobileMe-AuthToken");
LC32_CFNETWORK_STRING(kCFHTTPAuthenticationUsername, "kCFHTTPAuthenticationUsername");
LC32_CFNETWORK_STRING(kCFHTTPVersion2_0, "HTTP/2.0");
LC32_CFNETWORK_STRING(kCFNetworkProxiesHTTPEnable, "HTTPEnable");
LC32_CFNETWORK_STRING(kCFNetworkProxiesHTTPPort, "HTTPPort");
LC32_CFNETWORK_STRING(kCFNetworkProxiesHTTPProxy, "HTTPProxy");
LC32_CFNETWORK_STRING(kCFNetworkProxiesProxyAutoConfigEnable, "ProxyAutoConfigEnable");
LC32_CFNETWORK_STRING(kCFNetworkProxiesProxyAutoConfigURLString, "ProxyAutoConfigURLString");
LC32_CFNETWORK_STRING(kCFProxyAutoConfigurationJavaScriptKey, "kCFProxyAutoConfigurationJavaScriptKey");
LC32_CFNETWORK_STRING(kCFProxyAutoConfigurationURLKey, "kCFProxyAutoConfigurationURLKey");
LC32_CFNETWORK_STRING(kCFProxyPasswordKey, "kCFProxyPasswordKey");
LC32_CFNETWORK_STRING(kCFProxyTypeAutoConfigurationJavaScript, "kCFProxyTypeAutoConfigurationJavaScript");
LC32_CFNETWORK_STRING(kCFProxyTypeAutoConfigurationURL, "kCFProxyTypeAutoConfigurationURL");
LC32_CFNETWORK_STRING(kCFProxyTypeFTP, "kCFProxyTypeFTP");
LC32_CFNETWORK_STRING(kCFProxyTypeHTTP, "kCFProxyTypeHTTP");
LC32_CFNETWORK_STRING(kCFProxyTypeHTTPS, "kCFProxyTypeHTTPS");
LC32_CFNETWORK_STRING(kCFProxyTypeKey, "kCFProxyTypeKey");
LC32_CFNETWORK_STRING(kCFProxyTypeNone, "kCFProxyTypeNone");
LC32_CFNETWORK_STRING(kCFProxyTypeSOCKS, "kCFProxyTypeSOCKS");
LC32_CFNETWORK_STRING(kCFProxyUsernameKey, "kCFProxyUsernameKey");
LC32_CFNETWORK_STRING(kCFSOCKSNegotiationMethodKey, "kCFSOCKSNegotiationMethodKey");
LC32_CFNETWORK_STRING(kCFSOCKSStatusCodeKey, "kCFSOCKSStatusCodeKey");
LC32_CFNETWORK_STRING(kCFSOCKSVersionKey, "kCFSOCKSVersionKey");
LC32_CFNETWORK_STRING(kCFStreamNetworkServiceTypeBackground, "kCFStreamNetworkServiceTypeBackground");
LC32_CFNETWORK_STRING(kCFStreamNetworkServiceTypeCallSignaling, "kCFStreamNetworkServiceTypeCallSignaling");
LC32_CFNETWORK_STRING(kCFStreamNetworkServiceTypeVideo, "kCFStreamNetworkServiceTypeVideo");
LC32_CFNETWORK_STRING(kCFStreamNetworkServiceTypeVoice, "kCFStreamNetworkServiceTypeVoice");
LC32_CFNETWORK_STRING(kCFStreamPropertyConnectionIsCellular, "kCFStreamPropertyConnectionIsCellular");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPAttemptPersistentConnection, "kCFStreamPropertyFTPAttemptPersistentConnection");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPFetchResourceInfo, "kCFStreamPropertyFTPFetchResourceInfo");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPFileTransferOffset, "kCFStreamPropertyFTPFileTransferOffset");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPPassword, "kCFStreamPropertyFTPPassword");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPProxy, "kCFStreamPropertyFTPProxy");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPProxyHost, "FTPProxy");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPProxyPassword, "kCFStreamPropertyFTPProxyPassword");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPProxyPort, "FTPPort");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPProxyUser, "kCFStreamPropertyFTPProxyUser");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPResourceSize, "kCFStreamPropertyFTPResourceSize");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPUsePassiveMode, "kCFStreamPropertyFTPUsePassiveMode");
LC32_CFNETWORK_STRING(kCFStreamPropertyFTPUserName, "kCFStreamPropertyFTPUserName");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPAttemptPersistentConnection, "kCFStreamPropertyHTTPAttemptPersistentConnection");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPFinalRequest, "kCFStreamPropertyHTTPFinalRequest");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPFinalURL, "kCFStreamPropertyHTTPFinalURL");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPProxyHost, "HTTPProxy");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPProxyPort, "HTTPPort");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPRequestBytesWrittenCount, "kCFStreamPropertyHTTPRequestBytesWrittenCount");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPSProxyHost, "HTTPSProxy");
LC32_CFNETWORK_STRING(kCFStreamPropertyHTTPSProxyPort, "HTTPSPort");
LC32_CFNETWORK_STRING(kCFStreamPropertyNoCellular, "kCFStreamPropertyNoCellular");
LC32_CFNETWORK_STRING(kCFStreamPropertyProxyLocalBypass, "ExcludeSimpleHostnames");
LC32_CFNETWORK_STRING(kCFStreamPropertySSLContext, "kCFStreamPropertySSLContext");
LC32_CFNETWORK_STRING(kCFStreamPropertySSLPeerCertificates, "kCFStreamPropertySSLPeerCertificates");
LC32_CFNETWORK_STRING(kCFStreamPropertySSLPeerTrust, "kCFStreamPropertySSLPeerTrust");
LC32_CFNETWORK_STRING(kCFStreamPropertySocketExtendedBackgroundIdleMode, "kCFStreamPropertySocketExtendedBackgroundIdleMode");
LC32_CFNETWORK_STRING(kCFStreamPropertySocketRemoteHost, "kCFStreamPropertySocketRemoteHost");
LC32_CFNETWORK_STRING(kCFStreamPropertySocketRemoteNetService, "kCFStreamPropertySocketRemoteNetService");
LC32_CFNETWORK_STRING(kCFURLErrorFailingURLErrorKey, "NSErrorFailingURLKey");
LC32_CFNETWORK_STRING(kCFURLErrorFailingURLStringErrorKey, "NSErrorFailingURLStringKey");

#undef LC32_CFNETWORK_STRING
#undef LC32_CFNETWORK_OBJECT_CONSTANTS
