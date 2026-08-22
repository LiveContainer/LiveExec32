#import <Foundation/Foundation+LC32.h>
#import <CoreFoundation/CoreFoundation.h>

#include <stdint.h>
#include <string.h>

@implementation NSString (LC32CString)

- (BOOL)getCString:(char *)buffer
          maxLength:(NSUInteger)maximumLength
           encoding:(NSStringEncoding)encoding {
    /*
     * The generated selector bridge cannot pass an ARM32 output pointer to
     * native Foundation.  CoreFoundation already stages the destination in
     * guest memory, including the terminating NUL required by this method.
     */
    if(!buffer || maximumLength == 0 || maximumLength > INT32_MAX)
        return NO;
    const CFStringEncoding cfEncoding =
        CFStringConvertNSStringEncodingToEncoding(encoding);
    if(cfEncoding == kCFStringEncodingInvalidId) return NO;
    return CFStringGetCString((CFStringRef)self, buffer,
                              (CFIndex)maximumLength, cfEncoding);
}

- (const char *)UTF8String {
    uint32_t required = LC32CopyHostStringUTF8(self.host_self, NULL, 0);
    if(!required) return NULL;
    char *bytes = LC32GetAssociatedGuestBuffer(self, required);
    if(!bytes) return NULL;
    return LC32CopyHostStringUTF8(self.host_self, bytes, required) == required
        ? bytes : NULL;
}

- (const char *)cStringUsingEncoding:(NSStringEncoding)encoding {
    uint32_t required = LC32CopyHostStringBytes(
        self.host_self, (uint32_t)encoding, NULL, 0);
    if(!required) return NULL;
    char *bytes = LC32GetAssociatedGuestBuffer(self, required);
    if(!bytes) return NULL;
    return LC32CopyHostStringBytes(
        self.host_self, (uint32_t)encoding, bytes, required) == required
        ? bytes : NULL;
}

- (const char *)fileSystemRepresentation {
    /* Darwin paths are UTF-8.  Keep the bytes in guest-owned associated
     * storage so POSIX calls can safely consume the returned pointer. */
    return self.UTF8String;
}

- (BOOL)getFileSystemRepresentation:(char *)buffer
                           maxLength:(NSUInteger)maximumLength {
    if(!buffer) return NO;
    const char *source = self.fileSystemRepresentation;
    if(!source) return NO;
    const size_t required = strlen(source) + 1;
    if(required > maximumLength) return NO;
    memcpy(buffer, source, required);
    return YES;
}

@end

@implementation NSFileManager (LC32PathRepresentation)

- (const char *)fileSystemRepresentationWithPath:(NSString *)path {
    return path.fileSystemRepresentation;
}

- (BOOL)getFileSystemRepresentation:(char *)buffer
                           maxLength:(NSUInteger)maximumLength
                            withPath:(NSString *)path {
    return [path getFileSystemRepresentation:buffer maxLength:maximumLength];
}

@end
