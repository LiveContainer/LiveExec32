#include <mach/clock.h>
#include <mach/mach.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Use raw iOS 10 requests so the libsystem_kernel trap fast paths cannot
 * bypass the RPC handlers under test. Only ports created here are mutated. */
struct __attribute__((packed, aligned(4))) request32 {
    mach_msg_header_t head;
    NDR_record_t ndr;
    uint32_t arguments[3];
};

struct rpc_buffer {
    union {
        struct request32 request;
        mig_reply_error_t reply;
        unsigned char bytes[640];
    } message;
    uint32_t canary[4];
};

_Static_assert(sizeof(struct request32) == 44, "ARM32 simple request layout");
static int failures;
static const mach_msg_size_t replyCapacity = 640;

static void report(const char *name, int passed) {
    printf("mach-simple-rpc-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static void prepare(struct rpc_buffer *buffer, mach_port_t target,
        mach_msg_id_t id, unsigned count, uint32_t a, uint32_t b, uint32_t c) {
    memset(buffer, 0xa5, sizeof(*buffer));
    memset(&buffer->message.request, 0, sizeof(buffer->message.request));
    struct request32 *request = &buffer->message.request;
    request->head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND,
        MACH_MSG_TYPE_MAKE_SEND_ONCE);
    request->head.msgh_remote_port = target;
    request->head.msgh_local_port = mig_get_reply_port();
    request->head.msgh_id = id;
    request->head.msgh_size = count ? 32 + 4 * count : 24;
    request->ndr = NDR_record;
    request->arguments[0] = a;
    request->arguments[1] = b;
    request->arguments[2] = c;
}

static mach_msg_return_t execute(struct rpc_buffer *buffer,
        mach_msg_size_t sendSize, mach_msg_size_t receiveSize) {
    unsigned char before[sizeof(*buffer)];
    memcpy(before, buffer, sizeof(before));
    mach_msg_return_t result = mach_msg(&buffer->message.request.head,
        MACH_SEND_MSG | MACH_RCV_MSG | MACH_RCV_TIMEOUT,
        sendSize, receiveSize, buffer->message.request.head.msgh_local_port,
        1000, MACH_PORT_NULL);
    if(memcmp((unsigned char *)buffer + receiveSize, before + receiveSize,
            sizeof(*buffer) - receiveSize)) {
        report("receive-capacity-canary", 0);
    }
    return result;
}

static int is_reply(const struct rpc_buffer *buffer, mach_msg_return_t result,
        mach_msg_id_t id, kern_return_t code, mach_msg_size_t size) {
    return result == MACH_MSG_SUCCESS &&
        buffer->message.reply.Head.msgh_id == id + 100 &&
        !(buffer->message.reply.Head.msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
        buffer->message.reply.Head.msgh_size == size &&
        buffer->message.reply.RetCode == code &&
        memcmp(&buffer->message.reply.NDR, &NDR_record, sizeof(NDR_record)) == 0;
}

static uint32_t word(const struct rpc_buffer *buffer, size_t offset) {
    uint32_t value;
    memcpy(&value, buffer->message.bytes + offset, sizeof(value));
    return value;
}

static kern_return_t call_port(mach_msg_id_t id, unsigned count,
        uint32_t a, uint32_t b, uint32_t c, uint32_t *value) {
    struct rpc_buffer buffer;
    prepare(&buffer, mach_task_self(), id, count, a, b, c);
    mach_msg_return_t result = execute(&buffer,
        buffer.message.request.head.msgh_size, replyCapacity);
    kern_return_t code = buffer.message.reply.RetCode;
    mach_msg_size_t size = code == KERN_SUCCESS && value ? 40 : 36;
    if(!is_reply(&buffer, result, id, code, size)) return MIG_REPLY_MISMATCH;
    if(code == KERN_SUCCESS && value) *value = word(&buffer, 36);
    return code;
}

static void test_rename(mach_port_t receivePort) {
    mach_port_t secondPort = MACH_PORT_NULL;
    kern_return_t kr = call_port(3204, 1, MACH_PORT_RIGHT_RECEIVE,
        0, 0, &secondPort);
    report("rename-allocate-target", kr == KERN_SUCCESS &&
        MACH_PORT_VALID(secondPort));
    if(kr != KERN_SUCCESS) return;

    /* XNU 3789 already returns KERN_NOT_SUPPORTED unconditionally here.
     * Newer mach_port.defs removes the kernel RPC, returning MIG_BAD_ID.
     * Forward that precise native failure without mutating either owned port. */
    kr = call_port(3202, 2, receivePort, secondPort, 0, NULL);
    printf("mach-simple-rpc-rename-result: %d (0x%x)\n", kr, (unsigned)kr);
    report("rename-native-unavailable", kr == KERN_NOT_SUPPORTED ||
        kr == MIG_BAD_ID);
    uint32_t refs = 0;
    report("rename-source-intact", call_port(3207, 2, receivePort,
        MACH_PORT_RIGHT_RECEIVE, 0, &refs) == KERN_SUCCESS && refs == 1);
    refs = 0;
    report("rename-target-intact", call_port(3207, 2, secondPort,
        MACH_PORT_RIGHT_RECEIVE, 0, &refs) == KERN_SUCCESS && refs == 1);
    report("rename-destroy-target", call_port(3205, 1, secondPort,
        0, 0, NULL) == KERN_SUCCESS);
}

static void test_validation(mach_port_t receivePort) {
    static const char *names[] = {"truncated-request", "extra-request-bytes",
        "stale-header-size", "complex-request", "unsupported-ndr",
        "short-mutation-receive", "valid-mod-refs"};
    for(unsigned variant = 0; variant < 7; ++variant) {
        struct rpc_buffer buffer;
        prepare(&buffer, mach_task_self(), 3208, 3,
            receivePort, MACH_PORT_RIGHT_SEND, 1);
        mach_msg_size_t sendSize = 44, receiveSize = replyCapacity;
        switch(variant) {
            case 0: sendSize = buffer.message.request.head.msgh_size = 40; break;
            case 1: sendSize = buffer.message.request.head.msgh_size = 48; break;
            case 2:
                /* The kernel replaces msgh_size with the trap's send size.
                 * MIG clients may leave that header field unset or stale. */
                buffer.message.request.head.msgh_size = 40;
                buffer.message.request.arguments[2] = 0;
                break;
            case 3:
                buffer.message.request.head.msgh_bits |= MACH_MSGH_BITS_COMPLEX;
                break;
            case 4: buffer.message.request.ndr.int_rep ^= 1; break;
            case 5: receiveSize = 24; break;
        }
        mach_msg_return_t result = execute(&buffer, sendSize, receiveSize);
        int passed = variant == 5
            ? result == MACH_RCV_TOO_LARGE &&
                buffer.message.reply.Head.msgh_size == 36
            : is_reply(&buffer, result, 3208,
                variant == 2 || variant == 6 ? KERN_SUCCESS : MIG_BAD_ARGUMENTS,
                36);
        uint32_t refs = 0;
        passed &= call_port(3207, 2, receivePort, MACH_PORT_RIGHT_SEND,
            0, &refs) == KERN_SUCCESS && refs == (variant == 6 ? 2U : 1U);
        report(names[variant], passed);
    }
    report("deallocate-send", call_port(3206, 1, receivePort, 0, 0, NULL) ==
        KERN_SUCCESS);
    uint32_t refs = 0;
    report("send-refcount-after-deallocate", call_port(3207, 2, receivePort,
        MACH_PORT_RIGHT_SEND, 0, &refs) == KERN_SUCCESS && refs == 1);
    report("negative-mod-refs", call_port(3208, 3, receivePort,
        MACH_PORT_RIGHT_SEND, (uint32_t)-1, NULL) == KERN_SUCCESS);
}

static void test_host_clock(void) {
    mach_port_t host = mach_host_self();
    struct rpc_buffer buffer;
    prepare(&buffer, host, 202, 0, 0, 0, 0);
    mach_msg_return_t result = execute(&buffer, 24, replyCapacity);
    report("guest-page-size", is_reply(&buffer, result, 202, KERN_SUCCESS, 40)
        && word(&buffer, 36) == 4096);

    vm_size_t pageSize = 0;
    kern_return_t kr = host_page_size(host, &pageSize);
    report("public-host-page-size", kr == KERN_SUCCESS && pageSize == 4096);
    pageSize = 0;
    kr = _host_page_size(host, &pageSize);
    report("public-host-page-size-rpc", kr == KERN_SUCCESS && pageSize == 4096);

    prepare(&buffer, host, 202, 0, 0, 0, 0);
    result = execute(&buffer, 24, 36);
    report("short-page-reply", result == MACH_RCV_TOO_LARGE &&
        buffer.message.reply.Head.msgh_size == 40);

    prepare(&buffer, host, 201, 0, 0, 0, 0);
    result = execute(&buffer, 24, replyCapacity);
    uint32_t count = word(&buffer, 40);
    int versionPassed = count > 1 && count <= 512 &&
        is_reply(&buffer, result, 201, KERN_SUCCESS, 44 + ((count + 3) & ~3U)) &&
        word(&buffer, 36) == 0 && buffer.message.bytes[44 + count - 1] == 0 &&
        memchr(buffer.message.bytes + 44, 0, count) ==
            buffer.message.bytes + 44 + count - 1;
    report("kernel-version-wire-string", versionPassed);

    kernel_version_t publicVersion;
    memset(publicVersion, 0xa5, sizeof(publicVersion));
    kr = host_kernel_version(host, publicVersion);
    const size_t publicVersionLength = strnlen(publicVersion,
        sizeof(publicVersion));
    report("public-host-kernel-version", kr == KERN_SUCCESS && versionPassed &&
        publicVersionLength + 1 == count &&
        memcmp(publicVersion, buffer.message.bytes + 44, count) == 0);

    clock_serv_t clock = MACH_PORT_NULL;
    kr = host_get_clock_service(host, SYSTEM_CLOCK, &clock);
    report("clock-service", kr == KERN_SUCCESS && MACH_PORT_VALID(clock));
    if(kr == KERN_SUCCESS) {
        integer_t attribute = 0;
        mach_msg_type_number_t attributeCount = 1;
        kr = clock_get_attributes(clock, CLOCK_GET_TIME_RES, &attribute,
            &attributeCount);
        report("public-clock-get-attributes", kr == KERN_SUCCESS &&
            attributeCount == 1 && attribute > 0);
        for(unsigned variant = 0; variant < 4; ++variant) {
            prepare(&buffer, clock, 1001, 2, CLOCK_GET_TIME_RES,
                variant == 1 ? 2 : 1, 0);
            if(variant == 2) buffer.message.request.arguments[0] = 0x7fffffff;
            result = execute(&buffer, 40, variant == 3 ? 40 : replyCapacity);
            int passed;
            if(variant == 0) {
                passed = is_reply(&buffer, result, 1001, KERN_SUCCESS, 44) &&
                    word(&buffer, 36) == 1 && word(&buffer, 40) > 0;
            } else if(variant == 1) {
                passed = is_reply(&buffer, result, 1001, MIG_ARRAY_TOO_LARGE, 36);
            } else if(variant == 2) {
                passed = buffer.message.reply.RetCode != KERN_SUCCESS &&
                    is_reply(&buffer, result, 1001,
                        buffer.message.reply.RetCode, 36);
            } else {
                passed = result == MACH_RCV_TOO_LARGE &&
                    buffer.message.reply.Head.msgh_size == 44;
            }
            static const char *names[] = {"clock-resolution", "clock-large-count",
                "clock-invalid-flavor", "clock-short-reply"};
            report(names[variant], passed);
        }
        mach_port_deallocate(mach_task_self(), clock);
    }
    mach_port_deallocate(mach_task_self(), host);
}

static void test_exception_ports(void) {
    report("registered-ports-isolated", mach_ports_register(
        mach_task_self(), NULL, 0) == KERN_NOT_SUPPORTED);
    /* Guest crash reporters must not install ARM32 exception handlers on the
     * native ARM64 host task. The public MIG stubs must receive a real error,
     * without consuming the reporter's own port or writing output arrays. */
    mach_port_t port = MACH_PORT_NULL;
    kern_return_t kr = mach_port_allocate(mach_task_self(),
        MACH_PORT_RIGHT_RECEIVE, &port);
    report("exception-allocate", kr == KERN_SUCCESS);
    if(kr != KERN_SUCCESS) return;
    kr = mach_port_insert_right(mach_task_self(), port, port,
        MACH_MSG_TYPE_MAKE_SEND);
    report("exception-send-right", kr == KERN_SUCCESS);
    if(kr == KERN_SUCCESS) {
        exception_mask_t masks[EXC_TYPES_COUNT];
        exception_handler_t ports[EXC_TYPES_COUNT];
        exception_behavior_t behaviors[EXC_TYPES_COUNT];
        thread_state_flavor_t flavors[EXC_TYPES_COUNT];
        for(unsigned swap = 0; swap < 2; ++swap) {
            memset(masks, 0xa5, sizeof(masks));
            memset(ports, 0xa5, sizeof(ports));
            memset(behaviors, 0xa5, sizeof(behaviors));
            memset(flavors, 0xa5, sizeof(flavors));
            mach_msg_type_number_t count = EXC_TYPES_COUNT;
            kr = swap ? task_swap_exception_ports(mach_task_self(),
                EXC_MASK_BAD_ACCESS, port, EXCEPTION_DEFAULT, ARM_THREAD_STATE,
                masks, &count, ports, behaviors, flavors) :
                task_get_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS,
                masks, &count, ports, behaviors, flavors);
            int intact = count == EXC_TYPES_COUNT;
            for(unsigned i = 0; i < EXC_TYPES_COUNT; ++i) {
                intact &= (uint32_t)masks[i] == 0xa5a5a5a5U &&
                    (uint32_t)ports[i] == 0xa5a5a5a5U &&
                    (uint32_t)behaviors[i] == 0xa5a5a5a5U &&
                    (uint32_t)flavors[i] == 0xa5a5a5a5U;
            }
            report(swap ? "exception-swap-unsupported" : "exception-get-unsupported",
                kr == KERN_NOT_SUPPORTED && intact);
        }
        report("exception-set-unsupported", task_set_exception_ports(
            mach_task_self(), EXC_MASK_BAD_ACCESS, port, EXCEPTION_DEFAULT,
            ARM_THREAD_STATE) == KERN_NOT_SUPPORTED);
        thread_t thread = mach_thread_self();
        mach_msg_type_number_t count = EXC_TYPES_COUNT;
        report("thread-exception-get-unsupported", thread_get_exception_ports(
            thread, EXC_MASK_BAD_ACCESS, masks, &count, ports, behaviors, flavors)
            == KERN_NOT_SUPPORTED && count == EXC_TYPES_COUNT);
        report("thread-exception-set-unsupported", thread_set_exception_ports(
            thread, EXC_MASK_BAD_ACCESS, port, EXCEPTION_DEFAULT, ARM_THREAD_STATE)
            == KERN_NOT_SUPPORTED);
        report("thread-exception-swap-unsupported", thread_swap_exception_ports(
            thread, EXC_MASK_BAD_ACCESS, port, EXCEPTION_DEFAULT, ARM_THREAD_STATE,
            masks, &count, ports, behaviors, flavors) == KERN_NOT_SUPPORTED);
        mach_port_deallocate(mach_task_self(), thread);
        mach_port_urefs_t refs = 0;
        report("exception-send-right-intact", mach_port_get_refs(mach_task_self(),
            port, MACH_PORT_RIGHT_SEND, &refs) == KERN_SUCCESS && refs == 1);
        mach_port_deallocate(mach_task_self(), port);
    }
    mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    test_host_clock();
    test_exception_ports();
    mach_port_t receivePort = MACH_PORT_NULL, portSet = MACH_PORT_NULL;
    kern_return_t kr = call_port(3204, 1, MACH_PORT_RIGHT_RECEIVE,
        0, 0, &receivePort);
    report("allocate-receive", kr == KERN_SUCCESS && MACH_PORT_VALID(receivePort));
    if(kr != KERN_SUCCESS) return 1;
    uint32_t refs = 0;
    report("receive-refs", call_port(3207, 2, receivePort, MACH_PORT_RIGHT_RECEIVE,
        0, &refs) == KERN_SUCCESS && refs == 1);
    report("allocate-name-collision", call_port(3203, 2, MACH_PORT_RIGHT_RECEIVE,
        receivePort, 0, NULL) == KERN_NAME_EXISTS);
    test_rename(receivePort);
    report("set-mscount", call_port(3210, 2, receivePort, 7, 0, NULL) == KERN_SUCCESS);
    report("set-seqno", call_port(3216, 2, receivePort, 41, 0, NULL) == KERN_SUCCESS);
    mach_port_status_t status = {0};
    mach_msg_type_number_t statusCount = MACH_PORT_RECEIVE_STATUS_COUNT;
    kr = mach_port_get_attributes(mach_task_self(), receivePort,
        MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&status, &statusCount);
    report("receive-status", kr == KERN_SUCCESS && status.mps_mscount == 7 &&
        status.mps_seqno == 41);
    kr = call_port(3204, 1, MACH_PORT_RIGHT_PORT_SET, 0, 0, &portSet);
    report("allocate-port-set", kr == KERN_SUCCESS && MACH_PORT_VALID(portSet));
    if(kr == KERN_SUCCESS) {
        report("move-member", call_port(3212, 2, receivePort, portSet, 0, NULL) ==
            KERN_SUCCESS);
        report("extract-member", call_port(3227, 2, receivePort, portSet, 0, NULL) ==
            KERN_SUCCESS);
        report("insert-member", call_port(3226, 2, receivePort, portSet, 0, NULL) ==
            KERN_SUCCESS);
        report("remove-memberships", call_port(3212, 2, receivePort,
            MACH_PORT_NULL, 0, NULL) == KERN_SUCCESS);
    }
    kr = mach_port_insert_right(mach_task_self(), receivePort,
        receivePort, MACH_MSG_TYPE_MAKE_SEND);
    report("create-send-right", kr == KERN_SUCCESS);
    if(kr == KERN_SUCCESS) test_validation(receivePort);
    report("destroy-receive", call_port(3205, 1, receivePort, 0, 0, NULL) ==
        KERN_SUCCESS);
    if(MACH_PORT_VALID(portSet)) {
        report("destroy-port-set", call_port(3205, 1, portSet, 0, 0, NULL) ==
            KERN_SUCCESS);
    }
    printf("mach-simple-rpc-regression: %s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
