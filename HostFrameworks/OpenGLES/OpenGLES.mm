#define GLES_SILENCE_DEPRECATION 1

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/ES3/gl.h>
#import <OpenGLES/ES3/glext.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <objc/runtime.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "bridge.h"
#include "../../GuestFrameworks/OpenGLES/LC32OpenGLESBridge.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface EAGLContext (LC32EAGLCompatibility)
- (BOOL)lc32_renderbufferStorage:(NSUInteger)target
                    fromDrawable:(id<EAGLDrawable>)drawable;
@end

@interface LC32EAGLContextStateLifetime : NSObject {
@public
    uintptr_t _contextKey;
}
@end

@interface LC32EAGLSharegroupStateLifetime : NSObject {
@public
    uintptr_t _sharegroupKey;
}
@end

namespace {

constexpr size_t kMaximumTransfer = 256u * 1024u * 1024u;
constexpr size_t kMaximumString = 16u * 1024u * 1024u;

thread_local GLenum bridgeError = GL_NO_ERROR;

void SetBridgeError(GLenum error) {
    if(bridgeError == GL_NO_ERROR) bridgeError = error;
}

bool GuestRangeValid(uint32_t guestAddress, size_t byteCount) {
    return static_cast<uint64_t>(byteCount) <=
        (UINT64_C(1) << 32) - static_cast<uint64_t>(guestAddress);
}

bool ReadCall(uint32_t guestAddress, LC32OpenGLESCall &call) {
    struct {
        uint32_t version;
        uint32_t slotCount;
    } header = {};
    if(!guestAddress || !GuestRangeValid(guestAddress, sizeof(header)) ||
       Dynarmic_mem_1read(guestAddress, sizeof(header),
                          reinterpret_cast<char *>(&header)) != 0 ||
       header.version != LC32OpenGLESABIVersion ||
       header.slotCount > LC32OpenGLESMaxSlots) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }

    call = {};
    call.version = header.version;
    call.slotCount = header.slotCount;
    const size_t byteCount = header.slotCount * sizeof(call.slots[0]);
    constexpr uint32_t slotsOffset =
        static_cast<uint32_t>(offsetof(LC32OpenGLESCall, slots));
    if(byteCount &&
       (!GuestRangeValid(guestAddress, slotsOffset + byteCount) ||
        Dynarmic_mem_1read(guestAddress + slotsOffset, byteCount,
            reinterpret_cast<char *>(call.slots)) != 0)) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }
    return true;
}

bool RequireSlots(const LC32OpenGLESCall &call, uint32_t count) {
    if(call.slotCount == count) return true;
    SetBridgeError(GL_INVALID_OPERATION);
    return false;
}

uint32_t SlotU32(const LC32OpenGLESCall &call, size_t index) {
    return static_cast<uint32_t>(call.slots[index]);
}

uint64_t SlotU64(const LC32OpenGLESCall &call, size_t index) {
    return call.slots[index];
}

int32_t SlotI32(const LC32OpenGLESCall &call, size_t index) {
    return static_cast<int32_t>(call.slots[index]);
}

GLfloat SlotFloat(const LC32OpenGLESCall &call, size_t index) {
    uint32_t bits = SlotU32(call, index);
    GLfloat value;
    static_assert(sizeof(value) == sizeof(bits));
    memcpy(&value, &bits, sizeof(value));
    return value;
}

bool CheckedByteCount(size_t count, size_t elementSize, size_t &bytes) {
    if(elementSize && count > kMaximumTransfer / elementSize) return false;
    bytes = count * elementSize;
    return bytes <= kMaximumTransfer;
}

template<typename T>
bool ReadGuestArray(uint32_t guestAddress, size_t count,
                    std::vector<T> &values) {
    size_t byteCount;
    if(!CheckedByteCount(count, sizeof(T), byteCount) ||
       !GuestRangeValid(guestAddress, byteCount) ||
       (byteCount && !guestAddress)) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    values.resize(count);
    if(byteCount && Dynarmic_mem_1read(guestAddress, byteCount,
            reinterpret_cast<char *>(values.data())) != 0) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }
    return true;
}

template<typename T>
bool WriteGuestArray(uint32_t guestAddress, const T *values, size_t count) {
    size_t byteCount;
    if(!CheckedByteCount(count, sizeof(T), byteCount) ||
       !GuestRangeValid(guestAddress, byteCount) ||
       (byteCount && !guestAddress)) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    if(byteCount && Dynarmic_mem_1write(guestAddress, byteCount,
            reinterpret_cast<char *>(const_cast<T *>(values))) != 0) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }
    return true;
}

bool ReadGuestBytes(uint32_t guestAddress, size_t byteCount,
                    std::vector<uint8_t> &bytes) {
    if(byteCount > kMaximumTransfer ||
       !GuestRangeValid(guestAddress, byteCount) ||
       (byteCount && !guestAddress)) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    bytes.resize(byteCount);
    if(byteCount && Dynarmic_mem_1read(guestAddress, byteCount,
            reinterpret_cast<char *>(bytes.data())) != 0) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }
    return true;
}

bool WriteGuestBytes(uint32_t guestAddress, const void *bytes,
                     size_t byteCount) {
    if(byteCount > kMaximumTransfer ||
       !GuestRangeValid(guestAddress, byteCount) ||
       (byteCount && !guestAddress)) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    if(byteCount && Dynarmic_mem_1write(guestAddress, byteCount,
            reinterpret_cast<char *>(const_cast<void *>(bytes))) != 0) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }
    return true;
}

bool ReadGuestCString(uint32_t guestAddress, std::string &string) {
    if(!guestAddress) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }

    string.clear();
    char chunk[256];
    while(string.size() < kMaximumString) {
        if(string.size() > UINT32_MAX - guestAddress) {
            SetBridgeError(GL_INVALID_OPERATION);
            return false;
        }
        const uint32_t currentAddress =
            guestAddress + static_cast<uint32_t>(string.size());
        size_t amount = std::min(sizeof(chunk),
            kMaximumString - string.size());
        size_t pageRemaining = DYN_PAGE_SIZE -
            (currentAddress & DYN_PAGE_MASK);
        amount = std::min(amount, pageRemaining);
        if(Dynarmic_mem_1read(currentAddress, amount, chunk) != 0) {
            SetBridgeError(GL_INVALID_OPERATION);
            return false;
        }
        const char *terminator = static_cast<const char *>(
            memchr(chunk, '\0', amount));
        size_t used = terminator ? static_cast<size_t>(terminator - chunk)
                                 : amount;
        string.append(chunk, used);
        if(terminator) return true;
    }
    SetBridgeError(GL_INVALID_VALUE);
    return false;
}

size_t StateElementCount(GLenum pname) {
    switch(pname) {
        case GL_MODELVIEW_MATRIX:
        case GL_PROJECTION_MATRIX:
        case GL_TEXTURE_MATRIX:
#ifdef GL_MODELVIEW_MATRIX_FLOAT_AS_INT_BITS_OES
        case GL_MODELVIEW_MATRIX_FLOAT_AS_INT_BITS_OES:
        case GL_PROJECTION_MATRIX_FLOAT_AS_INT_BITS_OES:
        case GL_TEXTURE_MATRIX_FLOAT_AS_INT_BITS_OES:
#endif
            return 16;
        case GL_CURRENT_NORMAL:
        case GL_POINT_DISTANCE_ATTENUATION:
            return 3;
        case GL_CURRENT_COLOR:
        case GL_CURRENT_TEXTURE_COORDS:
        case GL_FOG_COLOR:
        case GL_LIGHT_MODEL_AMBIENT:
            return 4;
        case GL_SMOOTH_LINE_WIDTH_RANGE:
        case GL_SMOOTH_POINT_SIZE_RANGE:
            return 2;
        case GL_ALIASED_LINE_WIDTH_RANGE:
        case GL_ALIASED_POINT_SIZE_RANGE:
        case GL_DEPTH_RANGE:
        case GL_MAX_VIEWPORT_DIMS:
            return 2;
        case GL_BLEND_COLOR:
        case GL_COLOR_CLEAR_VALUE:
        case GL_COLOR_WRITEMASK:
        case GL_SCISSOR_BOX:
        case GL_VIEWPORT:
            return 4;
        case GL_COMPRESSED_TEXTURE_FORMATS: {
            GLint count = 0;
            glGetIntegerv(GL_NUM_COMPRESSED_TEXTURE_FORMATS, &count);
            return count >= 0 && count < 4096
                ? static_cast<size_t>(count)
                : std::numeric_limits<size_t>::max();
        }
        case GL_SHADER_BINARY_FORMATS: {
            GLint count = 0;
            glGetIntegerv(GL_NUM_SHADER_BINARY_FORMATS, &count);
            return count >= 0 && count < 4096
                ? static_cast<size_t>(count)
                : std::numeric_limits<size_t>::max();
        }
#ifdef GL_PROGRAM_BINARY_FORMATS
        case GL_PROGRAM_BINARY_FORMATS: {
            GLint count = 0;
            glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, &count);
            return count >= 0 && count < 4096
                ? static_cast<size_t>(count)
                : std::numeric_limits<size_t>::max();
        }
#endif
        case GL_ACTIVE_TEXTURE:
        case GL_ALPHA_TEST:
        case GL_ALPHA_TEST_FUNC:
        case GL_ALPHA_TEST_REF:
        case GL_ALPHA_BITS:
        case GL_ARRAY_BUFFER_BINDING:
        case GL_BLEND:
        case GL_BLEND_DST:
        case GL_BLEND_DST_ALPHA:
        case GL_BLEND_DST_RGB:
        case GL_BLEND_EQUATION_ALPHA:
        case GL_BLEND_EQUATION_RGB:
        case GL_BLEND_SRC_ALPHA:
        case GL_BLEND_SRC_RGB:
        case GL_BLEND_SRC:
        case GL_BLUE_BITS:
        case GL_CLIENT_ACTIVE_TEXTURE:
        case GL_CLIP_PLANE0:
        case GL_CLIP_PLANE1:
        case GL_CLIP_PLANE2:
        case GL_CLIP_PLANE3:
        case GL_CLIP_PLANE4:
        case GL_CLIP_PLANE5:
        case GL_COLOR_ARRAY:
        case GL_COLOR_ARRAY_BUFFER_BINDING:
        case GL_COLOR_ARRAY_SIZE:
        case GL_COLOR_ARRAY_STRIDE:
        case GL_COLOR_ARRAY_TYPE:
        case GL_COLOR_LOGIC_OP:
        case GL_COLOR_MATERIAL:
        case GL_CULL_FACE:
        case GL_CULL_FACE_MODE:
        case GL_CURRENT_PROGRAM:
        case GL_DEPTH_BITS:
        case GL_DEPTH_CLEAR_VALUE:
        case GL_DEPTH_FUNC:
        case GL_DEPTH_TEST:
        case GL_DEPTH_WRITEMASK:
        case GL_DITHER:
        case GL_ELEMENT_ARRAY_BUFFER_BINDING:
        case GL_FRAMEBUFFER_BINDING:
        case GL_FRONT_FACE:
        case GL_FOG:
        case GL_FOG_DENSITY:
        case GL_FOG_END:
        case GL_FOG_HINT:
        case GL_FOG_MODE:
        case GL_FOG_START:
        case GL_GENERATE_MIPMAP_HINT:
        case GL_GREEN_BITS:
        case GL_IMPLEMENTATION_COLOR_READ_FORMAT:
        case GL_IMPLEMENTATION_COLOR_READ_TYPE:
        case GL_LINE_WIDTH:
        case GL_LINE_SMOOTH:
        case GL_LINE_SMOOTH_HINT:
        case GL_LIGHTING:
        case GL_LIGHT_MODEL_TWO_SIDE:
        case GL_LIGHT0:
        case GL_LIGHT1:
        case GL_LIGHT2:
        case GL_LIGHT3:
        case GL_LIGHT4:
        case GL_LIGHT5:
        case GL_LIGHT6:
        case GL_LIGHT7:
        case GL_LOGIC_OP_MODE:
        case GL_MATRIX_MODE:
        case GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS:
        case GL_MAX_CLIP_PLANES:
        case GL_MAX_CUBE_MAP_TEXTURE_SIZE:
        case GL_MAX_FRAGMENT_UNIFORM_VECTORS:
        case GL_MAX_RENDERBUFFER_SIZE:
        case GL_MAX_LIGHTS:
        case GL_MAX_MODELVIEW_STACK_DEPTH:
        case GL_MAX_PROJECTION_STACK_DEPTH:
#ifdef GL_MAX_SAMPLES_APPLE
        case GL_MAX_SAMPLES_APPLE:
#endif
        case GL_MAX_TEXTURE_IMAGE_UNITS:
        case GL_MAX_TEXTURE_SIZE:
        case GL_MAX_TEXTURE_STACK_DEPTH:
        case GL_MAX_TEXTURE_UNITS:
        case GL_MAX_VARYING_VECTORS:
        case GL_MAX_VERTEX_ATTRIBS:
        case GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS:
        case GL_MAX_VERTEX_UNIFORM_VECTORS:
        case GL_NUM_COMPRESSED_TEXTURE_FORMATS:
        case GL_NUM_SHADER_BINARY_FORMATS:
        case GL_MODELVIEW_STACK_DEPTH:
        case GL_PROJECTION_STACK_DEPTH:
        case GL_MULTISAMPLE:
        case GL_NORMAL_ARRAY:
        case GL_NORMAL_ARRAY_BUFFER_BINDING:
        case GL_NORMAL_ARRAY_STRIDE:
        case GL_NORMAL_ARRAY_TYPE:
        case GL_NORMALIZE:
        case GL_PACK_ALIGNMENT:
        case GL_PERSPECTIVE_CORRECTION_HINT:
        case GL_POINT_FADE_THRESHOLD_SIZE:
        case GL_POINT_SIZE:
        case GL_POINT_SIZE_MAX:
        case GL_POINT_SIZE_MIN:
        case GL_POINT_SMOOTH:
        case GL_POINT_SMOOTH_HINT:
        case GL_POLYGON_OFFSET_FACTOR:
        case GL_POLYGON_OFFSET_FILL:
        case GL_POLYGON_OFFSET_UNITS:
        case GL_RED_BITS:
        case GL_RENDERBUFFER_BINDING:
        case GL_RESCALE_NORMAL:
        case GL_SAMPLE_ALPHA_TO_COVERAGE:
        case GL_SAMPLE_ALPHA_TO_ONE:
        case GL_SAMPLE_BUFFERS:
        case GL_SAMPLE_COVERAGE:
        case GL_SAMPLE_COVERAGE_INVERT:
        case GL_SAMPLE_COVERAGE_VALUE:
        case GL_SAMPLES:
        case GL_SCISSOR_TEST:
        case GL_SHADE_MODEL:
        case GL_SHADER_COMPILER:
        case GL_STENCIL_BACK_FAIL:
        case GL_STENCIL_BACK_FUNC:
        case GL_STENCIL_BACK_PASS_DEPTH_FAIL:
        case GL_STENCIL_BACK_PASS_DEPTH_PASS:
        case GL_STENCIL_BACK_REF:
        case GL_STENCIL_BACK_VALUE_MASK:
        case GL_STENCIL_BACK_WRITEMASK:
        case GL_STENCIL_BITS:
        case GL_STENCIL_CLEAR_VALUE:
        case GL_STENCIL_FAIL:
        case GL_STENCIL_FUNC:
        case GL_STENCIL_PASS_DEPTH_FAIL:
        case GL_STENCIL_PASS_DEPTH_PASS:
        case GL_STENCIL_REF:
        case GL_STENCIL_TEST:
        case GL_STENCIL_VALUE_MASK:
        case GL_STENCIL_WRITEMASK:
        case GL_SUBPIXEL_BITS:
        case GL_TEXTURE_BINDING_2D:
        case GL_TEXTURE_BINDING_CUBE_MAP:
        case GL_TEXTURE_2D:
        case GL_TEXTURE_COORD_ARRAY:
        case GL_TEXTURE_COORD_ARRAY_BUFFER_BINDING:
        case GL_TEXTURE_COORD_ARRAY_SIZE:
        case GL_TEXTURE_COORD_ARRAY_STRIDE:
        case GL_TEXTURE_COORD_ARRAY_TYPE:
        case GL_TEXTURE_STACK_DEPTH:
        case GL_UNPACK_ALIGNMENT:
        case GL_VERTEX_ARRAY:
        case GL_VERTEX_ARRAY_BUFFER_BINDING:
        case GL_VERTEX_ARRAY_SIZE:
        case GL_VERTEX_ARRAY_STRIDE:
        case GL_VERTEX_ARRAY_TYPE:
#ifdef GL_POINT_SPRITE_OES
        case GL_POINT_SPRITE_OES:
#endif
#ifdef GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT
        case GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT:
#endif
#ifdef GL_VERTEX_ARRAY_BINDING_OES
        case GL_VERTEX_ARRAY_BINDING_OES:
#endif
#ifdef GL_DRAW_FRAMEBUFFER_BINDING_APPLE
        case GL_READ_FRAMEBUFFER_BINDING_APPLE:
#endif
#ifdef GL_POINT_SIZE_ARRAY_OES
        case GL_POINT_SIZE_ARRAY_OES:
        case GL_POINT_SIZE_ARRAY_BUFFER_BINDING_OES:
        case GL_POINT_SIZE_ARRAY_STRIDE_OES:
        case GL_POINT_SIZE_ARRAY_TYPE_OES:
#endif
#ifdef GL_MATRIX_PALETTE_OES
        case GL_MATRIX_PALETTE_OES:
        case GL_MAX_PALETTE_MATRICES_OES:
        case GL_MAX_VERTEX_UNITS_OES:
        case GL_CURRENT_PALETTE_MATRIX_OES:
        case GL_MATRIX_INDEX_ARRAY_OES:
        case GL_MATRIX_INDEX_ARRAY_SIZE_OES:
        case GL_MATRIX_INDEX_ARRAY_TYPE_OES:
        case GL_MATRIX_INDEX_ARRAY_STRIDE_OES:
        case GL_MATRIX_INDEX_ARRAY_BUFFER_BINDING_OES:
        case GL_WEIGHT_ARRAY_OES:
        case GL_WEIGHT_ARRAY_SIZE_OES:
        case GL_WEIGHT_ARRAY_TYPE_OES:
        case GL_WEIGHT_ARRAY_STRIDE_OES:
        case GL_WEIGHT_ARRAY_BUFFER_BINDING_OES:
#endif
#ifdef GL_CLIP_DISTANCE6_APPLE
        case GL_CLIP_DISTANCE6_APPLE:
        case GL_CLIP_DISTANCE7_APPLE:
#endif
#ifdef GL_PROGRAM_PIPELINE_BINDING_EXT
        case GL_PROGRAM_PIPELINE_BINDING_EXT:
#endif
#ifdef GL_FRAGMENT_SHADER_DISCARDS_SAMPLES_EXT
        case GL_FRAGMENT_SHADER_DISCARDS_SAMPLES_EXT:
#endif
#ifdef GL_PRIMITIVE_RESTART_FIXED_INDEX
        case GL_PRIMITIVE_RESTART_FIXED_INDEX:
        case GL_TRANSFORM_FEEDBACK_BINDING:
        case GL_RASTERIZER_DISCARD:
        case GL_TEXTURE_BINDING_3D:
        case GL_TEXTURE_BINDING_2D_ARRAY:
        case GL_SAMPLER_BINDING:
        case GL_READ_BUFFER:
        case GL_DRAW_BUFFER0:
        case GL_DRAW_BUFFER1:
        case GL_DRAW_BUFFER2:
        case GL_DRAW_BUFFER3:
        case GL_DRAW_BUFFER4:
        case GL_DRAW_BUFFER5:
        case GL_DRAW_BUFFER6:
        case GL_DRAW_BUFFER7:
        case GL_DRAW_BUFFER8:
        case GL_DRAW_BUFFER9:
        case GL_DRAW_BUFFER10:
        case GL_DRAW_BUFFER11:
        case GL_DRAW_BUFFER12:
        case GL_DRAW_BUFFER13:
        case GL_DRAW_BUFFER14:
        case GL_DRAW_BUFFER15:
        case GL_UNPACK_IMAGE_HEIGHT:
        case GL_UNPACK_SKIP_IMAGES:
        case GL_UNPACK_ROW_LENGTH:
        case GL_UNPACK_SKIP_ROWS:
        case GL_UNPACK_SKIP_PIXELS:
        case GL_PACK_ROW_LENGTH:
        case GL_PACK_SKIP_ROWS:
        case GL_PACK_SKIP_PIXELS:
        case GL_PIXEL_PACK_BUFFER_BINDING:
        case GL_PIXEL_UNPACK_BUFFER_BINDING:
        case GL_TRANSFORM_FEEDBACK_BUFFER_BINDING:
        case GL_TRANSFORM_FEEDBACK_PAUSED:
        case GL_TRANSFORM_FEEDBACK_ACTIVE:
        case GL_UNIFORM_BUFFER_BINDING:
        case GL_FRAGMENT_SHADER_DERIVATIVE_HINT:
        case GL_MAX_ELEMENT_INDEX:
        case GL_MAX_3D_TEXTURE_SIZE:
        case GL_MAX_ARRAY_TEXTURE_LAYERS:
        case GL_MAX_TEXTURE_LOD_BIAS:
        case GL_MAX_DRAW_BUFFERS:
        case GL_MAX_COLOR_ATTACHMENTS:
        case GL_MAX_ELEMENTS_INDICES:
        case GL_MAX_ELEMENTS_VERTICES:
        case GL_NUM_PROGRAM_BINARY_FORMATS:
        case GL_MAX_SERVER_WAIT_TIMEOUT:
        case GL_NUM_EXTENSIONS:
        case GL_MAJOR_VERSION:
        case GL_MINOR_VERSION:
        case GL_MAX_VERTEX_UNIFORM_COMPONENTS:
        case GL_MAX_VERTEX_UNIFORM_BLOCKS:
        case GL_MAX_VERTEX_OUTPUT_COMPONENTS:
        case GL_MAX_FRAGMENT_UNIFORM_COMPONENTS:
        case GL_MAX_FRAGMENT_UNIFORM_BLOCKS:
        case GL_MAX_FRAGMENT_INPUT_COMPONENTS:
        case GL_MIN_PROGRAM_TEXEL_OFFSET:
        case GL_MAX_PROGRAM_TEXEL_OFFSET:
        case GL_MAX_UNIFORM_BUFFER_BINDINGS:
        case GL_MAX_UNIFORM_BLOCK_SIZE:
        case GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT:
        case GL_MAX_COMBINED_UNIFORM_BLOCKS:
        case GL_MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS:
        case GL_MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS:
        case GL_MAX_VARYING_COMPONENTS:
        case GL_MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS:
        case GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS:
        case GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS:
        case GL_COPY_READ_BUFFER_BINDING:
        case GL_COPY_WRITE_BUFFER_BINDING:
#endif
            return 1;
        default:
            return std::numeric_limits<size_t>::max();
    }
}

size_t TextureParameterElementCount(GLenum pname) {
#ifdef GL_TEXTURE_CROP_RECT_OES
    if(pname == GL_TEXTURE_CROP_RECT_OES) return 4;
#endif
#ifdef GL_TEXTURE_BORDER_COLOR
    if(pname == GL_TEXTURE_BORDER_COLOR) return 4;
#endif
    switch(pname) {
        case GL_TEXTURE_MAG_FILTER:
        case GL_TEXTURE_MIN_FILTER:
        case GL_TEXTURE_WRAP_S:
        case GL_TEXTURE_WRAP_T:
#ifdef GL_GENERATE_MIPMAP
        case GL_GENERATE_MIPMAP:
#endif
#ifdef GL_TEXTURE_MAX_LEVEL_APPLE
        case GL_TEXTURE_MAX_LEVEL_APPLE:
#endif
#ifdef GL_TEXTURE_MAX_ANISOTROPY_EXT
        case GL_TEXTURE_MAX_ANISOTROPY_EXT:
#endif
#ifdef GL_TEXTURE_COMPARE_MODE_EXT
        case GL_TEXTURE_COMPARE_MODE_EXT:
        case GL_TEXTURE_COMPARE_FUNC_EXT:
#endif
#ifdef GL_TEXTURE_IMMUTABLE_FORMAT_EXT
        case GL_TEXTURE_IMMUTABLE_FORMAT_EXT:
#endif
#ifdef GL_TEXTURE_WRAP_R
        case GL_TEXTURE_WRAP_R:
        case GL_TEXTURE_MIN_LOD:
        case GL_TEXTURE_MAX_LOD:
        case GL_TEXTURE_BASE_LEVEL:
        case GL_TEXTURE_SWIZZLE_R:
        case GL_TEXTURE_SWIZZLE_G:
        case GL_TEXTURE_SWIZZLE_B:
        case GL_TEXTURE_SWIZZLE_A:
        case GL_TEXTURE_IMMUTABLE_LEVELS:
#endif
            return 1;
        default:
            return 0;
    }
}

size_t SamplerParameterElementCount(GLenum pname) {
    switch(pname) {
        case GL_TEXTURE_MAG_FILTER:
        case GL_TEXTURE_MIN_FILTER:
        case GL_TEXTURE_WRAP_S:
        case GL_TEXTURE_WRAP_T:
#ifdef GL_TEXTURE_WRAP_R
        case GL_TEXTURE_WRAP_R:
        case GL_TEXTURE_MIN_LOD:
        case GL_TEXTURE_MAX_LOD:
        case GL_TEXTURE_COMPARE_MODE:
        case GL_TEXTURE_COMPARE_FUNC:
#endif
#ifdef GL_TEXTURE_MAX_ANISOTROPY_EXT
        case GL_TEXTURE_MAX_ANISOTROPY_EXT:
#endif
            return 1;
        default:
            return 0;
    }
}

size_t ClearBufferElementCount(GLenum buffer) {
    switch(buffer) {
        case GL_COLOR: return 4;
        case GL_DEPTH:
        case GL_STENCIL: return 1;
        default: return 0;
    }
}

size_t UniformBlockElementCount(GLuint program, GLuint blockIndex,
                                GLenum pname) {
#ifdef GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES
    if(pname == GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES) {
        GLint count = 0;
        glGetActiveUniformBlockiv(program, blockIndex,
            GL_UNIFORM_BLOCK_ACTIVE_UNIFORMS, &count);
        return count >= 0 && count < 4096
            ? static_cast<size_t>(count)
            : std::numeric_limits<size_t>::max();
    }
#endif
    return 1;
}

size_t TextureEnvironmentElementCount(GLenum pname) {
    switch(pname) {
        case GL_TEXTURE_ENV_COLOR:
            return 4;
        case GL_TEXTURE_ENV_MODE:
        case GL_COMBINE_RGB:
        case GL_COMBINE_ALPHA:
        case GL_RGB_SCALE:
        case GL_ALPHA_SCALE:
        case GL_SRC0_RGB:
        case GL_SRC1_RGB:
        case GL_SRC2_RGB:
        case GL_SRC0_ALPHA:
        case GL_SRC1_ALPHA:
        case GL_SRC2_ALPHA:
        case GL_OPERAND0_RGB:
        case GL_OPERAND1_RGB:
        case GL_OPERAND2_RGB:
        case GL_OPERAND0_ALPHA:
        case GL_OPERAND1_ALPHA:
        case GL_OPERAND2_ALPHA:
#ifdef GL_COORD_REPLACE_OES
        case GL_COORD_REPLACE_OES:
#endif
#ifdef GL_TEXTURE_LOD_BIAS_EXT
        case GL_TEXTURE_LOD_BIAS_EXT:
#endif
            return 1;
        default:
            return 0;
    }
}

size_t FogElementCount(GLenum pname) {
    switch(pname) {
        case GL_FOG_COLOR:
            return 4;
        case GL_FOG_MODE:
        case GL_FOG_DENSITY:
        case GL_FOG_START:
        case GL_FOG_END:
            return 1;
        default:
            return 0;
    }
}

size_t LightElementCount(GLenum pname) {
    switch(pname) {
        case GL_AMBIENT:
        case GL_DIFFUSE:
        case GL_SPECULAR:
        case GL_POSITION:
            return 4;
        case GL_SPOT_DIRECTION:
            return 3;
        case GL_SPOT_EXPONENT:
        case GL_SPOT_CUTOFF:
        case GL_CONSTANT_ATTENUATION:
        case GL_LINEAR_ATTENUATION:
        case GL_QUADRATIC_ATTENUATION:
            return 1;
        default:
            return 0;
    }
}

size_t MaterialElementCount(GLenum pname) {
    switch(pname) {
        case GL_AMBIENT:
        case GL_DIFFUSE:
        case GL_SPECULAR:
        case GL_EMISSION:
        case GL_AMBIENT_AND_DIFFUSE:
            return 4;
        case GL_SHININESS:
            return 1;
        default:
            return 0;
    }
}

size_t LightModelElementCount(GLenum pname) {
    switch(pname) {
        case GL_LIGHT_MODEL_AMBIENT:
            return 4;
        case GL_LIGHT_MODEL_TWO_SIDE:
            return 1;
        default:
            return 0;
    }
}

size_t PointParameterElementCount(GLenum pname) {
    switch(pname) {
        case GL_POINT_DISTANCE_ATTENUATION:
            return 3;
        case GL_POINT_SIZE_MIN:
        case GL_POINT_SIZE_MAX:
        case GL_POINT_FADE_THRESHOLD_SIZE:
            return 1;
        default:
            return 0;
    }
}

bool PixelBytesPerPixel(GLenum format, GLenum type, size_t &bytesPerPixel,
                        GLenum &error);

bool PixelBytesPerPixel(GLenum format, GLenum type, size_t &bytesPerPixel,
                        GLenum &error) {
    error = GL_NO_ERROR;
    size_t components = 0;
    switch(format) {
        case GL_ALPHA:
        case GL_LUMINANCE:
#ifdef GL_RED
        case GL_RED:
        case GL_RED_INTEGER:
#endif
        case GL_DEPTH_COMPONENT:
            components = 1;
            break;
        case GL_LUMINANCE_ALPHA:
#ifdef GL_RG
        case GL_RG:
        case GL_RG_INTEGER:
#endif
            components = 2;
            break;
        case GL_RGB:
#ifdef GL_RGB_INTEGER
        case GL_RGB_INTEGER:
#endif
            components = 3;
            break;
        case GL_RGBA:
#ifdef GL_RGBA_INTEGER
        case GL_RGBA_INTEGER:
#endif
            components = 4;
            break;
#ifdef GL_DEPTH_STENCIL
        case GL_DEPTH_STENCIL:
            components = 2;
            break;
#endif
        default:
            error = GL_INVALID_ENUM;
            return false;
    }

    switch(type) {
        case GL_UNSIGNED_BYTE:
        case GL_BYTE:
            bytesPerPixel = components;
            return true;
        case GL_UNSIGNED_SHORT:
        case GL_SHORT:
#ifdef GL_HALF_FLOAT
        case GL_HALF_FLOAT:
#endif
            return CheckedByteCount(components, 2, bytesPerPixel);
        case GL_UNSIGNED_INT:
        case GL_INT:
        case GL_FLOAT:
            return CheckedByteCount(components, 4, bytesPerPixel);
        case GL_UNSIGNED_SHORT_5_6_5:
            if(format != GL_RGB) break;
            bytesPerPixel = 2;
            return true;
        case GL_UNSIGNED_SHORT_4_4_4_4:
        case GL_UNSIGNED_SHORT_5_5_5_1:
            if(format != GL_RGBA) break;
            bytesPerPixel = 2;
            return true;
#ifdef GL_UNSIGNED_INT_2_10_10_10_REV
        case GL_UNSIGNED_INT_2_10_10_10_REV:
        case GL_UNSIGNED_INT_10F_11F_11F_REV:
        case GL_UNSIGNED_INT_5_9_9_9_REV:
            if(format != GL_RGBA && format != GL_RGBA_INTEGER &&
               format != GL_RGB) break;
            bytesPerPixel = 4;
            return true;
        case GL_UNSIGNED_INT_24_8:
            if(format != GL_DEPTH_STENCIL) break;
            bytesPerPixel = 4;
            return true;
        case GL_FLOAT_32_UNSIGNED_INT_24_8_REV:
            if(format != GL_DEPTH_STENCIL) break;
            bytesPerPixel = 8;
            return true;
#endif
        default:
            error = GL_INVALID_ENUM;
            return false;
    }
    error = GL_INVALID_OPERATION;
    return false;
}

bool PixelVolumeSize(GLsizei width, GLsizei height, GLsizei depth,
                     GLenum format, GLenum type, GLint alignment,
                     GLint rowLength, GLint imageHeight, GLint skipPixels,
                     GLint skipRows, GLint skipImages, size_t &byteCount,
                     GLenum &error, size_t *rowBytesOutput = nullptr,
                     size_t *rowStrideOutput = nullptr,
                     size_t *dataOffsetOutput = nullptr) {
    error = GL_NO_ERROR;
    byteCount = 0;
    if(rowBytesOutput) *rowBytesOutput = 0;
    if(rowStrideOutput) *rowStrideOutput = 0;
    if(dataOffsetOutput) *dataOffsetOutput = 0;
    if(width < 0 || height < 0 || depth < 0 || rowLength < 0 ||
       imageHeight < 0 || skipPixels < 0 || skipRows < 0 || skipImages < 0) {
        error = GL_INVALID_VALUE;
        return false;
    }
    if(alignment != 1 && alignment != 2 && alignment != 4 && alignment != 8) {
        error = GL_INVALID_OPERATION;
        return false;
    }
    size_t bytesPerPixel = 0;
    if(!PixelBytesPerPixel(format, type, bytesPerPixel, error)) return false;
    size_t rowBytes;
    if(!CheckedByteCount(static_cast<size_t>(width), bytesPerPixel,
                         rowBytes)) {
        error = GL_INVALID_VALUE;
        return false;
    }
    if(rowBytesOutput) *rowBytesOutput = rowBytes;
    if(!width || !height || !depth) {
        return true;
    }

    const size_t rowPixels = rowLength ? static_cast<size_t>(rowLength)
                                       : static_cast<size_t>(width);
    const size_t imageRows = imageHeight ? static_cast<size_t>(imageHeight)
                                         : static_cast<size_t>(height);
    size_t rawRow;
    if(!CheckedByteCount(rowPixels, bytesPerPixel, rawRow) ||
       rawRow > kMaximumTransfer - static_cast<size_t>(alignment - 1)) {
        error = GL_INVALID_VALUE;
        return false;
    }
    const size_t rowStride =
        (rawRow + static_cast<size_t>(alignment - 1)) &
        ~static_cast<size_t>(alignment - 1);
    if(rowStrideOutput) *rowStrideOutput = rowStride;
    size_t imageStride;
    if(!CheckedByteCount(imageRows, rowStride, imageStride)) {
        error = GL_INVALID_VALUE;
        return false;
    }

    const auto addProduct = [&](size_t count, size_t stride,
                                size_t &total) -> bool {
        size_t amount;
        if(!CheckedByteCount(count, stride, amount) ||
           amount > kMaximumTransfer - total) return false;
        total += amount;
        return true;
    };
    size_t dataOffset = 0;
    if(!addProduct(static_cast<size_t>(skipImages), imageStride,
                   dataOffset) ||
       !addProduct(static_cast<size_t>(skipRows), rowStride, dataOffset) ||
       !addProduct(static_cast<size_t>(skipPixels), bytesPerPixel,
                   dataOffset)) {
        error = GL_INVALID_VALUE;
        return false;
    }
    if(dataOffsetOutput) *dataOffsetOutput = dataOffset;
    size_t total = dataOffset;
    if(
       !addProduct(static_cast<size_t>(depth - 1), imageStride, total) ||
       !addProduct(static_cast<size_t>(height - 1), rowStride, total) ||
       rowBytes > kMaximumTransfer - total) {
        error = GL_INVALID_VALUE;
        return false;
    }
    total += rowBytes;
    byteCount = total;
    return true;
}

size_t IndexElementSize(GLenum type) {
    switch(type) {
        case GL_UNSIGNED_BYTE: return sizeof(GLubyte);
        case GL_UNSIGNED_SHORT: return sizeof(GLushort);
#ifdef GL_UNSIGNED_INT
        case GL_UNSIGNED_INT: return sizeof(GLuint);
#endif
        default: return 0;
    }
}

enum class ClientArrayKind : uint8_t {
    VertexAttrib,
    Vertex,
    Color,
    TexCoord,
    Normal,
    PointSize,
    MatrixIndex,
    Weight,
};

struct ClientArrayDescriptor {
    ClientArrayKind kind = ClientArrayKind::VertexAttrib;
    GLuint index = 0;
    GLint size = 0;
    GLenum type = 0;
    GLboolean normalized = GL_FALSE;
    GLsizei stride = 0;
    uint32_t guestPointer = 0;
    GLuint divisor = 0;
    bool integer = false;
    bool valid = false;
};

struct VertexArrayClientState {
    std::unordered_map<GLuint, ClientArrayDescriptor> vertexAttribs;
    std::unordered_set<GLuint> enabledVertexAttribs;
    std::unordered_map<GLuint, GLuint> vertexAttribDivisors;
    ClientArrayDescriptor vertex;
    ClientArrayDescriptor color;
    std::unordered_map<GLenum, ClientArrayDescriptor> texCoords;
    std::unordered_set<GLenum> enabledTexCoords;
    ClientArrayDescriptor normal;
    ClientArrayDescriptor pointSize;
    ClientArrayDescriptor matrixIndex;
    ClientArrayDescriptor weight;
    bool vertexEnabled = false;
    bool colorEnabled = false;
    bool normalEnabled = false;
    bool pointSizeEnabled = false;
    bool matrixIndexEnabled = false;
    bool weightEnabled = false;
};

struct ClientArrayContextState {
    std::unordered_map<GLuint, VertexArrayClientState> vertexArrays;
    GLuint currentVertexArray = 0;
    GLenum clientActiveTexture = GL_TEXTURE0;
};

std::mutex clientArrayStateMutex;
std::unordered_map<uintptr_t, ClientArrayContextState> clientArrayStates;
static const void *clientArrayStateLifetimeKey =
    &clientArrayStateLifetimeKey;
static const void *auxiliarySharegroupStateLifetimeKey =
    &auxiliarySharegroupStateLifetimeKey;
std::mutex auxiliarySharegroupLifetimeMutex;

void RemoveClientArrayState(uintptr_t contextKey) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    clientArrayStates.erase(contextKey);
}

uintptr_t CurrentGLContextKey() {
    EAGLContext *context = EAGLContext.currentContext;
    const uintptr_t contextKey = reinterpret_cast<uintptr_t>(
        (__bridge void *)context);
    if(context && !objc_getAssociatedObject(
            context, clientArrayStateLifetimeKey)) {
        LC32EAGLContextStateLifetime *lifetime =
            [LC32EAGLContextStateLifetime new];
        lifetime->_contextKey = contextKey;
        objc_setAssociatedObject(context, clientArrayStateLifetimeKey,
            lifetime, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [lifetime release];
    }
    return contextKey;
}

bool CurrentContextIsES3() {
    EAGLContext *context = EAGLContext.currentContext;
    return context.API == kEAGLRenderingAPIOpenGLES3;
}

uintptr_t CurrentGLSharegroupKey() {
    EAGLContext *context = EAGLContext.currentContext;
    EAGLSharegroup *sharegroup = context.sharegroup;
    const uintptr_t sharegroupKey = reinterpret_cast<uintptr_t>(
        (__bridge void *)sharegroup);
    if(sharegroup) {
        std::lock_guard<std::mutex> lock(auxiliarySharegroupLifetimeMutex);
        if(!objc_getAssociatedObject(
                sharegroup, auxiliarySharegroupStateLifetimeKey)) {
            LC32EAGLSharegroupStateLifetime *lifetime =
                [LC32EAGLSharegroupStateLifetime new];
            lifetime->_sharegroupKey = sharegroupKey;
            objc_setAssociatedObject(sharegroup,
                auxiliarySharegroupStateLifetimeKey, lifetime,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [lifetime release];
        }
    }
    return sharegroupKey;
}

struct SyncSlot {
    GLsync sync = nullptr;
    uintptr_t sharegroupKey = 0;
    uint16_t generation = 0;
};

std::mutex syncStateMutex;
std::vector<SyncSlot> syncSlots;

uint32_t PublishSync(GLsync sync) {
    if(!sync) return 0;
    const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
    std::lock_guard<std::mutex> lock(syncStateMutex);
    size_t index = 0;
    for(; index < syncSlots.size(); ++index) {
        if(!syncSlots[index].sync) break;
    }
    if(index == UINT16_MAX) return 0;
    if(index == syncSlots.size()) {
        try {
            syncSlots.push_back({});
        } catch(const std::bad_alloc &) {
            return 0;
        }
    }
    SyncSlot &slot = syncSlots[index];
    slot.generation = static_cast<uint16_t>(slot.generation + 1);
    if(!slot.generation) slot.generation = 1;
    slot.sync = sync;
    slot.sharegroupKey = sharegroupKey;
    return (static_cast<uint32_t>(slot.generation) << 16) |
        static_cast<uint32_t>(index + 1);
}

GLsync LookupSync(uint32_t token) {
    const uint32_t encodedIndex = token & UINT16_MAX;
    const uint16_t generation = static_cast<uint16_t>(token >> 16);
    if(!encodedIndex || !generation) return nullptr;
    const size_t index = encodedIndex - 1;
    const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
    std::lock_guard<std::mutex> lock(syncStateMutex);
    if(index >= syncSlots.size()) return nullptr;
    const SyncSlot &slot = syncSlots[index];
    return slot.sync && slot.generation == generation &&
        slot.sharegroupKey == sharegroupKey ? slot.sync : nullptr;
}

GLsync TakeSync(uint32_t token) {
    const uint32_t encodedIndex = token & UINT16_MAX;
    const uint16_t generation = static_cast<uint16_t>(token >> 16);
    if(!encodedIndex || !generation) return nullptr;
    const size_t index = encodedIndex - 1;
    const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
    std::lock_guard<std::mutex> lock(syncStateMutex);
    if(index >= syncSlots.size()) return nullptr;
    SyncSlot &slot = syncSlots[index];
    if(!slot.sync || slot.generation != generation ||
       slot.sharegroupKey != sharegroupKey) return nullptr;
    GLsync sync = slot.sync;
    slot.sync = nullptr;
    slot.sharegroupKey = 0;
    return sync;
}

bool NativeSyncObjectName(uint32_t token, GLuint &object) {
    GLsync sync = LookupSync(token);
    if(!sync) return false;
    object = static_cast<GLuint>(reinterpret_cast<uintptr_t>(sync));
    return true;
}

struct MappedBufferEntry {
    uintptr_t sharegroupKey = 0;
    GLenum target = 0;
    GLuint buffer = 0;
    GLvoid *nativePointer = nullptr;
    uint32_t guestPointer = 0;
    size_t length = 0;
    bool writable = false;
    bool flushExplicit = false;
};

std::mutex mappedBufferMutex;
std::vector<MappedBufferEntry> mappedBuffers;
std::mutex deferredGuestFreeMutex;
std::vector<uint32_t> deferredGuestFrees;

void ReleaseGuestMappingPointer(uint32_t guestPointer) {
    if(!guestPointer) return;
    if(Dynarmic_guest_thread_is_registered()) {
        guest_free(guestPointer);
        return;
    }
    try {
        std::lock_guard<std::mutex> lock(deferredGuestFreeMutex);
        deferredGuestFrees.push_back(guestPointer);
    } catch(const std::bad_alloc &) {
        // The guest allocation cannot safely be released from this thread.
    }
}

void DrainDeferredGuestMappingFrees() {
    if(!Dynarmic_guest_thread_is_registered()) return;
    for(;;) {
        uint32_t guestPointer = 0;
        {
            std::lock_guard<std::mutex> lock(deferredGuestFreeMutex);
            if(deferredGuestFrees.empty()) return;
            guestPointer = deferredGuestFrees.back();
            deferredGuestFrees.pop_back();
        }
        guest_free(guestPointer);
    }
}

GLenum BufferBindingPname(GLenum target) {
    switch(target) {
        case GL_ARRAY_BUFFER: return GL_ARRAY_BUFFER_BINDING;
        case GL_ELEMENT_ARRAY_BUFFER: return GL_ELEMENT_ARRAY_BUFFER_BINDING;
#ifdef GL_COPY_READ_BUFFER
        case GL_COPY_READ_BUFFER: return GL_COPY_READ_BUFFER_BINDING;
        case GL_COPY_WRITE_BUFFER: return GL_COPY_WRITE_BUFFER_BINDING;
        case GL_PIXEL_PACK_BUFFER: return GL_PIXEL_PACK_BUFFER_BINDING;
        case GL_PIXEL_UNPACK_BUFFER: return GL_PIXEL_UNPACK_BUFFER_BINDING;
        case GL_TRANSFORM_FEEDBACK_BUFFER:
            return GL_TRANSFORM_FEEDBACK_BUFFER_BINDING;
        case GL_UNIFORM_BUFFER: return GL_UNIFORM_BUFFER_BINDING;
#endif
        default: return 0;
    }
}

bool BoundBuffer(GLenum target, GLuint &buffer) {
    const GLenum bindingPname = BufferBindingPname(target);
    if(!bindingPname) return false;
    GLint value = 0;
    glGetIntegerv(bindingPname, &value);
    buffer = static_cast<GLuint>(value);
    return buffer != 0;
}

std::vector<MappedBufferEntry>::iterator FindMappedBufferLocked(
        uintptr_t sharegroupKey, GLenum target, GLuint buffer) {
    (void)target;
    return std::find_if(mappedBuffers.begin(), mappedBuffers.end(),
        [=](const MappedBufferEntry &entry) {
            return entry.sharegroupKey == sharegroupKey &&
                entry.buffer == buffer;
        });
}

uint32_t RetireMappedBufferLocked(uintptr_t sharegroupKey, GLuint buffer) {
    auto mapped = FindMappedBufferLocked(sharegroupKey, 0, buffer);
    if(mapped == mappedBuffers.end()) return 0;
    const uint32_t guestPointer = mapped->guestPointer;
    mappedBuffers.erase(mapped);
    return guestPointer;
}

void RemoveAuxiliarySharegroupState(uintptr_t sharegroupKey) {
    for(;;) {
        uint32_t guestPointer = 0;
        {
            std::lock_guard<std::mutex> lock(mappedBufferMutex);
            auto mapped = std::find_if(mappedBuffers.begin(),
                mappedBuffers.end(), [=](const MappedBufferEntry &entry) {
                    return entry.sharegroupKey == sharegroupKey;
                });
            if(mapped == mappedBuffers.end()) break;
            guestPointer = mapped->guestPointer;
            mappedBuffers.erase(mapped);
        }
        ReleaseGuestMappingPointer(guestPointer);
    }
    {
        std::lock_guard<std::mutex> lock(syncStateMutex);
        for(SyncSlot &slot : syncSlots) {
            if(slot.sharegroupKey == sharegroupKey) {
                slot.sync = nullptr;
                slot.sharegroupKey = 0;
            }
        }
    }
}

VertexArrayClientState &CurrentVertexArrayState(
        ClientArrayContextState &context) {
    return context.vertexArrays[context.currentVertexArray];
}

void SetCurrentVertexArray(GLuint vertexArray) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    clientArrayStates[CurrentGLContextKey()].currentVertexArray = vertexArray;
}

void ForgetVertexArrayStates(GLsizei count, const GLuint *vertexArrays) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto context = clientArrayStates.find(CurrentGLContextKey());
    if(context == clientArrayStates.end()) return;
    for(GLsizei i = 0; i < count; ++i) {
        const GLuint vertexArray = vertexArrays[i];
        if(!vertexArray) continue;
        context->second.vertexArrays.erase(vertexArray);
        if(context->second.currentVertexArray == vertexArray)
            context->second.currentVertexArray = 0;
    }
}

void SetVertexAttribArrayEnabled(GLuint index, bool enabled) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto &context = clientArrayStates[CurrentGLContextKey()];
    auto &state = CurrentVertexArrayState(context);
    if(enabled) state.enabledVertexAttribs.insert(index);
    else state.enabledVertexAttribs.erase(index);
}

void SetVertexAttribDivisor(GLuint index, GLuint divisor) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto &context = clientArrayStates[CurrentGLContextKey()];
    auto &state = CurrentVertexArrayState(context);
    if(divisor) state.vertexAttribDivisors[index] = divisor;
    else state.vertexAttribDivisors.erase(index);
    auto descriptor = state.vertexAttribs.find(index);
    if(descriptor != state.vertexAttribs.end())
        descriptor->second.divisor = divisor;
}

void SetClientStateEnabled(GLenum array, bool enabled) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto &context = clientArrayStates[CurrentGLContextKey()];
    auto &state = CurrentVertexArrayState(context);
    switch(array) {
        case GL_VERTEX_ARRAY: state.vertexEnabled = enabled; break;
        case GL_COLOR_ARRAY: state.colorEnabled = enabled; break;
        case GL_TEXTURE_COORD_ARRAY:
            if(enabled) {
                state.enabledTexCoords.insert(context.clientActiveTexture);
            } else {
                state.enabledTexCoords.erase(context.clientActiveTexture);
            }
            break;
        case GL_NORMAL_ARRAY: state.normalEnabled = enabled; break;
#ifdef GL_POINT_SIZE_ARRAY_OES
        case GL_POINT_SIZE_ARRAY_OES: state.pointSizeEnabled = enabled; break;
#endif
#ifdef GL_MATRIX_INDEX_ARRAY_OES
        case GL_MATRIX_INDEX_ARRAY_OES:
            state.matrixIndexEnabled = enabled;
            break;
        case GL_WEIGHT_ARRAY_OES: state.weightEnabled = enabled; break;
#endif
        default: break;
    }
}

void SetClientActiveTexture(GLenum texture) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    clientArrayStates[CurrentGLContextKey()].clientActiveTexture = texture;
}

void RememberVertexAttribPointer(const ClientArrayDescriptor *descriptor,
                                 GLuint index) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto &context = clientArrayStates[CurrentGLContextKey()];
    auto &attributes = CurrentVertexArrayState(context).vertexAttribs;
    if(descriptor) {
        ClientArrayDescriptor saved = *descriptor;
        auto divisor = CurrentVertexArrayState(context).vertexAttribDivisors.find(
            index);
        if(divisor != CurrentVertexArrayState(context).vertexAttribDivisors.end())
            saved.divisor = divisor->second;
        attributes[index] = saved;
    }
    else attributes.erase(index);
}

void RememberClientPointer(const ClientArrayDescriptor *descriptor,
                           ClientArrayKind kind) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto &context = clientArrayStates[CurrentGLContextKey()];
    auto &state = CurrentVertexArrayState(context);
    if(kind == ClientArrayKind::TexCoord) {
        const GLenum texture = context.clientActiveTexture;
        if(descriptor) {
            ClientArrayDescriptor saved = *descriptor;
            saved.index = texture;
            state.texCoords[texture] = saved;
        } else {
            state.texCoords.erase(texture);
        }
        return;
    }
    ClientArrayDescriptor *destination = nullptr;
    switch(kind) {
        case ClientArrayKind::Vertex: destination = &state.vertex; break;
        case ClientArrayKind::Color: destination = &state.color; break;
        case ClientArrayKind::TexCoord: return;
        case ClientArrayKind::Normal: destination = &state.normal; break;
        case ClientArrayKind::PointSize: destination = &state.pointSize; break;
        case ClientArrayKind::MatrixIndex:
            destination = &state.matrixIndex;
            break;
        case ClientArrayKind::Weight: destination = &state.weight; break;
        case ClientArrayKind::VertexAttrib: return;
    }
    *destination = descriptor ? *descriptor : ClientArrayDescriptor{};
}

bool GuestClientPointer(GLenum pname, uint32_t &guestPointer) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto context = clientArrayStates.find(CurrentGLContextKey());
    if(context == clientArrayStates.end()) return false;
    auto vertexArray = context->second.vertexArrays.find(
        context->second.currentVertexArray);
    if(vertexArray == context->second.vertexArrays.end()) return false;

    const auto &state = vertexArray->second;
    const ClientArrayDescriptor *descriptor = nullptr;
    switch(pname) {
        case GL_VERTEX_ARRAY_POINTER: descriptor = &state.vertex; break;
        case GL_NORMAL_ARRAY_POINTER: descriptor = &state.normal; break;
        case GL_COLOR_ARRAY_POINTER: descriptor = &state.color; break;
        case GL_TEXTURE_COORD_ARRAY_POINTER: {
            auto value = state.texCoords.find(context->second.clientActiveTexture);
            if(value != state.texCoords.end()) descriptor = &value->second;
            break;
        }
#ifdef GL_POINT_SIZE_ARRAY_POINTER_OES
        case GL_POINT_SIZE_ARRAY_POINTER_OES:
            descriptor = &state.pointSize;
            break;
#endif
#ifdef GL_MATRIX_INDEX_ARRAY_POINTER_OES
        case GL_MATRIX_INDEX_ARRAY_POINTER_OES:
            descriptor = &state.matrixIndex;
            break;
        case GL_WEIGHT_ARRAY_POINTER_OES: descriptor = &state.weight; break;
#endif
        default: break;
    }
    if(!descriptor || !descriptor->valid) return false;
    guestPointer = descriptor->guestPointer;
    return true;
}

GLenum ClientPointerBufferBinding(GLenum pname) {
    switch(pname) {
        case GL_VERTEX_ARRAY_POINTER: return GL_VERTEX_ARRAY_BUFFER_BINDING;
        case GL_NORMAL_ARRAY_POINTER: return GL_NORMAL_ARRAY_BUFFER_BINDING;
        case GL_COLOR_ARRAY_POINTER: return GL_COLOR_ARRAY_BUFFER_BINDING;
        case GL_TEXTURE_COORD_ARRAY_POINTER:
            return GL_TEXTURE_COORD_ARRAY_BUFFER_BINDING;
#ifdef GL_POINT_SIZE_ARRAY_POINTER_OES
        case GL_POINT_SIZE_ARRAY_POINTER_OES:
            return GL_POINT_SIZE_ARRAY_BUFFER_BINDING_OES;
#endif
#ifdef GL_MATRIX_INDEX_ARRAY_POINTER_OES
        case GL_MATRIX_INDEX_ARRAY_POINTER_OES:
            return GL_MATRIX_INDEX_ARRAY_BUFFER_BINDING_OES;
        case GL_WEIGHT_ARRAY_POINTER_OES:
            return GL_WEIGHT_ARRAY_BUFFER_BINDING_OES;
#endif
        default: return 0;
    }
}

bool GuestVertexAttribPointer(GLuint index, uint32_t &guestPointer) {
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto context = clientArrayStates.find(CurrentGLContextKey());
    if(context == clientArrayStates.end()) return false;
    auto vertexArray = context->second.vertexArrays.find(
        context->second.currentVertexArray);
    if(vertexArray == context->second.vertexArrays.end()) return false;
    auto attribute = vertexArray->second.vertexAttribs.find(index);
    if(attribute == vertexArray->second.vertexAttribs.end()) return false;
    guestPointer = attribute->second.guestPointer;
    return true;
}

std::vector<ClientArrayDescriptor> EnabledClientArrays() {
    std::vector<ClientArrayDescriptor> descriptors;
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto context = clientArrayStates.find(CurrentGLContextKey());
    if(context == clientArrayStates.end()) return descriptors;
    auto vertexArray = context->second.vertexArrays.find(
        context->second.currentVertexArray);
    if(vertexArray == context->second.vertexArrays.end()) return descriptors;

    const auto &state = vertexArray->second;
    descriptors.reserve(state.enabledVertexAttribs.size() +
        state.enabledTexCoords.size() + 6);
    for(GLuint index : state.enabledVertexAttribs) {
        auto descriptor = state.vertexAttribs.find(index);
        if(descriptor != state.vertexAttribs.end() &&
           descriptor->second.valid) {
            descriptors.push_back(descriptor->second);
        }
    }
    if(state.vertexEnabled && state.vertex.valid)
        descriptors.push_back(state.vertex);
    if(state.colorEnabled && state.color.valid)
        descriptors.push_back(state.color);
    for(GLenum texture : state.enabledTexCoords) {
        auto descriptor = state.texCoords.find(texture);
        if(descriptor != state.texCoords.end() &&
                descriptor->second.valid) {
            descriptors.push_back(descriptor->second);
        }
    }
    if(state.normalEnabled && state.normal.valid)
        descriptors.push_back(state.normal);
    if(state.pointSizeEnabled && state.pointSize.valid)
        descriptors.push_back(state.pointSize);
    if(state.matrixIndexEnabled && state.matrixIndex.valid)
        descriptors.push_back(state.matrixIndex);
    if(state.weightEnabled && state.weight.valid)
        descriptors.push_back(state.weight);
    return descriptors;
}

size_t ClientArrayScalarSize(GLenum type) {
    switch(type) {
        case GL_BYTE:
        case GL_UNSIGNED_BYTE: return 1;
        case GL_SHORT:
        case GL_UNSIGNED_SHORT: return 2;
        case GL_INT:
        case GL_UNSIGNED_INT:
        case GL_FIXED:
        case GL_FLOAT: return 4;
#ifdef GL_HALF_FLOAT_OES
        case GL_HALF_FLOAT_OES: return 2;
#endif
        default: return 0;
    }
}

bool VertexAttribIndexValid(GLuint index) {
    GLint maximum = 0;
    glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &maximum);
    return maximum > 0 && index < static_cast<GLuint>(maximum);
}

bool ClientMemoryPointerAllowed(GLint arrayBufferBinding,
                                uint32_t guestPointer) {
    if(arrayBufferBinding || !guestPointer) return true;
    const uintptr_t contextKey = CurrentGLContextKey();
    std::lock_guard<std::mutex> lock(clientArrayStateMutex);
    auto context = clientArrayStates.find(contextKey);
    return context == clientArrayStates.end() ||
        context->second.currentVertexArray == 0;
}

bool VertexAttribDescriptorValid(GLuint index, GLint size, GLenum type,
                                 GLsizei stride, bool integer) {
    if(!VertexAttribIndexValid(index) || size < 1 || size > 4 || stride < 0)
        return false;
    if(integer) {
        return type == GL_BYTE || type == GL_UNSIGNED_BYTE ||
            type == GL_SHORT || type == GL_UNSIGNED_SHORT ||
            type == GL_INT || type == GL_UNSIGNED_INT;
    }
#ifdef GL_INT_2_10_10_10_REV
    if(type == GL_INT_2_10_10_10_REV ||
       type == GL_UNSIGNED_INT_2_10_10_10_REV) return size == 4;
#endif
    return type == GL_BYTE || type == GL_UNSIGNED_BYTE ||
        type == GL_SHORT || type == GL_UNSIGNED_SHORT ||
        type == GL_INT || type == GL_UNSIGNED_INT ||
        type == GL_FIXED || type == GL_FLOAT
#ifdef GL_HALF_FLOAT
        || type == GL_HALF_FLOAT
#endif
        ;
}

bool FixedClientDescriptorValid(ClientArrayKind kind, GLint size,
                                GLenum type, GLsizei stride) {
    if(stride < 0) return false;
    switch(kind) {
        case ClientArrayKind::Vertex:
        case ClientArrayKind::TexCoord:
            return size >= 2 && size <= 4 &&
                (type == GL_BYTE || type == GL_SHORT || type == GL_FIXED ||
                 type == GL_FLOAT);
        case ClientArrayKind::Color:
            return size == 4 &&
                (type == GL_UNSIGNED_BYTE || type == GL_FIXED ||
                 type == GL_FLOAT);
        case ClientArrayKind::Normal:
            return size == 3 &&
                (type == GL_BYTE || type == GL_SHORT || type == GL_FIXED ||
                 type == GL_FLOAT);
        case ClientArrayKind::PointSize:
            return size == 1 && (type == GL_FIXED || type == GL_FLOAT);
        case ClientArrayKind::MatrixIndex: {
            GLint maximum = 0;
            glGetIntegerv(GL_MAX_VERTEX_UNITS_OES, &maximum);
            return size >= 1 && size <= maximum && type == GL_UNSIGNED_BYTE;
        }
        case ClientArrayKind::Weight: {
            GLint maximum = 0;
            glGetIntegerv(GL_MAX_VERTEX_UNITS_OES, &maximum);
            return size >= 1 && size <= maximum &&
                (type == GL_FIXED || type == GL_FLOAT);
        }
        case ClientArrayKind::VertexAttrib:
            return false;
    }
}

bool ClientArrayByteCount(const ClientArrayDescriptor &descriptor,
                          size_t maximumIndex, size_t &byteCount) {
    size_t elementSize = 0;
#ifdef GL_INT_2_10_10_10_REV
    if(descriptor.type == GL_INT_2_10_10_10_REV ||
       descriptor.type == GL_UNSIGNED_INT_2_10_10_10_REV) {
        if(descriptor.size != 4) {
            SetBridgeError(GL_INVALID_VALUE);
            return false;
        }
        elementSize = 4;
    }
#endif
    const size_t scalarSize = ClientArrayScalarSize(descriptor.type);
    const bool widePaletteArray =
        descriptor.kind == ClientArrayKind::MatrixIndex ||
        descriptor.kind == ClientArrayKind::Weight;
    if((!scalarSize && !elementSize) || descriptor.size <= 0 ||
       (!widePaletteArray && descriptor.size > 4) || descriptor.stride < 0) {
        SetBridgeError(!scalarSize ? GL_INVALID_ENUM : GL_INVALID_VALUE);
        return false;
    }

    if(!elementSize &&
       !CheckedByteCount(static_cast<size_t>(descriptor.size), scalarSize,
                         elementSize)) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    const size_t stride = descriptor.stride
        ? static_cast<size_t>(descriptor.stride) : elementSize;
    if(maximumIndex > (kMaximumTransfer - elementSize) / stride) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    byteCount = maximumIndex * stride + elementSize;
    return true;
}

struct StagedClientArray {
    ClientArrayDescriptor descriptor;
    std::vector<uint8_t> bytes;
};

bool StageClientArrays(size_t maximumIndex, size_t instanceCount,
                       std::vector<StagedClientArray> &staged) {
    std::vector<ClientArrayDescriptor> descriptors = EnabledClientArrays();
    staged.clear();
    staged.reserve(descriptors.size());
    for(const ClientArrayDescriptor &descriptor : descriptors) {
        const size_t descriptorMaximum =
            descriptor.kind == ClientArrayKind::VertexAttrib &&
                    descriptor.divisor
                ? (instanceCount ? (instanceCount - 1) / descriptor.divisor : 0)
                : maximumIndex;
        size_t byteCount;
        if(!ClientArrayByteCount(descriptor, descriptorMaximum, byteCount))
            return false;
        staged.push_back({descriptor, {}});
        if(!ReadGuestBytes(descriptor.guestPointer, byteCount,
                           staged.back().bytes)) {
            return false;
        }
    }

    if(staged.empty()) return true;

    GLint savedBinding = 0;
    GLint savedClientActiveTexture = GL_TEXTURE0;
    bool changedClientActiveTexture = false;
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &savedBinding);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    for(const StagedClientArray &array : staged) {
        const ClientArrayDescriptor &descriptor = array.descriptor;
        const GLvoid *pointer = array.bytes.data();
        switch(descriptor.kind) {
            case ClientArrayKind::VertexAttrib:
                if(descriptor.integer) {
                    glVertexAttribIPointer(descriptor.index, descriptor.size,
                        descriptor.type, descriptor.stride, pointer);
                } else {
                    glVertexAttribPointer(descriptor.index, descriptor.size,
                        descriptor.type, descriptor.normalized,
                        descriptor.stride, pointer);
                }
                break;
            case ClientArrayKind::Vertex:
                glVertexPointer(descriptor.size, descriptor.type,
                    descriptor.stride, pointer);
                break;
            case ClientArrayKind::Color:
                glColorPointer(descriptor.size, descriptor.type,
                    descriptor.stride, pointer);
                break;
            case ClientArrayKind::TexCoord:
                if(!changedClientActiveTexture) {
                    glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE,
                                  &savedClientActiveTexture);
                    changedClientActiveTexture = true;
                }
                glClientActiveTexture(descriptor.index);
                glTexCoordPointer(descriptor.size, descriptor.type,
                    descriptor.stride, pointer);
                break;
            case ClientArrayKind::Normal:
                glNormalPointer(descriptor.type, descriptor.stride, pointer);
                break;
            case ClientArrayKind::PointSize:
                glPointSizePointerOES(descriptor.type, descriptor.stride,
                    pointer);
                break;
            case ClientArrayKind::MatrixIndex:
                glMatrixIndexPointerOES(descriptor.size, descriptor.type,
                    descriptor.stride, pointer);
                break;
            case ClientArrayKind::Weight:
                glWeightPointerOES(descriptor.size, descriptor.type,
                    descriptor.stride, pointer);
                break;
        }
    }
    if(changedClientActiveTexture)
        glClientActiveTexture(savedClientActiveTexture);
    glBindBuffer(GL_ARRAY_BUFFER, static_cast<GLuint>(savedBinding));
    return true;
}

bool StageClientArrays(size_t maximumIndex,
                       std::vector<StagedClientArray> &staged) {
    return StageClientArrays(maximumIndex, 1, staged);
}

bool MaximumIndex(GLenum type, const std::vector<uint8_t> &indices,
                  size_t &maximumIndex, bool &hasIndex) {
    maximumIndex = 0;
    hasIndex = false;
    const size_t elementSize = IndexElementSize(type);
    if(!elementSize || indices.size() % elementSize) return false;
    bool restartEnabled = false;
#ifdef GL_PRIMITIVE_RESTART_FIXED_INDEX
    restartEnabled = CurrentContextIsES3() &&
        glIsEnabled(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#endif
    const uint32_t restartIndex = elementSize == 1 ? UINT8_MAX :
        elementSize == 2 ? UINT16_MAX : UINT32_MAX;
    for(size_t offset = 0; offset < indices.size(); offset += elementSize) {
        uint32_t index = 0;
        memcpy(&index, indices.data() + offset, elementSize);
        if(restartEnabled && index == restartIndex) continue;
        hasIndex = true;
        maximumIndex = std::max(maximumIndex, static_cast<size_t>(index));
    }
    return true;
}

bool ReadCount(int32_t signedCount, size_t multiplier, size_t &count) {
    if(signedCount < 0 || multiplier == 0 ||
       static_cast<size_t>(signedCount) >
           kMaximumTransfer / multiplier) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    count = static_cast<size_t>(signedCount) * multiplier;
    return true;
}

template<typename T, typename Function>
uint32_t DispatchInputArray(const LC32OpenGLESCall &call,
                            size_t multiplier, Function function) {
    if(!RequireSlots(call, 3)) return 0;
    size_t count;
    if(!ReadCount(SlotI32(call, 1), multiplier, count)) return 0;
    std::vector<T> values;
    if(!ReadGuestArray(SlotU32(call, 2), count, values)) return 0;
    function(SlotI32(call, 0), SlotI32(call, 1), values.data());
    return 0;
}

template<typename T, typename Function>
uint32_t DispatchStateGetter(const LC32OpenGLESCall &call,
                             Function function) {
    if(!RequireSlots(call, 2)) return 0;
    GLenum pname = SlotU32(call, 0);
    const size_t count = StateElementCount(pname);
    if(count == std::numeric_limits<size_t>::max()) {
        SetBridgeError(GL_INVALID_ENUM);
        return 0;
    }
    std::vector<T> values(std::max<size_t>(count, 1));
    function(pname, values.data());
    WriteGuestArray(SlotU32(call, 1), values.data(), count);
    return 0;
}

template<typename Function>
uint32_t DispatchObjectInputArray(const LC32OpenGLESCall &call,
                                  Function function) {
    if(!RequireSlots(call, 2)) return 0;
    int32_t signedCount = SlotI32(call, 0);
    size_t count;
    if(!ReadCount(signedCount, 1, count)) return 0;
    std::vector<GLuint> values;
    if(!ReadGuestArray(SlotU32(call, 1), count, values)) return 0;
    function(signedCount, values.data());
    return 0;
}

template<typename Function>
uint32_t DispatchObjectOutputArray(const LC32OpenGLESCall &call,
                                   Function function) {
    if(!RequireSlots(call, 2)) return 0;
    int32_t signedCount = SlotI32(call, 0);
    size_t count;
    if(!ReadCount(signedCount, 1, count)) return 0;
    std::vector<GLuint> values(count);
    function(signedCount, values.data());
    WriteGuestArray(SlotU32(call, 1), values.data(), count);
    return 0;
}

uint32_t DispatchInfoLog(const LC32OpenGLESCall &call, bool shader) {
    if(!RequireSlots(call, 4)) return 0;
    const GLuint object = SlotU32(call, 0);
    const int32_t signedSize = SlotI32(call, 1);
    if(signedSize < 0 || static_cast<size_t>(signedSize) > kMaximumTransfer ||
       (signedSize && !SlotU32(call, 3))) {
        SetBridgeError(GL_INVALID_VALUE);
        return 0;
    }
    std::vector<GLchar> log(static_cast<size_t>(signedSize), 0);
    GLsizei length = 0;
    GLchar *logPointer = signedSize ? log.data() : nullptr;
    if(shader) {
        glGetShaderInfoLog(object, signedSize, &length, logPointer);
    } else {
        glGetProgramInfoLog(object, signedSize, &length, logPointer);
    }
    if(SlotU32(call, 2)) {
        WriteGuestArray(SlotU32(call, 2), &length, 1);
    }
    if(signedSize) {
        const size_t written = std::min(static_cast<size_t>(signedSize),
            length >= 0 ? static_cast<size_t>(length) + 1 : size_t{0});
        WriteGuestArray(SlotU32(call, 3), log.data(), written);
    }
    return 0;
}

bool ReadGuestGLString(int32_t length, uint32_t guestAddress,
                       std::vector<GLchar> &storage,
                       const GLchar *&string) {
    string = nullptr;
    if(length < 0) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    if(!guestAddress) return true;
    if(length == 0) {
        std::string value;
        if(!ReadGuestCString(guestAddress, value)) return false;
        storage.assign(value.begin(), value.end());
        storage.push_back('\0');
        string = storage.data();
        return true;
    }
    if(static_cast<size_t>(length) > kMaximumString) {
        SetBridgeError(GL_INVALID_VALUE);
        return false;
    }
    storage.assign(static_cast<size_t>(length) + 1, 0);
    if(length && Dynarmic_mem_1read(guestAddress, static_cast<size_t>(length),
            storage.data()) != 0) {
        SetBridgeError(GL_INVALID_OPERATION);
        return false;
    }
    string = storage.data();
    return true;
}

template<typename Function>
uint32_t DispatchOutputString(const LC32OpenGLESCall &call,
                              size_t sizeSlot, size_t lengthSlot,
                              size_t stringSlot, Function function) {
    const int32_t signedSize = SlotI32(call, sizeSlot);
    if(signedSize < 0 || static_cast<size_t>(signedSize) > kMaximumString ||
       (signedSize && !SlotU32(call, stringSlot))) {
        SetBridgeError(GL_INVALID_VALUE);
        return 0;
    }
    std::vector<GLchar> output(static_cast<size_t>(signedSize), 0);
    GLsizei length = 0;
    function(signedSize, &length,
        signedSize ? output.data() : nullptr);
    if(SlotU32(call, lengthSlot) &&
       !WriteGuestArray(SlotU32(call, lengthSlot), &length, 1)) return 0;
    if(signedSize) {
        const size_t written = std::min(static_cast<size_t>(signedSize),
            length >= 0 ? static_cast<size_t>(length) + 1 : size_t{0});
        WriteGuestArray(SlotU32(call, stringSlot), output.data(), written);
    }
    return 0;
}

template<typename T, typename Function>
uint32_t DispatchProgramUniformArray(const LC32OpenGLESCall &call,
                                     size_t width, Function function) {
    if(!RequireSlots(call, 4)) return 0;
    size_t elementCount;
    if(!ReadCount(SlotI32(call, 2), width, elementCount)) return 0;
    std::vector<T> values;
    if(!ReadGuestArray(SlotU32(call, 3), elementCount, values)) return 0;
    function(SlotU32(call, 0), SlotI32(call, 1), SlotI32(call, 2),
        values.data());
    return 0;
}

uint32_t DispatchMapBuffer(const LC32OpenGLESCall &call, bool range) {
    if(!RequireSlots(call, range ? 5 : 4)) return 0;
    const GLenum target = SlotU32(call, 0);
    const int32_t signedLength = SlotI32(call, range ? 2 : 3);
    const uint32_t guestPointer = SlotU32(call, range ? 4 : 2);
    if(signedLength < 0 ||
       static_cast<size_t>(signedLength) > kMaximumTransfer ||
       (guestPointer && !GuestRangeValid(guestPointer,
            static_cast<size_t>(signedLength)))) {
        SetBridgeError(GL_INVALID_VALUE);
        return 0;
    }
    if(range && signedLength == 0) {
        SetBridgeError(GL_INVALID_OPERATION);
        return 0;
    }

    GLuint buffer = 0;
    if(!BoundBuffer(target, buffer)) {
        if(!range) {
            (void)glMapBufferOES(target, SlotU32(call, 1));
            return 0;
        }
        SetBridgeError(BufferBindingPname(target)
            ? GL_INVALID_OPERATION : GL_INVALID_ENUM);
        return 0;
    }
    const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
    std::unique_lock<std::mutex> lock(mappedBufferMutex);
    if(FindMappedBufferLocked(sharegroupKey, target, buffer) !=
            mappedBuffers.end()) {
        SetBridgeError(GL_INVALID_OPERATION);
        return 0;
    }

    GLvoid *nativePointer = nullptr;
    bool writable = false;
    bool readable = false;
    bool flushExplicit = false;
    if(range) {
        const int32_t offset = SlotI32(call, 1);
        const GLbitfield access = SlotU32(call, 3);
        if(offset < 0) {
            SetBridgeError(GL_INVALID_VALUE);
            return 0;
        }

        constexpr GLbitfield knownAccess = GL_MAP_READ_BIT_EXT |
            GL_MAP_WRITE_BIT_EXT | GL_MAP_INVALIDATE_RANGE_BIT_EXT |
            GL_MAP_INVALIDATE_BUFFER_BIT_EXT |
            GL_MAP_FLUSH_EXPLICIT_BIT_EXT |
            GL_MAP_UNSYNCHRONIZED_BIT_EXT;
        const bool reads = (access & GL_MAP_READ_BIT_EXT) != 0;
        const bool writes = (access & GL_MAP_WRITE_BIT_EXT) != 0;
        const bool invalidates = (access &
            (GL_MAP_INVALIDATE_RANGE_BIT_EXT |
             GL_MAP_INVALIDATE_BUFFER_BIT_EXT)) != 0;
        const bool validAccess = !(access & ~knownAccess) &&
            (reads || writes) &&
            !(reads && (invalidates ||
                (access & GL_MAP_UNSYNCHRONIZED_BIT_EXT))) &&
            !((access & GL_MAP_FLUSH_EXPLICIT_BIT_EXT) && !writes);

        GLint nativeLength = 0;
        glGetBufferParameteriv(target, GL_BUFFER_SIZE, &nativeLength);
        const size_t length = static_cast<size_t>(signedLength);
        const bool rangeInBounds = nativeLength >= 0 &&
            static_cast<size_t>(offset) <=
                static_cast<size_t>(nativeLength) &&
            length <= static_cast<size_t>(nativeLength) -
                static_cast<size_t>(offset);
        if(guestPointer && validAccess && writes && !reads &&
           !invalidates && rangeInBounds) {
            GLvoid *snapshot = glMapBufferRangeEXT(target, offset,
                signedLength, GL_MAP_READ_BIT_EXT);
            if(!snapshot) return 0;
            const bool copied = WriteGuestBytes(guestPointer, snapshot,
                length);
            const GLboolean unmapped = glUnmapBufferOES(target);
            if(!copied) return 0;
            if(unmapped == GL_FALSE) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
        }
        nativePointer = glMapBufferRangeEXT(target, offset, signedLength,
            access);
        writable = writes;
        readable = reads;
        flushExplicit = (access & GL_MAP_FLUSH_EXPLICIT_BIT_EXT) != 0;
    } else {
        GLint nativeLength = 0;
        glGetBufferParameteriv(target, GL_BUFFER_SIZE, &nativeLength);
        if(nativeLength != signedLength) {
            SetBridgeError(GL_INVALID_OPERATION);
            return 0;
        }
        const GLenum access = SlotU32(call, 1);
        if(guestPointer && signedLength > 0 &&
           access == GL_WRITE_ONLY_OES) {
            GLvoid *snapshot = glMapBufferRangeEXT(target, 0,
                signedLength, GL_MAP_READ_BIT_EXT);
            if(!snapshot) return 0;
            const bool copied = WriteGuestBytes(guestPointer, snapshot,
                static_cast<size_t>(signedLength));
            const GLboolean unmapped = glUnmapBufferOES(target);
            if(!copied) return 0;
            if(unmapped == GL_FALSE) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
        }
        nativePointer = glMapBufferOES(target, access);
        writable = access == GL_WRITE_ONLY_OES;
    }
    if(!nativePointer) return 0;

    if(!guestPointer) {
        glUnmapBufferOES(target);
        SetBridgeError(signedLength > 0 ? GL_OUT_OF_MEMORY
                                        : GL_INVALID_OPERATION);
        return 0;
    }

    if(readable && !WriteGuestBytes(guestPointer, nativePointer,
            static_cast<size_t>(signedLength))) {
        glUnmapBufferOES(target);
        return 0;
    }

    try {
        mappedBuffers.push_back({sharegroupKey, target, buffer, nativePointer,
            guestPointer, static_cast<size_t>(signedLength), writable,
            flushExplicit});
    } catch(const std::bad_alloc &) {
        glUnmapBufferOES(target);
        SetBridgeError(GL_OUT_OF_MEMORY);
        return 0;
    }
    return 1;
}

uint32_t DispatchActiveInfo(const LC32OpenGLESCall &call, bool uniform) {
    if(!RequireSlots(call, 7)) return 0;
    const int32_t signedSize = SlotI32(call, 2);
    if(signedSize < 0 || static_cast<size_t>(signedSize) > kMaximumString ||
       (signedSize && !SlotU32(call, 6))) {
        SetBridgeError(GL_INVALID_VALUE);
        return 0;
    }

    std::vector<GLchar> name(static_cast<size_t>(signedSize), 0);
    GLsizei length = 0;
    GLint size = 0;
    GLenum type = 0;
    if(uniform) {
        glGetActiveUniform(SlotU32(call, 0), SlotU32(call, 1), signedSize,
            &length, &size, &type, signedSize ? name.data() : nullptr);
    } else {
        glGetActiveAttrib(SlotU32(call, 0), SlotU32(call, 1), signedSize,
            &length, &size, &type, signedSize ? name.data() : nullptr);
    }
    if(SlotU32(call, 3) &&
       !WriteGuestArray(SlotU32(call, 3), &length, 1)) return 0;
    if(SlotU32(call, 4) &&
       !WriteGuestArray(SlotU32(call, 4), &size, 1)) return 0;
    if(SlotU32(call, 5) &&
       !WriteGuestArray(SlotU32(call, 5), &type, 1)) return 0;
    if(signedSize) {
        const size_t written = std::min(static_cast<size_t>(signedSize),
            length >= 0 ? static_cast<size_t>(length) + 1 : size_t{0});
        WriteGuestArray(SlotU32(call, 6), name.data(), written);
    }
    return 0;
}

size_t UniformTypeElementCount(GLenum type) {
    switch(type) {
        case GL_FLOAT:
        case GL_INT:
        case GL_UNSIGNED_INT:
        case GL_BOOL:
        case GL_SAMPLER_2D:
        case GL_SAMPLER_CUBE:
#ifdef GL_SAMPLER_3D
        case GL_SAMPLER_3D:
        case GL_SAMPLER_2D_ARRAY:
        case GL_SAMPLER_2D_SHADOW:
        case GL_SAMPLER_2D_ARRAY_SHADOW:
        case GL_SAMPLER_CUBE_SHADOW:
        case GL_INT_SAMPLER_2D:
        case GL_INT_SAMPLER_3D:
        case GL_INT_SAMPLER_CUBE:
        case GL_INT_SAMPLER_2D_ARRAY:
        case GL_UNSIGNED_INT_SAMPLER_2D:
        case GL_UNSIGNED_INT_SAMPLER_3D:
        case GL_UNSIGNED_INT_SAMPLER_CUBE:
        case GL_UNSIGNED_INT_SAMPLER_2D_ARRAY:
#endif
            return 1;
        case GL_FLOAT_VEC2:
        case GL_INT_VEC2:
        case GL_UNSIGNED_INT_VEC2:
        case GL_BOOL_VEC2:
            return 2;
        case GL_FLOAT_VEC3:
        case GL_INT_VEC3:
        case GL_UNSIGNED_INT_VEC3:
        case GL_BOOL_VEC3:
            return 3;
        case GL_FLOAT_VEC4:
        case GL_INT_VEC4:
        case GL_UNSIGNED_INT_VEC4:
        case GL_BOOL_VEC4:
        case GL_FLOAT_MAT2:
            return 4;
        case GL_FLOAT_MAT3:
            return 9;
        case GL_FLOAT_MAT4:
            return 16;
#ifdef GL_FLOAT_MAT2x3
        case GL_FLOAT_MAT2x3:
        case GL_FLOAT_MAT3x2:
            return 6;
        case GL_FLOAT_MAT2x4:
        case GL_FLOAT_MAT4x2:
            return 8;
        case GL_FLOAT_MAT3x4:
        case GL_FLOAT_MAT4x3:
            return 12;
#endif
        default:
            return 0;
    }
}

size_t UniformElementCount(GLuint program, GLint location) {
    GLint activeCount = 0;
    GLint maximumNameLength = 0;
    glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &activeCount);
    glGetProgramiv(program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &maximumNameLength);
    if(activeCount < 0 || activeCount > 4096 || maximumNameLength <= 0 ||
       static_cast<size_t>(maximumNameLength) > kMaximumString) return 0;

    std::vector<GLchar> name(static_cast<size_t>(maximumNameLength));
    for(GLuint index = 0; index < static_cast<GLuint>(activeCount); ++index) {
        GLsizei nameLength = 0;
        GLint arraySize = 0;
        GLenum type = 0;
        glGetActiveUniform(program, index, maximumNameLength, &nameLength,
            &arraySize, &type, name.data());
        const size_t elementCount = UniformTypeElementCount(type);
        if(!elementCount || nameLength <= 0 || arraySize <= 0 ||
           arraySize > 4096) continue;

        std::string baseName(name.data(), static_cast<size_t>(nameLength));
        const size_t suffix = baseName.rfind("[0]");
        if(arraySize == 1 || suffix == std::string::npos) {
            if(glGetUniformLocation(program, baseName.c_str()) == location)
                return elementCount;
            continue;
        }

        const std::string prefix = baseName.substr(0, suffix);
        const std::string tail = baseName.substr(suffix + 3);
        for(GLint element = 0; element < arraySize; ++element) {
            std::string elementName = prefix + "[" +
                std::to_string(element) + "]" + tail;
            if(glGetUniformLocation(program, elementName.c_str()) == location)
                return elementCount;
        }
    }
    return 0;
}

size_t VertexAttribElementCount(GLenum pname) {
    switch(pname) {
        case GL_CURRENT_VERTEX_ATTRIB:
            return 4;
        case GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING:
        case GL_VERTEX_ATTRIB_ARRAY_ENABLED:
        case GL_VERTEX_ATTRIB_ARRAY_NORMALIZED:
        case GL_VERTEX_ATTRIB_ARRAY_SIZE:
        case GL_VERTEX_ATTRIB_ARRAY_STRIDE:
        case GL_VERTEX_ATTRIB_ARRAY_TYPE:
#ifdef GL_VERTEX_ATTRIB_ARRAY_DIVISOR_EXT
        case GL_VERTEX_ATTRIB_ARRAY_DIVISOR_EXT:
#endif
#ifdef GL_VERTEX_ATTRIB_ARRAY_INTEGER
        case GL_VERTEX_ATTRIB_ARRAY_INTEGER:
#endif
            return 1;
        default:
            return 0;
    }
}

} // namespace

@implementation LC32EAGLContextStateLifetime

- (void)dealloc {
    RemoveClientArrayState(_contextKey);
    [super dealloc];
}

@end

@implementation LC32EAGLSharegroupStateLifetime

- (void)dealloc {
    RemoveAuxiliarySharegroupState(_sharegroupKey);
    [super dealloc];
}

@end

@implementation EAGLContext (LC32EAGLCompatibility)

+ (void)load {
    Class contextClass = self;
    Method storage = class_getInstanceMethod(
        contextClass, @selector(renderbufferStorage:fromDrawable:));
    Method normalizedStorage = class_getInstanceMethod(
        contextClass, @selector(lc32_renderbufferStorage:fromDrawable:));
    if(storage && normalizedStorage) {
        method_exchangeImplementations(storage, normalizedStorage);
    }
}

- (BOOL)lc32_renderbufferStorage:(NSUInteger)target
                    fromDrawable:(id<EAGLDrawable>)drawable {
    CAEAGLLayer *drawableLayer = nil;
    BOOL requestedRGB565 = NO;
    if([(id)drawable isKindOfClass:CAEAGLLayer.class]) {
        drawableLayer = (CAEAGLLayer *)(id)drawable;
        NSDictionary *properties = drawableLayer.drawableProperties;
        NSMutableDictionary *normalized =
            [NSMutableDictionary dictionaryWithCapacity:properties.count];
        for(id key in properties) {
            id value = properties[key];
            const BOOL retainedBackingKey =
                [key isEqual:kEAGLDrawablePropertyRetainedBacking] ||
                [key isEqual:@"EAGLDrawablePropertyRetainedBacking"];
            if(retainedBackingKey && ![value boolValue]) {
                /*
                 * Recent Simulator OpenGLES rejects the retained-backing key
                 * even when its value is the native @NO singleton. Omitting
                 * a false value is exactly equivalent and remains valid on
                 * older hosts.
                 */
                continue;
            }

            id normalizedKey = key;
            id normalizedValue = value;
            if(retainedBackingKey) {
                normalizedKey = kEAGLDrawablePropertyRetainedBacking;
                normalizedValue = [value boolValue] ? @YES : @NO;
            } else if([key isEqual:@"EAGLDrawablePropertyColorFormat"]) {
                normalizedKey = kEAGLDrawablePropertyColorFormat;
                if([value isEqual:@"EAGLColorFormat8888"] ||
                        [value isEqual:@"EAGLColorFormatRGBA8"]) {
                    normalizedValue = kEAGLColorFormatRGBA8;
                } else if([value isEqual:kEAGLColorFormatRGB565] ||
                        [value isEqual:@"EAGLColorFormat565"] ||
                        [value isEqual:@"EAGLColorFormatRGB565"]) {
                    normalizedValue = kEAGLColorFormatRGB565;
                    requestedRGB565 = YES;
                }
            }
            normalized[normalizedKey] = normalizedValue;
        }
        drawableLayer.drawableProperties = normalized;
    }

    BOOL result = [self lc32_renderbufferStorage:target
                                    fromDrawable:drawable];
    if(!result && requestedRGB565 && drawableLayer) {
        /*
         * Recent Simulator OpenGLES builds no longer allocate RGB565 layer
         * storage even though the legacy constant remains exported.  Old
         * games commonly request it to save memory.  Preserve RGB565 where
         * the host still supports it, but promote a rejected request to the
         * universally supported RGBA8 format so the renderbuffer is usable.
         */
        NSMutableDictionary *fallback =
            [drawableLayer.drawableProperties mutableCopy];
        fallback[kEAGLDrawablePropertyColorFormat] =
            kEAGLColorFormatRGBA8;
        drawableLayer.drawableProperties = fallback;
        [fallback release];
        result = [self lc32_renderbufferStorage:target
                                    fromDrawable:drawable];
    }
    return result;
}

@end

extern "C" uint32_t LC32_OpenGLES_Dispatch(uint32_t opcode,
                                            uint32_t guestCall,
                                            uint32_t) {
    LC32OpenGLESCall call;
    if(!ReadCall(guestCall, call)) return 0;
    DrainDeferredGuestMappingFrees();

#define REQUIRE(count) do { if(!RequireSlots(call, (count))) return 0; } while(0)
#define U(index) SlotU32(call, (index))
#define Q(index) SlotU64(call, (index))
#define I(index) SlotI32(call, (index))
#define F(index) SlotFloat(call, (index))

    switch(static_cast<LC32OpenGLESOpcode>(opcode)) {
        case LC32OpenGLESOpEAGLGetVersion: {
            REQUIRE(2);
            unsigned int major = 0, minor = 0;
            EAGLGetVersion(&major, &minor);
            if(U(0)) WriteGuestArray(U(0), &major, 1);
            if(U(1)) WriteGuestArray(U(1), &minor, 1);
            return 0;
        }
        case LC32OpenGLESOpGetStringLength: {
            REQUIRE(1);
            const GLubyte *value = glGetString(U(0));
            if(!value) return 0;
            size_t length = strlen(reinterpret_cast<const char *>(value)) + 1;
            return length <= UINT32_MAX ? static_cast<uint32_t>(length) : 0;
        }
        case LC32OpenGLESOpGetStringCopy: {
            REQUIRE(3);
            const GLubyte *value = glGetString(U(0));
            if(!value) return 0;
            size_t length = strlen(reinterpret_cast<const char *>(value)) + 1;
            if(length > U(2) || length > UINT32_MAX ||
               !WriteGuestBytes(U(1), value, length)) return 0;
            return static_cast<uint32_t>(length);
        }
        case LC32OpenGLESOpGetError: {
            REQUIRE(0);
            if(bridgeError != GL_NO_ERROR) {
                GLenum result = bridgeError;
                bridgeError = GL_NO_ERROR;
                return result;
            }
            return glGetError();
        }
        case LC32OpenGLESOpGetIntegerv:
            return DispatchStateGetter<GLint>(call,
                [](GLenum pname, GLint *values) { glGetIntegerv(pname, values); });
        case LC32OpenGLESOpGetBooleanv:
            return DispatchStateGetter<GLboolean>(call,
                [](GLenum pname, GLboolean *values) { glGetBooleanv(pname, values); });
        case LC32OpenGLESOpGetFloatv:
            return DispatchStateGetter<GLfloat>(call,
                [](GLenum pname, GLfloat *values) { glGetFloatv(pname, values); });
        case LC32OpenGLESOpGetFixedv:
            return DispatchStateGetter<GLfixed>(call,
                [](GLenum pname, GLfixed *values) { glGetFixedv(pname, values); });
        case LC32OpenGLESOpActiveTexture: REQUIRE(1); glActiveTexture(U(0)); return 0;
        case LC32OpenGLESOpActiveShaderProgramEXT:
            REQUIRE(2); glActiveShaderProgramEXT(U(0), U(1)); return 0;
        case LC32OpenGLESOpAttachShader: REQUIRE(2); glAttachShader(U(0), U(1)); return 0;
        case LC32OpenGLESOpBeginQueryEXT:
            REQUIRE(2); glBeginQueryEXT(U(0), U(1)); return 0;
        case LC32OpenGLESOpBeginTransformFeedback:
            REQUIRE(1); glBeginTransformFeedback(U(0)); return 0;
        case LC32OpenGLESOpBindBuffer: REQUIRE(2); glBindBuffer(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindBufferBase:
            REQUIRE(3); glBindBufferBase(U(0), U(1), U(2)); return 0;
        case LC32OpenGLESOpBindBufferRange:
            REQUIRE(5); glBindBufferRange(U(0), U(1), U(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpBindFramebuffer: REQUIRE(2); glBindFramebuffer(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindRenderbuffer: REQUIRE(2); glBindRenderbuffer(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindTexture: REQUIRE(2); glBindTexture(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindProgramPipelineEXT:
            REQUIRE(1); glBindProgramPipelineEXT(U(0)); return 0;
        case LC32OpenGLESOpBindSampler:
            REQUIRE(2); glBindSampler(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindTransformFeedback:
            REQUIRE(2); glBindTransformFeedback(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindVertexArrayOES:
            REQUIRE(1);
            glBindVertexArrayOES(U(0));
            {
                GLint bound = 0;
                glGetIntegerv(GL_VERTEX_ARRAY_BINDING_OES, &bound);
                if(static_cast<GLuint>(bound) == U(0))
                    SetCurrentVertexArray(U(0));
            }
            return 0;
        case LC32OpenGLESOpBlendColor: REQUIRE(4); glBlendColor(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpBlendEquation: REQUIRE(1); glBlendEquation(U(0)); return 0;
        case LC32OpenGLESOpBlendEquationSeparate: REQUIRE(2); glBlendEquationSeparate(U(0), U(1)); return 0;
        case LC32OpenGLESOpBlendFunc: REQUIRE(2); glBlendFunc(U(0), U(1)); return 0;
        case LC32OpenGLESOpBlendFuncSeparate: REQUIRE(4); glBlendFuncSeparate(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpBlitFramebuffer:
            REQUIRE(10);
            glBlitFramebuffer(I(0), I(1), I(2), I(3), I(4), I(5), I(6),
                I(7), U(8), U(9));
            return 0;
        case LC32OpenGLESOpCheckFramebufferStatus: REQUIRE(1); return glCheckFramebufferStatus(U(0));
        case LC32OpenGLESOpClientWaitSyncAPPLE: {
            REQUIRE(3);
            GLsync sync = LookupSync(U(0));
            if(!sync) {
                SetBridgeError(GL_INVALID_VALUE);
                return GL_WAIT_FAILED_APPLE;
            }
            return glClientWaitSyncAPPLE(sync, U(1), Q(2));
        }
        case LC32OpenGLESOpClear: REQUIRE(1); glClear(U(0)); return 0;
        case LC32OpenGLESOpClearBufferfi:
            REQUIRE(4); glClearBufferfi(U(0), I(1), F(2), I(3)); return 0;
        case LC32OpenGLESOpClearColor: REQUIRE(4); glClearColor(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpClearDepthf: REQUIRE(1); glClearDepthf(F(0)); return 0;
        case LC32OpenGLESOpClearStencil: REQUIRE(1); glClearStencil(I(0)); return 0;
        case LC32OpenGLESOpColorMask: REQUIRE(4); glColorMask(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpCompileShader: REQUIRE(1); glCompileShader(U(0)); return 0;
        case LC32OpenGLESOpCopyTexImage2D: REQUIRE(8); glCopyTexImage2D(U(0), I(1), U(2), I(3), I(4), I(5), I(6), I(7)); return 0;
        case LC32OpenGLESOpCopyTexSubImage2D: REQUIRE(8); glCopyTexSubImage2D(U(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7)); return 0;
        case LC32OpenGLESOpCopyBufferSubData:
            REQUIRE(5); glCopyBufferSubData(U(0), U(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpCopyTexSubImage3D:
            REQUIRE(9); glCopyTexSubImage3D(U(0), I(1), I(2), I(3), I(4),
                I(5), I(6), I(7), I(8)); return 0;
        case LC32OpenGLESOpCopyTextureLevelsAPPLE:
            REQUIRE(4); glCopyTextureLevelsAPPLE(U(0), U(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpCreateProgram: REQUIRE(0); return glCreateProgram();
        case LC32OpenGLESOpCreateShader: REQUIRE(1); return glCreateShader(U(0));
        case LC32OpenGLESOpCullFace: REQUIRE(1); glCullFace(U(0)); return 0;
        case LC32OpenGLESOpDeleteBuffers:
            return DispatchObjectInputArray(call,
                [](GLsizei n, const GLuint *values) {
                    const uintptr_t sharegroupKey =
                        CurrentGLSharegroupKey();
                    for(GLsizei index = 0; index < n; ++index) {
                        uint32_t guestPointer = 0;
                        {
                            std::lock_guard<std::mutex> lock(
                                mappedBufferMutex);
                            glDeleteBuffers(1, values + index);
                            guestPointer = RetireMappedBufferLocked(
                                sharegroupKey, values[index]);
                        }
                        ReleaseGuestMappingPointer(guestPointer);
                    }
                });
        case LC32OpenGLESOpDeleteFramebuffers:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteFramebuffers(n, v); });
        case LC32OpenGLESOpDeleteRenderbuffers:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteRenderbuffers(n, v); });
        case LC32OpenGLESOpDeleteTextures:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteTextures(n, v); });
        case LC32OpenGLESOpDeleteProgramPipelinesEXT:
            return DispatchObjectInputArray(call,
                [](GLsizei n, const GLuint *v) {
                    glDeleteProgramPipelinesEXT(n, v);
                });
        case LC32OpenGLESOpDeleteQueriesEXT:
            return DispatchObjectInputArray(call,
                [](GLsizei n, const GLuint *v) { glDeleteQueriesEXT(n, v); });
        case LC32OpenGLESOpDeleteSamplers:
            return DispatchObjectInputArray(call,
                [](GLsizei n, const GLuint *v) { glDeleteSamplers(n, v); });
        case LC32OpenGLESOpDeleteTransformFeedbacks:
            return DispatchObjectInputArray(call,
                [](GLsizei n, const GLuint *v) {
                    glDeleteTransformFeedbacks(n, v);
                });
        case LC32OpenGLESOpDeleteVertexArraysOES:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) {
                glDeleteVertexArraysOES(n, v);
                ForgetVertexArrayStates(n, v);
            });
        case LC32OpenGLESOpDeleteProgram: REQUIRE(1); glDeleteProgram(U(0)); return 0;
        case LC32OpenGLESOpDeleteShader: REQUIRE(1); glDeleteShader(U(0)); return 0;
        case LC32OpenGLESOpDeleteSyncAPPLE: {
            REQUIRE(1);
            if(!U(0)) return 0;
            GLsync sync = TakeSync(U(0));
            if(!sync) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            glDeleteSyncAPPLE(sync);
            return 0;
        }
        case LC32OpenGLESOpDepthFunc: REQUIRE(1); glDepthFunc(U(0)); return 0;
        case LC32OpenGLESOpDepthMask: REQUIRE(1); glDepthMask(U(0)); return 0;
        case LC32OpenGLESOpDepthRangef: REQUIRE(2); glDepthRangef(F(0), F(1)); return 0;
        case LC32OpenGLESOpDetachShader: REQUIRE(2); glDetachShader(U(0), U(1)); return 0;
        case LC32OpenGLESOpDisable: REQUIRE(1); glDisable(U(0)); return 0;
        case LC32OpenGLESOpDisableVertexAttribArray:
            REQUIRE(1);
            glDisableVertexAttribArray(U(0));
            if(VertexAttribIndexValid(U(0)))
                SetVertexAttribArrayEnabled(U(0), false);
            return 0;
        case LC32OpenGLESOpDrawArrays: {
            REQUIRE(3);
            const int32_t first = I(1);
            const int32_t count = I(2);
            if(first < 0 || count < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(count == 0) {
                glDrawArrays(U(0), first, count);
                return 0;
            }
            const size_t maximumIndex = static_cast<size_t>(first) +
                static_cast<size_t>(count) - 1;
            std::vector<StagedClientArray> staged;
            if(!StageClientArrays(maximumIndex, staged)) return 0;
            glDrawArrays(U(0), first, count);
            return 0;
        }
        case LC32OpenGLESOpDrawArraysInstancedEXT: {
            REQUIRE(4);
            const int32_t first = I(1);
            const int32_t count = I(2);
            const int32_t instanceCount = I(3);
            if(first < 0 || count < 0 || instanceCount < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(!count || !instanceCount) {
                glDrawArraysInstancedEXT(U(0), first, count, instanceCount);
                return 0;
            }
            const size_t maximumIndex = static_cast<size_t>(first) +
                static_cast<size_t>(count) - 1;
            std::vector<StagedClientArray> staged;
            if(!StageClientArrays(maximumIndex,
                    static_cast<size_t>(instanceCount), staged)) return 0;
            glDrawArraysInstancedEXT(U(0), first, count, instanceCount);
            return 0;
        }
        case LC32OpenGLESOpEnable: REQUIRE(1); glEnable(U(0)); return 0;
        case LC32OpenGLESOpEnableVertexAttribArray:
            REQUIRE(1);
            glEnableVertexAttribArray(U(0));
            if(VertexAttribIndexValid(U(0)))
                SetVertexAttribArrayEnabled(U(0), true);
            return 0;
        case LC32OpenGLESOpEndQueryEXT:
            REQUIRE(1); glEndQueryEXT(U(0)); return 0;
        case LC32OpenGLESOpEndTransformFeedback:
            REQUIRE(0); glEndTransformFeedback(); return 0;
        case LC32OpenGLESOpFinish: REQUIRE(0); glFinish(); return 0;
        case LC32OpenGLESOpFenceSyncAPPLE: {
            REQUIRE(2);
            GLsync sync = glFenceSyncAPPLE(U(0), U(1));
            if(!sync) return 0;
            const uint32_t token = PublishSync(sync);
            if(!token) {
                glDeleteSyncAPPLE(sync);
                SetBridgeError(GL_OUT_OF_MEMORY);
            }
            return token;
        }
        case LC32OpenGLESOpFlush: REQUIRE(0); glFlush(); return 0;
        case LC32OpenGLESOpFramebufferRenderbuffer: REQUIRE(4); glFramebufferRenderbuffer(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpFramebufferTexture2D: REQUIRE(5); glFramebufferTexture2D(U(0), U(1), U(2), U(3), I(4)); return 0;
        case LC32OpenGLESOpFramebufferTextureLayer:
            REQUIRE(5); glFramebufferTextureLayer(U(0), U(1), U(2), I(3),
                I(4)); return 0;
        case LC32OpenGLESOpFrontFace: REQUIRE(1); glFrontFace(U(0)); return 0;
        case LC32OpenGLESOpGenBuffers:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenBuffers(n, v); });
        case LC32OpenGLESOpGenFramebuffers:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenFramebuffers(n, v); });
        case LC32OpenGLESOpGenRenderbuffers:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenRenderbuffers(n, v); });
        case LC32OpenGLESOpGenTextures:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenTextures(n, v); });
        case LC32OpenGLESOpGenProgramPipelinesEXT:
            return DispatchObjectOutputArray(call,
                [](GLsizei n, GLuint *v) { glGenProgramPipelinesEXT(n, v); });
        case LC32OpenGLESOpGenQueriesEXT:
            return DispatchObjectOutputArray(call,
                [](GLsizei n, GLuint *v) { glGenQueriesEXT(n, v); });
        case LC32OpenGLESOpGenSamplers:
            return DispatchObjectOutputArray(call,
                [](GLsizei n, GLuint *v) { glGenSamplers(n, v); });
        case LC32OpenGLESOpGenTransformFeedbacks:
            return DispatchObjectOutputArray(call,
                [](GLsizei n, GLuint *v) { glGenTransformFeedbacks(n, v); });
        case LC32OpenGLESOpGenVertexArraysOES:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenVertexArraysOES(n, v); });
        case LC32OpenGLESOpGenerateMipmap: REQUIRE(1); glGenerateMipmap(U(0)); return 0;
        case LC32OpenGLESOpHint: REQUIRE(2); glHint(U(0), U(1)); return 0;
        case LC32OpenGLESOpIsBuffer: REQUIRE(1); return glIsBuffer(U(0));
        case LC32OpenGLESOpIsEnabled: REQUIRE(1); return glIsEnabled(U(0));
        case LC32OpenGLESOpIsFramebuffer: REQUIRE(1); return glIsFramebuffer(U(0));
        case LC32OpenGLESOpIsProgram: REQUIRE(1); return glIsProgram(U(0));
        case LC32OpenGLESOpIsRenderbuffer: REQUIRE(1); return glIsRenderbuffer(U(0));
        case LC32OpenGLESOpIsShader: REQUIRE(1); return glIsShader(U(0));
        case LC32OpenGLESOpIsTexture: REQUIRE(1); return glIsTexture(U(0));
        case LC32OpenGLESOpIsProgramPipelineEXT:
            REQUIRE(1); return glIsProgramPipelineEXT(U(0));
        case LC32OpenGLESOpIsQueryEXT:
            REQUIRE(1); return glIsQueryEXT(U(0));
        case LC32OpenGLESOpIsSampler:
            REQUIRE(1); return glIsSampler(U(0));
        case LC32OpenGLESOpIsTransformFeedback:
            REQUIRE(1); return glIsTransformFeedback(U(0));
        case LC32OpenGLESOpIsVertexArrayOES:
            REQUIRE(1); return glIsVertexArrayOES(U(0));
        case LC32OpenGLESOpIsSyncAPPLE: {
            REQUIRE(1);
            GLsync sync = LookupSync(U(0));
            return sync ? glIsSyncAPPLE(sync) : GL_FALSE;
        }
        case LC32OpenGLESOpLineWidth: REQUIRE(1); glLineWidth(F(0)); return 0;
        case LC32OpenGLESOpLinkProgram: REQUIRE(1); glLinkProgram(U(0)); return 0;
        case LC32OpenGLESOpPixelStorei: REQUIRE(2); glPixelStorei(U(0), I(1)); return 0;
        case LC32OpenGLESOpPauseTransformFeedback:
            REQUIRE(0); glPauseTransformFeedback(); return 0;
        case LC32OpenGLESOpPolygonOffset: REQUIRE(2); glPolygonOffset(F(0), F(1)); return 0;
        case LC32OpenGLESOpPopGroupMarkerEXT:
            REQUIRE(0); glPopGroupMarkerEXT(); return 0;
        case LC32OpenGLESOpProgramParameteriEXT:
            REQUIRE(3); glProgramParameteriEXT(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpProgramUniform1fEXT:
            REQUIRE(3); glProgramUniform1fEXT(U(0), I(1), F(2)); return 0;
        case LC32OpenGLESOpProgramUniform2fEXT:
            REQUIRE(4); glProgramUniform2fEXT(U(0), I(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpProgramUniform3fEXT:
            REQUIRE(5); glProgramUniform3fEXT(U(0), I(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpProgramUniform4fEXT:
            REQUIRE(6); glProgramUniform4fEXT(U(0), I(1), F(2), F(3), F(4), F(5)); return 0;
        case LC32OpenGLESOpProgramUniform1iEXT:
            REQUIRE(3); glProgramUniform1iEXT(U(0), I(1), I(2)); return 0;
        case LC32OpenGLESOpProgramUniform2iEXT:
            REQUIRE(4); glProgramUniform2iEXT(U(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpProgramUniform3iEXT:
            REQUIRE(5); glProgramUniform3iEXT(U(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpProgramUniform4iEXT:
            REQUIRE(6); glProgramUniform4iEXT(U(0), I(1), I(2), I(3), I(4), I(5)); return 0;
        case LC32OpenGLESOpProgramUniform1uiEXT:
            REQUIRE(3); glProgramUniform1uiEXT(U(0), I(1), U(2)); return 0;
        case LC32OpenGLESOpProgramUniform2uiEXT:
            REQUIRE(4); glProgramUniform2uiEXT(U(0), I(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpProgramUniform3uiEXT:
            REQUIRE(5); glProgramUniform3uiEXT(U(0), I(1), U(2), U(3), U(4)); return 0;
        case LC32OpenGLESOpProgramUniform4uiEXT:
            REQUIRE(6); glProgramUniform4uiEXT(U(0), I(1), U(2), U(3), U(4), U(5)); return 0;
        case LC32OpenGLESOpReadBuffer:
            REQUIRE(1); glReadBuffer(U(0)); return 0;
        case LC32OpenGLESOpReleaseShaderCompiler: REQUIRE(0); glReleaseShaderCompiler(); return 0;
        case LC32OpenGLESOpRenderbufferStorage: REQUIRE(4); glRenderbufferStorage(U(0), U(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpRenderbufferStorageMultisampleAPPLE: REQUIRE(5); glRenderbufferStorageMultisampleAPPLE(U(0), I(1), U(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpResolveMultisampleFramebufferAPPLE: REQUIRE(0); glResolveMultisampleFramebufferAPPLE(); return 0;
        case LC32OpenGLESOpResumeTransformFeedback:
            REQUIRE(0); glResumeTransformFeedback(); return 0;
        case LC32OpenGLESOpSampleCoverage: REQUIRE(2); glSampleCoverage(F(0), U(1)); return 0;
        case LC32OpenGLESOpSamplerParameterf:
            REQUIRE(3); glSamplerParameterf(U(0), U(1), F(2)); return 0;
        case LC32OpenGLESOpSamplerParameteri:
            REQUIRE(3); glSamplerParameteri(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpScissor: REQUIRE(4); glScissor(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpStencilFunc: REQUIRE(3); glStencilFunc(U(0), I(1), U(2)); return 0;
        case LC32OpenGLESOpStencilFuncSeparate: REQUIRE(4); glStencilFuncSeparate(U(0), U(1), I(2), U(3)); return 0;
        case LC32OpenGLESOpStencilMask: REQUIRE(1); glStencilMask(U(0)); return 0;
        case LC32OpenGLESOpStencilMaskSeparate: REQUIRE(2); glStencilMaskSeparate(U(0), U(1)); return 0;
        case LC32OpenGLESOpStencilOp: REQUIRE(3); glStencilOp(U(0), U(1), U(2)); return 0;
        case LC32OpenGLESOpStencilOpSeparate: REQUIRE(4); glStencilOpSeparate(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpTexParameterf: REQUIRE(3); glTexParameterf(U(0), U(1), F(2)); return 0;
        case LC32OpenGLESOpTexParameteri: REQUIRE(3); glTexParameteri(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpTexStorage2DEXT:
            REQUIRE(5); glTexStorage2DEXT(U(0), I(1), U(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpTexStorage3D:
            REQUIRE(6); glTexStorage3D(U(0), I(1), U(2), I(3), I(4), I(5)); return 0;
        case LC32OpenGLESOpUniform1f: REQUIRE(2); glUniform1f(I(0), F(1)); return 0;
        case LC32OpenGLESOpUniform1i: REQUIRE(2); glUniform1i(I(0), I(1)); return 0;
        case LC32OpenGLESOpUniform2f: REQUIRE(3); glUniform2f(I(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpUniform2i: REQUIRE(3); glUniform2i(I(0), I(1), I(2)); return 0;
        case LC32OpenGLESOpUniform3f: REQUIRE(4); glUniform3f(I(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpUniform3i: REQUIRE(4); glUniform3i(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpUniform4f: REQUIRE(5); glUniform4f(I(0), F(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpUniform4i: REQUIRE(5); glUniform4i(I(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpUniform1ui:
            REQUIRE(2); glUniform1ui(I(0), U(1)); return 0;
        case LC32OpenGLESOpUniform2ui:
            REQUIRE(3); glUniform2ui(I(0), U(1), U(2)); return 0;
        case LC32OpenGLESOpUniform3ui:
            REQUIRE(4); glUniform3ui(I(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpUniform4ui:
            REQUIRE(5); glUniform4ui(I(0), U(1), U(2), U(3), U(4)); return 0;
        case LC32OpenGLESOpUniformBlockBinding:
            REQUIRE(3); glUniformBlockBinding(U(0), U(1), U(2)); return 0;
        case LC32OpenGLESOpUseProgram: REQUIRE(1); glUseProgram(U(0)); return 0;
        case LC32OpenGLESOpValidateProgram: REQUIRE(1); glValidateProgram(U(0)); return 0;
        case LC32OpenGLESOpUseProgramStagesEXT:
            REQUIRE(3); glUseProgramStagesEXT(U(0), U(1), U(2)); return 0;
        case LC32OpenGLESOpValidateProgramPipelineEXT:
            REQUIRE(1); glValidateProgramPipelineEXT(U(0)); return 0;
        case LC32OpenGLESOpVertexAttribDivisorEXT:
            REQUIRE(2);
            glVertexAttribDivisorEXT(U(0), U(1));
            if(VertexAttribIndexValid(U(0)))
                SetVertexAttribDivisor(U(0), U(1));
            return 0;
        case LC32OpenGLESOpWaitSyncAPPLE: {
            REQUIRE(3);
            GLsync sync = LookupSync(U(0));
            if(!sync) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            glWaitSyncAPPLE(sync, U(1), Q(2));
            return 0;
        }
        case LC32OpenGLESOpVertexAttrib1f: REQUIRE(2); glVertexAttrib1f(U(0), F(1)); return 0;
        case LC32OpenGLESOpVertexAttrib2f: REQUIRE(3); glVertexAttrib2f(U(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpVertexAttrib3f: REQUIRE(4); glVertexAttrib3f(U(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpVertexAttrib4f: REQUIRE(5); glVertexAttrib4f(U(0), F(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpVertexAttribI4i:
            REQUIRE(5); glVertexAttribI4i(U(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpVertexAttribI4ui:
            REQUIRE(5); glVertexAttribI4ui(U(0), U(1), U(2), U(3), U(4)); return 0;
        case LC32OpenGLESOpViewport: REQUIRE(4); glViewport(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpAlphaFunc: REQUIRE(2); glAlphaFunc(U(0), F(1)); return 0;
        case LC32OpenGLESOpAlphaFuncx: REQUIRE(2); glAlphaFuncx(U(0), I(1)); return 0;
        case LC32OpenGLESOpClearColorx: REQUIRE(4); glClearColorx(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpClearDepthx: REQUIRE(1); glClearDepthx(I(0)); return 0;
        case LC32OpenGLESOpColor4f: REQUIRE(4); glColor4f(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpColor4ub: REQUIRE(4); glColor4ub(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpColor4x: REQUIRE(4); glColor4x(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpDepthRangex: REQUIRE(2); glDepthRangex(I(0), I(1)); return 0;
        case LC32OpenGLESOpDisableClientState:
            REQUIRE(1);
            glDisableClientState(U(0));
            SetClientStateEnabled(U(0), false);
            return 0;
        case LC32OpenGLESOpEnableClientState:
            REQUIRE(1);
            glEnableClientState(U(0));
            SetClientStateEnabled(U(0), true);
            return 0;
        case LC32OpenGLESOpFogf: REQUIRE(2); glFogf(U(0), F(1)); return 0;
        case LC32OpenGLESOpFogx: REQUIRE(2); glFogx(U(0), I(1)); return 0;
        case LC32OpenGLESOpFrustumf: REQUIRE(6); glFrustumf(F(0), F(1), F(2), F(3), F(4), F(5)); return 0;
        case LC32OpenGLESOpFrustumx: REQUIRE(6); glFrustumx(I(0), I(1), I(2), I(3), I(4), I(5)); return 0;
        case LC32OpenGLESOpLightModelf: REQUIRE(2); glLightModelf(U(0), F(1)); return 0;
        case LC32OpenGLESOpLightModelx: REQUIRE(2); glLightModelx(U(0), I(1)); return 0;
        case LC32OpenGLESOpLightf: REQUIRE(3); glLightf(U(0), U(1), F(2)); return 0;
        case LC32OpenGLESOpLightx: REQUIRE(3); glLightx(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpLineWidthx: REQUIRE(1); glLineWidthx(I(0)); return 0;
        case LC32OpenGLESOpLoadIdentity: REQUIRE(0); glLoadIdentity(); return 0;
        case LC32OpenGLESOpLogicOp: REQUIRE(1); glLogicOp(U(0)); return 0;
        case LC32OpenGLESOpMaterialf: REQUIRE(3); glMaterialf(U(0), U(1), F(2)); return 0;
        case LC32OpenGLESOpMaterialx: REQUIRE(3); glMaterialx(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpMatrixMode: REQUIRE(1); glMatrixMode(U(0)); return 0;
        case LC32OpenGLESOpMultiTexCoord4f: REQUIRE(5); glMultiTexCoord4f(U(0), F(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpMultiTexCoord4x: REQUIRE(5); glMultiTexCoord4x(U(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpNormal3f: REQUIRE(3); glNormal3f(F(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpNormal3x: REQUIRE(3); glNormal3x(I(0), I(1), I(2)); return 0;
        case LC32OpenGLESOpOrthof: REQUIRE(6); glOrthof(F(0), F(1), F(2), F(3), F(4), F(5)); return 0;
        case LC32OpenGLESOpOrthox: REQUIRE(6); glOrthox(I(0), I(1), I(2), I(3), I(4), I(5)); return 0;
        case LC32OpenGLESOpPointParameterf: REQUIRE(2); glPointParameterf(U(0), F(1)); return 0;
        case LC32OpenGLESOpPointParameterx: REQUIRE(2); glPointParameterx(U(0), I(1)); return 0;
        case LC32OpenGLESOpPointSize: REQUIRE(1); glPointSize(F(0)); return 0;
        case LC32OpenGLESOpPointSizex: REQUIRE(1); glPointSizex(I(0)); return 0;
        case LC32OpenGLESOpPolygonOffsetx: REQUIRE(2); glPolygonOffsetx(I(0), I(1)); return 0;
        case LC32OpenGLESOpPopMatrix: REQUIRE(0); glPopMatrix(); return 0;
        case LC32OpenGLESOpPushMatrix: REQUIRE(0); glPushMatrix(); return 0;
        case LC32OpenGLESOpRotatef: REQUIRE(4); glRotatef(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpRotatex: REQUIRE(4); glRotatex(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpSampleCoveragex: REQUIRE(2); glSampleCoveragex(I(0), U(1)); return 0;
        case LC32OpenGLESOpScalef: REQUIRE(3); glScalef(F(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpScalex: REQUIRE(3); glScalex(I(0), I(1), I(2)); return 0;
        case LC32OpenGLESOpShadeModel: REQUIRE(1); glShadeModel(U(0)); return 0;
        case LC32OpenGLESOpTexEnvx: REQUIRE(3); glTexEnvx(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpTexParameterx: REQUIRE(3); glTexParameterx(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpTranslatef: REQUIRE(3); glTranslatef(F(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpTranslatex: REQUIRE(3); glTranslatex(I(0), I(1), I(2)); return 0;
        case LC32OpenGLESOpCurrentPaletteMatrixOES:
            REQUIRE(1); glCurrentPaletteMatrixOES(U(0)); return 0;
        case LC32OpenGLESOpLoadPaletteFromModelViewMatrixOES:
            REQUIRE(0); glLoadPaletteFromModelViewMatrixOES(); return 0;
        case LC32OpenGLESOpDrawTexfOES:
            REQUIRE(5); glDrawTexfOES(F(0), F(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpDrawTexiOES:
            REQUIRE(5); glDrawTexiOES(I(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpDrawTexsOES:
            REQUIRE(5); glDrawTexsOES(I(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpDrawTexxOES:
            REQUIRE(5); glDrawTexxOES(I(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpBindRenderbufferOES: REQUIRE(2); glBindRenderbufferOES(U(0), U(1)); return 0;
        case LC32OpenGLESOpFramebufferRenderbufferOES: REQUIRE(4); glFramebufferRenderbufferOES(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpGenRenderbuffersOES:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenRenderbuffersOES(n, v); });
        case LC32OpenGLESOpRenderbufferStorageOES: REQUIRE(4); glRenderbufferStorageOES(U(0), U(1), I(2), I(3)); return 0;
        default:
            break;
    }

    /* Pointer-bearing and variable-length calls are kept out of the terse cases. */
    switch(static_cast<LC32OpenGLESOpcode>(opcode)) {
        case LC32OpenGLESOpClearBufferfv:
        case LC32OpenGLESOpClearBufferiv:
        case LC32OpenGLESOpClearBufferuiv: {
            REQUIRE(3);
            const size_t count = ClearBufferElementCount(U(0));
            if(!count) {
                const GLuint dummy[4] = {};
                if(opcode == LC32OpenGLESOpClearBufferfv)
                    glClearBufferfv(U(0), I(1),
                        reinterpret_cast<const GLfloat *>(dummy));
                else if(opcode == LC32OpenGLESOpClearBufferiv)
                    glClearBufferiv(U(0), I(1),
                        reinterpret_cast<const GLint *>(dummy));
                else
                    glClearBufferuiv(U(0), I(1), dummy);
                return 0;
            }
            if(opcode == LC32OpenGLESOpClearBufferfv) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glClearBufferfv(U(0), I(1), values.data());
            } else if(opcode == LC32OpenGLESOpClearBufferiv) {
                std::vector<GLint> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glClearBufferiv(U(0), I(1), values.data());
            } else {
                std::vector<GLuint> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glClearBufferuiv(U(0), I(1), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpCompressedTexImage3D:
        case LC32OpenGLESOpCompressedTexSubImage3D: {
            const bool image = opcode == LC32OpenGLESOpCompressedTexImage3D;
            if(!RequireSlots(call, image ? 9 : 11)) return 0;
            const size_t sizeSlot = image ? 7 : 9;
            const size_t pointerSlot = image ? 8 : 10;
            const int32_t signedSize = I(sizeSlot);
            if(signedSize < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            GLint unpackBuffer = 0;
            glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer);
            std::vector<uint8_t> bytes;
            const void *data = nullptr;
            if(unpackBuffer) {
                data = reinterpret_cast<const void *>(
                    static_cast<uintptr_t>(U(pointerSlot)));
            } else if(signedSize && U(pointerSlot)) {
                if(!ReadGuestBytes(U(pointerSlot), signedSize, bytes)) return 0;
                data = bytes.data();
            } else if(signedSize && !image) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(image) {
                glCompressedTexImage3D(U(0), I(1), U(2), I(3), I(4), I(5),
                    I(6), signedSize, data);
            } else {
                glCompressedTexSubImage3D(U(0), I(1), I(2), I(3), I(4),
                    I(5), I(6), I(7), U(8), signedSize, data);
            }
            return 0;
        }
        case LC32OpenGLESOpDrawBuffers: {
            REQUIRE(2);
            size_t count;
            if(!ReadCount(I(0), 1, count)) return 0;
            std::vector<GLenum> values;
            if(!ReadGuestArray(U(1), count, values)) return 0;
            glDrawBuffers(I(0), values.data());
            return 0;
        }
        case LC32OpenGLESOpInvalidateFramebuffer:
        case LC32OpenGLESOpInvalidateSubFramebuffer: {
            const uint32_t required =
                opcode == LC32OpenGLESOpInvalidateSubFramebuffer ? 7 : 3;
            if(!RequireSlots(call, required)) return 0;
            size_t count;
            if(!ReadCount(I(1), 1, count)) return 0;
            std::vector<GLenum> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            if(opcode == LC32OpenGLESOpInvalidateFramebuffer)
                glInvalidateFramebuffer(U(0), I(1), values.data());
            else
                glInvalidateSubFramebuffer(U(0), I(1), values.data(),
                    I(3), I(4), I(5), I(6));
            return 0;
        }
        case LC32OpenGLESOpProgramBinary: {
            REQUIRE(4);
            const int32_t length = I(3);
            if(length < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<uint8_t> binary;
            if(!ReadGuestBytes(U(2), static_cast<size_t>(length), binary))
                return 0;
            glProgramBinary(U(0), U(1), length ? binary.data() : nullptr,
                length);
            return 0;
        }
        case LC32OpenGLESOpGetActiveUniformBlockName: {
            REQUIRE(5);
            return DispatchOutputString(call, 2, 3, 4,
                [&](GLsizei size, GLsizei *length, GLchar *name) {
                    glGetActiveUniformBlockName(U(0), U(1), size, length,
                        name);
                });
        }
        case LC32OpenGLESOpGetActiveUniformBlockiv: {
            REQUIRE(4);
            const size_t count = UniformBlockElementCount(U(0), U(1), U(2));
            if(count == std::numeric_limits<size_t>::max()) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<GLint> values(std::max<size_t>(count, 1));
            glGetActiveUniformBlockiv(U(0), U(1), U(2), values.data());
            WriteGuestArray(U(3), values.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetActiveUniformsiv: {
            REQUIRE(5);
            size_t count;
            if(!ReadCount(I(1), 1, count)) return 0;
            std::vector<GLuint> indices;
            std::vector<GLint> values(count);
            if(!ReadGuestArray(U(2), count, indices)) return 0;
            glGetActiveUniformsiv(U(0), I(1), indices.data(), U(3),
                values.data());
            WriteGuestArray(U(4), values.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetBufferParameteri64v: {
            REQUIRE(3);
            GLint64 value = 0;
            glGetBufferParameteri64v(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetFragDataLocation: {
            REQUIRE(2);
            std::string name;
            if(!ReadGuestCString(U(1), name)) return static_cast<uint32_t>(-1);
            return static_cast<uint32_t>(
                glGetFragDataLocation(U(0), name.c_str()));
        }
        case LC32OpenGLESOpGetInteger64i_v: {
            REQUIRE(3);
            GLint64 value = 0;
            glGetInteger64i_v(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetIntegeri_v: {
            REQUIRE(3);
            GLint value = 0;
            glGetIntegeri_v(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetInternalformativ: {
            REQUIRE(5);
            size_t byteCount;
            if(!ReadCount(I(3), sizeof(GLint), byteCount)) return 0;
            if(!GuestRangeValid(U(4), byteCount) ||
               (byteCount && !U(4))) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            const size_t count = byteCount / sizeof(GLint);
            std::vector<GLint> values;
            try {
                values.resize(count);
            } catch(const std::bad_alloc &) {
                SetBridgeError(GL_OUT_OF_MEMORY);
                return 0;
            }
            glGetInternalformativ(U(0), U(1), U(2), I(3),
                count ? values.data() : nullptr);
            WriteGuestArray(U(4), values.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetProgramBinary: {
            REQUIRE(5);
            const int32_t size = I(1);
            if(size < 0 || static_cast<size_t>(size) > kMaximumTransfer ||
               (size && !U(4))) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<uint8_t> binary(static_cast<size_t>(size));
            GLsizei length = 0;
            GLenum format = 0;
            glGetProgramBinary(U(0), size, &length, &format,
                size ? binary.data() : nullptr);
            if(U(2)) WriteGuestArray(U(2), &length, 1);
            if(U(3)) WriteGuestArray(U(3), &format, 1);
            if(size && length > 0) {
                const size_t written = std::min(static_cast<size_t>(size),
                    static_cast<size_t>(length));
                WriteGuestBytes(U(4), binary.data(), written);
            }
            return 0;
        }
        case LC32OpenGLESOpGetSamplerParameterfv:
        case LC32OpenGLESOpGetSamplerParameteriv: {
            REQUIRE(3);
            const size_t count = SamplerParameterElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetSamplerParameterfv) {
                std::vector<GLfloat> values(count);
                glGetSamplerParameterfv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLint> values(count);
                glGetSamplerParameteriv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetStringiLength: {
            REQUIRE(2);
            const GLubyte *value = glGetStringi(U(0), U(1));
            if(!value) return 0;
            const size_t length =
                strlen(reinterpret_cast<const char *>(value)) + 1;
            return length <= UINT32_MAX ? static_cast<uint32_t>(length) : 0;
        }
        case LC32OpenGLESOpGetStringiCopy: {
            REQUIRE(4);
            const GLubyte *value = glGetStringi(U(0), U(1));
            if(!value) return 0;
            const size_t length =
                strlen(reinterpret_cast<const char *>(value)) + 1;
            if(length > U(3) || length > UINT32_MAX ||
               !WriteGuestBytes(U(2), value, length)) return 0;
            return static_cast<uint32_t>(length);
        }
        case LC32OpenGLESOpGetTransformFeedbackVarying: {
            REQUIRE(7);
            const int32_t size = I(2);
            if(size < 0 || static_cast<size_t>(size) > kMaximumString ||
               (size && !U(6))) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<GLchar> name(static_cast<size_t>(size), 0);
            GLsizei length = 0;
            GLsizei varyingSize = 0;
            GLenum type = 0;
            glGetTransformFeedbackVarying(U(0), U(1), size, &length,
                &varyingSize, &type, size ? name.data() : nullptr);
            if(U(3)) WriteGuestArray(U(3), &length, 1);
            if(U(4)) WriteGuestArray(U(4), &varyingSize, 1);
            if(U(5)) WriteGuestArray(U(5), &type, 1);
            if(size) {
                const size_t written = std::min(static_cast<size_t>(size),
                    length >= 0 ? static_cast<size_t>(length) + 1 : size_t{0});
                WriteGuestArray(U(6), name.data(), written);
            }
            return 0;
        }
        case LC32OpenGLESOpGetUniformBlockIndex: {
            REQUIRE(2);
            std::string name;
            if(!ReadGuestCString(U(1), name)) return GL_INVALID_INDEX;
            return glGetUniformBlockIndex(U(0), name.c_str());
        }
        case LC32OpenGLESOpGetUniformIndices: {
            REQUIRE(4);
            size_t count;
            if(!ReadCount(I(1), 1, count)) return 0;
            std::vector<uint32_t> guestNames;
            if(!ReadGuestArray(U(2), count, guestNames)) return 0;
            std::vector<std::string> storage(count);
            std::vector<const GLchar *> names(count);
            size_t total = 0;
            for(size_t i = 0; i < count; ++i) {
                if(!ReadGuestCString(guestNames[i], storage[i])) return 0;
                if(storage[i].size() > kMaximumString - total) {
                    SetBridgeError(GL_INVALID_VALUE);
                    return 0;
                }
                total += storage[i].size();
                names[i] = storage[i].c_str();
            }
            std::vector<GLuint> indices(count);
            glGetUniformIndices(U(0), I(1), names.data(), indices.data());
            WriteGuestArray(U(3), indices.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetUniformuiv: {
            REQUIRE(3);
            const size_t count = UniformElementCount(U(0), I(1));
            if(!count) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            std::vector<GLuint> values(count);
            glGetUniformuiv(U(0), I(1), values.data());
            WriteGuestArray(U(2), values.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetVertexAttribIiv:
        case LC32OpenGLESOpGetVertexAttribIuiv: {
            REQUIRE(3);
            const size_t count = VertexAttribElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetVertexAttribIiv) {
                std::vector<GLint> values(count);
                glGetVertexAttribIiv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLuint> values(count);
                glGetVertexAttribIuiv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpCompressedTexImage2D:
        case LC32OpenGLESOpCompressedTexSubImage2D: {
            const bool image = opcode == LC32OpenGLESOpCompressedTexImage2D;
            if(!RequireSlots(call, image ? 8 : 9)) return 0;
            const size_t sizeSlot = image ? 6 : 7;
            const size_t pointerSlot = image ? 7 : 8;
            const int32_t signedSize = I(sizeSlot);
            if(signedSize < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            GLint unpackBuffer = 0;
            if(CurrentContextIsES3())
                glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer);
            std::vector<uint8_t> bytes;
            const void *data = nullptr;
            if(unpackBuffer) {
                data = reinterpret_cast<const void *>(
                    static_cast<uintptr_t>(U(pointerSlot)));
            } else if(signedSize && U(pointerSlot)) {
                if(!ReadGuestBytes(U(pointerSlot), signedSize, bytes))
                    return 0;
                data = bytes.data();
            } else if(signedSize && !image) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(image) {
                glCompressedTexImage2D(U(0), I(1), U(2), I(3), I(4), I(5),
                    signedSize, data);
            } else {
                glCompressedTexSubImage2D(U(0), I(1), I(2), I(3), I(4),
                    I(5), U(6), signedSize, data);
            }
            return 0;
        }
        case LC32OpenGLESOpBindAttribLocation:
        case LC32OpenGLESOpGetAttribLocation:
        case LC32OpenGLESOpGetUniformLocation: {
            const uint32_t count = opcode == LC32OpenGLESOpBindAttribLocation ? 3 : 2;
            if(!RequireSlots(call, count)) return 0;
            std::string name;
            uint32_t nameSlot = count - 1;
            if(!ReadGuestCString(U(nameSlot), name)) return 0;
            if(opcode == LC32OpenGLESOpBindAttribLocation) {
                glBindAttribLocation(U(0), U(1), name.c_str());
                return 0;
            }
            return opcode == LC32OpenGLESOpGetAttribLocation
                ? static_cast<uint32_t>(glGetAttribLocation(U(0), name.c_str()))
                : static_cast<uint32_t>(glGetUniformLocation(U(0), name.c_str()));
        }
        case LC32OpenGLESOpBufferData: {
            REQUIRE(4);
            const int32_t signedSize = I(1);
            if(signedSize < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<uint8_t> bytes;
            const void *data = nullptr;
            if(U(2) && signedSize) {
                if(!ReadGuestBytes(U(2), signedSize, bytes)) return 0;
                data = bytes.data();
            }
            GLuint buffer = 0;
            if(!BoundBuffer(U(0), buffer)) {
                glBufferData(U(0), signedSize, data, U(3));
                return 0;
            }
            const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
            uint32_t guestPointer = 0;
            {
                std::lock_guard<std::mutex> lock(mappedBufferMutex);
                auto mapped = FindMappedBufferLocked(sharegroupKey, U(0),
                    buffer);
                glBufferData(U(0), signedSize, data, U(3));
                if(mapped != mappedBuffers.end()) {
                    GLint stillMapped = GL_TRUE;
                    glGetBufferParameteriv(U(0), GL_BUFFER_MAPPED_OES,
                        &stillMapped);
                    if(stillMapped == GL_FALSE)
                        guestPointer = RetireMappedBufferLocked(
                            sharegroupKey, buffer);
                }
            }
            ReleaseGuestMappingPointer(guestPointer);
            return 0;
        }
        case LC32OpenGLESOpBufferSubData: {
            REQUIRE(4);
            const int32_t signedOffset = I(1);
            const int32_t signedSize = I(2);
            if(signedOffset < 0 || signedSize < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<uint8_t> bytes;
            if(!ReadGuestBytes(U(3), signedSize, bytes)) return 0;
            glBufferSubData(U(0), signedOffset, signedSize,
                signedSize ? bytes.data() : nullptr);
            return 0;
        }
        case LC32OpenGLESOpGetBufferParameteriv:
        case LC32OpenGLESOpGetRenderbufferParameteriv: {
            REQUIRE(3);
            GLint value = 0;
            if(opcode == LC32OpenGLESOpGetBufferParameteriv)
                glGetBufferParameteriv(U(0), U(1), &value);
            else
                glGetRenderbufferParameteriv(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetBufferPointervOES: {
            REQUIRE(3);
            uint32_t guestPointer = 0;
            GLuint buffer = 0;
            if(U(1) == GL_BUFFER_MAP_POINTER_OES &&
               BoundBuffer(U(0), buffer)) {
                const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
                std::lock_guard<std::mutex> lock(mappedBufferMutex);
                auto mapped = FindMappedBufferLocked(
                    sharegroupKey, U(0), buffer);
                if(mapped != mappedBuffers.end())
                    guestPointer = mapped->guestPointer;
            } else {
                GLvoid *ignored = nullptr;
                glGetBufferPointervOES(U(0), U(1), &ignored);
            }
            WriteGuestArray(U(2), &guestPointer, 1);
            return 0;
        }
        case LC32OpenGLESOpGetFramebufferAttachmentParameteriv: {
            REQUIRE(4);
            GLint value = 0;
            glGetFramebufferAttachmentParameteriv(U(0), U(1), U(2), &value);
            WriteGuestArray(U(3), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetInteger64vAPPLE: {
            REQUIRE(2);
            const size_t count = StateElementCount(U(0));
            if(count == std::numeric_limits<size_t>::max()) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<GLint64> values(std::max<size_t>(count, 1));
            if(CurrentContextIsES3())
                glGetInteger64v(U(0), values.data());
            else
                glGetInteger64vAPPLE(U(0), values.data());
            WriteGuestArray(U(1), values.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetSyncivAPPLE: {
            REQUIRE(5);
            const int32_t signedSize = I(2);
            if(signedSize < 0 ||
               static_cast<size_t>(signedSize) >
                   kMaximumTransfer / sizeof(GLint) ||
               (signedSize && !U(4))) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            GLsync sync = LookupSync(U(0));
            if(!sync) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<GLint> values(static_cast<size_t>(signedSize));
            GLsizei length = 0;
            glGetSyncivAPPLE(sync, U(1), signedSize, &length,
                signedSize ? values.data() : nullptr);
            if(U(3) && !WriteGuestArray(U(3), &length, 1)) return 0;
            if(length > 0 && length <= signedSize)
                WriteGuestArray(U(4), values.data(),
                    static_cast<size_t>(length));
            return 0;
        }
        case LC32OpenGLESOpGetProgramPipelineivEXT: {
            REQUIRE(3);
            GLint value = 0;
            glGetProgramPipelineivEXT(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetQueryivEXT: {
            REQUIRE(3);
            GLint value = 0;
            glGetQueryivEXT(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetQueryObjectuivEXT: {
            REQUIRE(3);
            GLuint value = 0;
            glGetQueryObjectuivEXT(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetProgramiv:
        case LC32OpenGLESOpGetShaderiv: {
            REQUIRE(3);
            GLint value = 0;
            if(opcode == LC32OpenGLESOpGetProgramiv)
                glGetProgramiv(U(0), U(1), &value);
            else
                glGetShaderiv(U(0), U(1), &value);
            WriteGuestArray(U(2), &value, 1);
            return 0;
        }
        case LC32OpenGLESOpGetProgramInfoLog:
            return DispatchInfoLog(call, false);
        case LC32OpenGLESOpGetShaderInfoLog:
            return DispatchInfoLog(call, true);
        case LC32OpenGLESOpGetObjectLabelEXT: {
            REQUIRE(5);
            GLuint object = U(1);
            if(U(0) == GL_SYNC_OBJECT_APPLE &&
               !NativeSyncObjectName(U(1), object)) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            return DispatchOutputString(call, 2, 3, 4,
                [&](GLsizei size, GLsizei *length, GLchar *output) {
                    glGetObjectLabelEXT(U(0), object, size, length, output);
                });
        }
        case LC32OpenGLESOpGetProgramPipelineInfoLogEXT:
            REQUIRE(4);
            return DispatchOutputString(call, 1, 2, 3,
                [&](GLsizei size, GLsizei *length, GLchar *output) {
                    glGetProgramPipelineInfoLogEXT(U(0), size, length,
                        output);
                });
        case LC32OpenGLESOpGetActiveAttrib:
            return DispatchActiveInfo(call, false);
        case LC32OpenGLESOpGetActiveUniform:
            return DispatchActiveInfo(call, true);
        case LC32OpenGLESOpGetAttachedShaders: {
            REQUIRE(4);
            const int32_t signedMaximum = I(1);
            if(signedMaximum < 0 ||
               static_cast<size_t>(signedMaximum) >
                   kMaximumTransfer / sizeof(GLuint) ||
               (signedMaximum && !U(3))) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<GLuint> shaders(static_cast<size_t>(signedMaximum));
            GLsizei count = 0;
            glGetAttachedShaders(U(0), signedMaximum, &count,
                signedMaximum ? shaders.data() : nullptr);
            if(U(2) && !WriteGuestArray(U(2), &count, 1)) return 0;
            if(count > 0 && count <= signedMaximum)
                WriteGuestArray(U(3), shaders.data(), static_cast<size_t>(count));
            return 0;
        }
        case LC32OpenGLESOpGetShaderPrecisionFormat: {
            REQUIRE(4);
            GLint range[2] = {};
            GLint precision = 0;
            glGetShaderPrecisionFormat(U(0), U(1), range, &precision);
            if(!WriteGuestArray(U(2), range, 2)) return 0;
            WriteGuestArray(U(3), &precision, 1);
            return 0;
        }
        case LC32OpenGLESOpGetShaderSource: {
            REQUIRE(4);
            const int32_t signedSize = I(1);
            if(signedSize < 0 ||
               static_cast<size_t>(signedSize) > kMaximumString ||
               (signedSize && !U(3))) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<GLchar> source(static_cast<size_t>(signedSize), 0);
            GLsizei length = 0;
            glGetShaderSource(U(0), signedSize, &length,
                signedSize ? source.data() : nullptr);
            if(U(2) && !WriteGuestArray(U(2), &length, 1)) return 0;
            if(signedSize) {
                const size_t written = std::min(
                    static_cast<size_t>(signedSize),
                    length >= 0 ? static_cast<size_t>(length) + 1 : size_t{0});
                WriteGuestArray(U(3), source.data(), written);
            }
            return 0;
        }
        case LC32OpenGLESOpGetTexParameterfv:
        case LC32OpenGLESOpGetTexParameteriv: {
            REQUIRE(3);
            const size_t count = TextureParameterElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetTexParameterfv) {
                std::vector<GLfloat> values(count);
                glGetTexParameterfv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLint> values(count);
                glGetTexParameteriv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetClipPlanef:
        case LC32OpenGLESOpGetClipPlanex: {
            REQUIRE(2);
            if(opcode == LC32OpenGLESOpGetClipPlanef) {
                GLfloat values[4] = {};
                glGetClipPlanef(U(0), values);
                WriteGuestArray(U(1), values, 4);
            } else {
                GLfixed values[4] = {};
                glGetClipPlanex(U(0), values);
                WriteGuestArray(U(1), values, 4);
            }
            return 0;
        }
        case LC32OpenGLESOpGetLightfv:
        case LC32OpenGLESOpGetLightxv: {
            REQUIRE(3);
            const size_t count = LightElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetLightfv) {
                std::vector<GLfloat> values(count);
                glGetLightfv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLfixed> values(count);
                glGetLightxv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetMaterialfv:
        case LC32OpenGLESOpGetMaterialxv: {
            REQUIRE(3);
            const size_t count = MaterialElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetMaterialfv) {
                std::vector<GLfloat> values(count);
                glGetMaterialfv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLfixed> values(count);
                glGetMaterialxv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetTexEnvfv:
        case LC32OpenGLESOpGetTexEnviv:
        case LC32OpenGLESOpGetTexEnvxv: {
            REQUIRE(3);
            const size_t count = TextureEnvironmentElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetTexEnvfv) {
                std::vector<GLfloat> values(count);
                glGetTexEnvfv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else if(opcode == LC32OpenGLESOpGetTexEnviv) {
                std::vector<GLint> values(count);
                glGetTexEnviv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLfixed> values(count);
                glGetTexEnvxv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetTexParameterxv: {
            REQUIRE(3);
            const size_t count = TextureParameterElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<GLfixed> values(count);
            glGetTexParameterxv(U(0), U(1), values.data());
            WriteGuestArray(U(2), values.data(), count);
            return 0;
        }
        case LC32OpenGLESOpGetPointerv: {
            REQUIRE(2);
            const GLenum bindingPname = ClientPointerBufferBinding(U(0));
            if(!bindingPname) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            uint32_t guestPointer = 0;
            if(GuestClientPointer(U(0), guestPointer)) {
                WriteGuestArray(U(1), &guestPointer, 1);
                return 0;
            }
            GLvoid *nativePointer = nullptr;
            glGetPointerv(U(0), &nativePointer);
            GLint binding = 0;
            glGetIntegerv(bindingPname, &binding);
            const uintptr_t value = reinterpret_cast<uintptr_t>(nativePointer);
            if((!binding && value) || value > UINT32_MAX) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            guestPointer = static_cast<uint32_t>(value);
            WriteGuestArray(U(1), &guestPointer, 1);
            return 0;
        }
        case LC32OpenGLESOpGetUniformfv:
        case LC32OpenGLESOpGetUniformiv: {
            REQUIRE(3);
            const size_t count = UniformElementCount(U(0), I(1));
            if(!count) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetUniformfv) {
                std::vector<GLfloat> values(count);
                glGetUniformfv(U(0), I(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLint> values(count);
                glGetUniformiv(U(0), I(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetVertexAttribfv:
        case LC32OpenGLESOpGetVertexAttribiv: {
            REQUIRE(3);
            const size_t count = VertexAttribElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpGetVertexAttribfv) {
                std::vector<GLfloat> values(count);
                glGetVertexAttribfv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            } else {
                std::vector<GLint> values(count);
                glGetVertexAttribiv(U(0), U(1), values.data());
                WriteGuestArray(U(2), values.data(), count);
            }
            return 0;
        }
        case LC32OpenGLESOpGetVertexAttribPointerv: {
            REQUIRE(3);
            if(U(1) == GL_VERTEX_ATTRIB_ARRAY_POINTER) {
                uint32_t guestPointer;
                if(GuestVertexAttribPointer(U(0), guestPointer)) {
                    WriteGuestArray(U(2), &guestPointer, 1);
                    return 0;
                }
            }
            GLvoid *pointer = nullptr;
            glGetVertexAttribPointerv(U(0), U(1), &pointer);
            GLint binding = 0;
            glGetVertexAttribiv(U(0), GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING,
                &binding);
            const uintptr_t value = reinterpret_cast<uintptr_t>(pointer);
            if((!binding && value) || value > UINT32_MAX) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            const uint32_t guestPointer = static_cast<uint32_t>(value);
            WriteGuestArray(U(2), &guestPointer, 1);
            return 0;
        }
        case LC32OpenGLESOpShaderSource: {
            REQUIRE(4);
            const int32_t signedCount = I(1);
            size_t count;
            if(!ReadCount(signedCount, 1, count)) return 0;
            std::vector<uint32_t> guestStrings;
            if(!ReadGuestArray(U(2), count, guestStrings)) return 0;
            std::vector<GLint> lengths;
            if(U(3) && !ReadGuestArray(U(3), count, lengths)) return 0;
            std::vector<std::string> storage(count);
            std::vector<const GLchar *> strings(count);
            size_t total = 0;
            for(size_t i = 0; i < count; ++i) {
                if(U(3) && lengths[i] >= 0) {
                    size_t length = static_cast<size_t>(lengths[i]);
                    if(length > kMaximumString || total > kMaximumString - length) {
                        SetBridgeError(GL_INVALID_VALUE);
                        return 0;
                    }
                    std::vector<char> bytes;
                    if(!ReadGuestArray(guestStrings[i], length, bytes)) return 0;
                    storage[i].assign(bytes.begin(), bytes.end());
                } else if(!ReadGuestCString(guestStrings[i], storage[i])) {
                    return 0;
                }
                total += storage[i].size();
                if(total > kMaximumString) { SetBridgeError(GL_INVALID_VALUE); return 0; }
                strings[i] = storage[i].c_str();
            }
            glShaderSource(U(0), signedCount, strings.data(),
                U(3) ? lengths.data() : nullptr);
            return 0;
        }
        case LC32OpenGLESOpCreateShaderProgramvEXT: {
            REQUIRE(3);
            size_t count;
            if(!ReadCount(I(1), 1, count)) return 0;
            std::vector<uint32_t> guestStrings;
            if(!ReadGuestArray(U(2), count, guestStrings)) return 0;
            std::vector<std::string> storage(count);
            std::vector<const GLchar *> strings(count);
            size_t total = 0;
            for(size_t i = 0; i < count; ++i) {
                if(!ReadGuestCString(guestStrings[i], storage[i])) return 0;
                if(storage[i].size() > kMaximumString - total) {
                    SetBridgeError(GL_INVALID_VALUE);
                    return 0;
                }
                total += storage[i].size();
                strings[i] = storage[i].c_str();
            }
            return glCreateShaderProgramvEXT(U(0), I(1), strings.data());
        }
        case LC32OpenGLESOpLabelObjectEXT: {
            REQUIRE(4);
            GLuint object = U(1);
            if(U(0) == GL_SYNC_OBJECT_APPLE &&
               !NativeSyncObjectName(U(1), object)) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            std::vector<GLchar> storage;
            const GLchar *label = nullptr;
            if(!ReadGuestGLString(I(2), U(3), storage, label)) return 0;
            glLabelObjectEXT(U(0), object, I(2), label);
            return 0;
        }
        case LC32OpenGLESOpInsertEventMarkerEXT:
        case LC32OpenGLESOpPushGroupMarkerEXT: {
            REQUIRE(2);
            std::vector<GLchar> storage;
            const GLchar *marker = nullptr;
            if(!ReadGuestGLString(I(0), U(1), storage, marker)) return 0;
            if(opcode == LC32OpenGLESOpInsertEventMarkerEXT)
                glInsertEventMarkerEXT(I(0), marker);
            else
                glPushGroupMarkerEXT(I(0), marker);
            return 0;
        }
        case LC32OpenGLESOpReadPixels: {
            REQUIRE(7);
            GLint packBuffer = 0;
            if(CurrentContextIsES3())
                glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &packBuffer);
            if(packBuffer) {
                glReadPixels(I(0), I(1), I(2), I(3), U(4), U(5),
                    reinterpret_cast<void *>(
                        static_cast<uintptr_t>(U(6))));
                return 0;
            }
            GLint alignment = 4;
            glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
            GLint rowLength = 0, skipPixels = 0, skipRows = 0;
            if(CurrentContextIsES3()) {
                glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength);
                glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels);
                glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows);
            }
            size_t byteCount;
            size_t rowBytes;
            size_t rowStride;
            size_t dataOffset;
            GLenum sizeError;
            if(!PixelVolumeSize(I(2), I(3), 1, U(4), U(5), alignment,
                    rowLength, 0, skipPixels, skipRows, 0, byteCount,
                    sizeError, &rowBytes, &rowStride, &dataOffset)) {
                SetBridgeError(sizeError);
                return 0;
            }
            std::vector<uint8_t> pixels(byteCount);
            glReadPixels(I(0), I(1), I(2), I(3), U(4), U(5),
                byteCount ? pixels.data() : nullptr);
            if(rowBytes) {
                for(GLsizei row = 0; row < I(3); ++row) {
                    const size_t rowOffset = dataOffset +
                        static_cast<size_t>(row) * rowStride;
                    const uint64_t guestRow =
                        static_cast<uint64_t>(U(6)) + rowOffset;
                    if(guestRow > UINT32_MAX ||
                       !WriteGuestBytes(static_cast<uint32_t>(guestRow),
                           pixels.data() + rowOffset,
                           rowBytes)) return 0;
                }
            }
            return 0;
        }
        case LC32OpenGLESOpTexImage2D:
        case LC32OpenGLESOpTexSubImage2D: {
            const bool image = opcode == LC32OpenGLESOpTexImage2D;
            if(!RequireSlots(call, image ? 9 : 9)) return 0;
            const size_t widthSlot = image ? 3 : 4;
            const size_t heightSlot = image ? 4 : 5;
            const size_t formatSlot = image ? 6 : 6;
            const size_t typeSlot = image ? 7 : 7;
            const size_t pointerSlot = 8;
            GLint unpackBuffer = 0;
            if(CurrentContextIsES3())
                glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer);
            std::vector<uint8_t> pixels;
            const void *data = nullptr;
            if(unpackBuffer) {
                data = reinterpret_cast<const void *>(
                    static_cast<uintptr_t>(U(pointerSlot)));
            } else if(U(pointerSlot)) {
                GLint alignment = 4, rowLength = 0;
                GLint skipPixels = 0, skipRows = 0;
                glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
                if(CurrentContextIsES3()) {
                    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
                    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels);
                    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows);
                }
                size_t byteCount = 0;
                GLenum sizeError = GL_NO_ERROR;
                if(!PixelVolumeSize(I(widthSlot), I(heightSlot), 1,
                        U(formatSlot), U(typeSlot), alignment, rowLength, 0,
                        skipPixels, skipRows, 0, byteCount, sizeError)) {
                    SetBridgeError(sizeError);
                    return 0;
                }
                if(byteCount) {
                    if(!ReadGuestBytes(U(pointerSlot), byteCount, pixels))
                        return 0;
                    data = pixels.data();
                }
            } else if(!image && I(widthSlot) > 0 && I(heightSlot) > 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(image) {
                glTexImage2D(U(0), I(1), I(2), I(3), I(4), I(5),
                    U(6), U(7), data);
            } else {
                glTexSubImage2D(U(0), I(1), I(2), I(3), I(4), I(5),
                    U(6), U(7), data);
            }
            return 0;
        }
        case LC32OpenGLESOpTexParameterfv:
        case LC32OpenGLESOpTexParameteriv: {
            REQUIRE(3);
            size_t count = TextureParameterElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpTexParameterfv) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glTexParameterfv(U(0), U(1), values.data());
            } else {
                std::vector<GLint> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glTexParameteriv(U(0), U(1), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpShaderBinary: {
            REQUIRE(5);
            const int32_t signedCount = I(0);
            const int32_t signedLength = I(4);
            size_t shaderCount;
            if(!ReadCount(signedCount, 1, shaderCount) || signedLength < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            std::vector<GLuint> shaders;
            std::vector<uint8_t> binary;
            if(!ReadGuestArray(U(1), shaderCount, shaders) ||
               !ReadGuestBytes(U(3), static_cast<size_t>(signedLength), binary))
                return 0;
            glShaderBinary(signedCount, shaders.data(), U(2),
                signedLength ? binary.data() : nullptr, signedLength);
            return 0;
        }
        case LC32OpenGLESOpMapBufferOES:
            return DispatchMapBuffer(call, false);
        case LC32OpenGLESOpMapBufferRangeEXT:
            return DispatchMapBuffer(call, true);
        case LC32OpenGLESOpFlushMappedBufferRangeEXT: {
            REQUIRE(3);
            const int32_t signedOffset = I(1);
            const int32_t signedLength = I(2);
            if(signedOffset < 0 || signedLength < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            GLuint buffer = 0;
            if(!BoundBuffer(U(0), buffer)) {
                SetBridgeError(BufferBindingPname(U(0))
                    ? GL_INVALID_OPERATION : GL_INVALID_ENUM);
                return 0;
            }
            const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
            std::lock_guard<std::mutex> lock(mappedBufferMutex);
            auto mapped = FindMappedBufferLocked(sharegroupKey,
                U(0), buffer);
            if(mapped == mappedBuffers.end()) {
                glFlushMappedBufferRangeEXT(U(0), signedOffset,
                    signedLength);
                return 0;
            }
            const size_t offset = static_cast<size_t>(signedOffset);
            const size_t length = static_cast<size_t>(signedLength);
            if(offset > mapped->length || length > mapped->length - offset) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(mapped->writable && mapped->flushExplicit && length) {
                std::vector<uint8_t> bytes;
                if(!ReadGuestBytes(mapped->guestPointer +
                        static_cast<uint32_t>(offset), length, bytes)) return 0;
                memcpy(static_cast<uint8_t *>(mapped->nativePointer) + offset,
                    bytes.data(), length);
            }
            glFlushMappedBufferRangeEXT(U(0), signedOffset, signedLength);
            return 0;
        }
        case LC32OpenGLESOpUnmapBufferOES: {
            REQUIRE(2);
            uint32_t guestPointer = 0;
            GLuint buffer = 0;
            if(!BoundBuffer(U(0), buffer)) {
                SetBridgeError(BufferBindingPname(U(0))
                    ? GL_INVALID_OPERATION : GL_INVALID_ENUM);
                WriteGuestArray(U(1), &guestPointer, 1);
                return GL_FALSE;
            }
            bool copySucceeded = true;
            GLboolean result = GL_FALSE;
            const uintptr_t sharegroupKey = CurrentGLSharegroupKey();
            {
                std::lock_guard<std::mutex> lock(mappedBufferMutex);
                auto mapped = FindMappedBufferLocked(sharegroupKey, U(0),
                    buffer);
                if(mapped != mappedBuffers.end()) {
                    guestPointer = mapped->guestPointer;
                    if(mapped->writable && !mapped->flushExplicit &&
                       mapped->length) {
                        std::vector<uint8_t> bytes;
                        copySucceeded = ReadGuestBytes(mapped->guestPointer,
                            mapped->length, bytes);
                        if(copySucceeded)
                            memcpy(mapped->nativePointer, bytes.data(),
                                mapped->length);
                    }
                    mappedBuffers.erase(mapped);
                }
                result = glUnmapBufferOES(U(0));
            }
            WriteGuestArray(U(1), &guestPointer, 1);
            return copySucceeded ? result : GL_FALSE;
        }
        case LC32OpenGLESOpSamplerParameterfv:
        case LC32OpenGLESOpSamplerParameteriv: {
            REQUIRE(3);
            const size_t count = SamplerParameterElementCount(U(1));
            if(!count) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            if(opcode == LC32OpenGLESOpSamplerParameterfv) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glSamplerParameterfv(U(0), U(1), values.data());
            } else {
                std::vector<GLint> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glSamplerParameteriv(U(0), U(1), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpTexImage3D:
        case LC32OpenGLESOpTexSubImage3D: {
            const bool image = opcode == LC32OpenGLESOpTexImage3D;
            if(!RequireSlots(call, image ? 10 : 11)) return 0;
            const size_t widthSlot = image ? 3 : 5;
            const size_t heightSlot = image ? 4 : 6;
            const size_t depthSlot = image ? 5 : 7;
            const size_t formatSlot = image ? 7 : 8;
            const size_t typeSlot = image ? 8 : 9;
            const size_t pointerSlot = image ? 9 : 10;
            GLint unpackBuffer = 0;
            glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBuffer);
            std::vector<uint8_t> pixels;
            const void *data = nullptr;
            if(unpackBuffer) {
                data = reinterpret_cast<const void *>(
                    static_cast<uintptr_t>(U(pointerSlot)));
            } else if(U(pointerSlot)) {
                GLint alignment = 4, rowLength = 0, imageHeight = 0;
                GLint skipPixels = 0, skipRows = 0, skipImages = 0;
                glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
                glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
                glGetIntegerv(GL_UNPACK_IMAGE_HEIGHT, &imageHeight);
                glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels);
                glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows);
                glGetIntegerv(GL_UNPACK_SKIP_IMAGES, &skipImages);
                size_t byteCount = 0;
                GLenum sizeError = GL_NO_ERROR;
                if(!PixelVolumeSize(I(widthSlot), I(heightSlot), I(depthSlot),
                        U(formatSlot), U(typeSlot), alignment, rowLength,
                        imageHeight, skipPixels, skipRows, skipImages,
                        byteCount, sizeError)) {
                    SetBridgeError(sizeError);
                    return 0;
                }
                if(!ReadGuestBytes(U(pointerSlot), byteCount, pixels)) return 0;
                data = pixels.data();
            } else if(!image && I(widthSlot) > 0 && I(heightSlot) > 0 &&
                      I(depthSlot) > 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            if(image) {
                glTexImage3D(U(0), I(1), I(2), I(3), I(4), I(5), I(6),
                    U(7), U(8), data);
            } else {
                glTexSubImage3D(U(0), I(1), I(2), I(3), I(4), I(5), I(6),
                    I(7), U(8), U(9), data);
            }
            return 0;
        }
        case LC32OpenGLESOpTransformFeedbackVaryings: {
            REQUIRE(4);
            size_t count;
            if(!ReadCount(I(1), 1, count)) return 0;
            std::vector<uint32_t> guestNames;
            if(!ReadGuestArray(U(2), count, guestNames)) return 0;
            std::vector<std::string> storage(count);
            std::vector<const GLchar *> names(count);
            size_t total = 0;
            for(size_t i = 0; i < count; ++i) {
                if(!ReadGuestCString(guestNames[i], storage[i])) return 0;
                if(storage[i].size() > kMaximumString - total) {
                    SetBridgeError(GL_INVALID_VALUE);
                    return 0;
                }
                total += storage[i].size();
                names[i] = storage[i].c_str();
            }
            glTransformFeedbackVaryings(U(0), I(1), names.data(), U(3));
            return 0;
        }
        case LC32OpenGLESOpVertexAttribI4iv:
        case LC32OpenGLESOpVertexAttribI4uiv: {
            REQUIRE(2);
            if(opcode == LC32OpenGLESOpVertexAttribI4iv) {
                std::vector<GLint> values;
                if(!ReadGuestArray(U(1), 4, values)) return 0;
                glVertexAttribI4iv(U(0), values.data());
            } else {
                std::vector<GLuint> values;
                if(!ReadGuestArray(U(1), 4, values)) return 0;
                glVertexAttribI4uiv(U(0), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpVertexAttribIPointer: {
            REQUIRE(5);
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
            if(!ClientMemoryPointerAllowed(binding, U(4))) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            const bool valid = VertexAttribDescriptorValid(U(0), I(1), U(2),
                I(3), true);
            if(!valid) {
                glVertexAttribIPointer(U(0), I(1), U(2), I(3), binding
                    ? reinterpret_cast<const void *>(
                        static_cast<uintptr_t>(U(4)))
                    : nullptr);
                return 0;
            }
            if(!binding) {
                ClientArrayDescriptor descriptor;
                descriptor.kind = ClientArrayKind::VertexAttrib;
                descriptor.index = U(0);
                descriptor.size = I(1);
                descriptor.type = U(2);
                descriptor.stride = I(3);
                descriptor.guestPointer = U(4);
                descriptor.integer = true;
                descriptor.valid = true;
                RememberVertexAttribPointer(&descriptor, descriptor.index);
                glVertexAttribIPointer(descriptor.index, descriptor.size,
                    descriptor.type, descriptor.stride, nullptr);
                return 0;
            }
            RememberVertexAttribPointer(nullptr, U(0));
            glVertexAttribIPointer(U(0), I(1), U(2), I(3),
                reinterpret_cast<const void *>(
                    static_cast<uintptr_t>(U(4))));
            return 0;
        }
        case LC32OpenGLESOpUniform1fv:
            return DispatchInputArray<GLfloat>(call, 1,
                [](GLint l, GLsizei c, const GLfloat *v) { glUniform1fv(l, c, v); });
        case LC32OpenGLESOpUniform2fv:
            return DispatchInputArray<GLfloat>(call, 2,
                [](GLint l, GLsizei c, const GLfloat *v) { glUniform2fv(l, c, v); });
        case LC32OpenGLESOpUniform3fv:
            return DispatchInputArray<GLfloat>(call, 3,
                [](GLint l, GLsizei c, const GLfloat *v) { glUniform3fv(l, c, v); });
        case LC32OpenGLESOpUniform4fv:
            return DispatchInputArray<GLfloat>(call, 4,
                [](GLint l, GLsizei c, const GLfloat *v) { glUniform4fv(l, c, v); });
        case LC32OpenGLESOpUniform1iv:
            return DispatchInputArray<GLint>(call, 1,
                [](GLint l, GLsizei c, const GLint *v) { glUniform1iv(l, c, v); });
        case LC32OpenGLESOpUniform2iv:
            return DispatchInputArray<GLint>(call, 2,
                [](GLint l, GLsizei c, const GLint *v) { glUniform2iv(l, c, v); });
        case LC32OpenGLESOpUniform3iv:
            return DispatchInputArray<GLint>(call, 3,
                [](GLint l, GLsizei c, const GLint *v) { glUniform3iv(l, c, v); });
        case LC32OpenGLESOpUniform4iv:
            return DispatchInputArray<GLint>(call, 4,
                [](GLint l, GLsizei c, const GLint *v) { glUniform4iv(l, c, v); });
        case LC32OpenGLESOpUniform1uiv:
            return DispatchInputArray<GLuint>(call, 1,
                [](GLint l, GLsizei c, const GLuint *v) { glUniform1uiv(l, c, v); });
        case LC32OpenGLESOpUniform2uiv:
            return DispatchInputArray<GLuint>(call, 2,
                [](GLint l, GLsizei c, const GLuint *v) { glUniform2uiv(l, c, v); });
        case LC32OpenGLESOpUniform3uiv:
            return DispatchInputArray<GLuint>(call, 3,
                [](GLint l, GLsizei c, const GLuint *v) { glUniform3uiv(l, c, v); });
        case LC32OpenGLESOpUniform4uiv:
            return DispatchInputArray<GLuint>(call, 4,
                [](GLint l, GLsizei c, const GLuint *v) { glUniform4uiv(l, c, v); });
        case LC32OpenGLESOpProgramUniform1fvEXT:
            return DispatchProgramUniformArray<GLfloat>(call, 1,
                [](GLuint p, GLint l, GLsizei c, const GLfloat *v) {
                    glProgramUniform1fvEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform2fvEXT:
            return DispatchProgramUniformArray<GLfloat>(call, 2,
                [](GLuint p, GLint l, GLsizei c, const GLfloat *v) {
                    glProgramUniform2fvEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform3fvEXT:
            return DispatchProgramUniformArray<GLfloat>(call, 3,
                [](GLuint p, GLint l, GLsizei c, const GLfloat *v) {
                    glProgramUniform3fvEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform4fvEXT:
            return DispatchProgramUniformArray<GLfloat>(call, 4,
                [](GLuint p, GLint l, GLsizei c, const GLfloat *v) {
                    glProgramUniform4fvEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform1ivEXT:
            return DispatchProgramUniformArray<GLint>(call, 1,
                [](GLuint p, GLint l, GLsizei c, const GLint *v) {
                    glProgramUniform1ivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform2ivEXT:
            return DispatchProgramUniformArray<GLint>(call, 2,
                [](GLuint p, GLint l, GLsizei c, const GLint *v) {
                    glProgramUniform2ivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform3ivEXT:
            return DispatchProgramUniformArray<GLint>(call, 3,
                [](GLuint p, GLint l, GLsizei c, const GLint *v) {
                    glProgramUniform3ivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform4ivEXT:
            return DispatchProgramUniformArray<GLint>(call, 4,
                [](GLuint p, GLint l, GLsizei c, const GLint *v) {
                    glProgramUniform4ivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform1uivEXT:
            return DispatchProgramUniformArray<GLuint>(call, 1,
                [](GLuint p, GLint l, GLsizei c, const GLuint *v) {
                    glProgramUniform1uivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform2uivEXT:
            return DispatchProgramUniformArray<GLuint>(call, 2,
                [](GLuint p, GLint l, GLsizei c, const GLuint *v) {
                    glProgramUniform2uivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform3uivEXT:
            return DispatchProgramUniformArray<GLuint>(call, 3,
                [](GLuint p, GLint l, GLsizei c, const GLuint *v) {
                    glProgramUniform3uivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpProgramUniform4uivEXT:
            return DispatchProgramUniformArray<GLuint>(call, 4,
                [](GLuint p, GLint l, GLsizei c, const GLuint *v) {
                    glProgramUniform4uivEXT(p, l, c, v);
                });
        case LC32OpenGLESOpUniformMatrix2fv:
        case LC32OpenGLESOpUniformMatrix3fv:
        case LC32OpenGLESOpUniformMatrix4fv: {
            REQUIRE(4);
            size_t side = opcode == LC32OpenGLESOpUniformMatrix2fv ? 2 :
                          opcode == LC32OpenGLESOpUniformMatrix3fv ? 3 : 4;
            size_t count;
            if(!ReadCount(I(1), side * side, count)) return 0;
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(3), count, values)) return 0;
            if(side == 2) glUniformMatrix2fv(I(0), I(1), U(2), values.data());
            else if(side == 3) glUniformMatrix3fv(I(0), I(1), U(2), values.data());
            else glUniformMatrix4fv(I(0), I(1), U(2), values.data());
            return 0;
        }
        case LC32OpenGLESOpProgramUniformMatrix2fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix3fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix4fvEXT: {
            REQUIRE(5);
            const size_t side =
                opcode == LC32OpenGLESOpProgramUniformMatrix2fvEXT ? 2 :
                opcode == LC32OpenGLESOpProgramUniformMatrix3fvEXT ? 3 : 4;
            size_t elementCount;
            if(!ReadCount(I(2), side * side, elementCount)) return 0;
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(4), elementCount, values)) return 0;
            if(side == 2)
                glProgramUniformMatrix2fvEXT(U(0), I(1), I(2), U(3),
                    values.data());
            else if(side == 3)
                glProgramUniformMatrix3fvEXT(U(0), I(1), I(2), U(3),
                    values.data());
            else
                glProgramUniformMatrix4fvEXT(U(0), I(1), I(2), U(3),
                    values.data());
            return 0;
        }
        case LC32OpenGLESOpUniformMatrix2x3fv:
        case LC32OpenGLESOpUniformMatrix2x4fv:
        case LC32OpenGLESOpUniformMatrix3x2fv:
        case LC32OpenGLESOpUniformMatrix3x4fv:
        case LC32OpenGLESOpUniformMatrix4x2fv:
        case LC32OpenGLESOpUniformMatrix4x3fv: {
            REQUIRE(4);
            size_t width = 0, height = 0;
            if(opcode == LC32OpenGLESOpUniformMatrix2x3fv) {
                width = 2; height = 3;
            } else if(opcode == LC32OpenGLESOpUniformMatrix2x4fv) {
                width = 2; height = 4;
            } else if(opcode == LC32OpenGLESOpUniformMatrix3x2fv) {
                width = 3; height = 2;
            } else if(opcode == LC32OpenGLESOpUniformMatrix3x4fv) {
                width = 3; height = 4;
            } else if(opcode == LC32OpenGLESOpUniformMatrix4x2fv) {
                width = 4; height = 2;
            } else {
                width = 4; height = 3;
            }
            size_t elementCount;
            if(!ReadCount(I(1), width * height, elementCount)) return 0;
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(3), elementCount, values)) return 0;
            if(width == 2 && height == 3)
                glUniformMatrix2x3fv(I(0), I(1), U(2), values.data());
            else if(width == 2 && height == 4)
                glUniformMatrix2x4fv(I(0), I(1), U(2), values.data());
            else if(width == 3 && height == 2)
                glUniformMatrix3x2fv(I(0), I(1), U(2), values.data());
            else if(width == 3 && height == 4)
                glUniformMatrix3x4fv(I(0), I(1), U(2), values.data());
            else if(width == 4 && height == 2)
                glUniformMatrix4x2fv(I(0), I(1), U(2), values.data());
            else
                glUniformMatrix4x3fv(I(0), I(1), U(2), values.data());
            return 0;
        }
        case LC32OpenGLESOpProgramUniformMatrix2x3fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix2x4fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix3x2fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix3x4fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix4x2fvEXT:
        case LC32OpenGLESOpProgramUniformMatrix4x3fvEXT: {
            REQUIRE(5);
            size_t width = 0, height = 0;
            if(opcode == LC32OpenGLESOpProgramUniformMatrix2x3fvEXT) {
                width = 2; height = 3;
            } else if(opcode ==
                    LC32OpenGLESOpProgramUniformMatrix2x4fvEXT) {
                width = 2; height = 4;
            } else if(opcode ==
                    LC32OpenGLESOpProgramUniformMatrix3x2fvEXT) {
                width = 3; height = 2;
            } else if(opcode ==
                    LC32OpenGLESOpProgramUniformMatrix3x4fvEXT) {
                width = 3; height = 4;
            } else if(opcode ==
                    LC32OpenGLESOpProgramUniformMatrix4x2fvEXT) {
                width = 4; height = 2;
            } else {
                width = 4; height = 3;
            }
            size_t elementCount;
            if(!ReadCount(I(2), width * height, elementCount)) return 0;
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(4), elementCount, values)) return 0;
            if(width == 2 && height == 3)
                glProgramUniformMatrix2x3fvEXT(U(0), I(1), I(2), U(3), values.data());
            else if(width == 2 && height == 4)
                glProgramUniformMatrix2x4fvEXT(U(0), I(1), I(2), U(3), values.data());
            else if(width == 3 && height == 2)
                glProgramUniformMatrix3x2fvEXT(U(0), I(1), I(2), U(3), values.data());
            else if(width == 3 && height == 4)
                glProgramUniformMatrix3x4fvEXT(U(0), I(1), I(2), U(3), values.data());
            else if(width == 4 && height == 2)
                glProgramUniformMatrix4x2fvEXT(U(0), I(1), I(2), U(3), values.data());
            else
                glProgramUniformMatrix4x3fvEXT(U(0), I(1), I(2), U(3), values.data());
            return 0;
        }
        case LC32OpenGLESOpDrawRangeElements: {
            REQUIRE(6);
            const int32_t count = I(3);
            if(count < 0 || U(2) < U(1)) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            GLint binding = 0;
            glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &binding);
            if(binding) {
                if(!EnabledClientArrays().empty()) {
                    SetBridgeError(GL_INVALID_OPERATION);
                    return 0;
                }
                glDrawRangeElements(U(0), U(1), U(2), count, U(4),
                    reinterpret_cast<const void *>(
                        static_cast<uintptr_t>(U(5))));
                return 0;
            }
            const size_t elementSize = IndexElementSize(U(4));
            size_t byteCount;
            if(!elementSize || !ReadCount(count, elementSize, byteCount)) {
                SetBridgeError(!elementSize ? GL_INVALID_ENUM : GL_INVALID_VALUE);
                return 0;
            }
            std::vector<uint8_t> indices;
            if(!ReadGuestBytes(U(5), byteCount, indices)) return 0;
            if(!count) {
                glDrawRangeElements(U(0), U(1), U(2), count, U(4), nullptr);
                return 0;
            }
            size_t maximumIndex;
            bool hasIndex;
            if(!MaximumIndex(U(4), indices, maximumIndex, hasIndex)) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<StagedClientArray> staged;
            if(hasIndex && !StageClientArrays(maximumIndex, staged)) return 0;
            glDrawRangeElements(U(0), U(1), U(2), count, U(4),
                indices.data());
            return 0;
        }
        case LC32OpenGLESOpDrawElements: {
            REQUIRE(4);
            GLint binding = 0;
            glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &binding);
            if(binding) {
                if(!EnabledClientArrays().empty()) {
                    /*
                     * An element-buffer offset does not expose its indices to
                     * the bridge, so there is no safe upper bound for copying
                     * guest client arrays. Buffer-backed attributes still use
                     * this path normally.
                     */
                    SetBridgeError(GL_INVALID_OPERATION);
                    return 0;
                }
                glDrawElements(U(0), I(1), U(2),
                    reinterpret_cast<const void *>(static_cast<uintptr_t>(U(3))));
                return 0;
            }
            size_t elementSize = IndexElementSize(U(2));
            size_t count;
            if(!elementSize || !ReadCount(I(1), elementSize, count)) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<uint8_t> indices;
            if(!ReadGuestBytes(U(3), count, indices)) return 0;
            if(I(1) == 0) {
                glDrawElements(U(0), I(1), U(2), nullptr);
                return 0;
            }
            size_t maximumIndex;
            bool hasIndex;
            if(!MaximumIndex(U(2), indices, maximumIndex, hasIndex)) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<StagedClientArray> staged;
            if(hasIndex && !StageClientArrays(maximumIndex, staged)) return 0;
            glDrawElements(U(0), I(1), U(2), indices.data());
            return 0;
        }
        case LC32OpenGLESOpDrawElementsInstancedEXT: {
            REQUIRE(5);
            const int32_t count = I(1);
            const int32_t instanceCount = I(4);
            if(count < 0 || instanceCount < 0) {
                SetBridgeError(GL_INVALID_VALUE);
                return 0;
            }
            GLint binding = 0;
            glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &binding);
            if(!count || !instanceCount) {
                const void *indices = binding
                    ? reinterpret_cast<const void *>(
                        static_cast<uintptr_t>(U(3)))
                    : nullptr;
                glDrawElementsInstancedEXT(U(0), count, U(2), indices,
                    instanceCount);
                return 0;
            }
            if(binding) {
                if(!EnabledClientArrays().empty()) {
                    SetBridgeError(GL_INVALID_OPERATION);
                    return 0;
                }
                glDrawElementsInstancedEXT(U(0), count, U(2),
                    reinterpret_cast<const void *>(
                        static_cast<uintptr_t>(U(3))), instanceCount);
                return 0;
            }
            const size_t elementSize = IndexElementSize(U(2));
            size_t byteCount;
            if(!elementSize || !ReadCount(count, elementSize, byteCount)) {
                SetBridgeError(!elementSize ? GL_INVALID_ENUM : GL_INVALID_VALUE);
                return 0;
            }
            std::vector<uint8_t> indices;
            if(!ReadGuestBytes(U(3), byteCount, indices)) return 0;
            size_t maximumIndex;
            bool hasIndex;
            if(!MaximumIndex(U(2), indices, maximumIndex, hasIndex)) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<StagedClientArray> staged;
            if(hasIndex && !StageClientArrays(maximumIndex,
                    static_cast<size_t>(instanceCount), staged)) return 0;
            glDrawElementsInstancedEXT(U(0), count, U(2), indices.data(),
                instanceCount);
            return 0;
        }
        case LC32OpenGLESOpVertexAttribPointer: {
            REQUIRE(6);
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
            if(!ClientMemoryPointerAllowed(binding, U(5))) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            const bool valid = VertexAttribDescriptorValid(U(0), I(1), U(2),
                I(4), false);
            if(!valid) {
                glVertexAttribPointer(U(0), I(1), U(2), U(3), I(4), binding
                    ? reinterpret_cast<const void *>(
                        static_cast<uintptr_t>(U(5)))
                    : nullptr);
                return 0;
            }
            if(!binding) {
                ClientArrayDescriptor descriptor;
                descriptor.kind = ClientArrayKind::VertexAttrib;
                descriptor.index = U(0);
                descriptor.size = I(1);
                descriptor.type = U(2);
                descriptor.normalized = static_cast<GLboolean>(U(3));
                descriptor.stride = I(4);
                descriptor.guestPointer = U(5);
                descriptor.valid = true;
                RememberVertexAttribPointer(&descriptor, descriptor.index);
                /* Preserve the host-side metadata without retaining a guest
                 * address that is meaningless in the host address space. */
                glVertexAttribPointer(descriptor.index, descriptor.size,
                    descriptor.type, descriptor.normalized,
                    descriptor.stride, nullptr);
                return 0;
            }
            RememberVertexAttribPointer(nullptr, U(0));
            glVertexAttribPointer(U(0), I(1), U(2), U(3), I(4),
                reinterpret_cast<const void *>(static_cast<uintptr_t>(U(5))));
            return 0;
        }
        case LC32OpenGLESOpVertexAttrib1fv:
        case LC32OpenGLESOpVertexAttrib2fv:
        case LC32OpenGLESOpVertexAttrib3fv:
        case LC32OpenGLESOpVertexAttrib4fv: {
            REQUIRE(2);
            const size_t count =
                static_cast<size_t>(opcode - LC32OpenGLESOpVertexAttrib1fv) + 1;
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(1), count, values)) return 0;
            switch(count) {
                case 1: glVertexAttrib1fv(U(0), values.data()); break;
                case 2: glVertexAttrib2fv(U(0), values.data()); break;
                case 3: glVertexAttrib3fv(U(0), values.data()); break;
                case 4: glVertexAttrib4fv(U(0), values.data()); break;
            }
            return 0;
        }
        case LC32OpenGLESOpFogfv: {
            REQUIRE(2);
            const size_t count = FogElementCount(U(0));
            if(!count) {
                const GLfloat dummy[4] = {};
                glFogfv(U(0), dummy);
                return 0;
            }
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(1), count, values)) return 0;
            glFogfv(U(0), values.data());
            return 0;
        }
        case LC32OpenGLESOpFogxv: {
            REQUIRE(2);
            const size_t count = FogElementCount(U(0));
            if(!count) {
                const GLfixed dummy[4] = {};
                glFogxv(U(0), dummy);
                return 0;
            }
            std::vector<GLfixed> values;
            if(!ReadGuestArray(U(1), count, values)) return 0;
            glFogxv(U(0), values.data());
            return 0;
        }
        case LC32OpenGLESOpClipPlanef:
        case LC32OpenGLESOpClipPlanex: {
            REQUIRE(2);
            if(opcode == LC32OpenGLESOpClipPlanef) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(1), 4, values)) return 0;
                glClipPlanef(U(0), values.data());
            } else {
                std::vector<GLfixed> values;
                if(!ReadGuestArray(U(1), 4, values)) return 0;
                glClipPlanex(U(0), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpLightfv: {
            REQUIRE(3);
            const size_t count = LightElementCount(U(1));
            if(!count) {
                const GLfloat dummy[4] = {};
                glLightfv(U(0), U(1), dummy);
                return 0;
            }
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glLightfv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpLightxv: {
            REQUIRE(3);
            const size_t count = LightElementCount(U(1));
            if(!count) {
                const GLfixed dummy[4] = {};
                glLightxv(U(0), U(1), dummy);
                return 0;
            }
            std::vector<GLfixed> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glLightxv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpMaterialfv: {
            REQUIRE(3);
            const size_t count = MaterialElementCount(U(1));
            if(!count) {
                const GLfloat dummy[4] = {};
                glMaterialfv(U(0), U(1), dummy);
                return 0;
            }
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glMaterialfv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpMaterialxv: {
            REQUIRE(3);
            const size_t count = MaterialElementCount(U(1));
            if(!count) {
                const GLfixed dummy[4] = {};
                glMaterialxv(U(0), U(1), dummy);
                return 0;
            }
            std::vector<GLfixed> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glMaterialxv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpLightModelfv:
        case LC32OpenGLESOpLightModelxv: {
            REQUIRE(2);
            const size_t count = LightModelElementCount(U(0));
            if(!count) {
                if(opcode == LC32OpenGLESOpLightModelfv) {
                    const GLfloat dummy[4] = {};
                    glLightModelfv(U(0), dummy);
                } else {
                    const GLfixed dummy[4] = {};
                    glLightModelxv(U(0), dummy);
                }
                return 0;
            }
            if(opcode == LC32OpenGLESOpLightModelfv) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(1), count, values)) return 0;
                glLightModelfv(U(0), values.data());
            } else {
                std::vector<GLfixed> values;
                if(!ReadGuestArray(U(1), count, values)) return 0;
                glLightModelxv(U(0), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpPointParameterfv:
        case LC32OpenGLESOpPointParameterxv: {
            REQUIRE(2);
            const size_t count = PointParameterElementCount(U(0));
            if(!count) {
                if(opcode == LC32OpenGLESOpPointParameterfv) {
                    const GLfloat dummy[3] = {};
                    glPointParameterfv(U(0), dummy);
                } else {
                    const GLfixed dummy[3] = {};
                    glPointParameterxv(U(0), dummy);
                }
                return 0;
            }
            if(opcode == LC32OpenGLESOpPointParameterfv) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(1), count, values)) return 0;
                glPointParameterfv(U(0), values.data());
            } else {
                std::vector<GLfixed> values;
                if(!ReadGuestArray(U(1), count, values)) return 0;
                glPointParameterxv(U(0), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpClientActiveTexture: {
            REQUIRE(1);
            glClientActiveTexture(U(0));
            GLint activeTexture = GL_TEXTURE0;
            glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE, &activeTexture);
            SetClientActiveTexture((GLenum)activeTexture);
            return 0;
        }
        case LC32OpenGLESOpNormalPointer: {
            REQUIRE(3);
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
            if(!ClientMemoryPointerAllowed(binding, U(2))) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            if(!FixedClientDescriptorValid(ClientArrayKind::Normal, 3, U(0),
                    I(1))) {
                glNormalPointer(U(0), I(1), binding
                    ? reinterpret_cast<const GLvoid *>(
                        static_cast<uintptr_t>(U(2)))
                    : nullptr);
                return 0;
            }
            if(!binding) {
                ClientArrayDescriptor descriptor;
                descriptor.kind = ClientArrayKind::Normal;
                descriptor.size = 3;
                descriptor.type = U(0);
                descriptor.stride = I(1);
                descriptor.guestPointer = U(2);
                descriptor.valid = true;
                RememberClientPointer(&descriptor, ClientArrayKind::Normal);
                glNormalPointer(U(0), I(1), nullptr);
                return 0;
            }
            RememberClientPointer(nullptr, ClientArrayKind::Normal);
            const GLvoid *pointer = reinterpret_cast<const GLvoid *>(
                static_cast<uintptr_t>(U(2)));
            glNormalPointer(U(0), I(1), pointer);
            return 0;
        }
        case LC32OpenGLESOpTexEnvi: {
            REQUIRE(3);
            glTexEnvi(U(0), U(1), I(2));
            return 0;
        }
        case LC32OpenGLESOpTexEnvf: {
            REQUIRE(3);
            glTexEnvf(U(0), U(1), F(2));
            return 0;
        }
        case LC32OpenGLESOpTexEnvfv: {
            REQUIRE(3);
            const size_t count = TextureEnvironmentElementCount(U(1));
            if(!count) {
                const GLfloat dummy[4] = {};
                glTexEnvfv(U(0), U(1), dummy);
                return 0;
            }
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glTexEnvfv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpTexEnviv:
        case LC32OpenGLESOpTexEnvxv: {
            REQUIRE(3);
            const size_t count = TextureEnvironmentElementCount(U(1));
            if(!count) {
                if(opcode == LC32OpenGLESOpTexEnviv) {
                    const GLint dummy[4] = {};
                    glTexEnviv(U(0), U(1), dummy);
                } else {
                    const GLfixed dummy[4] = {};
                    glTexEnvxv(U(0), U(1), dummy);
                }
                return 0;
            }
            if(opcode == LC32OpenGLESOpTexEnviv) {
                std::vector<GLint> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glTexEnviv(U(0), U(1), values.data());
            } else {
                std::vector<GLfixed> values;
                if(!ReadGuestArray(U(2), count, values)) return 0;
                glTexEnvxv(U(0), U(1), values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpTexParameterxv: {
            REQUIRE(3);
            const size_t count = TextureParameterElementCount(U(1));
            if(!count) {
                const GLfixed dummy[4] = {};
                glTexParameterxv(U(0), U(1), dummy);
                return 0;
            }
            std::vector<GLfixed> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glTexParameterxv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpMultMatrixf: {
            REQUIRE(1);
            std::vector<GLfloat> matrix;
            if(!ReadGuestArray(U(0), 16, matrix)) return 0;
            glMultMatrixf(matrix.data());
            return 0;
        }
        case LC32OpenGLESOpLoadMatrixf: {
            REQUIRE(1);
            std::vector<GLfloat> matrix;
            if(!ReadGuestArray(U(0), 16, matrix)) return 0;
            glLoadMatrixf(matrix.data());
            return 0;
        }
        case LC32OpenGLESOpMultMatrixx:
        case LC32OpenGLESOpLoadMatrixx: {
            REQUIRE(1);
            std::vector<GLfixed> matrix;
            if(!ReadGuestArray(U(0), 16, matrix)) return 0;
            if(opcode == LC32OpenGLESOpMultMatrixx)
                glMultMatrixx(matrix.data());
            else
                glLoadMatrixx(matrix.data());
            return 0;
        }
        case LC32OpenGLESOpDrawTexfvOES:
        case LC32OpenGLESOpDrawTexivOES:
        case LC32OpenGLESOpDrawTexsvOES:
        case LC32OpenGLESOpDrawTexxvOES: {
            REQUIRE(1);
            if(opcode == LC32OpenGLESOpDrawTexfvOES) {
                std::vector<GLfloat> values;
                if(!ReadGuestArray(U(0), 5, values)) return 0;
                glDrawTexfvOES(values.data());
            } else if(opcode == LC32OpenGLESOpDrawTexivOES) {
                std::vector<GLint> values;
                if(!ReadGuestArray(U(0), 5, values)) return 0;
                glDrawTexivOES(values.data());
            } else if(opcode == LC32OpenGLESOpDrawTexsvOES) {
                std::vector<GLshort> values;
                if(!ReadGuestArray(U(0), 5, values)) return 0;
                glDrawTexsvOES(values.data());
            } else {
                std::vector<GLfixed> values;
                if(!ReadGuestArray(U(0), 5, values)) return 0;
                glDrawTexxvOES(values.data());
            }
            return 0;
        }
        case LC32OpenGLESOpMatrixIndexPointerOES:
        case LC32OpenGLESOpWeightPointerOES: {
            REQUIRE(4);
            const ClientArrayKind kind =
                opcode == LC32OpenGLESOpMatrixIndexPointerOES
                    ? ClientArrayKind::MatrixIndex
                    : ClientArrayKind::Weight;
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
            if(!ClientMemoryPointerAllowed(binding, U(3))) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            if(!FixedClientDescriptorValid(kind, I(0), U(1), I(2))) {
                const GLvoid *pointer = binding
                    ? reinterpret_cast<const GLvoid *>(
                        static_cast<uintptr_t>(U(3)))
                    : nullptr;
                if(kind == ClientArrayKind::MatrixIndex)
                    glMatrixIndexPointerOES(I(0), U(1), I(2), pointer);
                else
                    glWeightPointerOES(I(0), U(1), I(2), pointer);
                return 0;
            }
            if(!binding) {
                ClientArrayDescriptor descriptor;
                descriptor.kind = kind;
                descriptor.size = I(0);
                descriptor.type = U(1);
                descriptor.stride = I(2);
                descriptor.guestPointer = U(3);
                descriptor.valid = true;
                RememberClientPointer(&descriptor, kind);
                if(kind == ClientArrayKind::MatrixIndex)
                    glMatrixIndexPointerOES(I(0), U(1), I(2), nullptr);
                else
                    glWeightPointerOES(I(0), U(1), I(2), nullptr);
                return 0;
            }
            RememberClientPointer(nullptr, kind);
            const GLvoid *pointer = reinterpret_cast<const GLvoid *>(
                static_cast<uintptr_t>(U(3)));
            if(kind == ClientArrayKind::MatrixIndex)
                glMatrixIndexPointerOES(I(0), U(1), I(2), pointer);
            else
                glWeightPointerOES(I(0), U(1), I(2), pointer);
            return 0;
        }
        case LC32OpenGLESOpPointSizePointerOES: {
            REQUIRE(3);
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
            if(!ClientMemoryPointerAllowed(binding, U(2))) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            if(!FixedClientDescriptorValid(ClientArrayKind::PointSize, 1,
                    U(0), I(1))) {
                glPointSizePointerOES(U(0), I(1), binding
                    ? reinterpret_cast<const GLvoid *>(
                        static_cast<uintptr_t>(U(2)))
                    : nullptr);
                return 0;
            }
            if(!binding) {
                ClientArrayDescriptor descriptor;
                descriptor.kind = ClientArrayKind::PointSize;
                descriptor.size = 1;
                descriptor.type = U(0);
                descriptor.stride = I(1);
                descriptor.guestPointer = U(2);
                descriptor.valid = true;
                RememberClientPointer(&descriptor,
                    ClientArrayKind::PointSize);
                glPointSizePointerOES(U(0), I(1), nullptr);
                return 0;
            }
            RememberClientPointer(nullptr, ClientArrayKind::PointSize);
            glPointSizePointerOES(U(0), I(1),
                reinterpret_cast<const GLvoid *>(
                    static_cast<uintptr_t>(U(2))));
            return 0;
        }
        case LC32OpenGLESOpDiscardFramebufferEXT: {
            REQUIRE(3);
            size_t count;
            if(!ReadCount(I(1), 1, count)) return 0;
            std::vector<GLenum> attachments;
            if(!ReadGuestArray(U(2), count, attachments)) return 0;
            glDiscardFramebufferEXT(U(0), I(1), attachments.data());
            return 0;
        }
        case LC32OpenGLESOpColorPointer:
        case LC32OpenGLESOpTexCoordPointer:
        case LC32OpenGLESOpVertexPointer: {
            REQUIRE(4);
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
            ClientArrayKind kind = opcode == LC32OpenGLESOpColorPointer
                ? ClientArrayKind::Color
                : opcode == LC32OpenGLESOpTexCoordPointer
                    ? ClientArrayKind::TexCoord : ClientArrayKind::Vertex;
            if(!ClientMemoryPointerAllowed(binding, U(3))) {
                SetBridgeError(GL_INVALID_OPERATION);
                return 0;
            }
            if(!FixedClientDescriptorValid(kind, I(0), U(1), I(2))) {
                const GLvoid *pointer = binding
                    ? reinterpret_cast<const GLvoid *>(
                        static_cast<uintptr_t>(U(3)))
                    : nullptr;
                if(kind == ClientArrayKind::Color)
                    glColorPointer(I(0), U(1), I(2), pointer);
                else if(kind == ClientArrayKind::TexCoord)
                    glTexCoordPointer(I(0), U(1), I(2), pointer);
                else
                    glVertexPointer(I(0), U(1), I(2), pointer);
                return 0;
            }
            if(!binding) {
                ClientArrayDescriptor descriptor;
                descriptor.kind = kind;
                descriptor.size = I(0);
                descriptor.type = U(1);
                descriptor.stride = I(2);
                descriptor.guestPointer = U(3);
                descriptor.valid = true;
                RememberClientPointer(&descriptor, kind);
                if(kind == ClientArrayKind::Color)
                    glColorPointer(I(0), U(1), I(2), nullptr);
                else if(kind == ClientArrayKind::TexCoord)
                    glTexCoordPointer(I(0), U(1), I(2), nullptr);
                else
                    glVertexPointer(I(0), U(1), I(2), nullptr);
                return 0;
            }
            RememberClientPointer(nullptr, kind);
            const GLvoid *pointer = reinterpret_cast<const GLvoid *>(
                static_cast<uintptr_t>(U(3)));
            if(kind == ClientArrayKind::Color)
                glColorPointer(I(0), U(1), I(2), pointer);
            else if(kind == ClientArrayKind::TexCoord)
                glTexCoordPointer(I(0), U(1), I(2), pointer);
            else
                glVertexPointer(I(0), U(1), I(2), pointer);
            return 0;
        }
        default:
            SetBridgeError(GL_INVALID_OPERATION);
            return 0;
    }

#undef REQUIRE
#undef U
#undef Q
#undef I
#undef F
}

#pragma clang diagnostic pop
