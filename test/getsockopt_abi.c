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
    CHECK(socket_fd >= 0, "getsockopt-socket");

    int socket_type = -1;
    socklen_t value_len = sizeof(socket_type);
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE,
                     &socket_type, &value_len) == 0 &&
              socket_type == SOCK_DGRAM &&
              value_len == sizeof(socket_type),
          "getsockopt-fifth-argument-r4");

    unsigned char truncated[4] = { 0xcc, 0xcc, 0xcc, 0xcc };
    value_len = 1;
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE,
                     truncated, &value_len) == 0 &&
              value_len == 1 && truncated[0] == SOCK_DGRAM &&
              truncated[1] == 0xcc && truncated[2] == 0xcc &&
              truncated[3] == 0xcc,
          "getsockopt-truncated-copyout");

    /*
     * XNU treats a NULL value as a zero-capacity query: it ignores the
     * input length, copies no option bytes, and reports zero bytes copied.
     */
    value_len = sizeof(socket_type);
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE,
                     NULL, &value_len) == 0 && value_len == 0,
          "getsockopt-null-value-zero-capacity");

    errno = 0;
    CHECK(getsockopt(socket_fd, SOL_SOCKET, 0x7fffffff,
                     NULL, (socklen_t *)(uintptr_t)1) == -1 &&
              errno == ENOPROTOOPT,
          "getsockopt-null-value-option-error-precedence");

    errno = 0;
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE,
                     NULL, NULL) == -1 && errno == EFAULT,
          "getsockopt-null-value-length-copyout-error");

    struct timeval set_timeout = {
        .tv_sec = 1,
        .tv_usec = 250000,
    };
    CHECK(setsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO,
                     &set_timeout, sizeof(set_timeout)) == 0,
          "getsockopt-timeval-setup");

    struct timeval returned_timeout = {};
    value_len = sizeof(returned_timeout);
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_RCVTIMEO,
                     &returned_timeout, &value_len) == 0 &&
              value_len == sizeof(returned_timeout) &&
              returned_timeout.tv_sec == set_timeout.tv_sec &&
              returned_timeout.tv_usec == set_timeout.tv_usec,
          "getsockopt-timeval64-to-timeval32");

    value_len = sizeof(socket_type);
    errno = 0;
    CHECK(getsockopt(-1, SOL_SOCKET, SO_TYPE,
                     &socket_type, &value_len) == -1 && errno == EBADF,
          "getsockopt-error-carry-errno");

    value_len = sizeof(socket_type);
    errno = 0;
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE,
                     (void *)(uintptr_t)1, &value_len) == -1 &&
              errno == EFAULT,
          "getsockopt-invalid-value-pointer");

    errno = 0;
    CHECK(getsockopt(socket_fd, SOL_SOCKET, SO_TYPE,
                     &socket_type, (socklen_t *)(uintptr_t)1) == -1 &&
              errno == EFAULT,
          "getsockopt-invalid-length-pointer");

    close(socket_fd);
    printf("getsockopt ABI: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
