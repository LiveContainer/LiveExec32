#ifndef LC32_CORE_MEDIA_BRIDGE_H
#define LC32_CORE_MEDIA_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

enum {
    LC32CoreMediaABIVersion = 1,
    LC32CoreMediaMaxSlots = 12,
};

typedef struct {
    uint32_t version, slotCount;
    uint64_t slots[LC32CoreMediaMaxSlots];
} LC32CoreMediaCall;

// Do not pass a native structure return through the generic C call bridge.
// The guest reconstructs CMTime so clang supplies its ARM32 return ABI.
typedef struct {
    int64_t value;
    int32_t timescale;
    uint32_t flags;
    int64_t epoch;
} LC32CoreMediaTime;

#ifdef __cplusplus
static_assert(sizeof(LC32CoreMediaCall) == 104 &&
              offsetof(LC32CoreMediaCall, slots) == 8,
              "CoreMedia request layout must match the ARM32 guest");
static_assert(sizeof(LC32CoreMediaTime) == 24 &&
              offsetof(LC32CoreMediaTime, epoch) == 16,
              "CoreMedia time layout must match the ARM32 guest");
#else
_Static_assert(sizeof(LC32CoreMediaCall) == 104 &&
               offsetof(LC32CoreMediaCall, slots) == 8,
               "CoreMedia request layout must match the ARM64 host");
_Static_assert(sizeof(LC32CoreMediaTime) == 24 &&
               offsetof(LC32CoreMediaTime, epoch) == 16,
               "CoreMedia time layout must match the ARM64 host");
#endif

typedef enum : uint32_t {
    LC32CMSampleBufferGetImageBuffer = 1,
    LC32CMSampleBufferGetPresentationTimeStamp,
    LC32CMSampleBufferGetTypeID,
    LC32CMSampleBufferIsValid,
    LC32CMAudioFormatDescriptionCreate,
    LC32CMSampleBufferCreate,
    LC32CMSampleBufferSetDataBufferFromAudioBufferList,
    LC32CMSampleBufferSetDataReady,
} LC32CoreMediaOpcode;

#endif
