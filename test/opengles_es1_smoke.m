#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int es1Failures;

#define ES1_CHECK(condition, label) do {                                 \
    if(condition) {                                                       \
        printf("PASS %s\n", label);                                      \
    } else {                                                              \
        fprintf(stderr, "FAIL %s\n", label);                            \
        es1Failures++;                                                    \
    }                                                                     \
} while(0)

static int es1_gl_ok(const char *label) {
    GLenum error = glGetError();
    if(error == GL_NO_ERROR) {
        printf("PASS %s\n", label);
        return 1;
    }
    fprintf(stderr, "FAIL %s (OpenGL ES error 0x%x)\n", label, error);
    es1Failures++;
    return 0;
}

static GLfixed fixed(GLfloat value) {
    return (GLfixed)(value * 65536.0f);
}

static int float_near(GLfloat left, GLfloat right) {
    return fabsf(left - right) <= 0.0001f;
}

typedef struct {
    uint32_t before;
    GLfixed values[16];
    uint32_t after;
} Fixed16Output;

typedef struct {
    uint32_t before;
    GLfixed values[4];
    uint32_t after;
} Fixed4Output;

typedef struct {
    uint32_t before;
    GLfloat values[4];
    uint32_t after;
} Float4Output;

typedef struct {
    uint32_t before;
    GLfloat value;
    uint32_t after;
} Float1Output;

typedef struct {
    uint32_t before;
    GLint value;
    uint32_t after;
} Int1Output;

static void test_promoted_oes_aliases(void) {
    glBlendEquationOES(GL_FUNC_ADD_OES);
    glBlendEquationSeparateOES(GL_FUNC_ADD_OES, GL_FUNC_ADD_OES);
    glBlendFuncSeparateOES(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
                           GL_ONE, GL_ZERO);

    GLint blendEquationRGB = 0;
    GLint blendEquationAlpha = 0;
    GLint blendSourceRGB = 0;
    GLint blendDestinationRGB = 0;
    GLint blendSourceAlpha = 0;
    GLint blendDestinationAlpha = 0;
    glGetIntegerv(GL_BLEND_EQUATION_RGB_OES, &blendEquationRGB);
    glGetIntegerv(GL_BLEND_EQUATION_ALPHA_OES, &blendEquationAlpha);
    glGetIntegerv(GL_BLEND_SRC_RGB_OES, &blendSourceRGB);
    glGetIntegerv(GL_BLEND_DST_RGB_OES, &blendDestinationRGB);
    glGetIntegerv(GL_BLEND_SRC_ALPHA_OES, &blendSourceAlpha);
    glGetIntegerv(GL_BLEND_DST_ALPHA_OES, &blendDestinationAlpha);
    ES1_CHECK(blendEquationRGB == GL_FUNC_ADD_OES &&
              blendEquationAlpha == GL_FUNC_ADD_OES &&
              blendSourceRGB == GL_SRC_ALPHA &&
              blendDestinationRGB == GL_ONE_MINUS_SRC_ALPHA &&
              blendSourceAlpha == GL_ONE &&
              blendDestinationAlpha == GL_ZERO,
              "ES1-OES-promoted-blend-state");
    es1_gl_ok("ES1-OES-promoted-blend-error");

    GLuint renderbuffer = 0;
    glGenRenderbuffersOES(1, &renderbuffer);
    ES1_CHECK(renderbuffer != 0,
              "ES1-OES-renderbuffer-name-copyback");
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, renderbuffer);

    GLint boundRenderbuffer = 0;
    glGetIntegerv(GL_RENDERBUFFER_BINDING_OES, &boundRenderbuffer);
    ES1_CHECK((GLuint)boundRenderbuffer == renderbuffer,
              "ES1-OES-renderbuffer-binding");
    ES1_CHECK(glIsRenderbufferOES(renderbuffer) == GL_TRUE,
              "ES1-OES-renderbuffer-recognition");

    glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_RGBA4_OES, 16, 8);
    GLint renderbufferWidth = 0;
    GLint renderbufferHeight = 0;
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
                                    GL_RENDERBUFFER_WIDTH_OES,
                                    &renderbufferWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES,
                                    GL_RENDERBUFFER_HEIGHT_OES,
                                    &renderbufferHeight);
    ES1_CHECK(renderbufferWidth == 16 && renderbufferHeight == 8,
              "ES1-OES-renderbuffer-storage-parameters");

    GLuint framebuffer = 0;
    glGenFramebuffersOES(1, &framebuffer);
    ES1_CHECK(framebuffer != 0,
              "ES1-OES-framebuffer-name-copyback");
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, framebuffer);

    GLint boundFramebuffer = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING_OES, &boundFramebuffer);
    ES1_CHECK((GLuint)boundFramebuffer == framebuffer,
              "ES1-OES-framebuffer-binding");
    ES1_CHECK(glIsFramebufferOES(framebuffer) == GL_TRUE,
              "ES1-OES-framebuffer-recognition");

    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES,
                                 GL_COLOR_ATTACHMENT0_OES,
                                 GL_RENDERBUFFER_OES, renderbuffer);
    ES1_CHECK(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) ==
                  GL_FRAMEBUFFER_COMPLETE_OES,
              "ES1-OES-renderbuffer-framebuffer-complete");

    GLint attachmentType = 0;
    GLint attachmentName = 0;
    glGetFramebufferAttachmentParameterivOES(
        GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE_OES, &attachmentType);
    glGetFramebufferAttachmentParameterivOES(
        GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME_OES, &attachmentName);
    ES1_CHECK(attachmentType == GL_RENDERBUFFER_OES &&
              (GLuint)attachmentName == renderbuffer,
              "ES1-OES-renderbuffer-attachment-query");

    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenerateMipmapOES(GL_TEXTURE_2D);
    glFramebufferTexture2DOES(GL_FRAMEBUFFER_OES,
                              GL_COLOR_ATTACHMENT0_OES,
                              GL_TEXTURE_2D, texture, 0);
    ES1_CHECK(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) ==
                  GL_FRAMEBUFFER_COMPLETE_OES,
              "ES1-OES-texture-framebuffer-complete");

    attachmentType = 0;
    attachmentName = 0;
    glGetFramebufferAttachmentParameterivOES(
        GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE_OES, &attachmentType);
    glGetFramebufferAttachmentParameterivOES(
        GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES,
        GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME_OES, &attachmentName);
    ES1_CHECK(attachmentType == GL_TEXTURE &&
              (GLuint)attachmentName == texture,
              "ES1-OES-texture-attachment-query");
    es1_gl_ok("ES1-OES-framebuffer-alias-error");

    glBindFramebufferOES(GL_FRAMEBUFFER_OES, 0);
    glDeleteFramebuffersOES(1, &framebuffer);
    ES1_CHECK(glIsFramebufferOES(framebuffer) == GL_FALSE,
              "ES1-OES-deleted-framebuffer-rejection");
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, 0);
    glDeleteRenderbuffersOES(1, &renderbuffer);
    ES1_CHECK(glIsRenderbufferOES(renderbuffer) == GL_FALSE,
              "ES1-OES-deleted-renderbuffer-rejection");
    if(texture) glDeleteTextures(1, &texture);
    es1_gl_ok("ES1-OES-framebuffer-alias-cleanup-error");
}

int run_opengles_es1_smoke(void) {
    @autoreleasepool {
        EAGLContext *context =
            [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        if(!context) {
            printf("SKIP create-ES1-context: Catalyst has no OpenGL ES "
                   "runtime; an ANGLE/Metal backend is required\n");
            return 0;
        }
        if(![EAGLContext setCurrentContext:context]) {
            ES1_CHECK(0, "set-current-ES1-context");
            [context release];
            return es1Failures;
        }
        ES1_CHECK(1, "set-current-ES1-context");

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        Fixed16Output matrix;
        memset(&matrix, 0xa5, sizeof(matrix));
        matrix.before = 0x12345678;
        matrix.after = 0x87654321;
        glGetFixedv(GL_MODELVIEW_MATRIX, matrix.values);
        int identity = 1;
        for(unsigned row = 0; row < 4; ++row) {
            for(unsigned column = 0; column < 4; ++column) {
                const GLfixed expected = row == column ? fixed(1.0f) : 0;
                if(matrix.values[row * 4 + column] != expected)
                    identity = 0;
            }
        }
        ES1_CHECK(identity, "ES1-fixed-matrix-copyback");
        ES1_CHECK(matrix.before == 0x12345678 &&
                  matrix.after == 0x87654321,
                  "ES1-fixed-matrix-copyback-canaries");
        es1_gl_ok("ES1-fixed-matrix-getter-error");

        const GLfixed clear[4] = {
            fixed(0.125f), fixed(0.25f), fixed(0.5f), fixed(0.75f),
        };
        glClearColorx(clear[0], clear[1], clear[2], clear[3]);
        Fixed4Output clearOutput = {
            .before = 0x11223344,
            .after = 0x55667788,
        };
        glGetFixedv(GL_COLOR_CLEAR_VALUE, clearOutput.values);
        ES1_CHECK(memcmp(clear, clearOutput.values, sizeof(clear)) == 0,
                  "ES1-fixed-four-value-state-copyback");
        ES1_CHECK(clearOutput.before == 0x11223344 &&
                  clearOutput.after == 0x55667788,
                  "ES1-fixed-four-value-state-canaries");
        es1_gl_ok("ES1-fixed-four-value-state-error");

        const GLfloat floatPlane[4] = {0.25f, -0.5f, 1.0f, -0.125f};
        Float4Output floatPlaneOutput = {
            .before = 0xa1b2c3d4,
            .after = 0x4d3c2b1a,
        };
        glClipPlanef(GL_CLIP_PLANE0, floatPlane);
        glGetClipPlanef(GL_CLIP_PLANE0, floatPlaneOutput.values);
        ES1_CHECK(float_near(floatPlaneOutput.values[0], floatPlane[0]) &&
                  float_near(floatPlaneOutput.values[1], floatPlane[1]) &&
                  float_near(floatPlaneOutput.values[2], floatPlane[2]) &&
                  float_near(floatPlaneOutput.values[3], floatPlane[3]),
                  "ES1-float-clip-plane-roundtrip");
        ES1_CHECK(floatPlaneOutput.before == 0xa1b2c3d4 &&
                  floatPlaneOutput.after == 0x4d3c2b1a,
                  "ES1-float-clip-plane-canaries");

        const GLfixed fixedPlane[4] = {
            fixed(1.0f), fixed(0.5f), fixed(-0.25f), fixed(-0.75f),
        };
        Fixed4Output fixedPlaneOutput = {
            .before = 0xabcdef01,
            .after = 0x10fedcba,
        };
        glClipPlanex(GL_CLIP_PLANE1, fixedPlane);
        glGetClipPlanex(GL_CLIP_PLANE1, fixedPlaneOutput.values);
        ES1_CHECK(memcmp(fixedPlane, fixedPlaneOutput.values,
                         sizeof(fixedPlane)) == 0,
                  "ES1-fixed-clip-plane-roundtrip");
        ES1_CHECK(fixedPlaneOutput.before == 0xabcdef01 &&
                  fixedPlaneOutput.after == 0x10fedcba,
                  "ES1-fixed-clip-plane-canaries");
        es1_gl_ok("ES1-clip-plane-vector-error");

        const GLfloat diffuse[4] = {0.125f, 0.25f, 0.5f, 1.0f};
        Float4Output diffuseOutput = {
            .before = 0x13572468,
            .after = 0x86427531,
        };
        glLightfv(GL_LIGHT0, GL_DIFFUSE, diffuse);
        glGetLightfv(GL_LIGHT0, GL_DIFFUSE, diffuseOutput.values);
        ES1_CHECK(float_near(diffuseOutput.values[0], diffuse[0]) &&
                  float_near(diffuseOutput.values[1], diffuse[1]) &&
                  float_near(diffuseOutput.values[2], diffuse[2]) &&
                  float_near(diffuseOutput.values[3], diffuse[3]),
                  "ES1-light-float-vector-roundtrip");
        ES1_CHECK(diffuseOutput.before == 0x13572468 &&
                  diffuseOutput.after == 0x86427531,
                  "ES1-light-float-vector-canaries");

        const GLfixed position[4] = {
            fixed(0.25f), fixed(-0.5f), fixed(0.75f), fixed(1.0f),
        };
        Fixed4Output positionOutput = {
            .before = 0x10293847,
            .after = 0x74839201,
        };
        glLightxv(GL_LIGHT0, GL_POSITION, position);
        glGetLightxv(GL_LIGHT0, GL_POSITION, positionOutput.values);
        ES1_CHECK(memcmp(position, positionOutput.values,
                         sizeof(position)) == 0,
                  "ES1-light-fixed-vector-roundtrip");
        ES1_CHECK(positionOutput.before == 0x10293847 &&
                  positionOutput.after == 0x74839201,
                  "ES1-light-fixed-vector-canaries");

        Float1Output exponentOutput = {
            .before = 0x31415926,
            .value = -1.0f,
            .after = 0x27182818,
        };
        glLightf(GL_LIGHT0, GL_SPOT_EXPONENT, 12.0f);
        glGetLightfv(GL_LIGHT0, GL_SPOT_EXPONENT, &exponentOutput.value);
        ES1_CHECK(float_near(exponentOutput.value, 12.0f),
                  "ES1-light-scalar-copyback");
        ES1_CHECK(exponentOutput.before == 0x31415926 &&
                  exponentOutput.after == 0x27182818,
                  "ES1-light-scalar-copyback-canaries");

        const GLfixed material[4] = {
            fixed(0.75f), fixed(0.5f), fixed(0.25f), fixed(1.0f),
        };
        Fixed4Output materialOutput = {
            .before = 0x24681357,
            .after = 0x75318642,
        };
        glMaterialxv(GL_FRONT_AND_BACK, GL_AMBIENT, material);
        glGetMaterialxv(GL_FRONT, GL_AMBIENT, materialOutput.values);
        ES1_CHECK(memcmp(material, materialOutput.values,
                         sizeof(material)) == 0,
                  "ES1-material-fixed-vector-roundtrip");
        ES1_CHECK(materialOutput.before == 0x24681357 &&
                  materialOutput.after == 0x75318642,
                  "ES1-material-fixed-vector-canaries");

        const GLfloat specular[4] = {0.2f, 0.4f, 0.6f, 0.8f};
        Float4Output specularOutput = {
            .before = 0x55aa55aa,
            .after = 0xaa55aa55,
        };
        glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, specular);
        glGetMaterialfv(GL_FRONT, GL_SPECULAR, specularOutput.values);
        ES1_CHECK(float_near(specularOutput.values[0], specular[0]) &&
                  float_near(specularOutput.values[1], specular[1]) &&
                  float_near(specularOutput.values[2], specular[2]) &&
                  float_near(specularOutput.values[3], specular[3]),
                  "ES1-material-float-vector-roundtrip");
        ES1_CHECK(specularOutput.before == 0x55aa55aa &&
                  specularOutput.after == 0xaa55aa55,
                  "ES1-material-float-vector-canaries");
        es1_gl_ok("ES1-light-material-vector-error");

        const GLfixed environmentColor[4] = {
            fixed(0.125f), fixed(0.375f), fixed(0.625f), fixed(0.875f),
        };
        Fixed4Output environmentOutput = {
            .before = 0x0badcafe,
            .after = 0xc001d00d,
        };
        glTexEnvxv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, environmentColor);
        glGetTexEnvxv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR,
                      environmentOutput.values);
        ES1_CHECK(memcmp(environmentColor, environmentOutput.values,
                         sizeof(environmentColor)) == 0,
                  "ES1-texture-env-fixed-vector-roundtrip");
        ES1_CHECK(environmentOutput.before == 0x0badcafe &&
                  environmentOutput.after == 0xc001d00d,
                  "ES1-texture-env-fixed-vector-canaries");

        const GLfloat floatEnvironmentColor[4] = {
            0.2f, 0.4f, 0.6f, 0.8f,
        };
        Float4Output floatEnvironmentOutput = {
            .before = 0x01020304,
            .after = 0x40302010,
        };
        glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR,
                   floatEnvironmentColor);
        glGetTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR,
                      floatEnvironmentOutput.values);
        ES1_CHECK(float_near(floatEnvironmentOutput.values[0],
                             floatEnvironmentColor[0]) &&
                  float_near(floatEnvironmentOutput.values[1],
                             floatEnvironmentColor[1]) &&
                  float_near(floatEnvironmentOutput.values[2],
                             floatEnvironmentColor[2]) &&
                  float_near(floatEnvironmentOutput.values[3],
                             floatEnvironmentColor[3]),
                  "ES1-texture-env-float-vector-roundtrip");
        ES1_CHECK(floatEnvironmentOutput.before == 0x01020304 &&
                  floatEnvironmentOutput.after == 0x40302010,
                  "ES1-texture-env-float-vector-canaries");

        Int1Output modeOutput = {
            .before = 0x11112222,
            .value = 0,
            .after = 0x33334444,
        };
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
        glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE,
                      &modeOutput.value);
        ES1_CHECK(modeOutput.value == GL_REPLACE,
                  "ES1-texture-env-integer-scalar-roundtrip");
        ES1_CHECK(modeOutput.before == 0x11112222 &&
                  modeOutput.after == 0x33334444,
                  "ES1-texture-env-integer-scalar-canaries");

        GLuint texture = 0;
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameterx(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        GLfixed textureParameter = 0;
        glGetTexParameterxv(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                            &textureParameter);
        ES1_CHECK(textureParameter == GL_NEAREST,
                  "ES1-texture-parameter-fixed-roundtrip");
        es1_gl_ok("ES1-texture-fixed-vector-error");

        GLfloat vertices[] = {
            -1.0f, -1.0f,
             1.0f, -1.0f,
             0.0f,  1.0f,
        };
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glVertexPointer(2, GL_FLOAT, 0, vertices);
        void *vertexPointer = (void *)(uintptr_t)0x1;
        glGetPointerv(GL_VERTEX_ARRAY_POINTER, &vertexPointer);
        ES1_CHECK(vertexPointer == vertices,
                  "ES1-client-pointer-guest-address-roundtrip");

        GLuint vertexBuffer = 0;
        glGenBuffers(1, &vertexBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices,
                     GL_STATIC_DRAW);
        glVertexPointer(2, GL_FLOAT, 0, (const void *)(uintptr_t)4);
        vertexPointer = NULL;
        glGetPointerv(GL_VERTEX_ARRAY_POINTER, &vertexPointer);
        ES1_CHECK(vertexPointer == (void *)(uintptr_t)4,
                  "ES1-client-pointer-VBO-offset-roundtrip");
        es1_gl_ok("ES1-client-pointer-roundtrip-error");

        test_promoted_oes_aliases();

        if(vertexBuffer) glDeleteBuffers(1, &vertexBuffer);
        if(texture) glDeleteTextures(1, &texture);
        [EAGLContext setCurrentContext:nil];
        [context release];
    }

    return es1Failures;
}
