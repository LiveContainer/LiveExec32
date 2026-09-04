#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/CoreFoundation.framework/CoreFoundation"}
SDKROOT=${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}
SDK_STUB="$SDKROOT/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation.tbd"

work=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-corefoundation-low-risk.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

cat > "$work/expected" <<'EOF'
CFCopyHomeDirectoryURL
CFAbsoluteTimeGetDayOfWeek
CFAbsoluteTimeGetDayOfYear
CFAbsoluteTimeGetWeekOfYear
CFDateFormatterCreateISO8601Formatter
CFNumberFormatterGetDecimalInfoForCurrencyCode
CFPropertyListCreateFromXMLData
CFPreferencesAddSuitePreferencesToApp
CFPreferencesAppValueIsForced
CFPreferencesCopyApplicationList
CFPreferencesCopyKeyList
CFPreferencesCopyMultiple
CFPreferencesCopyValue
CFPreferencesRemoveSuitePreferencesFromApp
CFPreferencesSetMultiple
CFPreferencesSetValue
CFPreferencesSynchronize
CFShow
CFShowStr
CFLocaleCopyCommonISOCurrencyCodes
CFLocaleCopyPreferredLanguages
CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode
CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes
CFLocaleGetWindowsLocaleCodeFromLocaleIdentifier
CFLocaleGetLanguageCharacterDirection
CFLocaleGetLanguageLineDirection
CFStringCompareWithOptionsAndLocale
CFStringFindWithOptionsAndLocale
CFStringGetLineBounds
CFStringGetHyphenationLocationBeforeIndex
CFStringGetMostCompatibleMacStringEncoding
CFStringGetParagraphBounds
CFStringGetSmallestEncoding
CFStringGetSystemEncoding
CFStringIsEncodingAvailable
CFStringIsHyphenationAvailableForLocale
CFStringGetNameOfEncoding
CFStringConvertEncodingToWindowsCodepage
CFStringConvertWindowsCodepageToEncoding
CFStringPad
CFStringTrim
CFURLClearResourcePropertyCache
CFURLClearResourcePropertyCacheForKey
CFURLCopyResourcePropertiesForKeys
CFURLCopyResourcePropertyForKey
CFURLCopyNetLocation
CFURLCopyParameterString
CFURLCreateData
CFURLCreateFilePathURL
CFURLCreateFileReferenceURL
CFURLIsFileReferenceURL
CFURLResourceIsReachable
CFURLSetResourcePropertiesForKeys
CFURLSetTemporaryResourcePropertyForKey
CFURLStartAccessingSecurityScopedResource
CFURLStopAccessingSecurityScopedResource
CFAttributedStringGetTypeID
CFBitVectorContainsBit
CFBitVectorCreateCopy
CFBitVectorCreateMutable
CFBitVectorFlipBitAtIndex
CFBitVectorFlipBits
CFBitVectorGetBits
CFBitVectorGetCount
CFBitVectorGetCountOfBit
CFBitVectorGetFirstIndexOfBit
CFBitVectorGetLastIndexOfBit
CFBitVectorSetAllBits
CFBitVectorSetBits
CFBitVectorSetCount
CFBitVectorGetTypeID
CFBundleCopyExecutableArchitecturesForURL
CFBundleCopyInfoDictionaryForURL
CFBundleCopyInfoDictionaryInDirectory
CFBundleCopyLocalizationsForURL
CFBundleCopyResourceURLInDirectory
CFBundleCopyResourceURLsOfTypeInDirectory
CFBundleCreateBundlesFromDirectory
CFBundleGetAllBundles
CFBundleGetPackageInfo
CFBundleGetPackageInfoInDirectory
CFBundleGetTypeID
CFFileSecurityClearProperties
CFFileSecurityCopyGroupUUID
CFFileSecurityCopyOwnerUUID
CFFileSecurityCreate
CFFileSecurityCreateCopy
CFFileSecurityGetGroup
CFFileSecurityGetMode
CFFileSecurityGetOwner
CFFileSecurityGetTypeID
CFFileSecuritySetGroup
CFFileSecuritySetGroupUUID
CFFileSecuritySetMode
CFFileSecuritySetOwner
CFFileSecuritySetOwnerUUID
CFNotificationCenterGetTypeID
CFNotificationCenterPostNotification
CFNotificationCenterPostNotificationWithOptions
CFReadStreamCreateWithFile
CFReadStreamGetTypeID
CFStreamCreateBoundPair
CFWriteStreamCreateWithAllocatedBuffers
CFWriteStreamCreateWithFile
CFWriteStreamGetTypeID
CFRunLoopGetTypeID
CFRunLoopContainsSource
CFRunLoopContainsTimer
CFRunLoopCopyCurrentMode
CFRunLoopGetNextTimerFireDate
CFRunLoopIsWaiting
CFRunLoopSourceGetOrder
CFRunLoopSourceIsValid
CFRunLoopSourceGetTypeID
CFRunLoopTimerDoesRepeat
CFRunLoopTimerGetInterval
CFRunLoopTimerGetNextFireDate
CFRunLoopTimerGetOrder
CFRunLoopTimerGetTolerance
CFRunLoopTimerIsValid
CFRunLoopTimerSetTolerance
CFRunLoopTimerGetTypeID
CFSocketGetTypeID
CFSocketCopyAddress
CFSocketCopyPeerAddress
CFSocketDisableCallBacks
CFSocketEnableCallBacks
CFSocketGetDefaultNameRegistryPortNumber
CFSocketGetSocketFlags
CFSocketIsValid
CFSocketSendData
CFSocketSetAddress
CFSocketSetDefaultNameRegistryPortNumber
CFSocketSetSocketFlags
__CFRangeMake
EOF

if [ ! -f "$FRAMEWORK" ] || [ ! -f "$SDK_STUB" ]; then
    echo "CoreFoundation guest image or iOS 10.3 SDK stub is missing" >&2
    exit 1
fi

LC_ALL=C sort -u "$work/expected" -o "$work/expected"
xcrun nm -gjU "$SDK_STUB" 2>/dev/null | sed 's/^_//' | LC_ALL=C sort -u \
    > "$work/sdk"
xcrun nm -gjU "$FRAMEWORK" | sed 's/^_//' | LC_ALL=C sort -u \
    > "$work/actual"

comm -23 "$work/expected" "$work/sdk" > "$work/not-in-sdk"
if [ -s "$work/not-in-sdk" ]; then
    echo "CoreFoundation shortlist symbols are not public in iOS 10.3:" >&2
    sed 's/^/  /' "$work/not-in-sdk" >&2
    exit 1
fi

comm -23 "$work/expected" "$work/actual" > "$work/missing"
if [ -s "$work/missing" ]; then
    echo "CoreFoundation guest image is missing shortlist symbols:" >&2
    sed 's/^/  /' "$work/missing" >&2
    exit 1
fi

expected_count=$(wc -l < "$work/expected" | tr -d ' ')
if [ "$expected_count" -ne 135 ]; then
    echo "CoreFoundation shortlist baseline changed: expected 135, got $expected_count" >&2
    exit 1
fi

echo "CoreFoundation low-risk symbol audit: PASS ($expected_count exports)"
