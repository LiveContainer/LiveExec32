#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

static int failures, retains, releases, reads, writes, accepts, accepted = -1;
static CFSocketRef expected;
static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
static const void *retainInfo(const void *info) { ++retains; return info; }
static void releaseInfo(const void *info) { (void)info; ++releases; }
static void callback(CFSocketRef socket, CFSocketCallBackType type,
        CFDataRef address, const void *data, void *info) {
    if(socket != expected || info != &expected) ++failures;
    if(type == kCFSocketReadCallBack) {
        char byte = 0;
        check("native-read-callback-payload", !data && read(CFSocketGetNative(socket), &byte, 1) == 1 && byte == 'x');
        ++reads;
    } else if(type == kCFSocketWriteCallBack) {
        check("native-write-callback-null-data", data == NULL);
        ++writes;
        CFSocketDisableCallBacks(socket, kCFSocketWriteCallBack);
    } else if(type == kCFSocketAcceptCallBack) {
        accepted = data ? *(const CFSocketNativeHandle *)data : -1;
        check("native-accept-callback-fd", accepted >= 0 && address != NULL && fcntl(accepted, F_GETFD) >= 0);
        ++accepts;
    }
}

int main(void) {
    @autoreleasepool {
        int pair[2];
        if(socketpair(AF_UNIX, SOCK_STREAM, 0, pair)) return 1;
        CFSocketContext context = {0, &expected, retainInfo, releaseInfo, NULL};
        expected = CFSocketCreateWithNative(NULL, pair[0],
            kCFSocketReadCallBack | kCFSocketWriteCallBack, callback, &context);
        check("socket-native-create-ownership", expected && CFSocketGetNative(expected) == pair[0] && retains == 1 && releases == 0);
        if(!expected) return 1;
        // Invalidation must not close a caller-owned descriptor when requested.
        CFSocketSetSocketFlags(expected, CFSocketGetSocketFlags(expected) & ~kCFSocketCloseOnInvalidate);
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, expected, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        write(pair[1], "x", 1);
        for(int i = 0; i < 10 && (!reads || !writes); ++i)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        check("socket-native-read-write", reads == 1 && writes == 1);
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);
        CFSocketInvalidate(expected); CFRelease(expected);
        check("socket-native-preserve-fd-context-release", releases == retains && fcntl(pair[0], F_GETFD) >= 0);
        close(pair[0]); close(pair[1]);

        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address = {0};
        address.sin_len = sizeof(address); address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        socklen_t length = sizeof(address);
        if(listener < 0 || bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
            getsockname(listener, (struct sockaddr *)&address, &length) || listen(listener, 1)) return 1;
        expected = CFSocketCreateWithNative(NULL, listener, kCFSocketAcceptCallBack, callback, &context);
        source = expected ? CFSocketCreateRunLoopSource(NULL, expected, 0) : NULL;
        if(!source) return 1;
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        int client = socket(AF_INET, SOCK_STREAM, 0);
        check("socket-native-loopback-connect", client >= 0 && connect(client, (struct sockaddr *)&address, length) == 0);
        for(int i = 0; i < 10 && !accepts; ++i)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        check("socket-native-accept", accepts == 1 && accepted >= 0);
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source); CFSocketInvalidate(expected); CFRelease(expected);
        check("socket-native-default-closes-fd", fcntl(listener, F_GETFD) == -1 && releases == retains);
        if(accepted >= 0) close(accepted);
        if(client >= 0) close(client);
    }
    return failures;
}
