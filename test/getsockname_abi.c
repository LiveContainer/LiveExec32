#include <errno.h>
#include <netinet/in.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
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
    int inet_socket = socket(AF_INET, SOCK_DGRAM, 0);
    CHECK(inet_socket >= 0, "getsockname-ipv4-socket");

    struct sockaddr_in bind_address = {};
    bind_address.sin_len = sizeof(bind_address);
    bind_address.sin_family = AF_INET;
    bind_address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind_address.sin_port = 0;
    CHECK(bind(inet_socket, (const struct sockaddr *)&bind_address,
               sizeof(bind_address)) == 0,
          "getsockname-ipv4-bind");

    struct sockaddr_in inet_address = {};
    socklen_t inet_address_len = sizeof(inet_address);
    CHECK(getsockname(inet_socket, (struct sockaddr *)&inet_address,
                      &inet_address_len) == 0 &&
              inet_address_len == sizeof(inet_address) &&
              inet_address.sin_len == sizeof(inet_address) &&
              inet_address.sin_family == AF_INET &&
              inet_address.sin_addr.s_addr == htonl(INADDR_LOOPBACK) &&
              inet_address.sin_port != 0,
          "getsockname-ipv4-address");

    unsigned char truncated[sizeof(struct sockaddr_in) + 1];
    memset(truncated, 0xa5, sizeof(truncated));
    socklen_t truncated_len = 2;
    CHECK(getsockname(inet_socket, (struct sockaddr *)truncated,
                      &truncated_len) == 0 &&
              truncated_len == sizeof(struct sockaddr_in) &&
              truncated[0] == sizeof(struct sockaddr_in) &&
              truncated[1] == AF_INET &&
              truncated[2] == 0xa5,
          "getsockname-truncated-output");

    socklen_t zero_len = 0;
    CHECK(getsockname(inet_socket, NULL, &zero_len) == 0 &&
              zero_len == sizeof(struct sockaddr_in),
          "getsockname-zero-length-null-address");

    socklen_t bad_address_len = sizeof(struct sockaddr_in);
    errno = 0;
    CHECK(getsockname(inet_socket, NULL, &bad_address_len) == -1 &&
              errno == EFAULT,
          "getsockname-null-address-error");
    close(inet_socket);

    char unix_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    snprintf(unix_path, sizeof(unix_path),
             "/usr/local/lc32-getsockname-abi.%d.sock", getpid());
    unlink(unix_path);
    int unix_socket = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECK(unix_socket >= 0, "getsockname-unix-socket");

    struct sockaddr_un unix_bind_address = {};
    unix_bind_address.sun_family = AF_UNIX;
    snprintf(unix_bind_address.sun_path,
             sizeof(unix_bind_address.sun_path), "%s", unix_path);
    unix_bind_address.sun_len = SUN_LEN(&unix_bind_address);
    CHECK(bind(unix_socket,
               (const struct sockaddr *)&unix_bind_address,
               unix_bind_address.sun_len) == 0,
          "getsockname-unix-bind");

    struct sockaddr_un unix_address = {};
    socklen_t unix_address_len = sizeof(unix_address);
    CHECK(getsockname(unix_socket,
                      (struct sockaddr *)&unix_address,
                      &unix_address_len) == 0 &&
              unix_address.sun_family == AF_UNIX &&
              unix_address_len == SUN_LEN(&unix_bind_address) &&
              unix_address.sun_len == unix_address_len &&
              strcmp(unix_address.sun_path, unix_path) == 0,
          "getsockname-unix-guest-path");
    close(unix_socket);
    unlink(unix_path);

    struct sockaddr_in invalid_address = {};
    socklen_t invalid_address_len = sizeof(invalid_address);
    errno = 0;
    CHECK(getsockname(-1, (struct sockaddr *)&invalid_address,
                      &invalid_address_len) == -1 && errno == EBADF,
          "getsockname-error-carry-errno");

    printf("getsockname ABI: %s\n",
           failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
