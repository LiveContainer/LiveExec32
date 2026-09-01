#include <errno.h>
#include <fcntl.h>
#include <mach/machine.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

enum {
    GuestPageSize = 0x1000,
    GuestMappingSize = 0x4000,
    NullCryptID = 0x10,
};

static int failures;

#define CHECK(condition, label) do {                                    \
    if(condition) {                                                      \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while(0)

static uint32_t hash_bytes(const uint8_t *bytes, size_t size) {
    uint32_t hash = UINT32_C(2166136261);
    for(size_t index = 0; index < size; ++index) {
        hash ^= bytes[index];
        hash *= UINT32_C(16777619);
    }
    return hash;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);

    errno = 0;
    CHECK(syscall(SYS_mremap_encrypted,
              (void *)(uintptr_t)0x1000, 0,
              0, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S) == 0,
        "mremap-encrypted-cryptid-zero-noop");

    errno = 0;
    CHECK(syscall(SYS_mremap_encrypted,
              (void *)(uintptr_t)0x1001, GuestPageSize,
              0, CPU_TYPE_ARM, CPU_SUBTYPE_ARM_V7S) == -1 &&
              errno == EINVAL,
        "mremap-encrypted-guest-alignment");

    if(argc < 1 || argv == NULL || argv[0] == NULL) {
        fprintf(stderr, "FAIL mremap-encrypted-arguments\n");
        return 1;
    }
    int descriptor = open(argv[0], O_RDONLY);
    struct stat info = {};
    if(descriptor < 0 || fstat(descriptor, &info) != 0 ||
            info.st_size < GuestMappingSize) {
        perror("mremap-encrypted executable setup");
        if(descriptor >= 0) close(descriptor);
        return 1;
    }

    uint8_t *mapping = mmap(NULL, GuestMappingSize,
        PROT_READ | PROT_EXEC, MAP_PRIVATE, descriptor, 0);
    close(descriptor);
    if(mapping == MAP_FAILED) {
        perror("mremap-encrypted mmap");
        return 1;
    }
    const struct mach_header *header =
        (const struct mach_header *)mapping;
    if(header->magic != MH_MAGIC || header->cputype != CPU_TYPE_ARM) {
        fprintf(stderr, "FAIL mremap-encrypted Mach-O setup\n");
        munmap(mapping, GuestMappingSize);
        return 1;
    }

    uint8_t *testPage = mapping + GuestPageSize;
    const uint32_t originalHash = hash_bytes(testPage, GuestPageSize);

    errno = 0;
    CHECK(syscall(SYS_mremap_encrypted,
              testPage, GuestPageSize, UINT32_C(0xfeedface),
              header->cputype, header->cpusubtype) == -1 &&
              errno == EINVAL,
        "mremap-encrypted-invalid-cryptid");
    CHECK(hash_bytes(testPage, GuestPageSize) == originalHash,
        "mremap-encrypted-error-preserves-bytes");

    /* com.apple.null exercises the vnode-backed staging/remap path without
     * requiring a FairPlay license. It is not installed on every kernel, so
     * an unavailable crypter is a supported skip rather than a failure. */
    const uint32_t nullOriginalHash =
        hash_bytes(mapping, GuestPageSize);
    errno = 0;
    const long nullResult = syscall(SYS_mremap_encrypted,
        mapping, GuestPageSize, NullCryptID,
        header->cputype, header->cpusubtype);
    const int nullError = errno;
    if(nullResult == 0) {
        CHECK(hash_bytes(mapping, GuestPageSize) == nullOriginalHash,
            "mremap-encrypted-null-preserves-bytes");
    } else if(nullError == ENOTSUP || nullError == ENOMEM ||
              nullError == EPERM || nullError == EACCES) {
        printf("SKIP mremap-encrypted-null-crypter (errno=%d)\n",
            nullError);
    } else {
        fprintf(stderr,
            "FAIL mremap-encrypted-null-crypter (errno=%d)\n",
            nullError);
        failures++;
    }

    CHECK(munmap(mapping, GuestMappingSize) == 0,
        "mremap-encrypted-cleanup");
    printf("mremap-encrypted regression: %s\n",
        failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
