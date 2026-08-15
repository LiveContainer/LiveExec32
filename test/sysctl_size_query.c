#include <sys/sysctl.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int check_query_by_name(char **value_out) {
    size_t length = (size_t)0xa5a5a5a5u;
    errno = 0;
    const int queryResult = sysctlbyname(
        "hw.machine", NULL, &length, NULL, 0);
    const int queryPassed = queryResult == 0 &&
        length > 1 && length < 4096 &&
        length != (size_t)0xa5a5a5a5u;
    printf("sysctlbyname-size-query: %s (result=%d errno=%d length=%lu)\n",
        queryPassed ? "PASS" : "FAIL", queryResult, errno,
        (unsigned long)length);
    if(!queryPassed) return 0;

    char *value = calloc(1, length);
    if(!value) return 0;
    const size_t capacity = length;
    errno = 0;
    const int readResult = sysctlbyname(
        "hw.machine", value, &length, NULL, 0);
    const int readPassed = readResult == 0 &&
        length > 1 && length <= capacity && value[length - 1] == '\0';
    printf("sysctlbyname-value-read: %s "
           "(result=%d errno=%d length=%lu value=%s)\n",
        readPassed ? "PASS" : "FAIL", readResult, errno,
        (unsigned long)length, readPassed ? value : "<invalid>");
    if(!readPassed) {
        free(value);
        return 0;
    }

    *value_out = value;
    return 1;
}

static int check_numeric_query(const char *expected) {
    int mib[] = { CTL_HW, HW_MACHINE };
    size_t length = (size_t)0x5a5a5a5au;
    errno = 0;
    const int queryResult = sysctl(
        mib, sizeof(mib) / sizeof(mib[0]), NULL, &length, NULL, 0);
    const int queryPassed = queryResult == 0 &&
        length > 1 && length < 4096 &&
        length != (size_t)0x5a5a5a5au;
    printf("sysctl-size-query: %s (result=%d errno=%d length=%lu)\n",
        queryPassed ? "PASS" : "FAIL", queryResult, errno,
        (unsigned long)length);
    if(!queryPassed) return 0;

    char *value = calloc(1, length);
    if(!value) return 0;
    const size_t capacity = length;
    errno = 0;
    const int readResult = sysctl(
        mib, sizeof(mib) / sizeof(mib[0]), value, &length, NULL, 0);
    const int readPassed = readResult == 0 &&
        length > 1 && length <= capacity && value[length - 1] == '\0' &&
        strcmp(value, expected) == 0;
    printf("sysctl-value-read: %s "
           "(result=%d errno=%d length=%lu value=%s)\n",
        readPassed ? "PASS" : "FAIL", readResult, errno,
        (unsigned long)length, readResult == 0 ? value : "<invalid>");
    free(value);
    return readPassed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    char *machine = NULL;
    const int byNamePassed = check_query_by_name(&machine);
    const int numericPassed = byNamePassed &&
        check_numeric_query(machine);
    free(machine);

    const int passed = byNamePassed && numericPassed;
    printf("sysctl-size-query-regression: %s\n",
        passed ? "PASS" : "FAIL");
    return !passed;
}
