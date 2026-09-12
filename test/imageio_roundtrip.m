#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef LC32_IMAGEIO_NATIVE_CHECK
_Static_assert(sizeof(void *) == 4, "ImageIO must work with ARM32 references");
#endif

static int failures;

static void check(const char *name, BOOL passed) {
    printf("imageio-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static BOOL containsPNG(CFArrayRef types) {
    return types && CFArrayContainsValue(types,
        CFRangeMake(0, CFArrayGetCount(types)), CFSTR("public.png"));
}

static BOOL hasDimensions(CGImageRef image, size_t width, size_t height) {
    return image && CGImageGetWidth(image) == width &&
        CGImageGetHeight(image) == height;
}

static BOOL hasExpectedPixels(CGImageRef image) {
    if(!image) return NO;
    UInt8 pixels[8] = {0};
    const UInt8 expected[] = {255, 0, 0, 255, 0, 255, 0, 255};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 2, 1, 8, 8, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    BOOL matches = NO;
    if(context) {
        CGContextDrawImage(context, CGRectMake(0, 0, 2, 1), image);
        const void *decoded = CGBitmapContextGetData(context);
        matches = decoded && memcmp(decoded, expected, sizeof(expected)) == 0;
        CGContextRelease(context);
    }
    if(space) CGColorSpaceRelease(space);
    return matches;
}

static void checkSource(CGImageSourceRef source) {
    check("source-type-id", source &&
        CFGetTypeID(source) == CGImageSourceGetTypeID());
    if(!source) return;
    check("source-count", CGImageSourceGetCount(source) == 1);
    CFStringRef type = CGImageSourceGetType(source);
    check("source-type", type && CFEqual(type, CFSTR("public.png")));
    check("source-status", CGImageSourceGetStatus(source) == kCGImageStatusComplete);
    check("source-index-status", CGImageSourceGetStatusAtIndex(source, 0) ==
        kCGImageStatusComplete);

    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
    check("image-properties", properties &&
        [[(NSDictionary *)properties objectForKey:(id)kCGImagePropertyPixelWidth]
            intValue] == 2 &&
        [[(NSDictionary *)properties objectForKey:(id)kCGImagePropertyPixelHeight]
            intValue] == 1);
    if(properties) CFRelease(properties);
    properties = CGImageSourceCopyProperties(source, NULL);
    check("source-properties", properties != NULL);
    if(properties) CFRelease(properties);

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    check("decode-dimensions", hasDimensions(image, 2, 1));
    check("decode-pixels", hasExpectedPixels(image));
    if(image) CGImageRelease(image);
    CGImageSourceRemoveCacheAtIndex(source, 0);
    image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    check("decode-after-cache-removal", hasExpectedPixels(image));
    if(image) CGImageRelease(image);
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @1,
    };
    image = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
    check("thumbnail", hasDimensions(image, 1, 1));
    if(image) CGImageRelease(image);
}

static void checkIncremental(CFDataRef data) {
    CGImageSourceRef source = CGImageSourceCreateIncremental(NULL);
    check("incremental-create", source != NULL);
    if(!source) return;
    CFDataRef prefix = CFDataCreate(kCFAllocatorDefault, CFDataGetBytePtr(data), 8);
    CGImageSourceUpdateData(source, prefix, false);
    check("incremental-incomplete", CGImageSourceGetStatus(source) <
        kCGImageStatusComplete);
    CFRelease(prefix);
    CGImageSourceUpdateData(source, data, true);
    check("incremental-complete", CGImageSourceGetStatus(source) ==
        kCGImageStatusComplete && CGImageSourceGetCount(source) == 1);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    check("incremental-decode", hasDimensions(image, 2, 1));
    if(image) CGImageRelease(image);
    CFRelease(source);

    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    source = provider ? CGImageSourceCreateWithDataProvider(provider, NULL) : NULL;
    check("provider-source", source && CGImageSourceGetCount(source) == 1);
    if(source) CFRelease(source);
    source = CGImageSourceCreateIncremental(NULL);
    if(source && provider) CGImageSourceUpdateDataProvider(source, provider, true);
    check("incremental-provider", source && provider &&
        CGImageSourceGetStatus(source) == kCGImageStatusComplete &&
        CGImageSourceGetCount(source) == 1);
    if(source) CFRelease(source);
    if(provider) CGDataProviderRelease(provider);
}

static void checkURL(CGImageSourceRef source) {
    NSString *template = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"lc32-imageio-XXXXXX"];
    char *path = strdup([template fileSystemRepresentation]);
    int descriptor = path ? mkstemp(path) : -1;
    check("url-temp-file", descriptor >= 0);
    if(descriptor < 0) { free(path); return; }
    close(descriptor);
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
        (const UInt8 *)path, strlen(path), false);
    CGImageDestinationRef destination = url ? CGImageDestinationCreateWithURL(
        url, CFSTR("public.png"), 1, NULL) : NULL;
    check("url-destination", destination != NULL);
    if(destination) {
        CGImageDestinationAddImageFromSource(destination, source, 0, NULL);
        check("url-finalize", CGImageDestinationFinalize(destination));
        CFRelease(destination);
    }
    CGImageSourceRef copied = url ? CGImageSourceCreateWithURL(url, NULL) : NULL;
    check("url-source", copied && CGImageSourceGetCount(copied) == 1);
    CGImageRef image = copied ? CGImageSourceCreateImageAtIndex(copied, 0, NULL) : NULL;
    check("url-image", hasDimensions(image, 2, 1));
    if(image) CGImageRelease(image);
    if(copied) CFRelease(copied);
    if(url) CFRelease(url);
    check("url-cleanup", unlink(path) == 0);
    free(path);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    CFArrayRef sourceTypes = CGImageSourceCopyTypeIdentifiers();
    CFArrayRef destinationTypes = CGImageDestinationCopyTypeIdentifiers();
    check("source-formats", containsPNG(sourceTypes));
    check("destination-formats", containsPNG(destinationTypes));
    if(sourceTypes) CFRelease(sourceTypes);
    if(destinationTypes) CFRelease(destinationTypes);

    UInt8 pixels[] = {255, 0, 0, 255, 0, 255, 0, 255};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 2, 1, 8, 8, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGImageRef image = context ? CGBitmapContextCreateImage(context) : NULL;
    check("input-image", hasDimensions(image, 2, 1));
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    CGImageDestinationRef destination = data ? CGImageDestinationCreateWithData(
        data, CFSTR("public.png"), 1, NULL) : NULL;
    check("destination-type-id", destination &&
        CFGetTypeID(destination) == CGImageDestinationGetTypeID());
    BOOL finalized = NO;
    if(destination && image) {
        CGImageDestinationSetProperties(destination,
            (CFDictionaryRef)[NSDictionary dictionary]);
        CGImageDestinationAddImage(destination, image, NULL);
        finalized = CGImageDestinationFinalize(destination);
        check("memory-finalize", finalized);
    }
    // Release the destination first: it must neither invalidate the caller's
    // mutable data nor leave the encoded bytes only in host-private storage.
    if(destination) CFRelease(destination);
    check("encoded-data-visible", finalized && data && CFDataGetLength(data) > 8);
    if(finalized && data && CFDataGetLength(data) > 8) {
        CGImageSourceRef source = CGImageSourceCreateWithData(data, NULL);
        checkSource(source);
        checkIncremental(data);
        if(source) { checkURL(source); CFRelease(source); }
    }
    if(data) CFRelease(data);
    if(image) CGImageRelease(image);
    if(context) CGContextRelease(context);
    if(space) CGColorSpaceRelease(space);
    [pool drain];
    return failures != 0;
}
