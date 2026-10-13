#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>

static unsigned failures;
static void check(const char *name, BOOL passed) {
    printf("attributed-callback-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static void checkLayout(NSAttributedString *string) {
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)string);
    check("native-layout", line && CTLineGetGlyphCount(line) == 5);
    if(line) CFRelease(line);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 16, NULL);
        check("font", font != NULL);
        if(!font) return 1;
        for(unsigned mode = 0; mode < 4; ++mode) {
            printf("callback modes: keys=%s values=%s\n",
                mode & 1 ? "object" : "raw", mode & 2 ? "object" : "raw");
            CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(NULL, 0,
                mode & 1 ? &kCFTypeDictionaryKeyCallBacks : NULL,
                mode & 2 ? &kCFTypeDictionaryValueCallBacks : NULL);
            CFDictionarySetValue(attributes, kCTFontAttributeName, font);
            NSAttributedString *initialized = [[NSAttributedString alloc]
                initWithString:@"Video" attributes:(NSDictionary *)attributes];
            checkLayout(initialized);
            [initialized release];

            NSMutableAttributedString *mutable = [[NSMutableAttributedString alloc]
                initWithString:@"Video"];
            [mutable setAttributes:(NSDictionary *)attributes range:NSMakeRange(0, 5)];
            checkLayout(mutable);
            [mutable setAttributes:nil range:NSMakeRange(0, 5)];
            [mutable addAttributes:(NSDictionary *)attributes range:NSMakeRange(0, 5)];
            checkLayout(mutable);
            [mutable release];

            CFAttributedStringRef cfString = CFAttributedStringCreate(NULL, CFSTR("Video"), attributes);
            checkLayout((NSAttributedString *)cfString);
            if(cfString) CFRelease(cfString);
            check("source-unchanged", CFDictionaryGetCount(attributes) == 1 &&
                CFDictionaryGetValue(attributes, kCTFontAttributeName) == font);
            CFRelease(attributes);
        }
        CFRelease(font);
    }
    printf("attributed callback regression: %s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
