#import <GameController/GameController.h>

#include <stdint.h>
#include <string.h>

typedef struct __attribute__((packed)) {
    uint16_t version;
    uint16_t size;
} LC32GameControllerSnapshotHeader;

_Static_assert(sizeof(LC32GameControllerSnapshotHeader) == 4,
               "snapshot header layout changed");

static BOOL LC32DecodeGameControllerSnapshot(
        void *snapshot, size_t snapshotSize, NSData *data) {
    if(!snapshot || !data) return NO;

    /* Match GameController's tolerant decoder: the embedded size is a copy
     * bound, short records are zero-filled, and only nil arguments fail. */
    memset(snapshot, 0, snapshotSize);
    const NSUInteger dataLength = data.length;
    const void *bytes = data.bytes;
    if(!bytes || dataLength < sizeof(LC32GameControllerSnapshotHeader))
        return YES;

    LC32GameControllerSnapshotHeader header;
    memcpy(&header, bytes, sizeof(header));
    const size_t copyLength = MIN(
        snapshotSize, MIN((size_t)dataLength, (size_t)header.size));
    if(copyLength) memcpy(snapshot, bytes, copyLength);
    return YES;
}

static NSData *LC32EncodeGameControllerSnapshot(
        const void *snapshot, size_t snapshotSize) {
    if(!snapshot) return nil;

    NSMutableData *data = [NSMutableData dataWithBytes:snapshot
                                               length:snapshotSize];
    if(!data) return nil;

    LC32GameControllerSnapshotHeader *header = data.mutableBytes;
    if(!header) return nil;
    if(!header->version) {
        header->version = 0x0100;
        header->size = (uint16_t)snapshotSize;
    }
    return data;
}

BOOL GCGamepadSnapShotDataV100FromNSData(
        GCGamepadSnapShotDataV100 *snapshotData, NSData *data) {
    return LC32DecodeGameControllerSnapshot(
        snapshotData, sizeof(*snapshotData), data);
}

NSData *NSDataFromGCGamepadSnapShotDataV100(
        GCGamepadSnapShotDataV100 *snapshotData) {
    return LC32EncodeGameControllerSnapshot(
        snapshotData, sizeof(*snapshotData));
}

BOOL GCExtendedGamepadSnapShotDataV100FromNSData(
        GCExtendedGamepadSnapShotDataV100 *snapshotData, NSData *data) {
    return LC32DecodeGameControllerSnapshot(
        snapshotData, sizeof(*snapshotData), data);
}

NSData *NSDataFromGCExtendedGamepadSnapShotDataV100(
        GCExtendedGamepadSnapShotDataV100 *snapshotData) {
    return LC32EncodeGameControllerSnapshot(
        snapshotData, sizeof(*snapshotData));
}

BOOL GCMicroGamepadSnapShotDataV100FromNSData(
        GCMicroGamepadSnapShotDataV100 *snapshotData, NSData *data) {
    return LC32DecodeGameControllerSnapshot(
        snapshotData, sizeof(*snapshotData), data);
}

NSData *NSDataFromGCMicroGamepadSnapShotDataV100(
        GCMicroGamepadSnapShotDataV100 *snapshotData) {
    return LC32EncodeGameControllerSnapshot(
        snapshotData, sizeof(*snapshotData));
}
