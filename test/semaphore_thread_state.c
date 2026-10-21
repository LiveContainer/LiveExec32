#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static unsigned checks;
static unsigned failures;
static int finished;
static mach_timebase_info_data_t timebase;

struct waiter {
    semaphore_t semaphore;
    int timed;
    mach_timespec_t timeout;
    int ready;
    int done;
    kern_return_t result;
    uint64_t elapsed;
};

static uint64_t nanoseconds(void) {
    return mach_absolute_time() * timebase.numer / timebase.denom;
}

static int report(const char *name, int passed) {
    ++checks;
    failures += !passed;
    printf("semaphore-thread-state-%s: %s\n", name, passed ? "PASS" : "FAIL");
    return passed;
}

static void *watchdog(void *unused) {
    (void)unused;
    for (unsigned i = 0; i < 300; ++i) {
        if (__atomic_load_n(&finished, __ATOMIC_ACQUIRE)) return NULL;
        usleep(100000);
    }
    static const char message[] = "semaphore-thread-state: TIMEOUT\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(2);
}

static int wait_flag(const int *flag, unsigned milliseconds) {
    for (unsigned i = 0; i < milliseconds; ++i) {
        if (__atomic_load_n(flag, __ATOMIC_ACQUIRE)) return 1;
        usleep(1000);
    }
    return 0;
}

static void *wait_once(void *opaque) {
    struct waiter *waiter = opaque;
    const uint64_t start = nanoseconds();
    __atomic_store_n(&waiter->ready, 1, __ATOMIC_RELEASE);
    /* Deliberately do not retry KERN_ABORTED in guest code: internal register
     * inspection must not look like a guest-visible semaphore interruption. */
    waiter->result = waiter->timed
        ? semaphore_timedwait(waiter->semaphore, waiter->timeout)
        : semaphore_wait(waiter->semaphore);
    waiter->elapsed = nanoseconds() - start;
    __atomic_store_n(&waiter->done, 1, __ATOMIC_RELEASE);
    return NULL;
}

static pthread_t start_waiter(struct waiter *waiter) {
    pthread_t worker;
    if (!report("create-semaphore", semaphore_create(mach_task_self(),
            &waiter->semaphore, SYNC_POLICY_FIFO, 0) == KERN_SUCCESS) ||
        !report("create-worker", pthread_create(&worker, NULL,
            wait_once, waiter) == 0) ||
        !report("worker-ready", wait_flag(&waiter->ready, 2000))) _exit(1);
    /* ready precedes the trap; allow the worker to enter its blocking call. */
    usleep(20000);
    return worker;
}

static int sample(pthread_t worker) {
    struct {
        arm_thread_state_t state;
        uint32_t canary;
    } output = {.canary = 0x1234abcd};
    mach_msg_type_number_t count = ARM_THREAD_STATE_COUNT;
    return thread_get_state(pthread_mach_thread_np(worker), ARM_THREAD_STATE,
        (thread_state_t)&output.state, &count) == KERN_SUCCESS &&
        count == ARM_THREAD_STATE_COUNT && output.state.__pc != 0 &&
        output.state.__sp != 0 && output.canary == 0x1234abcd;
}

static void join_waiter(pthread_t worker, struct waiter *waiter) {
    if (!report("worker-finished", wait_flag(&waiter->done, 3000))) _exit(1);
    report("join-worker", pthread_join(worker, NULL) == 0);
}

static void signal_after_sampling(int timed) {
    printf("case: %s wait, inspect then signal\n", timed ? "timed" : "infinite");
    struct waiter waiter = {.timed = timed, .timeout = {3, 0}};
    pthread_t worker = start_waiter(&waiter);
    int samples_ok = 1;
    for (unsigned i = 0; i < 30; ++i) {
        if (__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE)) break;
        if (!sample(worker) &&
                !__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE))
            samples_ok = 0;
        usleep(2000);
    }
    report("state-snapshots", samples_ok);
    report("inspection-does-not-end-wait",
        !__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE));
    report("signal", semaphore_signal(waiter.semaphore) == KERN_SUCCESS);
    join_waiter(worker, &waiter);
    report("wait-success", waiter.result == KERN_SUCCESS);
    const mach_timespec_t zero = {0, 0};
    report("signal-consumed-once",
        semaphore_timedwait(waiter.semaphore, zero) == KERN_OPERATION_TIMED_OUT);
    report("destroy", semaphore_destroy(mach_task_self(),
        waiter.semaphore) == KERN_SUCCESS);
}

static void timeout_while_sampling(void) {
    puts("case: original deadline survives repeated inspection");
    struct waiter waiter = {.timed = 1, .timeout = {1, 0}};
    pthread_t worker = start_waiter(&waiter);
    const uint64_t end = nanoseconds() + UINT64_C(1800000000);
    int samples_ok = 1;
    while (nanoseconds() < end &&
            !__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE)) {
        if (!sample(worker) &&
                !__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE))
            samples_ok = 0;
        usleep(5000);
    }
    report("timed-state-snapshots", samples_ok);
    join_waiter(worker, &waiter);
    report("timed-out", waiter.result == KERN_OPERATION_TIMED_OUT);
    report("original-deadline", waiter.elapsed >= UINT64_C(900000000) &&
        waiter.elapsed < UINT64_C(1600000000));
    printf("timed wait elapsed: %.3f seconds\n", waiter.elapsed / 1e9);
    report("destroy-timed", semaphore_destroy(mach_task_self(),
        waiter.semaphore) == KERN_SUCCESS);
}

static void suspend_waiter(int timed) {
    printf("case: %s wait, suspend/resume\n", timed ? "expired timed" : "signaled");
    struct waiter waiter = {.timed = timed, .timeout = {0, 150000000}};
    pthread_t worker = start_waiter(&waiter);
    mach_port_t thread = pthread_mach_thread_np(worker);
    if (!report("suspend", thread_suspend(thread) == KERN_SUCCESS)) _exit(1);
    report("suspended-state", sample(worker));
    if (!timed) report("signal-suspended", semaphore_signal(
        waiter.semaphore) == KERN_SUCCESS);
    usleep(250000);
    report("no-guest-return-while-suspended",
        !__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE));
    const uint64_t resumed = nanoseconds();
    report("resume", thread_resume(thread) == KERN_SUCCESS);
    join_waiter(worker, &waiter);
    report("resumed-result", waiter.result ==
        (timed ? KERN_OPERATION_TIMED_OUT : KERN_SUCCESS));
    if (timed) report("expired-deadline-not-restarted",
        nanoseconds() - resumed < UINT64_C(100000000));
    report("destroy-suspended", semaphore_destroy(mach_task_self(),
        waiter.semaphore) == KERN_SUCCESS);
}

static void destroyed_wait(void) {
    puts("case: destruction is not retried");
    struct waiter waiter = {0};
    pthread_t worker = start_waiter(&waiter);
    report("destroy-blocked", semaphore_destroy(mach_task_self(),
        waiter.semaphore) == KERN_SUCCESS);
    join_waiter(worker, &waiter);
    report("destroy-error-preserved", waiter.result != KERN_SUCCESS);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (mach_timebase_info(&timebase) != KERN_SUCCESS) return 1;
    pthread_t watchdog_thread;
    if (pthread_create(&watchdog_thread, NULL, watchdog, NULL) != 0) return 1;
    pthread_detach(watchdog_thread);
    if (argc == 2 && strcmp(argv[1], "--exit-blocked") == 0) {
        static struct waiter waiter;
        pthread_t worker = start_waiter(&waiter);
        report("shutdown-state-snapshot", sample(worker));
        report("shutdown-worker-still-blocked",
            !__atomic_load_n(&waiter.done, __ATOMIC_ACQUIRE));
        puts("semaphore-thread-state: exiting with blocked waiter");
        _exit(failures != 0);
    }
    signal_after_sampling(0);
    signal_after_sampling(1);
    timeout_while_sampling();
    suspend_waiter(0);
    suspend_waiter(1);
    destroyed_wait();
    report("invalid-port", semaphore_wait(MACH_PORT_NULL) != KERN_SUCCESS);
    semaphore_t semaphore;
    if (semaphore_create(mach_task_self(), &semaphore, SYNC_POLICY_FIFO, 0)
            != KERN_SUCCESS) return 1;
    const mach_timespec_t invalid = {0, 1000000000};
    report("invalid-timeout", semaphore_timedwait(semaphore, invalid) ==
        KERN_INVALID_VALUE);
    semaphore_destroy(mach_task_self(), semaphore);
    __atomic_store_n(&finished, 1, __ATOMIC_RELEASE);
    printf("semaphore-thread-state: %s (%u/%u checks)\n",
        failures ? "FAIL" : "PASS", checks - failures, checks);
    return failures != 0;
}
