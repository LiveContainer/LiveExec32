#include <mach/mach.h>
#include <mach/vm_page_size.h>
#include <mach/vm_purgable.h>
#include <mach/vm_statistics.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

/* The iOS 10.3 SDK exports these public LP64-address entry points without
 * exposing their declarations to 32-bit clients. */
extern kern_return_t mach_vm_allocate(
    mach_port_name_t target, mach_vm_address_t *address,
    mach_vm_size_t size, int flags);
extern kern_return_t mach_vm_purgable_control(
    mach_port_name_t target, mach_vm_offset_t address,
    vm_purgable_t control, int *state);
extern kern_return_t _kernelrpc_mach_vm_map_trap(
    mach_port_name_t target, mach_vm_offset_t *address,
    mach_vm_size_t size, mach_vm_offset_t mask, int flags,
    vm_prot_t current_protection);

static int report(const char *name, int passed) {
    printf("vm-purgable-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    const mach_vm_size_t size = vm_page_size * 2;
    mach_vm_address_t widePurgable = UINT64_MAX;
    mach_vm_address_t wideMapped = UINT64_C(0xffffffff00000000);
    vm_address_t ordinary = 0;
    vm_address_t mapPointerStorage = 0;
    kern_return_t result = mach_vm_allocate(
        mach_task_self(), &widePurgable, size,
        VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE);
    int passed = report("wide-allocate-copyout",
        result == KERN_SUCCESS &&
        widePurgable != 0 &&
        widePurgable <= UINT32_MAX);
    if (!passed) {
        return 1;
    }
    const vm_address_t purgable =
        (vm_address_t)widePurgable;
    volatile uint32_t *purgableWord =
        (volatile uint32_t *)(uintptr_t)purgable;
    *purgableWord = UINT32_C(0x51a7c0de);

    result = vm_allocate(
        mach_task_self(), &ordinary, vm_page_size,
        VM_FLAGS_ANYWHERE);
    passed &= report("ordinary-allocate",
        result == KERN_SUCCESS && ordinary != 0);

    result = _kernelrpc_mach_vm_map_trap(
        mach_task_self(), &wideMapped, vm_page_size, 0,
        VM_FLAGS_ANYWHERE, VM_PROT_READ | VM_PROT_WRITE);
    const vm_address_t mapped =
        result == KERN_SUCCESS && wideMapped <= UINT32_MAX
            ? (vm_address_t)wideMapped : 0;
    passed &= report("wide-map-copyout",
        result == KERN_SUCCESS && mapped != 0);

    result = vm_allocate(
        mach_task_self(), &mapPointerStorage, size,
        VM_FLAGS_ANYWHERE);
    const int pointerStorageAllocated =
        result == KERN_SUCCESS && mapPointerStorage != 0;
    passed &= report("map-pointer-storage",
        pointerStorageAllocated);
    if(pointerStorageAllocated) {
        mach_vm_offset_t splitInitial =
            UINT64_C(0xffffffff00000000);
        mach_vm_offset_t *splitAddress =
            (mach_vm_offset_t *)(uintptr_t)(
                mapPointerStorage + vm_page_size - sizeof(uint32_t));
        memcpy(splitAddress, &splitInitial, sizeof(splitInitial));
        const int protectedSecondPage = mprotect(
            (void *)(uintptr_t)(mapPointerStorage + vm_page_size),
            vm_page_size, PROT_NONE) == 0;
        result = protectedSecondPage
            ? _kernelrpc_mach_vm_map_trap(
                mach_task_self(), splitAddress, vm_page_size, 0,
                VM_FLAGS_ANYWHERE,
                VM_PROT_READ | VM_PROT_WRITE)
            : KERN_FAILURE;
        passed &= report("map-wide-copyin-permissions",
            protectedSecondPage && result == KERN_INVALID_ADDRESS);
        (void)mprotect(
            (void *)(uintptr_t)(mapPointerStorage + vm_page_size),
            vm_page_size, PROT_READ | PROT_WRITE);

        mach_vm_offset_t *readOnlyAddress =
            (mach_vm_offset_t *)(uintptr_t)mapPointerStorage;
        *readOnlyAddress = 0;
        const int protectedOutput = mprotect(
            (void *)(uintptr_t)mapPointerStorage,
            vm_page_size, PROT_READ) == 0;
        result = protectedOutput
            ? _kernelrpc_mach_vm_map_trap(
                mach_task_self(), readOnlyAddress, vm_page_size, 0,
                VM_FLAGS_ANYWHERE,
                VM_PROT_READ | VM_PROT_WRITE)
            : KERN_FAILURE;
        passed &= report("map-copyout-permissions",
            protectedOutput && result == KERN_INVALID_ADDRESS);
        (void)mprotect(
            (void *)(uintptr_t)mapPointerStorage,
            vm_page_size, PROT_READ | PROT_WRITE);
    }

    int state = -1;
    result = mach_vm_purgable_control(
        mach_task_self(), widePurgable + vm_page_size,
        VM_PURGABLE_GET_STATE, &state);
    passed &= report("initial-nonvolatile",
        result == KERN_SUCCESS &&
        state == VM_PURGABLE_NONVOLATILE);

    state = VM_PURGABLE_VOLATILE;
    result = mach_vm_purgable_control(
        mach_task_self(), widePurgable,
        VM_PURGABLE_SET_STATE, &state);
    passed &= report("set-volatile",
        result == KERN_SUCCESS &&
        state == VM_PURGABLE_NONVOLATILE);

    state = -1;
    result = mach_vm_purgable_control(
        mach_task_self(), widePurgable,
        VM_PURGABLE_GET_STATE, &state);
    passed &= report("get-volatile",
        result == KERN_SUCCESS &&
        ((state & VM_PURGABLE_STATE_MASK) ==
            VM_PURGABLE_VOLATILE ||
         (state & VM_PURGABLE_STATE_MASK) ==
            VM_PURGABLE_EMPTY));

    state = VM_PURGABLE_NONVOLATILE;
    result = mach_vm_purgable_control(
        mach_task_self(), widePurgable,
        VM_PURGABLE_SET_STATE, &state);
    passed &= report("restore-nonvolatile",
        result == KERN_SUCCESS &&
        ((state & VM_PURGABLE_STATE_MASK) ==
            VM_PURGABLE_VOLATILE ||
         (state & VM_PURGABLE_STATE_MASK) ==
            VM_PURGABLE_EMPTY));
    passed &= report("volatile-content",
        (state & VM_PURGABLE_STATE_MASK) == VM_PURGABLE_EMPTY ||
        *purgableWord == UINT32_C(0x51a7c0de));

    state = 0;
    result = mach_vm_purgable_control(
        mach_task_self(), UINT64_MAX,
        VM_PURGABLE_PURGE_ALL, &state);
    passed &= report("purge-all-ignores-address",
        result == KERN_SUCCESS);

    state = 0x12345678;
    result = mach_vm_purgable_control(
        mach_task_self(), ordinary,
        VM_PURGABLE_GET_STATE, &state);
    passed &= report("ordinary-rejected",
        result == KERN_INVALID_ARGUMENT &&
        state == 0x12345678);

    result = mach_vm_purgable_control(
        mach_task_self(), widePurgable,
        VM_PURGABLE_GET_STATE,
        (int *)(uintptr_t)1);
    passed &= report("invalid-state-pointer",
        result == KERN_INVALID_ADDRESS);

    const int ordinaryCleanup = ordinary == 0 ||
        vm_deallocate(mach_task_self(), ordinary,
            vm_page_size) == KERN_SUCCESS;
    const int mappedCleanup = mapped == 0 ||
        vm_deallocate(mach_task_self(), mapped,
            vm_page_size) == KERN_SUCCESS;
    const int mapPointerStorageCleanup =
        mapPointerStorage == 0 ||
        vm_deallocate(mach_task_self(), mapPointerStorage,
            size) == KERN_SUCCESS;
    const int purgableCleanup = vm_deallocate(
        mach_task_self(), purgable, size) == KERN_SUCCESS;
    passed &= report("cleanup",
        ordinaryCleanup && mappedCleanup &&
        mapPointerStorageCleanup && purgableCleanup);

    printf("vm-purgable-regression: %s\n",
        passed ? "PASS" : "FAIL");
    return !passed;
}
