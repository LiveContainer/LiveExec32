#pragma once

#include <stdint.h>

enum {
    LC32FoundationDelayedTimerABIVersion = 1,
    LC32FoundationDelayedTimerSlotCount = 3,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32FoundationDelayedTimerSlotCount];
} LC32FoundationDelayedTimerCall;

enum {
    LC32FoundationDelayedTimerTargetSlot = 0,
    LC32FoundationDelayedTimerSelectorSlot = 1,
    LC32FoundationDelayedTimerIntervalSlot = 2,
};
