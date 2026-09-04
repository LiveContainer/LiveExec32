#include <CoreFoundation/CoreFoundation.h>
#include <MobileCoreServices/UTCoreTypes.h>
#include <MobileCoreServices/UTType.h>

static int LC32StringsEqual(CFStringRef left, CFStringRef right) {
    return left && right &&
        CFStringCompare(left, right, 0) == kCFCompareEqualTo;
}

int main(void) {
    CFStringRef identifier = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension, CFSTR("JpEg"), NULL);
    if(!LC32StringsEqual(identifier, kUTTypeJPEG)) return 1;
    CFRelease(identifier);

    identifier = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassMIMEType, CFSTR("application/json"), kUTTypeText);
    if(!LC32StringsEqual(identifier, kUTTypeJSON)) return 2;
    CFRelease(identifier);

    if(!UTTypeConformsTo(kUTTypeJPEG, kUTTypeImage) ||
       !UTTypeConformsTo(kUTTypeJPEG, kUTTypeContent) ||
       UTTypeConformsTo(kUTTypeJPEG, kUTTypeAudio)) return 3;

    CFStringRef tag = UTTypeCopyPreferredTagWithClass(
        kUTTypePNG, kUTTagClassMIMEType);
    if(!LC32StringsEqual(tag, CFSTR("image/png"))) return 4;
    CFRelease(tag);

    CFArrayRef tags = UTTypeCopyAllTagsWithClass(
        kUTTypeJPEG, kUTTagClassFilenameExtension);
    if(!tags || CFArrayGetCount(tags) != 2) return 5;
    CFRelease(tags);

    CFDictionaryRef declaration = UTTypeCopyDeclaration(kUTTypePDF);
    if(!declaration || !LC32StringsEqual(
            (CFStringRef)CFDictionaryGetValue(
                declaration, kUTTypeIdentifierKey), kUTTypePDF)) return 6;
    CFRelease(declaration);

    if(!UTTypeIsDeclared(kUTTypeHTML) ||
       UTTypeIsDeclared(CFSTR("com.example.unknown")) ||
       !UTTypeIsDynamic(CFSTR("dyn.example"))) return 7;

    if(UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            CFSTR("definitely-unknown"), NULL) != NULL) return 8;

    return 0;
}
