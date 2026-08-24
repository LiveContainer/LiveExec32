#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

#include <stdio.h>
#include <string.h>

#ifndef GL_TEXTURE_ENV
#define GL_TEXTURE_ENV 0x2300
#endif
#ifndef GL_TEXTURE_ENV_MODE
#define GL_TEXTURE_ENV_MODE 0x2200
#endif
#ifndef GL_TEXTURE_ENV_COLOR
#define GL_TEXTURE_ENV_COLOR 0x2201
#endif
#ifndef GL_MODULATE
#define GL_MODULATE 0x2100
#endif

extern void glTexEnvfv(GLenum target, GLenum pname,
                       const GLfloat *params);

static int failures;

#define CHECK(condition, label) do {                                      \
    if(condition) {                                                       \
        printf("PASS %s\n", label);                                      \
    } else {                                                              \
        fprintf(stderr, "FAIL %s\n", label);                            \
        failures++;                                                       \
    }                                                                     \
} while(0)

static int gl_ok(const char *label) {
    GLenum error = glGetError();
    if(error == GL_NO_ERROR) {
        printf("PASS %s\n", label);
        return 1;
    }
    fprintf(stderr, "FAIL %s (OpenGL ES error 0x%x)\n", label, error);
    failures++;
    return 0;
}

static GLuint compile_shader(GLenum type, const char *source,
                             const char *label) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);

    char copiedSource[512] = {};
    GLsizei copiedLength = 0;
    glGetShaderSource(shader, sizeof(copiedSource), &copiedLength,
                      copiedSource);
    CHECK(copiedLength == (GLsizei)strlen(source) &&
          strcmp(copiedSource, source) == 0,
          "shader-source-copyback");

    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if(compiled != GL_TRUE) {
        char log[1024] = {};
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        fprintf(stderr, "FAIL %s: %s\n", label, log);
        failures++;
        glDeleteShader(shader);
        return 0;
    }
    printf("PASS %s\n", label);
    return shader;
}

static void test_texture_environment_vector(void) {
    EAGLContext *context =
        [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
    if(!context) {
        printf("SKIP create-ES1-context: Catalyst has no OpenGL ES "
               "runtime; an ANGLE/Metal backend is required\n");
        return;
    }
    if(![EAGLContext setCurrentContext:context]) {
        CHECK(0, "set-current-ES1-context");
        [context release];
        return;
    }
    CHECK(1, "set-current-ES1-context");

    const GLfloat color[4] = {0.125f, 0.25f, 0.5f, 0.75f};
    glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, color);
    gl_ok("texture-env-four-float-vector");

    const GLfloat mode = (GLfloat)GL_MODULATE;
    glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &mode);
    gl_ok("texture-env-scalar-vector");

    [EAGLContext setCurrentContext:nil];
    [context release];
}

int main(void) {
    @autoreleasepool {
        unsigned int major = 0;
        unsigned int minor = 0;
        EAGLGetVersion(&major, &minor);
        CHECK(major >= 1, "EAGL-version-copyback");

        test_texture_environment_vector();

        EAGLContext *context =
            [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if(!context) {
            printf("SKIP create-ES2-context: Catalyst has no OpenGL ES "
                   "runtime; an ANGLE/Metal backend is required\n");
            return 0;
        }
        CHECK(context != nil, "create-ES2-context");
        CHECK([EAGLContext setCurrentContext:context], "set-current-context");
        CHECK([EAGLContext currentContext] != nil,
              "current-context-roundtrip");

        const GLenum stringNames[] = {
            GL_VENDOR, GL_RENDERER, GL_VERSION, GL_EXTENSIONS,
            GL_SHADING_LANGUAGE_VERSION,
        };
        const GLubyte *strings[5] = {};
        for(unsigned i = 0; i < 5; ++i) {
            strings[i] = glGetString(stringNames[i]);
            CHECK(strings[i] != NULL, "GL-string-guest-copy");
        }
        CHECK(glGetString(GL_VENDOR) == strings[0],
              "five-entry-GL-string-cache");

        GLuint framebuffer = 0;
        GLuint renderbuffer = 0;
        GLuint vertexShader = 0;
        GLuint fragmentShader = 0;
        GLuint program = 0;
        GLuint vertexBuffer = 0;
        GLuint indexBuffer = 0;
        GLuint vertexArray = 0;
        GLuint texture = 0;
        glGenFramebuffers(1, &framebuffer);
        glGenRenderbuffers(1, &renderbuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, renderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, 4, 4);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                  GL_RENDERBUFFER, renderbuffer);
        CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
                  GL_FRAMEBUFFER_COMPLETE,
              "offscreen-framebuffer-complete");
        if(!gl_ok("offscreen-framebuffer-setup")) goto cleanup;

        glViewport(0, 0, 4, 4);
        GLint viewport[4] = {};
        glGetIntegerv(GL_VIEWPORT, viewport);
        CHECK(viewport[0] == 0 && viewport[1] == 0 &&
              viewport[2] == 4 && viewport[3] == 4,
              "four-value-state-copyback");

#ifdef GL_MAX_SAMPLES_APPLE
        GLint maximumSamples = 0;
        glGetIntegerv(GL_MAX_SAMPLES_APPLE, &maximumSamples);
        CHECK(glGetError() == GL_NO_ERROR && maximumSamples >= 0,
              "APPLE-max-samples-state-copyback");
#endif

        glDisable(GL_DITHER);
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
        GLfloat clearColor[4] = {};
        glGetFloatv(GL_COLOR_CLEAR_VALUE, clearColor);
        CHECK(clearColor[0] == 1.0f && clearColor[1] == 0.0f &&
              clearColor[2] == 0.0f && clearColor[3] == 1.0f,
              "four-float-state-copyback");
        glClear(GL_COLOR_BUFFER_BIT);
        glFinish();

        GLubyte pixel[4] = {};
        glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        CHECK(pixel[0] >= 248 && pixel[1] <= 7 && pixel[2] <= 7 &&
              pixel[3] >= 248,
              "offscreen-clear-readback");
        if(!gl_ok("offscreen-clear-readback-error")) goto cleanup;

        /* RGB rows are 3 bytes wide and 4-byte aligned: two rows occupy
         * exactly seven bytes because the final row has no trailing pad. */
        const GLubyte textureRows[8] = {
            255, 0, 0, 0xa5,
            0, 255, 0, 0x5a,
        };
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 1, 2, 0,
                     GL_RGB, GL_UNSIGNED_BYTE, textureRows);
        CHECK(textureRows[7] == 0x5a, "RGB-upload-final-padding-canary");
        if(!gl_ok("RGB-two-row-upload")) goto cleanup;

        GLubyte packedRGB[8];
        memset(packedRGB, 0xa5, sizeof(packedRGB));
        glPixelStorei(GL_PACK_ALIGNMENT, 4);
        glReadPixels(0, 0, 1, 2, GL_RGB, GL_UNSIGNED_BYTE, packedRGB);
        GLenum packedReadError = glGetError();
        if(packedReadError == GL_NO_ERROR) {
            CHECK(packedRGB[3] == 0xa5 && packedRGB[7] == 0xa5,
                  "RGB-read-row-and-final-padding-canaries");
        } else {
            printf("SKIP RGB-read-padding-canary: backend error 0x%x\n",
                   packedReadError);
        }

        const char *vertexSource =
            "attribute vec2 position;"
            "void main() { gl_Position = vec4(position, 0.0, 1.0); }";
        const char *fragmentSource =
            "precision mediump float;"
            "uniform vec4 tint;"
            "void main() { gl_FragColor = tint; }";
        vertexShader = compile_shader(GL_VERTEX_SHADER, vertexSource,
                                      "compile-vertex-shader");
        fragmentShader = compile_shader(GL_FRAGMENT_SHADER, fragmentSource,
                                        "compile-fragment-shader");
        if(!vertexShader || !fragmentShader) goto cleanup;

        program = glCreateProgram();
        glAttachShader(program, vertexShader);
        glAttachShader(program, fragmentShader);
        glBindAttribLocation(program, 0, "position");
        glLinkProgram(program);
        GLint linked = GL_FALSE;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        if(linked != GL_TRUE) {
            char log[1024] = {};
            glGetProgramInfoLog(program, sizeof(log), NULL, log);
            fprintf(stderr, "FAIL link-program: %s\n", log);
            failures++;
            goto cleanup;
        }
        printf("PASS link-program\n");

        GLsizei attachedCount = 0;
        GLuint attached[2] = {};
        glGetAttachedShaders(program, 2, &attachedCount, attached);
        CHECK(attachedCount == 2, "attached-shader-copyback");

        GLsizei activeLength = 0;
        GLint activeSize = 0;
        GLenum activeType = 0;
        GLchar activeName[64] = {};
        glGetActiveAttrib(program, 0, sizeof(activeName), &activeLength,
                          &activeSize, &activeType, activeName);
        CHECK(activeLength > 0 && activeSize == 1 &&
              activeType == GL_FLOAT_VEC2,
              "active-attrib-copyback");
        memset(activeName, 0, sizeof(activeName));
        glGetActiveUniform(program, 0, sizeof(activeName), &activeLength,
                           &activeSize, &activeType, activeName);
        CHECK(activeLength > 0 && activeSize == 1 &&
              activeType == GL_FLOAT_VEC4,
              "active-uniform-copyback");

        const GLfloat vertices[] = {
            -1.0f, -1.0f,
             3.0f, -1.0f,
            -1.0f,  3.0f,
        };
        glGenBuffers(1, &vertexBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
        glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices,
                     GL_STATIC_DRAW);
        GLint bufferSize = 0;
        glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &bufferSize);
        CHECK(bufferSize == (GLint)sizeof(vertices), "VBO-upload-copy");

        GLint position = glGetAttribLocation(program, "position");
        GLint tint = glGetUniformLocation(program, "tint");
        CHECK(position >= 0 && tint >= 0, "shader-location-string-copy");
        glUseProgram(program);
        glUniform4f(tint, 0.0f, 1.0f, 0.0f, 1.0f);
        GLfloat tintValue[4] = {};
        glGetUniformfv(program, tint, tintValue);
        CHECK(tintValue[0] == 0.0f && tintValue[1] == 1.0f &&
              tintValue[2] == 0.0f && tintValue[3] == 1.0f,
              "uniform-copyback");

        glEnableVertexAttribArray((GLuint)position);
        glVertexAttribPointer((GLuint)position, 2, GL_FLOAT, GL_FALSE,
                              2 * sizeof(GLfloat), (const GLvoid *)0);
        GLvoid *attributeOffset = (GLvoid *)1;
        glGetVertexAttribPointerv((GLuint)position,
                                  GL_VERTEX_ATTRIB_ARRAY_POINTER,
                                  &attributeOffset);
        CHECK(attributeOffset == NULL, "VBO-zero-offset-copyback");

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        glFinish();
        memset(pixel, 0, sizeof(pixel));
        glReadPixels(2, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        CHECK(pixel[0] <= 7 && pixel[1] >= 248 && pixel[2] <= 7 &&
              pixel[3] >= 248,
              "shader-VBO-draw-readback");
        gl_ok("shader-VBO-path-error");

        /* A direct/client-pointer draw on VAO 0 must not contaminate the
         * bridge metadata for a named VAO whose attributes and indices are
         * entirely buffer-backed. Cocos2d's CCSpriteBatchNode follows this
         * sequence after drawing ordinary sprites. */
        const GLushort indices[] = {0, 1, 2};
        glGenVertexArraysOES(1, &vertexArray);
        CHECK(vertexArray != 0, "VAO-name-copyback");
        glBindVertexArrayOES(vertexArray);
        glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
        glEnableVertexAttribArray((GLuint)position);
        glVertexAttribPointer((GLuint)position, 2, GL_FLOAT, GL_FALSE,
                              2 * sizeof(GLfloat), (const GLvoid *)0);
        glGenBuffers(1, &indexBuffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices,
                     GL_STATIC_DRAW);
        glBindVertexArrayOES(0);

        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        glEnableVertexAttribArray((GLuint)position);
        glVertexAttribPointer((GLuint)position, 2, GL_FLOAT, GL_FALSE,
                              2 * sizeof(GLfloat), vertices);

        glBindVertexArrayOES(vertexArray);
        GLint capturedVertexBuffer = 0;
        glGetVertexAttribiv((GLuint)position,
                            GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING,
                            &capturedVertexBuffer);
        CHECK(capturedVertexBuffer == (GLint)vertexBuffer,
              "VAO-captured-VBO-binding");
        glUniform4f(tint, 0.0f, 0.0f, 1.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT,
                       (const GLvoid *)0);
        glFinish();
        memset(pixel, 0, sizeof(pixel));
        glReadPixels(2, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        CHECK(pixel[0] <= 7 && pixel[1] <= 7 && pixel[2] >= 248 &&
              pixel[3] >= 248,
              "VAO-EBO-draw-after-client-pointer-readback");
        gl_ok("VAO-EBO-draw-after-client-pointer-error");
        glBindVertexArrayOES(0);

cleanup:
        if(texture) glDeleteTextures(1, &texture);
        if(vertexArray) glDeleteVertexArraysOES(1, &vertexArray);
        if(indexBuffer) glDeleteBuffers(1, &indexBuffer);
        if(vertexBuffer) glDeleteBuffers(1, &vertexBuffer);
        if(program) glDeleteProgram(program);
        if(vertexShader) glDeleteShader(vertexShader);
        if(fragmentShader) glDeleteShader(fragmentShader);
        if(renderbuffer) glDeleteRenderbuffers(1, &renderbuffer);
        if(framebuffer) glDeleteFramebuffers(1, &framebuffer);
        [EAGLContext setCurrentContext:nil];
        [context release];
    }

    printf("OpenGLES bridge smoke: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
