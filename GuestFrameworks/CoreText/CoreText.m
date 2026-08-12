#import <CoreText/CoreText.h>
#import <Foundation/Foundation+LC32.h>

LC32_CONST_STR_DECL(const CFStringRef kCTFontAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTForegroundColorAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTKernAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTParagraphStyleAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTStrokeColorAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTStrokeWidthAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTUnderlineColorAttributeName)
LC32_CONST_STR_DECL(const CFStringRef kCTUnderlineStyleAttributeName)

__attribute__((constructor)) void CoreTextInit() {
    LC32_CONST_STR_INIT(kCTFontAttributeName);
    LC32_CONST_STR_INIT(kCTForegroundColorAttributeName);
    LC32_CONST_STR_INIT(kCTKernAttributeName);
    LC32_CONST_STR_INIT(kCTParagraphStyleAttributeName);
    LC32_CONST_STR_INIT(kCTStrokeColorAttributeName);
    LC32_CONST_STR_INIT(kCTStrokeWidthAttributeName);
    LC32_CONST_STR_INIT(kCTUnderlineColorAttributeName);
    LC32_CONST_STR_INIT(kCTUnderlineStyleAttributeName);
}
