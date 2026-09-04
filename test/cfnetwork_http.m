#import <CFNetwork/CFNetwork.h>
#import <CoreFoundation/CoreFoundation.h>

#include <stdint.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int Check(Boolean condition, int code) {
    return condition ? 0 : code;
}

int main(void) {
    if(kCFStreamErrorDomainFTP != 6) return 12;
    if(kCFStreamErrorDomainHTTP != 4) return 13;
    if(kCFStreamErrorDomainMach != 11) return 14;
    if(kCFStreamErrorDomainNetDB != 12) return 15;
    if(kCFStreamErrorDomainNetServices != 10) return 16;
    if(kCFStreamErrorDomainSystemConfiguration != 13) return 17;
    if(kCFStreamErrorDomainWinSock != 7) return 18;

    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("https://example.invalid/resource"), NULL);
    CFHTTPMessageRef request = CFHTTPMessageCreateRequest(
        kCFAllocatorDefault, CFSTR("GET"), url, kCFHTTPVersion1_1);
    if(url) CFRelease(url);
    if(!request) return 1;

    int result = Check(CFHTTPMessageIsRequest(request), 2);
    if(!result) result = Check(CFGetTypeID(request) ==
        CFHTTPMessageGetTypeID(), 3);

    CFHTTPMessageSetHeaderFieldValue(request,
        CFSTR("X-LC32-Test"), CFSTR("present"));
    CFStringRef header = CFHTTPMessageCopyHeaderFieldValue(
        request, CFSTR("X-LC32-Test"));
    if(!result) result = Check(header &&
        CFEqual(header, CFSTR("present")), 4);
    if(header) CFRelease(header);

    CFHTTPMessageRef copy = CFHTTPMessageCreateCopy(
        kCFAllocatorDefault, request);
    if(!result) result = Check(copy && CFHTTPMessageIsRequest(copy), 5);
    if(copy) CFRelease(copy);

    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(
        kCFAllocatorDefault, 401, CFSTR("Unauthorized"),
        kCFHTTPVersion1_1);
    if(!result) result = Check(response != NULL, 6);
    if(response) {
        CFHTTPMessageSetHeaderFieldValue(response,
            CFSTR("WWW-Authenticate"), CFSTR("Basic realm=\"LC32\""));
        CFStringRef statusLine =
            CFHTTPMessageCopyResponseStatusLine(response);
        if(!result) result = Check(statusLine != NULL, 7);
        if(statusLine) CFRelease(statusLine);

        Boolean added = CFHTTPMessageAddAuthentication(request, response,
            CFSTR("lc32-user"), CFSTR("lc32-password"),
            kCFHTTPAuthenticationSchemeBasic, false);
        if(!result) result = Check(added, 21);
        CFStringRef authorization = CFHTTPMessageCopyHeaderFieldValue(
            request, CFSTR("Authorization"));
        if(!result) result = Check(authorization != NULL, 22);
        if(authorization) CFRelease(authorization);

        CFHTTPAuthenticationRef authentication =
            CFHTTPAuthenticationCreateFromResponse(
                kCFAllocatorDefault, response);
        if(!result) result = Check(authentication != NULL, 8);
        if(authentication) {
            if(!result) result = Check(CFGetTypeID(authentication) ==
                CFHTTPAuthenticationGetTypeID(), 9);
            CFStringRef method =
                CFHTTPAuthenticationCopyMethod(authentication);
            CFStringRef realm =
                CFHTTPAuthenticationCopyRealm(authentication);
            CFArrayRef domains =
                CFHTTPAuthenticationCopyDomains(authentication);
            if(!result) result = Check(method != NULL, 10);
            if(!result) result = Check(realm != NULL, 11);
            (void)CFHTTPAuthenticationRequiresOrderedRequests(
                authentication);
            (void)CFHTTPAuthenticationRequiresUserNameAndPassword(
                authentication);
            (void)CFHTTPAuthenticationRequiresAccountDomain(
                authentication);
            (void)CFHTTPAuthenticationAppliesToRequest(
                authentication, request);

            CFStreamError validityError = { 123, 456 };
            Boolean valid = CFHTTPAuthenticationIsValid(
                authentication, &validityError);
            if(!result && !valid) result = Check(
                validityError.domain == kCFStreamErrorDomainHTTP &&
                validityError.error != 456, 23);

            CFStreamError credentialsError = { 123, 456 };
            Boolean applied = CFHTTPMessageApplyCredentials(request,
                authentication, CFSTR("lc32-user"),
                CFSTR("lc32-password"), &credentialsError);
            if(!result && !applied) result = Check(
                credentialsError.domain == kCFStreamErrorDomainHTTP &&
                credentialsError.error != 456, 24);

            const void *credentialKeys[] = {
                kCFHTTPAuthenticationUsername,
                kCFHTTPAuthenticationPassword,
            };
            const void *credentialValues[] = {
                CFSTR("lc32-user"),
                CFSTR("lc32-password"),
            };
            CFDictionaryRef credentials = CFDictionaryCreate(
                kCFAllocatorDefault, credentialKeys, credentialValues, 2,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks);
            CFStreamError dictionaryError = { 123, 456 };
            Boolean dictionaryApplied =
                CFHTTPMessageApplyCredentialDictionary(request,
                    authentication, credentials, &dictionaryError);
            if(!result && !dictionaryApplied) result = Check(
                dictionaryError.domain == kCFStreamErrorDomainHTTP &&
                dictionaryError.error != 456, 25);
            CFRelease(credentials);

            if(method) CFRelease(method);
            if(realm) CFRelease(realm);
            if(domains) CFRelease(domains);
            CFRelease(authentication);
        }
        CFRelease(response);
    }

    CFRelease(request);

    CFHostRef host = CFHostCreateWithName(kCFAllocatorDefault,
        CFSTR("example.invalid"));
    if(!result) result = Check(host != NULL, 26);
    if(host) {
        if(!result) result = Check(CFGetTypeID(host) ==
            CFHostGetTypeID(), 27);
        Boolean resolved = false;
        CFArrayRef names = CFHostGetNames(host, &resolved);
        if(!result) result = Check(resolved && names &&
            CFArrayGetCount(names) == 1, 28);
        if(!result) result = Check(CFHostGetAddressing(host, NULL) == NULL,
            29);
        if(!result) result = Check(CFHostGetReachability(host, NULL) == NULL,
            30);
        CFHostRef hostCopy = CFHostCreateCopy(kCFAllocatorDefault, host);
        if(!result) result = Check(hostCopy != NULL, 31);
        if(hostCopy) CFRelease(hostCopy);
        CFRelease(host);
    }

    CFNetServiceRef service = CFNetServiceCreate(kCFAllocatorDefault,
        CFSTR("local."), CFSTR("_lc32._tcp."), CFSTR("LC32"), 1234);
    if(!result) result = Check(service != NULL, 32);
    if(service) {
        if(!result) result = Check(CFGetTypeID(service) ==
            CFNetServiceGetTypeID(), 33);
        if(!result) result = Check(CFEqual(CFNetServiceGetDomain(service),
            CFSTR("local.")), 34);
        if(!result) result = Check(CFEqual(CFNetServiceGetType(service),
            CFSTR("_lc32._tcp.")), 35);
        if(!result) result = Check(CFEqual(CFNetServiceGetName(service),
            CFSTR("LC32")), 36);
        if(!result) result = Check(CFNetServiceGetPortNumber(service) ==
            1234, 37);
        if(!result) result = Check(
            CFNetServiceGetTargetHost(service) == NULL &&
            CFNetServiceGetAddressing(service) == NULL &&
            CFNetServiceGetTXTData(service) == NULL, 38);

        const UInt8 txtBytes[] = { 1, 2, 3 };
        CFDataRef txtValue = CFDataCreate(kCFAllocatorDefault,
            txtBytes, sizeof(txtBytes));
        const void *txtKeys[] = { CFSTR("flag") };
        const void *txtValues[] = { txtValue };
        CFDictionaryRef txtDictionary = CFDictionaryCreate(
            kCFAllocatorDefault, txtKeys, txtValues, 1,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
        CFDataRef txtData = CFNetServiceCreateTXTDataWithDictionary(
            kCFAllocatorDefault, txtDictionary);
        if(!result) result = Check(txtData != NULL, 39);
        if(!result) result = Check(CFNetServiceSetTXTData(
            service, txtData), 40);
        if(!result) result = Check(CFEqual(
            CFNetServiceGetTXTData(service), txtData), 41);
        CFDictionaryRef parsed = txtData ?
            CFNetServiceCreateDictionaryWithTXTData(
                kCFAllocatorDefault, txtData) : NULL;
        if(!result) result = Check(parsed && CFEqual(
            CFDictionaryGetValue(parsed, CFSTR("flag")), txtValue), 42);

        CFNetServiceRef serviceCopy = CFNetServiceCreateCopy(
            kCFAllocatorDefault, service);
        if(!result) result = Check(serviceCopy &&
            CFNetServiceGetPortNumber(serviceCopy) == 1234, 43);
        if(serviceCopy) CFRelease(serviceCopy);
        if(parsed) CFRelease(parsed);
        if(txtData) CFRelease(txtData);
        CFRelease(txtDictionary);
        CFRelease(txtValue);
        CFRelease(service);
    }

    CFURLRef pacURL = CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("https://example.invalid/"), NULL);
    CFErrorRef pacError = (CFErrorRef)(uintptr_t)1;
    CFArrayRef proxies =
        CFNetworkCopyProxiesForAutoConfigurationScript(
            CFSTR("function FindProxyForURL(url, host) { return 'DIRECT'; }"),
            pacURL, &pacError);
    if(!result) result = Check(pacError != (CFErrorRef)(uintptr_t)1, 44);
    if(!result) result = Check((proxies != NULL) != (pacError != NULL), 45);
    if(proxies) CFRelease(proxies);
    if(pacError) CFRelease(pacError);

    CFHTTPMessageRef streamedRequest = CFHTTPMessageCreateRequest(
        kCFAllocatorDefault, CFSTR("POST"), pacURL, kCFHTTPVersion1_1);
    CFURLRef bodyURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
        CFSTR("/dev/null"), kCFURLPOSIXPathStyle, false);
    CFReadStreamRef bodyStream = CFReadStreamCreateWithFile(
        kCFAllocatorDefault, bodyURL);
    CFReadStreamRef streamedResponse =
        CFReadStreamCreateForStreamedHTTPRequest(kCFAllocatorDefault,
            streamedRequest, bodyStream);
    if(!result) result = Check(streamedResponse != NULL, 46);
    if(streamedResponse) CFRelease(streamedResponse);
    if(bodyStream) CFRelease(bodyStream);
    if(bodyURL) CFRelease(bodyURL);
    if(streamedRequest) CFRelease(streamedRequest);
    if(pacURL) CFRelease(pacURL);

    return result;
}
