#import <ImageIO/ImageIO.h>
#import <LC32/LC32.h>
#import <objc/runtime.h>

#import "LC32ImageIOBridge.h"

#include <pthread.h>
#include <string.h>

static pthread_once_t LC32ImageIODispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32ImageIODispatcherAddress;

static void LC32ImageIOResolveDispatcher(void) {
    LC32ImageIODispatcherAddress = LC32Dlsym("LC32_ImageIO_Dispatch", YES);
}

static uint32_t LC32ImageIODispatch(LC32ImageIOOpcode opcode,
                                   const uint64_t *slots,
                                   uint32_t slotCount) {
    if(slotCount > LC32ImageIOMaxSlots) return 0;
    pthread_once(&LC32ImageIODispatcherOnce, LC32ImageIOResolveDispatcher);
    if(!LC32ImageIODispatcherAddress) return 0;
    LC32ImageIOCall call = {
        .version = LC32ImageIOABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));
    return LC32InvokeHostCRet32(LC32ImageIODispatcherAddress,
        (uint32_t)opcode, (uint32_t)(uintptr_t)&call);
}

static uint64_t LC32ImageIOHostObject(const void *object) {
    return object ? [(id)object host_self] : 0;
}

extern void LC32InvalidateDataGuestBuffer(NSData *data);
static const void *kLC32ImageIODestinationData = &kLC32ImageIODestinationData;

static void LC32ImageIOInvalidateDestinationData(CGImageDestinationRef destination) {
    // The native encoder mutates NSMutableData without calling a guest
    // mutator. Invalidate even after failed operations, which may emit bytes.
    NSData *data = objc_getAssociatedObject((id)destination,
        kLC32ImageIODestinationData);
    LC32InvalidateDataGuestBuffer(data);
}

#define LC32_IMAGEIO_CALL0(opcode) LC32ImageIODispatch((opcode), NULL, 0)
#define LC32_IMAGEIO_CALL(opcode, ...) \
    LC32ImageIODispatch((opcode), (const uint64_t[]){__VA_ARGS__}, \
        sizeof((const uint64_t[]){__VA_ARGS__}) / sizeof(uint64_t))
#define LC32_IMAGEIO_HOST(object) LC32ImageIOHostObject((const void *)(object))
#define LC32_IMAGEIO_U32(value) ((uint64_t)(uint32_t)(value))

// Metadata objects use the same CF ownership bridge as image sources.

CFTypeID CGImageMetadataGetTypeID(void) {
    return (CFTypeID)LC32_IMAGEIO_CALL0(LC32ImageIOOpMetadataGetTypeID);
}

CFTypeID CGImageMetadataTagGetTypeID(void) {
    return (CFTypeID)LC32_IMAGEIO_CALL0(LC32ImageIOOpMetadataTagGetTypeID);
}

CGMutableImageMetadataRef CGImageMetadataCreateMutable(void) {
    return (CGMutableImageMetadataRef)LC32_IMAGEIO_CALL0(LC32ImageIOOpMetadataCreateMutable);
}

CGImageMetadataRef CGImageMetadataCreateFromXMPData(CFDataRef data) {
    if(!data) return NULL;
    return (CGImageMetadataRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCreateFromXMPData,
        LC32_IMAGEIO_HOST(data));
}

CGMutableImageMetadataRef CGImageMetadataCreateMutableCopy(CGImageMetadataRef metadata) {
    if(!metadata) return NULL;
    return (CGMutableImageMetadataRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCreateMutableCopy,
        LC32_IMAGEIO_HOST(metadata));
}

CFDataRef CGImageMetadataCreateXMPData(CGImageMetadataRef metadata, CFDictionaryRef options) {
    if(!metadata) return NULL;
    return (CFDataRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCreateXMPData,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(options));
}

CFArrayRef CGImageMetadataCopyTags(CGImageMetadataRef metadata) {
    if(!metadata) return NULL;
    return (CFArrayRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCopyTags,
        LC32_IMAGEIO_HOST(metadata));
}

CFStringRef CGImageMetadataTagCopyName(CGImageMetadataTagRef tag) {
    if(!tag) return NULL;
    return (CFStringRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagCopyName,
        LC32_IMAGEIO_HOST(tag));
}

CFStringRef CGImageMetadataTagCopyNamespace(CGImageMetadataTagRef tag) {
    if(!tag) return NULL;
    return (CFStringRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagCopyNamespace,
        LC32_IMAGEIO_HOST(tag));
}

CFStringRef CGImageMetadataTagCopyPrefix(CGImageMetadataTagRef tag) {
    if(!tag) return NULL;
    return (CFStringRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagCopyPrefix,
        LC32_IMAGEIO_HOST(tag));
}

CFArrayRef CGImageMetadataTagCopyQualifiers(CGImageMetadataTagRef tag) {
    if(!tag) return NULL;
    return (CFArrayRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagCopyQualifiers,
        LC32_IMAGEIO_HOST(tag));
}

CFTypeRef CGImageMetadataTagCopyValue(CGImageMetadataTagRef tag) {
    if(!tag) return NULL;
    return (CFTypeRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagCopyValue,
        LC32_IMAGEIO_HOST(tag));
}

CGImageMetadataType CGImageMetadataTagGetType(CGImageMetadataTagRef tag) {
    if(!tag) return 0;
    return (CGImageMetadataType)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagGetType,
        LC32_IMAGEIO_HOST(tag));
}

CGImageMetadataTagRef CGImageMetadataTagCreate(CFStringRef xmlns, CFStringRef prefix, CFStringRef name, CGImageMetadataType type, CFTypeRef value) {
    if(!xmlns || !name || !value) return NULL;
    return (CGImageMetadataTagRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataTagCreate,
        LC32_IMAGEIO_HOST(xmlns),
        LC32_IMAGEIO_HOST(prefix),
        LC32_IMAGEIO_HOST(name),
        LC32_IMAGEIO_U32(type),
        LC32_IMAGEIO_HOST(value));
}

CFStringRef CGImageMetadataCopyStringValueWithPath(CGImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path) {
    if(!metadata || !path) return NULL;
    return (CFStringRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCopyStringValueWithPath,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(parent),
        LC32_IMAGEIO_HOST(path));
}

CGImageMetadataTagRef CGImageMetadataCopyTagWithPath(CGImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path) {
    if(!metadata || !path) return NULL;
    return (CGImageMetadataTagRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCopyTagWithPath,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(parent),
        LC32_IMAGEIO_HOST(path));
}

CGImageMetadataTagRef CGImageMetadataCopyTagMatchingImageProperty(CGImageMetadataRef metadata, CFStringRef dictionary, CFStringRef property) {
    if(!metadata || !dictionary || !property) return NULL;
    return (CGImageMetadataTagRef)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataCopyTagMatchingImageProperty,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(dictionary),
        LC32_IMAGEIO_HOST(property));
}

bool CGImageMetadataRemoveTagWithPath(CGMutableImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path) {
    if(!metadata || !path) return 0;
    return (bool)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataRemoveTagWithPath,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(parent),
        LC32_IMAGEIO_HOST(path));
}

bool CGImageMetadataSetTagWithPath(CGMutableImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path, CGImageMetadataTagRef value) {
    if(!metadata || !path || !value) return 0;
    return (bool)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataSetTagWithPath,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(parent),
        LC32_IMAGEIO_HOST(path),
        LC32_IMAGEIO_HOST(value));
}

bool CGImageMetadataSetValueWithPath(CGMutableImageMetadataRef metadata, CGImageMetadataTagRef parent, CFStringRef path, CFTypeRef value) {
    if(!metadata || !path || !value) return 0;
    return (bool)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataSetValueWithPath,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(parent),
        LC32_IMAGEIO_HOST(path),
        LC32_IMAGEIO_HOST(value));
}

bool CGImageMetadataSetValueMatchingImageProperty(CGMutableImageMetadataRef metadata, CFStringRef dictionary, CFStringRef property, CFTypeRef value) {
    if(!metadata || !dictionary || !property || !value) return 0;
    return (bool)LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataSetValueMatchingImageProperty,
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(dictionary),
        LC32_IMAGEIO_HOST(property),
        LC32_IMAGEIO_HOST(value));
}

CGImageMetadataRef CGImageSourceCopyMetadataAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    if(!source) return NULL;
    return (CGImageMetadataRef)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCopyMetadataAtIndex,
        LC32_IMAGEIO_HOST(source),
        LC32_IMAGEIO_U32(index),
        LC32_IMAGEIO_HOST(options));
}

void CGImageDestinationAddImageAndMetadata(CGImageDestinationRef destination, CGImageRef image, CGImageMetadataRef metadata, CFDictionaryRef options) {
    if(!destination || !image) return;
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationAddImageAndMetadata,
        LC32_IMAGEIO_HOST(destination),
        LC32_IMAGEIO_HOST(image),
        LC32_IMAGEIO_HOST(metadata),
        LC32_IMAGEIO_HOST(options));
    LC32ImageIOInvalidateDestinationData(destination);
}

bool CGImageMetadataRegisterNamespaceForPrefix(CGMutableImageMetadataRef metadata,
        CFStringRef xmlns, CFStringRef prefix, CFErrorRef *error) {
    if(error) *error = NULL;
    if(!metadata || !xmlns || !prefix) return false;
    return LC32_IMAGEIO_CALL(LC32ImageIOOpMetadataRegisterNamespaceForPrefix,
        LC32_IMAGEIO_HOST(metadata), LC32_IMAGEIO_HOST(xmlns),
        LC32_IMAGEIO_HOST(prefix), LC32_IMAGEIO_U32((uintptr_t)error)) != 0;
}

bool CGImageDestinationCopyImageSource(CGImageDestinationRef destination,
        CGImageSourceRef source, CFDictionaryRef options, CFErrorRef *error) {
    if(error) *error = NULL;
    if(!destination || !source) return false;
    bool result = LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationCopyImageSource,
        LC32_IMAGEIO_HOST(destination), LC32_IMAGEIO_HOST(source),
        LC32_IMAGEIO_HOST(options), LC32_IMAGEIO_U32((uintptr_t)error)) != 0;
    LC32ImageIOInvalidateDestinationData(destination);
    return result;
}

CFTypeID CGImageSourceGetTypeID(void) {
    return (CFTypeID)LC32_IMAGEIO_CALL0(LC32ImageIOOpSourceGetTypeID);
}

CFArrayRef CGImageSourceCopyTypeIdentifiers(void) {
    return (CFArrayRef)(uintptr_t)LC32_IMAGEIO_CALL0(LC32ImageIOOpSourceCopyTypeIdentifiers);
}

CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef provider, CFDictionaryRef options) {
    return (CGImageSourceRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCreateWithDataProvider,
        LC32_IMAGEIO_HOST(provider), LC32_IMAGEIO_HOST(options));
}

CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options) {
    return (CGImageSourceRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCreateWithData,
        LC32_IMAGEIO_HOST(data), LC32_IMAGEIO_HOST(options));
}

CGImageSourceRef CGImageSourceCreateWithURL(CFURLRef url, CFDictionaryRef options) {
    return (CGImageSourceRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCreateWithURL,
        LC32_IMAGEIO_HOST(url), LC32_IMAGEIO_HOST(options));
}

CFStringRef CGImageSourceGetType(CGImageSourceRef source) {
    return (CFStringRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceGetType,
        LC32_IMAGEIO_HOST(source));
}

size_t CGImageSourceGetCount(CGImageSourceRef source) {
    return (size_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceGetCount,
        LC32_IMAGEIO_HOST(source));
}

CFDictionaryRef CGImageSourceCopyProperties(CGImageSourceRef source, CFDictionaryRef options) {
    return (CFDictionaryRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCopyProperties,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_HOST(options));
}

CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    return (CFDictionaryRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCopyPropertiesAtIndex,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_U32(index), LC32_IMAGEIO_HOST(options));
}

CGImageRef CGImageSourceCreateImageAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    return (CGImageRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCreateImageAtIndex,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_U32(index), LC32_IMAGEIO_HOST(options));
}

void CGImageSourceRemoveCacheAtIndex(CGImageSourceRef source, size_t index) {
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceRemoveCacheAtIndex,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_U32(index));
}

CGImageRef CGImageSourceCreateThumbnailAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    return (CGImageRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCreateThumbnailAtIndex,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_U32(index), LC32_IMAGEIO_HOST(options));
}

CGImageSourceRef CGImageSourceCreateIncremental(CFDictionaryRef options) {
    return (CGImageSourceRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceCreateIncremental,
        LC32_IMAGEIO_HOST(options));
}

void CGImageSourceUpdateData(CGImageSourceRef source, CFDataRef data, bool final) {
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceUpdateData,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_HOST(data), LC32_IMAGEIO_U32(final));
}

void CGImageSourceUpdateDataProvider(CGImageSourceRef source, CGDataProviderRef provider, bool final) {
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceUpdateDataProvider,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_HOST(provider), LC32_IMAGEIO_U32(final));
}

CGImageSourceStatus CGImageSourceGetStatus(CGImageSourceRef source) {
    return (CGImageSourceStatus)(int32_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceGetStatus,
        LC32_IMAGEIO_HOST(source));
}

CGImageSourceStatus CGImageSourceGetStatusAtIndex(CGImageSourceRef source, size_t index) {
    return (CGImageSourceStatus)(int32_t)LC32_IMAGEIO_CALL(LC32ImageIOOpSourceGetStatusAtIndex,
        LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_U32(index));
}

CFTypeID CGImageDestinationGetTypeID(void) {
    return (CFTypeID)LC32_IMAGEIO_CALL0(LC32ImageIOOpDestinationGetTypeID);
}

CFArrayRef CGImageDestinationCopyTypeIdentifiers(void) {
    return (CFArrayRef)(uintptr_t)LC32_IMAGEIO_CALL0(LC32ImageIOOpDestinationCopyTypeIdentifiers);
}

CGImageDestinationRef CGImageDestinationCreateWithDataConsumer(CGDataConsumerRef consumer, CFStringRef type, size_t count, CFDictionaryRef options) {
    return (CGImageDestinationRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationCreateWithDataConsumer,
        LC32_IMAGEIO_HOST(consumer), LC32_IMAGEIO_HOST(type), LC32_IMAGEIO_U32(count), LC32_IMAGEIO_HOST(options));
}

CGImageDestinationRef CGImageDestinationCreateWithData(CFMutableDataRef data, CFStringRef type, size_t count, CFDictionaryRef options) {
    CGImageDestinationRef destination = (CGImageDestinationRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationCreateWithData,
        LC32_IMAGEIO_HOST(data), LC32_IMAGEIO_HOST(type), LC32_IMAGEIO_U32(count), LC32_IMAGEIO_HOST(options));
    if(destination) {
        // Keep the guest data proxy alive for as long as its native encoder.
        // The association is released with the destination; no back-link exists.
        objc_setAssociatedObject((id)destination, kLC32ImageIODestinationData,
            (id)data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    LC32InvalidateDataGuestBuffer((NSData *)data);
    return destination;
}

CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef type, size_t count, CFDictionaryRef options) {
    return (CGImageDestinationRef)(uintptr_t)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationCreateWithURL,
        LC32_IMAGEIO_HOST(url), LC32_IMAGEIO_HOST(type), LC32_IMAGEIO_U32(count), LC32_IMAGEIO_HOST(options));
}

void CGImageDestinationSetProperties(CGImageDestinationRef destination, CFDictionaryRef properties) {
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationSetProperties,
        LC32_IMAGEIO_HOST(destination), LC32_IMAGEIO_HOST(properties));
    LC32ImageIOInvalidateDestinationData(destination);
}

void CGImageDestinationAddImage(CGImageDestinationRef destination, CGImageRef image, CFDictionaryRef properties) {
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationAddImage,
        LC32_IMAGEIO_HOST(destination), LC32_IMAGEIO_HOST(image), LC32_IMAGEIO_HOST(properties));
    LC32ImageIOInvalidateDestinationData(destination);
}

void CGImageDestinationAddImageFromSource(CGImageDestinationRef destination, CGImageSourceRef source, size_t index, CFDictionaryRef properties) {
    (void)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationAddImageFromSource,
        LC32_IMAGEIO_HOST(destination), LC32_IMAGEIO_HOST(source), LC32_IMAGEIO_U32(index), LC32_IMAGEIO_HOST(properties));
    LC32ImageIOInvalidateDestinationData(destination);
}

bool CGImageDestinationFinalize(CGImageDestinationRef destination) {
    bool finalized = (bool)LC32_IMAGEIO_CALL(LC32ImageIOOpDestinationFinalize,
        LC32_IMAGEIO_HOST(destination));
    LC32ImageIOInvalidateDestinationData(destination);
    return finalized;
}

#undef LC32_IMAGEIO_CALL0
#undef LC32_IMAGEIO_CALL
#undef LC32_IMAGEIO_HOST
#undef LC32_IMAGEIO_U32
