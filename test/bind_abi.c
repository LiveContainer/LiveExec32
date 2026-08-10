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
    CHECK(inet_socket >= 0, "bind-ipv4-socket");

    struct sockaddr_in inet_address = {};
    inet_address.sin_len = sizeof(inet_address);
    inet_address.sin_family = AF_INET;
    inet_address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    inet_address.sin_port = 0;
    CHECK(bind(inet_socket, (const struct sockaddr *)&inet_address,
               sizeof(inet_address)) == 0,
          "bind-ipv4-loopback");
    close(inet_socket);

    char unix_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    snprintf(unix_path, sizeof(unix_path),
             "/usr/local/lc32-bind-abi.%d.sock", getpid());
    unlink(unix_path);
    int unix_socket = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECK(unix_socket >= 0, "bind-unix-socket");

    struct sockaddr_un unix_address = {};
    unix_address.sun_family = AF_UNIX;
    snprintf(unix_address.sun_path, sizeof(unix_address.sun_path),
             "%s", unix_path);
    unix_address.sun_len = SUN_LEN(&unix_address);
    CHECK(bind(unix_socket, (const struct sockaddr *)&unix_address,
               unix_address.sun_len) == 0,
          "bind-unix-translated-path");
    CHECK(access(unix_path, F_OK) == 0, "bind-unix-created-node");
    close(unix_socket);
    unlink(unix_path);

    errno = 0;
    CHECK(bind(-1, (const struct sockaddr *)&inet_address,
               sizeof(inet_address)) == -1 && errno == EBADF,
          "bind-error-carry-errno");

    printf("bind ABI: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
