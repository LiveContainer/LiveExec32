#ifndef LC32_CORE_GRAPHICS_BRIDGE_H
#define LC32_CORE_GRAPHICS_BRIDGE_H

#include <stdint.h>

enum {
    LC32CoreGraphicsABIVersion = 1,
    LC32CoreGraphicsMaxSlots = 12,
    LC32CoreGraphicsMaximumFilenameBytes = 64 * 1024,
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
    LC32CoreGraphicsOpColorGetColorSpace = 11,
    LC32CoreGraphicsOpColorGetNumberOfComponents = 12,
    LC32CoreGraphicsOpColorCopyComponents = 13,
    LC32CoreGraphicsOpColorSpaceGetModel = 14,
    LC32CoreGraphicsOpDataProviderCreateWithFilename = 15,
    LC32CoreGraphicsOpImageCreateWithJPEGDataProvider = 16,
    LC32CoreGraphicsOpImageCreateWithPNGDataProvider = 17,
    LC32CoreGraphicsOpPathCreateMutable = 18,
    LC32CoreGraphicsOpPathAddLineToPoint = 19,
    LC32CoreGraphicsOpPathContainsPoint = 20,
    LC32CoreGraphicsOpPathMoveToPoint = 21,
    LC32CoreGraphicsOpPathCloseSubpath = 22,
    LC32CoreGraphicsOpPathRelease = 23,
} LC32CoreGraphicsOpcode;

#endif
