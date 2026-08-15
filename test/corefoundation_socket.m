#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int failures;
static const char expectedPayload[] = "lc32-cfsocket-payload";

typedef struct {
    int retains;
    int releases;
    int callbacks;
    Boolean sawSocketIdentity;
    Boolean sawContextIdentity;
    Boolean sawAddress;
    Boolean sawPayload;
} SocketInfo;

static SocketInfo originalInfo;
static SocketInfo retainedInfo;
static CFSocketRef expectedSocket;

static void check(const char *name, Boolean condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static void skip(const char *name, const char *reason) {
    printf("%s: SKIP (%s)\n", name, reason);
}

static const void *retainSocketInfo(const void *rawInfo) {
    ((SocketInfo *)rawInfo)->retains++;
    return &retainedInfo;
}

static void releaseSocketInfo(const void *rawInfo) {
    if(rawInfo == &retainedInfo) {
        retainedInfo.releases++;
    } else {
        failures++;
    }
}

static CFStringRef copySocketInfoDescription(const void *rawInfo) {
    (void)rawInfo;
    return CFStringCreateCopy(kCFAllocatorDefault,
                              CFSTR("socket-context"));
}

static void socketCallback(CFSocketRef socket,
                           CFSocketCallBackType type,
                           CFDataRef address,
                           const void *data,
                           void *rawInfo) {
    SocketInfo *info = (SocketInfo *)rawInfo;
    info->callbacks++;
    info->sawSocketIdentity |= socket == expectedSocket;
    info->sawContextIdentity |= rawInfo == &retainedInfo;

    if(type == kCFSocketDataCallBack) {
        CFDataRef payload = (CFDataRef)data;
        info->sawAddress |= address && CFDataGetLength(address) >=
            (CFIndex)sizeof(struct sockaddr_in);
        info->sawPayload |= payload &&
            CFDataGetLength(payload) ==
                (CFIndex)(sizeof(expectedPayload) - 1) &&
            memcmp(CFDataGetBytePtr(payload), expectedPayload,
                   sizeof(expectedPayload) - 1) == 0;
    }

    /* This intentionally releases the native context while the callback is
     * active; the host bridge must keep its wrapper alive through return. */
    CFSocketInvalidate(socket);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    CFSocketContext context = {
        0,
        &originalInfo,
        retainSocketInfo,
        releaseSocketInfo,
        copySocketInfoDescription,
    };
    CFSocketRef receiver = CFSocketCreate(
        kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP,
        kCFSocketDataCallBack, socketCallback, &context);
    expectedSocket = receiver;
    check("socket-create", receiver != NULL);
    check("context-retained-once",
        originalInfo.retains == 1 && retainedInfo.releases == 0);

    CFSocketNativeHandle receiverFD = receiver
        ? CFSocketGetNative(receiver) : -1;
    check("get-native", receiverFD >= 0);

    struct sockaddr_in receiverAddress = {};
    receiverAddress.sin_len = sizeof(receiverAddress);
    receiverAddress.sin_family = AF_INET;
    receiverAddress.sin_port = 0;
    receiverAddress.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int bindResult = receiverFD >= 0
        ? bind(receiverFD, (const struct sockaddr *)&receiverAddress,
               sizeof(receiverAddress)) : -1;
    const int bindError = bindResult == 0 ? 0 : errno;
    socklen_t receiverAddressLength = sizeof(receiverAddress);
    int nameResult = bindResult == 0
        ? getsockname(receiverFD, (struct sockaddr *)&receiverAddress,
                      &receiverAddressLength) : -1;
    const Boolean networkBlocked = bindResult != 0 && bindError == EPERM;
    const Boolean networkReady = bindResult == 0 && nameResult == 0 &&
        receiverAddress.sin_port != 0;
    if(networkBlocked) {
        skip("bind-loopback", "execution sandbox denied bind");
    } else {
        check("bind-loopback", networkReady);
    }
    if(bindResult != 0) {
        printf("bind-loopback detail: fd=%d errno=%d\n",
            receiverFD, bindError);
    }

    CFDataRef addressData = networkReady
        ? CFDataCreate(kCFAllocatorDefault,
              (const UInt8 *)&receiverAddress,
              (CFIndex)receiverAddressLength) : NULL;
    CFSocketRef connector = CFSocketCreate(
        kCFAllocatorDefault, PF_INET, SOCK_DGRAM, IPPROTO_UDP,
        kCFSocketNoCallBack, NULL, NULL);
    CFSocketError connectResult = connector && addressData
        ? CFSocketConnectToAddress(connector, addressData, 0.125)
        : kCFSocketError;
    if(networkBlocked) {
        skip("connect-to-address", "requires bound loopback socket");
    } else {
        check("connect-to-address", connectResult == kCFSocketSuccess);
    }
    if(connector) {
        CFSocketInvalidate(connector);
        CFRelease(connector);
    }
    if(addressData) CFRelease(addressData);

    CFRunLoopSourceRef source = receiver
        ? CFSocketCreateRunLoopSource(
              kCFAllocatorDefault, receiver, INT32_MIN)
        : NULL;
    check("create-run-loop-source", source != NULL);

    int sender = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
    ssize_t sent = sender >= 0 && networkReady
        ? sendto(sender, expectedPayload, sizeof(expectedPayload) - 1, 0,
              (const struct sockaddr *)&receiverAddress,
              receiverAddressLength)
        : -1;
    if(networkBlocked) {
        skip("send-local-datagram", "execution sandbox denied bind");
    } else {
        check("send-local-datagram",
            sent == (ssize_t)(sizeof(expectedPayload) - 1));
    }

    CFRunLoopRunResult runResult = kCFRunLoopRunFinished;
    if(source) {
        if(networkReady) {
            CFRunLoopRef runLoop = CFRunLoopGetCurrent();
            CFRunLoopAddSource(runLoop, source, kCFRunLoopDefaultMode);
            runResult = CFRunLoopRunInMode(
                kCFRunLoopDefaultMode, 1.0, true);
            CFRunLoopRemoveSource(runLoop, source,
                kCFRunLoopDefaultMode);
        }
        CFRelease(source);
    }
    if(sender >= 0) close(sender);

    if(networkBlocked) {
        skip("data-callback-ran", "execution sandbox denied bind");
        skip("callback-socket-identity", "callback not delivered");
        skip("callback-context-identity", "callback not delivered");
        skip("callback-address-data-proxy", "callback not delivered");
        skip("callback-payload-data-proxy", "callback not delivered");
    } else {
        check("data-callback-ran",
            runResult == kCFRunLoopRunHandledSource &&
            retainedInfo.callbacks == 1);
        check("callback-socket-identity", retainedInfo.sawSocketIdentity);
        check("callback-context-identity", retainedInfo.sawContextIdentity);
        check("callback-address-data-proxy", retainedInfo.sawAddress);
        check("callback-payload-data-proxy", retainedInfo.sawPayload);
    }

    if(receiver) {
        CFSocketInvalidate(receiver);
        check("invalidate", CFSocketGetNative(receiver) == -1);
        CFRelease(receiver);
    }
    check("context-released-once", retainedInfo.releases == 1);

    CFSocketContext invalidContext = {};
    invalidContext.version = 1;
    check("reject-context-version",
        CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM,
            IPPROTO_UDP, kCFSocketDataCallBack, socketCallback,
            &invalidContext) == NULL);
    check("reject-unsupported-callback",
        CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_DGRAM,
            IPPROTO_UDP, kCFSocketReadCallBack, socketCallback,
            NULL) == NULL);

    [pool drain];
    return failures != 0;
}
