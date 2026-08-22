#include <mach/mach.h>
#include <mach/vm_page_size.h>
#include <mach/vm_statistics.h>
#include <sys/mman.h>

#include <stdint.h>
#include <stdio.h>

static int report(const char *name, int passed) {
    printf("vm-allocate-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    const vm_size_t pageSize = vm_page_size;
    vm_address_t region = 0;
    kern_return_t result = vm_allocate(
        mach_task_self(), &region, pageSize * 2,
        VM_FLAGS_ANYWHERE);
    if (!report("setup", result == KERN_SUCCESS && region != 0)) {
        return 1;
    }

    volatile uint32_t *first = (volatile uint32_t *)region;
    volatile uint32_t *second =
        (volatile uint32_t *)(region + pageSize);
    *first = UINT32_C(0x1234abcd);
    *second = UINT32_C(0x5678ef90);

    const vm_address_t occupiedAddress = region + pageSize;
    vm_address_t collisionAddress = occupiedAddress;
    result = vm_allocate(
        mach_task_self(), &collisionAddress, pageSize,
        VM_MAKE_TAG(VM_MEMORY_REALLOC));
    const int collisionPassed =
        result == KERN_NO_SPACE &&
        collisionAddress == occupiedAddress &&
        *first == UINT32_C(0x1234abcd) &&
        *second == UINT32_C(0x5678ef90);
    if (!report("occupied-fixed-preserved", collisionPassed)) {
        vm_deallocate(mach_task_self(), region, pageSize * 2);
        return 1;
    }

    result = vm_deallocate(
        mach_task_self(), occupiedAddress, pageSize);
    vm_address_t freeAddress = occupiedAddress;
    if (result == KERN_SUCCESS) {
        result = vm_allocate(
            mach_task_self(), &freeAddress, pageSize,
            VM_MAKE_TAG(VM_MEMORY_REALLOC));
    }
    const int freePassed =
        result == KERN_SUCCESS &&
        freeAddress == occupiedAddress &&
        *first == UINT32_C(0x1234abcd) &&
        *second == 0;
    if (!report("free-fixed-succeeds", freePassed)) {
        vm_deallocate(mach_task_self(), region, pageSize * 2);
        return 1;
    }

    result = vm_deallocate(
        mach_task_self(), occupiedAddress, pageSize);
    vm_address_t unalignedAddress = occupiedAddress + 17;
    if (result == KERN_SUCCESS) {
        result = vm_allocate(
            mach_task_self(), &unalignedAddress, 1,
            VM_MAKE_TAG(VM_MEMORY_REALLOC));
    }
    const int roundingPassed =
        result == KERN_SUCCESS &&
        unalignedAddress == occupiedAddress &&
        *first == UINT32_C(0x1234abcd) &&
        *second == 0;
    if (!report("fixed-page-rounding", roundingPassed)) {
        vm_deallocate(mach_task_self(), region, pageSize * 2);
        return 1;
    }

    *second = UINT32_C(0xa5a5a5a5);
    void *replacement = mmap(
        (void *)occupiedAddress, pageSize,
        PROT_READ | PROT_WRITE,
        MAP_FIXED | MAP_PRIVATE | MAP_ANON, -1, 0);
    const int mmapPassed =
        replacement == (void *)occupiedAddress &&
        *first == UINT32_C(0x1234abcd) &&
        *second == 0;
    const int cleanupPassed = vm_deallocate(
        mach_task_self(), region, pageSize * 2) == KERN_SUCCESS;

    const int passed =
        report("mmap-fixed-still-replaces", mmapPassed) &&
        report("cleanup", cleanupPassed);
    printf("vm-allocate-collision-regression: %s\n",
        passed ? "PASS" : "FAIL");
    return !passed;
}
