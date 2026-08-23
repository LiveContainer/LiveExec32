#include <mach/mach.h>
#include <mach/vm_page_size.h>
#include <sys/mman.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int cleanupPassed = 1;

static int report(const char *name, int passed) {
    printf("vm-copy-%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed;
}

static int allocate_region(vm_address_t *address, vm_size_t size) {
    *address = 0;
    return vm_allocate(mach_task_self(), address, size,
        VM_FLAGS_ANYWHERE) == KERN_SUCCESS && *address != 0;
}

static void deallocate_region(vm_address_t address, vm_size_t size) {
    if(address && vm_deallocate(
            mach_task_self(), address, size) != KERN_SUCCESS) {
        cleanupPassed = 0;
    }
}

static void fill_pattern(uint8_t *bytes, size_t size, uint8_t salt) {
    for(size_t index = 0; index < size; ++index) {
        bytes[index] = (uint8_t)(index * 37u + salt);
    }
}

static int bytes_equal_value(
        const uint8_t *bytes, size_t size, uint8_t value) {
    for(size_t index = 0; index < size; ++index) {
        if(bytes[index] != value) return 0;
    }
    return 1;
}

static int test_cross_page_unaligned(vm_size_t pageSize) {
    const vm_size_t regionSize = pageSize * 3;
    const vm_size_t sourceOffset = pageSize - 31;
    const vm_size_t destinationOffset = pageSize - 17;
    const vm_size_t copySize = pageSize + 137;
    vm_address_t source = 0;
    vm_address_t destination = 0;
    uint8_t *expected = NULL;
    int passed = 0;

    if(!allocate_region(&source, regionSize) ||
       !allocate_region(&destination, regionSize)) {
        goto cleanup;
    }

    fill_pattern((uint8_t *)(uintptr_t)source, regionSize, 11);
    memset((void *)(uintptr_t)destination, 0xa5, regionSize);
    expected = malloc(copySize);
    if(!expected) goto cleanup;
    memcpy(expected,
        (const void *)(uintptr_t)(source + sourceOffset), copySize);

    const kern_return_t result = vm_copy(
        mach_task_self(), source + sourceOffset, copySize,
        destination + destinationOffset);
    const uint8_t *destinationBytes =
        (const uint8_t *)(uintptr_t)destination;
    passed = result == KERN_SUCCESS &&
        memcmp(destinationBytes + destinationOffset,
            expected, copySize) == 0 &&
        destinationBytes[destinationOffset - 1] == 0xa5 &&
        destinationBytes[destinationOffset + copySize] == 0xa5;

cleanup:
    free(expected);
    deallocate_region(destination, regionSize);
    deallocate_region(source, regionSize);
    return passed;
}

static int test_overlap(vm_size_t pageSize, int destinationAfterSource) {
    const vm_size_t regionSize = pageSize * 3;
    const vm_size_t lowerOffset = pageSize / 2 - 19;
    const vm_size_t displacement = 73;
    const vm_size_t copySize = pageSize + 333;
    const vm_size_t sourceOffset = destinationAfterSource
        ? lowerOffset : lowerOffset + displacement;
    const vm_size_t destinationOffset = destinationAfterSource
        ? lowerOffset + displacement : lowerOffset;
    vm_address_t region = 0;
    uint8_t *expected = NULL;
    int passed = 0;

    if(!allocate_region(&region, regionSize)) goto cleanup;
    fill_pattern((uint8_t *)(uintptr_t)region, regionSize,
        destinationAfterSource ? 29 : 71);
    expected = malloc(regionSize);
    if(!expected) goto cleanup;
    memcpy(expected, (const void *)(uintptr_t)region, regionSize);
    memmove(expected + destinationOffset, expected + sourceOffset, copySize);

    const kern_return_t result = vm_copy(
        mach_task_self(), region + sourceOffset, copySize,
        region + destinationOffset);
    passed = result == KERN_SUCCESS &&
        memcmp((const void *)(uintptr_t)region,
            expected, regionSize) == 0;

cleanup:
    free(expected);
    deallocate_region(region, regionSize);
    return passed;
}

static int test_zero_size_invalid_addresses(void) {
    const vm_address_t invalidLow = 1;
    const vm_address_t invalidHigh = ~(vm_address_t)0;
    return vm_copy(mach_task_self(), invalidLow, 0, invalidHigh) ==
            KERN_SUCCESS &&
        vm_copy(mach_task_self(), invalidHigh, 0, invalidLow) ==
            KERN_SUCCESS;
}

static int test_nonself_target_rejected(void) {
    const mach_port_t host = mach_host_self();
    const kern_return_t result = vm_copy(host, 1, 0, 1);
    const kern_return_t cleanup = mach_port_deallocate(
        mach_task_self(), host);
    return result == KERN_INVALID_ARGUMENT &&
        cleanup == KERN_SUCCESS;
}

static int test_source_hole_is_atomic(vm_size_t pageSize) {
    const vm_size_t regionSize = pageSize * 3;
    vm_address_t source = 0;
    vm_address_t destination = 0;
    int middleRemoved = 0;
    int passed = 0;

    if(!allocate_region(&source, regionSize) ||
       !allocate_region(&destination, regionSize)) {
        goto cleanup;
    }
    fill_pattern((uint8_t *)(uintptr_t)source, regionSize, 43);
    memset((void *)(uintptr_t)destination, 0x6d, regionSize);
    middleRemoved = vm_deallocate(
        mach_task_self(), source + pageSize, pageSize) == KERN_SUCCESS;
    if(!middleRemoved) goto cleanup;

    const kern_return_t result = vm_copy(
        mach_task_self(), source, regionSize, destination);
    passed = result == KERN_INVALID_ADDRESS && bytes_equal_value(
        (const uint8_t *)(uintptr_t)destination, regionSize, 0x6d);

cleanup:
    if(middleRemoved) {
        deallocate_region(source, pageSize);
        deallocate_region(source + pageSize * 2, pageSize);
    } else {
        deallocate_region(source, regionSize);
    }
    deallocate_region(destination, regionSize);
    return passed;
}

static int test_source_protection_is_atomic(vm_size_t pageSize) {
    const vm_size_t regionSize = pageSize * 3;
    vm_address_t source = 0;
    vm_address_t destination = 0;
    int protected = 0;
    int passed = 0;

    if(!allocate_region(&source, regionSize) ||
       !allocate_region(&destination, regionSize)) {
        goto cleanup;
    }
    fill_pattern((uint8_t *)(uintptr_t)source, regionSize, 131);
    memset((void *)(uintptr_t)destination, 0x87, regionSize);
    protected = mprotect(
        (void *)(uintptr_t)(source + pageSize),
        pageSize, PROT_NONE) == 0;
    if(!protected) goto cleanup;

    const kern_return_t result = vm_copy(
        mach_task_self(), source, regionSize, destination);
    passed = result == KERN_PROTECTION_FAILURE && bytes_equal_value(
        (const uint8_t *)(uintptr_t)destination, regionSize, 0x87);

cleanup:
    if(protected && mprotect(
            (void *)(uintptr_t)(source + pageSize), pageSize,
            PROT_READ | PROT_WRITE) != 0) {
        cleanupPassed = 0;
    }
    deallocate_region(destination, regionSize);
    deallocate_region(source, regionSize);
    return passed;
}

static int test_destination_hole_is_atomic(vm_size_t pageSize) {
    const vm_size_t regionSize = pageSize * 3;
    vm_address_t source = 0;
    vm_address_t destination = 0;
    int middleRemoved = 0;
    int passed = 0;

    if(!allocate_region(&source, regionSize) ||
       !allocate_region(&destination, regionSize)) {
        goto cleanup;
    }
    fill_pattern((uint8_t *)(uintptr_t)source, regionSize, 173);
    memset((void *)(uintptr_t)destination, 0x39, regionSize);
    middleRemoved = vm_deallocate(
        mach_task_self(), destination + pageSize,
        pageSize) == KERN_SUCCESS;
    if(!middleRemoved) goto cleanup;

    const kern_return_t result = vm_copy(
        mach_task_self(), source, regionSize, destination);
    passed = result == KERN_INVALID_ADDRESS &&
        bytes_equal_value(
            (const uint8_t *)(uintptr_t)destination,
            pageSize, 0x39) &&
        bytes_equal_value(
            (const uint8_t *)(uintptr_t)(destination + pageSize * 2),
            pageSize, 0x39);

cleanup:
    if(middleRemoved) {
        deallocate_region(destination, pageSize);
        deallocate_region(destination + pageSize * 2, pageSize);
    } else {
        deallocate_region(destination, regionSize);
    }
    deallocate_region(source, regionSize);
    return passed;
}

static int test_destination_protection_is_atomic(vm_size_t pageSize) {
    const vm_size_t regionSize = pageSize * 3;
    vm_address_t source = 0;
    vm_address_t destination = 0;
    int protected = 0;
    int passed = 0;

    if(!allocate_region(&source, regionSize) ||
       !allocate_region(&destination, regionSize)) {
        goto cleanup;
    }
    fill_pattern((uint8_t *)(uintptr_t)source, regionSize, 211);
    memset((void *)(uintptr_t)destination, 0xc3, regionSize);
    protected = mprotect(
        (void *)(uintptr_t)(destination + pageSize),
        pageSize, PROT_READ) == 0;
    if(!protected) goto cleanup;

    const kern_return_t result = vm_copy(
        mach_task_self(), source, regionSize, destination);
    passed = result == KERN_PROTECTION_FAILURE &&
        bytes_equal_value(
            (const uint8_t *)(uintptr_t)destination,
            regionSize, 0xc3);

cleanup:
    if(protected && mprotect(
            (void *)(uintptr_t)(destination + pageSize), pageSize,
            PROT_READ | PROT_WRITE) != 0) {
        cleanupPassed = 0;
    }
    deallocate_region(destination, regionSize);
    deallocate_region(source, regionSize);
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    const vm_size_t pageSize = vm_page_size;
    int passed = report("page-size", pageSize > 128);
    if(pageSize <= 128) return 1;

    passed &= report("cross-page-unaligned",
        test_cross_page_unaligned(pageSize));
    passed &= report("overlap-destination-after-source",
        test_overlap(pageSize, 1));
    passed &= report("overlap-destination-before-source",
        test_overlap(pageSize, 0));
    passed &= report("zero-size-invalid-addresses",
        test_zero_size_invalid_addresses());
    passed &= report("nonself-target-rejected",
        test_nonself_target_rejected());
    passed &= report("source-hole-destination-unchanged",
        test_source_hole_is_atomic(pageSize));
    passed &= report("source-protection-destination-unchanged",
        test_source_protection_is_atomic(pageSize));
    passed &= report("destination-hole-unchanged",
        test_destination_hole_is_atomic(pageSize));
    passed &= report("destination-protection-unchanged",
        test_destination_protection_is_atomic(pageSize));
    passed &= report("cleanup", cleanupPassed);

    printf("vm-copy-regression: %s\n", passed ? "PASS" : "FAIL");
    return !passed;
}
