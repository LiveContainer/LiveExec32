#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <Foundation/Foundation+LC32.h>
#import <LC32/LC32.h>

#include <stdint.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#include "LC32OpenGLESBridge.h"

NSString * const kEAGLColorFormatRGBA8 = @"EAGLColorFormat8888";
NSString * const kEAGLColorFormatRGB565 = @"EAGLColorFormat565";
NSString * const kEAGLDrawablePropertyColorFormat =
    @"EAGLDrawablePropertyColorFormat";
NSString * const kEAGLDrawablePropertyRetainedBacking =
    @"EAGLDrawablePropertyRetained";

static pthread_once_t LC32OpenGLESDispatcherOnce = PTHREAD_ONCE_INIT;
static uint64_t LC32OpenGLESDispatcherAddress;

static void LC32OpenGLESResolveDispatcher(void) {
    LC32OpenGLESDispatcherAddress =
        LC32Dlsym("LC32_OpenGLES_Dispatch", YES);
}

static uint64_t LC32OpenGLESDispatcher(void) {
    pthread_once(&LC32OpenGLESDispatcherOnce,
        LC32OpenGLESResolveDispatcher);
    return LC32OpenGLESDispatcherAddress;
}

static uint32_t LC32OpenGLESDispatch(LC32OpenGLESOpcode opcode,
                                     const uint64_t *slots,
                                     uint32_t slotCount) {
    if(slotCount > LC32OpenGLESMaxSlots) return 0;
    uint64_t dispatcher = LC32OpenGLESDispatcher();
    if(!dispatcher) return 0;

    LC32OpenGLESCall call = {
        .version = LC32OpenGLESABIVersion,
        .slotCount = slotCount,
    };
    if(slotCount) memcpy(call.slots, slots, slotCount * sizeof(*slots));

    /*
     * SVC 1002 forwards the first two post-function-pointer words as r2/r3.
     * Keeping both values 32-bit makes this call independent of ARMv7 vararg
     * alignment. The pointed-to packet contains the normalized ABI.
     */
    return LC32InvokeHostCRet32(dispatcher, (uint32_t)opcode,
        (uint32_t)(uintptr_t)&call);
}

static uint64_t LC32OpenGLESFloat(GLfloat value) {
    union {
        GLfloat value;
        uint32_t bits;
    } converted = {.value = value};
    return converted.bits;
}

static uint64_t LC32OpenGLESGuestPointer(const void *pointer) {
    return (uint32_t)(uintptr_t)pointer;
}

static uint64_t LC32OpenGLESSigned(GLint value) {
    return (uint64_t)(int64_t)(int32_t)value;
}

#define LC32_GL_CALL0(opcode) \
    LC32OpenGLESDispatch((opcode), NULL, 0)
#define LC32_GL_CALL(opcode, ...) \
    LC32OpenGLESDispatch((opcode), (const uint64_t[]){__VA_ARGS__}, \
        (uint32_t)(sizeof((const uint64_t[]){__VA_ARGS__}) / sizeof(uint64_t)))
#define LC32_GL_U32(value) ((uint64_t)(uint32_t)(value))
#define LC32_GL_U64(value) ((uint64_t)(value))
#define LC32_GL_I32(value) LC32OpenGLESSigned((GLint)(value))
#define LC32_GL_F32(value) LC32OpenGLESFloat((GLfloat)(value))
#define LC32_GL_PTR(value) LC32OpenGLESGuestPointer((const void *)(value))

void EAGLGetVersion(unsigned int *major, unsigned int *minor) {
    LC32_GL_CALL(LC32OpenGLESOpEAGLGetVersion,
        LC32_GL_PTR(major), LC32_GL_PTR(minor));
}

typedef struct {
    GLenum name;
    GLubyte *bytes;
    uint32_t capacity;
} LC32OpenGLESStringCache;

static __thread LC32OpenGLESStringCache LC32OpenGLESStrings[5];

const GLubyte *glGetString(GLenum name) {
    LC32OpenGLESStringCache *cache = NULL;
    for(size_t i = 0; i < sizeof(LC32OpenGLESStrings) /
            sizeof(LC32OpenGLESStrings[0]); ++i) {
        if(LC32OpenGLESStrings[i].name == name) {
            cache = &LC32OpenGLESStrings[i];
            break;
        }
        if(!cache && LC32OpenGLESStrings[i].name == 0) {
            cache = &LC32OpenGLESStrings[i];
        }
    }
    if(!cache) return NULL;

    uint32_t length = LC32_GL_CALL(LC32OpenGLESOpGetStringLength,
        LC32_GL_U32(name));
    if(!length) return NULL;
    if(cache->capacity < length) {
        GLubyte *replacement = realloc(cache->bytes, length);
        if(!replacement) return NULL;
        cache->bytes = replacement;
        cache->capacity = length;
    }
    cache->name = name;
    uint32_t copied = LC32_GL_CALL(LC32OpenGLESOpGetStringCopy,
        LC32_GL_U32(name), LC32_GL_PTR(cache->bytes),
        LC32_GL_U32(cache->capacity));
    return copied == length ? cache->bytes : NULL;
}

GLenum glGetError(void) {
    return (GLenum)LC32_GL_CALL0(LC32OpenGLESOpGetError);
}

void glGetIntegerv(GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetIntegerv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetBooleanv(GLenum pname, GLboolean *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetBooleanv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetFloatv(GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetFloatv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glActiveTexture(GLenum texture) {
    LC32_GL_CALL(LC32OpenGLESOpActiveTexture, LC32_GL_U32(texture));
}

void glClientActiveTexture(GLenum texture) {
    LC32_GL_CALL(LC32OpenGLESOpClientActiveTexture, LC32_GL_U32(texture));
}

void glAttachShader(GLuint program, GLuint shader) {
    LC32_GL_CALL(LC32OpenGLESOpAttachShader,
        LC32_GL_U32(program), LC32_GL_U32(shader));
}

void glBindAttribLocation(GLuint program, GLuint index, const GLchar *name) {
    LC32_GL_CALL(LC32OpenGLESOpBindAttribLocation,
        LC32_GL_U32(program), LC32_GL_U32(index), LC32_GL_PTR(name));
}

void glBindBuffer(GLenum target, GLuint buffer) {
    LC32_GL_CALL(LC32OpenGLESOpBindBuffer,
        LC32_GL_U32(target), LC32_GL_U32(buffer));
}

void glBindFramebuffer(GLenum target, GLuint framebuffer) {
    LC32_GL_CALL(LC32OpenGLESOpBindFramebuffer,
        LC32_GL_U32(target), LC32_GL_U32(framebuffer));
}

void glBindRenderbuffer(GLenum target, GLuint renderbuffer) {
    LC32_GL_CALL(LC32OpenGLESOpBindRenderbuffer,
        LC32_GL_U32(target), LC32_GL_U32(renderbuffer));
}

void glBindTexture(GLenum target, GLuint texture) {
    LC32_GL_CALL(LC32OpenGLESOpBindTexture,
        LC32_GL_U32(target), LC32_GL_U32(texture));
}

void glBlendColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
    LC32_GL_CALL(LC32OpenGLESOpBlendColor,
        LC32_GL_F32(red), LC32_GL_F32(green),
        LC32_GL_F32(blue), LC32_GL_F32(alpha));
}

void glBlendEquation(GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpBlendEquation, LC32_GL_U32(mode));
}

void glBlendEquationSeparate(GLenum modeRGB, GLenum modeAlpha) {
    LC32_GL_CALL(LC32OpenGLESOpBlendEquationSeparate,
        LC32_GL_U32(modeRGB), LC32_GL_U32(modeAlpha));
}

void glBlendFunc(GLenum sfactor, GLenum dfactor) {
    LC32_GL_CALL(LC32OpenGLESOpBlendFunc,
        LC32_GL_U32(sfactor), LC32_GL_U32(dfactor));
}

void glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB,
                         GLenum srcAlpha, GLenum dstAlpha) {
    LC32_GL_CALL(LC32OpenGLESOpBlendFuncSeparate,
        LC32_GL_U32(srcRGB), LC32_GL_U32(dstRGB),
        LC32_GL_U32(srcAlpha), LC32_GL_U32(dstAlpha));
}

void glBufferData(GLenum target, GLsizeiptr size,
                  const GLvoid *data, GLenum usage) {
    LC32_GL_CALL(LC32OpenGLESOpBufferData,
        LC32_GL_U32(target), LC32_GL_I32(size),
        LC32_GL_PTR(data), LC32_GL_U32(usage));
}

void glBufferSubData(GLenum target, GLintptr offset,
                     GLsizeiptr size, const GLvoid *data) {
    LC32_GL_CALL(LC32OpenGLESOpBufferSubData,
        LC32_GL_U32(target), LC32_GL_I32(offset),
        LC32_GL_I32(size), LC32_GL_PTR(data));
}

GLenum glCheckFramebufferStatus(GLenum target) {
    return (GLenum)LC32_GL_CALL(LC32OpenGLESOpCheckFramebufferStatus,
        LC32_GL_U32(target));
}

void glClear(GLbitfield mask) {
    LC32_GL_CALL(LC32OpenGLESOpClear, LC32_GL_U32(mask));
}

void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
    LC32_GL_CALL(LC32OpenGLESOpClearColor,
        LC32_GL_F32(red), LC32_GL_F32(green),
        LC32_GL_F32(blue), LC32_GL_F32(alpha));
}

void glClearDepthf(GLfloat depth) {
    LC32_GL_CALL(LC32OpenGLESOpClearDepthf, LC32_GL_F32(depth));
}

void glClearStencil(GLint stencil) {
    LC32_GL_CALL(LC32OpenGLESOpClearStencil, LC32_GL_I32(stencil));
}

void glColorMask(GLboolean red, GLboolean green,
                 GLboolean blue, GLboolean alpha) {
    LC32_GL_CALL(LC32OpenGLESOpColorMask,
        LC32_GL_U32(red), LC32_GL_U32(green),
        LC32_GL_U32(blue), LC32_GL_U32(alpha));
}

void glCompileShader(GLuint shader) {
    LC32_GL_CALL(LC32OpenGLESOpCompileShader, LC32_GL_U32(shader));
}

void glCompressedTexImage2D(GLenum target, GLint level,
                            GLenum internalFormat, GLsizei width,
                            GLsizei height, GLint border,
                            GLsizei imageSize, const GLvoid *data) {
    LC32_GL_CALL(LC32OpenGLESOpCompressedTexImage2D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_U32(internalFormat), LC32_GL_I32(width),
        LC32_GL_I32(height), LC32_GL_I32(border),
        LC32_GL_I32(imageSize), LC32_GL_PTR(data));
}

void glCompressedTexSubImage2D(GLenum target, GLint level,
                               GLint xOffset, GLint yOffset,
                               GLsizei width, GLsizei height,
                               GLenum format, GLsizei imageSize,
                               const GLvoid *data) {
    LC32_GL_CALL(LC32OpenGLESOpCompressedTexSubImage2D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_I32(xOffset), LC32_GL_I32(yOffset),
        LC32_GL_I32(width), LC32_GL_I32(height),
        LC32_GL_U32(format), LC32_GL_I32(imageSize), LC32_GL_PTR(data));
}

void glCopyTexImage2D(GLenum target, GLint level, GLenum internalFormat,
                      GLint x, GLint y, GLsizei width, GLsizei height,
                      GLint border) {
    LC32_GL_CALL(LC32OpenGLESOpCopyTexImage2D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_U32(internalFormat), LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(width), LC32_GL_I32(height), LC32_GL_I32(border));
}

void glCopyTexSubImage2D(GLenum target, GLint level,
                         GLint xOffset, GLint yOffset,
                         GLint x, GLint y, GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpCopyTexSubImage2D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_I32(xOffset), LC32_GL_I32(yOffset),
        LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

GLuint glCreateProgram(void) {
    return (GLuint)LC32_GL_CALL0(LC32OpenGLESOpCreateProgram);
}

GLuint glCreateShader(GLenum type) {
    return (GLuint)LC32_GL_CALL(LC32OpenGLESOpCreateShader,
        LC32_GL_U32(type));
}

void glCullFace(GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpCullFace, LC32_GL_U32(mode));
}

#define LC32_GL_ARRAY_VOID(name, opcode, type) \
    void name(GLsizei count, const type *values) { \
        LC32_GL_CALL((opcode), LC32_GL_I32(count), LC32_GL_PTR(values)); \
    }
#define LC32_GL_ARRAY_OUT(name, opcode, type) \
    void name(GLsizei count, type *values) { \
        LC32_GL_CALL((opcode), LC32_GL_I32(count), LC32_GL_PTR(values)); \
    }

LC32_GL_ARRAY_VOID(glDeleteBuffers, LC32OpenGLESOpDeleteBuffers, GLuint)
LC32_GL_ARRAY_VOID(glDeleteFramebuffers, LC32OpenGLESOpDeleteFramebuffers,
    GLuint)
LC32_GL_ARRAY_VOID(glDeleteRenderbuffers, LC32OpenGLESOpDeleteRenderbuffers,
    GLuint)
LC32_GL_ARRAY_VOID(glDeleteTextures, LC32OpenGLESOpDeleteTextures, GLuint)
LC32_GL_ARRAY_VOID(glDeleteVertexArraysOES,
    LC32OpenGLESOpDeleteVertexArraysOES, GLuint)
LC32_GL_ARRAY_OUT(glGenBuffers, LC32OpenGLESOpGenBuffers, GLuint)
LC32_GL_ARRAY_OUT(glGenFramebuffers, LC32OpenGLESOpGenFramebuffers, GLuint)
LC32_GL_ARRAY_OUT(glGenRenderbuffers, LC32OpenGLESOpGenRenderbuffers, GLuint)
LC32_GL_ARRAY_OUT(glGenTextures, LC32OpenGLESOpGenTextures, GLuint)
LC32_GL_ARRAY_OUT(glGenVertexArraysOES,
    LC32OpenGLESOpGenVertexArraysOES, GLuint)

void glDeleteProgram(GLuint program) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteProgram, LC32_GL_U32(program));
}

void glDeleteShader(GLuint shader) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteShader, LC32_GL_U32(shader));
}

void glDepthFunc(GLenum function) {
    LC32_GL_CALL(LC32OpenGLESOpDepthFunc, LC32_GL_U32(function));
}

void glDepthMask(GLboolean flag) {
    LC32_GL_CALL(LC32OpenGLESOpDepthMask, LC32_GL_U32(flag));
}

void glDepthRangef(GLfloat nearValue, GLfloat farValue) {
    LC32_GL_CALL(LC32OpenGLESOpDepthRangef,
        LC32_GL_F32(nearValue), LC32_GL_F32(farValue));
}

void glDetachShader(GLuint program, GLuint shader) {
    LC32_GL_CALL(LC32OpenGLESOpDetachShader,
        LC32_GL_U32(program), LC32_GL_U32(shader));
}

void glDisable(GLenum capability) {
    LC32_GL_CALL(LC32OpenGLESOpDisable, LC32_GL_U32(capability));
}

void glDisableVertexAttribArray(GLuint index) {
    LC32_GL_CALL(LC32OpenGLESOpDisableVertexAttribArray,
        LC32_GL_U32(index));
}

void glDrawArrays(GLenum mode, GLint first, GLsizei count) {
    LC32_GL_CALL(LC32OpenGLESOpDrawArrays,
        LC32_GL_U32(mode), LC32_GL_I32(first), LC32_GL_I32(count));
}

void glDrawElements(GLenum mode, GLsizei count,
                    GLenum type, const GLvoid *indices) {
    LC32_GL_CALL(LC32OpenGLESOpDrawElements,
        LC32_GL_U32(mode), LC32_GL_I32(count),
        LC32_GL_U32(type), LC32_GL_PTR(indices));
}

void glEnable(GLenum capability) {
    LC32_GL_CALL(LC32OpenGLESOpEnable, LC32_GL_U32(capability));
}

void glEnableVertexAttribArray(GLuint index) {
    LC32_GL_CALL(LC32OpenGLESOpEnableVertexAttribArray,
        LC32_GL_U32(index));
}

void glFinish(void) {
    LC32_GL_CALL0(LC32OpenGLESOpFinish);
}

void glFlush(void) {
    LC32_GL_CALL0(LC32OpenGLESOpFlush);
}

void glFramebufferRenderbuffer(GLenum target, GLenum attachment,
                               GLenum renderbufferTarget,
                               GLuint renderbuffer) {
    LC32_GL_CALL(LC32OpenGLESOpFramebufferRenderbuffer,
        LC32_GL_U32(target), LC32_GL_U32(attachment),
        LC32_GL_U32(renderbufferTarget), LC32_GL_U32(renderbuffer));
}

void glFramebufferTexture2D(GLenum target, GLenum attachment,
                            GLenum textureTarget, GLuint texture,
                            GLint level) {
    LC32_GL_CALL(LC32OpenGLESOpFramebufferTexture2D,
        LC32_GL_U32(target), LC32_GL_U32(attachment),
        LC32_GL_U32(textureTarget), LC32_GL_U32(texture),
        LC32_GL_I32(level));
}

void glFrontFace(GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpFrontFace, LC32_GL_U32(mode));
}

void glGenerateMipmap(GLenum target) {
    LC32_GL_CALL(LC32OpenGLESOpGenerateMipmap, LC32_GL_U32(target));
}

void glGetActiveAttrib(GLuint program, GLuint index, GLsizei bufferSize,
                       GLsizei *length, GLint *size, GLenum *type,
                       GLchar *name) {
    LC32_GL_CALL(LC32OpenGLESOpGetActiveAttrib,
        LC32_GL_U32(program), LC32_GL_U32(index),
        LC32_GL_I32(bufferSize), LC32_GL_PTR(length), LC32_GL_PTR(size),
        LC32_GL_PTR(type), LC32_GL_PTR(name));
}

void glGetActiveUniform(GLuint program, GLuint index, GLsizei bufferSize,
                        GLsizei *length, GLint *size, GLenum *type,
                        GLchar *name) {
    LC32_GL_CALL(LC32OpenGLESOpGetActiveUniform,
        LC32_GL_U32(program), LC32_GL_U32(index),
        LC32_GL_I32(bufferSize), LC32_GL_PTR(length), LC32_GL_PTR(size),
        LC32_GL_PTR(type), LC32_GL_PTR(name));
}

void glGetAttachedShaders(GLuint program, GLsizei maximumCount,
                          GLsizei *count, GLuint *shaders) {
    LC32_GL_CALL(LC32OpenGLESOpGetAttachedShaders,
        LC32_GL_U32(program), LC32_GL_I32(maximumCount),
        LC32_GL_PTR(count), LC32_GL_PTR(shaders));
}

GLint glGetAttribLocation(GLuint program, const GLchar *name) {
    return (GLint)LC32_GL_CALL(LC32OpenGLESOpGetAttribLocation,
        LC32_GL_U32(program), LC32_GL_PTR(name));
}

void glGetBufferParameteriv(GLenum target, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetBufferParameteriv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetFramebufferAttachmentParameteriv(GLenum target, GLenum attachment,
                                            GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetFramebufferAttachmentParameteriv,
        LC32_GL_U32(target), LC32_GL_U32(attachment),
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetProgramInfoLog(GLuint program, GLsizei bufferSize,
                         GLsizei *length, GLchar *infoLog) {
    LC32_GL_CALL(LC32OpenGLESOpGetProgramInfoLog,
        LC32_GL_U32(program), LC32_GL_I32(bufferSize),
        LC32_GL_PTR(length), LC32_GL_PTR(infoLog));
}

void glGetProgramiv(GLuint program, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetProgramiv,
        LC32_GL_U32(program), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetRenderbufferParameteriv(GLenum target, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetRenderbufferParameteriv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetShaderInfoLog(GLuint shader, GLsizei bufferSize,
                        GLsizei *length, GLchar *infoLog) {
    LC32_GL_CALL(LC32OpenGLESOpGetShaderInfoLog,
        LC32_GL_U32(shader), LC32_GL_I32(bufferSize),
        LC32_GL_PTR(length), LC32_GL_PTR(infoLog));
}

void glGetShaderiv(GLuint shader, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetShaderiv,
        LC32_GL_U32(shader), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetShaderPrecisionFormat(GLenum shaderType, GLenum precisionType,
                                GLint *range, GLint *precision) {
    LC32_GL_CALL(LC32OpenGLESOpGetShaderPrecisionFormat,
        LC32_GL_U32(shaderType), LC32_GL_U32(precisionType),
        LC32_GL_PTR(range), LC32_GL_PTR(precision));
}

void glGetShaderSource(GLuint shader, GLsizei bufferSize,
                       GLsizei *length, GLchar *source) {
    LC32_GL_CALL(LC32OpenGLESOpGetShaderSource,
        LC32_GL_U32(shader), LC32_GL_I32(bufferSize),
        LC32_GL_PTR(length), LC32_GL_PTR(source));
}

void glGetTexParameterfv(GLenum target, GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetTexParameterfv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetTexParameteriv(GLenum target, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetTexParameteriv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetUniformfv(GLuint program, GLint location, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetUniformfv,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_PTR(params));
}

void glGetUniformiv(GLuint program, GLint location, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetUniformiv,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_PTR(params));
}

GLint glGetUniformLocation(GLuint program, const GLchar *name) {
    return (GLint)LC32_GL_CALL(LC32OpenGLESOpGetUniformLocation,
        LC32_GL_U32(program), LC32_GL_PTR(name));
}

void glGetVertexAttribfv(GLuint index, GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetVertexAttribfv,
        LC32_GL_U32(index), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetVertexAttribiv(GLuint index, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetVertexAttribiv,
        LC32_GL_U32(index), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetVertexAttribPointerv(GLuint index, GLenum pname, GLvoid **pointer) {
    LC32_GL_CALL(LC32OpenGLESOpGetVertexAttribPointerv,
        LC32_GL_U32(index), LC32_GL_U32(pname), LC32_GL_PTR(pointer));
}

void glHint(GLenum target, GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpHint,
        LC32_GL_U32(target), LC32_GL_U32(mode));
}

#define LC32_GL_IS_OBJECT(name, opcode) \
    GLboolean name(GLuint object) { \
        return (GLboolean)LC32_GL_CALL((opcode), LC32_GL_U32(object)); \
    }

LC32_GL_IS_OBJECT(glIsBuffer, LC32OpenGLESOpIsBuffer)
LC32_GL_IS_OBJECT(glIsFramebuffer, LC32OpenGLESOpIsFramebuffer)
LC32_GL_IS_OBJECT(glIsProgram, LC32OpenGLESOpIsProgram)
LC32_GL_IS_OBJECT(glIsRenderbuffer, LC32OpenGLESOpIsRenderbuffer)
LC32_GL_IS_OBJECT(glIsShader, LC32OpenGLESOpIsShader)
LC32_GL_IS_OBJECT(glIsTexture, LC32OpenGLESOpIsTexture)

GLboolean glIsEnabled(GLenum capability) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsEnabled,
        LC32_GL_U32(capability));
}

void glLineWidth(GLfloat width) {
    LC32_GL_CALL(LC32OpenGLESOpLineWidth, LC32_GL_F32(width));
}

void glLinkProgram(GLuint program) {
    LC32_GL_CALL(LC32OpenGLESOpLinkProgram, LC32_GL_U32(program));
}

void glPixelStorei(GLenum pname, GLint param) {
    LC32_GL_CALL(LC32OpenGLESOpPixelStorei,
        LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glPolygonOffset(GLfloat factor, GLfloat units) {
    LC32_GL_CALL(LC32OpenGLESOpPolygonOffset,
        LC32_GL_F32(factor), LC32_GL_F32(units));
}

void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height,
                  GLenum format, GLenum type, GLvoid *pixels) {
    LC32_GL_CALL(LC32OpenGLESOpReadPixels,
        LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(width), LC32_GL_I32(height),
        LC32_GL_U32(format), LC32_GL_U32(type), LC32_GL_PTR(pixels));
}

void glReleaseShaderCompiler(void) {
    LC32_GL_CALL0(LC32OpenGLESOpReleaseShaderCompiler);
}

void glRenderbufferStorage(GLenum target, GLenum internalFormat,
                           GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpRenderbufferStorage,
        LC32_GL_U32(target), LC32_GL_U32(internalFormat),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

void glSampleCoverage(GLfloat value, GLboolean invert) {
    LC32_GL_CALL(LC32OpenGLESOpSampleCoverage,
        LC32_GL_F32(value), LC32_GL_U32(invert));
}

void glScissor(GLint x, GLint y, GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpScissor,
        LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

void glShaderBinary(GLsizei count, const GLuint *shaders,
                    GLenum binaryFormat, const GLvoid *binary,
                    GLsizei length) {
    LC32_GL_CALL(LC32OpenGLESOpShaderBinary,
        LC32_GL_I32(count), LC32_GL_PTR(shaders),
        LC32_GL_U32(binaryFormat), LC32_GL_PTR(binary), LC32_GL_I32(length));
}

void glShaderSource(GLuint shader, GLsizei count,
                    const GLchar *const *strings, const GLint *lengths) {
    LC32_GL_CALL(LC32OpenGLESOpShaderSource,
        LC32_GL_U32(shader), LC32_GL_I32(count),
        LC32_GL_PTR(strings), LC32_GL_PTR(lengths));
}

void glStencilFunc(GLenum function, GLint reference, GLuint mask) {
    LC32_GL_CALL(LC32OpenGLESOpStencilFunc,
        LC32_GL_U32(function), LC32_GL_I32(reference), LC32_GL_U32(mask));
}

void glStencilFuncSeparate(GLenum face, GLenum function,
                           GLint reference, GLuint mask) {
    LC32_GL_CALL(LC32OpenGLESOpStencilFuncSeparate,
        LC32_GL_U32(face), LC32_GL_U32(function),
        LC32_GL_I32(reference), LC32_GL_U32(mask));
}

void glStencilMask(GLuint mask) {
    LC32_GL_CALL(LC32OpenGLESOpStencilMask, LC32_GL_U32(mask));
}

void glStencilMaskSeparate(GLenum face, GLuint mask) {
    LC32_GL_CALL(LC32OpenGLESOpStencilMaskSeparate,
        LC32_GL_U32(face), LC32_GL_U32(mask));
}

void glStencilOp(GLenum stencilFail, GLenum depthFail,
                 GLenum depthPass) {
    LC32_GL_CALL(LC32OpenGLESOpStencilOp,
        LC32_GL_U32(stencilFail), LC32_GL_U32(depthFail),
        LC32_GL_U32(depthPass));
}

void glStencilOpSeparate(GLenum face, GLenum stencilFail,
                         GLenum depthFail, GLenum depthPass) {
    LC32_GL_CALL(LC32OpenGLESOpStencilOpSeparate,
        LC32_GL_U32(face), LC32_GL_U32(stencilFail),
        LC32_GL_U32(depthFail), LC32_GL_U32(depthPass));
}

void glTexImage2D(GLenum target, GLint level, GLint internalFormat,
                  GLsizei width, GLsizei height, GLint border,
                  GLenum format, GLenum type, const GLvoid *pixels) {
    LC32_GL_CALL(LC32OpenGLESOpTexImage2D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_I32(internalFormat), LC32_GL_I32(width),
        LC32_GL_I32(height), LC32_GL_I32(border),
        LC32_GL_U32(format), LC32_GL_U32(type), LC32_GL_PTR(pixels));
}

void glTexParameterf(GLenum target, GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpTexParameterf,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glTexParameterfv(GLenum target, GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpTexParameterfv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTexEnvf(GLenum target, GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpTexEnvf,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glTexEnvfv(GLenum target, GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpTexEnvfv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTexEnvi(GLenum target, GLenum pname, GLint param) {
    LC32_GL_CALL(LC32OpenGLESOpTexEnvi,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glTexParameteri(GLenum target, GLenum pname, GLint param) {
    LC32_GL_CALL(LC32OpenGLESOpTexParameteri,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glTexParameteriv(GLenum target, GLenum pname, const GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpTexParameteriv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTexSubImage2D(GLenum target, GLint level, GLint xOffset,
                     GLint yOffset, GLsizei width, GLsizei height,
                     GLenum format, GLenum type, const GLvoid *pixels) {
    LC32_GL_CALL(LC32OpenGLESOpTexSubImage2D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_I32(xOffset), LC32_GL_I32(yOffset),
        LC32_GL_I32(width), LC32_GL_I32(height),
        LC32_GL_U32(format), LC32_GL_U32(type), LC32_GL_PTR(pixels));
}

#define LC32_GL_UNIFORM_F1(name, opcode) \
    void name(GLint location, GLfloat x) { \
        LC32_GL_CALL((opcode), LC32_GL_I32(location), LC32_GL_F32(x)); \
    }
#define LC32_GL_UNIFORM_I1(name, opcode) \
    void name(GLint location, GLint x) { \
        LC32_GL_CALL((opcode), LC32_GL_I32(location), LC32_GL_I32(x)); \
    }

LC32_GL_UNIFORM_F1(glUniform1f, LC32OpenGLESOpUniform1f)
LC32_GL_UNIFORM_I1(glUniform1i, LC32OpenGLESOpUniform1i)

void glUniform2f(GLint location, GLfloat x, GLfloat y) {
    LC32_GL_CALL(LC32OpenGLESOpUniform2f,
        LC32_GL_I32(location), LC32_GL_F32(x), LC32_GL_F32(y));
}

void glUniform2i(GLint location, GLint x, GLint y) {
    LC32_GL_CALL(LC32OpenGLESOpUniform2i,
        LC32_GL_I32(location), LC32_GL_I32(x), LC32_GL_I32(y));
}

void glUniform3f(GLint location, GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpUniform3f,
        LC32_GL_I32(location), LC32_GL_F32(x),
        LC32_GL_F32(y), LC32_GL_F32(z));
}

void glUniform3i(GLint location, GLint x, GLint y, GLint z) {
    LC32_GL_CALL(LC32OpenGLESOpUniform3i,
        LC32_GL_I32(location), LC32_GL_I32(x),
        LC32_GL_I32(y), LC32_GL_I32(z));
}

void glUniform4f(GLint location, GLfloat x, GLfloat y,
                 GLfloat z, GLfloat w) {
    LC32_GL_CALL(LC32OpenGLESOpUniform4f,
        LC32_GL_I32(location), LC32_GL_F32(x), LC32_GL_F32(y),
        LC32_GL_F32(z), LC32_GL_F32(w));
}

void glUniform4i(GLint location, GLint x, GLint y, GLint z, GLint w) {
    LC32_GL_CALL(LC32OpenGLESOpUniform4i,
        LC32_GL_I32(location), LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(z), LC32_GL_I32(w));
}

#define LC32_GL_UNIFORM_ARRAY(name, opcode, type) \
    void name(GLint location, GLsizei count, const type *values) { \
        LC32_GL_CALL((opcode), LC32_GL_I32(location), \
            LC32_GL_I32(count), LC32_GL_PTR(values)); \
    }

LC32_GL_UNIFORM_ARRAY(glUniform1fv, LC32OpenGLESOpUniform1fv, GLfloat)
LC32_GL_UNIFORM_ARRAY(glUniform2fv, LC32OpenGLESOpUniform2fv, GLfloat)
LC32_GL_UNIFORM_ARRAY(glUniform3fv, LC32OpenGLESOpUniform3fv, GLfloat)
LC32_GL_UNIFORM_ARRAY(glUniform4fv, LC32OpenGLESOpUniform4fv, GLfloat)
LC32_GL_UNIFORM_ARRAY(glUniform1iv, LC32OpenGLESOpUniform1iv, GLint)
LC32_GL_UNIFORM_ARRAY(glUniform2iv, LC32OpenGLESOpUniform2iv, GLint)
LC32_GL_UNIFORM_ARRAY(glUniform3iv, LC32OpenGLESOpUniform3iv, GLint)
LC32_GL_UNIFORM_ARRAY(glUniform4iv, LC32OpenGLESOpUniform4iv, GLint)

#define LC32_GL_UNIFORM_MATRIX(name, opcode) \
    void name(GLint location, GLsizei count, GLboolean transpose, \
              const GLfloat *values) { \
        LC32_GL_CALL((opcode), LC32_GL_I32(location), LC32_GL_I32(count), \
            LC32_GL_U32(transpose), LC32_GL_PTR(values)); \
    }

LC32_GL_UNIFORM_MATRIX(glUniformMatrix2fv, LC32OpenGLESOpUniformMatrix2fv)
LC32_GL_UNIFORM_MATRIX(glUniformMatrix3fv, LC32OpenGLESOpUniformMatrix3fv)
LC32_GL_UNIFORM_MATRIX(glUniformMatrix4fv, LC32OpenGLESOpUniformMatrix4fv)

void glUseProgram(GLuint program) {
    LC32_GL_CALL(LC32OpenGLESOpUseProgram, LC32_GL_U32(program));
}

void glValidateProgram(GLuint program) {
    LC32_GL_CALL(LC32OpenGLESOpValidateProgram, LC32_GL_U32(program));
}

void glVertexAttrib1f(GLuint index, GLfloat x) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib1f,
        LC32_GL_U32(index), LC32_GL_F32(x));
}

void glVertexAttrib1fv(GLuint index, const GLfloat *values) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib1fv,
        LC32_GL_U32(index), LC32_GL_PTR(values));
}

void glVertexAttrib2f(GLuint index, GLfloat x, GLfloat y) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib2f,
        LC32_GL_U32(index), LC32_GL_F32(x), LC32_GL_F32(y));
}

void glVertexAttrib2fv(GLuint index, const GLfloat *values) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib2fv,
        LC32_GL_U32(index), LC32_GL_PTR(values));
}

void glVertexAttrib3f(GLuint index, GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib3f,
        LC32_GL_U32(index), LC32_GL_F32(x),
        LC32_GL_F32(y), LC32_GL_F32(z));
}

void glVertexAttrib3fv(GLuint index, const GLfloat *values) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib3fv,
        LC32_GL_U32(index), LC32_GL_PTR(values));
}

void glVertexAttrib4f(GLuint index, GLfloat x, GLfloat y,
                      GLfloat z, GLfloat w) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib4f,
        LC32_GL_U32(index), LC32_GL_F32(x), LC32_GL_F32(y),
        LC32_GL_F32(z), LC32_GL_F32(w));
}

void glVertexAttrib4fv(GLuint index, const GLfloat *values) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttrib4fv,
        LC32_GL_U32(index), LC32_GL_PTR(values));
}

void glVertexAttribPointer(GLuint index, GLint size, GLenum type,
                           GLboolean normalized, GLsizei stride,
                           const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribPointer,
        LC32_GL_U32(index), LC32_GL_I32(size), LC32_GL_U32(type),
        LC32_GL_U32(normalized), LC32_GL_I32(stride), LC32_GL_PTR(pointer));
}

void glViewport(GLint x, GLint y, GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpViewport,
        LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

#pragma mark OpenGL ES 1 fixed-function API

void glAlphaFunc(GLenum function, GLclampf reference) {
    LC32_GL_CALL(LC32OpenGLESOpAlphaFunc,
        LC32_GL_U32(function), LC32_GL_F32(reference));
}

void glBindVertexArrayOES(GLuint array) {
    LC32_GL_CALL(LC32OpenGLESOpBindVertexArrayOES, LC32_GL_U32(array));
}

void glColor4f(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
    LC32_GL_CALL(LC32OpenGLESOpColor4f,
        LC32_GL_F32(red), LC32_GL_F32(green),
        LC32_GL_F32(blue), LC32_GL_F32(alpha));
}

void glColor4ub(GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha) {
    LC32_GL_CALL(LC32OpenGLESOpColor4ub,
        LC32_GL_U32(red), LC32_GL_U32(green),
        LC32_GL_U32(blue), LC32_GL_U32(alpha));
}

void glColorPointer(GLint size, GLenum type, GLsizei stride,
                    const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpColorPointer,
        LC32_GL_I32(size), LC32_GL_U32(type), LC32_GL_I32(stride),
        LC32_GL_PTR(pointer));
}

void glDisableClientState(GLenum array) {
    LC32_GL_CALL(LC32OpenGLESOpDisableClientState, LC32_GL_U32(array));
}

void glDiscardFramebufferEXT(GLenum target, GLsizei count,
                             const GLenum *attachments) {
    LC32_GL_CALL(LC32OpenGLESOpDiscardFramebufferEXT,
        LC32_GL_U32(target), LC32_GL_I32(count), LC32_GL_PTR(attachments));
}

void glEnableClientState(GLenum array) {
    LC32_GL_CALL(LC32OpenGLESOpEnableClientState, LC32_GL_U32(array));
}

void glFogf(GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpFogf,
        LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glFogfv(GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpFogfv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glFogx(GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpFogx,
        LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glLightfv(GLenum light, GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpLightfv,
        LC32_GL_U32(light), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glLoadIdentity(void) {
    LC32_GL_CALL0(LC32OpenGLESOpLoadIdentity);
}

void glLoadMatrixf(const GLfloat *matrix) {
    LC32_GL_CALL(LC32OpenGLESOpLoadMatrixf, LC32_GL_PTR(matrix));
}

void glMaterialfv(GLenum face, GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpMaterialfv,
        LC32_GL_U32(face), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glMatrixMode(GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpMatrixMode, LC32_GL_U32(mode));
}

void glMultMatrixf(const GLfloat *matrix) {
    LC32_GL_CALL(LC32OpenGLESOpMultMatrixf, LC32_GL_PTR(matrix));
}

void glNormal3f(GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpNormal3f,
        LC32_GL_F32(x), LC32_GL_F32(y), LC32_GL_F32(z));
}

void glNormalPointer(GLenum type, GLsizei stride, const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpNormalPointer,
        LC32_GL_U32(type), LC32_GL_I32(stride), LC32_GL_PTR(pointer));
}

void glOrthof(GLfloat left, GLfloat right, GLfloat bottom, GLfloat top,
              GLfloat nearValue, GLfloat farValue) {
    LC32_GL_CALL(LC32OpenGLESOpOrthof,
        LC32_GL_F32(left), LC32_GL_F32(right),
        LC32_GL_F32(bottom), LC32_GL_F32(top),
        LC32_GL_F32(nearValue), LC32_GL_F32(farValue));
}

void glPopMatrix(void) {
    LC32_GL_CALL0(LC32OpenGLESOpPopMatrix);
}

void glPushMatrix(void) {
    LC32_GL_CALL0(LC32OpenGLESOpPushMatrix);
}

void glRenderbufferStorageMultisampleAPPLE(GLenum target, GLsizei samples,
                                            GLenum internalFormat,
                                            GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpRenderbufferStorageMultisampleAPPLE,
        LC32_GL_U32(target), LC32_GL_I32(samples),
        LC32_GL_U32(internalFormat), LC32_GL_I32(width),
        LC32_GL_I32(height));
}

void glResolveMultisampleFramebufferAPPLE(void) {
    LC32_GL_CALL0(LC32OpenGLESOpResolveMultisampleFramebufferAPPLE);
}

/* OES entry points promoted verbatim to ES2 core are true symbol aliases, so
 * both spellings have the same address and no forwarding thunk is introduced. */
LC32_ASM_GLOBAL_ALIAS(glBindFramebufferOES, glBindFramebuffer);
LC32_ASM_GLOBAL_ALIAS(glBindRenderbufferOES, glBindRenderbuffer);
LC32_ASM_GLOBAL_ALIAS(glBlendEquationOES, glBlendEquation);
LC32_ASM_GLOBAL_ALIAS(glBlendEquationSeparateOES, glBlendEquationSeparate);
LC32_ASM_GLOBAL_ALIAS(glBlendFuncSeparateOES, glBlendFuncSeparate);
LC32_ASM_GLOBAL_ALIAS(glCheckFramebufferStatusOES,
    glCheckFramebufferStatus);
LC32_ASM_GLOBAL_ALIAS(glDeleteFramebuffersOES, glDeleteFramebuffers);
LC32_ASM_GLOBAL_ALIAS(glDeleteRenderbuffersOES, glDeleteRenderbuffers);
LC32_ASM_GLOBAL_ALIAS(glFramebufferRenderbufferOES,
    glFramebufferRenderbuffer);
LC32_ASM_GLOBAL_ALIAS(glFramebufferTexture2DOES, glFramebufferTexture2D);
LC32_ASM_GLOBAL_ALIAS(glGenFramebuffersOES, glGenFramebuffers);
LC32_ASM_GLOBAL_ALIAS(glGenRenderbuffersOES, glGenRenderbuffers);
LC32_ASM_GLOBAL_ALIAS(glGenerateMipmapOES, glGenerateMipmap);
LC32_ASM_GLOBAL_ALIAS(glGetFramebufferAttachmentParameterivOES,
    glGetFramebufferAttachmentParameteriv);
LC32_ASM_GLOBAL_ALIAS(glGetRenderbufferParameterivOES,
    glGetRenderbufferParameteriv);
LC32_ASM_GLOBAL_ALIAS(glIsFramebufferOES, glIsFramebuffer);
LC32_ASM_GLOBAL_ALIAS(glIsRenderbufferOES, glIsRenderbuffer);
LC32_ASM_GLOBAL_ALIAS(glRenderbufferStorageOES, glRenderbufferStorage);

void glRotatef(GLfloat angle, GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpRotatef,
        LC32_GL_F32(angle), LC32_GL_F32(x),
        LC32_GL_F32(y), LC32_GL_F32(z));
}

void glScalef(GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpScalef,
        LC32_GL_F32(x), LC32_GL_F32(y), LC32_GL_F32(z));
}

void glShadeModel(GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpShadeModel, LC32_GL_U32(mode));
}

void glTexCoordPointer(GLint size, GLenum type, GLsizei stride,
                       const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpTexCoordPointer,
        LC32_GL_I32(size), LC32_GL_U32(type), LC32_GL_I32(stride),
        LC32_GL_PTR(pointer));
}

void glTranslatef(GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpTranslatef,
        LC32_GL_F32(x), LC32_GL_F32(y), LC32_GL_F32(z));
}

void glVertexPointer(GLint size, GLenum type, GLsizei stride,
                     const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpVertexPointer,
        LC32_GL_I32(size), LC32_GL_U32(type), LC32_GL_I32(stride),
        LC32_GL_PTR(pointer));
}

void glAlphaFuncx(GLenum function, GLclampx reference) {
    LC32_GL_CALL(LC32OpenGLESOpAlphaFuncx,
        LC32_GL_U32(function), LC32_GL_I32(reference));
}

void glClearColorx(GLclampx red, GLclampx green, GLclampx blue,
                   GLclampx alpha) {
    LC32_GL_CALL(LC32OpenGLESOpClearColorx,
        LC32_GL_I32(red), LC32_GL_I32(green),
        LC32_GL_I32(blue), LC32_GL_I32(alpha));
}

void glClearDepthx(GLclampx depth) {
    LC32_GL_CALL(LC32OpenGLESOpClearDepthx, LC32_GL_I32(depth));
}

void glClipPlanef(GLenum plane, const GLfloat *equation) {
    LC32_GL_CALL(LC32OpenGLESOpClipPlanef,
        LC32_GL_U32(plane), LC32_GL_PTR(equation));
}

void glClipPlanex(GLenum plane, const GLfixed *equation) {
    LC32_GL_CALL(LC32OpenGLESOpClipPlanex,
        LC32_GL_U32(plane), LC32_GL_PTR(equation));
}

void glColor4x(GLfixed red, GLfixed green, GLfixed blue, GLfixed alpha) {
    LC32_GL_CALL(LC32OpenGLESOpColor4x,
        LC32_GL_I32(red), LC32_GL_I32(green),
        LC32_GL_I32(blue), LC32_GL_I32(alpha));
}

void glDepthRangex(GLclampx nearValue, GLclampx farValue) {
    LC32_GL_CALL(LC32OpenGLESOpDepthRangex,
        LC32_GL_I32(nearValue), LC32_GL_I32(farValue));
}

void glFogxv(GLenum pname, const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpFogxv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glFrustumf(GLfloat left, GLfloat right, GLfloat bottom, GLfloat top,
                GLfloat nearValue, GLfloat farValue) {
    LC32_GL_CALL(LC32OpenGLESOpFrustumf,
        LC32_GL_F32(left), LC32_GL_F32(right),
        LC32_GL_F32(bottom), LC32_GL_F32(top),
        LC32_GL_F32(nearValue), LC32_GL_F32(farValue));
}

void glFrustumx(GLfixed left, GLfixed right, GLfixed bottom, GLfixed top,
                GLfixed nearValue, GLfixed farValue) {
    LC32_GL_CALL(LC32OpenGLESOpFrustumx,
        LC32_GL_I32(left), LC32_GL_I32(right),
        LC32_GL_I32(bottom), LC32_GL_I32(top),
        LC32_GL_I32(nearValue), LC32_GL_I32(farValue));
}

void glGetClipPlanef(GLenum plane, GLfloat *equation) {
    LC32_GL_CALL(LC32OpenGLESOpGetClipPlanef,
        LC32_GL_U32(plane), LC32_GL_PTR(equation));
}

void glGetClipPlanex(GLenum plane, GLfixed *equation) {
    LC32_GL_CALL(LC32OpenGLESOpGetClipPlanex,
        LC32_GL_U32(plane), LC32_GL_PTR(equation));
}

void glGetFixedv(GLenum pname, GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetFixedv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetLightfv(GLenum light, GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetLightfv,
        LC32_GL_U32(light), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetLightxv(GLenum light, GLenum pname, GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetLightxv,
        LC32_GL_U32(light), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetMaterialfv(GLenum face, GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetMaterialfv,
        LC32_GL_U32(face), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetMaterialxv(GLenum face, GLenum pname, GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetMaterialxv,
        LC32_GL_U32(face), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetPointerv(GLenum pname, void **params) {
    LC32_GL_CALL(LC32OpenGLESOpGetPointerv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetTexEnvfv(GLenum environment, GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetTexEnvfv,
        LC32_GL_U32(environment), LC32_GL_U32(pname),
        LC32_GL_PTR(params));
}

void glGetTexEnviv(GLenum environment, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetTexEnviv,
        LC32_GL_U32(environment), LC32_GL_U32(pname),
        LC32_GL_PTR(params));
}

void glGetTexEnvxv(GLenum environment, GLenum pname, GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetTexEnvxv,
        LC32_GL_U32(environment), LC32_GL_U32(pname),
        LC32_GL_PTR(params));
}

void glGetTexParameterxv(GLenum target, GLenum pname, GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetTexParameterxv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glLightModelf(GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpLightModelf,
        LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glLightModelfv(GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpLightModelfv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glLightModelx(GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpLightModelx,
        LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glLightModelxv(GLenum pname, const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpLightModelxv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glLightf(GLenum light, GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpLightf,
        LC32_GL_U32(light), LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glLightx(GLenum light, GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpLightx,
        LC32_GL_U32(light), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glLightxv(GLenum light, GLenum pname, const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpLightxv,
        LC32_GL_U32(light), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glLineWidthx(GLfixed width) {
    LC32_GL_CALL(LC32OpenGLESOpLineWidthx, LC32_GL_I32(width));
}

void glLoadMatrixx(const GLfixed *matrix) {
    LC32_GL_CALL(LC32OpenGLESOpLoadMatrixx, LC32_GL_PTR(matrix));
}

void glLogicOp(GLenum opcode) {
    LC32_GL_CALL(LC32OpenGLESOpLogicOp, LC32_GL_U32(opcode));
}

void glMaterialf(GLenum face, GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpMaterialf,
        LC32_GL_U32(face), LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glMaterialx(GLenum face, GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpMaterialx,
        LC32_GL_U32(face), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glMaterialxv(GLenum face, GLenum pname, const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpMaterialxv,
        LC32_GL_U32(face), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glMultMatrixx(const GLfixed *matrix) {
    LC32_GL_CALL(LC32OpenGLESOpMultMatrixx, LC32_GL_PTR(matrix));
}

void glMultiTexCoord4f(GLenum target, GLfloat s, GLfloat t, GLfloat r,
                       GLfloat q) {
    LC32_GL_CALL(LC32OpenGLESOpMultiTexCoord4f,
        LC32_GL_U32(target), LC32_GL_F32(s), LC32_GL_F32(t),
        LC32_GL_F32(r), LC32_GL_F32(q));
}

void glMultiTexCoord4x(GLenum target, GLfixed s, GLfixed t, GLfixed r,
                       GLfixed q) {
    LC32_GL_CALL(LC32OpenGLESOpMultiTexCoord4x,
        LC32_GL_U32(target), LC32_GL_I32(s), LC32_GL_I32(t),
        LC32_GL_I32(r), LC32_GL_I32(q));
}

void glNormal3x(GLfixed x, GLfixed y, GLfixed z) {
    LC32_GL_CALL(LC32OpenGLESOpNormal3x,
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z));
}

void glOrthox(GLfixed left, GLfixed right, GLfixed bottom, GLfixed top,
              GLfixed nearValue, GLfixed farValue) {
    LC32_GL_CALL(LC32OpenGLESOpOrthox,
        LC32_GL_I32(left), LC32_GL_I32(right),
        LC32_GL_I32(bottom), LC32_GL_I32(top),
        LC32_GL_I32(nearValue), LC32_GL_I32(farValue));
}

void glPointParameterf(GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpPointParameterf,
        LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glPointParameterfv(GLenum pname, const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpPointParameterfv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glPointParameterx(GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpPointParameterx,
        LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glPointParameterxv(GLenum pname, const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpPointParameterxv,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glPointSize(GLfloat size) {
    LC32_GL_CALL(LC32OpenGLESOpPointSize, LC32_GL_F32(size));
}

void glPointSizex(GLfixed size) {
    LC32_GL_CALL(LC32OpenGLESOpPointSizex, LC32_GL_I32(size));
}

void glPolygonOffsetx(GLfixed factor, GLfixed units) {
    LC32_GL_CALL(LC32OpenGLESOpPolygonOffsetx,
        LC32_GL_I32(factor), LC32_GL_I32(units));
}

void glRotatex(GLfixed angle, GLfixed x, GLfixed y, GLfixed z) {
    LC32_GL_CALL(LC32OpenGLESOpRotatex,
        LC32_GL_I32(angle), LC32_GL_I32(x),
        LC32_GL_I32(y), LC32_GL_I32(z));
}

void glSampleCoveragex(GLclampx value, GLboolean invert) {
    LC32_GL_CALL(LC32OpenGLESOpSampleCoveragex,
        LC32_GL_I32(value), LC32_GL_U32(invert));
}

void glScalex(GLfixed x, GLfixed y, GLfixed z) {
    LC32_GL_CALL(LC32OpenGLESOpScalex,
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z));
}

void glTexEnviv(GLenum target, GLenum pname, const GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpTexEnviv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTexEnvx(GLenum target, GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpTexEnvx,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glTexEnvxv(GLenum target, GLenum pname, const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpTexEnvxv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTexParameterx(GLenum target, GLenum pname, GLfixed param) {
    LC32_GL_CALL(LC32OpenGLESOpTexParameterx,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glTexParameterxv(GLenum target, GLenum pname,
                      const GLfixed *params) {
    LC32_GL_CALL(LC32OpenGLESOpTexParameterxv,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTranslatex(GLfixed x, GLfixed y, GLfixed z) {
    LC32_GL_CALL(LC32OpenGLESOpTranslatex,
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z));
}

void glCurrentPaletteMatrixOES(GLuint matrixpaletteindex) {
    LC32_GL_CALL(LC32OpenGLESOpCurrentPaletteMatrixOES,
        LC32_GL_U32(matrixpaletteindex));
}

void glDrawTexfOES(GLfloat x, GLfloat y, GLfloat z,
                   GLfloat width, GLfloat height) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexfOES,
        LC32_GL_F32(x), LC32_GL_F32(y), LC32_GL_F32(z),
        LC32_GL_F32(width), LC32_GL_F32(height));
}

void glDrawTexfvOES(const GLfloat *coords) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexfvOES, LC32_GL_PTR(coords));
}

void glDrawTexiOES(GLint x, GLint y, GLint z, GLint width, GLint height) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexiOES,
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

void glDrawTexivOES(const GLint *coords) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexivOES, LC32_GL_PTR(coords));
}

void glDrawTexsOES(GLshort x, GLshort y, GLshort z,
                   GLshort width, GLshort height) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexsOES,
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

void glDrawTexsvOES(const GLshort *coords) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexsvOES, LC32_GL_PTR(coords));
}

void glDrawTexxOES(GLfixed x, GLfixed y, GLfixed z,
                   GLfixed width, GLfixed height) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexxOES,
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

void glDrawTexxvOES(const GLfixed *coords) {
    LC32_GL_CALL(LC32OpenGLESOpDrawTexxvOES, LC32_GL_PTR(coords));
}

void glLoadPaletteFromModelViewMatrixOES(void) {
    LC32_GL_CALL0(LC32OpenGLESOpLoadPaletteFromModelViewMatrixOES);
}

void glMatrixIndexPointerOES(GLint size, GLenum type, GLsizei stride,
                             const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpMatrixIndexPointerOES,
        LC32_GL_I32(size), LC32_GL_U32(type), LC32_GL_I32(stride),
        LC32_GL_PTR(pointer));
}

void glPointSizePointerOES(GLenum type, GLsizei stride,
                           const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpPointSizePointerOES,
        LC32_GL_U32(type), LC32_GL_I32(stride), LC32_GL_PTR(pointer));
}

void glWeightPointerOES(GLint size, GLenum type, GLsizei stride,
                        const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpWeightPointerOES,
        LC32_GL_I32(size), LC32_GL_U32(type), LC32_GL_I32(stride),
        LC32_GL_PTR(pointer));
}

void glActiveShaderProgramEXT(GLuint pipeline, GLuint program) {
    LC32_GL_CALL(LC32OpenGLESOpActiveShaderProgramEXT,
        LC32_GL_U32(pipeline), LC32_GL_U32(program));
}

void glBeginQueryEXT(GLenum target, GLuint id) {
    LC32_GL_CALL(LC32OpenGLESOpBeginQueryEXT,
        LC32_GL_U32(target), LC32_GL_U32(id));
}

void glBindProgramPipelineEXT(GLuint pipeline) {
    LC32_GL_CALL(LC32OpenGLESOpBindProgramPipelineEXT,
        LC32_GL_U32(pipeline));
}

GLenum glClientWaitSyncAPPLE(GLsync sync, GLbitfield flags,
                             GLuint64 timeout) {
    return (GLenum)LC32_GL_CALL(LC32OpenGLESOpClientWaitSyncAPPLE,
        LC32_GL_PTR(sync), LC32_GL_U32(flags), LC32_GL_U64(timeout));
}

void glCopyTextureLevelsAPPLE(GLuint destinationTexture,
                              GLuint sourceTexture,
                              GLint sourceBaseLevel,
                              GLsizei sourceLevelCount) {
    LC32_GL_CALL(LC32OpenGLESOpCopyTextureLevelsAPPLE,
        LC32_GL_U32(destinationTexture), LC32_GL_U32(sourceTexture),
        LC32_GL_I32(sourceBaseLevel), LC32_GL_I32(sourceLevelCount));
}

GLuint glCreateShaderProgramvEXT(GLenum type, GLsizei count,
                                 const GLchar *const *strings) {
    return (GLuint)LC32_GL_CALL(LC32OpenGLESOpCreateShaderProgramvEXT,
        LC32_GL_U32(type), LC32_GL_I32(count), LC32_GL_PTR(strings));
}

void glDeleteProgramPipelinesEXT(GLsizei count, const GLuint *pipelines) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteProgramPipelinesEXT,
        LC32_GL_I32(count), LC32_GL_PTR(pipelines));
}

void glDeleteQueriesEXT(GLsizei count, const GLuint *ids) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteQueriesEXT,
        LC32_GL_I32(count), LC32_GL_PTR(ids));
}

void glDeleteSyncAPPLE(GLsync sync) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteSyncAPPLE, LC32_GL_PTR(sync));
}

void glDrawArraysInstancedEXT(GLenum mode, GLint first, GLsizei count,
                              GLsizei instanceCount) {
    LC32_GL_CALL(LC32OpenGLESOpDrawArraysInstancedEXT,
        LC32_GL_U32(mode), LC32_GL_I32(first), LC32_GL_I32(count),
        LC32_GL_I32(instanceCount));
}

void glDrawElementsInstancedEXT(GLenum mode, GLsizei count, GLenum type,
                                const GLvoid *indices,
                                GLsizei instanceCount) {
    LC32_GL_CALL(LC32OpenGLESOpDrawElementsInstancedEXT,
        LC32_GL_U32(mode), LC32_GL_I32(count), LC32_GL_U32(type),
        LC32_GL_PTR(indices), LC32_GL_I32(instanceCount));
}

void glEndQueryEXT(GLenum target) {
    LC32_GL_CALL(LC32OpenGLESOpEndQueryEXT, LC32_GL_U32(target));
}

GLsync glFenceSyncAPPLE(GLenum condition, GLbitfield flags) {
    return (GLsync)(uintptr_t)LC32_GL_CALL(LC32OpenGLESOpFenceSyncAPPLE,
        LC32_GL_U32(condition), LC32_GL_U32(flags));
}

void glFlushMappedBufferRangeEXT(GLenum target, GLintptr offset,
                                 GLsizeiptr length) {
    LC32_GL_CALL(LC32OpenGLESOpFlushMappedBufferRangeEXT,
        LC32_GL_U32(target), LC32_GL_I32(offset), LC32_GL_I32(length));
}

void glGenProgramPipelinesEXT(GLsizei count, GLuint *pipelines) {
    LC32_GL_CALL(LC32OpenGLESOpGenProgramPipelinesEXT,
        LC32_GL_I32(count), LC32_GL_PTR(pipelines));
}

void glGenQueriesEXT(GLsizei count, GLuint *ids) {
    LC32_GL_CALL(LC32OpenGLESOpGenQueriesEXT,
        LC32_GL_I32(count), LC32_GL_PTR(ids));
}

void glGetBufferPointervOES(GLenum target, GLenum pname, GLvoid **params) {
    uint32_t guestPointer = 0;
    LC32_GL_CALL(LC32OpenGLESOpGetBufferPointervOES,
        LC32_GL_U32(target), LC32_GL_U32(pname),
        LC32_GL_PTR(&guestPointer));
    if(params) *params = (GLvoid *)(uintptr_t)guestPointer;
}

void glGetInteger64vAPPLE(GLenum pname, GLint64 *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetInteger64vAPPLE,
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetObjectLabelEXT(GLenum type, GLuint object, GLsizei bufSize,
                         GLsizei *length, GLchar *label) {
    LC32_GL_CALL(LC32OpenGLESOpGetObjectLabelEXT,
        LC32_GL_U32(type), LC32_GL_U32(object), LC32_GL_I32(bufSize),
        LC32_GL_PTR(length), LC32_GL_PTR(label));
}

void glGetProgramPipelineInfoLogEXT(GLuint pipeline, GLsizei bufSize,
                                    GLsizei *length, GLchar *infoLog) {
    LC32_GL_CALL(LC32OpenGLESOpGetProgramPipelineInfoLogEXT,
        LC32_GL_U32(pipeline), LC32_GL_I32(bufSize),
        LC32_GL_PTR(length), LC32_GL_PTR(infoLog));
}

void glGetProgramPipelineivEXT(GLuint pipeline, GLenum pname,
                               GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetProgramPipelineivEXT,
        LC32_GL_U32(pipeline), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetQueryObjectuivEXT(GLuint id, GLenum pname, GLuint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetQueryObjectuivEXT,
        LC32_GL_U32(id), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetQueryivEXT(GLenum target, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetQueryivEXT,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetSyncivAPPLE(GLsync sync, GLenum pname, GLsizei bufSize,
                      GLsizei *length, GLint *values) {
    LC32_GL_CALL(LC32OpenGLESOpGetSyncivAPPLE,
        LC32_GL_PTR(sync), LC32_GL_U32(pname), LC32_GL_I32(bufSize),
        LC32_GL_PTR(length), LC32_GL_PTR(values));
}

void glInsertEventMarkerEXT(GLsizei length, const GLchar *marker) {
    LC32_GL_CALL(LC32OpenGLESOpInsertEventMarkerEXT,
        LC32_GL_I32(length), LC32_GL_PTR(marker));
}

GLboolean glIsProgramPipelineEXT(GLuint pipeline) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsProgramPipelineEXT,
        LC32_GL_U32(pipeline));
}

GLboolean glIsQueryEXT(GLuint id) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsQueryEXT,
        LC32_GL_U32(id));
}

GLboolean glIsSyncAPPLE(GLsync sync) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsSyncAPPLE,
        LC32_GL_PTR(sync));
}

GLboolean glIsVertexArrayOES(GLuint array) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsVertexArrayOES,
        LC32_GL_U32(array));
}

void glLabelObjectEXT(GLenum type, GLuint object, GLsizei length,
                      const GLchar *label) {
    LC32_GL_CALL(LC32OpenGLESOpLabelObjectEXT,
        LC32_GL_U32(type), LC32_GL_U32(object), LC32_GL_I32(length),
        LC32_GL_PTR(label));
}

GLvoid *glMapBufferOES(GLenum target, GLenum access) {
    GLint length = 0;
    glGetBufferParameteriv(target, GL_BUFFER_SIZE, &length);
    void *shadow = length > 0 ? malloc((size_t)length) : NULL;
    uint32_t mapped = LC32_GL_CALL(LC32OpenGLESOpMapBufferOES,
        LC32_GL_U32(target), LC32_GL_U32(access), LC32_GL_PTR(shadow),
        LC32_GL_I32(length));
    if(!mapped) {
        free(shadow);
        return NULL;
    }
    return shadow;
}

GLvoid *glMapBufferRangeEXT(GLenum target, GLintptr offset,
                            GLsizeiptr length, GLbitfield access) {
    void *shadow = length > 0 ? malloc((size_t)length) : NULL;
    uint32_t mapped = LC32_GL_CALL(LC32OpenGLESOpMapBufferRangeEXT,
        LC32_GL_U32(target), LC32_GL_I32(offset), LC32_GL_I32(length),
        LC32_GL_U32(access), LC32_GL_PTR(shadow));
    if(!mapped) {
        free(shadow);
        return NULL;
    }
    return shadow;
}

void glPopGroupMarkerEXT(void) {
    LC32_GL_CALL0(LC32OpenGLESOpPopGroupMarkerEXT);
}

void glProgramParameteriEXT(GLuint program, GLenum pname, GLint value) {
    LC32_GL_CALL(LC32OpenGLESOpProgramParameteriEXT,
        LC32_GL_U32(program), LC32_GL_U32(pname), LC32_GL_I32(value));
}

void glProgramUniform1fEXT(GLuint program, GLint location, GLfloat x) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform1fEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_F32(x));
}

void glProgramUniform2fEXT(GLuint program, GLint location,
                           GLfloat x, GLfloat y) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform2fEXT,
        LC32_GL_U32(program), LC32_GL_I32(location),
        LC32_GL_F32(x), LC32_GL_F32(y));
}

void glProgramUniform3fEXT(GLuint program, GLint location,
                           GLfloat x, GLfloat y, GLfloat z) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform3fEXT,
        LC32_GL_U32(program), LC32_GL_I32(location),
        LC32_GL_F32(x), LC32_GL_F32(y), LC32_GL_F32(z));
}

void glProgramUniform4fEXT(GLuint program, GLint location,
                           GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform4fEXT,
        LC32_GL_U32(program), LC32_GL_I32(location),
        LC32_GL_F32(x), LC32_GL_F32(y), LC32_GL_F32(z), LC32_GL_F32(w));
}

void glProgramUniform1iEXT(GLuint program, GLint location, GLint x) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform1iEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_I32(x));
}

void glProgramUniform2iEXT(GLuint program, GLint location, GLint x, GLint y) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform2iEXT,
        LC32_GL_U32(program), LC32_GL_I32(location),
        LC32_GL_I32(x), LC32_GL_I32(y));
}

void glProgramUniform3iEXT(GLuint program, GLint location,
                           GLint x, GLint y, GLint z) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform3iEXT,
        LC32_GL_U32(program), LC32_GL_I32(location),
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z));
}

void glProgramUniform4iEXT(GLuint program, GLint location,
                           GLint x, GLint y, GLint z, GLint w) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform4iEXT,
        LC32_GL_U32(program), LC32_GL_I32(location),
        LC32_GL_I32(x), LC32_GL_I32(y), LC32_GL_I32(z), LC32_GL_I32(w));
}

#define LC32_GL_PROGRAM_UNIFORM_ARRAY(width, suffix, type, opcode)          \
void glProgramUniform##width##suffix##EXT(GLuint program, GLint location,   \
        GLsizei count, const type *value) {                                 \
    LC32_GL_CALL((opcode), LC32_GL_U32(program), LC32_GL_I32(location),     \
        LC32_GL_I32(count), LC32_GL_PTR(value));                            \
}

LC32_GL_PROGRAM_UNIFORM_ARRAY(1, fv, GLfloat,
    LC32OpenGLESOpProgramUniform1fvEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(2, fv, GLfloat,
    LC32OpenGLESOpProgramUniform2fvEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(3, fv, GLfloat,
    LC32OpenGLESOpProgramUniform3fvEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(4, fv, GLfloat,
    LC32OpenGLESOpProgramUniform4fvEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(1, iv, GLint,
    LC32OpenGLESOpProgramUniform1ivEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(2, iv, GLint,
    LC32OpenGLESOpProgramUniform2ivEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(3, iv, GLint,
    LC32OpenGLESOpProgramUniform3ivEXT)
LC32_GL_PROGRAM_UNIFORM_ARRAY(4, iv, GLint,
    LC32OpenGLESOpProgramUniform4ivEXT)

#undef LC32_GL_PROGRAM_UNIFORM_ARRAY

#define LC32_GL_PROGRAM_UNIFORM_MATRIX(width, opcode)                     \
void glProgramUniformMatrix##width##fvEXT(GLuint program, GLint location,  \
        GLsizei count, GLboolean transpose, const GLfloat *value) {        \
    LC32_GL_CALL((opcode), LC32_GL_U32(program), LC32_GL_I32(location),    \
        LC32_GL_I32(count), LC32_GL_U32(transpose), LC32_GL_PTR(value));   \
}

LC32_GL_PROGRAM_UNIFORM_MATRIX(2, LC32OpenGLESOpProgramUniformMatrix2fvEXT)
LC32_GL_PROGRAM_UNIFORM_MATRIX(3, LC32OpenGLESOpProgramUniformMatrix3fvEXT)
LC32_GL_PROGRAM_UNIFORM_MATRIX(4, LC32OpenGLESOpProgramUniformMatrix4fvEXT)

#undef LC32_GL_PROGRAM_UNIFORM_MATRIX

void glPushGroupMarkerEXT(GLsizei length, const GLchar *marker) {
    LC32_GL_CALL(LC32OpenGLESOpPushGroupMarkerEXT,
        LC32_GL_I32(length), LC32_GL_PTR(marker));
}

void glTexStorage2DEXT(GLenum target, GLsizei levels,
                       GLenum internalformat, GLsizei width,
                       GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpTexStorage2DEXT,
        LC32_GL_U32(target), LC32_GL_I32(levels),
        LC32_GL_U32(internalformat), LC32_GL_I32(width),
        LC32_GL_I32(height));
}

GLboolean glUnmapBufferOES(GLenum target) {
    uint32_t guestPointer = 0;
    GLboolean result = (GLboolean)LC32_GL_CALL(
        LC32OpenGLESOpUnmapBufferOES, LC32_GL_U32(target),
        LC32_GL_PTR(&guestPointer));
    if(guestPointer) free((void *)(uintptr_t)guestPointer);
    return result;
}

void glUseProgramStagesEXT(GLuint pipeline, GLbitfield stages,
                           GLuint program) {
    LC32_GL_CALL(LC32OpenGLESOpUseProgramStagesEXT,
        LC32_GL_U32(pipeline), LC32_GL_U32(stages),
        LC32_GL_U32(program));
}

void glValidateProgramPipelineEXT(GLuint pipeline) {
    LC32_GL_CALL(LC32OpenGLESOpValidateProgramPipelineEXT,
        LC32_GL_U32(pipeline));
}

void glVertexAttribDivisorEXT(GLuint index, GLuint divisor) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribDivisorEXT,
        LC32_GL_U32(index), LC32_GL_U32(divisor));
}

void glWaitSyncAPPLE(GLsync sync, GLbitfield flags, GLuint64 timeout) {
    LC32_GL_CALL(LC32OpenGLESOpWaitSyncAPPLE,
        LC32_GL_PTR(sync), LC32_GL_U32(flags), LC32_GL_U64(timeout));
}

void glBeginTransformFeedback(GLenum primitiveMode) {
    LC32_GL_CALL(LC32OpenGLESOpBeginTransformFeedback,
        LC32_GL_U32(primitiveMode));
}

void glBindBufferBase(GLenum target, GLuint index, GLuint buffer) {
    LC32_GL_CALL(LC32OpenGLESOpBindBufferBase,
        LC32_GL_U32(target), LC32_GL_U32(index), LC32_GL_U32(buffer));
}

void glBindBufferRange(GLenum target, GLuint index, GLuint buffer,
                       GLintptr offset, GLsizeiptr size) {
    LC32_GL_CALL(LC32OpenGLESOpBindBufferRange,
        LC32_GL_U32(target), LC32_GL_U32(index), LC32_GL_U32(buffer),
        LC32_GL_I32(offset), LC32_GL_I32(size));
}

void glBindSampler(GLuint unit, GLuint sampler) {
    LC32_GL_CALL(LC32OpenGLESOpBindSampler,
        LC32_GL_U32(unit), LC32_GL_U32(sampler));
}

void glBindTransformFeedback(GLenum target, GLuint id) {
    LC32_GL_CALL(LC32OpenGLESOpBindTransformFeedback,
        LC32_GL_U32(target), LC32_GL_U32(id));
}

void glBlitFramebuffer(GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1,
                       GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1,
                       GLbitfield mask, GLenum filter) {
    LC32_GL_CALL(LC32OpenGLESOpBlitFramebuffer,
        LC32_GL_I32(srcX0), LC32_GL_I32(srcY0), LC32_GL_I32(srcX1),
        LC32_GL_I32(srcY1), LC32_GL_I32(dstX0), LC32_GL_I32(dstY0),
        LC32_GL_I32(dstX1), LC32_GL_I32(dstY1), LC32_GL_U32(mask),
        LC32_GL_U32(filter));
}

void glClearBufferfi(GLenum buffer, GLint drawbuffer, GLfloat depth,
                     GLint stencil) {
    LC32_GL_CALL(LC32OpenGLESOpClearBufferfi,
        LC32_GL_U32(buffer), LC32_GL_I32(drawbuffer),
        LC32_GL_F32(depth), LC32_GL_I32(stencil));
}

void glClearBufferfv(GLenum buffer, GLint drawbuffer, const GLfloat *value) {
    LC32_GL_CALL(LC32OpenGLESOpClearBufferfv,
        LC32_GL_U32(buffer), LC32_GL_I32(drawbuffer), LC32_GL_PTR(value));
}

void glClearBufferiv(GLenum buffer, GLint drawbuffer, const GLint *value) {
    LC32_GL_CALL(LC32OpenGLESOpClearBufferiv,
        LC32_GL_U32(buffer), LC32_GL_I32(drawbuffer), LC32_GL_PTR(value));
}

void glClearBufferuiv(GLenum buffer, GLint drawbuffer, const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpClearBufferuiv,
        LC32_GL_U32(buffer), LC32_GL_I32(drawbuffer), LC32_GL_PTR(value));
}

void glCompressedTexImage3D(GLenum target, GLint level,
                            GLenum internalformat, GLsizei width,
                            GLsizei height, GLsizei depth, GLint border,
                            GLsizei imageSize, const GLvoid *data) {
    LC32_GL_CALL(LC32OpenGLESOpCompressedTexImage3D,
        LC32_GL_U32(target), LC32_GL_I32(level),
        LC32_GL_U32(internalformat), LC32_GL_I32(width),
        LC32_GL_I32(height), LC32_GL_I32(depth), LC32_GL_I32(border),
        LC32_GL_I32(imageSize), LC32_GL_PTR(data));
}

void glCompressedTexSubImage3D(GLenum target, GLint level, GLint xoffset,
                               GLint yoffset, GLint zoffset, GLsizei width,
                               GLsizei height, GLsizei depth, GLenum format,
                               GLsizei imageSize, const GLvoid *data) {
    LC32_GL_CALL(LC32OpenGLESOpCompressedTexSubImage3D,
        LC32_GL_U32(target), LC32_GL_I32(level), LC32_GL_I32(xoffset),
        LC32_GL_I32(yoffset), LC32_GL_I32(zoffset), LC32_GL_I32(width),
        LC32_GL_I32(height), LC32_GL_I32(depth), LC32_GL_U32(format),
        LC32_GL_I32(imageSize), LC32_GL_PTR(data));
}

void glCopyBufferSubData(GLenum readTarget, GLenum writeTarget,
                         GLintptr readOffset, GLintptr writeOffset,
                         GLsizeiptr size) {
    LC32_GL_CALL(LC32OpenGLESOpCopyBufferSubData,
        LC32_GL_U32(readTarget), LC32_GL_U32(writeTarget),
        LC32_GL_I32(readOffset), LC32_GL_I32(writeOffset),
        LC32_GL_I32(size));
}

void glCopyTexSubImage3D(GLenum target, GLint level, GLint xoffset,
                         GLint yoffset, GLint zoffset, GLint x, GLint y,
                         GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpCopyTexSubImage3D,
        LC32_GL_U32(target), LC32_GL_I32(level), LC32_GL_I32(xoffset),
        LC32_GL_I32(yoffset), LC32_GL_I32(zoffset), LC32_GL_I32(x),
        LC32_GL_I32(y), LC32_GL_I32(width), LC32_GL_I32(height));
}

void glDeleteSamplers(GLsizei count, const GLuint *samplers) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteSamplers,
        LC32_GL_I32(count), LC32_GL_PTR(samplers));
}

void glDeleteTransformFeedbacks(GLsizei count, const GLuint *ids) {
    LC32_GL_CALL(LC32OpenGLESOpDeleteTransformFeedbacks,
        LC32_GL_I32(count), LC32_GL_PTR(ids));
}

void glDrawBuffers(GLsizei count, const GLenum *buffers) {
    LC32_GL_CALL(LC32OpenGLESOpDrawBuffers,
        LC32_GL_I32(count), LC32_GL_PTR(buffers));
}

void glDrawRangeElements(GLenum mode, GLuint start, GLuint end,
                         GLsizei count, GLenum type,
                         const GLvoid *indices) {
    LC32_GL_CALL(LC32OpenGLESOpDrawRangeElements,
        LC32_GL_U32(mode), LC32_GL_U32(start), LC32_GL_U32(end),
        LC32_GL_I32(count), LC32_GL_U32(type), LC32_GL_PTR(indices));
}

void glEndTransformFeedback(void) {
    LC32_GL_CALL0(LC32OpenGLESOpEndTransformFeedback);
}

void glFramebufferTextureLayer(GLenum target, GLenum attachment,
                               GLuint texture, GLint level, GLint layer) {
    LC32_GL_CALL(LC32OpenGLESOpFramebufferTextureLayer,
        LC32_GL_U32(target), LC32_GL_U32(attachment),
        LC32_GL_U32(texture), LC32_GL_I32(level), LC32_GL_I32(layer));
}

void glGenSamplers(GLsizei count, GLuint *samplers) {
    LC32_GL_CALL(LC32OpenGLESOpGenSamplers,
        LC32_GL_I32(count), LC32_GL_PTR(samplers));
}

void glGenTransformFeedbacks(GLsizei count, GLuint *ids) {
    LC32_GL_CALL(LC32OpenGLESOpGenTransformFeedbacks,
        LC32_GL_I32(count), LC32_GL_PTR(ids));
}

void glGetActiveUniformBlockName(GLuint program, GLuint blockIndex,
                                 GLsizei bufSize, GLsizei *length,
                                 GLchar *name) {
    LC32_GL_CALL(LC32OpenGLESOpGetActiveUniformBlockName,
        LC32_GL_U32(program), LC32_GL_U32(blockIndex),
        LC32_GL_I32(bufSize), LC32_GL_PTR(length), LC32_GL_PTR(name));
}

void glGetActiveUniformBlockiv(GLuint program, GLuint blockIndex,
                               GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetActiveUniformBlockiv,
        LC32_GL_U32(program), LC32_GL_U32(blockIndex),
        LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetActiveUniformsiv(GLuint program, GLsizei uniformCount,
                           const GLuint *uniformIndices, GLenum pname,
                           GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetActiveUniformsiv,
        LC32_GL_U32(program), LC32_GL_I32(uniformCount),
        LC32_GL_PTR(uniformIndices), LC32_GL_U32(pname),
        LC32_GL_PTR(params));
}

void glGetBufferParameteri64v(GLenum target, GLenum pname, GLint64 *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetBufferParameteri64v,
        LC32_GL_U32(target), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

GLint glGetFragDataLocation(GLuint program, const GLchar *name) {
    return (GLint)LC32_GL_CALL(LC32OpenGLESOpGetFragDataLocation,
        LC32_GL_U32(program), LC32_GL_PTR(name));
}

void glGetInteger64i_v(GLenum target, GLuint index, GLint64 *data) {
    LC32_GL_CALL(LC32OpenGLESOpGetInteger64i_v,
        LC32_GL_U32(target), LC32_GL_U32(index), LC32_GL_PTR(data));
}

void glGetIntegeri_v(GLenum target, GLuint index, GLint *data) {
    LC32_GL_CALL(LC32OpenGLESOpGetIntegeri_v,
        LC32_GL_U32(target), LC32_GL_U32(index), LC32_GL_PTR(data));
}

void glGetInternalformativ(GLenum target, GLenum internalformat,
                           GLenum pname, GLsizei bufSize, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetInternalformativ,
        LC32_GL_U32(target), LC32_GL_U32(internalformat),
        LC32_GL_U32(pname), LC32_GL_I32(bufSize), LC32_GL_PTR(params));
}

void glGetProgramBinary(GLuint program, GLsizei bufSize, GLsizei *length,
                        GLenum *binaryFormat, GLvoid *binary) {
    LC32_GL_CALL(LC32OpenGLESOpGetProgramBinary,
        LC32_GL_U32(program), LC32_GL_I32(bufSize), LC32_GL_PTR(length),
        LC32_GL_PTR(binaryFormat), LC32_GL_PTR(binary));
}

void glGetSamplerParameterfv(GLuint sampler, GLenum pname, GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetSamplerParameterfv,
        LC32_GL_U32(sampler), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetSamplerParameteriv(GLuint sampler, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetSamplerParameteriv,
        LC32_GL_U32(sampler), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

typedef struct LC32OpenGLESIndexedStringCache {
    GLenum name;
    GLuint index;
    GLubyte *bytes;
    uint32_t capacity;
    struct LC32OpenGLESIndexedStringCache *next;
} LC32OpenGLESIndexedStringCache;

static __thread LC32OpenGLESIndexedStringCache *LC32OpenGLESIndexedStrings;

const GLubyte *glGetStringi(GLenum name, GLuint index) {
    LC32OpenGLESIndexedStringCache *cache = LC32OpenGLESIndexedStrings;
    while(cache && (cache->name != name || cache->index != index))
        cache = cache->next;
    if(!cache) {
        cache = calloc(1, sizeof(*cache));
        if(!cache) return NULL;
        cache->name = name;
        cache->index = index;
        cache->next = LC32OpenGLESIndexedStrings;
        LC32OpenGLESIndexedStrings = cache;
    }

    const uint32_t length = LC32_GL_CALL(
        LC32OpenGLESOpGetStringiLength, LC32_GL_U32(name),
        LC32_GL_U32(index));
    if(!length) return NULL;
    if(cache->capacity < length) {
        GLubyte *replacement = realloc(cache->bytes, length);
        if(!replacement) return NULL;
        cache->bytes = replacement;
        cache->capacity = length;
    }
    const uint32_t copied = LC32_GL_CALL(LC32OpenGLESOpGetStringiCopy,
        LC32_GL_U32(name), LC32_GL_U32(index), LC32_GL_PTR(cache->bytes),
        LC32_GL_U32(cache->capacity));
    return copied == length ? cache->bytes : NULL;
}

void glGetTransformFeedbackVarying(GLuint program, GLuint index,
                                   GLsizei bufSize, GLsizei *length,
                                   GLsizei *size, GLenum *type,
                                   GLchar *name) {
    LC32_GL_CALL(LC32OpenGLESOpGetTransformFeedbackVarying,
        LC32_GL_U32(program), LC32_GL_U32(index), LC32_GL_I32(bufSize),
        LC32_GL_PTR(length), LC32_GL_PTR(size), LC32_GL_PTR(type),
        LC32_GL_PTR(name));
}

GLuint glGetUniformBlockIndex(GLuint program, const GLchar *name) {
    return (GLuint)LC32_GL_CALL(LC32OpenGLESOpGetUniformBlockIndex,
        LC32_GL_U32(program), LC32_GL_PTR(name));
}

void glGetUniformIndices(GLuint program, GLsizei uniformCount,
                         const GLchar *const *uniformNames,
                         GLuint *uniformIndices) {
    LC32_GL_CALL(LC32OpenGLESOpGetUniformIndices,
        LC32_GL_U32(program), LC32_GL_I32(uniformCount),
        LC32_GL_PTR(uniformNames), LC32_GL_PTR(uniformIndices));
}

void glGetUniformuiv(GLuint program, GLint location, GLuint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetUniformuiv,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_PTR(params));
}

void glGetVertexAttribIiv(GLuint index, GLenum pname, GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetVertexAttribIiv,
        LC32_GL_U32(index), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glGetVertexAttribIuiv(GLuint index, GLenum pname, GLuint *params) {
    LC32_GL_CALL(LC32OpenGLESOpGetVertexAttribIuiv,
        LC32_GL_U32(index), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glInvalidateFramebuffer(GLenum target, GLsizei numAttachments,
                             const GLenum *attachments) {
    LC32_GL_CALL(LC32OpenGLESOpInvalidateFramebuffer,
        LC32_GL_U32(target), LC32_GL_I32(numAttachments),
        LC32_GL_PTR(attachments));
}

void glInvalidateSubFramebuffer(GLenum target, GLsizei numAttachments,
                                const GLenum *attachments, GLint x, GLint y,
                                GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpInvalidateSubFramebuffer,
        LC32_GL_U32(target), LC32_GL_I32(numAttachments),
        LC32_GL_PTR(attachments), LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

GLboolean glIsSampler(GLuint sampler) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsSampler,
        LC32_GL_U32(sampler));
}

GLboolean glIsTransformFeedback(GLuint id) {
    return (GLboolean)LC32_GL_CALL(LC32OpenGLESOpIsTransformFeedback,
        LC32_GL_U32(id));
}

void glPauseTransformFeedback(void) {
    LC32_GL_CALL0(LC32OpenGLESOpPauseTransformFeedback);
}

void glProgramBinary(GLuint program, GLenum binaryFormat,
                     const GLvoid *binary, GLsizei length) {
    LC32_GL_CALL(LC32OpenGLESOpProgramBinary,
        LC32_GL_U32(program), LC32_GL_U32(binaryFormat),
        LC32_GL_PTR(binary), LC32_GL_I32(length));
}

void glProgramUniform1uiEXT(GLuint program, GLint location, GLuint x) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform1uiEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_U32(x));
}

void glProgramUniform2uiEXT(GLuint program, GLint location, GLuint x,
                            GLuint y) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform2uiEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_U32(x),
        LC32_GL_U32(y));
}

void glProgramUniform3uiEXT(GLuint program, GLint location, GLuint x,
                            GLuint y, GLuint z) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform3uiEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_U32(x),
        LC32_GL_U32(y), LC32_GL_U32(z));
}

void glProgramUniform4uiEXT(GLuint program, GLint location, GLuint x,
                            GLuint y, GLuint z, GLuint w) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform4uiEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_U32(x),
        LC32_GL_U32(y), LC32_GL_U32(z), LC32_GL_U32(w));
}

void glProgramUniform1uivEXT(GLuint program, GLint location, GLsizei count,
                             const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform1uivEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_I32(count),
        LC32_GL_PTR(value));
}

void glProgramUniform2uivEXT(GLuint program, GLint location, GLsizei count,
                             const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform2uivEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_I32(count),
        LC32_GL_PTR(value));
}

void glProgramUniform3uivEXT(GLuint program, GLint location, GLsizei count,
                             const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform3uivEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_I32(count),
        LC32_GL_PTR(value));
}

void glProgramUniform4uivEXT(GLuint program, GLint location, GLsizei count,
                             const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpProgramUniform4uivEXT,
        LC32_GL_U32(program), LC32_GL_I32(location), LC32_GL_I32(count),
        LC32_GL_PTR(value));
}

#define LC32_PROGRAM_MATRIX_EXT_BODY(opcode) \
    LC32_GL_CALL((opcode), LC32_GL_U32(program), LC32_GL_I32(location), \
        LC32_GL_I32(count), LC32_GL_U32(transpose), LC32_GL_PTR(value))

void glProgramUniformMatrix2x3fvEXT(GLuint program, GLint location,
                                    GLsizei count, GLboolean transpose,
                                    const GLfloat *value) {
    LC32_PROGRAM_MATRIX_EXT_BODY(
        LC32OpenGLESOpProgramUniformMatrix2x3fvEXT);
}
void glProgramUniformMatrix2x4fvEXT(GLuint program, GLint location,
                                    GLsizei count, GLboolean transpose,
                                    const GLfloat *value) {
    LC32_PROGRAM_MATRIX_EXT_BODY(
        LC32OpenGLESOpProgramUniformMatrix2x4fvEXT);
}
void glProgramUniformMatrix3x2fvEXT(GLuint program, GLint location,
                                    GLsizei count, GLboolean transpose,
                                    const GLfloat *value) {
    LC32_PROGRAM_MATRIX_EXT_BODY(
        LC32OpenGLESOpProgramUniformMatrix3x2fvEXT);
}
void glProgramUniformMatrix3x4fvEXT(GLuint program, GLint location,
                                    GLsizei count, GLboolean transpose,
                                    const GLfloat *value) {
    LC32_PROGRAM_MATRIX_EXT_BODY(
        LC32OpenGLESOpProgramUniformMatrix3x4fvEXT);
}
void glProgramUniformMatrix4x2fvEXT(GLuint program, GLint location,
                                    GLsizei count, GLboolean transpose,
                                    const GLfloat *value) {
    LC32_PROGRAM_MATRIX_EXT_BODY(
        LC32OpenGLESOpProgramUniformMatrix4x2fvEXT);
}
void glProgramUniformMatrix4x3fvEXT(GLuint program, GLint location,
                                    GLsizei count, GLboolean transpose,
                                    const GLfloat *value) {
    LC32_PROGRAM_MATRIX_EXT_BODY(
        LC32OpenGLESOpProgramUniformMatrix4x3fvEXT);
}

void glReadBuffer(GLenum mode) {
    LC32_GL_CALL(LC32OpenGLESOpReadBuffer, LC32_GL_U32(mode));
}

void glResumeTransformFeedback(void) {
    LC32_GL_CALL0(LC32OpenGLESOpResumeTransformFeedback);
}

void glSamplerParameterf(GLuint sampler, GLenum pname, GLfloat param) {
    LC32_GL_CALL(LC32OpenGLESOpSamplerParameterf,
        LC32_GL_U32(sampler), LC32_GL_U32(pname), LC32_GL_F32(param));
}

void glSamplerParameterfv(GLuint sampler, GLenum pname,
                          const GLfloat *params) {
    LC32_GL_CALL(LC32OpenGLESOpSamplerParameterfv,
        LC32_GL_U32(sampler), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glSamplerParameteri(GLuint sampler, GLenum pname, GLint param) {
    LC32_GL_CALL(LC32OpenGLESOpSamplerParameteri,
        LC32_GL_U32(sampler), LC32_GL_U32(pname), LC32_GL_I32(param));
}

void glSamplerParameteriv(GLuint sampler, GLenum pname, const GLint *params) {
    LC32_GL_CALL(LC32OpenGLESOpSamplerParameteriv,
        LC32_GL_U32(sampler), LC32_GL_U32(pname), LC32_GL_PTR(params));
}

void glTexImage3D(GLenum target, GLint level, GLint internalformat,
                  GLsizei width, GLsizei height, GLsizei depth, GLint border,
                  GLenum format, GLenum type, const GLvoid *pixels) {
    LC32_GL_CALL(LC32OpenGLESOpTexImage3D,
        LC32_GL_U32(target), LC32_GL_I32(level), LC32_GL_I32(internalformat),
        LC32_GL_I32(width), LC32_GL_I32(height), LC32_GL_I32(depth),
        LC32_GL_I32(border), LC32_GL_U32(format), LC32_GL_U32(type),
        LC32_GL_PTR(pixels));
}

void glTexStorage3D(GLenum target, GLsizei levels, GLenum internalformat,
                    GLsizei width, GLsizei height, GLsizei depth) {
    LC32_GL_CALL(LC32OpenGLESOpTexStorage3D,
        LC32_GL_U32(target), LC32_GL_I32(levels),
        LC32_GL_U32(internalformat), LC32_GL_I32(width),
        LC32_GL_I32(height), LC32_GL_I32(depth));
}

void glTexSubImage3D(GLenum target, GLint level, GLint xoffset, GLint yoffset,
                     GLint zoffset, GLsizei width, GLsizei height,
                     GLsizei depth, GLenum format, GLenum type,
                     const GLvoid *pixels) {
    LC32_GL_CALL(LC32OpenGLESOpTexSubImage3D,
        LC32_GL_U32(target), LC32_GL_I32(level), LC32_GL_I32(xoffset),
        LC32_GL_I32(yoffset), LC32_GL_I32(zoffset), LC32_GL_I32(width),
        LC32_GL_I32(height), LC32_GL_I32(depth), LC32_GL_U32(format),
        LC32_GL_U32(type), LC32_GL_PTR(pixels));
}

void glTransformFeedbackVaryings(GLuint program, GLsizei count,
                                 const GLchar *const *varyings,
                                 GLenum bufferMode) {
    LC32_GL_CALL(LC32OpenGLESOpTransformFeedbackVaryings,
        LC32_GL_U32(program), LC32_GL_I32(count), LC32_GL_PTR(varyings),
        LC32_GL_U32(bufferMode));
}

void glUniform1ui(GLint location, GLuint v0) {
    LC32_GL_CALL(LC32OpenGLESOpUniform1ui,
        LC32_GL_I32(location), LC32_GL_U32(v0));
}

void glUniform2ui(GLint location, GLuint v0, GLuint v1) {
    LC32_GL_CALL(LC32OpenGLESOpUniform2ui,
        LC32_GL_I32(location), LC32_GL_U32(v0), LC32_GL_U32(v1));
}

void glUniform3ui(GLint location, GLuint v0, GLuint v1, GLuint v2) {
    LC32_GL_CALL(LC32OpenGLESOpUniform3ui,
        LC32_GL_I32(location), LC32_GL_U32(v0), LC32_GL_U32(v1),
        LC32_GL_U32(v2));
}

void glUniform4ui(GLint location, GLuint v0, GLuint v1, GLuint v2,
                  GLuint v3) {
    LC32_GL_CALL(LC32OpenGLESOpUniform4ui,
        LC32_GL_I32(location), LC32_GL_U32(v0), LC32_GL_U32(v1),
        LC32_GL_U32(v2), LC32_GL_U32(v3));
}

void glUniform1uiv(GLint location, GLsizei count, const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpUniform1uiv, LC32_GL_I32(location),
        LC32_GL_I32(count), LC32_GL_PTR(value));
}
void glUniform2uiv(GLint location, GLsizei count, const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpUniform2uiv, LC32_GL_I32(location),
        LC32_GL_I32(count), LC32_GL_PTR(value));
}
void glUniform3uiv(GLint location, GLsizei count, const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpUniform3uiv, LC32_GL_I32(location),
        LC32_GL_I32(count), LC32_GL_PTR(value));
}
void glUniform4uiv(GLint location, GLsizei count, const GLuint *value) {
    LC32_GL_CALL(LC32OpenGLESOpUniform4uiv, LC32_GL_I32(location),
        LC32_GL_I32(count), LC32_GL_PTR(value));
}

void glUniformBlockBinding(GLuint program, GLuint uniformBlockIndex,
                           GLuint uniformBlockBinding) {
    LC32_GL_CALL(LC32OpenGLESOpUniformBlockBinding,
        LC32_GL_U32(program), LC32_GL_U32(uniformBlockIndex),
        LC32_GL_U32(uniformBlockBinding));
}

#define LC32_UNIFORM_MATRIX_BODY(opcode) \
    LC32_GL_CALL((opcode), LC32_GL_I32(location), LC32_GL_I32(count), \
        LC32_GL_U32(transpose), LC32_GL_PTR(value))

void glUniformMatrix2x3fv(GLint location, GLsizei count, GLboolean transpose,
                          const GLfloat *value) {
    LC32_UNIFORM_MATRIX_BODY(LC32OpenGLESOpUniformMatrix2x3fv);
}
void glUniformMatrix2x4fv(GLint location, GLsizei count, GLboolean transpose,
                          const GLfloat *value) {
    LC32_UNIFORM_MATRIX_BODY(LC32OpenGLESOpUniformMatrix2x4fv);
}
void glUniformMatrix3x2fv(GLint location, GLsizei count, GLboolean transpose,
                          const GLfloat *value) {
    LC32_UNIFORM_MATRIX_BODY(LC32OpenGLESOpUniformMatrix3x2fv);
}
void glUniformMatrix3x4fv(GLint location, GLsizei count, GLboolean transpose,
                          const GLfloat *value) {
    LC32_UNIFORM_MATRIX_BODY(LC32OpenGLESOpUniformMatrix3x4fv);
}
void glUniformMatrix4x2fv(GLint location, GLsizei count, GLboolean transpose,
                          const GLfloat *value) {
    LC32_UNIFORM_MATRIX_BODY(LC32OpenGLESOpUniformMatrix4x2fv);
}
void glUniformMatrix4x3fv(GLint location, GLsizei count, GLboolean transpose,
                          const GLfloat *value) {
    LC32_UNIFORM_MATRIX_BODY(LC32OpenGLESOpUniformMatrix4x3fv);
}

void glVertexAttribI4i(GLuint index, GLint x, GLint y, GLint z, GLint w) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribI4i,
        LC32_GL_U32(index), LC32_GL_I32(x), LC32_GL_I32(y),
        LC32_GL_I32(z), LC32_GL_I32(w));
}

void glVertexAttribI4iv(GLuint index, const GLint *v) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribI4iv,
        LC32_GL_U32(index), LC32_GL_PTR(v));
}

void glVertexAttribI4ui(GLuint index, GLuint x, GLuint y, GLuint z,
                        GLuint w) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribI4ui,
        LC32_GL_U32(index), LC32_GL_U32(x), LC32_GL_U32(y),
        LC32_GL_U32(z), LC32_GL_U32(w));
}

void glVertexAttribI4uiv(GLuint index, const GLuint *v) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribI4uiv,
        LC32_GL_U32(index), LC32_GL_PTR(v));
}

void glVertexAttribIPointer(GLuint index, GLint size, GLenum type,
                            GLsizei stride, const GLvoid *pointer) {
    LC32_GL_CALL(LC32OpenGLESOpVertexAttribIPointer,
        LC32_GL_U32(index), LC32_GL_I32(size), LC32_GL_U32(type),
        LC32_GL_I32(stride), LC32_GL_PTR(pointer));
}

#undef LC32_PROGRAM_MATRIX_EXT_BODY
#undef LC32_UNIFORM_MATRIX_BODY

/*
 * OpenGL ES 3 promoted these extension entry points without changing their
 * ABI.  Export true symbol aliases so clients comparing function pointers see
 * the same address and so the guest never gains a second dispatcher path for
 * one operation.
 */
LC32_ASM_GLOBAL_ALIAS(glBeginQuery, glBeginQueryEXT);
LC32_ASM_GLOBAL_ALIAS(glBindVertexArray, glBindVertexArrayOES);
LC32_ASM_GLOBAL_ALIAS(glClientWaitSync, glClientWaitSyncAPPLE);
LC32_ASM_GLOBAL_ALIAS(glDeleteQueries, glDeleteQueriesEXT);
LC32_ASM_GLOBAL_ALIAS(glDeleteSync, glDeleteSyncAPPLE);
LC32_ASM_GLOBAL_ALIAS(glDeleteVertexArrays, glDeleteVertexArraysOES);
LC32_ASM_GLOBAL_ALIAS(glDrawArraysInstanced, glDrawArraysInstancedEXT);
LC32_ASM_GLOBAL_ALIAS(glDrawElementsInstanced, glDrawElementsInstancedEXT);
LC32_ASM_GLOBAL_ALIAS(glEndQuery, glEndQueryEXT);
LC32_ASM_GLOBAL_ALIAS(glFenceSync, glFenceSyncAPPLE);
LC32_ASM_GLOBAL_ALIAS(glFlushMappedBufferRange,
                      glFlushMappedBufferRangeEXT);
LC32_ASM_GLOBAL_ALIAS(glGenQueries, glGenQueriesEXT);
LC32_ASM_GLOBAL_ALIAS(glGenVertexArrays, glGenVertexArraysOES);
LC32_ASM_GLOBAL_ALIAS(glGetBufferPointerv, glGetBufferPointervOES);
LC32_ASM_GLOBAL_ALIAS(glGetInteger64v, glGetInteger64vAPPLE);
LC32_ASM_GLOBAL_ALIAS(glGetQueryObjectuiv, glGetQueryObjectuivEXT);
LC32_ASM_GLOBAL_ALIAS(glGetQueryiv, glGetQueryivEXT);
LC32_ASM_GLOBAL_ALIAS(glGetSynciv, glGetSyncivAPPLE);
LC32_ASM_GLOBAL_ALIAS(glIsQuery, glIsQueryEXT);
LC32_ASM_GLOBAL_ALIAS(glIsSync, glIsSyncAPPLE);
LC32_ASM_GLOBAL_ALIAS(glIsVertexArray, glIsVertexArrayOES);
LC32_ASM_GLOBAL_ALIAS(glMapBufferRange, glMapBufferRangeEXT);
LC32_ASM_GLOBAL_ALIAS(glProgramParameteri, glProgramParameteriEXT);
LC32_ASM_GLOBAL_ALIAS(glRenderbufferStorageMultisample,
                      glRenderbufferStorageMultisampleAPPLE);
LC32_ASM_GLOBAL_ALIAS(glTexStorage2D, glTexStorage2DEXT);
LC32_ASM_GLOBAL_ALIAS(glUnmapBuffer, glUnmapBufferOES);
LC32_ASM_GLOBAL_ALIAS(glVertexAttribDivisor, glVertexAttribDivisorEXT);
LC32_ASM_GLOBAL_ALIAS(glWaitSync, glWaitSyncAPPLE);
