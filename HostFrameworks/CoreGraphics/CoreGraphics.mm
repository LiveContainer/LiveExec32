@import Darwin;
@import CoreGraphics;
#include "bridge.h"
#include "../../GuestFrameworks/CoreGraphics/LC32CoreGraphicsBridge.h"

#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

constexpr size_t kMaximumBitmapBytes = 256u * 1024u * 1024u;
constexpr size_t kMaximumColorComponents = 1024;

struct BitmapBacking {
    CGContextRef context = nullptr;
    u32 guestData = 0;
    size_t byteCount = 0;
    std::unique_ptr<uint8_t[]> bytes;
};

std::mutex bitmapBackingsMutex;
std::unordered_map<CGContextRef, BitmapBacking *> bitmapBackings;

bool ReadCoreGraphicsCall(u32 guestAddress, LC32CoreGraphicsCall &call) {
    struct {
        uint32_t version;
        uint32_t slotCount;
    } header = {};
    if(!guestAddress ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
           reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32CoreGraphicsABIVersion ||
       header.slotCount > LC32CoreGraphicsMaxSlots) {
        return false;
    }

    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    const uint64_t slotsAddress = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32CoreGraphicsCall, slots);
    if(slotsAddress > UINT32_MAX ||
       slotsAddress + byteCount > static_cast<uint64_t>(UINT32_MAX) + 1)
        return false;
    if(byteCount && Dynarmic_mem_1read(
            static_cast<u32>(slotsAddress),
            byteCount, reinterpret_cast<char *>(call.slots)) != 0) {
        return false;
    }
    return true;
}

bool RequireCoreGraphicsSlots(const LC32CoreGraphicsCall &call,
                              uint32_t count) {
    return call.slotCount == count;
}

u32 SlotU32(const LC32CoreGraphicsCall &call, size_t index) {
    return static_cast<u32>(call.slots[index]);
}

template<typename T>
T SlotHostObject(const LC32CoreGraphicsCall &call, size_t index) {
    return reinterpret_cast<T>(
        static_cast<uintptr_t>(call.slots[index]));
}

CGFloat SlotCGFloat(const LC32CoreGraphicsCall &call, size_t index) {
    const uint32_t bits = SlotU32(call, index);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return static_cast<CGFloat>(value);
}

CGRect SlotRect(const LC32CoreGraphicsCall &call, size_t first) {
    return CGRectMake(SlotCGFloat(call, first),
        SlotCGFloat(call, first + 1), SlotCGFloat(call, first + 2),
        SlotCGFloat(call, first + 3));
}

bool SlotOptionalTransform(const LC32CoreGraphicsCall &call,
                           size_t presenceIndex, size_t first,
                           CGAffineTransform &storage,
                           const CGAffineTransform *&transform) {
    const u32 present = SlotU32(call, presenceIndex);
    if(!present) {
        transform = nullptr;
        return true;
    }
    if(present != 1) return false;
    storage = CGAffineTransformMake(
        SlotCGFloat(call, first), SlotCGFloat(call, first + 1),
        SlotCGFloat(call, first + 2), SlotCGFloat(call, first + 3),
        SlotCGFloat(call, first + 4), SlotCGFloat(call, first + 5));
    transform = &storage;
    return true;
}

BitmapBacking *FindBitmapBacking(CGContextRef context) {
    std::lock_guard<std::mutex> lock(bitmapBackingsMutex);
    const auto iterator = bitmapBackings.find(context);
    return iterator == bitmapBackings.end() ? nullptr : iterator->second;
}

void SyncBitmapBacking(CGContextRef context,
                       BitmapBacking *backing) {
    if(!backing || !backing->guestData || !backing->byteCount) return;
    CGContextFlush(context);
    void *data = CGBitmapContextGetData(context);
    if(data) {
        (void)Dynarmic_mem_1write(backing->guestData, backing->byteCount,
            static_cast<char *>(data));
    }
}

void ReleaseBitmapBacking(void *releaseInfo, void *data) {
    auto *backing = static_cast<BitmapBacking *>(releaseInfo);
    if(!backing) return;
    if(backing->guestData && backing->byteCount && data) {
        (void)Dynarmic_mem_1write(backing->guestData, backing->byteCount,
            static_cast<char *>(data));
    }
    if(backing->context) {
        std::lock_guard<std::mutex> lock(bitmapBackingsMutex);
        const auto iterator = bitmapBackings.find(backing->context);
        if(iterator != bitmapBackings.end() && iterator->second == backing)
            bitmapBackings.erase(iterator);
    }
    delete backing;
}

} // namespace

__BEGIN_DECLS

u32 LC32_CoreGraphics_Dispatch(u32 opcode, u32 guestCall, u32) {
    LC32CoreGraphicsCall call;
    if(!ReadCoreGraphicsCall(guestCall, call)) return 0;

    switch(static_cast<LC32CoreGraphicsOpcode>(opcode)) {
        case LC32CoreGraphicsOpBitmapContextCreate: {
            if(!RequireCoreGraphicsSlots(call, 7)) return 0;
            const size_t width = SlotU32(call, 1);
            const size_t height = SlotU32(call, 2);
            const size_t bytesPerRow = SlotU32(call, 4);
            if(height && bytesPerRow > kMaximumBitmapBytes / height)
                return 0;
            const size_t byteCount = bytesPerRow * height;
            if(byteCount > kMaximumBitmapBytes) return 0;
            const u32 guestData = SlotU32(call, 0);
            if(guestData && static_cast<uint64_t>(guestData) + byteCount >
                    static_cast<uint64_t>(UINT32_MAX) + 1)
                return 0;

            BitmapBacking *backing = nullptr;
            void *hostData = nullptr;
            if(guestData) {
                backing = new BitmapBacking();
                backing->guestData = guestData;
                backing->byteCount = byteCount;
                if(byteCount) {
                    backing->bytes = std::make_unique<uint8_t[]>(byteCount);
                    if(Dynarmic_mem_1read(backing->guestData, byteCount,
                            reinterpret_cast<char *>(backing->bytes.get())) != 0)
                        {
                            delete backing;
                            return 0;
                        }
                    hostData = backing->bytes.get();
                }
            }

            CGColorSpaceRef colorSpace =
                SlotHostObject<CGColorSpaceRef>(call, 5);
            CGContextRef context = backing
                ? CGBitmapContextCreateWithData(hostData, width, height,
                    SlotU32(call, 3), bytesPerRow, colorSpace,
                    SlotU32(call, 6), ReleaseBitmapBacking, backing)
                : CGBitmapContextCreate(nullptr, width, height,
                    SlotU32(call, 3), bytesPerRow, colorSpace,
                    SlotU32(call, 6));
            if(!context) {
                delete backing;
                return 0;
            }
            if(backing) {
                backing->context = context;
                std::lock_guard<std::mutex> lock(bitmapBackingsMutex);
                bitmapBackings.emplace(context, backing);
            }
            return LC32GuestObjectForOwnedHostObject(context);
        }
        case LC32CoreGraphicsOpColorSpaceCreateDeviceRGB: {
            if(!RequireCoreGraphicsSlots(call, 0)) return 0;
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            if(!colorSpace) return 0;
            return LC32GuestObjectForOwnedHostObject(colorSpace);
        }
        case LC32CoreGraphicsOpColorSpaceRelease: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            return 0;
        }
        case LC32CoreGraphicsOpContextClearRect: {
            if(!RequireCoreGraphicsSlots(call, 5)) return 0;
            CGContextRef context = SlotHostObject<CGContextRef>(call, 0);
            if(!context) return 0;
            CGContextClearRect(context, SlotRect(call, 1));
            SyncBitmapBacking(context, FindBitmapBacking(context));
            return 0;
        }
        case LC32CoreGraphicsOpContextDrawImage: {
            if(!RequireCoreGraphicsSlots(call, 6)) return 0;
            CGContextRef context = SlotHostObject<CGContextRef>(call, 0);
            CGImageRef image = SlotHostObject<CGImageRef>(call, 5);
            if(!context || !image) return 0;
            CGContextDrawImage(context, SlotRect(call, 1), image);
            SyncBitmapBacking(context, FindBitmapBacking(context));
            return 0;
        }
        case LC32CoreGraphicsOpContextRelease: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGContextRef context = SlotHostObject<CGContextRef>(call, 0);
            if(!context) return 0;
            SyncBitmapBacking(context, FindBitmapBacking(context));
            return 0;
        }
        case LC32CoreGraphicsOpContextTranslateCTM: {
            if(!RequireCoreGraphicsSlots(call, 3)) return 0;
            CGContextRef context = SlotHostObject<CGContextRef>(call, 0);
            if(context) CGContextTranslateCTM(context,
                SlotCGFloat(call, 1), SlotCGFloat(call, 2));
            return 0;
        }
        case LC32CoreGraphicsOpImageGetHeight: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGImageRef image = SlotHostObject<CGImageRef>(call, 0);
            return image ? static_cast<u32>(CGImageGetHeight(image)) : 0;
        }
        case LC32CoreGraphicsOpImageGetWidth: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGImageRef image = SlotHostObject<CGImageRef>(call, 0);
            return image ? static_cast<u32>(CGImageGetWidth(image)) : 0;
        }
        case LC32CoreGraphicsOpImageRelease: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            return 0;
        }
        case LC32CoreGraphicsOpColorGetColorSpace: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGColorRef color = SlotHostObject<CGColorRef>(call, 0);
            CGColorSpaceRef space = color
                ? CGColorGetColorSpace(color) : nullptr;
            return space ? [(id)space guest_self] : 0;
        }
        case LC32CoreGraphicsOpColorGetNumberOfComponents: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGColorRef color = SlotHostObject<CGColorRef>(call, 0);
            if(!color) return 0;
            const size_t count = CGColorGetNumberOfComponents(color);
            return count <= kMaximumColorComponents
                ? static_cast<u32>(count) : 0;
        }
        case LC32CoreGraphicsOpColorCopyComponents: {
            if(!RequireCoreGraphicsSlots(call, 3)) return 0;
            CGColorRef color = SlotHostObject<CGColorRef>(call, 0);
            const u32 guestComponents = SlotU32(call, 1);
            const size_t capacity = SlotU32(call, 2);
            if(!color || !guestComponents ||
               capacity > kMaximumColorComponents) return 0;

            const size_t count = CGColorGetNumberOfComponents(color);
            const CGFloat *components = CGColorGetComponents(color);
            if(!components || count == 0 || count > capacity ||
               count > kMaximumColorComponents ||
               static_cast<uint64_t>(guestComponents) +
                   count * sizeof(float) >
                       static_cast<uint64_t>(UINT32_MAX) + 1) {
                return 0;
            }
            std::vector<float> guestValues(count);
            for(size_t index = 0; index < count; ++index)
                guestValues[index] = static_cast<float>(components[index]);
            return Dynarmic_mem_1write(guestComponents,
                guestValues.size() * sizeof(guestValues[0]),
                reinterpret_cast<char *>(guestValues.data())) == 0;
        }
        case LC32CoreGraphicsOpColorSpaceGetModel: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGColorSpaceRef space =
                SlotHostObject<CGColorSpaceRef>(call, 0);
            return static_cast<u32>(space
                ? CGColorSpaceGetModel(space)
                : kCGColorSpaceModelUnknown);
        }
        case LC32CoreGraphicsOpDataProviderCreateWithFilename: {
            if(!RequireCoreGraphicsSlots(call, 2)) return 0;
            const u32 guestFilename = SlotU32(call, 0);
            const size_t length = SlotU32(call, 1);
            if(!guestFilename ||
               length > LC32CoreGraphicsMaximumFilenameBytes ||
               static_cast<uint64_t>(guestFilename) + length + 1 >
                   static_cast<uint64_t>(UINT32_MAX) + 1) {
                return 0;
            }

            std::vector<char> filename(length + 1);
            if(Dynarmic_mem_1read(guestFilename, filename.size(),
                    filename.data()) != 0 || filename[length] != '\0' ||
               memchr(filename.data(), '\0', length) != nullptr) {
                return 0;
            }

            CGDataProviderRef provider =
                CGDataProviderCreateWithFilename(filename.data());
            if(!provider) return 0;
            return LC32GuestObjectForOwnedHostObject(provider);
        }
        case LC32CoreGraphicsOpImageCreateWithJPEGDataProvider:
        case LC32CoreGraphicsOpImageCreateWithPNGDataProvider: {
            if(!RequireCoreGraphicsSlots(call, 4)) return 0;
            CGDataProviderRef provider =
                SlotHostObject<CGDataProviderRef>(call, 0);
            /* A CGFloat decode array has no length in this API.  Never pass
             * the guest address to CoreGraphics; reject it until the required
             * component count can be established safely. */
            if(!provider || SlotU32(call, 1) != 0) return 0;

            const bool shouldInterpolate = SlotU32(call, 2) != 0;
            const auto intent = static_cast<CGColorRenderingIntent>(
                SlotU32(call, 3));
            CGImageRef image =
                static_cast<LC32CoreGraphicsOpcode>(opcode) ==
                        LC32CoreGraphicsOpImageCreateWithJPEGDataProvider
                    ? CGImageCreateWithJPEGDataProvider(provider, nullptr,
                        shouldInterpolate, intent)
                    : CGImageCreateWithPNGDataProvider(provider, nullptr,
                        shouldInterpolate, intent);
            if(!image) return 0;
            return LC32GuestObjectForOwnedHostObject(image);
        }
        case LC32CoreGraphicsOpPathCreateMutable: {
            if(!RequireCoreGraphicsSlots(call, 0)) return 0;
            CGMutablePathRef path = CGPathCreateMutable();
            if(!path) return 0;
            /* CGPathCreateMutable returns +1. Keep that ownership paired with
             * the +1 guest proxy returned by -guest_self. */
            return LC32GuestObjectForOwnedHostObject(path);
        }
        case LC32CoreGraphicsOpPathAddLineToPoint:
        case LC32CoreGraphicsOpPathMoveToPoint: {
            if(!RequireCoreGraphicsSlots(call, 10)) return 0;
            CGMutablePathRef path =
                SlotHostObject<CGMutablePathRef>(call, 0);
            if(!path) return 0;
            CGAffineTransform transformStorage;
            const CGAffineTransform *transform;
            if(!SlotOptionalTransform(call, 1, 2, transformStorage,
                    transform)) return 0;
            if(static_cast<LC32CoreGraphicsOpcode>(opcode) ==
                    LC32CoreGraphicsOpPathAddLineToPoint) {
                CGPathAddLineToPoint(path, transform,
                    SlotCGFloat(call, 8), SlotCGFloat(call, 9));
            } else {
                CGPathMoveToPoint(path, transform,
                    SlotCGFloat(call, 8), SlotCGFloat(call, 9));
            }
            return 1;
        }
        case LC32CoreGraphicsOpPathContainsPoint: {
            if(!RequireCoreGraphicsSlots(call, 11)) return 0;
            CGPathRef path = SlotHostObject<CGPathRef>(call, 0);
            if(!path) return 0;
            CGAffineTransform transformStorage;
            const CGAffineTransform *transform;
            if(!SlotOptionalTransform(call, 1, 2, transformStorage,
                    transform)) return 0;
            const CGPoint point = CGPointMake(
                SlotCGFloat(call, 8), SlotCGFloat(call, 9));
            return CGPathContainsPoint(path, transform, point,
                SlotU32(call, 10) != 0);
        }
        case LC32CoreGraphicsOpPathCloseSubpath: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            CGMutablePathRef path =
                SlotHostObject<CGMutablePathRef>(call, 0);
            if(!path) return 0;
            CGPathCloseSubpath(path);
            return 1;
        }
        case LC32CoreGraphicsOpPathRelease: {
            if(!RequireCoreGraphicsSlots(call, 1)) return 0;
            /* Guest CFRelease performs the paired proxy/native decrement.
             * This opcode deliberately validates without releasing again. */
            return SlotHostObject<CGPathRef>(call, 0) != nullptr;
        }
    }
    return 0;
}

__END_DECLS
