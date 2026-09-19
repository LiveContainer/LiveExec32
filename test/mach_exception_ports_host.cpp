#include "guest_mach_messages.h"
#include <mach/mach.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>
#include <cstdio>
#include <cstring>

struct __attribute__((packed, aligned(4))) Request {
    mach_msg_header_t head;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t port;
    NDR_record_t ndr;
    uint32_t mask, behavior, flavor;
};
static_assert(sizeof(Request) == 60);
static int failures;
static void check(const char *name, bool passed) {
    std::printf("mach-exception-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
int main() {
    mach_port_t port = MACH_PORT_NULL;
    if(mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) ||
       mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND)) return 1;
    for(unsigned variant = 0; variant < 12; ++variant) {
        alignas(4) unsigned char buffer[96];
        std::memset(buffer, 0xa5, sizeof(buffer));
        Request request = {};
        request.head.msgh_id = variant == 1 ? 3413 : 3415;
        request.head.msgh_size = sizeof(request);
        request.head.msgh_remote_port = mach_task_self();
        request.head.msgh_bits = MACH_MSGH_BITS_COMPLEX;
        request.body.msgh_descriptor_count = 1;
        request.port.name = port;
        request.port.type = MACH_MSG_PORT_DESCRIPTOR;
        request.port.disposition = MACH_MSG_TYPE_COPY_SEND;
        request.ndr = NDR_record;
        request.mask = EXC_MASK_BAD_ACCESS;
        request.behavior = EXCEPTION_DEFAULT;
        request.flavor = ARM_THREAD_STATE;
        mach_msg_size_t sendSize = sizeof(request), receiveSize = sizeof(buffer);
        kern_return_t expected = KERN_NOT_SUPPORTED;
        switch(variant) {
            case 2: sendSize = 59; expected = MIG_BAD_ARGUMENTS; break;
            case 3: sendSize = 64; expected = MIG_BAD_ARGUMENTS; break;
            case 4: request.head.msgh_bits = 0; expected = MIG_BAD_ARGUMENTS; break;
            case 5: request.body.msgh_descriptor_count = 2; expected = MIG_BAD_ARGUMENTS; break;
            case 6: request.port.type = MACH_MSG_OOL_DESCRIPTOR; expected = MIG_BAD_ARGUMENTS; break;
            case 7: request.port.disposition = MACH_MSG_TYPE_MOVE_SEND; expected = MIG_BAD_ARGUMENTS; break;
            case 8: request.ndr.int_rep ^= 1; expected = MIG_BAD_ARGUMENTS; break;
            case 9: request.head.msgh_remote_port = port; expected = KERN_INVALID_ARGUMENT; break;
            case 10: receiveSize = 24; break;
            case 11: request.head.msgh_id = 99999; break;
        }
        request.head.msgh_size = sendSize;
        std::memcpy(buffer, &request, sizeof(request));
        unsigned char before[sizeof(buffer)];
        std::memcpy(before, buffer, sizeof(buffer));
        mach_msg_return_t result = -1;
        const bool handled = HandleGuestExceptionPortMessage(
            reinterpret_cast<mach_msg_header_t *>(buffer), sendSize,
            receiveSize, request.head.msgh_bits, &result);
        const auto *reply = reinterpret_cast<const mig_reply_error_t *>(buffer);
        bool passed = variant == 11 ? !handled && !std::memcmp(before, buffer, sizeof(buffer)) :
            variant == 10 ? handled && result == MACH_RCV_TOO_LARGE && reply->Head.msgh_size == 36 :
            handled && result == MACH_MSG_SUCCESS && reply->RetCode == expected &&
                reply->Head.msgh_size == 36 && !(reply->Head.msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
                !std::memcmp(&reply->NDR, &NDR_record, sizeof(NDR_record));
        const size_t written = variant == 11 ? 0 : variant == 10 ? 24 : 36;
        passed &= !std::memcmp(buffer + written, before + written, sizeof(buffer) - written);
        static const char *names[] = {"swap-unsupported","set-unsupported","short-request",
            "long-request","not-complex","descriptor-count","descriptor-type",
            "descriptor-disposition","ndr","foreign-target","short-reply","unrelated-id"};
        check(names[variant], passed);
    }
    struct {mach_msg_header_t head; NDR_record_t ndr; uint32_t mask;} query = {};
    query.head.msgh_id = 3414; query.head.msgh_size = sizeof(query);
    query.head.msgh_remote_port = mach_task_self(); query.ndr = NDR_record;
    query.mask = EXC_MASK_BAD_ACCESS;
    mach_msg_return_t result = -1;
    bool handled = HandleGuestExceptionPortMessage(&query.head, sizeof(query), sizeof(query), 0, &result);
    mig_reply_error_t reply;
    std::memcpy(&reply, &query, sizeof(reply));
    check("get-unsupported", handled && result == MACH_MSG_SUCCESS && reply.RetCode == KERN_NOT_SUPPORTED);
    mach_port_urefs_t refs = 0;
    check("send-right-not-consumed", mach_port_get_refs(mach_task_self(), port,
        MACH_PORT_RIGHT_SEND, &refs) == KERN_SUCCESS && refs == 1);
    check("receive-right-intact", mach_port_get_refs(mach_task_self(), port,
        MACH_PORT_RIGHT_RECEIVE, &refs) == KERN_SUCCESS && refs == 1);
    mach_port_deallocate(mach_task_self(), port);
    mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
    return failures ? 1 : 0;
}
