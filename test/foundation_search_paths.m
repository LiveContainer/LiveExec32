#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

/* Run in a configured guest container. For the simulator regression, set
 * SIMCTL_CHILD_LC32_GUEST_HOME and SIMCTL_CHILD_CFFIXED_USER_HOME to the same
 * symlink, targeting a writable home with Documents and Library/Caches. */
static unsigned checks, failures;

static void check(const char *name, BOOL passed) {
    ++checks;
    failures += !passed;
    printf("foundation-search-paths-%s: %s\n", name, passed ? "PASS" : "FAIL");
}

/* Foundation may spell /private/var as /var. Do not resolve other symlinks:
 * the regression is precisely a stale alias returned by native Foundation. */
static NSString *pathSpelling(NSString *path) {
    return [path hasPrefix:@"/private/var/"] ? [path substringFromIndex:8] : path;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        NSString *environmentHome = getenv("HOME")
            ? [NSString stringWithUTF8String:getenv("HOME")] : nil;
        check("home-environment", [home isEqualToString:environmentHome]);
        check("home-absolute", [home hasPrefix:@"/"]);
        NSString *prefix = [pathSpelling(home) stringByAppendingString:@"/"];
        NSFileManager *manager = [NSFileManager defaultManager];
        const NSSearchPathDirectory directories[] = {
            NSDocumentDirectory, NSLibraryDirectory,
            NSCachesDirectory, NSApplicationSupportDirectory
        };
        for(unsigned i = 0; i < sizeof(directories) / sizeof(directories[0]); ++i) {
            NSSearchPathDirectory directory = directories[i];
            printf("directory: %lu\n", (unsigned long)directory);
            NSArray *paths = NSSearchPathForDirectoriesInDomains(
                directory, NSUserDomainMask, YES);
            NSArray *urls = [manager URLsForDirectory:directory inDomains:NSUserDomainMask];
            check("search-path-present", paths.count != 0);
            check("search-url-present", urls.count != 0);
            if(!paths.count || !urls.count) continue;
            NSString *path = [paths objectAtIndex:0];
            NSURL *url = [urls objectAtIndex:0];
            printf("path=%s\nurl=%s\n", path.UTF8String, url.absoluteString.UTF8String);
            check("search-path-home", [pathSpelling(path) hasPrefix:prefix]);
            check("search-url-home", url.isFileURL &&
                [pathSpelling(url.path) hasPrefix:prefix]);

            NSError *error = nil;
            NSURL *created = [manager URLForDirectory:directory inDomain:NSUserDomainMask
                appropriateForURL:nil create:YES error:&error];
            check("created-url-home", created && !error && created.isFileURL &&
                [pathSpelling(created.path) hasPrefix:prefix]);
            struct stat info = {0};
            check("created-url-posix-visible", created &&
                stat(created.path.fileSystemRepresentation, &info) == 0 &&
                S_ISDIR(info.st_mode));
        }
        /* Keep ordinary string-search failure semantics intact. */
        check("not-found-unchanged", [@"file:///Users/example"
            rangeOfString:@"/var/"].location == NSNotFound);
    }
    printf("foundation-search-paths: %s (%u/%u checks)\n",
        failures ? "FAIL" : "PASS", checks - failures, checks);
    return failures != 0;
}
