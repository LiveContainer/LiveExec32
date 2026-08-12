#import <Foundation/Foundation+LC32.h>

#include <stdint.h>
#include <string.h>

@implementation NSString (LC32CString)

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
