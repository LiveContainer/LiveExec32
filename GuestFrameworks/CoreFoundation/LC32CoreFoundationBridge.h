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
    LC32CoreFoundationOpURLCreateFromFileSystemRepresentation = 18,

    /* Collection, data, and runtime-type operations. */
    LC32CoreFoundationOpDictionaryContainsKey = 19,
    LC32CoreFoundationOpDictionaryGetCount = 20,
    LC32CoreFoundationOpDictionaryGetKeysAndValues = 21,
    LC32CoreFoundationOpDataCreate = 22,
    LC32CoreFoundationOpDataCreateCopy = 23,
    LC32CoreFoundationOpDataCreateMutable = 24,
    LC32CoreFoundationOpDataCreateMutableCopy = 25,
    LC32CoreFoundationOpDataAppendBytes = 26,
    LC32CoreFoundationOpDataDeleteBytes = 27,
    LC32CoreFoundationOpDataIncreaseLength = 28,
    LC32CoreFoundationOpDataReplaceBytes = 29,
    LC32CoreFoundationOpDataSetLength = 30,
    LC32CoreFoundationOpGetTypeID = 31,
    LC32CoreFoundationOpGetKnownTypeID = 32,
    LC32CoreFoundationOpNumberCreate = 33,

    /* Bundle operations used by the guest Security framework. */
    LC32CoreFoundationOpBundleGetIdentifier = 34,
    LC32CoreFoundationOpBundleCopyLocalizedString = 35,
    LC32CoreFoundationOpBundleCopyResourceURL = 36,
    LC32CoreFoundationOpBundleCreate = 37,
    LC32CoreFoundationOpBundleGetBundleWithIdentifier = 38,
    LC32CoreFoundationOpBundleGetFunctionPointerForName = 39,
    LC32CoreFoundationOpRunLoopGetCurrent = 40,

    /* String operations use an isolated range so parallel bridge work can
     * add lower-valued opcode families without changing this guest ABI. */
    LC32CoreFoundationOpStringCreateWithBytes = 100,
    LC32CoreFoundationOpStringCreateWithCharacters = 101,
    LC32CoreFoundationOpStringAppendCString = 102,
    LC32CoreFoundationOpStringAppendCharacters = 103,
    LC32CoreFoundationOpStringCompareWithOptions = 104,
    LC32CoreFoundationOpStringCreateExternalRepresentation = 105,
    LC32CoreFoundationOpStringCreateFromExternalRepresentation = 106,
    LC32CoreFoundationOpStringFindWithOptions = 107,
    LC32CoreFoundationOpStringFindCharacterFromSet = 108,
    LC32CoreFoundationOpStringFindAndReplace = 109,
    LC32CoreFoundationOpStringGetBytes = 110,
    LC32CoreFoundationOpStringGetCharacterAtIndex = 111,
    LC32CoreFoundationOpStringGetCharacters = 112,
    LC32CoreFoundationOpStringGetIntValue = 113,
    LC32CoreFoundationOpStringUppercase = 114,

    /* Date, error, locale, and preferences operations used by Security. */
    LC32CoreFoundationOpDateCreate = 200,
    LC32CoreFoundationOpDateGetAbsoluteTime = 201,
    LC32CoreFoundationOpDateGetTimeIntervalSinceDate = 202,
    LC32CoreFoundationOpDateCompare = 203,
    LC32CoreFoundationOpDateFormatterCreate = 204,
    LC32CoreFoundationOpDateFormatterSetFormat = 205,
    LC32CoreFoundationOpDateFormatterCreateStringWithAbsoluteTime = 206,
    LC32CoreFoundationOpErrorCreate = 207,
    LC32CoreFoundationOpErrorCreateWithUserInfoKeysAndValues = 208,
    LC32CoreFoundationOpErrorGetDomain = 209,
    LC32CoreFoundationOpErrorGetCode = 210,
    LC32CoreFoundationOpErrorCopyUserInfo = 211,
    LC32CoreFoundationOpErrorCopyDescription = 212,
    LC32CoreFoundationOpLocaleCopyCurrent = 213,
    LC32CoreFoundationOpPreferencesCopyAppValue = 214,
    LC32CoreFoundationOpPreferencesGetAppBooleanValue = 215,
    LC32CoreFoundationOpPreferencesGetAppIntegerValue = 216,

    /* Property-list serialization operations used by Security. */
    LC32CoreFoundationOpPropertyListCreateWithData = 217,

    /* CFSet operations used by the guest Security framework. */
    LC32CoreFoundationOpSetCreate = 300,
    LC32CoreFoundationOpSetCreateCopy = 301,
    LC32CoreFoundationOpSetCreateMutable = 302,
    LC32CoreFoundationOpSetCreateMutableCopy = 303,
    LC32CoreFoundationOpSetGetCount = 304,
    LC32CoreFoundationOpSetGetValue = 305,
    LC32CoreFoundationOpSetGetValues = 306,
    LC32CoreFoundationOpSetContainsValue = 307,
    LC32CoreFoundationOpSetAddValue = 308,
    LC32CoreFoundationOpSetSetValue = 309,
    LC32CoreFoundationOpSetRemoveValue = 310,
    LC32CoreFoundationOpSetRemoveAllValues = 311,
} LC32CoreFoundationOpcode;

typedef enum : uint32_t {
    LC32CoreFoundationCallbacksInvalid = 0,
    LC32CoreFoundationCallbacksCFType = 1,
    LC32CoreFoundationCallbacksNull = 2,
    LC32CoreFoundationCallbacksWeakCFType = 3,
    LC32CoreFoundationCallbacksWeakCFTypeNoDescription = 4,
    LC32CoreFoundationCallbacksCopyString = 5,
} LC32CoreFoundationCallbacksMode;

typedef enum : uint32_t {
    LC32CoreFoundationTypeArray = 1,
    LC32CoreFoundationTypeBoolean = 2,
    LC32CoreFoundationTypeData = 3,
    LC32CoreFoundationTypeDate = 4,
    LC32CoreFoundationTypeDictionary = 5,
    LC32CoreFoundationTypeNull = 6,
    LC32CoreFoundationTypeNumber = 7,
    LC32CoreFoundationTypeSet = 8,
    LC32CoreFoundationTypeString = 9,
} LC32CoreFoundationKnownType;

#endif
