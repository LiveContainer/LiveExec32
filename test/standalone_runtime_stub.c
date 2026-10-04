// Host-only endpoint for testing the real launcher's path/argument contract.
#include <stdio.h>
#include <stdlib.h>

int LC32RunGuest(int argc, char *argv[], char *envp[]) {
    (void)envp;
    printf("argc=%d\n", argc);
    for(int i = 0; i < argc; ++i) printf("argv%d=%s\n", i, argv[i]);
    printf("root=%s\n", getenv("ROOT_PATH"));
    printf("home=%s\n", getenv("LC32_GUEST_HOME"));
    printf("native-threads=%s\n", getenv("NATIVE_GUEST_THREADS") ?: "unset");
    printf("dyld=%s\n", getenv("DYLD_PATH") ?: "unset");
    return 0;
}
