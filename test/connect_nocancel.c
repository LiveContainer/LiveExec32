#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

extern int test_connect_nocancel(
    int, const struct sockaddr *, socklen_t);
extern int test_select_nocancel(
    int, fd_set *, fd_set *, fd_set *, struct timeval *);
extern ssize_t test_sendto_nocancel(
    int, const void *, size_t, int,
    const struct sockaddr *, socklen_t);

static int failures;

#define CHECK(condition, label) do {                                     \
    if (condition) {                                                      \
        printf("PASS %s\n", label);                                    \
    } else {                                                             \
        fprintf(stderr, "FAIL %s\n", label);                          \
        failures++;                                                      \
    }                                                                    \
} while (0)

int main(void) {
    int client = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client < 0) {
        perror("socket(AF_UNIX)");
        return 1;
    }

    struct sockaddr_un address = {};
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s",
        "/var/run/mDNSResponder");
    address.sun_len = SUN_LEN(&address);
    const int connect_result = test_connect_nocancel(client,
        (const struct sockaddr *)&address, address.sun_len);
    if (connect_result == 0) {
        printf("PASS connect-nocancel-unix-stream\n");
    } else if (errno == EPERM) {
        printf("SKIP connect-nocancel-unix-stream (sandbox)\n");
    } else {
        fprintf(stderr, "FAIL connect-nocancel-unix-stream errno=%d\n",
            errno);
        failures++;
    }

    errno = 0;
    CHECK(test_connect_nocancel(
              -1, (const struct sockaddr *)&address,
              address.sun_len) == -1 && errno == EBADF,
        "connect-nocancel-carry-errno");

    errno = 0;
    CHECK(test_connect_nocancel(
              client,
              (const struct sockaddr *)&address, 1) == -1 &&
              errno == EINVAL,
        "connect-nocancel-short-address");
    errno = 0;
    CHECK(test_connect_nocancel(client,
              (const struct sockaddr *)(uintptr_t)1, 2) == -1 &&
              errno == EFAULT,
        "connect-nocancel-bad-address");

    static const char payload[] = "lc32-nocancel";
    int readable_descriptor = open("/dev/null", O_RDONLY);
    CHECK(readable_descriptor >= 0, "select-readable-open");

    fd_set readable;
    FD_ZERO(&readable);
    FD_SET(readable_descriptor, &readable);
    struct {
        struct timeval timeout;
        uint32_t canary;
    } timeout_storage = {
        .timeout = {.tv_sec = 60, .tv_usec = 0},
        .canary = UINT32_C(0xa5c35a3c),
    };
    CHECK(test_select_nocancel(
              readable_descriptor + 1, &readable, NULL, NULL,
              &timeout_storage.timeout) == 1 &&
              FD_ISSET(readable_descriptor, &readable),
        "select-nocancel-ready");
    CHECK(timeout_storage.timeout.tv_sec == 60 &&
              timeout_storage.timeout.tv_usec == 0 &&
              timeout_storage.canary == UINT32_C(0xa5c35a3c),
        "select-nocancel-timeval32-canary");

    FD_ZERO(&readable);
    timeout_storage.timeout.tv_sec = 0;
    CHECK(test_select_nocancel(0, &readable, NULL, NULL,
              &timeout_storage.timeout) == 0,
        "select-nocancel-empty");

    errno = 0;
    timeout_storage.timeout.tv_usec = 1000000;
    CHECK(test_select_nocancel(0, NULL, NULL, NULL,
              &timeout_storage.timeout) == -1 && errno == EINVAL,
        "select-nocancel-invalid-timeval");
    timeout_storage.timeout.tv_usec = 0;
    errno = 0;
    CHECK(test_select_nocancel(-1, NULL, NULL, NULL,
              &timeout_storage.timeout) == -1 && errno == EINVAL,
        "select-nocancel-negative-count");

    errno = 0;
    CHECK(test_sendto_nocancel(-1, payload, sizeof(payload), 0,
              NULL, 0) == -1 && errno == EBADF,
        "sendto-nocancel-carry-errno");
    errno = 0;
    CHECK(test_sendto_nocancel(-1, payload, sizeof(payload), 0,
              NULL, UINT32_MAX) == -1 && errno == EBADF,
        "sendto-nocancel-null-ignores-address-length");
    errno = 0;
    CHECK(test_sendto_nocancel(client, payload, sizeof(payload), 0,
              (const struct sockaddr *)&address, 1) == -1 &&
              errno == EINVAL,
        "sendto-nocancel-short-address");
    errno = 0;
    CHECK(test_sendto_nocancel(client,
              (const void *)(uintptr_t)1, 1, 0, NULL, 0) == -1 &&
              errno == EFAULT,
        "sendto-nocancel-bad-buffer");
    errno = 0;
    CHECK(test_sendto_nocancel(client, payload, sizeof(payload), 0,
              (const struct sockaddr *)(uintptr_t)1, 2) == -1 &&
              errno == EFAULT,
        "sendto-nocancel-bad-address");

    const int descriptors[] = {readable_descriptor, client};
    for (size_t index = 0;
            index < sizeof(descriptors) / sizeof(descriptors[0]);
            ++index) {
        if (descriptors[index] >= 0 && close(descriptors[index]) != 0) {
            perror("close(socket)");
            failures++;
        }
    }
    printf("network $NOCANCEL ABI: %s\n",
        failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
