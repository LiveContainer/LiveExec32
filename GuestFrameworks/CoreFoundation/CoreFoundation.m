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
    // unused: allocator, pathStyle
    return (CFURLRef)[[NSURL alloc]
        initFileURLWithPath:(NSString *)filePath isDirectory:isDirectory];
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
