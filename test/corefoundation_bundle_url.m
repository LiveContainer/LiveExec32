#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    CFBundleRef mainBundle = CFBundleGetMainBundle();
    CFURLRef sourceURL = mainBundle
        ? CFBundleCopyBundleURL(mainBundle)
        : NULL;
    NSString *expectedPath = sourceURL
        ? [[(NSURL *)sourceURL path] copy]
        : nil;

    /* Use an owned bundle so the copied URL must remain valid independently
     * of both the input URL and the bundle from which it was obtained. */
    CFBundleRef recreatedBundle = sourceURL
        ? CFBundleCreate(kCFAllocatorDefault, sourceURL)
        : NULL;
    CFURLRef firstCopy = recreatedBundle
        ? CFBundleCopyBundleURL(recreatedBundle)
        : NULL;
    CFURLRef survivingCopy = recreatedBundle
        ? CFBundleCopyBundleURL(recreatedBundle)
        : NULL;

    check("bundle-url-create", mainBundle && sourceURL && recreatedBundle &&
        firstCopy && survivingCopy);
    if(firstCopy) CFRelease(firstCopy);
    if(recreatedBundle) CFRelease(recreatedBundle);
    if(sourceURL) CFRelease(sourceURL);

    CFStringRef survivingPath = survivingCopy
        ? CFURLCopyFileSystemPath(survivingCopy, kCFURLPOSIXPathStyle)
        : NULL;
    check("bundle-url-copy-ownership", survivingCopy && expectedPath &&
        [(NSURL *)survivingCopy isFileURL] &&
        survivingPath &&
        [(NSString *)survivingPath isEqualToString:expectedPath]);

    if(survivingCopy) CFRelease(survivingCopy);

    check("url-filesystem-path-copy-ownership", survivingPath &&
        expectedPath &&
        [(NSString *)survivingPath isEqualToString:expectedPath]);

    static const UInt8 guestSystemPath[] = "/System/Library";
    CFURLRef translatedURL = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, guestSystemPath,
        sizeof(guestSystemPath) - 1, true);
    CFStringRef translatedPath = translatedURL
        ? CFURLCopyFileSystemPath(
            translatedURL, kCFURLPOSIXPathStyle) : NULL;
    check("url-filesystem-path-guest-translation", translatedPath &&
        CFEqual(translatedPath, CFSTR("/System/Library")));

    if(survivingPath) CFRelease(survivingPath);
    if(translatedPath) CFRelease(translatedPath);
    if(translatedURL) CFRelease(translatedURL);
    [expectedPath release];
    [pool drain];
    return failures != 0;
}
