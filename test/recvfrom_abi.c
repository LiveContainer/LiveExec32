#include <errno.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
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

static int send_packet(int socket_fd,
        const struct sockaddr_in *destination,
        const char *payload, size_t payload_len) {
    return sendto(socket_fd, payload, payload_len, 0,
                  (const struct sockaddr *)destination,
                  sizeof(*destination)) == (ssize_t)payload_len;
}

int main(void) {
    int receiver = socket(AF_INET, SOCK_DGRAM, 0);
    int sender = socket(AF_INET, SOCK_DGRAM, 0);
    CHECK(receiver >= 0 && sender >= 0, "recvfrom-sockets");

    struct sockaddr_in receiver_address = {};
    receiver_address.sin_len = sizeof(receiver_address);
    receiver_address.sin_family = AF_INET;
    receiver_address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(receiver,
               (const struct sockaddr *)&receiver_address,
               sizeof(receiver_address)) == 0,
          "recvfrom-bind-receiver");
    socklen_t receiver_address_len = sizeof(receiver_address);
    CHECK(getsockname(receiver,
                      (struct sockaddr *)&receiver_address,
                      &receiver_address_len) == 0 &&
              receiver_address.sin_port != 0,
          "recvfrom-receiver-address");

    struct sockaddr_in sender_address = {};
    sender_address.sin_len = sizeof(sender_address);
    sender_address.sin_family = AF_INET;
    sender_address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    CHECK(bind(sender, (const struct sockaddr *)&sender_address,
               sizeof(sender_address)) == 0,
          "recvfrom-bind-sender");
    socklen_t sender_address_len = sizeof(sender_address);
    CHECK(getsockname(sender,
                      (struct sockaddr *)&sender_address,
                      &sender_address_len) == 0 &&
              sender_address.sin_port != 0,
          "recvfrom-sender-address");

    static const char first_payload[] = "raknet-first";
    CHECK(send_packet(sender, &receiver_address,
                      first_payload, sizeof(first_payload)),
          "recvfrom-send-first");
    char buffer[64] = {};
    struct sockaddr_in source_address = {};
    socklen_t source_address_len = sizeof(source_address);
    ssize_t received = recvfrom(
        receiver, buffer, sizeof(buffer), 0,
        (struct sockaddr *)&source_address,
        &source_address_len);
    CHECK(received == sizeof(first_payload) &&
              memcmp(buffer, first_payload,
                     sizeof(first_payload)) == 0,
          "recvfrom-payload-copyout");
    CHECK(source_address_len == sizeof(source_address) &&
              source_address.sin_len == sizeof(source_address) &&
              source_address.sin_family == AF_INET &&
              source_address.sin_addr.s_addr ==
                  htonl(INADDR_LOOPBACK) &&
              source_address.sin_port == sender_address.sin_port,
          "recvfrom-source-copyout");

    static const char second_payload[] = "raknet-second";
    CHECK(send_packet(sender, &receiver_address,
                      second_payload, sizeof(second_payload)),
          "recvfrom-send-truncated");
    unsigned char truncated_address[
        sizeof(struct sockaddr_in) + 1];
    memset(truncated_address, 0xa5, sizeof(truncated_address));
    socklen_t truncated_address_len = 2;
    memset(buffer, 0, sizeof(buffer));
    received = recvfrom(
        receiver, buffer, sizeof(buffer), 0,
        (struct sockaddr *)truncated_address,
        &truncated_address_len);
    CHECK(received == sizeof(second_payload) &&
              memcmp(buffer, second_payload,
                     sizeof(second_payload)) == 0 &&
              truncated_address_len ==
                  sizeof(struct sockaddr_in) &&
              truncated_address[0] == sizeof(struct sockaddr_in) &&
              truncated_address[1] == AF_INET &&
              truncated_address[2] == 0xa5,
          "recvfrom-truncated-source");

    static const char third_payload[] = "raknet-third";
    CHECK(send_packet(sender, &receiver_address,
                      third_payload, sizeof(third_payload)),
          "recvfrom-send-no-source");
    memset(buffer, 0, sizeof(buffer));
    received = recvfrom(
        receiver, buffer, sizeof(buffer), 0, NULL, NULL);
    CHECK(received == sizeof(third_payload) &&
              memcmp(buffer, third_payload,
                     sizeof(third_payload)) == 0,
          "recvfrom-optional-source");

    static const char from_without_length_payload[] =
        "raknet-from-without-length";
    CHECK(send_packet(sender, &receiver_address,
                      from_without_length_payload,
                      sizeof(from_without_length_payload)),
          "recvfrom-send-from-without-length");
    memset(&source_address, 0xa5, sizeof(source_address));
    memset(buffer, 0, sizeof(buffer));
    received = recvfrom(
        receiver, buffer, sizeof(buffer), 0,
        (struct sockaddr *)&source_address, NULL);
    CHECK(received == sizeof(from_without_length_payload) &&
              memcmp(buffer, from_without_length_payload,
                     sizeof(from_without_length_payload)) == 0 &&
              ((unsigned char *)&source_address)[0] == 0xa5,
          "recvfrom-from-without-length");

    static const char length_without_from_payload[] =
        "raknet-length-without-from";
    CHECK(send_packet(sender, &receiver_address,
                      length_without_from_payload,
                      sizeof(length_without_from_payload)),
          "recvfrom-send-length-without-from");
    source_address_len = 0x1234;
    memset(buffer, 0, sizeof(buffer));
    received = recvfrom(
        receiver, buffer, sizeof(buffer), 0,
        NULL, &source_address_len);
    CHECK(received == sizeof(length_without_from_payload) &&
              memcmp(buffer, length_without_from_payload,
                     sizeof(length_without_from_payload)) == 0 &&
              source_address_len == 0x1234,
          "recvfrom-length-without-from");

    static const char fourth_payload[] = "raknet-fourth";
    CHECK(send_packet(sender, &receiver_address,
                      fourth_payload, sizeof(fourth_payload)),
          "recvfrom-send-zero-source-length");
    memset(&source_address, 0xa5, sizeof(source_address));
    source_address_len = 0;
    memset(buffer, 0, sizeof(buffer));
    received = recvfrom(
        receiver, buffer, sizeof(buffer), 0,
        (struct sockaddr *)&source_address,
        &source_address_len);
    CHECK(received == sizeof(fourth_payload) &&
              memcmp(buffer, fourth_payload,
                     sizeof(fourth_payload)) == 0 &&
              source_address_len == 0 &&
              ((unsigned char *)&source_address)[0] == 0xa5,
          "recvfrom-zero-source-length");

    errno = 0;
    received = recvfrom(
        receiver, buffer, sizeof(buffer), MSG_DONTWAIT,
        NULL, NULL);
    CHECK(received == -1 &&
              (errno == EAGAIN || errno == EWOULDBLOCK),
          "recvfrom-explicit-nonblocking");

    errno = 0;
    received = recvfrom(
        receiver, buffer, (size_t)INT32_MAX + 1,
        MSG_DONTWAIT, NULL, NULL);
    CHECK(received == -1 && errno == EINVAL,
          "recvfrom-oversized-buffer");

    errno = 0;
    received = recvfrom(
        receiver, buffer, sizeof(buffer), MSG_DONTWAIT,
        (struct sockaddr *)&source_address,
        (socklen_t *)(uintptr_t)1);
    CHECK(received == -1 && errno == EFAULT,
          "recvfrom-invalid-fromlen");

    errno = 0;
    received = recvfrom(
        -1, buffer, sizeof(buffer), 0, NULL, NULL);
    CHECK(received == -1 && errno == EBADF,
          "recvfrom-error-carry-errno");

    close(sender);
    close(receiver);
    printf("recvfrom ABI: %s\n",
           failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
