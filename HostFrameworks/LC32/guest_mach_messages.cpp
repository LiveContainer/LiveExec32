#include "guest_mach_messages.h"
#include "dynarmic.h"

#include <mach/clock.h>
#include <mach/mach.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace {

/* Wire layouts and IDs are from the iOS 10.3 SDK's mach/{mach_host,
 * mach_port,clock}.h and libsystem_kernel's _kernelrpc stubs. Keep them
 * independent of the host SDK's LP64 MIG structs: even _host_page_size
 * widens its vm_size_t result on arm64. */
template<size_t Count>
struct __attribute__((packed, aligned(4))) ScalarRequest32 {
    mach_msg_header_t Head;
    NDR_record_t NDR;
    uint32_t values[Count];
};

template<typename T>
struct __attribute__((packed, aligned(4))) ScalarReply32 {
    mach_msg_header_t Head;
    NDR_record_t NDR;
    kern_return_t RetCode;
    T value;
};

struct __attribute__((packed, aligned(4))) ClockAttributesReply32 {
    mach_msg_header_t Head;
    NDR_record_t NDR;
    kern_return_t RetCode;
    mach_msg_type_number_t count;
    integer_t attributes[1];
};

struct __attribute__((packed, aligned(4))) KernelVersionReply32 {
    mach_msg_header_t Head;
    NDR_record_t NDR;
    kern_return_t RetCode;
    mach_msg_type_number_t offset;
    mach_msg_type_number_t count;
    char version[512];
};

static_assert(sizeof(mach_msg_header_t) == 24);
static_assert(sizeof(mig_reply_error_t) == 36);
static_assert(sizeof(ScalarRequest32<1>) == 36);
static_assert(sizeof(ScalarRequest32<2>) == 40);
static_assert(sizeof(ScalarRequest32<3>) == 44);
static_assert(sizeof(ScalarReply32<uint32_t>) == 40);
static_assert(sizeof(ScalarReply32<uint64_t>) == 44);
static_assert(offsetof(ScalarReply32<uint64_t>, value) == 36);
static_assert(sizeof(ClockAttributesReply32) == 44);
static_assert(offsetof(KernelVersionReply32, version) == 44);
static_assert(sizeof(KernelVersionReply32) == 556);

class ReplyWriter {
public:
    ReplyWriter(mach_msg_header_t *message, mach_msg_size_t capacity,
                mach_msg_return_t *result)
        : message_(message), capacity_(capacity), result_(result) {
        *result_ = MACH_MSG_SUCCESS;
    }

    bool require(mach_msg_size_t size) {
        if(capacity_ >= size) return true;
        message_->msgh_size = size;
        *result_ = MACH_RCV_TOO_LARGE;
        return false;
    }

    void error(kern_return_t code) {
        if(!require(sizeof(mig_reply_error_t))) return;
        mig_reply_error_t reply = {};
        reply.Head = header(sizeof(reply));
        reply.NDR = NDR_record;
        reply.RetCode = code;
        std::memcpy(message_, &reply, sizeof(reply));
    }

    template<typename T>
    void scalar(kern_return_t code, T value) {
        if(code != KERN_SUCCESS) return error(code);
        if(!require(sizeof(ScalarReply32<T>))) return;
        ScalarReply32<T> reply = {};
        reply.Head = header(sizeof(reply));
        reply.NDR = NDR_record;
        reply.RetCode = KERN_SUCCESS;
        reply.value = value;
        std::memcpy(message_, &reply, sizeof(reply));
    }

    mach_msg_header_t header(mach_msg_size_t size) const {
        mach_msg_header_t result = *message_;
        result.msgh_bits &= ~MACH_MSGH_BITS_COMPLEX;
        result.msgh_size = size;
        return result;
    }

private:
    mach_msg_header_t *message_;
    mach_msg_size_t capacity_;
    mach_msg_return_t *result_;
};

} // namespace

bool HandleGuestSimpleMachMessage(
        mach_msg_header_t *message, mach_msg_size_t sendSize,
        mach_msg_size_t receiveSize, mach_msg_bits_t requestBits,
        mach_msg_return_t *result) {
    if(!message || !result) return false;
    unsigned argumentCount;
    mach_msg_size_t replySize = sizeof(mig_reply_error_t);
    switch(message->msgh_id) {
        case 201: // host_kernel_version
            argumentCount = 0;
            break;
        case 202: // _host_page_size
            argumentCount = 0;
            replySize = sizeof(ScalarReply32<uint32_t>);
            break;
        case 3204: // mach_port_allocate
            argumentCount = 1;
            replySize = sizeof(ScalarReply32<uint32_t>);
            break;
        case 3228: // mach_port_get_context
            argumentCount = 1;
            replySize = sizeof(ScalarReply32<uint64_t>);
            break;
        case 3205: // mach_port_destroy
        case 3206: // mach_port_deallocate
            argumentCount = 1;
            break;
        case 3207: // mach_port_get_refs
            argumentCount = 2;
            replySize = sizeof(ScalarReply32<uint32_t>);
            break;
        case 1001: // clock_get_attributes
        case 3202: // mach_port_rename
        case 3203: // mach_port_allocate_name
        case 3210: // mach_port_set_mscount
        case 3212: // mach_port_move_member
        case 3216: // mach_port_set_seqno
        case 3226: // mach_port_insert_member
        case 3227: // mach_port_extract_member
            argumentCount = 2;
            break;
        case 3208: // mach_port_mod_refs
        case 3229: // mach_port_set_context
            argumentCount = 3;
            break;
        default:
            return false;
    }

    ReplyWriter reply(message, receiveSize, result);
    const mach_msg_size_t requestSize = sizeof(mach_msg_header_t) +
        (argumentCount ? sizeof(NDR_record_t) + 4 * argumentCount : 0);
    if(sendSize != requestSize || message->msgh_size != sendSize ||
            (requestBits & MACH_MSGH_BITS_COMPLEX)) {
        reply.error(MIG_BAD_ARGUMENTS);
        return true;
    }
    uint32_t arguments[3] = {};
    if(argumentCount) {
        NDR_record_t ndr;
        std::memcpy(&ndr, reinterpret_cast<const char *>(message) +
            sizeof(mach_msg_header_t), sizeof(ndr));
        if(std::memcmp(&ndr, &NDR_record, sizeof(ndr))) {
            reply.error(MIG_BAD_ARGUMENTS);
            return true;
        }
        std::memcpy(arguments, reinterpret_cast<const char *>(message) +
            sizeof(mach_msg_header_t) + sizeof(ndr), 4 * argumentCount);
    }

    /* Preflight replies before namespace mutations, notably allocate: do not
     * create a right whose returned name cannot fit in the guest's buffer. */
    if(!reply.require(replySize)) return true;
    const mach_port_t target = message->msgh_remote_port;
    kern_return_t code;
    switch(message->msgh_id) {
        case 201: {
            kernel_version_t version = {};
            code = host_kernel_version(target, version);
            if(code != KERN_SUCCESS) {
                reply.error(code);
                break;
            }
            const size_t length = strnlen(version, sizeof(version));
            if(length >= sizeof(version) || length >= 512) {
                reply.error(MIG_TYPE_ERROR);
                break;
            }
            const mach_msg_type_number_t count = length + 1;
            const mach_msg_size_t size = offsetof(KernelVersionReply32, version)
                + ((count + 3U) & ~3U);
            if(!reply.require(size)) break;
            KernelVersionReply32 response = {};
            response.Head = reply.header(size);
            response.NDR = NDR_record;
            response.RetCode = KERN_SUCCESS;
            response.count = count;
            std::memcpy(response.version, version, count);
            std::memcpy(message, &response, size);
            break;
        }
        case 202: {
            vm_size_t hostPageSize = 0;
            code = _host_page_size(target, &hostPageSize);
            /* Validate the destination using the real RPC, but expose the
             * emulator's 4 KiB logical pages rather than native 16 KiB pages. */
            reply.scalar(code, static_cast<uint32_t>(DYN_PAGE_SIZE));
            break;
        }
        case 1001: {
            if(arguments[1] > 1) {
                reply.error(MIG_ARRAY_TOO_LARGE);
                break;
            }
            const mach_msg_size_t capacity =
                offsetof(ClockAttributesReply32, attributes) + 4 * arguments[1];
            if(!reply.require(capacity)) break;
            integer_t attribute = 0;
            mach_msg_type_number_t count = arguments[1];
            code = clock_get_attributes(target,
                static_cast<clock_flavor_t>(arguments[0]), &attribute, &count);
            if(code != KERN_SUCCESS) {
                reply.error(code);
                break;
            }
            if(count > arguments[1] || count > 1) {
                reply.error(MIG_TYPE_ERROR);
                break;
            }
            ClockAttributesReply32 response = {};
            const mach_msg_size_t size =
                offsetof(ClockAttributesReply32, attributes) + 4 * count;
            response.Head = reply.header(size);
            response.NDR = NDR_record;
            response.RetCode = KERN_SUCCESS;
            response.count = count;
            response.attributes[0] = attribute;
            std::memcpy(message, &response, size);
            break;
        }
        case 3202:
            reply.error(mach_port_rename(target, arguments[0], arguments[1]));
            break;
        case 3203:
            reply.error(mach_port_allocate_name(target, arguments[0], arguments[1]));
            break;
        case 3204: {
            mach_port_name_t name = MACH_PORT_NULL;
            code = mach_port_allocate(target, arguments[0], &name);
            reply.scalar(code, name);
            break;
        }
        case 3205:
            reply.error(mach_port_destroy(target, arguments[0]));
            break;
        case 3206:
            reply.error(mach_port_deallocate(target, arguments[0]));
            break;
        case 3207: {
            mach_port_urefs_t refs = 0;
            code = mach_port_get_refs(target, arguments[0], arguments[1], &refs);
            reply.scalar(code, refs);
            break;
        }
        case 3208:
            reply.error(mach_port_mod_refs(target, arguments[0], arguments[1],
                static_cast<mach_port_delta_t>(static_cast<int32_t>(arguments[2]))));
            break;
        case 3210:
            reply.error(mach_port_set_mscount(target, arguments[0], arguments[1]));
            break;
        case 3212:
            reply.error(mach_port_move_member(target, arguments[0], arguments[1]));
            break;
        case 3216:
            reply.error(mach_port_set_seqno(target, arguments[0], arguments[1]));
            break;
        case 3226:
            reply.error(mach_port_insert_member(target, arguments[0], arguments[1]));
            break;
        case 3227:
            reply.error(mach_port_extract_member(target, arguments[0], arguments[1]));
            break;
        case 3228: {
            mach_port_context_t context = 0;
            code = mach_port_get_context(target, arguments[0], &context);
            // libsystem_kernel's _kernelrpc wire ABI uses 64 bits even though
            // the public ARM32 mach_port_context_t is only 32 bits.
            reply.scalar(code, static_cast<uint64_t>(context));
            break;
        }
        case 3229:
            reply.error(mach_port_set_context(target, arguments[0],
                static_cast<uint64_t>(arguments[1]) |
                (static_cast<uint64_t>(arguments[2]) << 32)));
            break;
    }
    return true;
}
