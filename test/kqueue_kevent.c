#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/event.h>
#include <time.h>
#include <unistd.h>

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
    const uintptr_t identifier = 0x1234;
    void *const userData = (void *)(uintptr_t)0x76543210;
    const struct timespec immediate = {0, 0};

    const int descriptor = kqueue();
    if (descriptor < 0) {
        perror("kqueue");
        return 1;
    }
    CHECK(descriptor >= 0, "kqueue-create");

    struct kevent event = {0};
    CHECK(kevent(descriptor, NULL, 0, &event, 1, &immediate) == 0,
        "kevent-empty-nonblocking");

    struct kevent change;
    EV_SET(&change, identifier, EVFILT_USER,
        EV_ADD | EV_CLEAR, 0, 0, userData);
    CHECK(kevent(descriptor, &change, 1, NULL, 0, NULL) == 0,
        "kevent-register-user");

    EV_SET(&change, identifier, EVFILT_USER,
        0, NOTE_TRIGGER, 0, userData);
    CHECK(kevent(descriptor, &change, 1, NULL, 0, NULL) == 0,
        "kevent-trigger-user");

    event = (struct kevent){0};
    const int eventCount =
        kevent(descriptor, NULL, 0, &event, 1, &immediate);
    CHECK(eventCount == 1, "kevent-read-count");
    CHECK(event.ident == identifier, "kevent-read-ident");
    CHECK(event.filter == EVFILT_USER, "kevent-read-filter");
    CHECK(event.udata == userData, "kevent-read-udata");

    const int fileDescriptor = open(
        "/System/Library/CoreServices/SystemVersion.plist", O_RDONLY);
    if (fileDescriptor < 0) {
        perror("open(SystemVersion.plist)");
        failures++;
    } else {
        void *const fileData = (void *)(uintptr_t)0x13572468;
        EV_SET(&change, (uintptr_t)fileDescriptor, EVFILT_READ,
            EV_ADD | EV_CLEAR, 0, 0, fileData);
        CHECK(kevent(descriptor, &change, 1, NULL, 0, NULL) == 0,
            "kevent-register-file-read");

        event = (struct kevent){0};
        const int fileEventCount =
            kevent(descriptor, NULL, 0, &event, 1, &immediate);
        CHECK(fileEventCount == 1, "kevent-file-read-count");
        CHECK(event.ident == (uintptr_t)fileDescriptor,
            "kevent-file-read-ident");
        CHECK(event.filter == EVFILT_READ, "kevent-file-read-filter");
        CHECK(event.data > 0, "kevent-file-read-data");
        CHECK(event.udata == fileData, "kevent-file-read-udata");

        if (close(fileDescriptor) != 0) {
            perror("close(file)");
            failures++;
        }
    }

    CHECK(kevent(descriptor, NULL, -1, NULL, -1, &immediate) == 0,
        "kevent-negative-counts-are-empty");

    errno = 0;
    CHECK(kevent(descriptor, (const struct kevent *)(uintptr_t)1,
              1, NULL, 0, &immediate) == -1 && errno == EFAULT,
        "kevent-input-efault");

    errno = 0;
    CHECK(kevent(-1, NULL, 0, NULL, 0, &immediate) == -1 &&
              errno == EBADF,
        "kevent-error-carry-errno");

    if (close(descriptor) != 0) {
        perror("close(kqueue)");
        failures++;
    }
    printf("kqueue/kevent ABI: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
