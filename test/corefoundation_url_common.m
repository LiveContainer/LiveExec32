#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(CFRange) == 8,
               "the guest CFRange ABI must remain two 32-bit words");

static int failures;

static void check(const char *name, BOOL condition) {
    printf("%s: %s\n", name, condition ? "PASS" : "FAIL");
    failures += !condition;
}

static BOOL stringEquals(CFStringRef string, NSString *expected) {
    return string && [(NSString *)string isEqualToString:expected];
}

static BOOL rangeEquals(CFRange range, CFIndex location, CFIndex length) {
    return range.location == location && range.length == length;
}

static BOOL pathEquals(CFURLRef url, NSString *expected) {
    CFStringRef path = url
        ? CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle)
        : NULL;
    const BOOL equal = stringEquals(path, expected);
    if(path) CFRelease(path);
    return equal;
}

static BOOL byteRangeEquals(const UInt8 *bytes, CFIndex byteCount,
                            CFRange range, const char *expected) {
    const size_t expectedLength = strlen(expected);
    if(!bytes || range.location < 0 || range.length < 0 ||
       range.location > byteCount ||
       range.length > byteCount - range.location ||
       (size_t)range.length != expectedLength) {
        return NO;
    }
    return memcmp(bytes + range.location, expected, expectedLength) == 0;
}

static void testRelativeAndComponents(void) {
    CFURLRef base = CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("https://user:pa%20ss@example.test:8443/root/"), NULL);
    CFURLRef relative = CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("child/file.tar.gz?name=one%20two#part"), base);

    check("url-type-id", base && CFURLGetTypeID() != 0 &&
        CFGetTypeID(base) == CFURLGetTypeID());
    check("url-get-string", relative && stringEquals(
        CFURLGetString(relative), @"child/file.tar.gz?name=one%20two#part"));
    check("url-get-base", relative && CFURLGetBaseURL(relative) &&
        CFEqual(CFURLGetBaseURL(relative), base));
    check("url-can-be-decomposed", relative &&
        CFURLCanBeDecomposed(relative));

    CFURLRef absolute = relative ? CFURLCopyAbsoluteURL(relative) : NULL;
    check("url-copy-absolute", absolute && stringEquals(
        CFURLGetString(absolute),
        @"https://user:pa%20ss@example.test:8443/root/child/"
         "file.tar.gz?name=one%20two#part"));

    static const char expectedBytes[] =
        "https://user:pa%20ss@example.test:8443/root/child/"
        "file.tar.gz?name=one%20two#part";
    const CFIndex requiredBytes = absolute
        ? CFURLGetBytes(absolute, NULL, 0) : -1;
    UInt8 bytes[sizeof(expectedBytes) - 1] = {};
    const CFIndex copiedBytes = absolute ? CFURLGetBytes(
        absolute, bytes, sizeof(bytes)) : -1;
    check("url-get-bytes-length-query", requiredBytes == sizeof(bytes));
    check("url-get-bytes-exact-buffer", copiedBytes == sizeof(bytes) &&
        memcmp(bytes, expectedBytes, sizeof(bytes)) == 0);

    UInt8 shortBytes[5];
    memset(shortBytes, 0xa5, sizeof(shortBytes));
    const CFIndex shortResult = absolute ? CFURLGetBytes(
        absolute, shortBytes, sizeof(shortBytes) - 1) : 0;
    check("url-get-bytes-short-buffer", shortResult == -1 &&
        shortBytes[sizeof(shortBytes) - 1] == 0xa5);

    CFRange queryWithSeparators = CFRangeMake(kCFNotFound, 0);
    const CFRange queryRange = absolute
        ? CFURLGetByteRangeForComponent(absolute, kCFURLComponentQuery,
            &queryWithSeparators)
        : CFRangeMake(kCFNotFound, 0);
    const CFRange schemeRange = absolute
        ? CFURLGetByteRangeForComponent(
            absolute, kCFURLComponentScheme, NULL)
        : CFRangeMake(kCFNotFound, 0);
    CFRange absentWithSeparators = CFRangeMake(123, 456);
    const CFRange absentRange = absolute
        ? CFURLGetByteRangeForComponent(absolute,
            kCFURLComponentParameterString, &absentWithSeparators)
        : CFRangeMake(123, 456);
    check("url-byte-range-return-abi", byteRangeEquals(
        bytes, copiedBytes, queryRange, "name=one%20two"));
    check("url-byte-range-separators-out", byteRangeEquals(
        bytes, copiedBytes, queryWithSeparators, "?name=one%20two#"));
    check("url-byte-range-null-out", byteRangeEquals(
        bytes, copiedBytes, schemeRange, "https"));
    const char *querySeparator = strchr(expectedBytes, '?');
    check("url-byte-range-not-found", rangeEquals(
        absentRange, kCFNotFound, 0) && querySeparator && rangeEquals(
        absentWithSeparators, querySeparator - expectedBytes, 0));

    CFStringRef scheme = absolute ? CFURLCopyScheme(absolute) : NULL;
    CFStringRef host = absolute ? CFURLCopyHostName(absolute) : NULL;
    CFStringRef path = absolute ? CFURLCopyPath(absolute) : NULL;
    Boolean strictIsAbsolute = false;
    CFStringRef strictPath = absolute
        ? CFURLCopyStrictPath(absolute, &strictIsAbsolute) : NULL;
    CFStringRef resourceSpecifier = absolute
        ? CFURLCopyResourceSpecifier(absolute) : NULL;
    CFStringRef user = absolute ? CFURLCopyUserName(absolute) : NULL;
    CFStringRef password = absolute ? CFURLCopyPassword(absolute) : NULL;
    CFStringRef query = absolute
        ? CFURLCopyQueryString(absolute, CFSTR("")) : NULL;
    CFStringRef fragment = absolute
        ? CFURLCopyFragment(absolute, CFSTR("")) : NULL;
    CFStringRef lastComponent = absolute
        ? CFURLCopyLastPathComponent(absolute) : NULL;

    check("url-copy-scheme", stringEquals(scheme, @"https"));
    check("url-copy-host", stringEquals(host, @"example.test"));
    check("url-copy-path", stringEquals(
        path, @"/root/child/file.tar.gz"));
    check("url-copy-strict-path-out-param", strictIsAbsolute &&
        stringEquals(strictPath, @"root/child/file.tar.gz"));
    check("url-copy-resource-specifier", stringEquals(
        resourceSpecifier, @"?name=one%20two#part"));
    check("url-copy-user", stringEquals(user, @"user"));
    check("url-copy-password", stringEquals(password, @"pa ss"));
    check("url-port", CFURLGetPortNumber(absolute) == 8443);
    check("url-copy-query", stringEquals(query, @"name=one two"));
    check("url-copy-fragment", stringEquals(fragment, @"part"));
    check("url-copy-last-component",
        stringEquals(lastComponent, @"file.tar.gz"));

    if(base) CFRelease(base);
    if(relative) CFRelease(relative);

    /* Every Copy result must remain independently owned after both input
     * URLs have gone away. */
    check("url-copy-component-ownership",
        stringEquals(scheme, @"https") &&
        stringEquals(lastComponent, @"file.tar.gz"));
    check("url-copy-absolute-ownership", absolute && stringEquals(
        CFURLGetString(absolute),
        @"https://user:pa%20ss@example.test:8443/root/child/"
         "file.tar.gz?name=one%20two#part"));

    if(lastComponent) CFRelease(lastComponent);
    if(fragment) CFRelease(fragment);
    if(query) CFRelease(query);
    if(password) CFRelease(password);
    if(user) CFRelease(user);
    if(resourceSpecifier) CFRelease(resourceSpecifier);
    if(strictPath) CFRelease(strictPath);
    if(path) CFRelease(path);
    if(host) CFRelease(host);
    if(scheme) CFRelease(scheme);
    if(absolute) CFRelease(absolute);
}

static void testPathManipulation(void) {
    CFURLRef root = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
        CFSTR("/private/tmp/lc32 url root"), kCFURLPOSIXPathStyle, true);
    CFURLRef child = root ? CFURLCreateCopyAppendingPathComponent(
        kCFAllocatorDefault, root, CFSTR("archive name"), false) : NULL;
    CFURLRef childWithExtension = child
        ? CFURLCreateCopyAppendingPathExtension(
            kCFAllocatorDefault, child, CFSTR("tar")) : NULL;
    CFURLRef childWithoutExtension = childWithExtension
        ? CFURLCreateCopyDeletingPathExtension(
            kCFAllocatorDefault, childWithExtension) : NULL;
    CFURLRef parent = childWithoutExtension
        ? CFURLCreateCopyDeletingLastPathComponent(
            kCFAllocatorDefault, childWithoutExtension) : NULL;
    CFURLRef directory = root ? CFURLCreateCopyAppendingPathComponent(
        kCFAllocatorDefault, root, CFSTR("directory"), true) : NULL;

    check("url-append-component", pathEquals(
        child, @"/private/tmp/lc32 url root/archive name"));
    check("url-append-extension", pathEquals(childWithExtension,
        @"/private/tmp/lc32 url root/archive name.tar"));
    check("url-delete-extension", childWithoutExtension && child &&
        CFEqual(childWithoutExtension, child));
    check("url-delete-component", parent && root && CFEqual(parent, root));
    check("url-directory-path", directory &&
        CFURLHasDirectoryPath(directory) && pathEquals(
            directory, @"/private/tmp/lc32 url root/directory"));
    check("url-file-path", child && !CFURLHasDirectoryPath(child));

    if(root) CFRelease(root);
    check("url-derived-create-ownership", childWithExtension && pathEquals(
        childWithExtension,
        @"/private/tmp/lc32 url root/archive name.tar"));

    if(directory) CFRelease(directory);
    if(parent) CFRelease(parent);
    if(childWithoutExtension) CFRelease(childWithoutExtension);
    if(childWithExtension) CFRelease(childWithExtension);
    if(child) CFRelease(child);
}

static void testFileSystemRepresentation(void) {
    static const UInt8 systemPath[] = "/System/Library";
    CFURLRef system = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, systemPath, sizeof(systemPath) - 1, true);
    CFURLRef systemFromString = CFURLCreateWithFileSystemPath(
        kCFAllocatorDefault, CFSTR("/System/Library"),
        kCFURLPOSIXPathStyle, true);
    check("url-filesystem-string-constructor-mapping",
        system && systemFromString && CFEqual(systemFromString, system) &&
        stringEquals(CFURLGetString(systemFromString),
            @"file:///System/Library/"));

    static const char expectedURLBytes[] = "file:///System/Library/";
    UInt8 urlBytes[sizeof(expectedURLBytes) - 1] = {};
    const CFIndex urlByteCount = systemFromString ? CFURLGetBytes(
        systemFromString, urlBytes, sizeof(urlBytes)) : -1;
    CFRange pathWithSeparators = CFRangeMake(kCFNotFound, 0);
    const CFRange pathRange = systemFromString
        ? CFURLGetByteRangeForComponent(systemFromString,
            kCFURLComponentPath, &pathWithSeparators)
        : CFRangeMake(kCFNotFound, 0);
    check("url-filesystem-bytes-guest-path", urlByteCount ==
        sizeof(urlBytes) && memcmp(
            urlBytes, expectedURLBytes, sizeof(urlBytes)) == 0);
    check("url-filesystem-byte-range-guest-path", byteRangeEquals(
        urlBytes, urlByteCount, pathRange, "/System/Library/") &&
        byteRangeEquals(urlBytes, urlByteCount, pathWithSeparators,
            ":///System/Library/"));

    CFURLRef frameworks = CFURLCreateWithFileSystemPath(
        kCFAllocatorDefault, CFSTR("/System/Library/Frameworks"),
        kCFURLPOSIXPathStyle, true);
    CFURLRef relativeUIKit = frameworks
        ? CFURLCreateWithFileSystemPathRelativeToBase(
            kCFAllocatorDefault, CFSTR("UIKit.framework"),
            kCFURLPOSIXPathStyle, true, frameworks)
        : NULL;
    static const UInt8 relativeUIKitBytes[] = "UIKit.framework";
    CFURLRef relativeUIKitFromBytes = frameworks
        ? CFURLCreateFromFileSystemRepresentationRelativeToBase(
            kCFAllocatorDefault, relativeUIKitBytes,
            sizeof(relativeUIKitBytes) - 1, true, frameworks)
        : NULL;
    CFURLRef absoluteUIKit = relativeUIKit
        ? CFURLCopyAbsoluteURL(relativeUIKit) : NULL;
    CFBundleRef uiKitBundle = absoluteUIKit
        ? CFBundleCreate(kCFAllocatorDefault, absoluteUIKit) : NULL;
    check("url-filesystem-relative-base-mapping", absoluteUIKit &&
        pathEquals(absoluteUIKit,
            @"/System/Library/Frameworks/UIKit.framework") &&
        uiKitBundle && CFEqual(CFBundleGetIdentifier(uiKitBundle),
            CFSTR("com.apple.UIKit")));
    check("url-filesystem-relative-bytes", relativeUIKitFromBytes &&
        relativeUIKit && CFEqual(relativeUIKitFromBytes, relativeUIKit));

    static const UInt8 embeddedNULPath[] = {'b', 'a', 'd', 0, 'p', 'a', 't', 'h'};
    CFURLRef invalidNULURL =
        CFURLCreateFromFileSystemRepresentationRelativeToBase(
            kCFAllocatorDefault, embeddedNULPath,
            sizeof(embeddedNULPath), false, frameworks);
    check("url-filesystem-relative-bytes-nul", !invalidNULURL);

    UInt8 exact[sizeof("/System/Library")];
    memset(exact, 0xa5, sizeof(exact));
    const Boolean copied = system && CFURLGetFileSystemRepresentation(
        system, true, exact, sizeof(exact));
    check("url-filesystem-representation-guest-path", copied &&
        strcmp((const char *)exact, "/System/Library") == 0);

    UInt8 tooSmall[sizeof("/System/Library") - 1];
    memset(tooSmall, 0xa5, sizeof(tooSmall));
    const Boolean rejected = system && !CFURLGetFileSystemRepresentation(
        system, true, tooSmall, sizeof(tooSmall));
    BOOL untouched = YES;
    for(size_t index = 0; index < sizeof(tooSmall); ++index)
        untouched &= tooSmall[index] == 0xa5;
    check("url-filesystem-representation-capacity",
        rejected && untouched);

    if(uiKitBundle) CFRelease(uiKitBundle);
    if(invalidNULURL) CFRelease(invalidNULURL);
    if(absoluteUIKit) CFRelease(absoluteUIKit);
    if(relativeUIKitFromBytes) CFRelease(relativeUIKitFromBytes);
    if(relativeUIKit) CFRelease(relativeUIKit);
    if(frameworks) CFRelease(frameworks);
    if(systemFromString) CFRelease(systemFromString);
    if(system) CFRelease(system);
}

static void testResourcePropertyError(void) {
    static const UInt8 missingPath[] =
        "/private/tmp/lc32-corefoundation-url-missing/resource";
    CFURLRef missing = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault, missingPath, sizeof(missingPath) - 1, false);
    CFErrorRef error = NULL;
    const Boolean result = missing && CFURLSetResourcePropertyForKey(
        missing, kCFURLIsExcludedFromBackupKey, kCFBooleanTrue, &error);
    check("url-set-resource-property-error-out", !result && error &&
        CFGetTypeID(error) != 0);

    if(missing) CFRelease(missing);
    check("url-resource-error-copy-ownership", error &&
        CFErrorGetCode(error) != 0);
    if(error) CFRelease(error);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    testRelativeAndComponents();
    testPathManipulation();
    testFileSystemRepresentation();
    testResourcePropertyError();

    [pool drain];
    return failures != 0;
}
