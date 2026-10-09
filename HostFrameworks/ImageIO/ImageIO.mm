@import ImageIO;
@import Foundation;

#include "bridge.h"
#include "../../GuestFrameworks/ImageIO/LC32ImageIOBridge.h"

#include <cstddef>
#include <cstdint>

namespace {

class NativeImageIOCallScope {
public:
    NativeImageIOCallScope()
        : active(Dynarmic_guest_host_call_quiescence_begin()) {}
    ~NativeImageIOCallScope() {
        if(active) Dynarmic_guest_host_call_quiescence_end();
    }
    NativeImageIOCallScope(const NativeImageIOCallScope &) = delete;
    NativeImageIOCallScope &operator=(const NativeImageIOCallScope &) = delete;

private:
    const bool active;
};

template<typename Function>
auto InvokeNativeImageIO(Function function) -> decltype(function()) {
    // Reading URLs and decoding/encoding can block. Do not retain a guest
    // execution lease across native work; guest callbacks reacquire it.
    NativeImageIOCallScope scope;
    return function();
}

bool ReadImageIOCall(u32 guestAddress, LC32ImageIOCall &call) {
    struct {
        uint32_t version;
        uint32_t slotCount;
    } header = {};
    if(!guestAddress ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
           reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32ImageIOABIVersion ||
       header.slotCount > LC32ImageIOMaxSlots) {
        return false;
    }
    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    const uint64_t address = static_cast<uint64_t>(guestAddress) +
        offsetof(LC32ImageIOCall, slots);
    if(address > UINT32_MAX ||
       address + byteCount > static_cast<uint64_t>(UINT32_MAX) + 1) {
        return false;
    }
    return !byteCount || Dynarmic_mem_1read(static_cast<u32>(address),
        byteCount, reinterpret_cast<char *>(call.slots)) == 0;
}

template<typename T>
T SlotHostObject(const LC32ImageIOCall &call, size_t index) {
    return reinterpret_cast<T>(static_cast<uintptr_t>(call.slots[index]));
}

u32 SlotU32(const LC32ImageIOCall &call, size_t index) {
    return static_cast<u32>(call.slots[index]);
}

u32 GuestForCreatedObject(CFTypeRef object) {
    return LC32GuestObjectForOwnedHostObject(object);
}

u32 GuestForBorrowedObject(CFTypeRef object) {
    return object ? [(__bridge id)object guest_self] : 0;
}

u32 GuestSize(size_t value) {
    // A host count cannot wrap into a different, valid-looking ARM32 count.
    return value > UINT32_MAX ? UINT32_MAX : static_cast<u32>(value);
}

u32 GuestStatus(CGImageSourceStatus status) {
    return static_cast<u32>(static_cast<int32_t>(status));
}

class GuestSourceOptions {
public:
    explicit GuestSourceOptions(CFDictionaryRef options)
        : dictionary(options ? CFDictionaryCreateMutableCopy(
              kCFAllocatorDefault, 0, options) : CFDictionaryCreateMutable(
              kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
              &kCFTypeDictionaryValueCallBacks)) {
        // ImageIO documents different 32-bit/64-bit cache defaults. Preserve
        // the ARM32 default without changing an explicit caller preference.
        if(dictionary && !CFDictionaryContainsKey(
                dictionary, kCGImageSourceShouldCache)) {
            CFDictionarySetValue(dictionary, kCGImageSourceShouldCache,
                kCFBooleanFalse);
        }
    }
    ~GuestSourceOptions() {
        if(dictionary) CFRelease(dictionary);
    }
    GuestSourceOptions(const GuestSourceOptions &) = delete;
    GuestSourceOptions &operator=(const GuestSourceOptions &) = delete;

    CFDictionaryRef get() const { return dictionary; }

private:
    CFMutableDictionaryRef dictionary;
};

} // namespace

#define LC32_IMAGEIO_NATIVE(expression) \
    InvokeNativeImageIO([&] { return (expression); })

extern "C" u32 LC32_ImageIO_Dispatch(u32 opcodeValue, u32 guestCall, u32) {
    LC32ImageIOCall call = {};
    if(!ReadImageIOCall(guestCall, call)) return 0;

    switch(static_cast<LC32ImageIOOpcode>(opcodeValue)) {
    case LC32ImageIOOpMetadataGetTypeID: {
        if(call.slotCount != 0) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataGetTypeID()));
    }
    case LC32ImageIOOpMetadataTagGetTypeID: {
        if(call.slotCount != 0) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataTagGetTypeID()));
    }
    case LC32ImageIOOpMetadataCreateMutable: {
        if(call.slotCount != 0) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCreateMutable()));
    }
    case LC32ImageIOOpMetadataCreateFromXMPData: {
        if(call.slotCount != 1) return 0;
        CFDataRef data = SlotHostObject<CFDataRef>(call, 0);
        if(!data) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCreateFromXMPData(data)));
    }
    case LC32ImageIOOpMetadataCreateMutableCopy: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 0);
        if(!metadata) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCreateMutableCopy(metadata)));
    }
    case LC32ImageIOOpMetadataCreateXMPData: {
        if(call.slotCount != 2) return 0;
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 0);
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 1);
        if(!metadata) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCreateXMPData(metadata, options)));
    }
    case LC32ImageIOOpMetadataCopyTags: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 0);
        if(!metadata) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCopyTags(metadata)));
    }
    case LC32ImageIOOpMetadataTagCopyName: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataTagRef tag = SlotHostObject<CGImageMetadataTagRef>(call, 0);
        if(!tag) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataTagCopyName(tag)));
    }
    case LC32ImageIOOpMetadataTagCopyNamespace: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataTagRef tag = SlotHostObject<CGImageMetadataTagRef>(call, 0);
        if(!tag) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataTagCopyNamespace(tag)));
    }
    case LC32ImageIOOpMetadataTagCopyPrefix: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataTagRef tag = SlotHostObject<CGImageMetadataTagRef>(call, 0);
        if(!tag) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataTagCopyPrefix(tag)));
    }
    case LC32ImageIOOpMetadataTagCopyQualifiers: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataTagRef tag = SlotHostObject<CGImageMetadataTagRef>(call, 0);
        if(!tag) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataTagCopyQualifiers(tag)));
    }
    case LC32ImageIOOpMetadataTagCopyValue: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataTagRef tag = SlotHostObject<CGImageMetadataTagRef>(call, 0);
        if(!tag) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataTagCopyValue(tag)));
    }
    case LC32ImageIOOpMetadataTagGetType: {
        if(call.slotCount != 1) return 0;
        CGImageMetadataTagRef tag = SlotHostObject<CGImageMetadataTagRef>(call, 0);
        if(!tag) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataTagGetType(tag)));
    }
    case LC32ImageIOOpMetadataTagCreate: {
        if(call.slotCount != 5) return 0;
        CFStringRef xmlns = SlotHostObject<CFStringRef>(call, 0);
        CFStringRef prefix = SlotHostObject<CFStringRef>(call, 1);
        CFStringRef name = SlotHostObject<CFStringRef>(call, 2);
        CGImageMetadataType type = static_cast<CGImageMetadataType>(SlotU32(call, 3));
        CFTypeRef value = SlotHostObject<CFTypeRef>(call, 4);
        if(!xmlns || !name || !value) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataTagCreate(xmlns, prefix, name, type, value)));
    }
    case LC32ImageIOOpMetadataCopyStringValueWithPath: {
        if(call.slotCount != 3) return 0;
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 0);
        CGImageMetadataTagRef parent = SlotHostObject<CGImageMetadataTagRef>(call, 1);
        CFStringRef path = SlotHostObject<CFStringRef>(call, 2);
        if(!metadata || !path) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCopyStringValueWithPath(metadata, parent, path)));
    }
    case LC32ImageIOOpMetadataCopyTagWithPath: {
        if(call.slotCount != 3) return 0;
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 0);
        CGImageMetadataTagRef parent = SlotHostObject<CGImageMetadataTagRef>(call, 1);
        CFStringRef path = SlotHostObject<CFStringRef>(call, 2);
        if(!metadata || !path) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCopyTagWithPath(metadata, parent, path)));
    }
    case LC32ImageIOOpMetadataCopyTagMatchingImageProperty: {
        if(call.slotCount != 3) return 0;
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 0);
        CFStringRef dictionary = SlotHostObject<CFStringRef>(call, 1);
        CFStringRef property = SlotHostObject<CFStringRef>(call, 2);
        if(!metadata || !dictionary || !property) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageMetadataCopyTagMatchingImageProperty(metadata, dictionary, property)));
    }
    case LC32ImageIOOpMetadataRemoveTagWithPath: {
        if(call.slotCount != 3) return 0;
        CGMutableImageMetadataRef metadata = SlotHostObject<CGMutableImageMetadataRef>(call, 0);
        CGImageMetadataTagRef parent = SlotHostObject<CGImageMetadataTagRef>(call, 1);
        CFStringRef path = SlotHostObject<CFStringRef>(call, 2);
        if(!metadata || !path) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataRemoveTagWithPath(metadata, parent, path)));
    }
    case LC32ImageIOOpMetadataSetTagWithPath: {
        if(call.slotCount != 4) return 0;
        CGMutableImageMetadataRef metadata = SlotHostObject<CGMutableImageMetadataRef>(call, 0);
        CGImageMetadataTagRef parent = SlotHostObject<CGImageMetadataTagRef>(call, 1);
        CFStringRef path = SlotHostObject<CFStringRef>(call, 2);
        CGImageMetadataTagRef value = SlotHostObject<CGImageMetadataTagRef>(call, 3);
        if(!metadata || !path || !value) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataSetTagWithPath(metadata, parent, path, value)));
    }
    case LC32ImageIOOpMetadataSetValueWithPath: {
        if(call.slotCount != 4) return 0;
        CGMutableImageMetadataRef metadata = SlotHostObject<CGMutableImageMetadataRef>(call, 0);
        CGImageMetadataTagRef parent = SlotHostObject<CGImageMetadataTagRef>(call, 1);
        CFStringRef path = SlotHostObject<CFStringRef>(call, 2);
        CFTypeRef value = SlotHostObject<CFTypeRef>(call, 3);
        if(!metadata || !path || !value) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataSetValueWithPath(metadata, parent, path, value)));
    }
    case LC32ImageIOOpMetadataSetValueMatchingImageProperty: {
        if(call.slotCount != 4) return 0;
        CGMutableImageMetadataRef metadata = SlotHostObject<CGMutableImageMetadataRef>(call, 0);
        CFStringRef dictionary = SlotHostObject<CFStringRef>(call, 1);
        CFStringRef property = SlotHostObject<CFStringRef>(call, 2);
        CFTypeRef value = SlotHostObject<CFTypeRef>(call, 3);
        if(!metadata || !dictionary || !property || !value) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, property, value)));
    }
    case LC32ImageIOOpSourceCopyMetadataAtIndex: {
        if(call.slotCount != 3) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        size_t index = static_cast<size_t>(SlotU32(call, 1));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 2);
        if(!source) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCopyMetadataAtIndex(source, index, options)));
    }
    case LC32ImageIOOpDestinationAddImageAndMetadata: {
        if(call.slotCount != 4) return 0;
        CGImageDestinationRef destination = SlotHostObject<CGImageDestinationRef>(call, 0);
        CGImageRef image = SlotHostObject<CGImageRef>(call, 1);
        CGImageMetadataRef metadata = SlotHostObject<CGImageMetadataRef>(call, 2);
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 3);
        if(!destination || !image) return 0;
        LC32_IMAGEIO_NATIVE(CGImageDestinationAddImageAndMetadata(destination, image, metadata, options));
        return 1;
    }
    case LC32ImageIOOpMetadataRegisterNamespaceForPrefix:
    case LC32ImageIOOpDestinationCopyImageSource: {
        if(call.slotCount != 4 || !call.slots[0] || !call.slots[1]) return 0;
        const u32 address = SlotU32(call, 3);
        u32 guestError = 0;
        if(address && (static_cast<uint64_t>(address) + sizeof(guestError) >
                static_cast<uint64_t>(UINT32_MAX) + 1 ||
            Dynarmic_mem_1write(address, sizeof(guestError),
                reinterpret_cast<char *>(&guestError)) != 0)) return 0;
        CFErrorRef error = nullptr;
        bool success;
        if(opcodeValue == LC32ImageIOOpMetadataRegisterNamespaceForPrefix) {
            if(!call.slots[2]) return 0;
            success = LC32_IMAGEIO_NATIVE(CGImageMetadataRegisterNamespaceForPrefix(
                SlotHostObject<CGMutableImageMetadataRef>(call, 0),
                SlotHostObject<CFStringRef>(call, 1),
                SlotHostObject<CFStringRef>(call, 2), address ? &error : nullptr));
        } else {
            success = LC32_IMAGEIO_NATIVE(CGImageDestinationCopyImageSource(
                SlotHostObject<CGImageDestinationRef>(call, 0),
                SlotHostObject<CGImageSourceRef>(call, 1),
                SlotHostObject<CFDictionaryRef>(call, 2), address ? &error : nullptr));
        }
        if(address) {
            guestError = GuestForCreatedObject(error);
            if(Dynarmic_mem_1write(address, sizeof(guestError),
                    reinterpret_cast<char *>(&guestError)) != 0) return 0;
        }
        return success;
    }
    case LC32ImageIOOpSourceGetTypeID: {
        if(call.slotCount != 0) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageSourceGetTypeID()));
    }
    case LC32ImageIOOpSourceCopyTypeIdentifiers: {
        if(call.slotCount != 0) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(
            CGImageSourceCopyTypeIdentifiers()));
    }
    case LC32ImageIOOpSourceCreateWithDataProvider: {
        if(call.slotCount != 2) return 0;
        CGDataProviderRef provider = SlotHostObject<CGDataProviderRef>(call, 0);
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 1);
        if(!provider) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCreateWithDataProvider(
            provider, guestOptions.get())));
    }
    case LC32ImageIOOpSourceCreateWithData: {
        if(call.slotCount != 2) return 0;
        CFDataRef data = SlotHostObject<CFDataRef>(call, 0);
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 1);
        if(!data) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCreateWithData(
            data, guestOptions.get())));
    }
    case LC32ImageIOOpSourceCreateWithURL: {
        if(call.slotCount != 2) return 0;
        CFURLRef url = SlotHostObject<CFURLRef>(call, 0);
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 1);
        if(!url) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCreateWithURL(
            url, guestOptions.get())));
    }
    case LC32ImageIOOpSourceGetType: {
        if(call.slotCount != 1) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        if(!source) return 0;
        return GuestForBorrowedObject(LC32_IMAGEIO_NATIVE(CGImageSourceGetType(
            source)));
    }
    case LC32ImageIOOpSourceGetCount: {
        if(call.slotCount != 1) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        if(!source) return 0;
        return GuestSize(LC32_IMAGEIO_NATIVE(CGImageSourceGetCount(
            source)));
    }
    case LC32ImageIOOpSourceCopyProperties: {
        if(call.slotCount != 2) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 1);
        if(!source) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCopyProperties(
            source, guestOptions.get())));
    }
    case LC32ImageIOOpSourceCopyPropertiesAtIndex: {
        if(call.slotCount != 3) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        size_t index = static_cast<size_t>(SlotU32(call, 1));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 2);
        if(!source) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCopyPropertiesAtIndex(
            source, index, guestOptions.get())));
    }
    case LC32ImageIOOpSourceCreateImageAtIndex: {
        if(call.slotCount != 3) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        size_t index = static_cast<size_t>(SlotU32(call, 1));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 2);
        if(!source) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCreateImageAtIndex(
            source, index, guestOptions.get())));
    }
    case LC32ImageIOOpSourceRemoveCacheAtIndex: {
        if(call.slotCount != 2) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        size_t index = static_cast<size_t>(SlotU32(call, 1));
        if(!source) return 0;
        LC32_IMAGEIO_NATIVE(CGImageSourceRemoveCacheAtIndex(
            source, index));
        return 0;
    }
    case LC32ImageIOOpSourceCreateThumbnailAtIndex: {
        if(call.slotCount != 3) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        size_t index = static_cast<size_t>(SlotU32(call, 1));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 2);
        if(!source) return 0;
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCreateThumbnailAtIndex(
            source, index, guestOptions.get())));
    }
    case LC32ImageIOOpSourceCreateIncremental: {
        if(call.slotCount != 1) return 0;
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 0);
        GuestSourceOptions guestOptions(options);
        if(!guestOptions.get()) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageSourceCreateIncremental(
            guestOptions.get())));
    }
    case LC32ImageIOOpSourceUpdateData: {
        if(call.slotCount != 3) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        CFDataRef data = SlotHostObject<CFDataRef>(call, 1);
        bool final = static_cast<bool>(SlotU32(call, 2));
        if(!source || !data) return 0;
        LC32_IMAGEIO_NATIVE(CGImageSourceUpdateData(
            source, data, final));
        return 0;
    }
    case LC32ImageIOOpSourceUpdateDataProvider: {
        if(call.slotCount != 3) return 0;
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        CGDataProviderRef provider = SlotHostObject<CGDataProviderRef>(call, 1);
        bool final = static_cast<bool>(SlotU32(call, 2));
        if(!source || !provider) return 0;
        LC32_IMAGEIO_NATIVE(CGImageSourceUpdateDataProvider(
            source, provider, final));
        return 0;
    }
    case LC32ImageIOOpSourceGetStatus: {
        if(call.slotCount != 1) return GuestStatus(kCGImageStatusInvalidData);
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        if(!source) return GuestStatus(kCGImageStatusInvalidData);
        return GuestStatus(LC32_IMAGEIO_NATIVE(CGImageSourceGetStatus(
            source)));
    }
    case LC32ImageIOOpSourceGetStatusAtIndex: {
        if(call.slotCount != 2) return GuestStatus(kCGImageStatusInvalidData);
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 0);
        size_t index = static_cast<size_t>(SlotU32(call, 1));
        if(!source) return GuestStatus(kCGImageStatusInvalidData);
        return GuestStatus(LC32_IMAGEIO_NATIVE(CGImageSourceGetStatusAtIndex(
            source, index)));
    }
    case LC32ImageIOOpDestinationGetTypeID: {
        if(call.slotCount != 0) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageDestinationGetTypeID()));
    }
    case LC32ImageIOOpDestinationCopyTypeIdentifiers: {
        if(call.slotCount != 0) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(
            CGImageDestinationCopyTypeIdentifiers()));
    }
    case LC32ImageIOOpDestinationCreateWithDataConsumer: {
        if(call.slotCount != 4) return 0;
        CGDataConsumerRef consumer = SlotHostObject<CGDataConsumerRef>(call, 0);
        CFStringRef type = SlotHostObject<CFStringRef>(call, 1);
        size_t count = static_cast<size_t>(SlotU32(call, 2));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 3);
        if(!consumer || !type) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageDestinationCreateWithDataConsumer(
            consumer, type, count, options)));
    }
    case LC32ImageIOOpDestinationCreateWithData: {
        if(call.slotCount != 4) return 0;
        CFMutableDataRef data = SlotHostObject<CFMutableDataRef>(call, 0);
        CFStringRef type = SlotHostObject<CFStringRef>(call, 1);
        size_t count = static_cast<size_t>(SlotU32(call, 2));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 3);
        if(!data || !type) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageDestinationCreateWithData(
            data, type, count, options)));
    }
    case LC32ImageIOOpDestinationCreateWithURL: {
        if(call.slotCount != 4) return 0;
        CFURLRef url = SlotHostObject<CFURLRef>(call, 0);
        CFStringRef type = SlotHostObject<CFStringRef>(call, 1);
        size_t count = static_cast<size_t>(SlotU32(call, 2));
        CFDictionaryRef options = SlotHostObject<CFDictionaryRef>(call, 3);
        if(!url || !type) return 0;
        return GuestForCreatedObject(LC32_IMAGEIO_NATIVE(CGImageDestinationCreateWithURL(
            url, type, count, options)));
    }
    case LC32ImageIOOpDestinationSetProperties: {
        if(call.slotCount != 2) return 0;
        CGImageDestinationRef destination = SlotHostObject<CGImageDestinationRef>(call, 0);
        CFDictionaryRef properties = SlotHostObject<CFDictionaryRef>(call, 1);
        if(!destination) return 0;
        LC32_IMAGEIO_NATIVE(CGImageDestinationSetProperties(
            destination, properties));
        return 0;
    }
    case LC32ImageIOOpDestinationAddImage: {
        if(call.slotCount != 3) return 0;
        CGImageDestinationRef destination = SlotHostObject<CGImageDestinationRef>(call, 0);
        CGImageRef image = SlotHostObject<CGImageRef>(call, 1);
        CFDictionaryRef properties = SlotHostObject<CFDictionaryRef>(call, 2);
        if(!destination || !image) return 0;
        LC32_IMAGEIO_NATIVE(CGImageDestinationAddImage(
            destination, image, properties));
        return 0;
    }
    case LC32ImageIOOpDestinationAddImageFromSource: {
        if(call.slotCount != 4) return 0;
        CGImageDestinationRef destination = SlotHostObject<CGImageDestinationRef>(call, 0);
        CGImageSourceRef source = SlotHostObject<CGImageSourceRef>(call, 1);
        size_t index = static_cast<size_t>(SlotU32(call, 2));
        CFDictionaryRef properties = SlotHostObject<CFDictionaryRef>(call, 3);
        if(!destination || !source) return 0;
        LC32_IMAGEIO_NATIVE(CGImageDestinationAddImageFromSource(
            destination, source, index, properties));
        return 0;
    }
    case LC32ImageIOOpDestinationFinalize: {
        if(call.slotCount != 1) return 0;
        CGImageDestinationRef destination = SlotHostObject<CGImageDestinationRef>(call, 0);
        if(!destination) return 0;
        return static_cast<u32>(LC32_IMAGEIO_NATIVE(CGImageDestinationFinalize(
            destination)));
    }
    }
    return 0;
}

#undef LC32_IMAGEIO_NATIVE
