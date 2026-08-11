#import <Foundation/Foundation.h>
#import <LC32/LC32.h>

#import "LC32CoreFoundationBridge.h"

@interface __NSCFType : NSObject
@end
@interface __NSCFString : NSObject // NSString
@end
@interface __NSCFConstantString : __NSCFString
@end

extern int __CFConstantStringClassReference[];

uint32_t LC32CoreFoundationDispatch(LC32CoreFoundationOpcode opcode,
                                    const uint64_t *slots,
                                    uint32_t slotCount);

static inline uint64_t LC32CoreFoundationHostObject(const void *object) {
    return object ? [(id)object host_self] : 0;
}

#define LC32_CF_CALL0(opcode) \
    LC32CoreFoundationDispatch((opcode), NULL, 0)
#define LC32_CF_CALL(opcode, ...) \
    LC32CoreFoundationDispatch((opcode), \
        (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / \
                   sizeof(uint64_t)))
#define LC32_CF_U32(value) ((uint64_t)(uint32_t)(value))
#define LC32_CF_HOST(value) \
    LC32CoreFoundationHostObject((const void *)(value))
