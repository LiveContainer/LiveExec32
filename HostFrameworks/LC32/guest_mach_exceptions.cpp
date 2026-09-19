#include "guest_mach_messages.h"

#include <mach/mach.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>
#include <cstring>

namespace {
// iOS 10.3 task/thread exception-port APIs share these ARM32 wire layouts:
// set/swap carry a copy-send descriptor; get is a simple request.
struct __attribute__((packed, aligned(4))) ExceptionPortRequest32 {
    mach_msg_header_t head;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t port;
    NDR_record_t ndr;
    exception_mask_t mask;
    exception_behavior_t behavior;
    thread_state_flavor_t flavor;
};
struct __attribute__((packed, aligned(4))) ExceptionQuery32 {
    mach_msg_header_t head;
    NDR_record_t ndr;
    exception_mask_t mask;
};
static_assert(sizeof(ExceptionPortRequest32) == 60);
static_assert(sizeof(ExceptionQuery32) == 36);
static_assert(sizeof(mig_reply_error_t) == 36);
}

bool HandleGuestExceptionPortMessage(
        mach_msg_header_t *message, mach_msg_size_t sendSize,
        mach_msg_size_t receiveSize, mach_msg_bits_t requestBits,
        mach_msg_return_t *result) {
    if(!message || !result) return false;
    const bool thread = message->msgh_id >= 3613 && message->msgh_id <= 3615;
    const bool query = message->msgh_id == 3414 || message->msgh_id == 3614;
    if(!thread && !query && message->msgh_id != 3413 && message->msgh_id != 3415)
        return false;

    *result = MACH_MSG_SUCCESS;
    if(receiveSize < sizeof(mig_reply_error_t)) {
        message->msgh_size = sizeof(mig_reply_error_t);
        *result = MACH_RCV_TOO_LARGE;
        return true;
    }
    bool valid = message->msgh_size == sendSize;
    if(query) {
        valid &= sendSize == sizeof(ExceptionQuery32) &&
            !(requestBits & MACH_MSGH_BITS_COMPLEX);
        if(valid) {
            ExceptionQuery32 request;
            std::memcpy(&request, message, sizeof(request));
            valid = !std::memcmp(&request.ndr, &NDR_record, sizeof(NDR_record));
        }
    } else {
        valid &= sendSize == sizeof(ExceptionPortRequest32) &&
            (requestBits & MACH_MSGH_BITS_COMPLEX);
        if(valid) {
            ExceptionPortRequest32 request;
            std::memcpy(&request, message, sizeof(request));
            valid = request.body.msgh_descriptor_count == 1 &&
                request.port.type == MACH_MSG_PORT_DESCRIPTOR &&
                request.port.disposition == MACH_MSG_TYPE_COPY_SEND &&
                !std::memcmp(&request.ndr, &NDR_record, sizeof(NDR_record));
        }
    }

    mig_reply_error_t reply = {};
    reply.Head = *message;
    reply.Head.msgh_bits &= ~MACH_MSGH_BITS_COMPLEX;
    reply.Head.msgh_size = sizeof(reply);
    reply.NDR = NDR_record;
    reply.RetCode = !valid ? MIG_BAD_ARGUMENTS :
        (!MACH_PORT_VALID(message->msgh_remote_port) ||
         (!thread && message->msgh_remote_port != mach_task_self())) ? KERN_INVALID_ARGUMENT :
        KERN_NOT_SUPPORTED;
    // Do not forward to task/thread_{set,swap}_exception_ports: an ARM32 crash
    // reporter cannot receive/interpret the emulator host's ARM64 exceptions.
    // A truthful failure lets optional reporters abandon registration instead
    // of aborting the game or claiming an exception handler was installed.
    std::memcpy(message, &reply, sizeof(reply));
    return true;
}
