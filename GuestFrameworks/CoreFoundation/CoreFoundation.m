#import <LC32/LC32.h>
#import <CoreFoundation/CoreFoundation+LC32.h>

const CFAllocatorRef kCFAllocatorDefault = NULL;

// Set CF version to iOS 10.3.3
double kCFCoreFoundationVersionNumber = (double)1349.7;

@implementation __NSCFType
@end

@implementation __NSCFString
@end
@implementation __NSCFConstantString
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
    return (CFURLRef)[NSURL fileURLWithPath:(NSString *)filePath isDirectory:isDirectory];
}

void CFRelease(CFTypeRef ref) {
    [(id)ref release];
}

__attribute__((constructor)) void __CFInitialize() {
    // Since we cannot link against Foundation, we have to change superclass at runtime
    // Actually, internal CF does this aswel
    class_setSuperclass(objc_getClass("__NSCFString"), objc_getClass("NSMutableString"));
}
