@import Darwin;
@import Foundation;
#include <asl.h>

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
}
