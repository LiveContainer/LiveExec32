#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <unistd.h>

static int check_statfs(const char *label, const struct statfs *value) {
    if(value->f_bsize == 0 || value->f_blocks == 0 ||
            value->f_bavail == 0) {
        fprintf(stderr,
            "%s returned invalid capacity: bsize=%u blocks=%llu "
            "available=%llu\n",
            label, value->f_bsize,
            (unsigned long long)value->f_blocks,
            (unsigned long long)value->f_bavail);
        return 1;
    }
    return 0;
}

int main(void) {
    struct statfs path_value;
    memset(&path_value, 0, sizeof(path_value));
    if(statfs("/var/mobile", &path_value) != 0) {
        fprintf(stderr, "statfs failed: %s\n", strerror(errno));
        return 1;
    }
    if(check_statfs("statfs", &path_value) != 0) return 1;

    int descriptor = open("/var/mobile", O_RDONLY);
    if(descriptor < 0) {
        fprintf(stderr, "open failed: %s\n", strerror(errno));
        return 1;
    }

    struct statfs descriptor_value;
    memset(&descriptor_value, 0, sizeof(descriptor_value));
    int result = fstatfs(descriptor, &descriptor_value);
    int saved_errno = errno;
    close(descriptor);
    if(result != 0) {
        fprintf(stderr, "fstatfs failed: %s\n", strerror(saved_errno));
        return 1;
    }
    if(check_statfs("fstatfs", &descriptor_value) != 0) return 1;

    if(path_value.f_bsize != descriptor_value.f_bsize ||
            path_value.f_blocks != descriptor_value.f_blocks ||
            path_value.f_bavail != descriptor_value.f_bavail) {
        fprintf(stderr, "statfs and fstatfs returned different capacities\n");
        return 1;
    }

    printf("bsize=%u blocks=%llu available=%llu\n",
        path_value.f_bsize,
        (unsigned long long)path_value.f_blocks,
        (unsigned long long)path_value.f_bavail);
    return 0;
}
