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
            const u32 guestContext = [(id)context guest_self];
            if(!guestContext) CGContextRelease(context);
            return guestContext;
        }
        case LC32CoreGraphicsOpColorSpaceCreateDeviceRGB: {
            if(!RequireCoreGraphicsSlots(call, 0)) return 0;
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            if(!colorSpace) return 0;
            const u32 guestColorSpace = [(id)colorSpace guest_self];
            if(!guestColorSpace) CGColorSpaceRelease(colorSpace);
            return guestColorSpace;
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
    }
    return 0;
}

u32 LC32_CoreGraphics_CGPathCreateMutable() {
    return [(id)CGPathCreateMutable() guest_self];
}

void LC32_CoreGraphics_CGPathAddLineToPoint(u32 r2, u32 r3, u32 sp) {
    CGMutablePathRef path = (CGMutablePathRef)(r2 | (u64)r3 << 32);

    // TODO: improve DynarmicHostString to handle direct access of such type
    u32 guest_m = (u32)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    CGAffineTransform m;
    Dynarmic_mem_1read(guest_m, sizeof(m), (char *)&m);

    CGFloat x = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGFloat y = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGPathAddLineToPoint(path, (const CGAffineTransform *)&m, x, y);
}

bool LC32_CoreGraphics_CGPathContainsPoint(u32 r2, u32 r3, u32 sp) {
    CGMutablePathRef path = (CGMutablePathRef)(r2 | (u64)r3 << 32);

    // TODO: improve DynarmicHostString to handle direct access of such type
    u32 guest_m = (u32)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    CGAffineTransform m;
    Dynarmic_mem_1read(guest_m, sizeof(m), (char *)&m);

    CGPoint point;
    Dynarmic_mem_1read(sp += 8, sizeof(m), (char *)&m);

    bool eoFill = (bool)Dynarmic_current_user_callbacks()->MemoryRead64(sp += sizeof(point));
    return CGPathContainsPoint(path, (const CGAffineTransform *)&m, point, eoFill);
}

void LC32_CoreGraphics_CGPathMoveToPoint(u32 r2, u32 r3, u32 sp) {
    CGMutablePathRef path = (CGMutablePathRef)(r2 | (u64)r3 << 32);

    // TODO: improve DynarmicHostString to handle direct access of such type
    u32 guest_m = (u32)Dynarmic_current_user_callbacks()->MemoryRead64(sp);
    CGAffineTransform m;
    Dynarmic_mem_1read(guest_m, sizeof(m), (char *)&m);

    CGFloat x = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGFloat y = (CGFloat)Dynarmic_current_user_callbacks()->MemoryRead64(sp += 8);
    CGPathMoveToPoint(path, (const CGAffineTransform *)&m, x, y);
}

__END_DECLS
