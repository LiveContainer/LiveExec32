// Native property regression using the built host hook and real CAEAGLLayers.
// The storage sink avoids requiring a GPU context in command-line probes.
#define GLES_SILENCE_DEPRECATION 1
#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static unsigned failures;
static void check(const char *name, BOOL pass) {
    printf("drawable-properties-%s: %s\n", name, pass ? "PASS" : "FAIL");
    failures += !pass;
}

@interface LC32DrawableStorageSink : NSObject
@property(nonatomic) unsigned calls;
@end
@implementation LC32DrawableStorageSink
- (BOOL)lc32_renderbufferStorage:(NSUInteger)target fromDrawable:(id)drawable {
    (void)target;
    (void)drawable;
    ++self.calls;
    return YES;
}
@end

int main(int argc, char **argv) {
    if(argc < 2 || argc > 3) return 2;
    BOOL expectStale = argc == 3 && !strcmp(argv[2], "--expect-stale");
    @autoreleasepool {
        if(!dlopen(argv[1], RTLD_NOW | RTLD_LOCAL)) {
            fprintf(stderr, "dlopen: %s\n", dlerror());
            return 2;
        }
        SEL selector = @selector(renderbufferStorage:fromDrawable:);
        Method method = class_getInstanceMethod(EAGLContext.class, selector);
        BOOL (*storage)(id, SEL, NSUInteger, id) = (void *)method_getImplementation(method);
        LC32DrawableStorageSink *sink = [LC32DrawableStorageSink new];
        for(NSString *canonical in @[kEAGLColorFormatRGBA8, kEAGLColorFormatRGB565]) {
            CAEAGLLayer *layer = [CAEAGLLayer layer];
            NSString *dynamic = [NSMutableString stringWithString:canonical];
            layer.drawableProperties = @{kEAGLDrawablePropertyColorFormat:dynamic,
                @"test-unrelated-property":@"preserve-me"};
            check("distinct-equal-input", dynamic != canonical && [dynamic isEqual:canonical]);
            check("storage-forwarded", storage(sink, selector, 0x8d41, layer));
            id actual = layer.drawableProperties[kEAGLDrawablePropertyColorFormat];
            check("canonical-identity", expectStale ? actual == dynamic : actual == canonical);
            check("unrelated-property-preserved",
                [layer.drawableProperties[@"test-unrelated-property"] isEqual:@"preserve-me"]);
        }
        CAEAGLLayer *layer = [CAEAGLLayer layer];
        layer.drawableProperties = @{kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};
        NSDictionary *original = layer.drawableProperties;
        check("native-storage-forwarded", storage(sink, selector, 0x8d41, layer));
        check("native-dictionary-not-reset", layer.drawableProperties == original);
        NSString *invalid = @"invalid-format";
        layer.drawableProperties = @{kEAGLDrawablePropertyColorFormat:invalid};
        check("invalid-storage-forwarded", storage(sink, selector, 0x8d41, layer));
        check("invalid-format-not-rewritten",
            layer.drawableProperties[kEAGLDrawablePropertyColorFormat] == invalid);
        check("nil-drawable-forwarded", storage(sink, selector, 0x8d41, nil));
        check("one-native-call-per-request", sink.calls == 5);
    }
    printf("drawable-properties: %s (%u failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures != 0;
}
