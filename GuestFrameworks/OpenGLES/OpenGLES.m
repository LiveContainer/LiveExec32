#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
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
LC32_GL_ARRAY_OUT(glGenBuffers, LC32OpenGLESOpGenBuffers, GLuint)
LC32_GL_ARRAY_OUT(glGenFramebuffers, LC32OpenGLESOpGenFramebuffers, GLuint)
LC32_GL_ARRAY_OUT(glGenRenderbuffers, LC32OpenGLESOpGenRenderbuffers, GLuint)
LC32_GL_ARRAY_OUT(glGenTextures, LC32OpenGLESOpGenTextures, GLuint)

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

void glBindRenderbufferOES(GLenum target, GLuint renderbuffer) {
    LC32_GL_CALL(LC32OpenGLESOpBindRenderbufferOES,
        LC32_GL_U32(target), LC32_GL_U32(renderbuffer));
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

void glFramebufferRenderbufferOES(GLenum target, GLenum attachment,
                                  GLenum renderbufferTarget,
                                  GLuint renderbuffer) {
    LC32_GL_CALL(LC32OpenGLESOpFramebufferRenderbufferOES,
        LC32_GL_U32(target), LC32_GL_U32(attachment),
        LC32_GL_U32(renderbufferTarget), LC32_GL_U32(renderbuffer));
}

void glGenRenderbuffersOES(GLsizei count, GLuint *renderbuffers) {
    LC32_GL_CALL(LC32OpenGLESOpGenRenderbuffersOES,
        LC32_GL_I32(count), LC32_GL_PTR(renderbuffers));
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

void glRenderbufferStorageOES(GLenum target, GLenum internalFormat,
                              GLsizei width, GLsizei height) {
    LC32_GL_CALL(LC32OpenGLESOpRenderbufferStorageOES,
        LC32_GL_U32(target), LC32_GL_U32(internalFormat),
        LC32_GL_I32(width), LC32_GL_I32(height));
}

/* Legacy OES aliases.  These were the only names exposed by the iOS 2.x-era
 * OpenGL ES 1 headers, so old apps link against them; the host exports the
 * extension-free entry points only. */
void glBindFramebufferOES(GLenum target, GLuint framebuffer) {
    glBindFramebuffer(target, framebuffer);
}

GLenum glCheckFramebufferStatusOES(GLenum target) {
    return glCheckFramebufferStatus(target);
}

void glDeleteFramebuffersOES(GLsizei count, const GLuint *framebuffers) {
    glDeleteFramebuffers(count, framebuffers);
}

void glDeleteRenderbuffersOES(GLsizei count, const GLuint *renderbuffers) {
    glDeleteRenderbuffers(count, renderbuffers);
}

void glFramebufferTexture2DOES(GLenum target, GLenum attachment,
                               GLenum textureTarget, GLuint texture,
                               GLint level) {
    glFramebufferTexture2D(target, attachment, textureTarget, texture,
        level);
}

void glGenFramebuffersOES(GLsizei count, GLuint *framebuffers) {
    glGenFramebuffers(count, framebuffers);
}

void glGetRenderbufferParameterivOES(GLenum target, GLenum pname,
                                     GLint *params) {
    glGetRenderbufferParameteriv(target, pname, params);
}

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
