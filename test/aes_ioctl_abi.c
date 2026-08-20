#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

struct aes_info_32 {
    uint8_t reserved0[28];
    uint32_t maximum_bytes_per_call;
    uint8_t reserved1[8];
};

struct aes_crypt_32 {
    uint32_t first_buffer;
    uint32_t second_buffer;
    uint32_t data_length;
    uint8_t iv[16];
    uint32_t decrypt;
    uint32_t key_bits;
    uint8_t key[32];
    uint32_t reserved68;
    uint32_t reserved72;
};

#define AES_GET_INFO_32 _IOR('T', 0x65, struct aes_info_32)
#define AES_CRYPT_32 _IOWR('T', 0x66, struct aes_crypt_32)

_Static_assert(sizeof(struct aes_info_32) == 40,
               "AES info ABI size");
_Static_assert(sizeof(struct aes_crypt_32) == 76,
               "AES crypt ABI size");
_Static_assert(offsetof(struct aes_info_32,
                        maximum_bytes_per_call) == 28,
               "AES info quantum offset");
_Static_assert(offsetof(struct aes_crypt_32, first_buffer) == 0 &&
               offsetof(struct aes_crypt_32, second_buffer) == 4 &&
               offsetof(struct aes_crypt_32, data_length) == 8 &&
               offsetof(struct aes_crypt_32, iv) == 12 &&
               offsetof(struct aes_crypt_32, decrypt) == 28 &&
               offsetof(struct aes_crypt_32, key_bits) == 32 &&
               offsetof(struct aes_crypt_32, key) == 36 &&
               offsetof(struct aes_crypt_32, reserved68) == 68 &&
               offsetof(struct aes_crypt_32, reserved72) == 72,
               "AES crypt ABI offsets");
_Static_assert(AES_GET_INFO_32 == UINT32_C(0x40285465),
               "AES info ioctl number");
_Static_assert(AES_CRYPT_32 == UINT32_C(0xc04c5466),
               "AES crypt ioctl number");

static int failures;

#define CHECK(condition, label) do {                                    \
    if (condition) {                                                     \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while (0)

static uint32_t guest_pointer(void *pointer) {
    return (uint32_t)(uintptr_t)pointer;
}

static void initialize_request(
        struct aes_crypt_32 *request,
        void *destination, const void *source,
        uint32_t decrypt) {
    static const uint8_t key[16] = {
        0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6,
        0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c,
    };
    static const uint8_t iv[16] = {
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    };
    memset(request, 0, sizeof(*request));
    if (decrypt) {
        request->first_buffer = guest_pointer(destination);
        request->second_buffer = guest_pointer((void *)source);
    } else {
        request->first_buffer = guest_pointer((void *)source);
        request->second_buffer = guest_pointer(destination);
    }
    request->data_length = 16;
    memcpy(request->iv, iv, sizeof(iv));
    request->decrypt = decrypt;
    request->key_bits = 128;
    memcpy(request->key, key, sizeof(key));
}

int main(void) {
    static const uint8_t plaintext[16] = {
        0x6b, 0xc1, 0xbe, 0xe2, 0x2e, 0x40, 0x9f, 0x96,
        0xe9, 0x3d, 0x7e, 0x11, 0x73, 0x93, 0x17, 0x2a,
    };
    static const uint8_t ciphertext[16] = {
        0x76, 0x49, 0xab, 0xac, 0x81, 0x19, 0xb2, 0x46,
        0xce, 0xe9, 0x8e, 0x9b, 0x12, 0xe9, 0x19, 0x7d,
    };

    int fd = open("/dev/aes_0", O_RDWR);
    CHECK(fd >= 0, "aes-open-virtual-device");
    if (fd < 0) {
        return 1;
    }

    struct aes_info_32 info = {};
    CHECK(ioctl(fd, AES_GET_INFO_32, &info) == 0 &&
              info.maximum_bytes_per_call == 64 * 1024,
          "aes-capability-quantum");

    uint8_t result[16] = {};
    struct aes_crypt_32 request;
    initialize_request(&request, result, ciphertext, 1);
    CHECK(ioctl(fd, AES_CRYPT_32, &request) == 0 &&
              memcmp(result, plaintext, sizeof(result)) == 0,
          "aes-cbc-decrypt-nonzero-iv");
    CHECK(memcmp(request.iv, ciphertext, sizeof(request.iv)) == 0,
          "aes-cbc-decrypt-iv-writeback");

    memset(result, 0, sizeof(result));
    initialize_request(&request, result, plaintext, 0);
    CHECK(ioctl(fd, AES_CRYPT_32, &request) == 0 &&
              memcmp(result, ciphertext, sizeof(result)) == 0,
          "aes-cbc-encrypt-nonzero-iv");
    CHECK(memcmp(request.iv, ciphertext, sizeof(request.iv)) == 0,
          "aes-cbc-encrypt-iv-writeback");

    uint8_t in_place[16];
    memcpy(in_place, ciphertext, sizeof(in_place));
    initialize_request(&request, in_place, in_place, 1);
    CHECK(ioctl(fd, AES_CRYPT_32, &request) == 0 &&
              memcmp(in_place, plaintext, sizeof(in_place)) == 0,
          "aes-cbc-in-place-decrypt");

    initialize_request(&request, result, ciphertext, 1);
    request.data_length = info.maximum_bytes_per_call + 16;
    errno = 0;
    CHECK(ioctl(fd, AES_CRYPT_32, &request) == -1 && errno == EINVAL,
          "aes-oversized-request-error-carry");

    errno = 0;
    CHECK(ioctl(fd, AES_CRYPT_32, NULL) == -1 && errno == EFAULT,
          "aes-null-request-error-carry");

    int duplicate = fcntl(fd, F_DUPFD, 0);
    CHECK(duplicate >= 0, "aes-duplicate-descriptor");
    memset(&info, 0, sizeof(info));
    CHECK(duplicate >= 0 &&
              ioctl(duplicate, AES_GET_INFO_32, &info) == 0,
          "aes-duplicate-retains-device-type");
    if (duplicate >= 0) {
        close(duplicate);
    }

    int null_fd = open("/dev/null", O_RDWR);
    errno = 0;
    CHECK(null_fd >= 0 &&
              ioctl(null_fd, AES_GET_INFO_32, &info) == -1 &&
              errno == ENOTTY,
          "aes-ioctl-rejects-unrelated-descriptor");
    if (null_fd >= 0) {
        close(null_fd);
    }

    close(fd);
    errno = 0;
    CHECK(ioctl(fd, AES_GET_INFO_32, &info) == -1 && errno == EBADF,
          "aes-closed-descriptor-error-carry");

    printf("AES ioctl ABI: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
