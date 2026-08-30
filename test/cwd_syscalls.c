#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* These Darwin extensions are exported by libSystem but are not declared by
 * the public iOS 10 SDK headers. */
extern int pthread_chdir_np(const char *path);
extern int pthread_fchdir_np(int fd);

static int failures;

#define CHECK(condition, label) do {                                    \
    if (condition) {                                                     \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while (0)

static void check_cwd(const char *expected, const char *label) {
    char path[PATH_MAX];
    errno = 0;
    const char *result = getcwd(path, sizeof(path));
    if (result == path && strcmp(path, expected) == 0) {
        printf("PASS %s\n", label);
    } else {
        fprintf(stderr,
                "FAIL %s (expected=%s actual=%s errno=%d)\n",
                label, expected, result ? path : "<null>", errno);
        failures++;
    }
}

static int bytes_equal(const unsigned char *bytes, size_t length,
                       unsigned char value) {
    for (size_t index = 0; index < length; ++index) {
        if (bytes[index] != value) return 0;
    }
    return 1;
}

/* Calling through volatile function pointers prevents Clang from replacing
 * these deliberate invalid-argument probes with undefined-behavior-derived
 * assumptions based on the SDK's nonnull annotations. */
static int chdir_null(void) {
    int (*volatile function)(const char *) = chdir;
    return function(NULL);
}

static int pthread_chdir_null(void) {
    int (*volatile function)(const char *) = pthread_chdir_np;
    return function(NULL);
}

int main(void) {
    static const char missingPath[] =
        "/lc32-cwd-directory-that-does-not-exist";
    static const char regularFilePath[] = "/usr/lib/dyld";

    setvbuf(stdout, NULL, _IONBF, 0);
    check_cwd("/", "getcwd-translates-root");

    const int rootFd = open(".", O_RDONLY);
    const int systemFd = open("/System", O_RDONLY);
    const int fileFd = open(regularFilePath, O_RDONLY);
    CHECK(rootFd >= 0, "open-root-directory");
    CHECK(systemFd >= 0, "open-translated-system-directory");
    CHECK(fileFd >= 0, "open-translated-regular-file");

    if (rootFd >= 0) {
        char path[PATH_MAX];
        memset(path, 0, sizeof(path));
        errno = 0;
        CHECK(fcntl(rootFd, F_GETPATH, path) == 0 &&
                  strcmp(path, "/") == 0,
              "fcntl-getpath-translates-root");
    }
    if (systemFd >= 0) {
        char path[PATH_MAX];
        memset(path, 0, sizeof(path));
        errno = 0;
        CHECK(fcntl(systemFd, F_GETPATH, path) == 0 &&
                  strcmp(path, "/System") == 0,
              "fcntl-getpath-translates-system");
    }

    unsigned char failedPath[PATH_MAX];
    memset(failedPath, 0xa5, sizeof(failedPath));
    errno = 0;
    const int failedGetPath = fcntl(-1, F_GETPATH, failedPath);
    const int failedGetPathError = errno;
    CHECK(failedGetPath == -1 && failedGetPathError == EBADF &&
              bytes_equal(failedPath, sizeof(failedPath), 0xa5),
          "fcntl-getpath-error-preserves-output");

    errno = 0;
    CHECK(chdir(missingPath) == -1 && errno == ENOENT,
          "chdir-missing-errno");
    check_cwd("/", "chdir-missing-preserves-cwd");

    errno = 0;
    CHECK(chdir(regularFilePath) == -1 && errno == ENOTDIR,
          "chdir-regular-file-errno");

    errno = 0;
    CHECK(chdir_null() == -1 && errno == EFAULT,
          "chdir-null-errno");

    if (fileFd >= 0) {
        struct stat canonical = {};
        struct stat rootTraversal = {};
        struct stat mountTraversal = {};
        CHECK(fstat(fileFd, &canonical) == 0 &&
                  stat("/../../usr/lib/dyld", &rootTraversal) == 0 &&
                  rootTraversal.st_dev == canonical.st_dev &&
                  rootTraversal.st_ino == canonical.st_ino,
              "absolute-parent-components-clamp-at-guest-root");
        CHECK(stat("/private/var/../../usr/lib/dyld",
                   &mountTraversal) == 0 &&
                  mountTraversal.st_dev == canonical.st_dev &&
                  mountTraversal.st_ino == canonical.st_ino,
              "parent-components-cannot-escape-mount-prefix");
    }

    errno = 0;
    CHECK(fchdir(-1) == -1 && errno == EBADF,
          "fchdir-invalid-fd-errno");
    if (fileFd >= 0) {
        errno = 0;
        CHECK(fchdir(fileFd) == -1 && errno == ENOTDIR,
              "fchdir-regular-file-errno");
    }

    CHECK(chdir("/usr") == 0, "chdir-absolute-translated-path");
    check_cwd("/usr", "getcwd-after-absolute-chdir");
    CHECK(access("lib/dyld", R_OK) == 0,
          "relative-access-after-chdir");
    CHECK(chdir("lib") == 0, "chdir-relative-path");
    check_cwd("/usr/lib", "getcwd-after-relative-chdir");
    CHECK(access("dyld", R_OK) == 0,
          "relative-access-after-relative-chdir");

    char tinyPath[2] = { 'x', 'y' };
    errno = 0;
    CHECK(getcwd(tinyPath, sizeof(tinyPath)) == NULL && errno == ERANGE,
          "getcwd-small-buffer-errno");
    check_cwd("/usr/lib", "getcwd-error-preserves-cwd");

    CHECK(chdir("..") == 0, "chdir-relative-parent");
    check_cwd("/usr", "getcwd-after-relative-parent");
    if (systemFd >= 0) {
        CHECK(fchdir(systemFd) == 0, "fchdir-directory");
        check_cwd("/System", "getcwd-after-fchdir");
    }
    if (rootFd >= 0) {
        CHECK(fchdir(rootFd) == 0, "fchdir-restore-process-root");
        check_cwd("/", "getcwd-after-process-root-restore");
    }

    CHECK(pthread_chdir_np("/usr") == 0,
          "pthread-chdir-absolute-translated-path");
    check_cwd("/usr", "getcwd-after-pthread-chdir");
    CHECK(access("lib/dyld", R_OK) == 0,
          "relative-access-after-pthread-chdir");

    errno = 0;
    CHECK(pthread_chdir_np(missingPath) == -1 && errno == ENOENT,
          "pthread-chdir-missing-errno");
    check_cwd("/usr", "pthread-chdir-error-preserves-cwd");

    errno = 0;
    CHECK(pthread_chdir_null() == -1 && errno == EFAULT,
          "pthread-chdir-null-errno");

    if (fileFd >= 0) {
        errno = 0;
        CHECK(pthread_fchdir_np(fileFd) == -1 && errno == ENOTDIR,
              "pthread-fchdir-regular-file-errno");
    }
    if (systemFd >= 0) {
        CHECK(pthread_fchdir_np(systemFd) == 0,
              "pthread-fchdir-directory");
        check_cwd("/System", "getcwd-after-pthread-fchdir");
    }

    CHECK(pthread_fchdir_np(-1) == 0,
          "pthread-fchdir-clear-thread-cwd");
    check_cwd("/", "getcwd-after-pthread-cwd-clear");
    errno = 0;
    CHECK(pthread_fchdir_np(-1) == -1 && errno == EBADF,
          "pthread-fchdir-clear-without-thread-cwd");

    if (fileFd >= 0) close(fileFd);
    if (systemFd >= 0) close(systemFd);
    if (rootFd >= 0) close(rootFd);

    printf("cwd syscalls: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
