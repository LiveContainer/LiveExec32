#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
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

static int count_open_descriptors(void) {
    const int maximum = getdtablesize();
    int count = 0;
    for (int descriptor = 0; descriptor < maximum; ++descriptor) {
        if (fcntl(descriptor, F_GETFD) != -1) count++;
    }
    return count;
}

static int connect_ipv4(const struct sockaddr_in *server) {
    const int client = socket(AF_INET, SOCK_STREAM, 0);
    if (client < 0) return -1;
    if (connect(client, (const struct sockaddr *)server,
                sizeof(*server)) != 0) {
        close(client);
        return -1;
    }
    return client;
}

static void test_ipv4(void) {
    struct sockaddr_in invalid = {};
    socklen_t invalid_length = sizeof(invalid);
    errno = 0;
    CHECK(getpeername(-1, (struct sockaddr *)&invalid,
                      &invalid_length) == -1 && errno == EBADF,
          "getpeername-error-carry-errno");

    const int listener = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(listener >= 0, "accept-ipv4-listener");
    if (listener < 0) return;

    struct sockaddr_in server = {};
    server.sin_len = sizeof(server);
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    errno = 0;
    const int bind_result = bind(
        listener, (const struct sockaddr *)&server, sizeof(server));
    if (bind_result != 0 && errno == EPERM) {
        printf("SKIP accept-ipv4 (sandbox denied bind)\n");
        close(listener);
        return;
    }
    CHECK(bind_result == 0, "accept-ipv4-bind");
    if (bind_result != 0) {
        close(listener);
        return;
    }
    socklen_t server_length = sizeof(server);
    CHECK(getsockname(listener, (struct sockaddr *)&server,
                      &server_length) == 0 && server.sin_port != 0,
          "accept-ipv4-listener-address");
    CHECK(listen(listener, 4) == 0, "accept-ipv4-listen");

    int client = connect_ipv4(&server);
    CHECK(client >= 0, "accept-copyout-failure-client");
    if (client >= 0) {
        const int descriptors_before = count_open_descriptors();
        socklen_t invalid_length = sizeof(struct sockaddr_in);
        errno = 0;
        const int invalid_accept = accept(
            listener, (struct sockaddr *)(uintptr_t)1,
            &invalid_length);
        const int invalid_accept_error = errno;
        const int descriptors_after = count_open_descriptors();
        CHECK(invalid_accept == -1 && invalid_accept_error == EFAULT,
              "accept-invalid-address-copyout");
        CHECK(descriptors_after == descriptors_before,
              "accept-copyout-failure-closes-descriptor");
        close(client);
    }

    client = connect_ipv4(&server);
    CHECK(client >= 0, "accept-ipv4-client");
    if (client >= 0) {
        struct sockaddr_in client_address = {};
        socklen_t client_address_length = sizeof(client_address);
        CHECK(getsockname(client,
                          (struct sockaddr *)&client_address,
                          &client_address_length) == 0 &&
                  client_address.sin_port != 0,
              "accept-ipv4-client-address");

        struct sockaddr_in accepted_peer = {};
        socklen_t accepted_peer_length = sizeof(accepted_peer);
        const int accepted = accept(
            listener, (struct sockaddr *)&accepted_peer,
            &accepted_peer_length);
        CHECK(accepted >= 0 &&
                  accepted_peer_length == sizeof(accepted_peer) &&
                  accepted_peer.sin_family == AF_INET &&
                  accepted_peer.sin_addr.s_addr ==
                      htonl(INADDR_LOOPBACK) &&
                  accepted_peer.sin_port == client_address.sin_port,
              "accept-ipv4-peer-copyout");

        struct sockaddr_in client_peer = {};
        socklen_t client_peer_length = sizeof(client_peer);
        CHECK(getpeername(client,
                          (struct sockaddr *)&client_peer,
                          &client_peer_length) == 0 &&
                  client_peer_length == sizeof(client_peer) &&
                  client_peer.sin_port == server.sin_port,
              "getpeername-ipv4-client");

        if (accepted >= 0) {
            struct sockaddr_in server_peer = {};
            socklen_t server_peer_length = sizeof(server_peer);
            CHECK(getpeername(accepted,
                              (struct sockaddr *)&server_peer,
                              &server_peer_length) == 0 &&
                      server_peer_length == sizeof(server_peer) &&
                      server_peer.sin_port == client_address.sin_port,
                  "getpeername-ipv4-accepted");
            close(accepted);
        }

        unsigned char truncated[sizeof(struct sockaddr_in) + 1];
        memset(truncated, 0xa5, sizeof(truncated));
        socklen_t truncated_length = 2;
        CHECK(getpeername(client, (struct sockaddr *)truncated,
                          &truncated_length) == 0 &&
                  truncated_length == sizeof(struct sockaddr_in) &&
                  truncated[0] == sizeof(struct sockaddr_in) &&
                  truncated[1] == AF_INET &&
                  truncated[2] == 0xa5,
              "getpeername-truncated-output");

        socklen_t zero_length = 0;
        CHECK(getpeername(client, NULL, &zero_length) == 0 &&
                  zero_length == sizeof(struct sockaddr_in),
              "getpeername-zero-length-null-address");
        close(client);
    }

    client = connect_ipv4(&server);
    CHECK(client >= 0, "accept-nocancel-client");
    if (client >= 0) {
        const int accepted = (int)syscall(
            SYS_accept_nocancel, listener, NULL, NULL);
        CHECK(accepted >= 0, "accept-nocancel-indirect");
        if (accepted >= 0) close(accepted);
        close(client);
    }

    close(listener);
}

static void test_unix_paths(const char *temporary_root) {
    char listener_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    char client_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    if (temporary_root == NULL || temporary_root[0] != '/') {
        temporary_root = "/private/tmp";
    }
    const size_t root_length = strlen(temporary_root);
    const char *separator = root_length != 0 &&
            temporary_root[root_length - 1] == '/' ? "" : "/";
    const int listener_path_length = snprintf(
             listener_path, sizeof(listener_path),
             "%s%slc32-accept-listener-%d.sock",
             temporary_root, separator, getpid());
    const int client_path_length = snprintf(
             client_path, sizeof(client_path),
             "%s%slc32-accept-client-%d.sock",
             temporary_root, separator, getpid());
    CHECK(listener_path_length > 0 &&
              listener_path_length < (int)sizeof(listener_path) &&
              client_path_length > 0 &&
              client_path_length < (int)sizeof(client_path),
          "accept-unix-paths-fit");
    if (listener_path_length <= 0 ||
            listener_path_length >= (int)sizeof(listener_path) ||
            client_path_length <= 0 ||
            client_path_length >= (int)sizeof(client_path)) {
        return;
    }
    unlink(listener_path);
    unlink(client_path);

    const int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    const int client = socket(AF_UNIX, SOCK_STREAM, 0);
    CHECK(listener >= 0 && client >= 0, "accept-unix-sockets");
    if (listener < 0 || client < 0) {
        if (listener >= 0) close(listener);
        if (client >= 0) close(client);
        return;
    }

    struct sockaddr_un listener_address = {};
    listener_address.sun_family = AF_UNIX;
    snprintf(listener_address.sun_path,
             sizeof(listener_address.sun_path), "%s", listener_path);
    listener_address.sun_len = SUN_LEN(&listener_address);
    struct sockaddr_un client_address = {};
    client_address.sun_family = AF_UNIX;
    snprintf(client_address.sun_path,
             sizeof(client_address.sun_path), "%s", client_path);
    client_address.sun_len = SUN_LEN(&client_address);

    errno = 0;
    const int listener_bind_result = bind(
        listener, (const struct sockaddr *)&listener_address,
        listener_address.sun_len);
    if (listener_bind_result != 0 && errno == EPERM) {
        printf("SKIP accept-unix (sandbox denied bind)\n");
        close(client);
        close(listener);
        return;
    }
    const int listen_result = listener_bind_result == 0
        ? listen(listener, 1) : -1;
    CHECK(listener_bind_result == 0 && listen_result == 0,
          "accept-unix-listen");

    const int client_bind_result =
        listener_bind_result == 0 && listen_result == 0
            ? bind(client, (const struct sockaddr *)&client_address,
                   client_address.sun_len)
            : -1;
    const int connect_result = client_bind_result == 0
        ? connect(client,
                  (const struct sockaddr *)&listener_address,
                  listener_address.sun_len)
        : -1;
    CHECK(client_bind_result == 0 && connect_result == 0,
          "accept-unix-connect");
    if (listener_bind_result != 0 || listen_result != 0 ||
            client_bind_result != 0 || connect_result != 0) {
        close(client);
        close(listener);
        unlink(client_path);
        unlink(listener_path);
        return;
    }

    struct sockaddr_un accepted_address = {};
    socklen_t accepted_length = sizeof(accepted_address);
    const int accepted = accept(
        listener, (struct sockaddr *)&accepted_address,
        &accepted_length);
    CHECK(accepted >= 0 &&
              accepted_address.sun_family == AF_UNIX &&
              strcmp(accepted_address.sun_path, client_path) == 0,
          "accept-unix-guest-path");

    struct sockaddr_un peer = {};
    socklen_t peer_length = sizeof(peer);
    CHECK(getpeername(client, (struct sockaddr *)&peer,
                      &peer_length) == 0 &&
              peer.sun_family == AF_UNIX &&
              strcmp(peer.sun_path, listener_path) == 0,
          "getpeername-unix-guest-path");

    if (accepted >= 0) close(accepted);
    close(client);
    close(listener);
    unlink(client_path);
    unlink(listener_path);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    test_ipv4();
    test_unix_paths(argc > 1 ? argv[1] : NULL);
    printf("socket accept ABI: %s\n",
           failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
