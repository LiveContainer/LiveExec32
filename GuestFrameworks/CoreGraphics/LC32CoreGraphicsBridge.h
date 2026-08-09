#ifndef LC32_CORE_GRAPHICS_BRIDGE_H
#define LC32_CORE_GRAPHICS_BRIDGE_H

#include <stdint.h>

enum {
    LC32CoreGraphicsABIVersion = 1,
    LC32CoreGraphicsMaxSlots = 8,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32CoreGraphicsMaxSlots];
} LC32CoreGraphicsCall;

typedef enum : uint32_t {
    LC32CoreGraphicsOpBitmapContextCreate = 1,
    LC32CoreGraphicsOpColorSpaceCreateDeviceRGB = 2,
    LC32CoreGraphicsOpColorSpaceRelease = 3,
    LC32CoreGraphicsOpContextClearRect = 4,
    LC32CoreGraphicsOpContextDrawImage = 5,
    LC32CoreGraphicsOpContextRelease = 6,
    LC32CoreGraphicsOpContextTranslateCTM = 7,
    LC32CoreGraphicsOpImageGetHeight = 8,
    LC32CoreGraphicsOpImageGetWidth = 9,
    LC32CoreGraphicsOpImageRelease = 10,
} LC32CoreGraphicsOpcode;

#endif
