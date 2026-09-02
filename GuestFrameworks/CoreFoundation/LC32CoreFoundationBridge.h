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

    /* URL construction and percent-decoding operations used by YouTube. */
    LC32CoreFoundationOpURLCreateWithString = 41,
    LC32CoreFoundationOpURLCreateWithBytes = 42,
    LC32CoreFoundationOpURLCreateStringByReplacingPercentEscapes = 43,
    LC32CoreFoundationOpStringTrimWhitespace = 44,
    LC32CoreFoundationOpNumberGetType = 45,
    LC32CoreFoundationOpBundleGetVersionNumber = 46,
    LC32CoreFoundationOpLocaleGetSystem = 47,
    LC32CoreFoundationOpStringLowercase = 48,
    LC32CoreFoundationOpURLCopyPathExtension = 49,
    LC32CoreFoundationOpBundleCopyBundleURL = 50,
    LC32CoreFoundationOpURLCopyFileSystemPath = 51,

    /* Public CFURL operations. Keep this range contiguous so the guest and
     * host bridge remain easy to audit against CFURL.h. */
    LC32CoreFoundationOpURLGetTypeID = 52,
    LC32CoreFoundationOpURLGetString = 53,
    LC32CoreFoundationOpURLGetBaseURL = 54,
    LC32CoreFoundationOpURLCanBeDecomposed = 55,
    LC32CoreFoundationOpURLCopyAbsoluteURL = 56,
    LC32CoreFoundationOpURLCopyScheme = 57,
    LC32CoreFoundationOpURLCopyHostName = 58,
    LC32CoreFoundationOpURLCopyPath = 59,
    LC32CoreFoundationOpURLCopyStrictPath = 60,
    LC32CoreFoundationOpURLCopyResourceSpecifier = 61,
    LC32CoreFoundationOpURLCopyUserName = 62,
    LC32CoreFoundationOpURLCopyPassword = 63,
    LC32CoreFoundationOpURLCopyQueryString = 64,
    LC32CoreFoundationOpURLCopyFragment = 65,
    LC32CoreFoundationOpURLCopyLastPathComponent = 66,
    LC32CoreFoundationOpURLGetPortNumber = 67,
    LC32CoreFoundationOpURLHasDirectoryPath = 68,
    LC32CoreFoundationOpURLCreateCopyAppendingPathComponent = 69,
    LC32CoreFoundationOpURLCreateCopyDeletingLastPathComponent = 70,
    LC32CoreFoundationOpURLCreateCopyAppendingPathExtension = 71,
    LC32CoreFoundationOpURLCreateCopyDeletingPathExtension = 72,
    LC32CoreFoundationOpURLGetFileSystemRepresentation = 73,
    LC32CoreFoundationOpURLSetResourcePropertyForKey = 74,
    LC32CoreFoundationOpURLCreateWithFileSystemPath = 75,
    LC32CoreFoundationOpURLCreateWithFileSystemPathRelativeToBase = 76,
    LC32CoreFoundationOpURLGetBytes = 77,
    LC32CoreFoundationOpURLGetByteRangeForComponent = 78,
    LC32CoreFoundationOpURLCreateFromFileSystemRepresentationRelativeToBase = 79,
    LC32CoreFoundationOpBundlePreflightExecutable = 80,
    LC32CoreFoundationOpBundleLoadExecutableAndReturnError = 81,

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
    LC32CoreFoundationOpStringConvertEncodingToNSStringEncoding = 115,
    LC32CoreFoundationOpStringConvertNSStringEncodingToEncoding = 116,
    LC32CoreFoundationOpStringConvertIANACharSetNameToEncoding = 117,
    LC32CoreFoundationOpStringConvertEncodingToIANACharSetName = 118,
    LC32CoreFoundationOpStringGetMaximumSizeOfFileSystemRepresentation = 119,
    LC32CoreFoundationOpStringGetFileSystemRepresentation = 120,

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
    LC32CoreFoundationOpPropertyListCreateDeepCopy = 218,
    LC32CoreFoundationOpPreferencesSetAppValue = 219,
    LC32CoreFoundationOpPreferencesAppSynchronize = 220,
    LC32CoreFoundationOpPropertyListCreateData = 221,
    LC32CoreFoundationOpPropertyListIsValid = 222,
    LC32CoreFoundationOpDateFormatterCreateDateFromString = 223,
    LC32CoreFoundationOpDateFormatterGetAbsoluteTimeFromString = 224,

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

    /* Attributed-string operations imported by the legacy YouTube client. */
    LC32CoreFoundationOpAttributedStringCreate = 400,
    LC32CoreFoundationOpAttributedStringCreateMutable = 401,
    LC32CoreFoundationOpAttributedStringCreateWithSubstring = 402,
    LC32CoreFoundationOpAttributedStringGetLength = 403,
    LC32CoreFoundationOpAttributedStringReplaceAttributedString = 404,
    LC32CoreFoundationOpAttributedStringGetAttributes = 405,
    LC32CoreFoundationOpAttributedStringGetAttribute = 406,
    LC32CoreFoundationOpAttributedStringGetAttributesLongest = 407,
    LC32CoreFoundationOpAttributedStringGetAttributeLongest = 408,

    /* CFReadStream operations used by the legacy YouTube Widevine client. */
    LC32CoreFoundationOpReadStreamOpen = 500,
    LC32CoreFoundationOpReadStreamClose = 501,
    LC32CoreFoundationOpReadStreamGetStatus = 502,
    LC32CoreFoundationOpReadStreamHasBytesAvailable = 503,
    LC32CoreFoundationOpReadStreamRead = 504,
    LC32CoreFoundationOpReadStreamCopyError = 505,
    LC32CoreFoundationOpReadStreamCopyProperty = 506,
    LC32CoreFoundationOpReadStreamSetProperty = 507,
    LC32CoreFoundationOpReadStreamScheduleWithRunLoop = 508,
    LC32CoreFoundationOpReadStreamUnscheduleFromRunLoop = 509,
    LC32CoreFoundationOpReadStreamGetError = 510,
    LC32CoreFoundationOpReadStreamSetClient = 511,

    /* CFWriteStream and socket-pair operations used by YouTube networking. */
    LC32CoreFoundationOpWriteStreamOpen = 512,
    LC32CoreFoundationOpWriteStreamClose = 513,
    LC32CoreFoundationOpWriteStreamGetStatus = 514,
    LC32CoreFoundationOpWriteStreamCanAcceptBytes = 515,
    LC32CoreFoundationOpWriteStreamWrite = 516,
    LC32CoreFoundationOpWriteStreamCopyError = 517,
    LC32CoreFoundationOpWriteStreamCopyProperty = 518,
    LC32CoreFoundationOpWriteStreamSetProperty = 519,
    LC32CoreFoundationOpWriteStreamScheduleWithRunLoop = 520,
    LC32CoreFoundationOpWriteStreamUnscheduleFromRunLoop = 521,
    LC32CoreFoundationOpWriteStreamGetError = 522,
    LC32CoreFoundationOpWriteStreamSetClient = 523,
    LC32CoreFoundationOpStreamCreatePairWithSocket = 524,
    LC32CoreFoundationOpStreamCreatePairWithSocketToHost = 525,

    /* Non-callback CFRunLoop operations used by legacy YouTube.  The timer
     * and source creators live in a separate callback-aware bridge. */
    LC32CoreFoundationOpRunLoopAddSource = 600,
    LC32CoreFoundationOpRunLoopAddTimer = 601,
    LC32CoreFoundationOpRunLoopCopyAllModes = 602,
    LC32CoreFoundationOpRunLoopRemoveSource = 603,
    LC32CoreFoundationOpRunLoopRemoveTimer = 604,
    LC32CoreFoundationOpRunLoopRun = 605,
    LC32CoreFoundationOpRunLoopRunInMode = 606,
    LC32CoreFoundationOpRunLoopSourceInvalidate = 607,
    LC32CoreFoundationOpRunLoopSourceSignal = 608,
    LC32CoreFoundationOpRunLoopStop = 609,
    LC32CoreFoundationOpRunLoopTimerInvalidate = 610,
    LC32CoreFoundationOpRunLoopTimerSetNextFireDate = 611,
    LC32CoreFoundationOpRunLoopWakeUp = 612,
    LC32CoreFoundationOpRunLoopTimerCreate = 613,
    LC32CoreFoundationOpRunLoopSourceCreate = 614,
    LC32CoreFoundationOpRunLoopAddCommonMode = 615,

    /* Callback-aware socket operations used by legacy YouTube. */
    LC32CoreFoundationOpSocketCreate = 700,
    LC32CoreFoundationOpSocketConnectToAddress = 701,
    LC32CoreFoundationOpSocketCreateRunLoopSource = 702,
    LC32CoreFoundationOpSocketGetNative = 703,
    LC32CoreFoundationOpSocketInvalidate = 704,

    /* Legacy CFBitVector operations. */
    LC32CoreFoundationOpBitVectorCreate = 800,
    LC32CoreFoundationOpBitVectorCreateMutableCopy = 801,
    LC32CoreFoundationOpBitVectorGetBitAtIndex = 802,
    LC32CoreFoundationOpBitVectorSetBitAtIndex = 803,
} LC32CoreFoundationOpcode;

typedef enum : uint32_t {
    LC32CoreFoundationCallbacksInvalid = 0,
    LC32CoreFoundationCallbacksCFType = 1,
    LC32CoreFoundationCallbacksNull = 2,
    LC32CoreFoundationCallbacksWeakCFType = 3,
    LC32CoreFoundationCallbacksWeakCFTypeNoDescription = 4,
    LC32CoreFoundationCallbacksCopyString = 5,
    LC32CoreFoundationCallbacksRetainedObjectNoDescriptionOrEqual = 6,
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
