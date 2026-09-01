@import Foundation;

#import <installd/MIExecutableBundle.h>
#import <libroot.h>

#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
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

static NSString *LC32CurrentExecutableBundleIdentifier(void) {
    char executablePath[PATH_MAX] = {0};
    uint32_t executablePathCapacity = sizeof(executablePath);
    if(_NSGetExecutablePath(
            executablePath, &executablePathCapacity) != 0) {
        return nil;
    }

    NSString *executablePathString =
        [NSFileManager.defaultManager
            stringWithFileSystemRepresentation:executablePath
            length:strlen(executablePath)];
    NSString *infoPath = [[executablePathString
        stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *infoDictionary =
        [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSString *bundleIdentifier =
        infoDictionary[@"CFBundleIdentifier"];
    return [bundleIdentifier isKindOfClass:NSString.class] ?
        bundleIdentifier : nil;
}

static BOOL LC32InjectArm64ExecutableSliceWithError(
        NSString *executablePath,
        NSString *bundleIdentifierString,
        NSError *__autoreleasing *error) {
    if(error != NULL) *error = nil;

    LC32MachOInjectionResult injectionResult =
        LC32MachOInjectionNotApplicable;
    char injectionError[512] = {0};
    const char *targetPath = executablePath.fileSystemRepresentation;
    const char *bundleIdentifier = bundleIdentifierString.UTF8String;
    char shimPathBuffer[PATH_MAX] = {0};
    const char *shimPath = libroot_dyn_jbrootpath(
        "/Applications/LiveExec32.app/LiveExec32", shimPathBuffer);

    if(targetPath == NULL || targetPath[0] == '\0') {
        injectionResult = LC32MachOInjectionFailed;
        snprintf(injectionError, sizeof(injectionError),
            "bundle has no executable path");
    } else if(bundleIdentifier == NULL || bundleIdentifier[0] == '\0') {
        injectionResult = LC32MachOInjectionFailed;
        snprintf(injectionError, sizeof(injectionError),
            "bundle has no identifier");
    } else if(shimPath == NULL || shimPath[0] == '\0') {
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
        return YES;
    }
    if(injectionResult == LC32MachOInjectionNotApplicable) return YES;

    NSString *message = [NSString stringWithUTF8String:injectionError] ?:
        @"unknown Mach-O injection failure";
    NSLog(@"LiveExec32Injector: could not process %@: %@",
        executablePath, message);
    if(error != NULL) *error = LC32InjectorError(message, nil);
    return NO;
}

%group LC32InstalldHooks

%hook MIExecutableBundle

- (BOOL)_validateWithError:
        (NSError *__autoreleasing *)error {
    NSString *pkgPath = [self.bundleURL.path stringByAppendingPathComponent:@"PkgInfo"];
    BOOL isPlaceholder = ![NSFileManager.defaultManager fileExistsAtPath:pkgPath];
    BOOL isValid = %orig;
    if(isPlaceholder || self.bundleType != MIBundleTypeUserApp || !isValid)
        return isValid;

    NSString *executablePath = self.executableURL.path;
    NSString *bundleIdentifierString = self.identifier;
    NSError *injectionError = nil;
    if(!LC32InjectArm64ExecutableSliceWithError(
            executablePath, bundleIdentifierString,
            &injectionError)) {
        if(error != NULL) *error = injectionError;
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

%group LC32TrollStoreLiteHooks

%hookf(int, signApp, NSString *appPath) {
    @autoreleasepool {
        if(![appPath isKindOfClass:NSString.class] ||
                appPath.length == 0) {
            return %orig(appPath);
        }

        NSString *infoPath =
            [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *infoDictionary =
            [NSDictionary dictionaryWithContentsOfFile:infoPath];
        NSString *bundleIdentifierString =
            infoDictionary[@"CFBundleIdentifier"];
        NSString *executableName =
            infoDictionary[@"CFBundleExecutable"];
        if(![bundleIdentifierString isKindOfClass:NSString.class] ||
                bundleIdentifierString.length == 0 ||
                ![executableName isKindOfClass:NSString.class] ||
                executableName.length == 0 ||
                ![executableName
                    isEqualToString:executableName.lastPathComponent] ||
                [executableName isEqualToString:@"."] ||
                [executableName isEqualToString:@".."]) {
            return %orig(appPath);
        }

        NSString *executablePath =
            [appPath stringByAppendingPathComponent:executableName];
        if(![NSFileManager.defaultManager
                fileExistsAtPath:executablePath]) {
            return %orig(appPath);
        }

        /* TrollStore Lite only accepts decrypted apps. Install the signed,
         * arm64-first image before its normal signing pass so it reads the
         * merged target/shim entitlements from the preferred slice and then
         * applies them while re-signing the bundle. */
        NSError *injectionError = nil;
        if(!LC32InjectArm64ExecutableSliceWithError(
                executablePath, bundleIdentifierString,
                &injectionError)) {
            NSLog(@"LiveExec32Injector: TrollStore Lite could not prepare "
                "%@: %@", appPath, injectionError);
            return 175;
        }
    }
    return %orig(appPath);
}

%end

%ctor {
    @autoreleasepool {
        NSString *processName = NSProcessInfo.processInfo.processName;
        if([processName isEqualToString:@"installd"]) {
            Class executableBundleClass =
                NSClassFromString(@"MIExecutableBundle");
            SEL validateSelector =
                @selector(_validateWithError:);
            if([executableBundleClass
                    instancesRespondToSelector:validateSelector]) {
                %init(LC32InstalldHooks);
            } else {
                NSLog(@"LiveExec32Injector: supported MobileInstallation API "
                    "is unavailable; injector disabled");
            }
        } else if([processName isEqualToString:@"trollstorehelper"] &&
                [LC32CurrentExecutableBundleIdentifier()
                    isEqualToString:@"com.opa334.TrollStoreLite"]) {
            void *signAppFunction = dlsym(RTLD_DEFAULT, "signApp");
            if(signAppFunction != NULL) {
                %init(LC32TrollStoreLiteHooks,
                    signApp = signAppFunction);
            } else {
                NSLog(@"LiveExec32Injector: signApp is unavailable; "
                    "TrollStore Lite injector disabled");
            }
        }
    }
}
