#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/xattr.h>
#include <unistd.h>

/* Exported by the iOS 10 libSystem but omitted from its public headers. */
extern int fdatasync(int fd);

static int failures;

#define CHECK(condition, label) do {                                    \
    if (condition) {                                                     \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while (0)

static int poll_null_descriptors(void) {
    int (*volatile function)(struct pollfd *, nfds_t, int) = poll;
    return function(NULL, 1, 0);
}

static int getgroups_null_output(int count) {
    int (*volatile function)(int, gid_t *) = getgroups;
    return function(count, NULL);
}

static ssize_t pwrite_null_buffer(int fd) {
    ssize_t (*volatile function)(int, const void *, size_t, off_t) = pwrite;
    return function(fd, NULL, 1, 0);
}

static int open_null_path(void) {
    int (*volatile function)(const char *, int, ...) = open;
    return function(NULL, O_RDONLY);
}

static int access_null_path(void) {
    int (*volatile function)(const char *, int) = access;
    return function(NULL, F_OK);
}

static int unlink_null_path(void) {
    int (*volatile function)(const char *) = unlink;
    return function(NULL);
}

static int list_contains(const char *list, size_t length,
                         const char *name) {
    size_t offset = 0;
    while (offset < length) {
        const size_t itemLength = strnlen(list + offset, length - offset);
        if (itemLength == length - offset) return 0;
        if (strcmp(list + offset, name) == 0) return 1;
        offset += itemLength + 1;
    }
    return 0;
}

static void test_scalar_syscalls(void) {
    const mode_t originalMask = umask(0027);
    const mode_t changedMask = umask(originalMask);
    CHECK(changedMask == 0027, "umask-return-and-restore");

    CHECK(getdtablesize() > 0, "getdtablesize-positive");
    const pid_t processGroup = getpgrp();
    CHECK(processGroup > 0, "getpgrp-positive");
    CHECK(getpgid(0) == processGroup, "getpgid-current-process");
    CHECK(getsid(0) > 0, "getsid-current-process");

    errno = 0;
    const int priority = getpriority(PRIO_PROCESS, 0);
    CHECK(errno == 0 && priority >= PRIO_MIN && priority <= PRIO_MAX,
          "getpriority-current-process");

    errno = 0;
    const int groupCount = getgroups(0, NULL);
    CHECK(groupCount >= 0, "getgroups-size-query");
    if (groupCount > 0) {
        gid_t *groups = calloc((size_t)groupCount, sizeof(*groups));
        CHECK(groups != NULL, "getgroups-allocation");
        if (groups != NULL) {
            CHECK(getgroups(groupCount, groups) == groupCount,
                  "getgroups-copyout");
            free(groups);
        }
        errno = 0;
        CHECK(getgroups_null_output(groupCount) == -1 && errno == EFAULT,
              "getgroups-null-output-errno");
    }

    CHECK(syscall(SYS_getpid) == getpid(), "indirect-syscall-no-args");
    CHECK(syscall(SYS_access, "/usr/lib/dyld", R_OK) == 0,
          "indirect-syscall-argument-shift");
    errno = 0;
    CHECK(syscall(SYS_MAXSYSCALL) == -1 && errno == ENOSYS,
          "indirect-syscall-invalid-number");

    errno = 0;
    CHECK(listen(-1, 1) == -1 && errno == EBADF,
          "listen-invalid-fd-errno");
    errno = 0;
    CHECK(shutdown(-1, SHUT_RDWR) == -1 && errno == EBADF,
          "shutdown-invalid-fd-errno");

    errno = 0;
    CHECK(open_null_path() == -1 && errno == EFAULT,
          "open-null-path-errno");
    errno = 0;
    CHECK(access_null_path() == -1 && errno == EFAULT,
          "access-null-path-errno");
    errno = 0;
    CHECK(unlink_null_path() == -1 && errno == EFAULT,
          "unlink-null-path-errno");
}

static void test_pipe_poll_readv(void) {
    int descriptors[2] = {-1, -1};
    CHECK(pipe(descriptors) == 0 &&
              descriptors[0] >= 0 && descriptors[1] >= 0 &&
              descriptors[0] != descriptors[1],
          "pipe-descriptor-register-pair");
    if (descriptors[0] < 0 || descriptors[1] < 0) return;

    struct pollfd descriptor = {
        .fd = descriptors[0],
        .events = POLLIN,
        .revents = (short)0x7fff,
    };
    CHECK(poll(&descriptor, 1, 0) == 0 && descriptor.revents == 0,
          "poll-empty-pipe");

    static const char message[] = "abcdef";
    CHECK(write(descriptors[1], message, sizeof(message) - 1) ==
              (ssize_t)(sizeof(message) - 1),
          "pipe-write");
    descriptor.revents = 0;
    CHECK(poll(&descriptor, 1, 0) == 1 &&
              (descriptor.revents & POLLIN) != 0,
          "poll-readable-copyout");

    char first[2] = {};
    char second[4] = {};
    struct iovec vectors[2] = {
        {.iov_base = first, .iov_len = sizeof(first)},
        {.iov_base = second, .iov_len = sizeof(second)},
    };
    CHECK(readv(descriptors[0], vectors, 2) ==
              (ssize_t)(sizeof(message) - 1) &&
              memcmp(first, "ab", sizeof(first)) == 0 &&
              memcmp(second, "cdef", sizeof(second)) == 0,
          "readv-scatter-copyout");

    struct iovec invalidVector = {
        .iov_base = NULL,
        .iov_len = 1,
    };
    errno = 0;
    CHECK(readv(descriptors[0], &invalidVector, 1) == -1 &&
              errno == EFAULT,
          "readv-null-buffer-errno");
    errno = 0;
    CHECK(poll_null_descriptors() == -1 && errno == EFAULT,
          "poll-null-descriptors-errno");

    close(descriptors[1]);
    close(descriptors[0]);
}

static void test_xattrs(const char *path, int fd) {
    static const char attributeName[] = "com.liveexec32.syscall-test";
    static const char attributeValue[] = "guest-xattr-value";
    const size_t valueLength = sizeof(attributeValue) - 1;

    CHECK(setxattr(path, attributeName, attributeValue,
                   valueLength, 0, 0) == 0,
          "setxattr-path");
    CHECK(getxattr(path, attributeName, NULL, 0, 0, 0) ==
              (ssize_t)valueLength,
          "getxattr-path-size-query");
    CHECK(getxattr(path, attributeName, NULL, 123, 0, 0) ==
              (ssize_t)valueLength,
          "getxattr-null-nonzero-size-query");

    char value[sizeof(attributeValue)] = {};
    CHECK(getxattr(path, attributeName, value,
                   valueLength, 0, 0) == (ssize_t)valueLength &&
              memcmp(value, attributeValue, valueLength) == 0,
          "getxattr-path-copyout");
    CHECK(getxattr(path, attributeName, value,
                   UINT32_MAX, 0, 0) == (ssize_t)valueLength,
          "getxattr-armv7-legacy-size-query");
    memset(value, 0, sizeof(value));
    CHECK(fgetxattr(fd, attributeName, value,
                    valueLength, 0, 0) == (ssize_t)valueLength &&
              memcmp(value, attributeValue, valueLength) == 0,
          "fgetxattr-copyout");
    CHECK(fgetxattr(fd, attributeName, NULL,
                    123, 0, 0) == (ssize_t)valueLength,
          "fgetxattr-null-nonzero-size-query");

    const ssize_t listLength = listxattr(path, NULL, 0, 0);
    CHECK(listLength > 0, "listxattr-size-query");
    if (listLength > 0) {
        char *list = calloc(1, (size_t)listLength);
        CHECK(list != NULL, "listxattr-allocation");
        if (list != NULL) {
            CHECK(listxattr(path, list, (size_t)listLength, 0) ==
                      listLength &&
                      list_contains(list, (size_t)listLength,
                                    attributeName),
                  "listxattr-copyout");
            free(list);
        }
    }
    CHECK(flistxattr(fd, NULL, 0, 0) > 0,
          "flistxattr-size-query");

    CHECK(removexattr(path, attributeName, 0) == 0,
          "removexattr-path");
    errno = 0;
    CHECK(getxattr(path, attributeName, value,
                   valueLength, 0, 0) == -1 && errno == ENOATTR,
          "getxattr-removed-errno");

    CHECK(fsetxattr(fd, attributeName, attributeValue,
                    valueLength, 0, 0) == 0,
          "fsetxattr");
    CHECK(fremovexattr(fd, attributeName, 0) == 0,
          "fremovexattr");
}

static void test_file_syscalls(const char *temporaryRootOverride) {
    char directory[PATH_MAX];
    char filePath[PATH_MAX];
    char hardLinkPath[PATH_MAX];
    char symbolicLinkPath[PATH_MAX];
    char relativeSymbolicLinkPath[PATH_MAX];
    char nestedDirectoryPath[PATH_MAX];
    char parentRelativeLinkPath[PATH_MAX];
    char escapingSymbolicLinkPath[PATH_MAX];
    char fifoPath[PATH_MAX];
    char emptyDirectoryPath[PATH_MAX];
    char emptyDirectoryDotPath[PATH_MAX];
    const char *temporaryRoot = temporaryRootOverride;
    if (temporaryRoot == NULL || temporaryRoot[0] != '/') {
        temporaryRoot = getenv("TMPDIR");
    }
    if (temporaryRoot == NULL || temporaryRoot[0] != '/') {
        temporaryRoot = "/private/tmp";
    }
    const size_t temporaryRootLength = strlen(temporaryRoot);
    snprintf(directory, sizeof(directory), "%s%slc32-darwin-safe-%d",
             temporaryRoot,
             temporaryRootLength != 0 &&
                     temporaryRoot[temporaryRootLength - 1] == '/' ? "" : "/",
             getpid());
    snprintf(filePath, sizeof(filePath), "%s/file", directory);
    snprintf(hardLinkPath, sizeof(hardLinkPath), "%s/hard", directory);
    snprintf(symbolicLinkPath, sizeof(symbolicLinkPath),
             "%s/symbolic", directory);
    snprintf(relativeSymbolicLinkPath, sizeof(relativeSymbolicLinkPath),
             "%s/relative-symbolic", directory);
    snprintf(nestedDirectoryPath, sizeof(nestedDirectoryPath),
             "%s/nested", directory);
    snprintf(parentRelativeLinkPath, sizeof(parentRelativeLinkPath),
             "%s/parent-relative-symbolic", nestedDirectoryPath);
    snprintf(escapingSymbolicLinkPath, sizeof(escapingSymbolicLinkPath),
             "%s/escaping-symbolic", directory);
    snprintf(fifoPath, sizeof(fifoPath), "%s/fifo", directory);
    snprintf(emptyDirectoryPath, sizeof(emptyDirectoryPath),
             "%s/empty", directory);
    snprintf(emptyDirectoryDotPath, sizeof(emptyDirectoryDotPath),
             "%s/.", emptyDirectoryPath);

    const int directoryResult = mkdir(directory, 0700);
    CHECK(directoryResult == 0, "mkdir-test-directory");
    if (directoryResult != 0) return;
    int fd = open(filePath, O_CREAT | O_EXCL | O_RDWR, 0600);
    CHECK(fd >= 0, "open-test-file");
    if (fd < 0) {
        rmdir(directory);
        return;
    }

    static const char initial[] = "initial";
    CHECK(write(fd, initial, sizeof(initial) - 1) ==
              (ssize_t)(sizeof(initial) - 1),
          "write-test-file");
    CHECK(fchmod(fd, 0640) == 0, "fchmod-file");
    CHECK(fchown(fd, getuid(), getgid()) == 0, "fchown-current-owner");
    CHECK(chflags(filePath, 0) == 0, "chflags-clear");
    CHECK(fchflags(fd, 0) == 0, "fchflags-clear");
    CHECK(flock(fd, LOCK_EX | LOCK_NB) == 0, "flock-exclusive");
    CHECK(flock(fd, LOCK_UN) == 0, "flock-unlock");

    const off_t largeOffset = ((off_t)UINT32_C(5) << 32) + 0x123;
    static const char marker = 'Z';
    CHECK(pwrite(fd, &marker, 1, largeOffset) == 1,
          "pwrite-large-offset");
    char readMarker = 0;
    CHECK(pread(fd, &readMarker, 1, largeOffset) == 1 &&
              readMarker == marker,
          "pread-after-pwrite");
    errno = 0;
    CHECK(pwrite_null_buffer(fd) == -1 && errno == EFAULT,
          "pwrite-null-buffer-errno");

    CHECK(ftruncate(fd, 128) == 0, "ftruncate-file");
    struct stat status = {};
    CHECK(fstat(fd, &status) == 0 && status.st_size == 128,
          "ftruncate-size");
    CHECK(truncate(filePath, 3) == 0, "truncate-translated-path");
    CHECK(stat(filePath, &status) == 0 && status.st_size == 3,
          "truncate-size");

    CHECK(fsync(fd) == 0, "fsync-file");
    CHECK(fdatasync(fd) == 0, "fdatasync-file");
    CHECK(pathconf(filePath, _PC_NAME_MAX) > 0,
          "pathconf-translated-path");
    CHECK(fpathconf(fd, _PC_NAME_MAX) > 0, "fpathconf-file");

    const struct timeval pathTimes[2] = {
        {.tv_sec = 1000000000, .tv_usec = 123456},
        {.tv_sec = 1000000100, .tv_usec = 654321},
    };
    CHECK(utimes(filePath, pathTimes) == 0, "utimes-translated-path");
    CHECK(stat(filePath, &status) == 0 &&
              status.st_mtimespec.tv_sec == pathTimes[1].tv_sec,
          "utimes-copyin");
    const struct timeval fdTimes[2] = {
        {.tv_sec = 1000000200, .tv_usec = 111111},
        {.tv_sec = 1000000300, .tv_usec = 222222},
    };
    CHECK(futimes(fd, fdTimes) == 0, "futimes-file");
    CHECK(fstat(fd, &status) == 0 &&
              status.st_mtimespec.tv_sec == fdTimes[1].tv_sec,
          "futimes-copyin");

    test_xattrs(filePath, fd);

    CHECK(link(filePath, hardLinkPath) == 0,
          "link-translated-paths");
    struct stat hardLinkStatus = {};
    CHECK(stat(hardLinkPath, &hardLinkStatus) == 0 &&
              fstat(fd, &status) == 0 &&
              hardLinkStatus.st_ino == status.st_ino,
          "link-shared-inode");
    CHECK(symlink(filePath, symbolicLinkPath) == 0,
          "symlink-absolute-target");
    unsigned char linkTarget[PATH_MAX];
    memset(linkTarget, 0xa5, sizeof(linkTarget));
    const ssize_t linkTargetLength = readlink(
        symbolicLinkPath, (char *)linkTarget, sizeof(linkTarget));
    CHECK(linkTargetLength > 0 &&
              linkTargetLength < (ssize_t)sizeof(linkTarget) &&
              linkTarget[linkTargetLength] == 0xa5,
          "readlink-translates-without-terminator");
    if (linkTargetLength > 0 &&
            linkTargetLength < (ssize_t)sizeof(linkTarget)) {
        char translatedTarget[PATH_MAX];
        memcpy(translatedTarget, linkTarget, (size_t)linkTargetLength);
        translatedTarget[linkTargetLength] = '\0';
        struct stat translatedTargetStatus = {};
        CHECK(stat(translatedTarget, &translatedTargetStatus) == 0 &&
                  fstat(fd, &status) == 0 &&
                  translatedTargetStatus.st_ino == status.st_ino,
              "readlink-translated-target-resolves");
    }
    struct stat symbolicStatus = {};
    CHECK(lstat(symbolicLinkPath, &symbolicStatus) == 0 &&
              S_ISLNK(symbolicStatus.st_mode) &&
              stat(symbolicLinkPath, &symbolicStatus) == 0 &&
              symbolicStatus.st_ino == status.st_ino,
          "symlink-resolves-translated-target");
    CHECK(lchown(symbolicLinkPath, getuid(), getgid()) == 0,
          "lchown-symbolic-link");

    CHECK(symlink("file", relativeSymbolicLinkPath) == 0,
          "symlink-relative-target");
    memset(linkTarget, 0, sizeof(linkTarget));
    const ssize_t relativeTargetLength = readlink(
        relativeSymbolicLinkPath, (char *)linkTarget, sizeof(linkTarget));
    CHECK(relativeTargetLength == 4 &&
              memcmp(linkTarget, "file", 4) == 0 &&
              stat(relativeSymbolicLinkPath, &symbolicStatus) == 0 &&
              symbolicStatus.st_ino == status.st_ino,
          "symlink-relative-target-resolves");

    CHECK(mkdir(nestedDirectoryPath, 0700) == 0,
          "mkdir-relative-symlink-directory");
    CHECK(symlink("../file", parentRelativeLinkPath) == 0,
          "symlink-safe-parent-relative-target");
    CHECK(stat(parentRelativeLinkPath, &symbolicStatus) == 0 &&
              symbolicStatus.st_ino == status.st_ino,
          "symlink-safe-parent-relative-target-resolves");

    char escapingTarget[PATH_MAX] = {};
    size_t escapingLength = 0;
    for (const char *cursor = directory; *cursor != '\0'; ++cursor) {
        if (*cursor == '/' && escapingLength + 3 < sizeof(escapingTarget)) {
            memcpy(escapingTarget + escapingLength, "../", 3);
            escapingLength += 3;
        }
    }
    const int escapingTargetFits =
        escapingLength + sizeof("Library") <= sizeof(escapingTarget);
    CHECK(escapingTargetFits,
          "symlink-escape-target-fits");
    if (escapingTargetFits) {
        memcpy(escapingTarget + escapingLength,
               "Library", sizeof("Library"));
        errno = 0;
        CHECK(symlink(escapingTarget, escapingSymbolicLinkPath) == -1 &&
                  errno == EPERM,
              "symlink-relative-parent-escape-denied");
        errno = 0;
        CHECK(lstat(escapingSymbolicLinkPath, &symbolicStatus) == -1 &&
                  errno == ENOENT,
              "symlink-relative-parent-escape-not-created");
    }

    CHECK(mkfifo(fifoPath, 0600) == 0, "mkfifo-translated-path");
    CHECK(lstat(fifoPath, &symbolicStatus) == 0 &&
              S_ISFIFO(symbolicStatus.st_mode),
          "mkfifo-file-type");
    CHECK(mkdir(emptyDirectoryPath, 0700) == 0,
          "mkdir-empty-directory");
    errno = 0;
    CHECK(rmdir(emptyDirectoryDotPath) == -1 &&
              access(emptyDirectoryPath, F_OK) == 0,
          "rmdir-terminal-dot-does-not-remove-directory");
    CHECK(rmdir(emptyDirectoryPath) == 0, "rmdir-translated-path");
    errno = 0;
    CHECK(rmdir(filePath) == -1 && errno == ENOTDIR,
          "rmdir-regular-file-errno");

    close(fd);
    unlink(parentRelativeLinkPath);
    rmdir(nestedDirectoryPath);
    unlink(relativeSymbolicLinkPath);
    unlink(symbolicLinkPath);
    unlink(hardLinkPath);
    unlink(fifoPath);
    unlink(filePath);
    CHECK(rmdir(directory) == 0, "rmdir-test-directory");
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    test_scalar_syscalls();
    test_pipe_poll_readv();
    test_file_syscalls(argc > 1 ? argv[1] : NULL);
    printf("Darwin safe syscalls: %s\n",
           failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
