#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

/* ptrace is present in libSystem but absent from the public iOS SDK headers. */
extern int ptrace(int request, pid_t pid, void *address, int data);

static int failures;

#define CHECK(condition, label) do {                                    \
    if (condition) {                                                     \
        printf("PASS %s\n", label);                                    \
    } else {                                                            \
        fprintf(stderr, "FAIL %s (errno=%d)\n", label, errno);          \
        failures++;                                                     \
    }                                                                   \
} while (0)

static void check_fork(void) {
    errno = 0;
    /* The public fork veneer runs process-wide atfork hooks before entering
     * the kernel. Invoke the indirect syscall veneer so this test reaches
     * LC32's policy boundary without exercising unrelated XPC Mach calls. */
    const pid_t result = (pid_t)syscall(SYS_fork);
    if (result == 0) _exit(120);
    CHECK(result == -1 && errno == EPERM, "fork-blocked-with-eperm");
}

static void check_vfork(void) {
    errno = 0;
    const pid_t result = (pid_t)syscall(SYS_vfork);
    if (result == 0) _exit(121);
    CHECK(result == -1 && errno == EPERM, "vfork-blocked-with-eperm");
}

int main(void) {
    char missingPath[PATH_MAX];
    snprintf(missingPath, sizeof(missingPath),
             "/private/var/tmp/lc32-blocked-syscall-%d", getpid());
    char *const arguments[] = {(char *)missingPath, NULL};
    char *const environment[] = {NULL};

    setvbuf(stdout, NULL, _IONBF, 0);
    check_fork();
    check_vfork();

    errno = 0;
    CHECK(kill(getpid(), 0) == -1 && errno == EPERM,
          "kill-probe-blocked-with-eperm");
    errno = 0;
    CHECK(ptrace(-1, getpid(), NULL, 0) == -1 && errno == EPERM,
          "ptrace-blocked-with-eperm");
    errno = 0;
    CHECK(execve(missingPath, arguments, environment) == -1 &&
              errno == EPERM,
          "execve-blocked-with-eperm");

    pid_t spawnedPid = -1;
    const int spawnResult = posix_spawn(
        &spawnedPid, missingPath, NULL, NULL, arguments, environment);
    CHECK(spawnResult == EPERM,
          "posix-spawn-blocked-with-eperm");

    errno = 0;
    const int mknodResult = mknod(missingPath, S_IFCHR | 0600, 0);
    CHECK(mknodResult == -1 && errno == EPERM,
          "mknod-blocked-with-eperm");
    if (mknodResult == 0) unlink(missingPath);

    errno = 0;
    CHECK(chroot(missingPath) == -1 && errno == EPERM,
          "chroot-blocked-with-eperm");
    errno = 0;
    CHECK(mount("none", missingPath, 0, NULL) == -1 && errno == EPERM,
          "mount-blocked-with-eperm");

    printf("Darwin blocked syscalls: %s\n",
           failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
