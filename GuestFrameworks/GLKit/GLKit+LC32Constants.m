#import <GLKit/GLKit.h>
#import <Foundation/Foundation+LC32.h>

/*
 * Keep guest exports at stable ARM32 addresses while binding each object to
 * the native framework constant. This preserves native key/identifier
 * identity when a guest collection crosses the bridge.
 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderApplyPremultiplication)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderErrorDomain)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderErrorKey)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderGLErrorKey)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderGenerateMipmaps)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderGrayscaleAsAlpha)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderOriginBottomLeft)
LC32_CONST_STR_DECL(NSString *const GLKTextureLoaderSRGB)
LC32_CONST_STR_DECL(NSString *const kGLKModelErrorDomain)
LC32_CONST_STR_DECL(NSString *const kGLKModelErrorKey)

__attribute__((constructor)) static void LC32InitializeGLKitConstants(void) {
    LC32LoadHostFramework("GLKit");
    LC32_CONST_STR_INIT(GLKTextureLoaderApplyPremultiplication);
    LC32_CONST_STR_INIT(GLKTextureLoaderErrorDomain);
    LC32_CONST_STR_INIT(GLKTextureLoaderErrorKey);
    LC32_CONST_STR_INIT(GLKTextureLoaderGLErrorKey);
    LC32_CONST_STR_INIT(GLKTextureLoaderGenerateMipmaps);
    LC32_CONST_STR_INIT(GLKTextureLoaderGrayscaleAsAlpha);
    LC32_CONST_STR_INIT(GLKTextureLoaderOriginBottomLeft);
    LC32_CONST_STR_INIT(GLKTextureLoaderSRGB);
    LC32_CONST_STR_INIT(kGLKModelErrorDomain);
    LC32_CONST_STR_INIT(kGLKModelErrorKey);
}

#pragma clang diagnostic pop
