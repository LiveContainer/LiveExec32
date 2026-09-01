@import Foundation;

#import <installd/MIExecutableBundle.h>
#import <libroot.h>

#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#import "FatMachO.h"

@interface MIExecutableBundle (LiveExec32Injector)
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *executableURL;
- (BOOL)_validateWithError:
    (NSError *__autoreleasing *)error;
@end

static NSString *const LC32InjectorErrorDomain =
    @"com.kdt.LiveExec32.Injector";
static pthread_mutex_t LC32InjectionMutex = PTHREAD_MUTEX_INITIALIZER;

static NSError *LC32InjectorError(
        NSString *message, NSError *underlyingError) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:
        message forKey:NSLocalizedDescriptionKey];
    if(underlyingError != nil) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }
    return [NSError errorWithDomain:LC32InjectorErrorDomain
        code:1 userInfo:userInfo];
}

%group LC32InjectorHooks

%hook MIExecutableBundle

- (BOOL)_validateWithError:
        (NSError *__autoreleasing *)error {
    NSString *pkgPath = [self.bundleURL.path stringByAppendingPathComponent:@"PkgInfo"];
    BOOL isPlaceholder = ![NSFileManager.defaultManager fileExistsAtPath:pkgPath];
    BOOL isValid = %orig;
    if(isPlaceholder || self.bundleType != MIBundleTypeUserApp || !isValid)
        return isValid;

    LC32MachOInjectionResult injectionResult =
        LC32MachOInjectionNotApplicable;
    char injectionError[512] = {0};
    NSString *executablePath = self.executableURL.path;
    const char *targetPath = executablePath.fileSystemRepresentation;
    NSString *bundleIdentifierString = self.identifier;
    const char *bundleIdentifier = bundleIdentifierString.UTF8String;
    char shimPath[PATH_MAX] = {0};
    libroot_dyn_jbrootpath(
        "/Applications/LiveExec32.app/LiveExec32", shimPath);

    if(targetPath == NULL || targetPath[0] == '\0') {
        injectionResult = LC32MachOInjectionFailed;
        snprintf(injectionError, sizeof(injectionError),
            "bundle has no executable path");
    } else if(bundleIdentifier == NULL || bundleIdentifier[0] == '\0') {
        injectionResult = LC32MachOInjectionFailed;
        snprintf(injectionError, sizeof(injectionError),
            "bundle has no identifier");
    } else if(shimPath[0] == '\0') {
        injectionResult = LC32MachOInjectionFailed;
        snprintf(injectionError, sizeof(injectionError),
            "could not resolve the installed LiveExec32 shim path");
    } else {
        const int lockError = pthread_mutex_lock(&LC32InjectionMutex);
        if(lockError != 0) {
            injectionResult = LC32MachOInjectionFailed;
            snprintf(injectionError, sizeof(injectionError),
                "could not lock the injector: %s",
                strerror(lockError));
        } else {
            injectionResult = LC32InjectArm64ExecutableSlice(
                targetPath, shimPath, bundleIdentifier,
                injectionError, sizeof(injectionError));
            pthread_mutex_unlock(&LC32InjectionMutex);
        }
    }

    if(injectionResult == LC32MachOInjectionSucceeded) {
        NSLog(@"LiveExec32Injector: added an arm64 slice to %@",
            executablePath);
    } else if(injectionResult == LC32MachOInjectionFailed) {
        NSString *message = [NSString stringWithUTF8String:injectionError] ?:
            @"unknown Mach-O injection failure";
        NSLog(@"LiveExec32Injector: could not process %@: %@",
            executablePath, message);
        if(error != NULL) *error = LC32InjectorError(message, nil);
        return NO;
    }

    return isValid;
}

%end

// Bypass Security::CodeSigning::UidGuard::seteuid(0) crash
%hookf(int, seteuid, uid_t uid) {
    %orig(uid);
    return 0;
}

%end

%ctor {
    @autoreleasepool {
        Class executableBundleClass =
            NSClassFromString(@"MIExecutableBundle");
        SEL validateSelector =
            @selector(_validateWithError:);
        if([executableBundleClass
                instancesRespondToSelector:validateSelector]) {
            %init(LC32InjectorHooks);
        } else {
            NSLog(@"LiveExec32Injector: supported MobileInstallation API "
                "is unavailable; injector disabled");
        }
    }
}
