#import <UIKit/UIKit.h>
#import <Foundation/Foundation+LC32.h>

#include <float.h>
#include <math.h>

/*
 * UIKit remains loaded by the host runtime for every guest application.
 * Export stable ARM32 proxy objects and bind them to UIKit's canonical host
 * values so old applications can use notification names, dictionary keys,
 * text styles, and other public object constants without copying host
 * pointers into guest memory.
 */
extern int __CFConstantStringClassReference[];

#define LC32_UIKIT_PUBLIC_OBJECT_CONSTANTS(X) \
    X(NSAttachmentAttributeName) \
    X(NSBackgroundColorAttributeName) \
    X(NSBackgroundColorDocumentAttribute) \
    X(NSBaselineOffsetAttributeName) \
    X(NSCharacterEncodingDocumentAttribute) \
    X(NSDefaultAttributesDocumentAttribute) \
    X(NSDefaultTabIntervalDocumentAttribute) \
    X(NSDocumentTypeDocumentAttribute) \
    X(NSExpansionAttributeName) \
    X(NSFontAttributeName) \
    X(NSForegroundColorAttributeName) \
    X(NSHTMLTextDocumentType) \
    X(NSHyphenationFactorDocumentAttribute) \
    X(NSKernAttributeName) \
    X(NSLigatureAttributeName) \
    X(NSLinkAttributeName) \
    X(NSObliquenessAttributeName) \
    X(NSPaperMarginDocumentAttribute) \
    X(NSPaperSizeDocumentAttribute) \
    X(NSParagraphStyleAttributeName) \
    X(NSPlainTextDocumentType) \
    X(NSRTFDTextDocumentType) \
    X(NSRTFTextDocumentType) \
    X(NSReadOnlyDocumentAttribute) \
    X(NSShadowAttributeName) \
    X(NSStrikethroughColorAttributeName) \
    X(NSStrikethroughStyleAttributeName) \
    X(NSStrokeColorAttributeName) \
    X(NSStrokeWidthAttributeName) \
    X(NSTabColumnTerminatorsAttributeName) \
    X(NSTextEffectAttributeName) \
    X(NSTextEffectLetterpressStyle) \
    X(NSTextLayoutSectionOrientation) \
    X(NSTextLayoutSectionRange) \
    X(NSTextLayoutSectionsAttribute) \
    X(NSTextStorageDidProcessEditingNotification) \
    X(NSTextStorageWillProcessEditingNotification) \
    X(NSUnderlineColorAttributeName) \
    X(NSUnderlineStyleAttributeName) \
    X(NSUserActivityDocumentURLKey) \
    X(NSVerticalGlyphFormAttributeName) \
    X(NSViewModeDocumentAttribute) \
    X(NSViewSizeDocumentAttribute) \
    X(NSViewZoomDocumentAttribute) \
    X(NSWritingDirectionAttributeName) \
    X(UIAccessibilityAnnouncementDidFinishNotification) \
    X(UIAccessibilityAnnouncementKeyStringValue) \
    X(UIAccessibilityAnnouncementKeyWasSuccessful) \
    X(UIAccessibilityAssistiveTechnologyKey) \
    X(UIAccessibilityAssistiveTouchStatusDidChangeNotification) \
    X(UIAccessibilityBoldTextStatusDidChangeNotification) \
    X(UIAccessibilityClosedCaptioningStatusDidChangeNotification) \
    X(UIAccessibilityDarkerSystemColorsStatusDidChangeNotification) \
    X(UIAccessibilityElementFocusedNotification) \
    X(UIAccessibilityFocusedElementKey) \
    X(UIAccessibilityGrayscaleStatusDidChangeNotification) \
    X(UIAccessibilityGuidedAccessStatusDidChangeNotification) \
    X(UIAccessibilityHearingDevicePairedEarDidChangeNotification) \
    X(UIAccessibilityInvertColorsStatusDidChangeNotification) \
    X(UIAccessibilityMonoAudioStatusDidChangeNotification) \
    X(UIAccessibilityNotificationSwitchControlIdentifier) \
    X(UIAccessibilityNotificationVoiceOverIdentifier) \
    X(UIAccessibilityReduceMotionStatusDidChangeNotification) \
    X(UIAccessibilityReduceTransparencyStatusDidChangeNotification) \
    X(UIAccessibilityShakeToUndoDidChangeNotification) \
    X(UIAccessibilitySpeakScreenStatusDidChangeNotification) \
    X(UIAccessibilitySpeakSelectionStatusDidChangeNotification) \
    X(UIAccessibilitySpeechAttributeLanguage) \
    X(UIAccessibilitySpeechAttributePitch) \
    X(UIAccessibilitySpeechAttributePunctuation) \
    X(UIAccessibilitySwitchControlStatusDidChangeNotification) \
    X(UIAccessibilityUnfocusedElementKey) \
    X(UIAccessibilityVoiceOverStatusChanged) \
    X(UIActivityTypeAddToReadingList) \
    X(UIActivityTypeAirDrop) \
    X(UIActivityTypeAssignToContact) \
    X(UIActivityTypeCopyToPasteboard) \
    X(UIActivityTypeMail) \
    X(UIActivityTypeMessage) \
    X(UIActivityTypeOpenInIBooks) \
    X(UIActivityTypePostToFacebook) \
    X(UIActivityTypePostToFlickr) \
    X(UIActivityTypePostToTencentWeibo) \
    X(UIActivityTypePostToTwitter) \
    X(UIActivityTypePostToVimeo) \
    X(UIActivityTypePostToWeibo) \
    X(UIActivityTypePrint) \
    X(UIActivityTypeSaveToCameraRoll) \
    X(UIApplicationBackgroundRefreshStatusDidChangeNotification) \
    X(UIApplicationInvalidInterfaceOrientationException) \
    X(UIApplicationKeyboardExtensionPointIdentifier) \
    X(UIApplicationLaunchOptionsAnnotationKey) \
    X(UIApplicationLaunchOptionsBluetoothCentralsKey) \
    X(UIApplicationLaunchOptionsBluetoothPeripheralsKey) \
    X(UIApplicationLaunchOptionsCloudKitShareMetadataKey) \
    X(UIApplicationLaunchOptionsLocationKey) \
    X(UIApplicationLaunchOptionsNewsstandDownloadsKey) \
    X(UIApplicationLaunchOptionsShortcutItemKey) \
    X(UIApplicationLaunchOptionsSourceApplicationKey) \
    X(UIApplicationLaunchOptionsURLKey) \
    X(UIApplicationLaunchOptionsUserActivityDictionaryKey) \
    X(UIApplicationLaunchOptionsUserActivityTypeKey) \
    X(UIApplicationOpenSettingsURLString) \
    X(UIApplicationOpenURLOptionUniversalLinksOnly) \
    X(UIApplicationOpenURLOptionsAnnotationKey) \
    X(UIApplicationOpenURLOptionsOpenInPlaceKey) \
    X(UIApplicationOpenURLOptionsSourceApplicationKey) \
    X(UIApplicationStateRestorationBundleVersionKey) \
    X(UIApplicationStateRestorationSystemVersionKey) \
    X(UIApplicationStateRestorationTimestampKey) \
    X(UIApplicationStateRestorationUserInterfaceIdiomKey) \
    X(UIApplicationStatusBarFrameUserInfoKey) \
    X(UIApplicationUserDidTakeScreenshotNotification) \
    X(UIApplicationWillChangeStatusBarFrameNotification) \
    X(UICollectionElementKindSectionFooter) \
    X(UICollectionElementKindSectionHeader) \
    X(UIContentSizeCategoryAccessibilityExtraExtraExtraLarge) \
    X(UIContentSizeCategoryAccessibilityExtraExtraLarge) \
    X(UIContentSizeCategoryAccessibilityExtraLarge) \
    X(UIContentSizeCategoryAccessibilityLarge) \
    X(UIContentSizeCategoryAccessibilityMedium) \
    X(UIContentSizeCategoryDidChangeNotification) \
    X(UIContentSizeCategoryExtraExtraExtraLarge) \
    X(UIContentSizeCategoryExtraExtraLarge) \
    X(UIContentSizeCategoryExtraLarge) \
    X(UIContentSizeCategoryExtraSmall) \
    X(UIContentSizeCategoryLarge) \
    X(UIContentSizeCategoryMedium) \
    X(UIContentSizeCategoryNewValueKey) \
    X(UIContentSizeCategorySmall) \
    X(UIContentSizeCategoryUnspecified) \
    X(UIDeviceProximityStateDidChangeNotification) \
    X(UIDocumentStateChangedNotification) \
    X(UIFontDescriptorCascadeListAttribute) \
    X(UIFontDescriptorCharacterSetAttribute) \
    X(UIFontDescriptorFaceAttribute) \
    X(UIFontDescriptorFamilyAttribute) \
    X(UIFontDescriptorFeatureSettingsAttribute) \
    X(UIFontDescriptorFixedAdvanceAttribute) \
    X(UIFontDescriptorMatrixAttribute) \
    X(UIFontDescriptorNameAttribute) \
    X(UIFontDescriptorSizeAttribute) \
    X(UIFontDescriptorTextStyleAttribute) \
    X(UIFontDescriptorTraitsAttribute) \
    X(UIFontDescriptorVisibleNameAttribute) \
    X(UIFontFeatureSelectorIdentifierKey) \
    X(UIFontFeatureTypeIdentifierKey) \
    X(UIFontSlantTrait) \
    X(UIFontSymbolicTrait) \
    X(UIFontTextStyleBody) \
    X(UIFontTextStyleCallout) \
    X(UIFontTextStyleCaption1) \
    X(UIFontTextStyleCaption2) \
    X(UIFontTextStyleFootnote) \
    X(UIFontTextStyleHeadline) \
    X(UIFontTextStyleSubheadline) \
    X(UIFontTextStyleTitle1) \
    X(UIFontTextStyleTitle2) \
    X(UIFontTextStyleTitle3) \
    X(UIFontWeightTrait) \
    X(UIFontWidthTrait) \
    X(UIImagePickerControllerCropRect) \
    X(UIImagePickerControllerLivePhoto) \
    X(UIImagePickerControllerMediaMetadata) \
    X(UIImagePickerControllerReferenceURL) \
    X(UIKeyInputDownArrow) \
    X(UIKeyInputEscape) \
    X(UIKeyInputLeftArrow) \
    X(UIKeyInputRightArrow) \
    X(UIKeyInputUpArrow) \
    X(UIKeyboardCenterBeginUserInfoKey) \
    X(UIKeyboardCenterEndUserInfoKey) \
    X(UIKeyboardDidChangeFrameNotification) \
    X(UIKeyboardIsLocalUserInfoKey) \
    X(UIKeyboardWillChangeFrameNotification) \
    X(UIMenuControllerDidShowMenuNotification) \
    X(UIMenuControllerMenuFrameDidChangeNotification) \
    X(UIMenuControllerWillHideMenuNotification) \
    X(UIMenuControllerWillShowMenuNotification) \
    X(UINibExternalObjects) \
    X(UINibProxiedObjectsKey) \
    X(UIPageViewControllerOptionInterPageSpacingKey) \
    X(UIPageViewControllerOptionSpineLocationKey) \
    X(UIPasteboardChangedNotification) \
    X(UIPasteboardChangedTypesAddedKey) \
    X(UIPasteboardChangedTypesRemovedKey) \
    X(UIPasteboardNameFind) \
    X(UIPasteboardNameGeneral) \
    X(UIPasteboardOptionExpirationDate) \
    X(UIPasteboardOptionLocalOnly) \
    X(UIPasteboardRemovedNotification) \
    X(UIPasteboardTypeAutomatic) \
    X(UIPrintErrorDomain) \
    X(UIScreenBrightnessDidChangeNotification) \
    X(UIScreenModeDidChangeNotification) \
    X(UIStateRestorationViewControllerStoryboardKey) \
    X(UITableViewIndexSearch) \
    X(UITableViewSelectionDidChangeNotification) \
    X(UITextContentTypeAddressCity) \
    X(UITextContentTypeAddressCityAndState) \
    X(UITextContentTypeAddressState) \
    X(UITextContentTypeCountryName) \
    X(UITextContentTypeCreditCardNumber) \
    X(UITextContentTypeEmailAddress) \
    X(UITextContentTypeFamilyName) \
    X(UITextContentTypeFullStreetAddress) \
    X(UITextContentTypeGivenName) \
    X(UITextContentTypeJobTitle) \
    X(UITextContentTypeLocation) \
    X(UITextContentTypeMiddleName) \
    X(UITextContentTypeName) \
    X(UITextContentTypeNamePrefix) \
    X(UITextContentTypeNameSuffix) \
    X(UITextContentTypeNickname) \
    X(UITextContentTypeOrganizationName) \
    X(UITextContentTypePostalCode) \
    X(UITextContentTypeStreetAddressLine1) \
    X(UITextContentTypeStreetAddressLine2) \
    X(UITextContentTypeSublocality) \
    X(UITextContentTypeTelephoneNumber) \
    X(UITextContentTypeURL) \
    X(UITextFieldDidEndEditingReasonKey) \
    X(UITextFieldTextDidBeginEditingNotification) \
    X(UITextFieldTextDidEndEditingNotification) \
    X(UITextInputCurrentInputModeDidChangeNotification) \
    X(UITextInputTextBackgroundColorKey) \
    X(UITextInputTextColorKey) \
    X(UITextInputTextFontKey) \
    X(UITextViewTextDidBeginEditingNotification) \
    X(UITextViewTextDidEndEditingNotification) \
    X(UITransitionContextFromViewControllerKey) \
    X(UITransitionContextFromViewKey) \
    X(UITransitionContextToViewControllerKey) \
    X(UITransitionContextToViewKey) \
    X(UIUserNotificationActionResponseTypedTextKey) \
    X(UIUserNotificationTextInputActionButtonTitleKey) \
    X(UIViewControllerHierarchyInconsistencyException) \
    X(UIViewControllerShowDetailTargetDidChangeNotification) \
    X(UIWindowDidBecomeHiddenNotification) \
    X(UIWindowDidResignKeyNotification)

#define LC32_DECLARE_UIKIT_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_DECL(NSString *const name)
LC32_UIKIT_PUBLIC_OBJECT_CONSTANTS(LC32_DECLARE_UIKIT_OBJECT_CONSTANT)
#undef LC32_DECLARE_UIKIT_OBJECT_CONSTANT

/*
 * Unlike the string constants above, these exports are canonical NSArray
 * objects.  The same host-object proxy storage works for either Objective-C
 * type once LC32BindHostObjectConstant binds it to UIKit's native object.
 */
#define LC32_UIKIT_PUBLIC_ARRAY_CONSTANTS(X) \
    X(UIPasteboardTypeListColor) \
    X(UIPasteboardTypeListImage) \
    X(UIPasteboardTypeListString) \
    X(UIPasteboardTypeListURL)

#define LC32_DECLARE_UIKIT_ARRAY_CONSTANT(name) \
    LC32_CONST_STR_DECL(NSArray<NSString *> *name)
LC32_UIKIT_PUBLIC_ARRAY_CONSTANTS(LC32_DECLARE_UIKIT_ARRAY_CONSTANT)
#undef LC32_DECLARE_UIKIT_ARRAY_CONSTANT

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
__attribute__((constructor))
static void LC32InitializeUIKitPublicObjectConstants(void) {
#define LC32_INITIALIZE_UIKIT_OBJECT_CONSTANT(name) \
    LC32_CONST_STR_INIT(name);
    LC32_UIKIT_PUBLIC_OBJECT_CONSTANTS(
        LC32_INITIALIZE_UIKIT_OBJECT_CONSTANT)
    LC32_UIKIT_PUBLIC_ARRAY_CONSTANTS(
        LC32_INITIALIZE_UIKIT_OBJECT_CONSTANT)
#undef LC32_INITIALIZE_UIKIT_OBJECT_CONSTANT
}
#pragma clang diagnostic pop

/* Public scalar constants whose 32-bit representation differs from the
 * native arm64 storage cannot use object proxies. */
UIAccessibilityNotifications UIAccessibilityAnnouncementNotification = 1008;
UIAccessibilityNotifications UIAccessibilityPageScrolledNotification = 1009;
UIAccessibilityNotifications
    UIAccessibilityPauseAssistiveTechnologyNotification = 1033;
UIAccessibilityNotifications
    UIAccessibilityResumeAssistiveTechnologyNotification = 1034;
UIAccessibilityNotifications UIAccessibilityScreenChangedNotification = 1000;

UIAccessibilityTraits UIAccessibilityTraitLink = UINT64_C(0x2);
UIAccessibilityTraits UIAccessibilityTraitImage = UINT64_C(0x4);
UIAccessibilityTraits UIAccessibilityTraitPlaysSound = UINT64_C(0x10);
UIAccessibilityTraits UIAccessibilityTraitKeyboardKey = UINT64_C(0x20);
UIAccessibilityTraits UIAccessibilityTraitSummaryElement = UINT64_C(0x80);
UIAccessibilityTraits UIAccessibilityTraitNotEnabled = UINT64_C(0x100);
UIAccessibilityTraits UIAccessibilityTraitUpdatesFrequently = UINT64_C(0x200);
UIAccessibilityTraits UIAccessibilityTraitSearchField = UINT64_C(0x400);
UIAccessibilityTraits UIAccessibilityTraitStartsMediaSession = UINT64_C(0x800);
UIAccessibilityTraits UIAccessibilityTraitAdjustable = UINT64_C(0x1000);
UIAccessibilityTraits UIAccessibilityTraitAllowsDirectInteraction =
    UINT64_C(0x2000);
UIAccessibilityTraits UIAccessibilityTraitCausesPageTurn = UINT64_C(0x4000);
UIAccessibilityTraits UIAccessibilityTraitTabBar = UINT64_C(0x8000);
UIAccessibilityTraits UIAccessibilityTraitHeader = UINT64_C(0x10000);

const NSTimeInterval UIApplicationBackgroundFetchIntervalMinimum = 0.0;
const NSTimeInterval UIApplicationBackgroundFetchIntervalNever = DBL_MAX;
const NSTimeInterval UIMinimumKeepAliveTimeout = 600.0;

const CGSize UICollectionViewFlowLayoutAutomaticSize = {
    CGFLOAT_MAX, CGFLOAT_MAX
};
const CGSize UILayoutFittingCompressedSize = {0.0f, 0.0f};
const CGSize UILayoutFittingExpandedSize = {10000.0f, 10000.0f};
const UIFloatRange UIFloatRangeZero = {0.0f, 0.0f};
const UIFloatRange UIFloatRangeInfinite = {-INFINITY, INFINITY};

const CGFloat UIFontWeightUltraLight = -0.8f;
const CGFloat UIFontWeightThin = -0.6f;
const CGFloat UIFontWeightLight = -0.4f;
const CGFloat UIFontWeightRegular = 0.0f;
const CGFloat UIFontWeightMedium = 0.23f;
const CGFloat UIFontWeightSemibold = 0.3f;
const CGFloat UIFontWeightBold = 0.4f;
const CGFloat UIFontWeightHeavy = 0.56f;
const CGFloat UIFontWeightBlack = 0.62f;
const CGFloat UINavigationControllerHideShowBarDuration = 0.2f;
const CGFloat UISplitViewControllerAutomaticDimension = -CGFLOAT_MAX;
const CGFloat UITableViewAutomaticDimension = -1.0f;
const CGFloat UIViewNoIntrinsicMetric = -1.0f;
