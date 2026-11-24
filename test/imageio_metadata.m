#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

static int failures;
static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
static void release(CFTypeRef object) { if(object) CFRelease(object); }

int main(void) {
    @autoreleasepool {
        CGMutableImageMetadataRef metadata = CGImageMetadataCreateMutable();
        check("metadata-create-typeid", metadata &&
            CFGetTypeID(metadata) == CGImageMetadataGetTypeID());
        if(!metadata) return 1;
        struct { uint32_t before; CFErrorRef error; uint32_t after; } guarded =
            {0x12345678, NULL, 0x76543210};
        bool registered = CGImageMetadataRegisterNamespaceForPrefix(metadata,
            CFSTR("https://example.test/lc32/"), CFSTR("lc32"), &guarded.error);
        check("metadata-namespace-error-slot", registered && !guarded.error &&
            guarded.before == 0x12345678 && guarded.after == 0x76543210);
        release(guarded.error); guarded.error = NULL;
        CGImageMetadataTagRef tag = CGImageMetadataTagCreate(
            CFSTR("https://example.test/lc32/"), CFSTR("lc32"), CFSTR("Title"),
            kCGImageMetadataTypeString, CFSTR("Legacy metadata"));
        check("metadata-tag-five-slot-create", tag && CFGetTypeID(tag) == CGImageMetadataTagGetTypeID() &&
            CGImageMetadataTagGetType(tag) == kCGImageMetadataTypeString);
        CFStringRef name = CGImageMetadataTagCopyName(tag);
        CFStringRef xmlns = CGImageMetadataTagCopyNamespace(tag);
        CFStringRef prefix = CGImageMetadataTagCopyPrefix(tag);
        CFTypeRef value = CGImageMetadataTagCopyValue(tag);
        CFArrayRef qualifiers = CGImageMetadataTagCopyQualifiers(tag);
        check("metadata-tag-copy-fields", name && xmlns && prefix && value &&
            CFEqual(name, CFSTR("Title")) && CFEqual(prefix, CFSTR("lc32")) &&
            CFEqual(xmlns, CFSTR("https://example.test/lc32/")) &&
            CFEqual(value, CFSTR("Legacy metadata")) &&
            (!qualifiers || CFGetTypeID(qualifiers) == CFArrayGetTypeID()));
        release(name); release(xmlns); release(prefix); release(value); release(qualifiers);
        check("metadata-set-tag", CGImageMetadataSetTagWithPath(metadata, NULL, CFSTR("lc32:Title"), tag));
        release(tag);
        check("metadata-set-value", CGImageMetadataSetValueWithPath(metadata, NULL,
            CFSTR("lc32:Title"), CFSTR("Updated")));
        CFStringRef text = CGImageMetadataCopyStringValueWithPath(metadata, NULL, CFSTR("lc32:Title"));
        CGImageMetadataTagRef copiedTag = CGImageMetadataCopyTagWithPath(metadata, NULL, CFSTR("lc32:Title"));
        CFArrayRef tags = CGImageMetadataCopyTags(metadata);
        check("metadata-copy-path-tags", text && CFEqual(text, CFSTR("Updated")) &&
            copiedTag && tags && CFArrayGetCount(tags) == 1);
        release(text); release(copiedTag); release(tags);
        CGMutableImageMetadataRef copied = CGImageMetadataCreateMutableCopy(metadata);
        check("metadata-independent-copy", copied && CGImageMetadataRemoveTagWithPath(copied, NULL, CFSTR("lc32:Title")));
        text = CGImageMetadataCopyStringValueWithPath(metadata, NULL, CFSTR("lc32:Title"));
        CFStringRef removed = CGImageMetadataCopyStringValueWithPath(copied, NULL, CFSTR("lc32:Title"));
        check("metadata-remove-isolation", text && !removed);
        release(text); release(removed); release(copied);
        check("metadata-property-map", CGImageMetadataSetValueMatchingImageProperty(metadata,
            kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment, CFSTR("LC32 roundtrip")));
        CGImageMetadataTagRef property = CGImageMetadataCopyTagMatchingImageProperty(metadata,
            kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment);
        value = property ? CGImageMetadataTagCopyValue(property) : NULL;
        check("metadata-property-copy", value && CFEqual(value, CFSTR("LC32 roundtrip")));
        release(value); release(property);
        CFDataRef xmp = CGImageMetadataCreateXMPData(metadata, NULL);
        CGImageMetadataRef parsed = xmp ? CGImageMetadataCreateFromXMPData(xmp) : NULL;
        release(xmp);
        text = parsed ? CGImageMetadataCopyStringValueWithPath(parsed, NULL, CFSTR("lc32:Title")) : NULL;
        check("metadata-xmp-roundtrip", text && CFEqual(text, CFSTR("Updated")));
        release(text); release(parsed);

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(NULL, 4, 4, 8, 16, space,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGContextSetRGBFillColor(bitmap, 1, 0, 0, 1);
        CGContextFillRect(bitmap, CGRectMake(0, 0, 4, 4));
        CGImageRef image = CGBitmapContextCreateImage(bitmap);
        CFMutableDataRef output = CFDataCreateMutable(NULL, 0);
        CGImageDestinationRef destination = CGImageDestinationCreateWithData(output, CFSTR("public.jpeg"), 1, NULL);
        // Warm the guest byte cache before native mutation; it must be invalidated.
        (void)CFDataGetBytePtr(output);
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, NULL);
        check("metadata-destination-finalize", CGImageDestinationFinalize(destination) && CFDataGetLength(output) > 0);
        release(destination);
        CGImageSourceRef source = CGImageSourceCreateWithData(output, NULL);
        parsed = source ? CGImageSourceCopyMetadataAtIndex(source, 0, NULL) : NULL;
        text = parsed ? CGImageMetadataCopyStringValueWithPath(parsed, NULL, CFSTR("lc32:Title")) : NULL;
        check("metadata-image-roundtrip", text && CFEqual(text, CFSTR("Updated")));
        release(text); release(parsed);
        CFMutableDataRef cloned = CFDataCreateMutable(NULL, 0);
        destination = CGImageDestinationCreateWithData(cloned, CFSTR("public.jpeg"), 1, NULL);
        (void)CFDataGetBytePtr(cloned);
        bool success = CGImageDestinationCopyImageSource(destination, source, NULL, &guarded.error);
        check("destination-copy-source-error-slot", success && !guarded.error &&
            guarded.before == 0x12345678 && guarded.after == 0x76543210 && CFDataGetLength(cloned) > 0);
        // CopyImageSource finalizes internally; calling Finalize again is invalid.
        CGImageSourceRef cloneSource = CGImageSourceCreateWithData(cloned, NULL);
        check("destination-copy-source-readable", cloneSource && CGImageSourceGetCount(cloneSource) == 1);
        release(guarded.error); release(cloneSource); release(destination); release(cloned);
        CFMutableDataRef invalidOutput = CFDataCreateMutable(NULL, 0);
        destination = CGImageDestinationCreateWithData(invalidOutput, CFSTR("public.jpeg"), 1, NULL);
        CGImageSourceRef incomplete = CGImageSourceCreateIncremental(NULL);
        guarded.error = NULL;
        success = CGImageDestinationCopyImageSource(destination, incomplete, NULL, &guarded.error);
        check("destination-copy-incomplete-source", !success &&
            (!guarded.error || CFGetTypeID(guarded.error) == CFErrorGetTypeID()) &&
            guarded.before == 0x12345678 && guarded.after == 0x76543210);
        release(guarded.error); release(incomplete); release(destination); release(invalidOutput);
        release(source); release(output); release(image); CGContextRelease(bitmap);
        CGColorSpaceRelease(space); release(metadata);
    }
    return failures;
}
