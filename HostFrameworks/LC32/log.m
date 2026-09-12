@import Darwin;
@import Foundation;
#include <asl.h>
#include <sys/utsname.h>

extern CFTypeRef MGCopyAnswer(CFStringRef property, CFDictionaryRef options)
    __attribute__((weak_import));

@interface NSUserDefaults(LiveContainer)
+ (instancetype)lcSharedDefaults;
@end

static NSString *LC32DeviceModel(void) {
    const char *simulatorModel = getenv("SIMULATOR_MODEL_IDENTIFIER");
    if(simulatorModel && simulatorModel[0]) {
        return [NSString stringWithFormat:@"Simulator (%s)", simulatorModel];
    }

    // MobileGestalt is weak-linked; balance its owned Copy result under MRC.
    NSString *name = MGCopyAnswer
        ? [(NSString *)MGCopyAnswer(CFSTR("marketing-name"), NULL) autorelease] : nil;
    if(name.length) return name;

    struct utsname systemInfo;
    return uname(&systemInfo) == 0
        ? [NSString stringWithUTF8String:systemInfo.machine] : @"unknown";
}

static void LC32LogBuildAndDeviceInfo(void) {
    @autoreleasepool {
        NSBundle *lc32Bundle = [NSBundle bundleWithIdentifier:@CONFIG_SHARED_FRAMEWORK_BUNDLE_ID];
        NSString *lc32Version = lc32Bundle.infoDictionary[@"CFBundleShortVersionString"];
        printf("LiveExec32 version: %s commit %s (%s)\n",
            (lc32Version ?: @CONFIG_VERSION).UTF8String, CONFIG_COMMIT, CONFIG_BRANCH);
        printf("Device: %s, %s\n", LC32DeviceModel().UTF8String,
            NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
    }
}

__attribute__((constructor)) void logToFileIfNeeded() {
    // Don't log in CLI
    if(getppid() != 1) return;

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *home = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path;
    NSString *currName = [home stringByAppendingPathComponent:@"LiveExec32.log"];
    NSString *oldName = [home stringByAppendingPathComponent:@"LiveExec32.old.log"];
    [fm removeItemAtPath:oldName error:nil];
    [fm moveItemAtPath:currName toPath:oldName error:nil];
    if (getenv("LC_HOME_PATH")) {
        [NSUserDefaults.lcSharedDefaults setURL:[NSURL fileURLWithPath:currName] forKey:@"LC32BitTranslationLayerLogFile"];
    }

    [fm createFileAtPath:currName contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:currName];

    if(!file) {
        assert(0 && "Failed to open LiveExec32.log. Check oslog for more details.");
    }

    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered

    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));

    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ssize_t rsize;
        char buf[2048];
        while((rsize = read(pfd[0], buf, sizeof(buf)-1)) > 0) {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "%s", buf);
            [file writeData:[NSData dataWithBytes:buf length:rsize]];
            [file synchronizeFile];
        }
        [file closeFile];
    });

    LC32LogBuildAndDeviceInfo();
}
