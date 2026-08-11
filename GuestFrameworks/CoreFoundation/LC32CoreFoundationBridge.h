#ifndef LC32_CORE_FOUNDATION_BRIDGE_H
#define LC32_CORE_FOUNDATION_BRIDGE_H

#include <stdint.h>

enum {
    LC32CoreFoundationABIVersion = 1,
    LC32CoreFoundationMaxSlots = 8,
};

typedef struct {
    uint32_t version;
    uint32_t slotCount;
    uint64_t slots[LC32CoreFoundationMaxSlots];
} LC32CoreFoundationCall;

typedef enum : uint32_t {
    LC32CoreFoundationOpArrayCreateMutable = 1,
    LC32CoreFoundationOpDictionaryCreateMutable = 2,
    LC32CoreFoundationOpStringCreateCopy = 3,
    LC32CoreFoundationOpStringCreateMutable = 4,
    LC32CoreFoundationOpStringCreateMutableCopy = 5,
    LC32CoreFoundationOpStringCreateWithCString = 6,
    LC32CoreFoundationOpStringCreateWithSubstring = 7,
    LC32CoreFoundationOpStringCreateArrayBySeparatingStrings = 8,
    LC32CoreFoundationOpStringGetCString = 9,
    LC32CoreFoundationOpStringGetMaximumSizeForEncoding = 10,
    LC32CoreFoundationOpURLCreateStringByAddingPercentEscapes = 11,
    LC32CoreFoundationOpNumberGetValue = 12,
    LC32CoreFoundationOpBundleGetMainBundle = 13,
    LC32CoreFoundationOpRunLoopGetMain = 14,
    LC32CoreFoundationOpDictionaryGetValue = 15,
    LC32CoreFoundationOpDictionarySetValue = 16,
    LC32CoreFoundationOpDictionaryRemoveValue = 17,
} LC32CoreFoundationOpcode;

typedef enum : uint32_t {
    LC32CoreFoundationCallbacksInvalid = 0,
    LC32CoreFoundationCallbacksCFType = 1,
    LC32CoreFoundationCallbacksNull = 2,
    LC32CoreFoundationCallbacksWeakCFType = 3,
    LC32CoreFoundationCallbacksWeakCFTypeNoDescription = 4,
} LC32CoreFoundationCallbacksMode;

#endif
