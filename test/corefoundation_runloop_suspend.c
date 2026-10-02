#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static unsigned checks, failures;
static int finished;
struct State { CFRunLoopRef loop; CFRunLoopSourceRef source; int ready, fired, done, mode; };
static void check(const char *name, int pass) {
    printf("runloop-suspend-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
static int waitFlag(int *flag) {
    for(unsigned i = 0; i < 5000; ++i) {
        if(__atomic_load_n(flag, __ATOMIC_ACQUIRE)) return 1;
        usleep(1000);
    }
    return 0;
}
static void perform(void *info) {
    struct State *state = info;
    __atomic_store_n(&state->fired, 1, __ATOMIC_RELEASE);
    CFRunLoopStop(state->loop);
}
static void *worker(void *info) {
    struct State *state = info;
    state->loop = CFRunLoopGetCurrent(); CFRetain(state->loop);
    CFRunLoopSourceContext context = {0}; context.info = state; context.perform = perform;
    state->source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(state->loop, state->source, kCFRunLoopDefaultMode);
    __atomic_store_n(&state->ready, 1, __ATOMIC_RELEASE);
    if(state->mode) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, false);
    else CFRunLoopRun();
    __atomic_store_n(&state->done, 1, __ATOMIC_RELEASE);
    return NULL;
}
static void *watchdog(void *unused) {
    (void)unused;
    for(unsigned i = 0; i < 100; ++i) {
        if(__atomic_load_n(&finished, __ATOMIC_ACQUIRE)) return NULL;
        usleep(100000);
    }
    const char message[] = "runloop-suspend: TIMEOUT\n";
    write(2, message, sizeof(message) - 1); _exit(2);
}
int main(void) {
    setbuf(stdout, NULL);
    pthread_t guard; if(pthread_create(&guard, NULL, watchdog, NULL)) return 1;
    for(int mode = 0; mode < 2; ++mode) {
        struct State state = {0}; state.mode = mode;
        pthread_t thread;
        check("create-worker", pthread_create(&thread, NULL, worker, &state) == 0);
        if(!waitFlag(&state.ready)) { check("worker-ready", 0); return 1; }
        unsigned i;
        for(i = 0; i < 5000 && !CFRunLoopIsWaiting(state.loop); ++i) usleep(1000);
        check("native-loop-waiting", i < 5000);
        const mach_port_t port = pthread_mach_thread_np(thread);
        kern_return_t suspended = thread_suspend(port);
        check("suspend-native-loop", suspended == KERN_SUCCESS);
        CFRunLoopSourceSignal(state.source); CFRunLoopWakeUp(state.loop);
        usleep(100000);
        check("callback-held-while-suspended", !__atomic_load_n(&state.fired, __ATOMIC_ACQUIRE));
        if(suspended == KERN_SUCCESS) check("resume", thread_resume(port) == KERN_SUCCESS);
        check("callback-after-resume", waitFlag(&state.fired));
        check("loop-returns", waitFlag(&state.done));
        check("join", pthread_join(thread, NULL) == 0);
        CFRunLoopSourceInvalidate(state.source); CFRelease(state.source); CFRelease(state.loop);
    }
    __atomic_store_n(&finished, 1, __ATOMIC_RELEASE); pthread_join(guard, NULL);
    printf("runloop-suspend: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
