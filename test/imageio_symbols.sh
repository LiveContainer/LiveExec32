#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)
IMAGEIO_FRAMEWORK=${1:-"$REPO_ROOT/GuestMakefile/.theos/obj/armv7s/ImageIO.framework/ImageIO"}
IMAGEIO_SDK=${LC32_GUEST_SDK:-${SDKROOT:-"$REPO_ROOT/tmp/iPhoneOS10.3.sdk"}}
IMAGEIO_HEADERS="$IMAGEIO_SDK/System/Library/Frameworks/ImageIO.framework/Headers"
IMAGEIO_STUB="$IMAGEIO_SDK/System/Library/Frameworks/ImageIO.framework/ImageIO.tbd"

if [ ! -f "$IMAGEIO_FRAMEWORK" ] || [ ! -f "$IMAGEIO_STUB" ] ||
   [ ! -d "$IMAGEIO_HEADERS" ]; then
    echo "ImageIO guest image or iOS 10.3 SDK headers/stub are missing" >&2
    exit 1
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/private/tmp}/lc32-imageio-symbols.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

# Headers establish public strings and exclude __IPHONE_NA declarations.
# Both OpenEXRDictionary and OpenEXRAspectRatio are macOS-only in iOS 10.3
# headers; the latter nevertheless exists in the iOS SDK export list.
# Include kCFErrorDomainCGImageMetadata and nullability-qualified declarations,
# not just kCG-prefixed identifiers. Metadata keys cover the object bridge too.
perl -0777 -ne '
    s@/\*.*?\*/@@gs;
    s@//[^\n]*@@g;
    while(/\bIMAGEIO_EXTERN\s+const\s+CFStringRef\s+
           (?:(?:__nonnull|__nullable)\s+)?([A-Za-z_]\w*)([^;]*);/gx) {
        next if $2 =~ /\b__IPHONE_NA\b/;
        print "$1\n";
    }
' "$IMAGEIO_HEADERS/"*.h | LC_ALL=C sort -u > "$TEMP_ROOT/header-constants"
xcrun nm -arch armv7s -gjU "$IMAGEIO_STUB" |
    sed -n 's/^_//p' | LC_ALL=C sort -u > "$TEMP_ROOT/sdk"
comm -12 "$TEMP_ROOT/header-constants" "$TEMP_ROOT/sdk" > "$TEMP_ROOT/constants"

# Public source/destination and metadata entry points. Block-based metadata
# enumeration remains deferred. Provider/consumer arguments are
# existing CoreGraphics objects, not new ImageIO callback registrations.
functions='CGImageSourceGetTypeID
CGImageSourceCopyTypeIdentifiers
CGImageSourceCreateWithDataProvider
CGImageSourceCreateWithData
CGImageSourceCreateWithURL
CGImageSourceGetType
CGImageSourceGetCount
CGImageSourceCopyProperties
CGImageSourceCopyPropertiesAtIndex
CGImageSourceCreateImageAtIndex
CGImageSourceRemoveCacheAtIndex
CGImageSourceCreateThumbnailAtIndex
CGImageSourceCreateIncremental
CGImageSourceUpdateData
CGImageSourceUpdateDataProvider
CGImageSourceGetStatus
CGImageSourceGetStatusAtIndex
CGImageDestinationGetTypeID
CGImageDestinationCopyTypeIdentifiers
CGImageDestinationCreateWithDataConsumer
CGImageDestinationCreateWithData
CGImageDestinationCreateWithURL
CGImageDestinationSetProperties
CGImageDestinationAddImage
CGImageDestinationAddImageFromSource
CGImageDestinationFinalize
CGImageDestinationAddImageAndMetadata
CGImageDestinationCopyImageSource
CGImageMetadataCopyStringValueWithPath
CGImageMetadataCopyTagMatchingImageProperty
CGImageMetadataCopyTagWithPath
CGImageMetadataCopyTags
CGImageMetadataCreateFromXMPData
CGImageMetadataCreateMutable
CGImageMetadataCreateMutableCopy
CGImageMetadataCreateXMPData
CGImageMetadataGetTypeID
CGImageMetadataRegisterNamespaceForPrefix
CGImageMetadataRemoveTagWithPath
CGImageMetadataSetTagWithPath
CGImageMetadataSetValueMatchingImageProperty
CGImageMetadataSetValueWithPath
CGImageMetadataTagCopyName
CGImageMetadataTagCopyNamespace
CGImageMetadataTagCopyPrefix
CGImageMetadataTagCopyQualifiers
CGImageMetadataTagCopyValue
CGImageMetadataTagCreate
CGImageMetadataTagGetType
CGImageMetadataTagGetTypeID
CGImageSourceCopyMetadataAtIndex'
printf '%s\n' "$functions" | LC_ALL=C sort -u > "$TEMP_ROOT/functions"

perl -0777 -ne '
    s@/\*.*?\*/@@gs;
    s@//[^\n]*@@g;
    while(/\bIMAGEIO_EXTERN\s+[^;]+?\b(CGImage(?:Source|Destination|Metadata)\w+)\s*\(/g) {
        print "$1\n";
    }
' "$IMAGEIO_HEADERS/CGImageSource.h" "$IMAGEIO_HEADERS/CGImageDestination.h" \
    "$IMAGEIO_HEADERS/CGImageMetadata.h" |
    LC_ALL=C sort -u > "$TEMP_ROOT/header-functions"

for public_set in sdk header-functions; do
    comm -23 "$TEMP_ROOT/functions" "$TEMP_ROOT/$public_set" > "$TEMP_ROOT/not-public"
    if [ -s "$TEMP_ROOT/not-public" ]; then
        echo "ImageIO function shortlist is absent from iOS 10.3 $public_set:" >&2
        sed 's/^/  /' "$TEMP_ROOT/not-public" >&2
        exit 1
    fi
done

constant_count=$(awk 'END { print NR + 0 }' "$TEMP_ROOT/constants")
function_count=$(awk 'END { print NR + 0 }' "$TEMP_ROOT/functions")
if [ "$constant_count" -ne 367 ] || [ "$function_count" -ne 51 ]; then
    echo "ImageIO public baseline changed: expected 367 strings + 51 functions, " \
         "got $constant_count strings + $function_count functions" >&2
    exit 1
fi

LC_ALL=C sort -u "$TEMP_ROOT/constants" "$TEMP_ROOT/functions" > "$TEMP_ROOT/expected"
xcrun nm -gjU "$IMAGEIO_FRAMEWORK" |
    sed -n 's/^_//p' | LC_ALL=C sort -u > "$TEMP_ROOT/actual"
comm -23 "$TEMP_ROOT/expected" "$TEMP_ROOT/actual" > "$TEMP_ROOT/missing"
if [ -s "$TEMP_ROOT/missing" ]; then
    echo "ImageIO guest framework is missing public symbols:" >&2
    sed 's/^/  /' "$TEMP_ROOT/missing" >&2
    exit 1
fi

echo "ImageIO public symbol audit: PASS ($constant_count strings + $function_count functions)"
