#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ES3 headers omit extension prototypes once an operation is promoted, but
 * the bridge intentionally exports both spellings as address-identical
 * symbols for older binaries. */
extern void glBeginQueryEXT(GLenum target, GLuint id);
extern void glBindVertexArrayOES(GLuint array);
extern GLvoid *glMapBufferRangeEXT(GLenum target, GLintptr offset,
                                  GLsizeiptr length, GLbitfield access);
extern void glWaitSyncAPPLE(GLsync sync, GLbitfield flags, GLuint64 timeout);

static int es3Failures;

#define ES3_CHECK(condition, label) do {                                  \
    if(condition) {                                                       \
        printf("PASS %s\n", label);                                      \
    } else {                                                              \
        fprintf(stderr, "FAIL %s\n", label);                            \
        es3Failures++;                                                    \
    }                                                                     \
} while(0)

static int es3_gl_ok(const char *label) {
    GLenum error = glGetError();
    if(error == GL_NO_ERROR) {
        printf("PASS %s\n", label);
        return 1;
    }
    fprintf(stderr, "FAIL %s (OpenGL ES error 0x%x)\n", label, error);
    es3Failures++;
    return 0;
}

static int float_near(GLfloat left, GLfloat right) {
    return fabsf(left - right) <= 0.0001f;
}

static GLuint compile_es3_shader(GLenum type, GLsizei count,
                                 const GLchar *const *sources,
                                 const char *label) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, count, sources, NULL);
    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if(compiled != GL_TRUE) {
        GLchar log[1024] = {};
        glGetShaderInfoLog(shader, sizeof(log), NULL, log);
        fprintf(stderr, "FAIL %s: %s\n", label, log);
        es3Failures++;
        glDeleteShader(shader);
        return 0;
    }
    printf("PASS %s\n", label);
    return shader;
}

static void test_es3_sampler_objects(void) {
    struct {
        uint32_t before;
        GLuint names[2];
        uint32_t after;
    } samplers = {
        .before = 0x10203040,
        .after = 0x40302010,
    };
    glGenSamplers(2, samplers.names);
    ES3_CHECK(samplers.names[0] != 0 && samplers.names[1] != 0 &&
              samplers.names[0] != samplers.names[1],
              "ES3-sampler-name-array-copyback");
    ES3_CHECK(samplers.before == 0x10203040 &&
              samplers.after == 0x40302010,
              "ES3-sampler-name-array-canaries");

    glBindSampler(0, samplers.names[0]);
    ES3_CHECK(glIsSampler(samplers.names[0]) == GL_TRUE,
              "ES3-sampler-object-recognition");
    glSamplerParameteri(samplers.names[0], GL_TEXTURE_MIN_FILTER,
                        GL_NEAREST);
    glSamplerParameterf(samplers.names[0], GL_TEXTURE_MAX_LOD, 3.5f);
    GLint minimumFilter = 0;
    GLfloat maximumLod = 0.0f;
    glGetSamplerParameteriv(samplers.names[0], GL_TEXTURE_MIN_FILTER,
                            &minimumFilter);
    glGetSamplerParameterfv(samplers.names[0], GL_TEXTURE_MAX_LOD,
                            &maximumLod);
    ES3_CHECK(minimumFilter == GL_NEAREST &&
              float_near(maximumLod, 3.5f),
              "ES3-sampler-parameter-roundtrip");
    glBindSampler(0, 0);
    glDeleteSamplers(2, samplers.names);
    ES3_CHECK(glIsSampler(samplers.names[0]) == GL_FALSE,
              "ES3-deleted-sampler-rejection");
    es3_gl_ok("ES3-sampler-object-error");
}

static void test_es3_texture_arrays(void) {
    GLuint immutableTexture = 0;
    GLuint imageTexture = 0;
    GLuint pixelStoreTexture = 0;
    GLuint pixelBuffer = 0;
    GLuint compressedTexture = 0;
    GLuint framebuffer = 0;
    glGenTextures(1, &immutableTexture);
    glBindTexture(GL_TEXTURE_2D_ARRAY, immutableTexture);
    glTexStorage3D(GL_TEXTURE_2D_ARRAY, 1, GL_RGBA8, 2, 2, 2);

    const GLubyte greenLayer[16] = {
        0, 255, 0, 255, 0, 255, 0, 255,
        0, 255, 0, 255, 0, 255, 0, 255,
    };
    glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, 1, 2, 2, 1,
                    GL_RGBA, GL_UNSIGNED_BYTE, greenLayer);

    GLubyte volume[32];
    memset(volume, 0, sizeof(volume));
    for(size_t offset = 0; offset < sizeof(volume); offset += 4) {
        volume[offset + 2] = 255;
        volume[offset + 3] = 255;
    }
    glGenTextures(1, &imageTexture);
    glBindTexture(GL_TEXTURE_2D_ARRAY, imageTexture);
    glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA8, 2, 2, 2, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, volume);
    es3_gl_ok("ES3-three-dimensional-texture-upload");

    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              immutableTexture, 0, 1);
    ES3_CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
                  GL_FRAMEBUFFER_COMPLETE,
              "ES3-framebuffer-texture-layer-complete");
    const GLenum drawBuffer = GL_COLOR_ATTACHMENT0;
    glDrawBuffers(1, &drawBuffer);
    glReadBuffer(GL_COLOR_ATTACHMENT0);
    GLubyte pixel[4] = {};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    ES3_CHECK(pixel[0] <= 7 && pixel[1] >= 248 && pixel[2] <= 7 &&
              pixel[3] >= 248,
              "ES3-texture-array-layer-readback");

    const GLfloat red[4] = {1.0f, 0.0f, 0.0f, 1.0f};
    glClearBufferfv(GL_COLOR, 0, red);
    memset(pixel, 0, sizeof(pixel));
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    ES3_CHECK(pixel[0] >= 248 && pixel[1] <= 7 && pixel[2] <= 7 &&
              pixel[3] >= 248,
              "ES3-clear-buffer-vector-readback");

    GLubyte skippedReadback[20];
    memset(skippedReadback, 0x5a, sizeof(skippedReadback));
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glPixelStorei(GL_PACK_ROW_LENGTH, 3);
    glPixelStorei(GL_PACK_SKIP_ROWS, 1);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 1);
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE,
                 skippedReadback);
    glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    int packCanaries = 1;
    for(size_t index = 0; index < sizeof(skippedReadback); ++index) {
        if(index >= 16 && index < 20) continue;
        if(skippedReadback[index] != 0x5a) packCanaries = 0;
    }
    ES3_CHECK(packCanaries && skippedReadback[16] >= 248 &&
              skippedReadback[17] <= 7 && skippedReadback[18] <= 7 &&
              skippedReadback[19] >= 248,
              "ES3-pack-row-skip-copyback");

    GLubyte upload[20];
    memset(upload, 0x33, sizeof(upload));
    upload[16] = 0;
    upload[17] = 255;
    upload[18] = 0;
    upload[19] = 255;
    glGenTextures(1, &pixelStoreTexture);
    glBindTexture(GL_TEXTURE_2D, pixelStoreTexture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 3);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 1);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, upload);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, pixelStoreTexture, 0);
    memset(pixel, 0, sizeof(pixel));
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    ES3_CHECK(pixel[0] <= 7 && pixel[1] >= 248 && pixel[2] <= 7 &&
              pixel[3] >= 248,
              "ES3-unpack-row-skip-texture-upload");

    const GLubyte pboUpload[8] = {0x44, 0x44, 0x44, 0x44,
                                  0, 0, 255, 255};
    glGenBuffers(1, &pixelBuffer);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pixelBuffer);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, sizeof(pboUpload), pboUpload,
                 GL_STATIC_DRAW);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, (const GLvoid *)(uintptr_t)4);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    memset(pixel, 0, sizeof(pixel));
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    ES3_CHECK(pixel[0] <= 7 && pixel[1] <= 7 && pixel[2] >= 248 &&
              pixel[3] >= 248,
              "ES3-unpack-PBO-offset-texture-upload");

    const GLubyte pboSeed[8] = {0x66, 0x66, 0x66, 0x66,
                                0x66, 0x66, 0x66, 0x66};
    glBindBuffer(GL_PIXEL_PACK_BUFFER, pixelBuffer);
    glBufferData(GL_PIXEL_PACK_BUFFER, sizeof(pboSeed), pboSeed,
                 GL_STREAM_READ);
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE,
                 (GLvoid *)(uintptr_t)4);
    const GLubyte *mappedPixels = (const GLubyte *)glMapBufferRange(
        GL_PIXEL_PACK_BUFFER, 0, sizeof(pboSeed), GL_MAP_READ_BIT);
    ES3_CHECK(mappedPixels && mappedPixels[0] == 0x66 &&
              mappedPixels[3] == 0x66 && mappedPixels[4] <= 7 &&
              mappedPixels[5] <= 7 && mappedPixels[6] >= 248 &&
              mappedPixels[7] >= 248,
              "ES3-pack-PBO-offset-copyback");
    if(mappedPixels) glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    es3_gl_ok("ES3-pixel-store-and-PBO-error");

    glGenTextures(1, &compressedTexture);
    glBindTexture(GL_TEXTURE_2D, compressedTexture);
    glCompressedTexImage2D(GL_TEXTURE_2D, 0,
                           GL_COMPRESSED_RGBA8_ETC2_EAC,
                           4, 4, 0, 16, NULL);
    es3_gl_ok("ES3-compressed-2D-null-allocation");
    GLubyte compressedPBO[20] = {};
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pixelBuffer);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, sizeof(compressedPBO),
                 compressedPBO, GL_STATIC_DRAW);
    glCompressedTexImage2D(GL_TEXTURE_2D, 0,
                           GL_COMPRESSED_RGBA8_ETC2_EAC,
                           4, 4, 0, 16,
                           (const GLvoid *)(uintptr_t)4);
    glCompressedTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 4, 4,
                              GL_COMPRESSED_RGBA8_ETC2_EAC, 16,
                              (const GLvoid *)(uintptr_t)4);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    es3_gl_ok("ES3-compressed-2D-PBO-offset");
    es3_gl_ok("ES3-texture-array-framebuffer-error");

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    if(compressedTexture) glDeleteTextures(1, &compressedTexture);
    if(pixelBuffer) glDeleteBuffers(1, &pixelBuffer);
    if(pixelStoreTexture) glDeleteTextures(1, &pixelStoreTexture);
    if(framebuffer) glDeleteFramebuffers(1, &framebuffer);
    if(imageTexture) glDeleteTextures(1, &imageTexture);
    if(immutableTexture) glDeleteTextures(1, &immutableTexture);
}

static void test_es3_program_and_transform_feedback(void) {
    const GLchar *vertexParts[] = {
        "#version 300 es\n",
        "layout(location = 0) in vec2 position;\n",
        "out vec2 captured; out float marker;\n",
        "layout(std140) uniform Params { vec4 scale; };\n",
        ("void main() { captured = position; marker = 1.0; "
         "gl_Position = vec4(position * scale.xy, 0.0, 1.0); }\n"),
    };
    const GLchar *fragmentParts[] = {
        "#version 300 es\n",
        "precision mediump float; precision highp int;\n",
        "in vec2 captured; in float marker;\n",
        "uniform highp uvec4 flags; uniform highp mat2x3 shape;\n",
        "out vec4 color;\n",
        ("void main() { color = vec4(captured * 0.000001, marker * "
         "0.000001 + float(flags.x) * 0.000001 + "
         "shape[0][0] * 0.000001, 1.0); }\n"),
    };
    GLuint vertexShader = compile_es3_shader(
        GL_VERTEX_SHADER,
        (GLsizei)(sizeof(vertexParts) / sizeof(vertexParts[0])),
        vertexParts, "ES3-compile-vertex-shader");
    GLuint fragmentShader = compile_es3_shader(
        GL_FRAGMENT_SHADER,
        (GLsizei)(sizeof(fragmentParts) / sizeof(fragmentParts[0])),
        fragmentParts, "ES3-compile-fragment-shader");
    if(!vertexShader || !fragmentShader) goto cleanup_shaders;

    GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    const GLchar *varyings[] = {"captured", "marker"};
    glTransformFeedbackVaryings(program, 2, varyings,
                                GL_INTERLEAVED_ATTRIBS);
    glProgramParameteri(program, GL_PROGRAM_BINARY_RETRIEVABLE_HINT,
                        GL_TRUE);
    glLinkProgram(program);
    GLint linked = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if(linked != GL_TRUE) {
        GLchar log[1024] = {};
        glGetProgramInfoLog(program, sizeof(log), NULL, log);
        fprintf(stderr, "FAIL ES3-link-program: %s\n", log);
        es3Failures++;
        goto cleanup_program;
    }
    printf("PASS ES3-link-program\n");

    GLint varyingCount = 0;
    glGetProgramiv(program, GL_TRANSFORM_FEEDBACK_VARYINGS, &varyingCount);
    ES3_CHECK(varyingCount == 2,
              "ES3-transform-feedback-varying-count-copyback");
    struct {
        GLchar name[32];
        uint32_t canary;
    } varyingOutput;
    memset(&varyingOutput, 0xa5, sizeof(varyingOutput));
    varyingOutput.canary = 0xa1b2c3d4;
    GLsizei varyingLength = -1;
    GLsizei varyingSize = -1;
    GLenum varyingType = 0;
    glGetTransformFeedbackVarying(program, 0,
        sizeof(varyingOutput.name), &varyingLength, &varyingSize,
        &varyingType, varyingOutput.name);
    ES3_CHECK(varyingLength == 8 && varyingSize == 1 &&
              varyingType == GL_FLOAT_VEC2 &&
              strcmp(varyingOutput.name, "captured") == 0,
              "ES3-transform-feedback-varying-copyback");
    ES3_CHECK(varyingOutput.canary == 0xa1b2c3d4,
              "ES3-transform-feedback-varying-canary");

    GLuint block = glGetUniformBlockIndex(program, "Params");
    ES3_CHECK(block != GL_INVALID_INDEX,
              "ES3-uniform-block-index-string-copy");
    GLint blockSize = 0;
    if(block != GL_INVALID_INDEX)
        glGetActiveUniformBlockiv(program, block,
                                  GL_UNIFORM_BLOCK_DATA_SIZE, &blockSize);
    ES3_CHECK(blockSize >= (GLint)(4 * sizeof(GLfloat)),
              "ES3-uniform-block-size-copyback");
    struct {
        GLchar name[16];
        uint32_t canary;
    } blockName;
    memset(&blockName, 0xa5, sizeof(blockName));
    blockName.canary = 0xdeadbeef;
    GLsizei blockNameLength = -1;
    if(block != GL_INVALID_INDEX) {
        glGetActiveUniformBlockName(program, block,
            sizeof(blockName.name), &blockNameLength, blockName.name);
    }
    ES3_CHECK(blockNameLength == 6 &&
              strcmp(blockName.name, "Params") == 0,
              "ES3-uniform-block-name-copyback");
    ES3_CHECK(blockName.canary == 0xdeadbeef,
              "ES3-uniform-block-name-canary");

    const GLchar *uniformNames[] = {"scale", "Params.scale"};
    GLuint uniformIndices[2] = {GL_INVALID_INDEX, GL_INVALID_INDEX};
    glGetUniformIndices(program, 2, uniformNames, uniformIndices);
    GLuint scaleIndex = uniformIndices[0] != GL_INVALID_INDEX
        ? uniformIndices[0] : uniformIndices[1];
    ES3_CHECK(scaleIndex != GL_INVALID_INDEX,
              "ES3-nested-uniform-name-array-copy");
    GLint uniformOffset = -1;
    if(scaleIndex != GL_INVALID_INDEX) {
        glGetActiveUniformsiv(program, 1, &scaleIndex,
                              GL_UNIFORM_OFFSET, &uniformOffset);
    }
    ES3_CHECK(uniformOffset >= 0,
              "ES3-active-uniform-array-copyback");

    glUseProgram(program);
    GLint flagsLocation = glGetUniformLocation(program, "flags");
    GLint shapeLocation = glGetUniformLocation(program, "shape");
    ES3_CHECK(flagsLocation >= 0 && shapeLocation >= 0,
              "ES3-unsigned-and-matrix-uniform-locations");
    const GLuint flags[4] = {1, 2, 3, 4};
    GLuint copiedFlags[4] = {};
    if(flagsLocation >= 0) {
        glUniform4uiv(flagsLocation, 1, flags);
        glGetUniformuiv(program, flagsLocation, copiedFlags);
    }
    ES3_CHECK(memcmp(flags, copiedFlags, sizeof(flags)) == 0,
              "ES3-unsigned-uniform-vector-roundtrip");
    const GLfloat shape[6] = {1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f};
    GLfloat copiedShape[6] = {};
    if(shapeLocation >= 0) {
        glUniformMatrix2x3fv(shapeLocation, 1, GL_FALSE, shape);
        glGetUniformfv(program, shapeLocation, copiedShape);
    }
    ES3_CHECK(memcmp(shape, copiedShape, sizeof(shape)) == 0,
              "ES3-nonsquare-matrix-uniform-roundtrip");

    GLuint uniformBuffer = 0;
    const GLfloat blockValues[4] = {1.0f, 1.0f, 0.0f, 0.0f};
    glGenBuffers(1, &uniformBuffer);
    glBindBuffer(GL_UNIFORM_BUFFER, uniformBuffer);
    glBufferData(GL_UNIFORM_BUFFER, sizeof(blockValues), blockValues,
                 GL_STATIC_DRAW);
    GLint64 bufferSize = 0;
    glGetBufferParameteri64v(GL_UNIFORM_BUFFER, GL_BUFFER_SIZE, &bufferSize);
    ES3_CHECK(bufferSize == (GLint64)sizeof(blockValues),
              "ES3-64-bit-buffer-size-copyback");
    if(block != GL_INVALID_INDEX)
        glUniformBlockBinding(program, block, 2);
    glBindBufferRange(GL_UNIFORM_BUFFER, 2, uniformBuffer, 0,
                      sizeof(blockValues));
    GLint indexedBinding = 0;
    GLint64 indexedSize = 0;
    glGetIntegeri_v(GL_UNIFORM_BUFFER_BINDING, 2, &indexedBinding);
    glGetInteger64i_v(GL_UNIFORM_BUFFER_SIZE, 2, &indexedSize);
    ES3_CHECK(indexedBinding == (GLint)uniformBuffer &&
              indexedSize == (GLint64)sizeof(blockValues),
              "ES3-indexed-buffer-state-copyback");

    const GLint signedAttribute[4] = {-1, 2, -3, 4};
    GLint signedAttributeOutput[4] = {};
    glVertexAttribI4iv(3, signedAttribute);
    glGetVertexAttribIiv(3, GL_CURRENT_VERTEX_ATTRIB,
                         signedAttributeOutput);
    ES3_CHECK(memcmp(signedAttribute, signedAttributeOutput,
                     sizeof(signedAttribute)) == 0,
              "ES3-signed-integer-attribute-roundtrip");
    const GLuint unsignedAttribute[4] = {5, 6, 7, 8};
    GLuint unsignedAttributeOutput[4] = {};
    glVertexAttribI4uiv(4, unsignedAttribute);
    glGetVertexAttribIuiv(4, GL_CURRENT_VERTEX_ATTRIB,
                          unsignedAttributeOutput);
    ES3_CHECK(memcmp(unsignedAttribute, unsignedAttributeOutput,
                     sizeof(unsignedAttribute)) == 0,
              "ES3-unsigned-integer-attribute-roundtrip");

    GLuint vertexArray = 0;
    GLuint vertexBuffer = 0;
    GLuint feedbackBuffer = 0;
    GLuint feedback = 0;
    GLuint feedbackFramebuffer = 0;
    GLuint feedbackRenderbuffer = 0;
    const GLfloat positions[6] = {
        -0.5f, -0.5f,
         0.5f, -0.5f,
         0.0f,  0.5f,
    };
    glGenVertexArrays(1, &vertexArray);
    glBindVertexArray(vertexArray);
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(positions), positions,
                 GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0,
                          (const GLvoid *)0);
    glVertexAttribIPointer(3, 2, GL_INT, 0, (const GLvoid *)0);
    GLvoid *integerPointer = (GLvoid *)(uintptr_t)1;
    glGetVertexAttribPointerv(3, GL_VERTEX_ATTRIB_ARRAY_POINTER,
                              &integerPointer);
    ES3_CHECK(integerPointer == NULL,
              "ES3-integer-attribute-VBO-offset-copyback");

    glGenBuffers(1, &feedbackBuffer);
    glGenTransformFeedbacks(1, &feedback);
    glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, feedback);
    ES3_CHECK(glIsTransformFeedback(feedback) == GL_TRUE,
              "ES3-transform-feedback-object-recognition");
    glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, feedbackBuffer);
    glBufferData(GL_TRANSFORM_FEEDBACK_BUFFER,
                 3 * 3 * sizeof(GLfloat), NULL, GL_DYNAMIC_COPY);
    glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, feedbackBuffer);
    GLint feedbackBinding = 0;
    glGetIntegeri_v(GL_TRANSFORM_FEEDBACK_BUFFER_BINDING, 0,
                    &feedbackBinding);
    ES3_CHECK(feedbackBinding == (GLint)feedbackBuffer,
              "ES3-transform-feedback-binding-copyback");
    glGenRenderbuffers(1, &feedbackRenderbuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, feedbackRenderbuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, 1, 1);
    glGenFramebuffers(1, &feedbackFramebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, feedbackFramebuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, feedbackRenderbuffer);
    ES3_CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
                  GL_FRAMEBUFFER_COMPLETE,
              "ES3-transform-feedback-framebuffer-complete");
    glEnable(GL_RASTERIZER_DISCARD);
    glBeginTransformFeedback(GL_TRIANGLES);
    glPauseTransformFeedback();
    glResumeTransformFeedback();
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glEndTransformFeedback();
    glDisable(GL_RASTERIZER_DISCARD);
    glFinish();
    if(es3_gl_ok("ES3-transform-feedback-capture-error")) {
        glBindBuffer(GL_ARRAY_BUFFER, feedbackBuffer);
        const GLfloat *captured = (const GLfloat *)glMapBufferRange(
            GL_ARRAY_BUFFER, 0, 3 * 3 * sizeof(GLfloat), GL_MAP_READ_BIT);
        ES3_CHECK(captured != NULL,
                  "ES3-core-map-buffer-range-shadow");
        if(captured) {
            int matches = 1;
            for(unsigned vertex = 0; vertex < 3; ++vertex) {
                if(!float_near(captured[vertex * 3],
                               positions[vertex * 2]) ||
                   !float_near(captured[vertex * 3 + 1],
                               positions[vertex * 2 + 1]) ||
                   !float_near(captured[vertex * 3 + 2], 1.0f)) {
                    matches = 0;
                }
            }
            ES3_CHECK(matches, "ES3-transform-feedback-shadow-readback");
            ES3_CHECK(glUnmapBuffer(GL_ARRAY_BUFFER) == GL_TRUE,
                      "ES3-core-unmap-buffer-shadow");
        }
    }

    GLint binaryLength = 0;
    GLint binaryFormatCount = 0;
    glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, &binaryFormatCount);
    glGetProgramiv(program, GL_PROGRAM_BINARY_LENGTH, &binaryLength);
    if(binaryFormatCount > 0 && binaryLength > 0) {
        const size_t allocation = (size_t)binaryLength + 8;
        GLubyte *binary = (GLubyte *)malloc(allocation);
        if(binary) {
            memset(binary, 0xa5, allocation);
            GLenum format = 0;
            GLsizei written = 0;
            glGetProgramBinary(program, binaryLength, &written, &format,
                               binary);
            int canary = 1;
            for(size_t index = (size_t)binaryLength;
                    index < allocation; ++index) {
                if(binary[index] != 0xa5) canary = 0;
            }
            ES3_CHECK(written > 0 && written <= binaryLength && format != 0,
                      "ES3-program-binary-copyback");
            ES3_CHECK(canary, "ES3-program-binary-copyback-canary");
            GLuint binaryProgram = glCreateProgram();
            glProgramBinary(binaryProgram, format, binary, written);
            GLint binaryLinked = GL_FALSE;
            glGetProgramiv(binaryProgram, GL_LINK_STATUS, &binaryLinked);
            ES3_CHECK(binaryLinked == GL_TRUE,
                      "ES3-program-binary-input-copy");
            glDeleteProgram(binaryProgram);
            free(binary);
        } else {
            ES3_CHECK(0, "ES3-program-binary-allocation");
        }
    } else {
        printf("SKIP ES3-program-binary-copy: backend exposes no format\n");
    }

    glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, 0);
    if(feedback) glDeleteTransformFeedbacks(1, &feedback);
    if(feedbackBuffer) glDeleteBuffers(1, &feedbackBuffer);
    if(vertexBuffer) glDeleteBuffers(1, &vertexBuffer);
    if(vertexArray) glDeleteVertexArrays(1, &vertexArray);
    if(feedbackFramebuffer)
        glDeleteFramebuffers(1, &feedbackFramebuffer);
    if(feedbackRenderbuffer)
        glDeleteRenderbuffers(1, &feedbackRenderbuffer);
    if(uniformBuffer) glDeleteBuffers(1, &uniformBuffer);
    es3_gl_ok("ES3-program-and-buffer-error");

cleanup_program:
    if(program) glDeleteProgram(program);
cleanup_shaders:
    if(vertexShader) glDeleteShader(vertexShader);
    if(fragmentShader) glDeleteShader(fragmentShader);
}

int run_opengles_es3_smoke(void) {
    @autoreleasepool {
        EAGLContext *context =
            [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
        if(!context) {
            printf("SKIP create-ES3-context: backend has no OpenGL ES 3 "
                   "runtime\n");
            return 0;
        }
        if(![EAGLContext setCurrentContext:context]) {
            ES3_CHECK(0, "set-current-ES3-context");
            [context release];
            return es3Failures;
        }
        ES3_CHECK(1, "set-current-ES3-context");

        GLint extensionCount = -1;
        glGetIntegerv(GL_NUM_EXTENSIONS, &extensionCount);
        ES3_CHECK(extensionCount >= 0,
                  "ES3-extension-count-copyback");
        if(extensionCount > 0) {
            const GLubyte *extension = glGetStringi(GL_EXTENSIONS, 0);
            ES3_CHECK(extension != NULL && extension[0] != '\0',
                      "ES3-indexed-string-guest-copy");
            ES3_CHECK(glGetStringi(GL_EXTENSIONS, 0) == extension,
                      "ES3-indexed-string-cache");
        }

        ES3_CHECK((uintptr_t)glBeginQuery == (uintptr_t)glBeginQueryEXT &&
                  (uintptr_t)glBindVertexArray ==
                      (uintptr_t)glBindVertexArrayOES &&
                  (uintptr_t)glMapBufferRange ==
                      (uintptr_t)glMapBufferRangeEXT &&
                  (uintptr_t)glWaitSync == (uintptr_t)glWaitSyncAPPLE,
                  "ES3-promoted-entrypoint-address-aliases");

        test_es3_sampler_objects();
        test_es3_texture_arrays();
        test_es3_program_and_transform_feedback();

        [EAGLContext setCurrentContext:nil];
        [context release];
    }

    return es3Failures;
}
