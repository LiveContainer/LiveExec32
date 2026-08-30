#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL urlPathEquals(CFURLRef url, NSString *expected) {
    CFURLRef absoluteURL = url ? CFURLCopyAbsoluteURL(url) : NULL;
    CFStringRef path = absoluteURL
        ? CFURLCopyFileSystemPath(absoluteURL, kCFURLPOSIXPathStyle)
        : NULL;
    const BOOL result = path &&
        [(NSString *)path isEqualToString:expected];
    if(path) CFRelease(path);
    if(absoluteURL) CFRelease(absoluteURL);
    return result;
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

    static const UInt8 frameworkPath[] =
        "/System/Library/Frameworks/CoreFoundation.framework";
    CFURLRef frameworkURL = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, frameworkPath, sizeof(frameworkPath) - 1,
        true);
    CFBundleRef frameworkBundle = frameworkURL
        ? CFBundleCreate(kCFAllocatorDefault, frameworkURL) : NULL;
    CFDictionaryRef frameworkInfo = frameworkBundle
        ? CFBundleGetInfoDictionary(frameworkBundle) : NULL;
    CFTypeRef executableName = frameworkBundle
        ? CFBundleGetValueForInfoDictionaryKey(
            frameworkBundle, kCFBundleExecutableKey) : NULL;
    check("bundle-info-wrappers", frameworkBundle && frameworkInfo &&
        executableName && CFEqual(executableName, CFSTR("CoreFoundation")) &&
        CFEqual(CFBundleGetDevelopmentRegion(frameworkBundle),
                CFSTR("en_US")));
    check("bundle-local-info", frameworkBundle &&
        CFBundleGetLocalInfoDictionary(frameworkBundle) == NULL);

    CFURLRef supportURL = frameworkBundle
        ? CFBundleCopySupportFilesDirectoryURL(frameworkBundle) : NULL;
    CFURLRef resourcesURL = frameworkBundle
        ? CFBundleCopyResourcesDirectoryURL(frameworkBundle) : NULL;
    CFURLRef privateFrameworksURL = frameworkBundle
        ? CFBundleCopyPrivateFrameworksURL(frameworkBundle) : NULL;
    CFURLRef sharedFrameworksURL = frameworkBundle
        ? CFBundleCopySharedFrameworksURL(frameworkBundle) : NULL;
    CFURLRef sharedSupportURL = frameworkBundle
        ? CFBundleCopySharedSupportURL(frameworkBundle) : NULL;
    CFURLRef plugInsURL = frameworkBundle
        ? CFBundleCopyBuiltInPlugInsURL(frameworkBundle) : NULL;
    CFURLRef executableURL = frameworkBundle
        ? CFBundleCopyExecutableURL(frameworkBundle) : NULL;
    CFURLRef auxiliaryURL = frameworkBundle
        ? CFBundleCopyAuxiliaryExecutableURL(
            frameworkBundle, CFSTR("CoreFoundation")) : NULL;

    check("bundle-directory-urls", supportURL && resourcesURL &&
        privateFrameworksURL && sharedFrameworksURL && sharedSupportURL &&
        plugInsURL && urlPathEquals(supportURL,
            @"/System/Library/Frameworks/CoreFoundation.framework") &&
        urlPathEquals(resourcesURL,
            @"/System/Library/Frameworks/CoreFoundation.framework") &&
        urlPathEquals(privateFrameworksURL,
            @"/System/Library/Frameworks/CoreFoundation.framework/"
             "Frameworks"));
    check("bundle-executable-urls", executableURL && auxiliaryURL &&
        urlPathEquals(executableURL,
            @"/System/Library/Frameworks/CoreFoundation.framework/"
             "CoreFoundation") &&
        urlPathEquals(auxiliaryURL,
            @"/System/Library/Frameworks/CoreFoundation.framework/"
             "CoreFoundation"));

    CFArrayRef architectures = frameworkBundle
        ? CFBundleCopyExecutableArchitectures(frameworkBundle) : NULL;
    CFArrayRef localizations = frameworkBundle
        ? CFBundleCopyBundleLocalizations(frameworkBundle) : NULL;
    CFArrayRef preferred = localizations
        ? CFBundleCopyPreferredLocalizationsFromArray(localizations) : NULL;
    const void *preferenceValues[] = {CFSTR("en_US")};
    CFArrayRef preferences = CFArrayCreate(kCFAllocatorDefault,
        preferenceValues, 1, &kCFTypeArrayCallBacks);
    CFArrayRef preferredForPreferences = localizations
        ? CFBundleCopyLocalizationsForPreferences(
            localizations, preferences) : NULL;
    check("bundle-copy-architectures", architectures &&
        CFArrayGetCount(architectures) != 0);
    check("bundle-copy-localizations", localizations && preferred &&
        preferredForPreferences &&
        CFArrayContainsValue(localizations,
            CFRangeMake(0, CFArrayGetCount(localizations)), CFSTR("en_US")) &&
        CFArrayContainsValue(preferredForPreferences,
            CFRangeMake(0, CFArrayGetCount(preferredForPreferences)),
            CFSTR("en_US")));

    CFArrayRef plistURLs = frameworkBundle
        ? CFBundleCopyResourceURLsOfType(
            frameworkBundle, CFSTR("plist"), NULL) : NULL;
    CFURLRef localizedInfo = frameworkBundle
        ? CFBundleCopyResourceURLForLocalization(frameworkBundle,
            CFSTR("Info"), CFSTR("plist"), NULL, CFSTR("en_US")) : NULL;
    CFArrayRef localizedPlists = frameworkBundle
        ? CFBundleCopyResourceURLsOfTypeForLocalization(frameworkBundle,
            CFSTR("plist"), NULL, CFSTR("en_US")) : NULL;
    check("bundle-resource-url-copies", plistURLs && localizedInfo &&
        localizedPlists && CFArrayGetCount(plistURLs) != 0 &&
        CFArrayGetCount(localizedPlists) != 0 &&
        urlPathEquals(localizedInfo,
            @"/System/Library/Frameworks/CoreFoundation.framework/"
             "Info.plist"));

    CFErrorRef preflightError = NULL;
    const Boolean preflighted = frameworkBundle &&
        CFBundlePreflightExecutable(frameworkBundle, &preflightError);
    check("bundle-preflight-error-out", !preflighted && preflightError &&
        CFErrorGetCode(preflightError) != 0);
    check("bundle-loaded-state", frameworkBundle &&
        !CFBundleIsExecutableLoaded(frameworkBundle));
    if(frameworkBundle) CFBundleUnloadExecutable(frameworkBundle);

    if(frameworkURL) CFRelease(frameworkURL);
    if(frameworkBundle) CFRelease(frameworkBundle);
    check("bundle-new-copy-ownership", executableURL && localizedInfo &&
        preflightError && urlPathEquals(executableURL,
            @"/System/Library/Frameworks/CoreFoundation.framework/"
             "CoreFoundation") && CFErrorGetCode(preflightError) != 0);

    if(preflightError) CFRelease(preflightError);
    if(localizedPlists) CFRelease(localizedPlists);
    if(localizedInfo) CFRelease(localizedInfo);
    if(plistURLs) CFRelease(plistURLs);
    if(preferredForPreferences) CFRelease(preferredForPreferences);
    if(preferences) CFRelease(preferences);
    if(preferred) CFRelease(preferred);
    if(localizations) CFRelease(localizations);
    if(architectures) CFRelease(architectures);
    if(auxiliaryURL) CFRelease(auxiliaryURL);
    if(executableURL) CFRelease(executableURL);
    if(plugInsURL) CFRelease(plugInsURL);
    if(sharedSupportURL) CFRelease(sharedSupportURL);
    if(sharedFrameworksURL) CFRelease(sharedFrameworksURL);
    if(privateFrameworksURL) CFRelease(privateFrameworksURL);
    if(resourcesURL) CFRelease(resourcesURL);
    if(supportURL) CFRelease(supportURL);

    if(survivingPath) CFRelease(survivingPath);
    if(translatedPath) CFRelease(translatedPath);
    if(translatedURL) CFRelease(translatedURL);
    [expectedPath release];
    [pool drain];
    return failures != 0;
}
