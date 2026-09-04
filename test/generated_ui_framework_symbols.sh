#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
FRAMEWORK_DIR=${GUEST_FRAMEWORK_DIR:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s"}

WORK_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-ui-symbols.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

TOTAL=0

audit_framework() {
    framework=$1
    expected_count=$2
    image="$FRAMEWORK_DIR/$framework.framework/$framework"
    if [ ! -f "$image" ]; then
        echo "$framework guest framework is missing: $image" >&2
        exit 1
    fi

    sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u \
        > "$WORK_DIR/$framework.expected"
    count=$(wc -l < "$WORK_DIR/$framework.expected" | tr -d ' ')
    if [ "$count" -ne "$expected_count" ]; then
        echo "$framework audit manifest has $count symbols; expected $expected_count" >&2
        exit 1
    fi

    xcrun nm -gjU "$image" | sed 's/^_//' | LC_ALL=C sort -u \
        > "$WORK_DIR/$framework.actual"
    comm -23 "$WORK_DIR/$framework.expected" \
        "$WORK_DIR/$framework.actual" > "$WORK_DIR/$framework.missing"
    if [ -s "$WORK_DIR/$framework.missing" ]; then
        echo "$framework is missing public guest symbols:" >&2
        sed 's/^/  /' "$WORK_DIR/$framework.missing" >&2
        exit 1
    fi

    TOTAL=$((TOTAL + count))
    echo "$framework public symbol audit: PASS ($count exports)"
}

audit_framework MapKit 33 <<'EOF'
MKAnnotationCalloutInfoDidChangeNotification
MKCoordinateForMapPoint
MKCoordinateRegionForMapRect
MKCoordinateRegionMakeWithDistance
MKErrorDomain
MKLaunchOptionsCameraKey
MKLaunchOptionsDirectionsModeDefault
MKLaunchOptionsDirectionsModeDriving
MKLaunchOptionsDirectionsModeKey
MKLaunchOptionsDirectionsModeTransit
MKLaunchOptionsDirectionsModeWalking
MKLaunchOptionsMapCenterKey
MKLaunchOptionsMapSpanKey
MKLaunchOptionsMapTypeKey
MKLaunchOptionsShowsTrafficKey
MKMapPointForCoordinate
MKMapPointsPerMeterAtLatitude
MKMapRectContainsPoint
MKMapRectContainsRect
MKMapRectDivide
MKMapRectInset
MKMapRectIntersection
MKMapRectIntersectsRect
MKMapRectNull
MKMapRectOffset
MKMapRectRemainder
MKMapRectSpans180thMeridian
MKMapRectUnion
MKMapRectWorld
MKMapSizeWorld
MKMetersBetweenMapPoints
MKMetersPerMapPointAtLatitude
MKRoadWidthAtZoomScale
EOF

audit_framework Photos 12 <<'EOF'
PHContentEditingInputCancelledKey
PHContentEditingInputErrorKey
PHContentEditingInputResultIsInCloudKey
PHImageCancelledKey
PHImageErrorKey
PHImageManagerMaximumSize
PHImageResultIsDegradedKey
PHImageResultIsInCloudKey
PHImageResultRequestIDKey
PHLivePhotoInfoCancelledKey
PHLivePhotoInfoErrorKey
PHLivePhotoInfoIsDegradedKey
EOF

audit_framework WebKit 13 <<'EOF'
WKErrorDomain
WKPreviewActionItemIdentifierAddToReadingList
WKPreviewActionItemIdentifierCopy
WKPreviewActionItemIdentifierOpen
WKPreviewActionItemIdentifierShare
WKWebsiteDataTypeCookies
WKWebsiteDataTypeDiskCache
WKWebsiteDataTypeIndexedDBDatabases
WKWebsiteDataTypeLocalStorage
WKWebsiteDataTypeMemoryCache
WKWebsiteDataTypeOfflineWebApplicationCache
WKWebsiteDataTypeSessionStorage
WKWebsiteDataTypeWebSQLDatabases
EOF

audit_framework UserNotifications 7 <<'EOF'
UNErrorDomain
UNNotificationAttachmentOptionsThumbnailClippingRectKey
UNNotificationAttachmentOptionsThumbnailHiddenKey
UNNotificationAttachmentOptionsThumbnailTimeKey
UNNotificationAttachmentOptionsTypeHintKey
UNNotificationDefaultActionIdentifier
UNNotificationDismissActionIdentifier
EOF

audit_framework MessageUI 5 <<'EOF'
MFMailComposeErrorDomain
MFMessageComposeViewControllerAttachmentAlternateFilename
MFMessageComposeViewControllerAttachmentURL
MFMessageComposeViewControllerTextMessageAvailabilityDidChangeNotification
MFMessageComposeViewControllerTextMessageAvailabilityKey
EOF

audit_framework ExternalAccessory 5 <<'EOF'
EAAccessoryDidConnectNotification
EAAccessoryDidDisconnectNotification
EAAccessoryKey
EAAccessorySelectedKey
EABluetoothAccessoryPickerErrorDomain
EOF

audit_framework EventKit 2 <<'EOF'
EKErrorDomain
EKEventStoreChangedNotification
EOF

audit_framework GameController 8 <<'EOF'
GCGamepadSnapShotDataV100FromNSData
GCExtendedGamepadSnapShotDataV100FromNSData
GCMicroGamepadSnapShotDataV100FromNSData
GCControllerDidConnectNotification
GCControllerDidDisconnectNotification
NSDataFromGCGamepadSnapShotDataV100
NSDataFromGCExtendedGamepadSnapShotDataV100
NSDataFromGCMicroGamepadSnapShotDataV100
EOF

audit_framework WatchKit 1 <<'EOF'
WatchKitErrorDomain
EOF

audit_framework WatchConnectivity 1 <<'EOF'
WCErrorDomain
EOF

audit_framework CallKit 4 <<'EOF'
CXErrorDomain
CXErrorDomainCallDirectoryManager
CXErrorDomainIncomingCall
CXErrorDomainRequestTransaction
EOF

audit_framework SafariServices 3 <<'EOF'
SFContentBlockerErrorDomain
SFErrorDomain
SSReadingListErrorDomain
EOF

audit_framework VideoSubscriberAccount 7 <<'EOF'
VSAccountProviderAuthenticationSchemeSAML
VSCheckAccessOptionPrompt
VSErrorDomain
VSErrorInfoKeyAccountProviderResponse
VSErrorInfoKeySAMLResponse
VSErrorInfoKeySAMLResponseStatus
VSErrorInfoKeyUnsupportedProviderIdentifier
EOF

audit_framework AVKit 1 <<'EOF'
AVKitErrorDomain
EOF

audit_framework PassKit 22 <<'EOF'
PKEncryptionSchemeECC_V2
PKEncryptionSchemeRSA_V2
PKPassKitErrorDomain
PKPassLibraryAddedPassesUserInfoKey
PKPassLibraryDidChangeNotification
PKPassLibraryPassTypeIdentifierUserInfoKey
PKPassLibraryRemotePaymentPassesDidChangeNotification
PKPassLibraryRemovedPassInfosUserInfoKey
PKPassLibraryReplacementPassesUserInfoKey
PKPassLibrarySerialNumberUserInfoKey
PKPaymentNetworkAmex
PKPaymentNetworkCarteBancaire
PKPaymentNetworkChinaUnionPay
PKPaymentNetworkDiscover
PKPaymentNetworkIDCredit
PKPaymentNetworkInterac
PKPaymentNetworkJCB
PKPaymentNetworkMasterCard
PKPaymentNetworkPrivateLabel
PKPaymentNetworkQuicPay
PKPaymentNetworkSuica
PKPaymentNetworkVisa
EOF

audit_framework CoreMotion 1 <<'EOF'
CMErrorDomain
EOF

audit_framework LocalAuthentication 2 <<'EOF'
LAErrorDomain
LATouchIDAuthenticationMaximumAllowableReuseDuration
EOF

audit_framework Metal 3 <<'EOF'
MTLCommandBufferErrorDomain
MTLCreateSystemDefaultDevice
MTLLibraryErrorDomain
EOF

echo "Generated UI framework symbol audit: PASS ($TOTAL exports)"
