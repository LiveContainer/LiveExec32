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
static pthread_key_t key;
static int started;
static int released;
static int counter;
static __thread uintptr_t tls_cookie;

struct worker_state {
    int index;
    int error;
    pthread_t self;
    uint64_t thread_id;
    mach_port_t mach_thread;
};

static void set_error(struct worker_state *state, int error) {
    if (state->error == 0) {
        state->error = error;
    }
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

    set_error(state, pthread_mutex_lock(&lock));
    ++started;
    set_error(state, pthread_cond_broadcast(&condition));
    while (!released && state->error == 0) {
        set_error(state,
            pthread_cond_wait(&condition, &lock));
    }
    set_error(state, pthread_mutex_unlock(&lock));

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

    int error = pthread_key_create(&key, NULL);
    if (error != 0) {
        return 10;
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
    released = 1;
    if ((error = pthread_cond_broadcast(
            &condition)) != 0) {
        return 50 + error;
    }
    if ((error = pthread_mutex_unlock(&lock)) != 0) {
        return 60 + error;
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
