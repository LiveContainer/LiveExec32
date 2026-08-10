#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static int failures;

#define CHECK(condition, label) do {                                    \
    if (condition) {                                                     \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while (0)

int main(void) {
    int socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    CHECK(socket_fd >= 0, "setsockopt-socket");

    int receive_buffer = 64 * 1024;
    CHECK(setsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF,
                     &receive_buffer, sizeof(receive_buffer)) == 0,
          "setsockopt-fifth-argument-r4");

    /*
     * timeval is two 32-bit fields in this armv7 guest and has a different
     * layout in the arm64 Simulator process.
     */
    struct timeval timeout = { .tv_sec = 0, .tv_usec = 250000 };
    CHECK(setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO,
                     &timeout, sizeof(timeout)) == 0,
          "setsockopt-timeval32");

    errno = 0;
    CHECK(setsockopt(-1, SOL_SOCKET, SO_RCVBUF,
                     &receive_buffer, sizeof(receive_buffer)) == -1 &&
              errno == EBADF,
          "setsockopt-error-carry-errno");

    errno = 0;
    CHECK(setsockopt(socket_fd, SOL_SOCKET, SO_RCVBUF,
                     (const void *)(uintptr_t)1,
                     sizeof(receive_buffer)) == -1 && errno == EFAULT,
          "setsockopt-invalid-guest-pointer");

    close(socket_fd);
    printf("setsockopt ABI: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
