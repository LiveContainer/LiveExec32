#include <mach/mach.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

enum {
    WORKERS = 2,
    INCREMENTS = 1000,
    RECYCLES = 70,
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t condition = PTHREAD_COND_INITIALIZER;
static pthread_rwlock_t rwlock = PTHREAD_RWLOCK_INITIALIZER;
static pthread_key_t key;
static int started;
static int released;
static int sampling_ready;
static int rwlock_waiters_started;
/*
 * Keep the spin loop in ordinary translated code. Clang's legacy armv7s
 * lowering for an atomic increment emits the deprecated Thumb high-register
 * CMP encoding with two low registers; Dynarmic deliberately diagnoses that
 * encoding as UNPREDICTABLE. The volatile callback below also forces each
 * spin iteration to return through the JIT dispatcher, which is the relevant
 * contract here: HaltExecution is observed at translated-block boundaries,
 * not inside a single self-linked block. A mutex publishes sampling_ready,
 * while the barriers below provide ordering for sampling_done.
 */
static volatile int sampling_done;
static int (*volatile sampling_complete)(void);
static int counter;
static int rwlock_value = 0x1234;
static __thread uintptr_t tls_cookie;

struct worker_state {
    int index;
    int error;
    pthread_t self;
    uint64_t thread_id;
    mach_port_t mach_thread;
};

__attribute__((noinline))
static int read_sampling_done(void) {
    return sampling_done;
}

static void set_error(struct worker_state *state, int error) {
    if (state->error == 0) {
        state->error = error;
    }
}

static int sample_all_guest_threads(void) {
    fprintf(stderr, "native pthread smoke: task_threads begin\n");
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t thread_count = 0;
    kern_return_t result = task_threads(
        mach_task_self(), &threads, &thread_count);
    if (result != KERN_SUCCESS || thread_count < WORKERS + 1) {
        return 2000 + result;
    }
    fprintf(stderr, "native pthread smoke: sampling %u threads\n",
        thread_count);

    int error = 0;
    for (mach_msg_type_number_t index = 0;
            index < thread_count; ++index) {
        thread_basic_info_data_t basic = {0};
        mach_msg_type_number_t basic_count =
            THREAD_BASIC_INFO_COUNT;
        result = thread_info(
            threads[index], THREAD_BASIC_INFO,
            (thread_info_t)&basic, &basic_count);
        fprintf(stderr,
            "native pthread smoke: thread %u basic result=%d count=%u\n",
            index, result, basic_count);
        if (result != KERN_SUCCESS ||
                basic_count != THREAD_BASIC_INFO_COUNT ||
                basic.user_time.seconds < 0 ||
                basic.user_time.microseconds < 0 ||
                basic.user_time.microseconds >= 1000000 ||
                basic.system_time.seconds < 0 ||
                basic.system_time.microseconds < 0 ||
                basic.system_time.microseconds >= 1000000 ||
                basic.cpu_usage < 0 ||
                basic.cpu_usage > TH_USAGE_SCALE ||
                basic.run_state < TH_STATE_RUNNING ||
                basic.run_state > TH_STATE_HALTED) {
            error = 2050 + result;
            break;
        }

        thread_identifier_info_data_t identifier = {0};
        mach_msg_type_number_t identifier_count =
            THREAD_IDENTIFIER_INFO_COUNT;
        result = thread_info(
            threads[index], THREAD_IDENTIFIER_INFO,
            (thread_info_t)&identifier, &identifier_count);
        fprintf(stderr,
            "native pthread smoke: thread %u identifier result=%d "
            "count=%u\n",
            index, result, identifier_count);
        if (result != KERN_SUCCESS ||
                identifier_count !=
                    THREAD_IDENTIFIER_INFO_COUNT ||
                identifier.thread_id == 0) {
            error = 2075 + result;
            break;
        }

        arm_thread_state_t state = {0};
        mach_msg_type_number_t state_count =
            ARM_THREAD_STATE_COUNT;
        result = thread_get_state(
            threads[index], ARM_THREAD_STATE,
            (thread_state_t)&state, &state_count);
        fprintf(stderr,
            "native pthread smoke: thread %u state result=%d count=%u\n",
            index, result, state_count);
        if (result != KERN_SUCCESS ||
                state_count != ARM_THREAD_STATE_COUNT ||
                state.__sp == 0 || state.__pc == 0) {
            error = 2100 + result;
            break;
        }
    }
    for (mach_msg_type_number_t index = 0;
            index < thread_count; ++index) {
        (void)mach_port_deallocate(
            mach_task_self(), threads[index]);
    }
    (void)vm_deallocate(
        mach_task_self(), (vm_address_t)threads,
        thread_count * sizeof(*threads));
    return error;
}

static void *worker(void *opaque) {
    struct worker_state *state = opaque;
    const uintptr_t cookie =
        0x1000u + (unsigned)state->index;
    tls_cookie = cookie;
    set_error(state, pthread_setspecific(key, state));
    state->self = pthread_self();
    set_error(state,
        pthread_threadid_np(NULL, &state->thread_id));
    state->mach_thread =
        pthread_mach_thread_np(state->self);
    fprintf(stderr, "native pthread smoke: worker %d initialized\n",
        state->index);

    set_error(state, pthread_mutex_lock(&lock));
    ++started;
    set_error(state, pthread_cond_broadcast(&condition));
    while (!released && state->error == 0) {
        set_error(state,
            pthread_cond_wait(&condition, &lock));
    }
    set_error(state, pthread_mutex_unlock(&lock));

    set_error(state, pthread_mutex_lock(&lock));
    ++sampling_ready;
    set_error(state, pthread_cond_broadcast(&condition));
    set_error(state, pthread_mutex_unlock(&lock));
    while (!sampling_complete()) {
        __asm__ volatile("" ::: "memory");
    }
    __sync_synchronize();

    if (state->index < WORKERS) {
        set_error(state, pthread_mutex_lock(&lock));
        ++rwlock_waiters_started;
        set_error(state, pthread_cond_broadcast(&condition));
        set_error(state, pthread_mutex_unlock(&lock));

        const int lock_error = pthread_rwlock_rdlock(&rwlock);
        set_error(state, lock_error);
        if (lock_error == 0) {
            if (rwlock_value != 0x1234) {
                set_error(state, 1005);
            }
            set_error(state, pthread_rwlock_unlock(&rwlock));
        }
    }

    for (int i = 0;
            i < INCREMENTS && state->error == 0; ++i) {
        set_error(state, pthread_mutex_lock(&lock));
        ++counter;
        set_error(state, pthread_mutex_unlock(&lock));
    }
    if (pthread_getspecific(key) != state) {
        set_error(state, 1001);
    }
    if (tls_cookie != cookie) {
        set_error(state, 1002);
    }
    if (!pthread_equal(state->self, pthread_self())) {
        set_error(state, 1003);
    }
    if (state->thread_id == 0 ||
            state->mach_thread == MACH_PORT_NULL) {
        set_error(state, 1004);
    }
    return state;
}

int main(void) {
    pthread_t threads[WORKERS];
    struct worker_state states[WORKERS] = {
        {.index = 0},
        {.index = 1},
    };
    tls_cookie = 0x55aa;
    sampling_complete = read_sampling_done;

    int error = pthread_key_create(&key, NULL);
    if (error != 0) {
        return 10;
    }
    if ((error = pthread_rwlock_wrlock(&rwlock)) != 0) {
        return 15 + error;
    }
    for (int i = 0; i < WORKERS; ++i) {
        error = pthread_create(
            &threads[i], NULL, worker, &states[i]);
        if (error != 0) {
            return 20 + error;
        }
    }

    if ((error = pthread_mutex_lock(&lock)) != 0) {
        return 30 + error;
    }
    while (started != WORKERS) {
        if ((error = pthread_cond_wait(
                &condition, &lock)) != 0) {
            return 40 + error;
        }
    }
    fprintf(stderr, "native pthread smoke: workers parked\n");

    /* Exercise state capture while both foreign guest JITs are parked in a
     * host-side pthread condition wait. */
    if ((error = sample_all_guest_threads()) != 0) {
        return error;
    }
    released = 1;
    if ((error = pthread_cond_broadcast(
            &condition)) != 0) {
        return 50 + error;
    }
    if ((error = pthread_mutex_unlock(&lock)) != 0) {
        return 60 + error;
    }


    if ((error = pthread_mutex_lock(&lock)) != 0) {
        return 65 + error;
    }
    while (sampling_ready != WORKERS) {
        if ((error = pthread_cond_wait(
                &condition, &lock)) != 0) {
            return 66 + error;
        }
    }
    if ((error = pthread_mutex_unlock(&lock)) != 0) {
        return 67 + error;
    }
    /* Exercise the other half of the handshake while both workers are
     * actively executing translated guest instructions. */
    if ((error = sample_all_guest_threads()) != 0) {
        return error;
    }
    __sync_synchronize();
    sampling_done = 1;

    if ((error = pthread_mutex_lock(&lock)) != 0) {
        return 68 + error;
    }
    while (rwlock_waiters_started != WORKERS) {
        if ((error = pthread_cond_wait(
                &condition, &lock)) != 0) {
            return 69 + error;
        }
    }
    if ((error = pthread_mutex_unlock(&lock)) != 0) {
        return 70 + error;
    }
    /* Give both readers a chance to cross the userspace generation update
     * before the writer posts its psynch unlock. This exercises both the
     * grouped-reader return value and the unlock-before-wait prepost race. */
    for (int i = 0; i < 128; ++i) {
        sched_yield();
    }
    if ((error = pthread_rwlock_unlock(&rwlock)) != 0) {
        return 71 + error;
    }
    /* Re-enter immediately, before the awakened readers are guaranteed to
     * have merged their psynch update into the shared L/S words. Darwin
     * treats this as a reader overlap and returns INC|MBIT rather than
     * parking the new reader behind an unlock which already happened. */
    if ((error = pthread_rwlock_rdlock(&rwlock)) != 0) {
        return 72 + error;
    }
    if (rwlock_value != 0x1234) {
        return 73;
    }
    if ((error = pthread_rwlock_unlock(&rwlock)) != 0) {
        return 74 + error;
    }

    for (int i = 0; i < WORKERS; ++i) {
        void *result = NULL;
        if ((error = pthread_join(
                threads[i], &result)) != 0) {
            return 70 + error;
        }
        if (result != &states[i] || states[i].error != 0) {
            return 80 + states[i].error;
        }
    }
    if (pthread_equal(states[0].self, states[1].self) ||
            states[0].thread_id == states[1].thread_id ||
            states[0].mach_thread == states[1].mach_thread) {
        return 90;
    }

    /* A zero psynch return can let the readers run while leaving K/W state
     * behind in the guest lock. Reacquiring it exclusively catches that
     * poisoned state instead of allowing the test to pass by accident. */
    if ((error = pthread_rwlock_wrlock(&rwlock)) != 0) {
        return 95 + error;
    }
    ++rwlock_value;
    if ((error = pthread_rwlock_unlock(&rwlock)) != 0) {
        return 96 + error;
    }
    if ((error = pthread_rwlock_rdlock(&rwlock)) != 0) {
        return 97 + error;
    }
    if (rwlock_value != 0x1235) {
        return 98;
    }
    if ((error = pthread_rwlock_unlock(&rwlock)) != 0) {
        return 99 + error;
    }

    for (int i = 0; i < RECYCLES; ++i) {
        struct worker_state state = {
            .index = i + WORKERS,
        };
        pthread_t thread;
        void *result = NULL;
        if ((error = pthread_create(
                &thread, NULL, worker, &state)) != 0) {
            return 100 + error;
        }
        if ((error = pthread_join(
                thread, &result)) != 0) {
            return 110 + error;
        }
        if (result != &state || state.error != 0) {
            return 120 + state.error;
        }
    }

    if (counter !=
            (WORKERS + RECYCLES) * INCREMENTS ||
            tls_cookie != 0x55aa) {
        return 130;
    }
    if ((error = pthread_key_delete(key)) != 0) {
        return 140 + error;
    }
    fprintf(stderr,
        "native pthread smoke: PASS (%d increments)\n",
        counter);
    return 0;
}
