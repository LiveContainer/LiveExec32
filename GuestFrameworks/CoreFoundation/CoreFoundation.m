#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

const CFAllocatorRef kCFAllocatorDefault = NULL;

/*
 * Older iOS binaries bind this Foundation spelling directly against
 * CoreFoundation. Keep the compatibility export here as well as in the
 * Foundation shim so two-level namespace lookup succeeds.
 */
NSString * const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";

// Set CF version to iOS 10.3.3
double kCFCoreFoundationVersionNumber = (double)1349.7;

@implementation __NSCFType
@end

@implementation __NSCFString
@end
@implementation __NSCFConstantString

/*
 * Compiler-emitted CF/NSString literals live in Mach-O __cfstring storage;
 * they are not heap objects.  NSObject's LC32 ownership bridge must never
 * forward a final release for one of them or the guest runtime will try to
 * free an address inside the image.
 */
- (instancetype)retain {
    return self;
}

- (oneway void)release {
}

- (instancetype)autorelease {
    return self;
}

- (NSUInteger)retainCount {
    return NSUIntegerMax;
}

- (BOOL)_tryRetain {
    return YES;
}

- (BOOL)_isDeallocating {
    return NO;
}

- (BOOL)allowsWeakReference {
    return YES;
}

- (BOOL)retainWeakReference {
    return YES;
}

@end
// clang doesn't support alias on darwin, but we can use this truck
__asm__(" \n \
.section	__DATA,__objc_data \n \
.global ___CFConstantStringClassReference \n \
___CFConstantStringClassReference = _OBJC_CLASS_$___NSCFConstantString \
");

// For convenience, most CF functions are shims of Objective-C
CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef allocator, CFStringRef filePath, CFURLPathStyle pathStyle, Boolean isDirectory) {
    (void)allocator;
    if(!filePath) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateWithFileSystemPath,
        LC32_CF_HOST(filePath), LC32_CF_U32(pathStyle),
        LC32_CF_U32(isDirectory));
}

CFURLRef CFURLCreateWithFileSystemPathRelativeToBase(
        CFAllocatorRef allocator, CFStringRef filePath,
        CFURLPathStyle pathStyle, Boolean isDirectory, CFURLRef baseURL) {
    (void)allocator;
    if(!filePath) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateWithFileSystemPathRelativeToBase,
        LC32_CF_HOST(filePath), LC32_CF_U32(pathStyle),
        LC32_CF_U32(isDirectory), LC32_CF_HOST(baseURL));
}

CFURLRef CFURLCreateFromFileSystemRepresentation(
        CFAllocatorRef allocator, const UInt8 *buffer,
        CFIndex bufferLength, Boolean isDirectory) {
    (void)allocator;
    if(bufferLength < 0 || (bufferLength && !buffer)) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateFromFileSystemRepresentation,
        LC32_CF_U32((uintptr_t)buffer), LC32_CF_U32(bufferLength),
        LC32_CF_U32(isDirectory));
}

CFURLRef CFURLCreateFromFileSystemRepresentationRelativeToBase(
        CFAllocatorRef allocator, const UInt8 *buffer,
        CFIndex bufferLength, Boolean isDirectory, CFURLRef baseURL) {
    (void)allocator;
    if(bufferLength < 0 || (bufferLength && !buffer)) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateFromFileSystemRepresentationRelativeToBase,
        LC32_CF_U32((uintptr_t)buffer), LC32_CF_U32(bufferLength),
        LC32_CF_U32(isDirectory), LC32_CF_HOST(baseURL));
}

CFURLRef CFURLCreateWithString(CFAllocatorRef allocator,
                               CFStringRef URLString,
                               CFURLRef baseURL) {
    (void)allocator;
    if(!URLString) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateWithString,
        LC32_CF_HOST(URLString), LC32_CF_HOST(baseURL));
}

CFURLRef CFURLCreateWithBytes(CFAllocatorRef allocator,
                              const UInt8 *URLBytes, CFIndex length,
                              CFStringEncoding encoding,
                              CFURLRef baseURL) {
    (void)allocator;
    if(length < 0 || (uint64_t)length > INT32_MAX ||
       (length && !URLBytes)) return NULL;
    return (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateWithBytes,
        LC32_CF_U32((uintptr_t)URLBytes), LC32_CF_U32(length),
        LC32_CF_U32(encoding), LC32_CF_HOST(baseURL));
}

CFStringRef CFURLCopyPathExtension(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyPathExtension,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyFileSystemPath(CFURLRef url,
                                    CFURLPathStyle pathStyle) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyFileSystemPath,
        LC32_CF_HOST(url), LC32_CF_U32(pathStyle)) : NULL;
}

CFTypeID CFURLGetTypeID(void) {
    return (CFTypeID)LC32_CF_CALL0(
        LC32CoreFoundationOpURLGetTypeID);
}

CFStringRef CFURLGetString(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLGetString,
        LC32_CF_HOST(url)) : NULL;
}

CFURLRef CFURLGetBaseURL(CFURLRef url) {
    return url ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLGetBaseURL,
        LC32_CF_HOST(url)) : NULL;
}

Boolean CFURLCanBeDecomposed(CFURLRef url) {
    return url && LC32_CF_CALL(
        LC32CoreFoundationOpURLCanBeDecomposed,
        LC32_CF_HOST(url));
}

CFURLRef CFURLCopyAbsoluteURL(CFURLRef url) {
    return url ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyAbsoluteURL,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyScheme(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyScheme,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyHostName(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyHostName,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyPath(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyPath,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyStrictPath(CFURLRef url, Boolean *isAbsolute) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyStrictPath,
        LC32_CF_HOST(url), LC32_CF_U32((uintptr_t)isAbsolute)) : NULL;
}

CFStringRef CFURLCopyResourceSpecifier(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyResourceSpecifier,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyUserName(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyUserName,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyPassword(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyPassword,
        LC32_CF_HOST(url)) : NULL;
}

CFStringRef CFURLCopyQueryString(
        CFURLRef url, CFStringRef charactersToLeaveEscaped) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyQueryString,
        LC32_CF_HOST(url), LC32_CF_HOST(charactersToLeaveEscaped)) : NULL;
}

CFStringRef CFURLCopyFragment(
        CFURLRef url, CFStringRef charactersToLeaveEscaped) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyFragment,
        LC32_CF_HOST(url), LC32_CF_HOST(charactersToLeaveEscaped)) : NULL;
}

CFStringRef CFURLCopyLastPathComponent(CFURLRef url) {
    return url ? (CFStringRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCopyLastPathComponent,
        LC32_CF_HOST(url)) : NULL;
}

SInt32 CFURLGetPortNumber(CFURLRef url) {
    return url ? (SInt32)LC32_CF_CALL(
        LC32CoreFoundationOpURLGetPortNumber,
        LC32_CF_HOST(url)) : -1;
}

Boolean CFURLHasDirectoryPath(CFURLRef url) {
    return url && LC32_CF_CALL(
        LC32CoreFoundationOpURLHasDirectoryPath,
        LC32_CF_HOST(url));
}

CFURLRef CFURLCreateCopyAppendingPathComponent(
        CFAllocatorRef allocator, CFURLRef url,
        CFStringRef pathComponent, Boolean isDirectory) {
    (void)allocator;
    return url && pathComponent ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateCopyAppendingPathComponent,
        LC32_CF_HOST(url), LC32_CF_HOST(pathComponent),
        LC32_CF_U32(isDirectory)) : NULL;
}

CFURLRef CFURLCreateCopyDeletingLastPathComponent(
        CFAllocatorRef allocator, CFURLRef url) {
    (void)allocator;
    return url ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateCopyDeletingLastPathComponent,
        LC32_CF_HOST(url)) : NULL;
}

CFURLRef CFURLCreateCopyAppendingPathExtension(
        CFAllocatorRef allocator, CFURLRef url, CFStringRef extension) {
    (void)allocator;
    return url && extension ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateCopyAppendingPathExtension,
        LC32_CF_HOST(url), LC32_CF_HOST(extension)) : NULL;
}

CFURLRef CFURLCreateCopyDeletingPathExtension(
        CFAllocatorRef allocator, CFURLRef url) {
    (void)allocator;
    return url ? (CFURLRef)LC32_CF_CALL(
        LC32CoreFoundationOpURLCreateCopyDeletingPathExtension,
        LC32_CF_HOST(url)) : NULL;
}

Boolean CFURLGetFileSystemRepresentation(
        CFURLRef url, Boolean resolveAgainstBase,
        UInt8 *buffer, CFIndex maxBufferLength) {
    if(!url || maxBufferLength < 0 ||
       (maxBufferLength && !buffer)) return false;
    return LC32_CF_CALL(
        LC32CoreFoundationOpURLGetFileSystemRepresentation,
        LC32_CF_HOST(url), LC32_CF_U32(resolveAgainstBase),
        LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(maxBufferLength));
}

CFIndex CFURLGetBytes(CFURLRef url, UInt8 *buffer,
                      CFIndex bufferLength) {
    if(!url || bufferLength < 0) return -1;
    return (CFIndex)(int32_t)LC32_CF_CALL(
        LC32CoreFoundationOpURLGetBytes,
        LC32_CF_HOST(url), LC32_CF_U32((uintptr_t)buffer),
        LC32_CF_U32(bufferLength));
}

CFRange CFURLGetByteRangeForComponent(
        CFURLRef url, CFURLComponentType component,
        CFRange *rangeIncludingSeparators) {
    CFRange result = CFRangeMake(kCFNotFound, 0);
    if(!url) {
        if(rangeIncludingSeparators)
            *rangeIncludingSeparators = result;
        return result;
    }
    if(!LC32_CF_CALL(
            LC32CoreFoundationOpURLGetByteRangeForComponent,
            LC32_CF_HOST(url), LC32_CF_U32(component),
            LC32_CF_U32((uintptr_t)&result),
            LC32_CF_U32((uintptr_t)rangeIncludingSeparators))) {
        result = CFRangeMake(kCFNotFound, 0);
        if(rangeIncludingSeparators)
            *rangeIncludingSeparators = result;
    }
    return result;
}

Boolean CFURLSetResourcePropertyForKey(
        CFURLRef url, CFStringRef key, CFTypeRef propertyValue,
        CFErrorRef *error) {
    if(!url || !key) {
        if(error) *error = NULL;
        return false;
    }
    return LC32_CF_CALL(
        LC32CoreFoundationOpURLSetResourcePropertyForKey,
        LC32_CF_HOST(url), LC32_CF_HOST(key),
        LC32_CF_HOST(propertyValue), LC32_CF_U32((uintptr_t)error));
}

void CFRelease(CFTypeRef ref) {
    [(id)ref release];
}

CFTypeRef CFRetain(CFTypeRef ref) {
    return [(id)ref retain];
}

__attribute__((constructor)) void __CFInitialize() {
    // Since we cannot link against Foundation, we have to change superclass at runtime
    // Actually, internal CF does this aswel
    class_setSuperclass(objc_getClass("__NSCFString"), objc_getClass("NSMutableString"));
}
