#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>

#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>

/*
 * Attribute readback is intentionally optional.  This regression is for the
 * create entry point, while older LC32 CoreText builds do not export the
 * descriptor accessor yet.  When the accessor is present, exercise the
 * round trip without making it a link-time requirement.
 */
typedef CFDictionaryRef (*CopyAttributesFunction)(CTFontDescriptorRef);

static bool number_is_close_to(CFTypeRef value, double expected) {
    if(!value || CFGetTypeID(value) != CFNumberGetTypeID()) return false;

    double actual = 0;
    if(!CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &actual))
        return false;
    const double difference = actual - expected;
    return difference > -0.001 && difference < 0.001;
}

int main(void) {
    const double expectedSize = 19.25;
    bool createPassed = false;
    bool ownershipPassed = false;
    bool fontPassed = false;
    bool uiFontPassed = false;
    bool roundTripPassed = true;

    CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFStringRef family = CFStringCreateCopy(
        kCFAllocatorDefault, CFSTR("Helvetica"));
    CFNumberRef size = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberDoubleType, &expectedSize);

    if(attributes && family && size) {
        CFDictionarySetValue(
            attributes, kCTFontFamilyNameAttribute, family);
        CFDictionarySetValue(attributes, kCTFontSizeAttribute, size);
    }

    CTFontDescriptorRef descriptor = attributes && family && size
        ? CTFontDescriptorCreateWithAttributes(attributes)
        : NULL;
    /* The descriptor must own everything it needs after creation. */
    if(attributes) CFRelease(attributes);
    if(family) CFRelease(family);
    if(size) CFRelease(size);

    CTFontRef descriptorFont = descriptor
        ? CTFontCreateWithFontDescriptor(descriptor, 0, NULL) : NULL;
    CTFontRef uiFont = CTFontCreateUIFontForLanguage(
        kCTFontUIFontSystem, 0, NULL);

    createPassed = descriptor != NULL;
    printf("coretext-font-descriptor-create: %s\n",
        createPassed ? "PASS" : "FAIL");

    if(descriptor) {
        CFRetain(descriptor);
        CFRelease(descriptor);
        ownershipPassed = descriptorFont != NULL;
    }
    printf("coretext-font-descriptor-ownership: %s\n",
        ownershipPassed ? "PASS" : "FAIL");

    CopyAttributesFunction copyAttributes = (CopyAttributesFunction)dlsym(
        RTLD_DEFAULT, "CTFontDescriptorCopyAttributes");
    if(copyAttributes) {
        CFDictionaryRef copied = descriptor
            ? copyAttributes(descriptor) : NULL;
        CFTypeRef copiedFamily = copied ? CFDictionaryGetValue(
            copied, kCTFontFamilyNameAttribute) : NULL;
        CFTypeRef copiedSize = copied ? CFDictionaryGetValue(
            copied, kCTFontSizeAttribute) : NULL;
        roundTripPassed = copied && copiedFamily &&
            CFEqual(copiedFamily, CFSTR("Helvetica")) &&
            number_is_close_to(copiedSize, expectedSize);
        printf("coretext-font-descriptor-attribute-roundtrip: %s\n",
            roundTripPassed ? "PASS" : "FAIL");
        if(copied) CFRelease(copied);
    } else {
        printf("coretext-font-descriptor-attribute-roundtrip: "
            "SKIP (CTFontDescriptorCopyAttributes unavailable)\n");
    }

    if(descriptor) {
        CFRelease(descriptor);
        descriptor = NULL;
    }
    if(descriptorFont) {
        CFRetain(descriptorFont);
        CFRelease(descriptorFont);
        fontPassed = true;
    }
    printf("coretext-font-from-descriptor: %s\n",
        fontPassed ? "PASS" : "FAIL");

    if(uiFont) {
        CFRetain(uiFont);
        CFRelease(uiFont);
        uiFontPassed = true;
    }
    printf("coretext-ui-font: %s\n", uiFontPassed ? "PASS" : "FAIL");

    if(uiFont) CFRelease(uiFont);
    if(descriptorFont) CFRelease(descriptorFont);
    return !(createPassed && ownershipPassed && fontPassed && uiFontPassed &&
        roundTripPassed);
}
