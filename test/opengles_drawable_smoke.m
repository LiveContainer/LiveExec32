#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/CAEAGLLayer.h>
#include <stdio.h>

static int failures;
static EAGLRenderingAPI api;

#define CHECK(test, label) do { \
    printf("%s ES%u-drawable-%s\n", (test) ? "PASS" : (++failures, "FAIL"), \
           (unsigned)api, label); \
} while(0)

static void bind_buffer(GLuint buffer) {
    if(api == kEAGLRenderingAPIOpenGLES1)
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, buffer);
    else glBindRenderbuffer(GL_RENDERBUFFER, buffer);
}

static GLuint new_buffer(void) {
    GLuint buffer = 0;
    if(api == kEAGLRenderingAPIOpenGLES1) glGenRenderbuffersOES(1, &buffer);
    else glGenRenderbuffers(1, &buffer);
    bind_buffer(buffer);
    return buffer;
}

static void delete_buffer(GLuint buffer) {
    if(api == kEAGLRenderingAPIOpenGLES1) glDeleteRenderbuffersOES(1, &buffer);
    else glDeleteRenderbuffers(1, &buffer);
}

static BOOL dimensions(GLint width, GLint height) {
    GLint w = 0, h = 0;
    if(api == kEAGLRenderingAPIOpenGLES1) {
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &w);
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &h);
    } else {
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &w);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &h);
    }
    return w == width && h == height;
}

static void run_drawable_test(void) {
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:api];
    if(!context) {
        printf("SKIP ES%u-drawable: no native context\n", (unsigned)api);
        return;
    }
    CHECK([EAGLContext setCurrentContext:context], "current-context");
    CAEAGLLayer *layer = [CAEAGLLayer layer];
    layer.bounds = CGRectMake(0, 0, 64, 32);
    layer.drawableProperties = @{
        kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
        kEAGLDrawablePropertyRetainedBacking: @YES,
    };
    GLuint first = new_buffer();
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "first-storage");
    CHECK(dimensions(64, 32), "first-dimensions");

    GLuint framebuffer = 0;
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    GLuint second = new_buffer();
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "replacement-storage");
    GLint binding = 0, framebufferBinding = 0;
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &binding);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebufferBinding);
    CHECK((GLuint)binding == second && (GLuint)framebufferBinding == framebuffer,
          "replacement-preserves-bindings");
    CHECK(dimensions(64, 32), "replacement-dimensions");
    CHECK(glIsRenderbuffer(first), "replacement-keeps-old-object");
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, second);
    CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "replacement-framebuffer");

    layer.bounds = CGRectMake(0, 0, 48, 24);
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "same-buffer-resize");
    CHECK(dimensions(48, 24), "resize-dimensions");
    glDeleteFramebuffers(1, &framebuffer);
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:nil], "explicit-release");
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "reattach-after-release");

    // Shared contexts see the same objects, but have distinct GL bindings.
    EAGLContext *peer = [[EAGLContext alloc] initWithAPI:api sharegroup:context.sharegroup];
    CHECK([EAGLContext setCurrentContext:peer], "shared-context");
    GLuint third = new_buffer();
    CHECK([peer renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "shared-replacement");
    CHECK(dimensions(48, 24), "shared-dimensions");
    [EAGLContext setCurrentContext:context];
    glGetIntegerv(GL_RENDERBUFFER_BINDING, &binding);
    CHECK((GLuint)binding == second, "other-context-binding-unchanged");

    // A malformed replacement must not release an existing valid attachment.
    GLuint fourth = new_buffer();
    layer.drawableProperties = @{kEAGLDrawablePropertyColorFormat: @"invalid-format"};
    CHECK(![context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "invalid-format-rejected");
    bind_buffer(third);
    CHECK(dimensions(48, 24), "invalid-format-keeps-owner");
    while(glGetError() != GL_NO_ERROR) {}
    layer.drawableProperties = @{
        kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
        kEAGLDrawablePropertyRetainedBacking: @YES,
    };
    bind_buffer(fourth);
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "replace-after-invalid-request");
    delete_buffer(fourth);

    // Reuse a deleted name as an unrelated offscreen buffer, then put the
    // layer in another sharegroup. A rejected cross-group request must not
    // detach the recycled object using an obsolete ownership record.
    bind_buffer(fourth);
    if(api == kEAGLRenderingAPIOpenGLES1)
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_RGBA4_OES, 8, 8);
    else glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, 8, 8);
    CHECK(dimensions(8, 8), "recycled-name-offscreen-storage");
    EAGLContext *foreign = [[EAGLContext alloc] initWithAPI:api];
    [EAGLContext setCurrentContext:foreign];
    GLuint foreignBuffer = new_buffer();
    CHECK([foreign renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "foreign-owner");
    [EAGLContext setCurrentContext:context];
    GLuint rejected = new_buffer();
    CHECK(![context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "cross-group-rejected");
    bind_buffer(fourth);
    CHECK(dimensions(8, 8), "cross-group-keeps-recycled-buffer");
    while(glGetError() != GL_NO_ERROR) {}
    [EAGLContext setCurrentContext:foreign];
    CHECK([foreign renderbufferStorage:GL_RENDERBUFFER fromDrawable:nil], "foreign-release");
    delete_buffer(foreignBuffer);
    [EAGLContext setCurrentContext:context];
    bind_buffer(rejected);
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "storage-after-foreign-release");
    CHECK(dimensions(48, 24), "final-dimensions");

    // Reuse the live object for offscreen storage after explicitly releasing
    // its drawable. Native EAGL rejects redefining a still-attached image.
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:nil], "release-before-redefinition");
    if(api == kEAGLRenderingAPIOpenGLES1)
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_RGBA4_OES, 16, 8);
    else glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, 16, 8);
    CHECK(dimensions(16, 8), "redefined-offscreen-storage");
    [EAGLContext setCurrentContext:foreign];
    foreignBuffer = new_buffer();
    CHECK([foreign renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "foreign-owner-after-redefinition");
    [EAGLContext setCurrentContext:context];
    bind_buffer(first);
    CHECK(![context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "redefined-cross-group-rejected");
    bind_buffer(rejected);
    CHECK(dimensions(16, 8), "cross-group-keeps-redefined-buffer");
    while(glGetError() != GL_NO_ERROR) {}
    [EAGLContext setCurrentContext:foreign];
    CHECK([foreign renderbufferStorage:GL_RENDERBUFFER fromDrawable:nil], "redefined-foreign-release");
    delete_buffer(foreignBuffer);
    [EAGLContext setCurrentContext:context];
    bind_buffer(rejected);
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer], "reattach-after-redefinition");
    CHECK([context renderbufferStorage:GL_RENDERBUFFER fromDrawable:nil], "final-release");
    delete_buffer(first);
    delete_buffer(second);
    delete_buffer(third);
    delete_buffer(fourth);
    delete_buffer(rejected);
    CHECK(glGetError() == GL_NO_ERROR, "cleanup-error");
    [EAGLContext setCurrentContext:nil];
    [foreign release];
    [peer release];
    [context release];
}

int run_opengles_drawable_smoke(void) {
    for(api = kEAGLRenderingAPIOpenGLES1; api <= kEAGLRenderingAPIOpenGLES3; ++api) {
        @autoreleasepool { run_drawable_test(); }
    }
    return failures;
}

#ifdef LC32_DRAWABLE_STANDALONE
int main(void) {
    return run_opengles_drawable_smoke() ? 1 : 0;
}
#endif
