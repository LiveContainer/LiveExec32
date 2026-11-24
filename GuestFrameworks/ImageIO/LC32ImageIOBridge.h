#ifndef LC32_IMAGEIO_BRIDGE_H
#define LC32_IMAGEIO_BRIDGE_H

#include <stdint.h>

enum {
    LC32ImageIOABIVersion = 1,
    LC32ImageIOMaxSlots = 5,
};

// Slots carry native object addresses or zero-extended ARM32 scalar values.
// No native size_t, pointer, or signed status is written into guest storage.
typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32ImageIOMaxSlots];
} LC32ImageIOCall;

typedef enum : uint32_t {
    LC32ImageIOOpSourceGetTypeID = 1,
    LC32ImageIOOpSourceCopyTypeIdentifiers = 2,
    LC32ImageIOOpSourceCreateWithDataProvider = 3,
    LC32ImageIOOpSourceCreateWithData = 4,
    LC32ImageIOOpSourceCreateWithURL = 5,
    LC32ImageIOOpSourceGetType = 6,
    LC32ImageIOOpSourceGetCount = 7,
    LC32ImageIOOpSourceCopyProperties = 8,
    LC32ImageIOOpSourceCopyPropertiesAtIndex = 9,
    LC32ImageIOOpSourceCreateImageAtIndex = 10,
    LC32ImageIOOpSourceRemoveCacheAtIndex = 11,
    LC32ImageIOOpSourceCreateThumbnailAtIndex = 12,
    LC32ImageIOOpSourceCreateIncremental = 13,
    LC32ImageIOOpSourceUpdateData = 14,
    LC32ImageIOOpSourceUpdateDataProvider = 15,
    LC32ImageIOOpSourceGetStatus = 16,
    LC32ImageIOOpSourceGetStatusAtIndex = 17,
    LC32ImageIOOpDestinationGetTypeID = 18,
    LC32ImageIOOpDestinationCopyTypeIdentifiers = 19,
    LC32ImageIOOpDestinationCreateWithDataConsumer = 20,
    LC32ImageIOOpDestinationCreateWithData = 21,
    LC32ImageIOOpDestinationCreateWithURL = 22,
    LC32ImageIOOpDestinationSetProperties = 23,
    LC32ImageIOOpDestinationAddImage = 24,
    LC32ImageIOOpDestinationAddImageFromSource = 25,
    LC32ImageIOOpDestinationFinalize = 26,
    LC32ImageIOOpMetadataGetTypeID = 27,
    LC32ImageIOOpMetadataTagGetTypeID = 28,
    LC32ImageIOOpMetadataCreateMutable = 29,
    LC32ImageIOOpMetadataCreateFromXMPData = 30,
    LC32ImageIOOpMetadataCreateMutableCopy = 31,
    LC32ImageIOOpMetadataCreateXMPData = 32,
    LC32ImageIOOpMetadataCopyTags = 33,
    LC32ImageIOOpMetadataTagCopyName = 34,
    LC32ImageIOOpMetadataTagCopyNamespace = 35,
    LC32ImageIOOpMetadataTagCopyPrefix = 36,
    LC32ImageIOOpMetadataTagCopyQualifiers = 37,
    LC32ImageIOOpMetadataTagCopyValue = 38,
    LC32ImageIOOpMetadataTagGetType = 39,
    LC32ImageIOOpMetadataTagCreate = 40,
    LC32ImageIOOpMetadataCopyStringValueWithPath = 41,
    LC32ImageIOOpMetadataCopyTagWithPath = 42,
    LC32ImageIOOpMetadataCopyTagMatchingImageProperty = 43,
    LC32ImageIOOpMetadataRemoveTagWithPath = 44,
    LC32ImageIOOpMetadataSetTagWithPath = 45,
    LC32ImageIOOpMetadataSetValueWithPath = 46,
    LC32ImageIOOpMetadataSetValueMatchingImageProperty = 47,
    LC32ImageIOOpSourceCopyMetadataAtIndex = 48,
    LC32ImageIOOpDestinationAddImageAndMetadata = 49,
    LC32ImageIOOpMetadataRegisterNamespaceForPrefix = 50,
    LC32ImageIOOpDestinationCopyImageSource = 51,
} LC32ImageIOOpcode;

#endif
