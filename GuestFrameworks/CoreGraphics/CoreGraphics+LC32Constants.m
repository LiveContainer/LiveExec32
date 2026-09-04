#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation+LC32.h>

/*
 * These CFString constants are toll-free bridged objects.  Backing them with
 * native CoreGraphics objects preserves values such as color-space names and
 * PDF dictionary keys without exposing a host pointer to ARM32 code.
 */
#define LC32_COREGRAPHICS_PUBLIC_STRING_CONSTANTS(X) \
    X(kCGColorConversionBlackPointCompensation) \
    X(kCGColorSpaceACESCGLinear) \
    X(kCGColorSpaceAdobeRGB1998) \
    X(kCGColorSpaceDCIP3) \
    X(kCGColorSpaceDisplayP3) \
    X(kCGColorSpaceExtendedGray) \
    X(kCGColorSpaceExtendedLinearGray) \
    X(kCGColorSpaceExtendedLinearSRGB) \
    X(kCGColorSpaceExtendedSRGB) \
    X(kCGColorSpaceGenericCMYK) \
    X(kCGColorSpaceGenericGray) \
    X(kCGColorSpaceGenericGrayGamma2_2) \
    X(kCGColorSpaceGenericRGB) \
    X(kCGColorSpaceGenericRGBLinear) \
    X(kCGColorSpaceGenericXYZ) \
    X(kCGColorSpaceITUR_2020) \
    X(kCGColorSpaceITUR_709) \
    X(kCGColorSpaceLinearGray) \
    X(kCGColorSpaceLinearSRGB) \
    X(kCGColorSpaceROMMRGB) \
    X(kCGColorSpaceSRGB) \
    X(kCGFontVariationAxisDefaultValue) \
    X(kCGFontVariationAxisMaxValue) \
    X(kCGFontVariationAxisMinValue) \
    X(kCGFontVariationAxisName) \
    X(kCGPDFContextAllowsCopying) \
    X(kCGPDFContextAllowsPrinting) \
    X(kCGPDFContextArtBox) \
    X(kCGPDFContextAuthor) \
    X(kCGPDFContextBleedBox) \
    X(kCGPDFContextCreator) \
    X(kCGPDFContextCropBox) \
    X(kCGPDFContextEncryptionKeyLength) \
    X(kCGPDFContextKeywords) \
    X(kCGPDFContextMediaBox) \
    X(kCGPDFContextOwnerPassword) \
    X(kCGPDFContextSubject) \
    X(kCGPDFContextTitle) \
    X(kCGPDFContextTrimBox) \
    X(kCGPDFContextUserPassword)

#define LC32_DECLARE_COREGRAPHICS_CONSTANT(name) \
    LC32_CONST_STR_DECL(const CFStringRef name)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-pointer-types"
LC32_COREGRAPHICS_PUBLIC_STRING_CONSTANTS(
    LC32_DECLARE_COREGRAPHICS_CONSTANT)
#pragma clang diagnostic pop
#undef LC32_DECLARE_COREGRAPHICS_CONSTANT

__attribute__((constructor))
static void LC32InitializeCoreGraphicsPublicConstants(void) {
#define LC32_INITIALIZE_COREGRAPHICS_CONSTANT(name) LC32_CONST_STR_INIT(name);
    LC32_COREGRAPHICS_PUBLIC_STRING_CONSTANTS(
        LC32_INITIALIZE_COREGRAPHICS_CONSTANT)
#undef LC32_INITIALIZE_COREGRAPHICS_CONSTANT
}
