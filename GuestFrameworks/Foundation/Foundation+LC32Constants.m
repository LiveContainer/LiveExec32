// Public Foundation data exports are not emitted by the generated Objective-C
// shims.  Keep an ARM32 object for each pointer-valued constant, then bind it
// to the corresponding native Foundation singleton.  This preserves exact
// native key identities when bridged dictionaries and notifications cross the
// guest/host boundary.

#import <Foundation/Foundation+LC32.h>

/* Exporting the legacy ABI necessarily references deprecated declarations. */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define LC32_FOUNDATION_OBJECT_CONSTANTS(X) \
    X(NSStringEncodingDetectionSuggestedEncodingsKey) \
    X(NSStringEncodingDetectionDisallowedEncodingsKey) \
    X(NSStringEncodingDetectionUseOnlySuggestedEncodingsKey) \
    X(NSStringEncodingDetectionAllowLossyKey) \
    X(NSStringEncodingDetectionFromWindowsKey) \
    X(NSStringEncodingDetectionLossySubstitutionKey) \
    X(NSStringEncodingDetectionLikelyLanguageKey) \
    X(NSCharacterConversionException) \
    X(NSProgressEstimatedTimeRemainingKey) \
    X(NSProgressThroughputKey) \
    X(NSProgressKindFile) \
    X(NSProgressFileOperationKindKey) \
    X(NSProgressFileOperationKindDownloading) \
    X(NSProgressFileOperationKindDecompressingAfterDownloading) \
    X(NSProgressFileOperationKindReceiving) \
    X(NSProgressFileOperationKindCopying) \
    X(NSProgressFileURLKey) \
    X(NSProgressFileTotalCountKey) \
    X(NSProgressFileCompletedCountKey) \
    X(NSBundleDidLoadNotification) \
    X(NSLoadedClasses) \
    X(NSBundleResourceRequestLowDiskSpaceNotification) \
    X(NSPersonNameComponentKey) \
    X(NSPersonNameComponentGivenName) \
    X(NSPersonNameComponentFamilyName) \
    X(NSPersonNameComponentMiddleName) \
    X(NSPersonNameComponentPrefix) \
    X(NSPersonNameComponentSuffix) \
    X(NSPersonNameComponentNickname) \
    X(NSPersonNameComponentDelimiter) \
    X(NSObjectInaccessibleException) \
    X(NSObjectNotAvailableException) \
    X(NSDestinationInvalidException) \
    X(NSPortTimeoutException) \
    X(NSInvalidSendPortException) \
    X(NSInvalidReceivePortException) \
    X(NSPortSendException) \
    X(NSPortReceiveException) \
    X(NSOldStyleException) \
    X(NSAssertionHandlerKey) \
    X(NSDecimalNumberExactnessException) \
    X(NSDecimalNumberOverflowException) \
    X(NSDecimalNumberUnderflowException) \
    X(NSDecimalNumberDivideByZeroException) \
    X(NSFileHandleOperationException) \
    X(NSFileHandleReadCompletionNotification) \
    X(NSFileHandleReadToEndOfFileCompletionNotification) \
    X(NSFileHandleConnectionAcceptedNotification) \
    X(NSFileHandleDataAvailableNotification) \
    X(NSFileHandleNotificationDataItem) \
    X(NSFileHandleNotificationFileHandleItem) \
    X(NSFileHandleNotificationMonitorModes) \
    X(NSURLFileScheme) \
    X(NSUbiquityIdentityDidChangeNotification) \
    X(NSUndefinedKeyException) \
    X(NSAverageKeyValueOperator) \
    X(NSCountKeyValueOperator) \
    X(NSDistinctUnionOfArraysKeyValueOperator) \
    X(NSDistinctUnionOfObjectsKeyValueOperator) \
    X(NSDistinctUnionOfSetsKeyValueOperator) \
    X(NSMaximumKeyValueOperator) \
    X(NSMinimumKeyValueOperator) \
    X(NSSumKeyValueOperator) \
    X(NSUnionOfArraysKeyValueOperator) \
    X(NSUnionOfObjectsKeyValueOperator) \
    X(NSUnionOfSetsKeyValueOperator) \
    X(NSInvalidArchiveOperationException) \
    X(NSInvalidUnarchiveOperationException) \
    X(NSKeyedArchiveRootObjectKey) \
    X(NSInvocationOperationVoidResultException) \
    X(NSInvocationOperationCancelledException) \
    X(NSPortDidBecomeInvalidNotification) \
    X(NSProcessInfoPowerStateDidChangeNotification) \
    X(NSTextCheckingNameKey) \
    X(NSTextCheckingJobTitleKey) \
    X(NSTextCheckingOrganizationKey) \
    X(NSTextCheckingStreetKey) \
    X(NSTextCheckingCityKey) \
    X(NSTextCheckingStateKey) \
    X(NSTextCheckingZIPKey) \
    X(NSTextCheckingCountryKey) \
    X(NSTextCheckingPhoneKey) \
    X(NSTextCheckingAirlineKey) \
    X(NSTextCheckingFlightKey) \
    X(NSStreamSocketSecurityLevelKey) \
    X(NSStreamSocketSecurityLevelNone) \
    X(NSStreamSocketSecurityLevelSSLv2) \
    X(NSStreamSocketSecurityLevelSSLv3) \
    X(NSStreamSocketSecurityLevelTLSv1) \
    X(NSStreamSocketSecurityLevelNegotiatedSSL) \
    X(NSStreamSOCKSProxyConfigurationKey) \
    X(NSStreamSOCKSProxyHostKey) \
    X(NSStreamSOCKSProxyPortKey) \
    X(NSStreamSOCKSProxyVersionKey) \
    X(NSStreamSOCKSProxyUserKey) \
    X(NSStreamSOCKSProxyPasswordKey) \
    X(NSStreamSOCKSProxyVersion4) \
    X(NSStreamSOCKSProxyVersion5) \
    X(NSStreamSocketSSLErrorDomain) \
    X(NSStreamSOCKSErrorDomain) \
    X(NSStreamNetworkServiceType) \
    X(NSStreamNetworkServiceTypeVoIP) \
    X(NSStreamNetworkServiceTypeVideo) \
    X(NSStreamNetworkServiceTypeBackground) \
    X(NSStreamNetworkServiceTypeVoice) \
    X(NSStreamNetworkServiceTypeCallSignaling) \
    X(NSWillBecomeMultiThreadedNotification) \
    X(NSDidBecomeSingleThreadedNotification) \
    X(NSThreadWillExitNotification) \
    X(NSErrorFailingURLStringKey) \
    X(NSURLErrorFailingURLPeerTrustErrorKey) \
    X(NSURLErrorBackgroundTaskCancelledReasonKey) \
    X(NSGlobalDomain) \
    X(NSArgumentDomain) \
    X(NSRegistrationDomain) \
    X(NSUserDefaultsSizeLimitExceededNotification) \
    X(NSUbiquitousUserDefaultsNoCloudAccountNotification) \
    X(NSUbiquitousUserDefaultsDidChangeAccountsNotification) \
    X(NSUbiquitousUserDefaultsCompletedInitialSyncNotification) \
    X(NSNegateBooleanTransformerName) \
    X(NSIsNilTransformerName) \
    X(NSIsNotNilTransformerName) \
    X(NSUnarchiveFromDataTransformerName) \
    X(NSKeyedUnarchiveFromDataTransformerName) \
    X(NSXMLParserErrorDomain) \
    X(NSExtensionItemsAndErrorsKey) \
    X(NSExtensionHostWillEnterForegroundNotification) \
    X(NSExtensionHostDidEnterBackgroundNotification) \
    X(NSExtensionHostWillResignActiveNotification) \
    X(NSExtensionHostDidBecomeActiveNotification) \
    X(NSItemProviderPreferredImageSizeKey) \
    X(NSExtensionJavaScriptPreprocessingResultsKey) \
    X(NSExtensionJavaScriptFinalizeArgumentKey) \
    X(NSItemProviderErrorDomain) \
    X(NSExtensionItemAttributedTitleKey) \
    X(NSExtensionItemAttributedContentTextKey) \
    X(NSExtensionItemAttachmentsKey) \
    X(NSLinguisticTagSchemeTokenType) \
    X(NSLinguisticTagSchemeLexicalClass) \
    X(NSLinguisticTagSchemeNameType) \
    X(NSLinguisticTagSchemeNameTypeOrLexicalClass) \
    X(NSLinguisticTagSchemeLemma) \
    X(NSLinguisticTagSchemeLanguage) \
    X(NSLinguisticTagSchemeScript) \
    X(NSLinguisticTagWord) \
    X(NSLinguisticTagPunctuation) \
    X(NSLinguisticTagWhitespace) \
    X(NSLinguisticTagOther) \
    X(NSLinguisticTagNoun) \
    X(NSLinguisticTagVerb) \
    X(NSLinguisticTagAdjective) \
    X(NSLinguisticTagAdverb) \
    X(NSLinguisticTagPronoun) \
    X(NSLinguisticTagDeterminer) \
    X(NSLinguisticTagParticle) \
    X(NSLinguisticTagPreposition) \
    X(NSLinguisticTagNumber) \
    X(NSLinguisticTagConjunction) \
    X(NSLinguisticTagInterjection) \
    X(NSLinguisticTagClassifier) \
    X(NSLinguisticTagIdiom) \
    X(NSLinguisticTagOtherWord) \
    X(NSLinguisticTagSentenceTerminator) \
    X(NSLinguisticTagOpenQuote) \
    X(NSLinguisticTagCloseQuote) \
    X(NSLinguisticTagOpenParenthesis) \
    X(NSLinguisticTagCloseParenthesis) \
    X(NSLinguisticTagWordJoiner) \
    X(NSLinguisticTagDash) \
    X(NSLinguisticTagOtherPunctuation) \
    X(NSLinguisticTagParagraphBreak) \
    X(NSLinguisticTagOtherWhitespace) \
    X(NSLinguisticTagPersonalName) \
    X(NSLinguisticTagPlaceName) \
    X(NSLinguisticTagOrganizationName) \
    X(NSMetadataItemFSNameKey) \
    X(NSMetadataItemDisplayNameKey) \
    X(NSMetadataItemURLKey) \
    X(NSMetadataItemPathKey) \
    X(NSMetadataItemFSSizeKey) \
    X(NSMetadataItemFSCreationDateKey) \
    X(NSMetadataItemFSContentChangeDateKey) \
    X(NSMetadataItemContentTypeKey) \
    X(NSMetadataItemContentTypeTreeKey) \
    X(NSMetadataItemIsUbiquitousKey) \
    X(NSMetadataUbiquitousItemHasUnresolvedConflictsKey) \
    X(NSMetadataUbiquitousItemIsDownloadedKey) \
    X(NSMetadataUbiquitousItemDownloadingStatusKey) \
    X(NSMetadataUbiquitousItemDownloadingStatusNotDownloaded) \
    X(NSMetadataUbiquitousItemDownloadingStatusDownloaded) \
    X(NSMetadataUbiquitousItemDownloadingStatusCurrent) \
    X(NSMetadataUbiquitousItemIsDownloadingKey) \
    X(NSMetadataUbiquitousItemIsUploadedKey) \
    X(NSMetadataUbiquitousItemIsUploadingKey) \
    X(NSMetadataUbiquitousItemPercentDownloadedKey) \
    X(NSMetadataUbiquitousItemPercentUploadedKey) \
    X(NSMetadataUbiquitousItemDownloadingErrorKey) \
    X(NSMetadataUbiquitousItemUploadingErrorKey) \
    X(NSMetadataUbiquitousItemDownloadRequestedKey) \
    X(NSMetadataUbiquitousItemIsExternalDocumentKey) \
    X(NSMetadataUbiquitousItemContainerDisplayNameKey) \
    X(NSMetadataUbiquitousItemURLInLocalContainerKey) \
    X(NSMetadataQueryDidStartGatheringNotification) \
    X(NSMetadataQueryGatheringProgressNotification) \
    X(NSMetadataQueryDidFinishGatheringNotification) \
    X(NSMetadataQueryDidUpdateNotification) \
    X(NSMetadataQueryUpdateAddedItemsKey) \
    X(NSMetadataQueryUpdateChangedItemsKey) \
    X(NSMetadataQueryUpdateRemovedItemsKey) \
    X(NSMetadataQueryResultContentRelevanceAttribute) \
    X(NSMetadataQueryUbiquitousDocumentsScope) \
    X(NSMetadataQueryUbiquitousDataScope) \
    X(NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope) \
    X(NSUbiquitousKeyValueStoreChangedKeysKey) \
    X(NSUndoManagerGroupIsDiscardableKey) \
    X(NSUndoManagerCheckpointNotification) \
    X(NSUndoManagerWillUndoChangeNotification) \
    X(NSUndoManagerWillRedoChangeNotification) \
    X(NSUndoManagerDidUndoChangeNotification) \
    X(NSUndoManagerDidRedoChangeNotification) \
    X(NSUndoManagerDidOpenUndoGroupNotification) \
    X(NSUndoManagerWillCloseUndoGroupNotification) \
    X(NSUndoManagerDidCloseUndoGroupNotification)

#define LC32_DECLARE_FOUNDATION_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(__typeof__(name) name)
LC32_FOUNDATION_OBJECT_CONSTANTS(LC32_DECLARE_FOUNDATION_OBJECT_CONSTANT)
#undef LC32_DECLARE_FOUNDATION_OBJECT_CONSTANT

const double NSBundleResourceRequestLoadingPriorityUrgent = 1.0;

__attribute__((constructor))
static void LC32InitializeFoundationObjectConstants(void) {
#define LC32_INITIALIZE_FOUNDATION_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_INIT(name);
    LC32_FOUNDATION_OBJECT_CONSTANTS(
        LC32_INITIALIZE_FOUNDATION_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_FOUNDATION_OBJECT_CONSTANT
}

#undef LC32_FOUNDATION_OBJECT_CONSTANTS
