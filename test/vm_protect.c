#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>

extern kern_return_t mach_vm_protect(mach_port_t, uint64_t, uint64_t, boolean_t, vm_prot_t);

static int failures;
static void check(const char *name, int passed) {
    printf("vm-protect-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

int main(void) {
    vm_address_t source = 0, destination = 0;
    const vm_size_t size = 8192;
    if(vm_allocate(mach_task_self(), &source, size, VM_FLAGS_ANYWHERE) ||
       vm_allocate(mach_task_self(), &destination, size, VM_FLAGS_ANYWHERE)) return 1;
    *(uint32_t *)(uintptr_t)source = 0x12345678;
    check("read-only-unaligned-range", mach_vm_protect(mach_task_self(),
        destination + 3, 12, FALSE, VM_PROT_READ) == KERN_SUCCESS);
    check("write-protection-enforced", vm_copy(mach_task_self(), source, 4,
        destination) == KERN_PROTECTION_FAILURE);
    check("restore-write", mach_vm_protect(mach_task_self(), destination, 4096,
        FALSE, VM_PROT_READ | VM_PROT_WRITE) == KERN_SUCCESS);
    check("copy-after-restore", vm_copy(mach_task_self(), source, 4, destination) == KERN_SUCCESS &&
        *(uint32_t *)(uintptr_t)destination == 0x12345678);
    check("foreign-task-rejected", mach_vm_protect(MACH_PORT_NULL, source, 4096,
        FALSE, VM_PROT_READ) == KERN_INVALID_ARGUMENT);
    check("high-address-not-truncated", mach_vm_protect(mach_task_self(),
        UINT64_C(0x100000000) + source, 4096, FALSE, VM_PROT_READ) == KERN_INVALID_ADDRESS);
    check("oversized-range-rejected", mach_vm_protect(mach_task_self(), source,
        UINT64_MAX, FALSE, VM_PROT_READ) == KERN_INVALID_ADDRESS);
    check("invalid-permissions", mach_vm_protect(mach_task_self(), source, 4096,
        FALSE, 0x40000000) == KERN_INVALID_ARGUMENT);
    check("unmapped-range", mach_vm_protect(mach_task_self(), 0, 4096,
        FALSE, VM_PROT_READ) == KERN_INVALID_ADDRESS);
    check("zero-size", mach_vm_protect(mach_task_self(), source, 0,
        FALSE, VM_PROT_READ) == KERN_SUCCESS);
    check("max-protection-explicitly-unsupported", mach_vm_protect(mach_task_self(), source,
        4096, TRUE, VM_PROT_READ) == KERN_NOT_SUPPORTED);
    vm_deallocate(mach_task_self(), source, size);
    vm_deallocate(mach_task_self(), destination, size);
    return failures ? 1 : 0;
}
