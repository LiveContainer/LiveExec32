#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// Set TMPDIR outside both the guest home and /var to exercise the explicit
// native temporary-directory mount (e.g. a simulator container under /Users).
static unsigned checks, failures;
static void check(const char *name, BOOL passed) {
    ++checks;
    failures += !passed;
    printf("temporary-files-%s: %s\n", name, passed ? "PASS" : "FAIL");
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSString *temporary = NSTemporaryDirectory();
        printf("temporary=%s\n", temporary.UTF8String);
        struct stat info = {0};
        check("directory-visible", temporary &&
            stat(temporary.fileSystemRepresentation, &info) == 0 &&
            S_ISDIR(info.st_mode));
        NSString *template = [temporary stringByAppendingPathComponent:
            @"lc32-file-handle-XXXXXX"];
        char *path = template ? strdup(template.fileSystemRepresentation) : NULL;
        int descriptor = path ? mkstemp(path) : -1;
        check("mkstemp", descriptor >= 0);
        if(descriptor >= 0) {
            NSString *filePath = [NSString stringWithUTF8String:path];
            const char bytes[] = "guest fd / native file handle";
            NSData *payload = [NSData dataWithBytes:bytes length:sizeof(bytes)];
            NSFileHandle *handle = [[NSFileHandle alloc]
                initWithFileDescriptor:descriptor closeOnDealloc:YES];
            @try {
                [handle writeData:payload];
                check("native-write", [[NSData dataWithContentsOfFile:
                    filePath] isEqualToData:payload]);
                char actual[sizeof(bytes)] = {0};
                check("posix-read", pread(descriptor, actual, sizeof(actual), 0)
                    == sizeof(actual) && memcmp(bytes, actual, sizeof(bytes)) == 0);
            } @catch(NSException *exception) {
                printf("file-handle exception: %s\n", exception.reason.UTF8String);
                check("native-write", NO);
            }
            [handle closeFile];
            [handle release];
            check("unlink", unlink(path) == 0 &&
                ![[NSFileManager defaultManager] fileExistsAtPath:filePath]);
            errno = 0;
            int missing = open(path, O_RDONLY);
            check("missing-file-unchanged", missing == -1 && errno == ENOENT);
            if(missing >= 0) close(missing);
            check("native-create", [payload writeToFile:filePath atomically:YES]);
            descriptor = open(path, O_RDONLY);
            char actual[sizeof(bytes)] = {0};
            check("native-create-posix-read", descriptor >= 0 &&
                read(descriptor, actual, sizeof(actual)) == sizeof(actual) &&
                memcmp(bytes, actual, sizeof(bytes)) == 0);
            if(descriptor >= 0) close(descriptor);
            unlink(path);
        }
        free(path);
    }
    printf("temporary-files: %s (%u/%u checks)\n",
        failures ? "FAIL" : "PASS", checks - failures, checks);
    return failures != 0;
}
