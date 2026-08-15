#pragma once

#include <stdint.h>

enum {
    LC32FoundationDelayedTimerABIVersion = 1,
    LC32FoundationDelayedTimerSlotCount = 3,
    LC32FoundationStringGetBytesABIVersion = 1,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32FoundationDelayedTimerSlotCount];
} LC32FoundationDelayedTimerCall;

typedef struct {
    uint32_t version;
    uint32_t byteSize;
    uint32_t hostStringLow;
    uint32_t hostStringHigh;
    uint32_t guestBuffer;
    uint32_t maximumLength;
    uint32_t guestUsedLength;
    uint32_t encoding;
    uint32_t options;
    uint32_t rangeLocation;
    uint32_t rangeLength;
    uint32_t guestRemainingRange;
} LC32FoundationStringGetBytesRequest;

enum {
    LC32FoundationDelayedTimerTargetSlot = 0,
    LC32FoundationDelayedTimerSelectorSlot = 1,
    LC32FoundationDelayedTimerIntervalSlot = 2,
};
