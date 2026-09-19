#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

// These kernel-control SPI declarations are absent from the public iOS SDK.
struct LC32CtlInfo { uint32_t ctl_id; char ctl_name[96]; };
#define LC32_CTLIOCGINFO _IOWR('N', 3, struct LC32CtlInfo)
_Static_assert(sizeof(struct LC32CtlInfo) == 100, "ctl_info ABI");
_Static_assert(LC32_CTLIOCGINFO == 0xc0644e03u, "CTLIOCGINFO ABI");
static int failures;
static void check(const char *name, int passed) {
    printf("kernel-control-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}
int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    int fd = socket(PF_SYSTEM, SOCK_DGRAM, 2 /* SYSPROTO_CONTROL */);
    check("socket", fd >= 0);
    if(fd < 0) return 1;
    struct {
        struct LC32CtlInfo info;
        uint32_t canary;
    } request = {.canary = 0x1234abcd};
    // Lookup only: do not connect or create a network interface.
    strcpy(request.info.ctl_name, "com.apple.net.utun_control");
    check("lookup", ioctl(fd, LC32_CTLIOCGINFO, &request.info) == 0 && request.info.ctl_id != 0);
    check("canary", request.canary == 0x1234abcd);
    check("name-preserved", strcmp(request.info.ctl_name, "com.apple.net.utun_control") == 0);
    errno = 0;
    check("null", ioctl(fd, LC32_CTLIOCGINFO, NULL) == -1 && errno == EFAULT);
    errno = 0;
    check("bad-pointer", ioctl(fd, LC32_CTLIOCGINFO, (void *)(uintptr_t)1) == -1 && errno == EFAULT);
    errno = 0;
    check("bad-fd", ioctl(-1, LC32_CTLIOCGINFO, &request.info) == -1 && errno == EBADF);
    strcpy(request.info.ctl_name, "org.liveexec32.nonexistent-control");
    errno = 0;
    check("missing-control", ioctl(fd, LC32_CTLIOCGINFO, &request.info) == -1 && errno == ENOENT);
    close(fd);
    return failures ? 1 : 0;
}
