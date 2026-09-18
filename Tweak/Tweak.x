@import Foundation;

#import <installd/MIExecutableBundle.h>
#import <MobileCoreServices/LSApplicationProxy.h>
#import <libroot.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#import "FatMachO.h"
#import "LegacyBundleLayout.h"

@interface MIExecutableBundle (LiveExec32Injector)
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *executableURL;
- (BOOL)_validateWithError:
    (NSError *__autoreleasing *)error;
@end

/* Verified in installd 16.5 and 26.1. Keep these declarations direct so a
 * private-API mismatch produces a useful crash report instead of silently
 * disabling the compatibility link. */
@interface MIContainer : NSObject
@property (nonatomic, readonly) NSURL *containerURL;
@property (nonatomic, readonly) NSString *identifier;
@end
@interface MIBundleContainer : MIContainer
@property (nonatomic, readonly) MIExecutableBundle *bundle;
@end
@interface MIDataContainer : MIContainer
@end
@interface MIInstallableBundle : NSObject
@property (nonatomic, readonly) MIBundleContainer *bundleContainer;
@property (nonatomic, readonly) MIDataContainer *dataContainer;
@property (nonatomic, readonly) BOOL isPlaceholderInstall;
- (BOOL)finalizeInstallationWithError:(NSError *__autoreleasing *)error;
@end

static NSString *const LC32InjectorErrorDomain =
    @"com.kdt.LiveExec32.Injector";
static pthread_mutex_t LC32InjectionMutex = PTHREAD_MUTEX_INITIALIZER;

static BOOL LC32BundleNeedsLegacyLayout(NSURL *bundleURL,
        NSString *bundleIdentifier) {
    if(![bundleURL isKindOfClass:NSURL.class] || !bundleURL.isFileURL ||
            ![bundleURL.path.pathExtension isEqualToString:@"app"] ||
            ![bundleIdentifier isKindOfClass:NSString.class] ||
            bundleIdentifier.length == 0) return NO;
    int directory = open(bundleURL.fileSystemRepresentation,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if(directory < 0) return NO;
    BOOL eligible = NO;
    int infoFD = openat(directory, "Info.plist", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    @try {
      if(infoFD >= 0) {
        struct stat metadata;
        if(fstat(infoFD, &metadata) == 0 && S_ISREG(metadata.st_mode) &&
                metadata.st_size > 0 && metadata.st_size <= 4 * 1024 * 1024) {
            NSFileHandle *file = [[NSFileHandle alloc]
                initWithFileDescriptor:infoFD closeOnDealloc:NO];
            NSData *data = [file readDataOfLength:(NSUInteger)metadata.st_size];
            id info = [NSPropertyListSerialization propertyListWithData:data
                options:NSPropertyListImmutable format:NULL error:NULL];
            if([info isKindOfClass:NSDictionary.class] &&
                    [info[@"CFBundleIdentifier"] isEqual:bundleIdentifier]) {
                NSString *name = info[@"CFBundleExecutable"];
                if([name isKindOfClass:NSString.class] && name.length > 0 &&
                        [name isEqualToString:name.lastPathComponent] &&
                        ![name isEqualToString:@"."] && ![name isEqualToString:@".."]) {
                    int executable = openat(directory, name.fileSystemRepresentation,
                        O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
                    if(executable >= 0) {
                        eligible = LC32ExecutableNeedsLegacyBundleLayout(executable);
                        close(executable);
                    }
                }
            }
        }
      }
    } @finally {
        if(infoFD >= 0) close(infoFD);
        close(directory);
    }
    return eligible;
}

static void LC32InstallLegacyOuterLink(NSURL *bundleURL,
        NSString *bundleIdentifier, NSURL *dataContainerURL) {
    if(![dataContainerURL isKindOfClass:NSURL.class] ||
            !dataContainerURL.isFileURL ||
            !LC32BundleNeedsLegacyLayout(bundleURL, bundleIdentifier)) return;
    int error = LC32CreateLegacyBundleOuterLink(
        dataContainerURL.fileSystemRepresentation);
    if(error != 0) {
        NSLog(@"LiveExec32Injector: could not create legacy bundle link for %@: %s",
            bundleIdentifier, strerror(error));
    }
}

static BOOL LC32SameDirectory(NSURL *first, NSURL *second) {
    if(![first isKindOfClass:NSURL.class] || !first.isFileURL ||
            ![second isKindOfClass:NSURL.class] || !second.isFileURL) return NO;
    struct stat a, b;
    return stat(first.fileSystemRepresentation, &a) == 0 &&
        stat(second.fileSystemRepresentation, &b) == 0 &&
        S_ISDIR(a.st_mode) && S_ISDIR(b.st_mode) &&
        a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

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
    NSString *csPath = [self.bundleURL.path stringByAppendingPathComponent:@"_CodeSignature"];
    BOOL isPlaceholder = ![NSFileManager.defaultManager fileExistsAtPath:pkgPath] &&
        ![NSFileManager.defaultManager fileExistsAtPath:csPath];
        
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

%group LC32InstalldLegacyLayoutHooks

%hook MIInstallableBundle

- (BOOL)finalizeInstallationWithError:(NSError *__autoreleasing *)error {
    BOOL succeeded = %orig;
    if(!succeeded || self.isPlaceholderInstall) return succeeded;
    /* finalize commits the data/bundle containers after verification.
     * Apple also has a compatibility-link helper, but its highest-SDK
     * check sees our modern ARM64 shim and its direct-link replacement
     * policy does not preserve conflicts or implement the two-hop layout. */
    MIExecutableBundle *bundle = self.bundleContainer.bundle;
    MIDataContainer *data = self.dataContainer;
    if(bundle.bundleType == MIBundleTypeUserApp) {
        LC32InstallLegacyOuterLink(bundle.bundleURL, bundle.identifier,
            data.containerURL);
    }
    return succeeded;
}

%end

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

%group LC32TrollStoreLiteLegacyLayoutHooks

%hookf(bool, registerPath, NSString *appPath, BOOL unregister, BOOL forceSystem) {
    bool succeeded = %orig(appPath, unregister, forceSystem);
    if(!succeeded || unregister) return succeeded;
    if(![appPath isKindOfClass:NSString.class] || !appPath.isAbsolutePath)
        return succeeded;
    NSURL *bundleURL = [NSURL fileURLWithPath:
        appPath.stringByResolvingSymlinksInPath isDirectory:YES];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:
        [bundleURL URLByAppendingPathComponent:@"Info.plist"]];
    NSString *identifier = info[@"CFBundleIdentifier"];
    if(![identifier isKindOfClass:NSString.class] || identifier.length == 0)
        return succeeded;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    LSApplicationProxy *proxy = [proxyClass applicationProxyForIdentifier:identifier];
    /* registerPath creates the data container and registers its actual
     * HOME. Never create a container from an incoming identifier at the
     * earlier signApp stage, or use trollstorehelper's own HOME. */
    if(proxy.isContainerized && LC32SameDirectory(bundleURL, proxy.bundleURL)) {
        LC32InstallLegacyOuterLink(proxy.bundleURL, identifier, proxy.dataContainerURL);
    }
    return succeeded;
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
            %init(LC32InstalldLegacyLayoutHooks);
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
            void *registerPathFunction = dlsym(RTLD_DEFAULT, "registerPath");
            if(registerPathFunction != NULL) {
                %init(LC32TrollStoreLiteLegacyLayoutHooks,
                    registerPath = registerPathFunction);
            } else {
                NSLog(@"LiveExec32Injector: registerPath is unavailable; TrollStore Lite legacy link setup disabled");
            }
        }
    }
}
