#import <Foundation/Foundation+LC32.h>

#include <stdint.h>

@implementation NSString (LC32CString)

- (const char *)UTF8String {
    uint32_t required = LC32CopyHostStringUTF8(self.host_self, NULL, 0);
    if(!required) return NULL;
    char *bytes = LC32GetAssociatedGuestBuffer(self, required);
    if(!bytes) return NULL;
    return LC32CopyHostStringUTF8(self.host_self, bytes, required) == required
        ? bytes : NULL;
}

@end
