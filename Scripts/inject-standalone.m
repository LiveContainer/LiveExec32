// Packaging helper: the Mach-O transformation itself is shared with the tweak.
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <unistd.h>
#include "FatMachO.h"
#include "MachOImage.h"

static void Fail(NSString *message) {
    fprintf(stderr, "inject-standalone: %s\n", message.UTF8String);
    exit(1);
}

static NSString *ExecutableName(NSDictionary *info) {
    id name = info[@"CFBundleExecutable"];
    if(![name isKindOfClass:NSString.class] || ![name length] ||
            [name containsString:@"/"] || [name isEqual:@"."] || [name isEqual:@".."]) {
        Fail(@"CFBundleExecutable must be a nonempty filename");
    }
    return name;
}

static LC32MachOImage ReadImage(NSString *path) {
    LC32MachOImage image = {0};
    char error[512] = {0};
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if(fd < 0) Fail([@"cannot open regular executable: " stringByAppendingString:path]);
    BOOL parsed = LC32MachOImageParseFD(fd, &image, error, sizeof(error));
    close(fd);
    if(!parsed) Fail([NSString stringWithUTF8String:error]);
    return image;
}

static BOOL IsVersion(id version) {
    if(![version isKindOfClass:NSString.class] || ![version length]) return NO;
    NSArray *parts = [version componentsSeparatedByString:@"."];
    if(parts.count > 3) return NO;
    for(NSString *part in parts) {
        if(!part.length || [part rangeOfCharacterFromSet:
                NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return NO;
    }
    return YES;
}

int main(int argc, const char *argv[]) {
    if(argc != 3) return 2;
    @autoreleasepool {
        NSString *app = [NSString stringWithUTF8String:argv[1]];
        NSString *runtime = [NSString stringWithUTF8String:argv[2]];
        NSString *plist = [app stringByAppendingPathComponent:@"Info.plist"];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:plist];
        NSDictionary *runtimeInfo = [NSDictionary dictionaryWithContentsOfFile:
            [runtime stringByAppendingPathComponent:@"Info.plist"]];
        if(!info || !runtimeInfo) Fail(@"cannot read app/runtime Info.plist");
        NSString *name = ExecutableName(info);
        if([name hasPrefix:@"LiveExec32"]) Fail(@"game executable uses the launcher's reserved LiveExec32 prefix");
        NSString *target = [app stringByAppendingPathComponent:name];
        NSString *shim = [runtime stringByAppendingPathComponent:ExecutableName(runtimeInfo)];
        NSString *identifier = info[@"CFBundleIdentifier"];
        if(![identifier isKindOfClass:NSString.class] || !identifier.length) Fail(@"missing game bundle identifier");
        LC32MachOImage guest = ReadImage(target);
        for(uint32_t i = 0; i < guest.count; ++i) {
            const LC32MachOSlice *slice = &guest.slices[i];
            if(slice->cpuType != CPU_TYPE_ARM || slice->fileType != MH_EXECUTE)
                Fail(@"input must contain only ARM32 executable slices; native or already-injected apps are not supported");
            if(slice->encrypted) Fail(@"encrypted ARM32 executable; provide a decrypted app");
        }
        LC32MachOImage host = ReadImage(shim);
        const LC32MachOSlice *arm64 = LC32MachOImageFindSlice(&host, CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL);
        if(!arm64 || !arm64->hasBuildVersion || arm64->buildVersionPlatform != PLATFORM_IOS)
            Fail(@"runtime must be a device iOS build, not a Catalyst or simulator build");
        NSData *launcher = [NSData dataWithContentsOfFile:shim];
        NSData *marker = [@"LiveExec32Standalone:1" dataUsingEncoding:NSUTF8StringEncoding];
        if(!launcher || [launcher rangeOfData:marker options:0
                range:NSMakeRange((NSUInteger)arm64->offset, (NSUInteger)arm64->size)].location == NSNotFound)
            Fail(@"launcher lacks bundled RootFS support; rebuild LiveExec32 with the current sources");

        NSString *minimum = runtimeInfo[@"MinimumOSVersion"];
        if(!IsVersion(minimum)) Fail(@"invalid runtime MinimumOSVersion");
        id originalMinimum = info[@"MinimumOSVersion"];
        if(originalMinimum && !IsVersion(originalMinimum)) Fail(@"invalid game MinimumOSVersion");
        if(!originalMinimum || [originalMinimum compare:minimum options:NSNumericSearch] == NSOrderedAscending)
            info[@"MinimumOSVersion"] = minimum;
        id capabilities = info[@"UIRequiredDeviceCapabilities"];
        NSArray *architectureCapabilities = @[@"armv6", @"armv7", @"armv7s", @"arm64", @"arm64e"];
        if([capabilities isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary *updated = [capabilities mutableCopy];
            [updated removeObjectsForKeys:architectureCapabilities];
            updated[@"arm64"] = @YES;
            info[@"UIRequiredDeviceCapabilities"] = updated;
        } else if(!capabilities || [capabilities isKindOfClass:NSArray.class]) {
            NSMutableArray *updated = capabilities ? [capabilities mutableCopy] : [NSMutableArray array];
            [updated removeObjectsInArray:architectureCapabilities];
            [updated addObject:@"arm64"];
            info[@"UIRequiredDeviceCapabilities"] = updated;
        } else {
            Fail(@"UIRequiredDeviceCapabilities must be an array or dictionary");
        }
        info[@"CFBundleSupportedPlatforms"] = @[@"iPhoneOS"];
        char error[512] = {0};
        if(LC32InjectArm64ExecutableSlice(target.fileSystemRepresentation,
                shim.fileSystemRepresentation, identifier.UTF8String, error, sizeof(error)) !=
                LC32MachOInjectionSucceeded) Fail([NSString stringWithUTF8String:error]);
        NSError *plistError = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:info
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:&plistError];
        if(!data || ![data writeToFile:plist options:NSDataWritingAtomic error:&plistError])
            Fail(plistError.localizedDescription ?: @"could not update Info.plist");
    }
    return 0;
}
