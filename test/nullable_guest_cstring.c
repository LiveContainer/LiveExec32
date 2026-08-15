#include <stdint.h>
#include <stdio.h>

extern uint64_t LC32GuestToHostCString(const char *string, size_t length);
extern void LC32GuestToHostCStringFree(uint64_t string);

int main(void) {
    uint64_t hostString = LC32GuestToHostCString(NULL, 0);
    LC32GuestToHostCStringFree(hostString);

    int passed = hostString == 0;
    printf("nullable-guest-cstring: %s\n", passed ? "PASS" : "FAIL");
    return !passed;
}
