#ifndef LC32_FOUNDATION_BRIDGE_ABI_H
#define LC32_FOUNDATION_BRIDGE_ABI_H

#include <stdint.h>

enum {
    LC32FoundationStringRangeABIVersion = 1,
};

typedef enum LC32FoundationStringRangeVariant {
    LC32FoundationStringRangePlain = 0,
    LC32FoundationStringRangeWithOptions = 1,
    LC32FoundationStringRangeWithRange = 2,
    LC32FoundationStringRangeWithLocale = 3,
} LC32FoundationStringRangeVariant;

/*
 * Keep this request entirely in 32-bit words.  In particular, do not put
 * uint64_t fields in it: their alignment differs between the ARM32 guest and
 * ARM64 host ABIs.  Host Objective-C object addresses are split explicitly.
 */
typedef struct LC32FoundationStringRangeRequest {
    uint32_t version;
    uint32_t byteSize;
    uint32_t variant;
    uint32_t options;
    uint32_t hostStringLow;
    uint32_t hostStringHigh;
    uint32_t hostNeedleLow;
    uint32_t hostNeedleHigh;
    uint32_t rangeLocation;
    uint32_t rangeLength;
    uint32_t hostLocaleLow;
    uint32_t hostLocaleHigh;
} LC32FoundationStringRangeRequest;

#if defined(__cplusplus)
static_assert(sizeof(LC32FoundationStringRangeRequest) == 48,
              "NSString range request ABI changed");
#else
_Static_assert(sizeof(LC32FoundationStringRangeRequest) == 48,
               "NSString range request ABI changed");
#endif

#endif
