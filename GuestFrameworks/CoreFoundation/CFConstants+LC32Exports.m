// Complete the public CoreFoundation data-symbol surface that is not emitted
// by the generated shims.  Pointer constants are distinct guest objects bound
// to the exact native constants, so their values remain correct even when a
// key's literal spelling differs from its exported symbol name.

#import <CoreFoundation/CoreFoundation+LC32.h>
#import <Foundation/Foundation+LC32.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define LC32_COREFOUNDATION_OBJECT_CONSTANTS(X) \
    X(kCFLocaleCurrentLocaleDidChangeNotification) \
    X(kCFLocaleIdentifier) \
    X(kCFLocaleLanguageCode) \
    X(kCFLocaleScriptCode) \
    X(kCFLocaleVariantCode) \
    X(kCFLocaleExemplarCharacterSet) \
    X(kCFLocaleCalendarIdentifier) \
    X(kCFLocaleCalendar) \
    X(kCFLocaleCollationIdentifier) \
    X(kCFLocaleUsesMetricSystem) \
    X(kCFLocaleMeasurementSystem) \
    X(kCFLocaleDecimalSeparator) \
    X(kCFLocaleGroupingSeparator) \
    X(kCFLocaleCurrencySymbol) \
    X(kCFLocaleCurrencyCode) \
    X(kCFLocaleCollatorIdentifier) \
    X(kCFLocaleQuotationBeginDelimiterKey) \
    X(kCFLocaleQuotationEndDelimiterKey) \
    X(kCFLocaleAlternateQuotationBeginDelimiterKey) \
    X(kCFLocaleAlternateQuotationEndDelimiterKey) \
    X(kCFBuddhistCalendar) \
    X(kCFChineseCalendar) \
    X(kCFHebrewCalendar) \
    X(kCFIslamicCalendar) \
    X(kCFIslamicCivilCalendar) \
    X(kCFJapaneseCalendar) \
    X(kCFRepublicOfChinaCalendar) \
    X(kCFPersianCalendar) \
    X(kCFIndianCalendar) \
    X(kCFISO8601Calendar) \
    X(kCFIslamicTabularCalendar) \
    X(kCFIslamicUmmAlQuraCalendar) \
    X(kCFStringTransformFullwidthHalfwidth) \
    X(kCFStringTransformLatinKatakana) \
    X(kCFStringTransformLatinHiragana) \
    X(kCFStringTransformHiraganaKatakana) \
    X(kCFStringTransformMandarinLatin) \
    X(kCFStringTransformLatinHangul) \
    X(kCFStringTransformLatinArabic) \
    X(kCFStringTransformLatinHebrew) \
    X(kCFStringTransformLatinThai) \
    X(kCFStringTransformLatinCyrillic) \
    X(kCFStringTransformLatinGreek) \
    X(kCFStringTransformToXMLHex) \
    X(kCFStringTransformToUnicodeName) \
    X(kCFStringTransformStripDiacritics) \
    X(kCFDateFormatterIsLenient) \
    X(kCFDateFormatterTimeZone) \
    X(kCFDateFormatterCalendarName) \
    X(kCFDateFormatterDefaultFormat) \
    X(kCFDateFormatterTwoDigitStartDate) \
    X(kCFDateFormatterDefaultDate) \
    X(kCFDateFormatterCalendar) \
    X(kCFDateFormatterEraSymbols) \
    X(kCFDateFormatterMonthSymbols) \
    X(kCFDateFormatterShortMonthSymbols) \
    X(kCFDateFormatterWeekdaySymbols) \
    X(kCFDateFormatterShortWeekdaySymbols) \
    X(kCFDateFormatterAMSymbol) \
    X(kCFDateFormatterPMSymbol) \
    X(kCFDateFormatterLongEraSymbols) \
    X(kCFDateFormatterVeryShortMonthSymbols) \
    X(kCFDateFormatterStandaloneMonthSymbols) \
    X(kCFDateFormatterShortStandaloneMonthSymbols) \
    X(kCFDateFormatterVeryShortStandaloneMonthSymbols) \
    X(kCFDateFormatterVeryShortWeekdaySymbols) \
    X(kCFDateFormatterStandaloneWeekdaySymbols) \
    X(kCFDateFormatterShortStandaloneWeekdaySymbols) \
    X(kCFDateFormatterVeryShortStandaloneWeekdaySymbols) \
    X(kCFDateFormatterQuarterSymbols) \
    X(kCFDateFormatterShortQuarterSymbols) \
    X(kCFDateFormatterStandaloneQuarterSymbols) \
    X(kCFDateFormatterShortStandaloneQuarterSymbols) \
    X(kCFDateFormatterGregorianStartDate) \
    X(kCFDateFormatterDoesRelativeDateFormattingKey) \
    X(kCFNumberFormatterCurrencyCode) \
    X(kCFNumberFormatterDecimalSeparator) \
    X(kCFNumberFormatterCurrencyDecimalSeparator) \
    X(kCFNumberFormatterAlwaysShowDecimalSeparator) \
    X(kCFNumberFormatterGroupingSeparator) \
    X(kCFNumberFormatterUseGroupingSeparator) \
    X(kCFNumberFormatterPercentSymbol) \
    X(kCFNumberFormatterZeroSymbol) \
    X(kCFNumberFormatterNaNSymbol) \
    X(kCFNumberFormatterInfinitySymbol) \
    X(kCFNumberFormatterMinusSign) \
    X(kCFNumberFormatterPlusSign) \
    X(kCFNumberFormatterCurrencySymbol) \
    X(kCFNumberFormatterExponentSymbol) \
    X(kCFNumberFormatterMinIntegerDigits) \
    X(kCFNumberFormatterMaxIntegerDigits) \
    X(kCFNumberFormatterMinFractionDigits) \
    X(kCFNumberFormatterMaxFractionDigits) \
    X(kCFNumberFormatterGroupingSize) \
    X(kCFNumberFormatterSecondaryGroupingSize) \
    X(kCFNumberFormatterRoundingMode) \
    X(kCFNumberFormatterRoundingIncrement) \
    X(kCFNumberFormatterFormatWidth) \
    X(kCFNumberFormatterPaddingPosition) \
    X(kCFNumberFormatterPaddingCharacter) \
    X(kCFNumberFormatterDefaultFormat) \
    X(kCFNumberFormatterMultiplier) \
    X(kCFNumberFormatterPositivePrefix) \
    X(kCFNumberFormatterPositiveSuffix) \
    X(kCFNumberFormatterNegativePrefix) \
    X(kCFNumberFormatterNegativeSuffix) \
    X(kCFNumberFormatterPerMillSymbol) \
    X(kCFNumberFormatterInternationalCurrencySymbol) \
    X(kCFNumberFormatterCurrencyGroupingSeparator) \
    X(kCFNumberFormatterIsLenient) \
    X(kCFNumberFormatterUseSignificantDigits) \
    X(kCFNumberFormatterMinSignificantDigits) \
    X(kCFNumberFormatterMaxSignificantDigits) \
    X(kCFURLKeysOfUnsetValuesKey) \
    X(kCFURLNameKey) \
    X(kCFURLLocalizedNameKey) \
    X(kCFURLIsRegularFileKey) \
    X(kCFURLIsDirectoryKey) \
    X(kCFURLIsSymbolicLinkKey) \
    X(kCFURLIsVolumeKey) \
    X(kCFURLIsPackageKey) \
    X(kCFURLIsApplicationKey) \
    X(kCFURLIsSystemImmutableKey) \
    X(kCFURLIsUserImmutableKey) \
    X(kCFURLIsHiddenKey) \
    X(kCFURLHasHiddenExtensionKey) \
    X(kCFURLCreationDateKey) \
    X(kCFURLContentAccessDateKey) \
    X(kCFURLContentModificationDateKey) \
    X(kCFURLAttributeModificationDateKey) \
    X(kCFURLLinkCountKey) \
    X(kCFURLParentDirectoryURLKey) \
    X(kCFURLVolumeURLKey) \
    X(kCFURLTypeIdentifierKey) \
    X(kCFURLLocalizedTypeDescriptionKey) \
    X(kCFURLLabelNumberKey) \
    X(kCFURLLabelColorKey) \
    X(kCFURLLocalizedLabelKey) \
    X(kCFURLEffectiveIconKey) \
    X(kCFURLCustomIconKey) \
    X(kCFURLFileResourceIdentifierKey) \
    X(kCFURLVolumeIdentifierKey) \
    X(kCFURLPreferredIOBlockSizeKey) \
    X(kCFURLIsReadableKey) \
    X(kCFURLIsWritableKey) \
    X(kCFURLIsExecutableKey) \
    X(kCFURLFileSecurityKey) \
    X(kCFURLPathKey) \
    X(kCFURLCanonicalPathKey) \
    X(kCFURLIsMountTriggerKey) \
    X(kCFURLGenerationIdentifierKey) \
    X(kCFURLDocumentIdentifierKey) \
    X(kCFURLAddedToDirectoryDateKey) \
    X(kCFURLFileResourceTypeKey) \
    X(kCFURLFileResourceTypeNamedPipe) \
    X(kCFURLFileResourceTypeCharacterSpecial) \
    X(kCFURLFileResourceTypeDirectory) \
    X(kCFURLFileResourceTypeBlockSpecial) \
    X(kCFURLFileResourceTypeRegular) \
    X(kCFURLFileResourceTypeSymbolicLink) \
    X(kCFURLFileResourceTypeSocket) \
    X(kCFURLFileResourceTypeUnknown) \
    X(kCFURLFileSizeKey) \
    X(kCFURLFileAllocatedSizeKey) \
    X(kCFURLTotalFileSizeKey) \
    X(kCFURLTotalFileAllocatedSizeKey) \
    X(kCFURLIsAliasFileKey) \
    X(kCFURLFileProtectionKey) \
    X(kCFURLFileProtectionNone) \
    X(kCFURLFileProtectionComplete) \
    X(kCFURLFileProtectionCompleteUnlessOpen) \
    X(kCFURLFileProtectionCompleteUntilFirstUserAuthentication) \
    X(kCFURLVolumeLocalizedFormatDescriptionKey) \
    X(kCFURLVolumeTotalCapacityKey) \
    X(kCFURLVolumeAvailableCapacityKey) \
    X(kCFURLVolumeResourceCountKey) \
    X(kCFURLVolumeSupportsPersistentIDsKey) \
    X(kCFURLVolumeSupportsSymbolicLinksKey) \
    X(kCFURLVolumeSupportsHardLinksKey) \
    X(kCFURLVolumeSupportsJournalingKey) \
    X(kCFURLVolumeIsJournalingKey) \
    X(kCFURLVolumeSupportsSparseFilesKey) \
    X(kCFURLVolumeSupportsZeroRunsKey) \
    X(kCFURLVolumeSupportsCaseSensitiveNamesKey) \
    X(kCFURLVolumeSupportsCasePreservedNamesKey) \
    X(kCFURLVolumeSupportsRootDirectoryDatesKey) \
    X(kCFURLVolumeSupportsVolumeSizesKey) \
    X(kCFURLVolumeSupportsRenamingKey) \
    X(kCFURLVolumeSupportsAdvisoryFileLockingKey) \
    X(kCFURLVolumeSupportsExtendedSecurityKey) \
    X(kCFURLVolumeIsBrowsableKey) \
    X(kCFURLVolumeMaximumFileSizeKey) \
    X(kCFURLVolumeIsEjectableKey) \
    X(kCFURLVolumeIsRemovableKey) \
    X(kCFURLVolumeIsInternalKey) \
    X(kCFURLVolumeIsAutomountedKey) \
    X(kCFURLVolumeIsLocalKey) \
    X(kCFURLVolumeIsReadOnlyKey) \
    X(kCFURLVolumeCreationDateKey) \
    X(kCFURLVolumeURLForRemountingKey) \
    X(kCFURLVolumeUUIDStringKey) \
    X(kCFURLVolumeNameKey) \
    X(kCFURLVolumeLocalizedNameKey) \
    X(kCFURLVolumeIsEncryptedKey) \
    X(kCFURLVolumeIsRootFileSystemKey) \
    X(kCFURLVolumeSupportsCompressionKey) \
    X(kCFURLVolumeSupportsFileCloningKey) \
    X(kCFURLVolumeSupportsSwapRenamingKey) \
    X(kCFURLVolumeSupportsExclusiveRenamingKey) \
    X(kCFURLIsUbiquitousItemKey) \
    X(kCFURLUbiquitousItemHasUnresolvedConflictsKey) \
    X(kCFURLUbiquitousItemIsDownloadedKey) \
    X(kCFURLUbiquitousItemIsDownloadingKey) \
    X(kCFURLUbiquitousItemIsUploadedKey) \
    X(kCFURLUbiquitousItemIsUploadingKey) \
    X(kCFURLUbiquitousItemPercentDownloadedKey) \
    X(kCFURLUbiquitousItemPercentUploadedKey) \
    X(kCFURLUbiquitousItemDownloadingStatusKey) \
    X(kCFURLUbiquitousItemDownloadingErrorKey) \
    X(kCFURLUbiquitousItemUploadingErrorKey) \
    X(kCFURLUbiquitousItemDownloadingStatusNotDownloaded) \
    X(kCFURLUbiquitousItemDownloadingStatusDownloaded) \
    X(kCFURLUbiquitousItemDownloadingStatusCurrent) \
    X(kCFSocketCommandKey) \
    X(kCFSocketNameKey) \
    X(kCFSocketValueKey) \
    X(kCFSocketResultKey) \
    X(kCFSocketErrorKey) \
    X(kCFSocketRegisterCommand) \
    X(kCFSocketRetrieveCommand) \
    X(kCFStreamPropertyAppendToFile) \
    X(kCFStreamPropertyFileCurrentOffset) \
    X(kCFStreamPropertySocketRemoteHostName) \
    X(kCFStreamPropertySocketRemotePortNumber) \
    X(kCFURLFileLength) \
    X(kCFURLFileLastModificationTime) \
    X(kCFURLFilePOSIXMode) \
    X(kCFURLFileOwnerID) \
    X(kCFURLHTTPStatusCode) \
    X(kCFURLHTTPStatusLine) \
    X(kCFPlugInDynamicRegistrationKey) \
    X(kCFPlugInDynamicRegisterFunctionKey) \
    X(kCFPlugInUnloadFunctionKey) \
    X(kCFPlugInFactoriesKey) \
    X(kCFPlugInTypesKey)

#define LC32_DECLARE_COREFOUNDATION_OBJECT_CONSTANT(name) \
    __typeof__(name) name = (__typeof__(name))(const void *) \
        &(LC32ConstantStringProxy){ \
            __CFConstantStringClassReference, 0x7c8, NULL, 0 \
        };
LC32_COREFOUNDATION_OBJECT_CONSTANTS(
    LC32_DECLARE_COREFOUNDATION_OBJECT_CONSTANT)
#undef LC32_DECLARE_COREFOUNDATION_OBJECT_CONSTANT

const CFTimeInterval kCFAbsoluteTimeIntervalSince1904 = 3061152000.0;

__attribute__((constructor))
static void LC32InitializeCoreFoundationExportedConstants(void) {
#define LC32_INITIALIZE_COREFOUNDATION_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_INIT(name);
    LC32_COREFOUNDATION_OBJECT_CONSTANTS(
        LC32_INITIALIZE_COREFOUNDATION_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_COREFOUNDATION_OBJECT_CONSTANT
}

#undef LC32_COREFOUNDATION_OBJECT_CONSTANTS
