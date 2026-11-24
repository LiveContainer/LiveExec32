#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

struct GuestFSignatures {
    int64_t fileStart;
    uint32_t blobStart;
    uint32_t blobSize;
};

_Static_assert(sizeof(struct GuestFSignatures) == 16,
    "unexpected 32-bit fsignatures layout");

static int failures;

#define CHECK(condition, label) do {                                    \
    if(condition) {                                                      \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while(0)

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if(argc < 1 || argv == NULL || argv[0] == NULL) {
        fprintf(stderr, "FAIL fcntl-filesigs-return-arguments\n");
        return 1;
    }

    const int descriptor = open(argv[0], O_RDONLY);
    struct stat fileStatus = {};
    if(descriptor < 0 || fstat(descriptor, &fileStatus) != 0 ||
            fileStatus.st_size < 0) {
        perror("fcntl-filesigs-return setup");
        if(descriptor >= 0) close(descriptor);
        return 1;
    }

    struct GuestFSignatures signatures = {
        .fileStart = -1,
        .blobStart = UINT32_C(0x12345678),
        .blobSize = UINT32_C(0x87654321),
    };
    const struct GuestFSignatures original = signatures;
    errno = 0;
    CHECK(fcntl(descriptor, F_ADDFILESIGS, &signatures) == 0 &&
              memcmp(&signatures, &original, sizeof(signatures)) == 0,
          "fcntl-filesigs-input-only-registration");
    errno = 0;
    CHECK(fcntl(descriptor, F_ADDFILESIGS, NULL) == -1 && errno == EFAULT,
          "fcntl-filesigs-null-structure");
    errno = 0;
    CHECK(fcntl(-1, F_ADDFILESIGS, &signatures) == -1 && errno == EBADF &&
              memcmp(&signatures, &original, sizeof(signatures)) == 0,
          "fcntl-filesigs-invalid-fd-preserves-input");

    const size_t pageSize = (size_t)getpagesize();
    char *pages = mmap(NULL, pageSize * 2, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANON, -1, 0);
    CHECK(pages != MAP_FAILED, "fcntl-filesigs-guard-allocation");
    if(pages != MAP_FAILED) {
        struct GuestFSignatures *atEnd =
            (struct GuestFSignatures *)(pages + pageSize - sizeof(signatures));
        *atEnd = original;
        CHECK(mprotect(pages, pageSize, PROT_READ) == 0 &&
                  mprotect(pages + pageSize, pageSize, PROT_NONE) == 0,
              "fcntl-filesigs-guard-protection");
        CHECK(fcntl(descriptor, F_ADDFILESIGS, atEnd) == 0 &&
                  memcmp(atEnd, &original, sizeof(original)) == 0,
              "fcntl-filesigs-readonly-16-byte-input");
        errno = 0;
        CHECK(fcntl(descriptor, F_ADDFILESIGS,
                    pages + pageSize - sizeof(signatures) + 4) == -1 &&
                  errno == EFAULT,
              "fcntl-filesigs-truncated-structure");
        errno = 0;
        CHECK(fcntl(descriptor, F_ADDFILESIGS_RETURN, atEnd) == -1 &&
                  errno == EFAULT &&
                  memcmp(atEnd, &original, sizeof(original)) == 0,
              "fcntl-filesigs-return-requires-writable-output");
        CHECK(munmap(pages, pageSize * 2) == 0,
              "fcntl-filesigs-guard-release");
    }
    errno = 0;
    CHECK(fcntl(descriptor, F_ADDFILESIGS_RETURN, &signatures) == 0 &&
              signatures.fileStart == fileStatus.st_size,
          "fcntl-filesigs-return-synthesizes-full-coverage");
    CHECK(signatures.blobStart == UINT32_C(0x12345678) &&
              signatures.blobSize == UINT32_C(0x87654321),
          "fcntl-filesigs-return-preserves-input-fields");

    errno = 0;
    CHECK(fcntl(descriptor, F_ADDFILESIGS_RETURN, NULL) == -1 &&
              errno == EFAULT,
          "fcntl-filesigs-return-null-structure");

    signatures.fileStart = INT64_C(0x123456789);
    errno = 0;
    CHECK(fcntl(-1, F_ADDFILESIGS_RETURN, &signatures) == -1 &&
              errno == EBADF &&
              signatures.fileStart == INT64_C(0x123456789),
          "fcntl-filesigs-return-invalid-fd-preserves-output");

    CHECK(close(descriptor) == 0, "fcntl-filesigs-return-close");
    printf("fcntl-filesigs-return regression: %s\n",
        failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
