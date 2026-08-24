#define GLES_SILENCE_DEPRECATION 1

#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/CAEAGLLayer.h>
#import <objc/runtime.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "../../bridge.h"
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
        case GL_ACTIVE_TEXTURE:
        case GL_ALPHA_BITS:
        case GL_ARRAY_BUFFER_BINDING:
        case GL_BLEND:
        case GL_BLEND_DST_ALPHA:
        case GL_BLEND_DST_RGB:
        case GL_BLEND_EQUATION_ALPHA:
        case GL_BLEND_EQUATION_RGB:
        case GL_BLEND_SRC_ALPHA:
        case GL_BLEND_SRC_RGB:
        case GL_BLUE_BITS:
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
        case GL_GENERATE_MIPMAP_HINT:
        case GL_GREEN_BITS:
        case GL_IMPLEMENTATION_COLOR_READ_FORMAT:
        case GL_IMPLEMENTATION_COLOR_READ_TYPE:
        case GL_LINE_WIDTH:
        case GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS:
        case GL_MAX_CUBE_MAP_TEXTURE_SIZE:
        case GL_MAX_FRAGMENT_UNIFORM_VECTORS:
        case GL_MAX_RENDERBUFFER_SIZE:
#ifdef GL_MAX_SAMPLES_APPLE
        case GL_MAX_SAMPLES_APPLE:
#endif
        case GL_MAX_TEXTURE_IMAGE_UNITS:
        case GL_MAX_TEXTURE_SIZE:
        case GL_MAX_VARYING_VECTORS:
        case GL_MAX_VERTEX_ATTRIBS:
        case GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS:
        case GL_MAX_VERTEX_UNIFORM_VECTORS:
        case GL_NUM_COMPRESSED_TEXTURE_FORMATS:
        case GL_NUM_SHADER_BINARY_FORMATS:
        case GL_PACK_ALIGNMENT:
        case GL_POLYGON_OFFSET_FACTOR:
        case GL_POLYGON_OFFSET_FILL:
        case GL_POLYGON_OFFSET_UNITS:
        case GL_RED_BITS:
        case GL_RENDERBUFFER_BINDING:
        case GL_SAMPLE_ALPHA_TO_COVERAGE:
        case GL_SAMPLE_BUFFERS:
        case GL_SAMPLE_COVERAGE:
        case GL_SAMPLE_COVERAGE_INVERT:
        case GL_SAMPLE_COVERAGE_VALUE:
        case GL_SAMPLES:
        case GL_SCISSOR_TEST:
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
        case GL_UNPACK_ALIGNMENT:
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
            return 1;
        default:
            return 0;
    }
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

bool PixelSize(GLsizei width, GLsizei height, GLenum format, GLenum type,
               GLint alignment, size_t &byteCount, GLenum &error,
               size_t *rowBytesOutput = nullptr,
               size_t *rowStrideOutput = nullptr) {
    error = GL_NO_ERROR;
    if(width < 0 || height < 0) {
        error = GL_INVALID_VALUE;
        return false;
    }
    size_t bytesPerPixel = 0;
    size_t componentCount = 0;
    switch(format) {
        case GL_ALPHA:
        case GL_LUMINANCE: componentCount = 1; break;
        case GL_LUMINANCE_ALPHA: componentCount = 2; break;
        case GL_RGB: componentCount = 3; break;
        case GL_RGBA: componentCount = 4; break;
        default: error = GL_INVALID_ENUM; return false;
    }
    if(type == GL_UNSIGNED_BYTE) {
        bytesPerPixel = componentCount;
    } else if(type == GL_UNSIGNED_SHORT_5_6_5) {
        if(format != GL_RGB) {
            error = GL_INVALID_OPERATION;
            return false;
        }
        bytesPerPixel = 2;
    } else if(type == GL_UNSIGNED_SHORT_4_4_4_4 ||
              type == GL_UNSIGNED_SHORT_5_5_5_1) {
        if(format != GL_RGBA) {
            error = GL_INVALID_OPERATION;
            return false;
        }
        bytesPerPixel = 2;
    } else {
        error = GL_INVALID_ENUM;
        return false;
    }

    if(alignment != 1 && alignment != 2 && alignment != 4 && alignment != 8) {
        error = GL_INVALID_OPERATION;
        return false;
    }
    size_t rowBytes;
    if(!CheckedByteCount(static_cast<size_t>(width), bytesPerPixel,
                         rowBytes)) {
        error = GL_INVALID_VALUE;
        return false;
    }
    const size_t alignedRow = (rowBytes + alignment - 1) & ~(alignment - 1);
    if(rowBytesOutput) *rowBytesOutput = rowBytes;
    if(rowStrideOutput) *rowStrideOutput = alignedRow;
    if(height == 0) {
        byteCount = 0;
        return true;
    }
    size_t precedingRows;
    if(!CheckedByteCount(static_cast<size_t>(height - 1), alignedRow,
                         precedingRows) ||
       rowBytes > kMaximumTransfer - precedingRows) {
        error = GL_INVALID_VALUE;
        return false;
    }
    byteCount = precedingRows + rowBytes;
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
};

struct ClientArrayDescriptor {
    ClientArrayKind kind = ClientArrayKind::VertexAttrib;
    GLuint index = 0;
    GLint size = 0;
    GLenum type = 0;
    GLboolean normalized = GL_FALSE;
    GLsizei stride = 0;
    uint32_t guestPointer = 0;
    bool valid = false;
};

struct VertexArrayClientState {
    std::unordered_map<GLuint, ClientArrayDescriptor> vertexAttribs;
    std::unordered_set<GLuint> enabledVertexAttribs;
    ClientArrayDescriptor vertex;
    ClientArrayDescriptor color;
    std::unordered_map<GLenum, ClientArrayDescriptor> texCoords;
    std::unordered_set<GLenum> enabledTexCoords;
    ClientArrayDescriptor normal;
    bool vertexEnabled = false;
    bool colorEnabled = false;
    bool normalEnabled = false;
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
    if(descriptor) attributes[index] = *descriptor;
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
        case ClientArrayKind::VertexAttrib: return;
    }
    *destination = descriptor ? *descriptor : ClientArrayDescriptor{};
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
        state.enabledTexCoords.size() + 3);
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
    return descriptors;
}

size_t ClientArrayScalarSize(GLenum type) {
    switch(type) {
        case GL_BYTE:
        case GL_UNSIGNED_BYTE: return 1;
        case GL_SHORT:
        case GL_UNSIGNED_SHORT: return 2;
        case GL_FIXED:
        case GL_FLOAT: return 4;
#ifdef GL_HALF_FLOAT_OES
        case GL_HALF_FLOAT_OES: return 2;
#endif
        default: return 0;
    }
}

bool ClientArrayByteCount(const ClientArrayDescriptor &descriptor,
                          size_t maximumIndex, size_t &byteCount) {
    const size_t scalarSize = ClientArrayScalarSize(descriptor.type);
    if(!scalarSize || descriptor.size <= 0 || descriptor.size > 4 ||
       descriptor.stride < 0) {
        SetBridgeError(!scalarSize ? GL_INVALID_ENUM : GL_INVALID_VALUE);
        return false;
    }

    size_t elementSize;
    if(!CheckedByteCount(static_cast<size_t>(descriptor.size), scalarSize,
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

bool StageClientArrays(size_t maximumIndex,
                       std::vector<StagedClientArray> &staged) {
    std::vector<ClientArrayDescriptor> descriptors = EnabledClientArrays();
    staged.clear();
    staged.reserve(descriptors.size());
    for(const ClientArrayDescriptor &descriptor : descriptors) {
        size_t byteCount;
        if(!ClientArrayByteCount(descriptor, maximumIndex, byteCount))
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
                glVertexAttribPointer(descriptor.index, descriptor.size,
                    descriptor.type, descriptor.normalized,
                    descriptor.stride, pointer);
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
        }
    }
    if(changedClientActiveTexture)
        glClientActiveTexture(savedClientActiveTexture);
    glBindBuffer(GL_ARRAY_BUFFER, static_cast<GLuint>(savedBinding));
    return true;
}

bool MaximumIndex(GLenum type, const std::vector<uint8_t> &indices,
                  size_t &maximumIndex) {
    maximumIndex = 0;
    const size_t elementSize = IndexElementSize(type);
    if(!elementSize || indices.size() % elementSize) return false;
    for(size_t offset = 0; offset < indices.size(); offset += elementSize) {
        uint32_t index = 0;
        memcpy(&index, indices.data() + offset, elementSize);
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
        case GL_BOOL:
        case GL_SAMPLER_2D:
        case GL_SAMPLER_CUBE:
            return 1;
        case GL_FLOAT_VEC2:
        case GL_INT_VEC2:
        case GL_BOOL_VEC2:
            return 2;
        case GL_FLOAT_VEC3:
        case GL_INT_VEC3:
        case GL_BOOL_VEC3:
            return 3;
        case GL_FLOAT_VEC4:
        case GL_INT_VEC4:
        case GL_BOOL_VEC4:
        case GL_FLOAT_MAT2:
            return 4;
        case GL_FLOAT_MAT3:
            return 9;
        case GL_FLOAT_MAT4:
            return 16;
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

#define REQUIRE(count) do { if(!RequireSlots(call, (count))) return 0; } while(0)
#define U(index) SlotU32(call, (index))
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
        case LC32OpenGLESOpActiveTexture: REQUIRE(1); glActiveTexture(U(0)); return 0;
        case LC32OpenGLESOpAttachShader: REQUIRE(2); glAttachShader(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindBuffer: REQUIRE(2); glBindBuffer(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindFramebuffer: REQUIRE(2); glBindFramebuffer(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindRenderbuffer: REQUIRE(2); glBindRenderbuffer(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindTexture: REQUIRE(2); glBindTexture(U(0), U(1)); return 0;
        case LC32OpenGLESOpBindVertexArrayOES:
            REQUIRE(1);
            glBindVertexArrayOES(U(0));
            SetCurrentVertexArray(U(0));
            return 0;
        case LC32OpenGLESOpBlendColor: REQUIRE(4); glBlendColor(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpBlendEquation: REQUIRE(1); glBlendEquation(U(0)); return 0;
        case LC32OpenGLESOpBlendEquationSeparate: REQUIRE(2); glBlendEquationSeparate(U(0), U(1)); return 0;
        case LC32OpenGLESOpBlendFunc: REQUIRE(2); glBlendFunc(U(0), U(1)); return 0;
        case LC32OpenGLESOpBlendFuncSeparate: REQUIRE(4); glBlendFuncSeparate(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpCheckFramebufferStatus: REQUIRE(1); return glCheckFramebufferStatus(U(0));
        case LC32OpenGLESOpClear: REQUIRE(1); glClear(U(0)); return 0;
        case LC32OpenGLESOpClearColor: REQUIRE(4); glClearColor(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpClearDepthf: REQUIRE(1); glClearDepthf(F(0)); return 0;
        case LC32OpenGLESOpClearStencil: REQUIRE(1); glClearStencil(I(0)); return 0;
        case LC32OpenGLESOpColorMask: REQUIRE(4); glColorMask(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpCompileShader: REQUIRE(1); glCompileShader(U(0)); return 0;
        case LC32OpenGLESOpCopyTexImage2D: REQUIRE(8); glCopyTexImage2D(U(0), I(1), U(2), I(3), I(4), I(5), I(6), I(7)); return 0;
        case LC32OpenGLESOpCopyTexSubImage2D: REQUIRE(8); glCopyTexSubImage2D(U(0), I(1), I(2), I(3), I(4), I(5), I(6), I(7)); return 0;
        case LC32OpenGLESOpCreateProgram: REQUIRE(0); return glCreateProgram();
        case LC32OpenGLESOpCreateShader: REQUIRE(1); return glCreateShader(U(0));
        case LC32OpenGLESOpCullFace: REQUIRE(1); glCullFace(U(0)); return 0;
        case LC32OpenGLESOpDeleteBuffers:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteBuffers(n, v); });
        case LC32OpenGLESOpDeleteFramebuffers:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteFramebuffers(n, v); });
        case LC32OpenGLESOpDeleteRenderbuffers:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteRenderbuffers(n, v); });
        case LC32OpenGLESOpDeleteTextures:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) { glDeleteTextures(n, v); });
        case LC32OpenGLESOpDeleteVertexArraysOES:
            return DispatchObjectInputArray(call, [](GLsizei n, const GLuint *v) {
                glDeleteVertexArraysOES(n, v);
                ForgetVertexArrayStates(n, v);
            });
        case LC32OpenGLESOpDeleteProgram: REQUIRE(1); glDeleteProgram(U(0)); return 0;
        case LC32OpenGLESOpDeleteShader: REQUIRE(1); glDeleteShader(U(0)); return 0;
        case LC32OpenGLESOpDepthFunc: REQUIRE(1); glDepthFunc(U(0)); return 0;
        case LC32OpenGLESOpDepthMask: REQUIRE(1); glDepthMask(U(0)); return 0;
        case LC32OpenGLESOpDepthRangef: REQUIRE(2); glDepthRangef(F(0), F(1)); return 0;
        case LC32OpenGLESOpDetachShader: REQUIRE(2); glDetachShader(U(0), U(1)); return 0;
        case LC32OpenGLESOpDisable: REQUIRE(1); glDisable(U(0)); return 0;
        case LC32OpenGLESOpDisableVertexAttribArray:
            REQUIRE(1);
            glDisableVertexAttribArray(U(0));
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
        case LC32OpenGLESOpEnable: REQUIRE(1); glEnable(U(0)); return 0;
        case LC32OpenGLESOpEnableVertexAttribArray:
            REQUIRE(1);
            glEnableVertexAttribArray(U(0));
            SetVertexAttribArrayEnabled(U(0), true);
            return 0;
        case LC32OpenGLESOpFinish: REQUIRE(0); glFinish(); return 0;
        case LC32OpenGLESOpFlush: REQUIRE(0); glFlush(); return 0;
        case LC32OpenGLESOpFramebufferRenderbuffer: REQUIRE(4); glFramebufferRenderbuffer(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpFramebufferTexture2D: REQUIRE(5); glFramebufferTexture2D(U(0), U(1), U(2), U(3), I(4)); return 0;
        case LC32OpenGLESOpFrontFace: REQUIRE(1); glFrontFace(U(0)); return 0;
        case LC32OpenGLESOpGenBuffers:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenBuffers(n, v); });
        case LC32OpenGLESOpGenFramebuffers:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenFramebuffers(n, v); });
        case LC32OpenGLESOpGenRenderbuffers:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenRenderbuffers(n, v); });
        case LC32OpenGLESOpGenTextures:
            return DispatchObjectOutputArray(call, [](GLsizei n, GLuint *v) { glGenTextures(n, v); });
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
        case LC32OpenGLESOpLineWidth: REQUIRE(1); glLineWidth(F(0)); return 0;
        case LC32OpenGLESOpLinkProgram: REQUIRE(1); glLinkProgram(U(0)); return 0;
        case LC32OpenGLESOpPixelStorei: REQUIRE(2); glPixelStorei(U(0), I(1)); return 0;
        case LC32OpenGLESOpPolygonOffset: REQUIRE(2); glPolygonOffset(F(0), F(1)); return 0;
        case LC32OpenGLESOpReleaseShaderCompiler: REQUIRE(0); glReleaseShaderCompiler(); return 0;
        case LC32OpenGLESOpRenderbufferStorage: REQUIRE(4); glRenderbufferStorage(U(0), U(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpRenderbufferStorageMultisampleAPPLE: REQUIRE(5); glRenderbufferStorageMultisampleAPPLE(U(0), I(1), U(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpResolveMultisampleFramebufferAPPLE: REQUIRE(0); glResolveMultisampleFramebufferAPPLE(); return 0;
        case LC32OpenGLESOpSampleCoverage: REQUIRE(2); glSampleCoverage(F(0), U(1)); return 0;
        case LC32OpenGLESOpScissor: REQUIRE(4); glScissor(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpStencilFunc: REQUIRE(3); glStencilFunc(U(0), I(1), U(2)); return 0;
        case LC32OpenGLESOpStencilFuncSeparate: REQUIRE(4); glStencilFuncSeparate(U(0), U(1), I(2), U(3)); return 0;
        case LC32OpenGLESOpStencilMask: REQUIRE(1); glStencilMask(U(0)); return 0;
        case LC32OpenGLESOpStencilMaskSeparate: REQUIRE(2); glStencilMaskSeparate(U(0), U(1)); return 0;
        case LC32OpenGLESOpStencilOp: REQUIRE(3); glStencilOp(U(0), U(1), U(2)); return 0;
        case LC32OpenGLESOpStencilOpSeparate: REQUIRE(4); glStencilOpSeparate(U(0), U(1), U(2), U(3)); return 0;
        case LC32OpenGLESOpTexParameterf: REQUIRE(3); glTexParameterf(U(0), U(1), F(2)); return 0;
        case LC32OpenGLESOpTexParameteri: REQUIRE(3); glTexParameteri(U(0), U(1), I(2)); return 0;
        case LC32OpenGLESOpUniform1f: REQUIRE(2); glUniform1f(I(0), F(1)); return 0;
        case LC32OpenGLESOpUniform1i: REQUIRE(2); glUniform1i(I(0), I(1)); return 0;
        case LC32OpenGLESOpUniform2f: REQUIRE(3); glUniform2f(I(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpUniform2i: REQUIRE(3); glUniform2i(I(0), I(1), I(2)); return 0;
        case LC32OpenGLESOpUniform3f: REQUIRE(4); glUniform3f(I(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpUniform3i: REQUIRE(4); glUniform3i(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpUniform4f: REQUIRE(5); glUniform4f(I(0), F(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpUniform4i: REQUIRE(5); glUniform4i(I(0), I(1), I(2), I(3), I(4)); return 0;
        case LC32OpenGLESOpUseProgram: REQUIRE(1); glUseProgram(U(0)); return 0;
        case LC32OpenGLESOpValidateProgram: REQUIRE(1); glValidateProgram(U(0)); return 0;
        case LC32OpenGLESOpVertexAttrib1f: REQUIRE(2); glVertexAttrib1f(U(0), F(1)); return 0;
        case LC32OpenGLESOpVertexAttrib2f: REQUIRE(3); glVertexAttrib2f(U(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpVertexAttrib3f: REQUIRE(4); glVertexAttrib3f(U(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpVertexAttrib4f: REQUIRE(5); glVertexAttrib4f(U(0), F(1), F(2), F(3), F(4)); return 0;
        case LC32OpenGLESOpViewport: REQUIRE(4); glViewport(I(0), I(1), I(2), I(3)); return 0;
        case LC32OpenGLESOpAlphaFunc: REQUIRE(2); glAlphaFunc(U(0), F(1)); return 0;
        case LC32OpenGLESOpColor4f: REQUIRE(4); glColor4f(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpColor4ub: REQUIRE(4); glColor4ub(U(0), U(1), U(2), U(3)); return 0;
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
        case LC32OpenGLESOpLoadIdentity: REQUIRE(0); glLoadIdentity(); return 0;
        case LC32OpenGLESOpMatrixMode: REQUIRE(1); glMatrixMode(U(0)); return 0;
        case LC32OpenGLESOpNormal3f: REQUIRE(3); glNormal3f(F(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpOrthof: REQUIRE(6); glOrthof(F(0), F(1), F(2), F(3), F(4), F(5)); return 0;
        case LC32OpenGLESOpPopMatrix: REQUIRE(0); glPopMatrix(); return 0;
        case LC32OpenGLESOpPushMatrix: REQUIRE(0); glPushMatrix(); return 0;
        case LC32OpenGLESOpRotatef: REQUIRE(4); glRotatef(F(0), F(1), F(2), F(3)); return 0;
        case LC32OpenGLESOpScalef: REQUIRE(3); glScalef(F(0), F(1), F(2)); return 0;
        case LC32OpenGLESOpShadeModel: REQUIRE(1); glShadeModel(U(0)); return 0;
        case LC32OpenGLESOpTranslatef: REQUIRE(3); glTranslatef(F(0), F(1), F(2)); return 0;
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
            std::vector<uint8_t> bytes;
            if(!ReadGuestBytes(U(pointerSlot), signedSize, bytes)) return 0;
            const void *data = signedSize ? bytes.data() : nullptr;
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
            glBufferData(U(0), signedSize, data, U(3));
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
        case LC32OpenGLESOpGetFramebufferAttachmentParameteriv: {
            REQUIRE(4);
            GLint value = 0;
            glGetFramebufferAttachmentParameteriv(U(0), U(1), U(2), &value);
            WriteGuestArray(U(3), &value, 1);
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
        case LC32OpenGLESOpReadPixels: {
            REQUIRE(7);
            GLint alignment = 4;
            glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
            size_t byteCount;
            size_t rowBytes;
            size_t rowStride;
            GLenum sizeError;
            if(!PixelSize(I(2), I(3), U(4), U(5), alignment, byteCount,
                          sizeError, &rowBytes, &rowStride)) {
                SetBridgeError(sizeError);
                return 0;
            }
            std::vector<uint8_t> pixels(byteCount);
            glReadPixels(I(0), I(1), I(2), I(3), U(4), U(5),
                byteCount ? pixels.data() : nullptr);
            if(rowBytes) {
                for(GLsizei row = 0; row < I(3); ++row) {
                    const uint64_t guestRow = static_cast<uint64_t>(U(6)) +
                        static_cast<size_t>(row) * rowStride;
                    if(guestRow > UINT32_MAX ||
                       !WriteGuestBytes(static_cast<uint32_t>(guestRow),
                           pixels.data() + static_cast<size_t>(row) * rowStride,
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
            GLint alignment = 4;
            glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
            size_t byteCount;
            GLenum sizeError;
            if(!PixelSize(I(widthSlot), I(heightSlot), U(formatSlot),
                          U(typeSlot), alignment, byteCount, sizeError)) {
                SetBridgeError(sizeError);
                return 0;
            }
            std::vector<uint8_t> pixels;
            const void *data = nullptr;
            if(U(pointerSlot) && byteCount) {
                if(!ReadGuestBytes(U(pointerSlot), byteCount, pixels)) return 0;
                data = pixels.data();
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
            if(!MaximumIndex(U(2), indices, maximumIndex)) {
                SetBridgeError(GL_INVALID_ENUM);
                return 0;
            }
            std::vector<StagedClientArray> staged;
            if(!StageClientArrays(maximumIndex, staged)) return 0;
            glDrawElements(U(0), I(1), U(2), indices.data());
            return 0;
        }
        case LC32OpenGLESOpVertexAttribPointer: {
            REQUIRE(6);
            GLint binding = 0;
            glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &binding);
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
            const size_t count = U(0) == GL_FOG_COLOR ? 4 : 1;
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(1), count, values)) return 0;
            glFogfv(U(0), values.data());
            return 0;
        }
        case LC32OpenGLESOpLightfv: {
            REQUIRE(3);
            size_t count;
            switch(U(1)) {
                case GL_AMBIENT:
                case GL_DIFFUSE:
                case GL_SPECULAR:
                case GL_POSITION:
                    count = 4;
                    break;
                case GL_SPOT_DIRECTION:
                    count = 3;
                    break;
                case GL_SPOT_EXPONENT:
                case GL_SPOT_CUTOFF:
                case GL_CONSTANT_ATTENUATION:
                case GL_LINEAR_ATTENUATION:
                case GL_QUADRATIC_ATTENUATION:
                    count = 1;
                    break;
                default: {
                    const GLfloat dummy[4] = {};
                    glLightfv(U(0), U(1), dummy);
                    return 0;
                }
            }
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glLightfv(U(0), U(1), values.data());
            return 0;
        }
        case LC32OpenGLESOpMaterialfv: {
            REQUIRE(3);
            size_t count;
            switch(U(1)) {
                case GL_SHININESS:
                    count = 1;
                    break;
                case GL_AMBIENT:
                case GL_DIFFUSE:
                case GL_SPECULAR:
                case GL_EMISSION:
                case GL_AMBIENT_AND_DIFFUSE:
                    count = 4;
                    break;
                default: {
                    const GLfloat dummy[4] = {};
                    glMaterialfv(U(0), U(1), dummy);
                    return 0;
                }
            }
            std::vector<GLfloat> values;
            if(!ReadGuestArray(U(2), count, values)) return 0;
            glMaterialfv(U(0), U(1), values.data());
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
#undef I
#undef F
}

#pragma clang diagnostic pop
