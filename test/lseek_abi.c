#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

static int failures;

#define CHECK(condition, label) do {                                      \
    if (condition) {                                                       \
        printf("PASS %s\n", label);                                      \
    } else {                                                              \
        fprintf(stderr, "FAIL %s\n", label);                            \
        failures++;                                                       \
    }                                                                     \
} while (0)

int main(void) {
    const char *path = "/private/tmp/lc32-lseek-abi.tmp";
    const off_t largeOffset = ((off_t)UINT32_C(5) << 32) + 0x123;
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    CHECK(lseek(fd, largeOffset, SEEK_SET) == largeOffset,
          "lseek-large-set-return");
    CHECK(lseek(fd, 0, SEEK_CUR) == largeOffset,
          "lseek-large-current-return");

    const char byte = 'x';
    CHECK(write(fd, &byte, sizeof(byte)) == sizeof(byte),
          "lseek-sparse-write");
    CHECK(lseek(fd, 0, SEEK_END) == largeOffset + 1,
          "lseek-large-end-return");
    CHECK(lseek(fd, -1, SEEK_END) == largeOffset,
          "lseek-negative-offset");

    errno = 0;
    CHECK(lseek(-1, 0, SEEK_SET) == (off_t)-1 && errno == EBADF,
          "lseek-error-carry-errno");

    close(fd);
    unlink(path);
    printf("lseek ABI: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
