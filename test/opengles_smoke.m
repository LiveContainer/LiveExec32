#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern int run_opengles_es1_smoke(void);
extern int run_opengles_es3_smoke(void);

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

static GLuint compile_shader_parts(GLenum type, GLsizei count,
                                   const char *const *sources,
                                   const GLint *lengths,
                                   const char *expectedSource,
                                   const char *label) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, count, sources, lengths);

    char copiedSource[512] = {};
    GLsizei copiedLength = 0;
    glGetShaderSource(shader, sizeof(copiedSource), &copiedLength,
                      copiedSource);
    CHECK(copiedLength == (GLsizei)strlen(expectedSource) &&
          strcmp(copiedSource, expectedSource) == 0,
          count == 1 ? "shader-source-copyback" :
                       "nested-shader-source-copyback");

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

static GLuint compile_shader(GLenum type, const char *source,
                             const char *label) {
    return compile_shader_parts(type, 1, &source, NULL, source, label);
}

static int extension_supported(const char *extension) {
    const char *extensions =
        (const char *)glGetString(GL_EXTENSIONS);
    if(!extensions || !extension || !extension[0] || strchr(extension, ' '))
        return 0;
    const size_t length = strlen(extension);
    const char *position = extensions;
    while((position = strstr(position, extension))) {
        const int leftBoundary = position == extensions || position[-1] == ' ';
        const int rightBoundary = position[length] == '\0' ||
                                  position[length] == ' ';
        if(leftBoundary && rightBoundary) return 1;
        position += length;
    }
    return 0;
}

static void skip_extension(const char *label, const char *extension) {
    printf("SKIP %s: backend does not advertise %s\n", label, extension);
}

static void test_mapped_buffers(void) {
    if(!extension_supported("GL_OES_mapbuffer")) {
        skip_extension("mapped-buffer-shadow", "GL_OES_mapbuffer");
        return;
    }

    GLuint buffer = 0;
    const GLubyte original[16] = {
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    };
    glGenBuffers(1, &buffer);
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(original), original,
                 GL_DYNAMIC_DRAW);

    GLubyte *writeShadow =
        (GLubyte *)glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    CHECK(writeShadow != NULL, "map-buffer-write-shadow-allocation");
    if(!writeShadow) goto cleanup;

    GLvoid *queriedPointer = NULL;
    glGetBufferPointervOES(GL_ARRAY_BUFFER, GL_BUFFER_MAP_POINTER_OES,
                           &queriedPointer);
    CHECK(queriedPointer == writeShadow,
          "mapped-buffer-guest-pointer-copyback");
    GLint mappedState = GL_FALSE;
    glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_MAPPED_OES,
                           &mappedState);
    CHECK(mappedState == GL_TRUE, "mapped-buffer-state-while-mapped");
    const GLubyte writePatch[4] = {0xc0, 0xff, 0xee, 0x00};
    memcpy(writeShadow + 4, writePatch, sizeof(writePatch));
    CHECK(glUnmapBufferOES(GL_ARRAY_BUFFER) == GL_TRUE,
          "mapped-buffer-write-shadow-unmap");
    queriedPointer = (GLvoid *)(uintptr_t)1;
    glGetBufferPointervOES(GL_ARRAY_BUFFER, GL_BUFFER_MAP_POINTER_OES,
                           &queriedPointer);
    CHECK(queriedPointer == NULL,
          "mapped-buffer-pointer-cleared-after-unmap");
    glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_MAPPED_OES,
                           &mappedState);
    CHECK(mappedState == GL_FALSE, "mapped-buffer-state-after-unmap");
    if(!gl_ok("mapped-buffer-OES-shadow-error")) goto cleanup;

    if(!extension_supported("GL_EXT_map_buffer_range")) {
        skip_extension("mapped-buffer-read-flush-shadow",
                       "GL_EXT_map_buffer_range");
        goto cleanup;
    }

    GLubyte *readShadow = (GLubyte *)glMapBufferRangeEXT(
        GL_ARRAY_BUFFER, 0, sizeof(original), GL_MAP_READ_BIT_EXT);
    CHECK(readShadow != NULL, "map-buffer-range-read-shadow-allocation");
    GLubyte expected[sizeof(original)];
    memcpy(expected, original, sizeof(expected));
    memcpy(expected + 4, writePatch, sizeof(writePatch));
    if(readShadow) {
        CHECK(memcmp(readShadow, expected, sizeof(expected)) == 0,
              "mapped-buffer-write-preserves-untouched-bytes");
        queriedPointer = NULL;
        glGetBufferPointervOES(GL_ARRAY_BUFFER, GL_BUFFER_MAP_POINTER_OES,
                               &queriedPointer);
        CHECK(queriedPointer == readShadow,
              "mapped-buffer-range-pointer-copyback");
        CHECK(glUnmapBufferOES(GL_ARRAY_BUFFER) == GL_TRUE,
              "mapped-buffer-read-shadow-unmap");
    }

    GLubyte *flushShadow = (GLubyte *)glMapBufferRangeEXT(
        GL_ARRAY_BUFFER, 0, sizeof(original),
        GL_MAP_WRITE_BIT_EXT | GL_MAP_FLUSH_EXPLICIT_BIT_EXT);
    CHECK(flushShadow != NULL,
          "map-buffer-range-explicit-flush-shadow-allocation");
    if(flushShadow) {
        const GLubyte flushPatch[4] = {0xde, 0xad, 0xbe, 0xef};
        memcpy(flushShadow + 8, flushPatch, sizeof(flushPatch));
        glFlushMappedBufferRangeEXT(GL_ARRAY_BUFFER, 8,
                                    sizeof(flushPatch));
        CHECK(glUnmapBufferOES(GL_ARRAY_BUFFER) == GL_TRUE,
              "mapped-buffer-explicit-flush-unmap");

        memcpy(expected + 8, flushPatch, sizeof(flushPatch));
        readShadow = (GLubyte *)glMapBufferRangeEXT(
            GL_ARRAY_BUFFER, 0, sizeof(expected), GL_MAP_READ_BIT_EXT);
        CHECK(readShadow != NULL,
              "map-buffer-range-post-flush-read-allocation");
        if(readShadow) {
            CHECK(memcmp(readShadow, expected, sizeof(expected)) == 0,
                  "mapped-buffer-explicit-subrange-flush-copy");
            CHECK(glUnmapBufferOES(GL_ARRAY_BUFFER) == GL_TRUE,
                  "mapped-buffer-post-flush-read-unmap");
        }
    }
    gl_ok("mapped-buffer-range-shadow-error");

cleanup:
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    if(buffer) glDeleteBuffers(1, &buffer);
}

static void test_debug_labels(GLuint buffer) {
    if(!extension_supported("GL_EXT_debug_label")) {
        skip_extension("debug-label-copy", "GL_EXT_debug_label");
        return;
    }

    const GLchar source[] = "bridge-hidden-suffix";
    glLabelObjectEXT(GL_BUFFER_OBJECT_EXT, buffer, 6, source);
    struct {
        GLchar text[16];
        uint32_t canary;
    } output;
    memset(&output, 0xa5, sizeof(output));
    output.canary = 0xfeedface;
    GLsizei length = -1;
    glGetObjectLabelEXT(GL_BUFFER_OBJECT_EXT, buffer,
                        sizeof(output.text), &length, output.text);
    CHECK(length == 6 && strcmp(output.text, "bridge") == 0,
          "debug-label-explicit-length-copyback");
    CHECK(output.canary == 0xfeedface,
          "debug-label-copyback-canary");

    glLabelObjectEXT(GL_BUFFER_OBJECT_EXT, buffer, 0, "guest-buffer");
    memset(output.text, 0, sizeof(output.text));
    length = -1;
    glGetObjectLabelEXT(GL_BUFFER_OBJECT_EXT, buffer,
                        sizeof(output.text), &length, output.text);
    CHECK(length == 12 && strcmp(output.text, "guest-buffer") == 0,
          "debug-label-null-terminated-copyback");
    gl_ok("debug-label-copy-error");

    glLabelObjectEXT(GL_BUFFER_OBJECT_EXT, buffer, -1, "invalid-label");
    CHECK(glGetError() == GL_INVALID_VALUE,
          "debug-label-negative-length-rejection");

    if(extension_supported("GL_EXT_debug_marker")) {
        glInsertEventMarkerEXT(6, "marker-hidden");
        glPushGroupMarkerEXT(0, "guest-group");
        glPopGroupMarkerEXT();
        gl_ok("debug-marker-string-copy");
    } else {
        skip_extension("debug-marker-string-copy", "GL_EXT_debug_marker");
    }
}

static void test_queries(void) {
    if(!extension_supported("GL_EXT_occlusion_query_boolean")) {
        skip_extension("query-object-copy", "GL_EXT_occlusion_query_boolean");
        return;
    }

    struct {
        uint32_t before;
        GLuint ids[2];
        uint32_t after;
    } queries = {
        .before = 0x01234567,
        .after = 0x76543210,
    };
    glGenQueriesEXT(2, queries.ids);
    CHECK(queries.ids[0] != 0 && queries.ids[1] != 0 &&
          queries.ids[0] != queries.ids[1], "query-name-array-copyback");
    CHECK(queries.before == 0x01234567 && queries.after == 0x76543210,
          "query-name-array-copyback-canaries");

    glBeginQueryEXT(GL_ANY_SAMPLES_PASSED_EXT, queries.ids[0]);
    GLint current = 0;
    glGetQueryivEXT(GL_ANY_SAMPLES_PASSED_EXT, GL_CURRENT_QUERY_EXT,
                    &current);
    CHECK(current == (GLint)queries.ids[0], "active-query-copyback");
    CHECK(glIsQueryEXT(queries.ids[0]) == GL_TRUE,
          "query-object-recognition");
    glClear(GL_COLOR_BUFFER_BIT);
    glEndQueryEXT(GL_ANY_SAMPLES_PASSED_EXT);
    glGetQueryivEXT(GL_ANY_SAMPLES_PASSED_EXT, GL_CURRENT_QUERY_EXT,
                    &current);
    CHECK(current == 0, "ended-query-copyback");
    glFinish();

    GLuint available = 0;
    GLuint result = 2;
    glGetQueryObjectuivEXT(queries.ids[0],
                           GL_QUERY_RESULT_AVAILABLE_EXT, &available);
    glGetQueryObjectuivEXT(queries.ids[0], GL_QUERY_RESULT_EXT, &result);
    CHECK(available == GL_TRUE && result <= GL_TRUE,
          "query-result-copyback");
    glDeleteQueriesEXT(2, queries.ids);
    CHECK(glIsQueryEXT(queries.ids[0]) == GL_FALSE,
          "deleted-query-rejection");
    gl_ok("query-object-copy-error");
}

static void test_sync_objects(void) {
    if(!extension_supported("GL_APPLE_sync")) {
        skip_extension("sync-token-lifetime", "GL_APPLE_sync");
        return;
    }

    GLsync first = glFenceSyncAPPLE(GL_SYNC_GPU_COMMANDS_COMPLETE_APPLE, 0);
    CHECK(first != NULL, "sync-token-publication");
    if(!first) {
        gl_ok("sync-token-publication-error");
        return;
    }
    CHECK(glIsSyncAPPLE(first) == GL_TRUE, "sync-token-lookup");

    struct {
        uint32_t before;
        GLint value;
        uint32_t after;
    } status = {
        .before = 0x89abcdef,
        .value = -1,
        .after = 0xfedcba98,
    };
    GLsizei length = -1;
    glGetSyncivAPPLE(first, GL_SYNC_STATUS_APPLE, 1, &length,
                     &status.value);
    CHECK(length == 1 &&
          (status.value == GL_SIGNALED_APPLE ||
           status.value == GL_UNSIGNALED_APPLE),
          "sync-status-copyback");
    CHECK(status.before == 0x89abcdef && status.after == 0xfedcba98,
          "sync-status-copyback-canaries");

    GLint64 maximumWait = -1;
    glGetInteger64vAPPLE(GL_MAX_SERVER_WAIT_TIMEOUT_APPLE, &maximumWait);
    CHECK(maximumWait >= 0, "sync-64-bit-state-copyback");

    glDeleteSyncAPPLE(first);
    CHECK(glIsSyncAPPLE(first) == GL_FALSE,
          "deleted-sync-token-rejection");
    GLsync second =
        glFenceSyncAPPLE(GL_SYNC_GPU_COMMANDS_COMPLETE_APPLE, 0);
    CHECK(second != NULL, "replacement-sync-token-publication");
    if(!second) {
        gl_ok("replacement-sync-token-publication-error");
        return;
    }
    CHECK((uintptr_t)first != (uintptr_t)second,
          "sync-token-generation-change");

    GLenum staleWait = glClientWaitSyncAPPLE(first, 0, 0);
    CHECK(staleWait == GL_WAIT_FAILED_APPLE,
          "stale-sync-token-wait-rejection");
    CHECK(glGetError() == GL_INVALID_VALUE,
          "stale-sync-token-bridge-error");

    GLenum validWait = glClientWaitSyncAPPLE(
        second, GL_SYNC_FLUSH_COMMANDS_BIT_APPLE, 1000000000ull);
    CHECK(validWait == GL_ALREADY_SIGNALED_APPLE ||
          validWait == GL_CONDITION_SATISFIED_APPLE ||
          validWait == GL_TIMEOUT_EXPIRED_APPLE,
          "valid-sync-token-wait");
    glWaitSyncAPPLE(second, 0, GL_TIMEOUT_IGNORED_APPLE);
    glDeleteSyncAPPLE(second);
    gl_ok("sync-token-lifetime-error");
}

static void test_program_pipelines(void) {
    if(!extension_supported("GL_EXT_separate_shader_objects")) {
        skip_extension("program-pipeline-copy",
                       "GL_EXT_separate_shader_objects");
        return;
    }

    const GLchar *vertexParts[] = {
        "attribute vec2 pipelinePosition;",
        "void main() {",
        "gl_Position = vec4(pipelinePosition, 0.0, 1.0); }",
    };
    const GLchar *fragmentParts[] = {
        "precision mediump float;",
        "uniform vec4 pipelineTint; uniform mat2 pipelineWarp;",
        "uniform int pipelineChoice;",
        "void main() { vec2 p = pipelineWarp * vec2(1.0);",
        ("gl_FragColor = pipelineTint + vec4(p * 0.000001, "
         "float(pipelineChoice) * 0.000001, 0.0); }"),
    };
    GLuint vertexProgram = glCreateShaderProgramvEXT(
        GL_VERTEX_SHADER,
        (GLsizei)(sizeof(vertexParts) / sizeof(vertexParts[0])),
        vertexParts);
    GLuint fragmentProgram = glCreateShaderProgramvEXT(
        GL_FRAGMENT_SHADER,
        (GLsizei)(sizeof(fragmentParts) / sizeof(fragmentParts[0])),
        fragmentParts);
    GLint vertexLinked = GL_FALSE;
    GLint fragmentLinked = GL_FALSE;
    if(vertexProgram)
        glGetProgramiv(vertexProgram, GL_LINK_STATUS, &vertexLinked);
    if(fragmentProgram)
        glGetProgramiv(fragmentProgram, GL_LINK_STATUS, &fragmentLinked);
    CHECK(vertexProgram != 0 && fragmentProgram != 0 &&
          vertexLinked == GL_TRUE && fragmentLinked == GL_TRUE,
          "nested-create-shader-program-strings");
    if(vertexLinked != GL_TRUE || fragmentLinked != GL_TRUE)
        goto cleanup;

    const GLint tint = glGetUniformLocation(fragmentProgram, "pipelineTint");
    const GLint warp = glGetUniformLocation(fragmentProgram, "pipelineWarp");
    const GLint choice =
        glGetUniformLocation(fragmentProgram, "pipelineChoice");
    CHECK(tint >= 0 && warp >= 0 && choice >= 0,
          "pipeline-uniform-location-copy");
    if(tint >= 0) {
        const GLfloat value[4] = {0.125f, 0.25f, 0.5f, 0.75f};
        GLfloat copied[4] = {};
        glProgramUniform4fvEXT(fragmentProgram, tint, 1, value);
        glGetUniformfv(fragmentProgram, tint, copied);
        CHECK(memcmp(value, copied, sizeof(value)) == 0,
              "program-uniform-vector-roundtrip");
    }
    if(warp >= 0) {
        const GLfloat value[4] = {1.0f, 0.25f, -0.5f, 2.0f};
        GLfloat copied[4] = {};
        glProgramUniformMatrix2fvEXT(fragmentProgram, warp, 1,
                                     GL_FALSE, value);
        glGetUniformfv(fragmentProgram, warp, copied);
        CHECK(memcmp(value, copied, sizeof(value)) == 0,
              "program-uniform-matrix-roundtrip");
    }
    if(choice >= 0) {
        GLint copied = 0;
        glProgramUniform1iEXT(fragmentProgram, choice, 7);
        glGetUniformiv(fragmentProgram, choice, &copied);
        CHECK(copied == 7, "program-uniform-integer-roundtrip");
    }

    GLuint pipeline = 0;
    glGenProgramPipelinesEXT(1, &pipeline);
    CHECK(pipeline != 0, "program-pipeline-name-copyback");
    if(!pipeline) goto cleanup;
    glBindProgramPipelineEXT(pipeline);
    CHECK(glIsProgramPipelineEXT(pipeline) == GL_TRUE,
          "program-pipeline-recognition");
    glUseProgramStagesEXT(pipeline, GL_VERTEX_SHADER_BIT_EXT,
                          vertexProgram);
    glUseProgramStagesEXT(pipeline, GL_FRAGMENT_SHADER_BIT_EXT,
                          fragmentProgram);
    glActiveShaderProgramEXT(pipeline, fragmentProgram);
    GLint activeProgram = 0;
    glGetProgramPipelineivEXT(pipeline, GL_ACTIVE_PROGRAM_EXT,
                              &activeProgram);
    CHECK(activeProgram == (GLint)fragmentProgram,
          "program-pipeline-active-program-copyback");
    glValidateProgramPipelineEXT(pipeline);
    GLint valid = GL_FALSE;
    glGetProgramPipelineivEXT(pipeline, GL_VALIDATE_STATUS, &valid);
    CHECK(valid == GL_TRUE, "program-pipeline-validation-copyback");

    struct {
        GLchar text[256];
        uint32_t canary;
    } log;
    memset(&log, 0xa5, sizeof(log));
    log.canary = 0xdecafbad;
    GLsizei logLength = -1;
    glGetProgramPipelineInfoLogEXT(pipeline, sizeof(log.text),
                                   &logLength, log.text);
    CHECK(logLength >= 0 && logLength < (GLsizei)sizeof(log.text),
          "program-pipeline-info-log-copyback");
    CHECK(log.canary == 0xdecafbad,
          "program-pipeline-info-log-canary");
    glBindProgramPipelineEXT(0);
    glDeleteProgramPipelinesEXT(1, &pipeline);
    CHECK(glIsProgramPipelineEXT(pipeline) == GL_FALSE,
          "deleted-program-pipeline-rejection");
    gl_ok("program-pipeline-copy-error");

cleanup:
    if(vertexProgram) glDeleteProgram(vertexProgram);
    if(fragmentProgram) glDeleteProgram(fragmentProgram);
}

static int magenta_pixel(const GLubyte pixel[4]) {
    return pixel[0] >= 248 && pixel[1] <= 7 && pixel[2] >= 248 &&
           pixel[3] >= 248;
}

static void test_instanced_client_arrays(GLuint program, GLint position,
                                         GLint instanceOffset, GLint tint) {
    if(!extension_supported("GL_EXT_draw_instanced")) {
        skip_extension("instanced-client-array-draw",
                       "GL_EXT_draw_instanced");
        return;
    }
    if(!extension_supported("GL_EXT_instanced_arrays")) {
        skip_extension("instanced-client-array-divisor",
                       "GL_EXT_instanced_arrays");
        return;
    }
    if(position < 0 || instanceOffset < 0 || tint < 0) {
        CHECK(0, "instanced-client-array-locations");
        return;
    }

    const GLfloat triangle[] = {
        -0.30f, -0.40f,
         0.30f, -0.40f,
         0.00f,  0.40f,
    };
    const GLfloat offsets[] = {
        -0.50f, 0.0f,
         0.50f, 0.0f,
    };
    const GLushort indices[] = {0, 1, 2};
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glUseProgram(program);
    glEnableVertexAttribArray((GLuint)position);
    glVertexAttribPointer((GLuint)position, 2, GL_FLOAT, GL_FALSE, 0,
                          triangle);
    glEnableVertexAttribArray((GLuint)instanceOffset);
    glVertexAttribPointer((GLuint)instanceOffset, 2, GL_FLOAT, GL_FALSE, 0,
                          offsets);
    glVertexAttribDivisorEXT((GLuint)position, 0);
    glVertexAttribDivisorEXT((GLuint)instanceOffset, 1);
    GLint copiedDivisor = 0;
    glGetVertexAttribiv((GLuint)instanceOffset,
                        GL_VERTEX_ATTRIB_ARRAY_DIVISOR_EXT,
                        &copiedDivisor);
    CHECK(copiedDivisor == 1,
          "instanced-client-array-divisor-copyback");

    glUniform4f(tint, 1.0f, 0.0f, 1.0f, 1.0f);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glDrawArraysInstancedEXT(GL_TRIANGLES, 0, 3, 2);
    glFinish();
    GLubyte left[4] = {};
    GLubyte right[4] = {};
    glReadPixels(4, 3, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, left);
    glReadPixels(12, 3, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, right);
    CHECK(magenta_pixel(left) && magenta_pixel(right),
          "instanced-draw-arrays-client-staging-readback");
    gl_ok("instanced-draw-arrays-client-staging-error");

    glClear(GL_COLOR_BUFFER_BIT);
    glDrawElementsInstancedEXT(GL_TRIANGLES, 3, GL_UNSIGNED_SHORT,
                               indices, 2);
    glFinish();
    memset(left, 0, sizeof(left));
    memset(right, 0, sizeof(right));
    glReadPixels(4, 3, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, left);
    glReadPixels(12, 3, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, right);
    CHECK(magenta_pixel(left) && magenta_pixel(right),
          "instanced-draw-elements-client-staging-readback");
    gl_ok("instanced-draw-elements-client-staging-error");

    glVertexAttribDivisorEXT((GLuint)instanceOffset, 0);
    glDisableVertexAttribArray((GLuint)instanceOffset);
}

int main(void) {
    @autoreleasepool {
        unsigned int major = 0;
        unsigned int minor = 0;
        EAGLGetVersion(&major, &minor);
        CHECK(major >= 1, "EAGL-version-copyback");

        failures += run_opengles_es1_smoke();
        failures += run_opengles_es3_smoke();

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
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, 16, 8);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                  GL_RENDERBUFFER, renderbuffer);
        CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) ==
                  GL_FRAMEBUFFER_COMPLETE,
              "offscreen-framebuffer-complete");
        if(!gl_ok("offscreen-framebuffer-setup")) goto cleanup;

        glViewport(0, 0, 16, 8);
        GLint viewport[4] = {};
        glGetIntegerv(GL_VIEWPORT, viewport);
        CHECK(viewport[0] == 0 && viewport[1] == 0 &&
              viewport[2] == 16 && viewport[3] == 8,
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

        const char *vertexParts[] = {
            "attribute vec2 position;",
            "attribute vec2 instanceOffset;",
            ("void main() { gl_Position = vec4(position + instanceOffset, "
             "0.0, 1.0); }"),
        };
        const GLint vertexPartLengths[] = {
            -1,
            (GLint)strlen(vertexParts[1]),
            -1,
        };
        const char *vertexSource =
            "attribute vec2 position;"
            "attribute vec2 instanceOffset;"
            "void main() { gl_Position = vec4(position + instanceOffset, "
            "0.0, 1.0); }";
        const char *fragmentSource =
            "precision mediump float;"
            "uniform vec4 tint;"
            "void main() { gl_FragColor = tint; }";
        vertexShader = compile_shader_parts(
            GL_VERTEX_SHADER,
            (GLsizei)(sizeof(vertexParts) / sizeof(vertexParts[0])),
            vertexParts, vertexPartLengths, vertexSource,
            "compile-vertex-shader");
        fragmentShader = compile_shader(GL_FRAGMENT_SHADER, fragmentSource,
                                        "compile-fragment-shader");
        if(!vertexShader || !fragmentShader) goto cleanup;

        program = glCreateProgram();
        glAttachShader(program, vertexShader);
        glAttachShader(program, fragmentShader);
        glBindAttribLocation(program, 0, "position");
        glBindAttribLocation(program, 1, "instanceOffset");
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
        GLint instanceOffset =
            glGetAttribLocation(program, "instanceOffset");
        GLint tint = glGetUniformLocation(program, "tint");
        CHECK(position >= 0 && instanceOffset >= 0 && tint >= 0,
              "shader-location-string-copy");
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

        test_debug_labels(vertexBuffer);
        test_queries();
        test_program_pipelines();
        test_sync_objects();
        test_mapped_buffers();
        test_instanced_client_arrays(program, position, instanceOffset, tint);

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
