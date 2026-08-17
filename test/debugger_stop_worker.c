#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void *crash_worker(void *opaque) {
    (void)opaque;
    /* Sleep briefly so the main thread reaches its host call first. */
    usleep(500 * 1000);
    printf("debugger-stop-worker: raising SIGABRT\n");
    fflush(stdout);
    raise(SIGABRT);
    return NULL;
}

int main(void) {
    printf("debugger-stop-worker: starting pid=%d\n", (int)getpid());
    fflush(stdout);
    pthread_t thread;
    if (pthread_create(&thread, NULL, crash_worker, NULL) != 0) {
        fprintf(stderr, "pthread_create failed\n");
        return 2;
    }
    /* Park the main thread in a long host call while the worker crashes. */
    printf("debugger-stop-worker: main sleeping\n");
    fflush(stdout);
    sleep(30);
    printf("debugger-stop-worker: main woke up\n");
    fflush(stdout);
    return 0;
}
