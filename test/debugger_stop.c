#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void) {
    printf("debugger-stop: starting pid=%d\n", (int)getpid());
    fflush(stdout);
    sleep(2);
    printf("debugger-stop: raising SIGABRT\n");
    fflush(stdout);
    raise(SIGABRT);
    printf("debugger-stop: survived, exiting normally\n");
    fflush(stdout);
    return 0;
}
