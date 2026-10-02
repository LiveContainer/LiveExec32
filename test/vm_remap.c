#include <mach/mach.h>
#include <mach/mig_errors.h>
#include <mach/ndr.h>
#include <mach/vm_page_size.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(value, name) do { \
    printf("vm-remap-%s: %s\n", name, (value) ? "PASS" : (++failures, "FAIL")); \
} while(0)

static kern_return_t alias(vm_address_t *target, vm_address_t source,
        vm_size_t size, int flags) {
    vm_prot_t current = 0, maximum = 0;
    kern_return_t result = vm_remap(mach_task_self(), target, size, 0,
        flags, mach_task_self(), source, FALSE, &current, &maximum, VM_INHERIT_COPY);
    if(result == KERN_SUCCESS)
        CHECK((current & (VM_PROT_READ | VM_PROT_WRITE)) == (VM_PROT_READ | VM_PROT_WRITE) &&
            (maximum & current) == current, "returned-protection");
    return result;
}

static void ring_buffer(void) {
    vm_size_t size = vm_page_size * 3;
    vm_address_t region = 0;
    kern_return_t kr = vm_allocate(mach_task_self(), &region, size * 2, VM_FLAGS_ANYWHERE);
    CHECK(kr == KERN_SUCCESS, "allocate-ring");
    if(kr) return;
    CHECK(vm_deallocate(mach_task_self(), region + size, size) == KERN_SUCCESS, "release-ring-tail");
    vm_address_t tail = region + size;
    kr = alias(&tail, region, size, VM_FLAGS_FIXED);
    CHECK(kr == KERN_SUCCESS && tail == region + size, "fixed-mirror");
    if(kr) { vm_deallocate(mach_task_self(), region, size); return; }
    volatile uint8_t *bytes = (volatile uint8_t *)(uintptr_t)region;
    for(vm_size_t index = 0; index < size; ++index) bytes[index] = index % 251;
    CHECK(memcmp((const void *)(uintptr_t)region, (const void *)(uintptr_t)tail, size) == 0,
        "all-pages-shared");
    bytes[size + 17] = 201;
    CHECK(bytes[17] == 201, "alias-to-source-write");
    // Span the wrap exactly as a mirrored audio circular buffer does.
    for(unsigned index = 0; index < 32; ++index) bytes[size - 16 + index] = 100 + index;
    CHECK(bytes[size - 1] == 115 && bytes[0] == 116 && bytes[15] == 131, "wraparound-write");
    CHECK(vm_deallocate(mach_task_self(), region, size) == KERN_SUCCESS, "unmap-source");
    volatile uint8_t *mirror = (volatile uint8_t *)(uintptr_t)tail;
    mirror[size - 1] = 77;
    CHECK(mirror[0] == 116 && mirror[size - 1] == 77, "alias-retains-backing");
    CHECK(vm_deallocate(mach_task_self(), tail, size) == KERN_SUCCESS, "unmap-alias");
}

static void replacement(void) {
    const vm_size_t size = vm_page_size * 3;
    vm_address_t source = 0, target = 0;
    if(vm_allocate(mach_task_self(), &source, size, VM_FLAGS_ANYWHERE) ||
            vm_allocate(mach_task_self(), &target, size, VM_FLAGS_ANYWHERE)) {
        CHECK(0, "allocate-replacement"); return;
    }
    memset((void *)(uintptr_t)source, 0x31, size);
    memset((void *)(uintptr_t)target, 0x72, size);
    vm_address_t saved = target;
    CHECK(alias(&target, source, size, VM_FLAGS_FIXED) == KERN_NO_SPACE &&
        target == saved && *(uint8_t *)(uintptr_t)target == 0x72, "collision-preserves-target");
    CHECK(alias(&target, source, size, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE) == KERN_SUCCESS &&
        target == saved && *(uint8_t *)(uintptr_t)target == 0x31, "overwrite");
    // Overlapping aliases must retain all source pages before releasing any.
    vm_address_t overlap = source + vm_page_size;
    CHECK(alias(&overlap, source, vm_page_size * 2, VM_FLAGS_FIXED | VM_FLAGS_OVERWRITE) == KERN_SUCCESS,
        "overlap");
    *(volatile uint8_t *)(uintptr_t)source = 0x55;
    CHECK(*(volatile uint8_t *)(uintptr_t)overlap == 0x55, "overlap-snapshot");
    CHECK(vm_deallocate(mach_task_self(), source, size) == KERN_SUCCESS &&
        *(volatile uint8_t *)(uintptr_t)target == 0x55, "overwrite-retains-source");
    CHECK(vm_deallocate(mach_task_self(), target, size) == KERN_SUCCESS, "replacement-cleanup");
}

static void validation(void) {
    vm_address_t source = 0;
    CHECK(vm_allocate(mach_task_self(), &source, vm_page_size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS,
        "allocate-validation");
    vm_address_t target = 0;
    CHECK(alias(&target, source, vm_page_size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS && target,
        "anywhere");
    vm_deallocate(mach_task_self(), target, vm_page_size);
    target = 0x12345678;
    vm_prot_t current = 0x55, maximum = 0x66;
    CHECK(vm_remap(mach_task_self(), &target, vm_page_size, 0, VM_FLAGS_ANYWHERE,
        mach_task_self(), 0, FALSE, &current, &maximum, VM_INHERIT_COPY) == KERN_INVALID_ADDRESS &&
        target == 0x12345678 && current == 0x55 && maximum == 0x66, "bad-source-output-unchanged");
    mach_port_t other = mach_host_self();
    CHECK(vm_remap(mach_task_self(), &target, vm_page_size, 0, VM_FLAGS_ANYWHERE,
        other, source, FALSE, &current, &maximum, VM_INHERIT_COPY) == KERN_INVALID_ARGUMENT,
        "nonself-source");
    mach_port_deallocate(mach_task_self(), other);
    vm_deallocate(mach_task_self(), source, vm_page_size);
}

static void protection_and_holes(void) {
    vm_address_t source = 0, target = 0;
    if(vm_allocate(mach_task_self(), &source, vm_page_size * 2, VM_FLAGS_ANYWHERE)) {
        CHECK(0, "allocate-protection"); return;
    }
    *(uint8_t *)(uintptr_t)source = 0x93;
    CHECK(vm_protect(mach_task_self(), source, vm_page_size, FALSE, VM_PROT_READ) == KERN_SUCCESS,
        "readonly-source");
    vm_prot_t current = 0, maximum = 0;
    CHECK(vm_remap(mach_task_self(), &target, vm_page_size, vm_page_size * 4 - 1,
        VM_FLAGS_ANYWHERE, mach_task_self(), source, FALSE, &current, &maximum,
        VM_INHERIT_COPY) == KERN_SUCCESS && current == VM_PROT_READ &&
        !(target & (vm_page_size * 4 - 1)) && *(uint8_t *)(uintptr_t)target == 0x93,
        "readonly-aligned-alias");
    CHECK(vm_protect(mach_task_self(), target, vm_page_size, FALSE, VM_PROT_NONE) == KERN_SUCCESS &&
        *(uint8_t *)(uintptr_t)source == 0x93, "alias-protection-independent");
    vm_deallocate(mach_task_self(), target, vm_page_size);
    CHECK(vm_deallocate(mach_task_self(), source + vm_page_size, vm_page_size) == KERN_SUCCESS,
        "source-hole");
    target = 0x12345678;
    CHECK(vm_remap(mach_task_self(), &target, vm_page_size * 2, 0,
        VM_FLAGS_ANYWHERE, mach_task_self(), source, FALSE, &current, &maximum,
        VM_INHERIT_COPY) == KERN_INVALID_ADDRESS && target == 0x12345678,
        "hole-rejected-atomically");
#if !__LP64__
    CHECK(vm_remap(mach_task_self(), &target, vm_page_size, 0,
        VM_FLAGS_ANYWHERE, mach_task_self(), source, TRUE, &current, &maximum,
        VM_INHERIT_COPY) == KERN_NOT_SUPPORTED && target == 0x12345678,
        "cow-explicitly-unsupported");
    CHECK(vm_remap(mach_task_self(), &target, 16, 0,
        VM_FLAGS_ANYWHERE, mach_task_self(), source + 1, FALSE, &current, &maximum,
        VM_INHERIT_COPY) == KERN_NOT_SUPPORTED && target == 0x12345678,
        "unaligned-explicitly-unsupported");
#endif
    vm_deallocate(mach_task_self(), source, vm_page_size);
}

// Raw ARM32 MIG requests exercise rejection without entering the VM helper.
#if !__LP64__
struct __attribute__((packed, aligned(4))) request32 {
    mach_msg_header_t head;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t task;
    NDR_record_t ndr;
    uint32_t address, size, mask;
    int flags;
    uint32_t source;
    boolean_t copy;
    vm_inherit_t inheritance;
};
_Static_assert(sizeof(struct request32) == 76, "ARM32 remap request");

static void malformed(unsigned variant) {
    union { struct request32 request; mig_reply_error_t reply; uint8_t bytes[128]; } message = {0};
    mach_port_t port = MACH_PORT_NULL;
    if(mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port)) {
        CHECK(0, "raw-reply-port"); return;
    }
    message.request.head.msgh_bits = MACH_MSGH_BITS_COMPLEX |
        MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    message.request.head.msgh_remote_port = mach_task_self();
    message.request.head.msgh_local_port = port;
    message.request.head.msgh_id = 3814;
    message.request.body.msgh_descriptor_count = 1;
    message.request.task.name = mach_task_self();
    message.request.task.disposition = MACH_MSG_TYPE_COPY_SEND;
    message.request.task.type = MACH_MSG_PORT_DESCRIPTOR;
    message.request.ndr = NDR_record;
    message.request.size = vm_page_size;
    message.request.flags = VM_FLAGS_ANYWHERE;
    message.request.inheritance = VM_INHERIT_COPY;
    mach_msg_size_t sendSize = sizeof(struct request32), receiveSize = sizeof(message);
    switch(variant) {
        case 0: --sendSize; break;
        case 1: message.request.head.msgh_bits &= ~MACH_MSGH_BITS_COMPLEX; break;
        case 2: message.request.body.msgh_descriptor_count = 2; break;
        case 3: message.request.task.type = MACH_MSG_OOL_DESCRIPTOR; break;
        case 4: message.request.task.disposition = MACH_MSG_TYPE_MOVE_SEND; break;
        case 5: message.request.ndr.int_rep ^= 1; break;
        case 6: receiveSize = sizeof(mach_msg_header_t); break;
        case 7: receiveSize = sizeof(mig_reply_error_t); break;
    }
    mach_msg_return_t status = mach_msg(&message.request.head,
        MACH_SEND_MSG | MACH_RCV_MSG, sendSize, receiveSize, port, 0, MACH_PORT_NULL);
    if(variant >= 6) {
        CHECK(status == MACH_RCV_TOO_LARGE && message.reply.Head.msgh_size ==
            (variant == 6 ? 36 : 48), "raw-short-receive");
    } else {
        CHECK(status == MACH_MSG_SUCCESS && message.reply.Head.msgh_id == 3914 &&
            message.reply.Head.msgh_size == sizeof(mig_reply_error_t) &&
            !(message.reply.Head.msgh_bits & MACH_MSGH_BITS_COMPLEX) &&
            message.reply.RetCode == MIG_BAD_ARGUMENTS, "raw-malformed");
    }
    CHECK(mach_port_destroy(mach_task_self(), port) == KERN_SUCCESS, "raw-port-cleanup");
}
#endif

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    ring_buffer();
    replacement();
    validation();
    protection_and_holes();
#if !__LP64__
    for(unsigned variant = 0; variant < 8; ++variant) malformed(variant);
#endif
    return failures ? 1 : 0;
}
