// Tests the real host timer backend without Dynarmic, guest TLS, or a simulator.
#include <sys/param.h>
#include <sys/event.h>
#include <sys/time.h>
#include <unistd.h>
#include <signal.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "mach_private.h"
#include "guest_timer_queue.h"

using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;

static unsigned checks, failures;

static void check(const std::string &label, bool passed) {
    std::printf("guest-timer/%s: %s\n", label.c_str(), passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

static void watchdog(int) {
    const char message[] = "guest-timer/watchdog: FAIL\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(2);
}

// Only the backend translation unit renames kevent64 to this wrapper. The
// real syscall runs unchanged, then this test can hold a timer result in the
// precise gap between kernel consumption and backend mutex publication.
static struct {
    std::mutex mutex;
    std::condition_variable changed;
    bool armed = false, paused = false, released = false;
} inFlight;

extern "C" int LC32TestKevent64(int descriptor, const struct kevent64_s *changes,
        int changeCount, struct kevent64_s *events, int eventCount,
        unsigned flags, const struct timespec *timeout) {
    int result = kevent64(descriptor, changes, changeCount, events, eventCount,
        flags, timeout);
    if(changeCount == 0 && result > 0) {
        bool timerResult = false;
        for(int index = 0; index < result; ++index)
            timerResult |= events[index].filter == EVFILT_TIMER;
        std::unique_lock<std::mutex> lock(inFlight.mutex);
        if(timerResult && inFlight.armed) {
            inFlight.armed = false;
            inFlight.paused = true;
            inFlight.changed.notify_all();
            inFlight.changed.wait_for(lock, 2s, [] { return inFlight.released; });
        }
    }
    return result;
}

static void armBarrier(void) {
    std::lock_guard<std::mutex> lock(inFlight.mutex);
    inFlight.armed = true;
    inFlight.paused = inFlight.released = false;
}

static bool waitBarrier(void) {
    std::unique_lock<std::mutex> lock(inFlight.mutex);
    return inFlight.changed.wait_for(lock, 1s, [] { return inFlight.paused; });
}

static void releaseBarrier(void) {
    std::lock_guard<std::mutex> lock(inFlight.mutex);
    inFlight.armed = false;
    inFlight.released = true;
    inFlight.changed.notify_all();
}

struct Ready {
    std::mutex mutex;
    std::condition_variable changed;
    unsigned count = 0;
    std::atomic<bool> stopOnReady{false};
    std::atomic<LC32GuestTimerQueue *> queue{nullptr};

    static void Call(void *context) {
        auto &ready = *static_cast<Ready *>(context);
        {
            std::lock_guard<std::mutex> lock(ready.mutex);
            ++ready.count;
        }
        ready.changed.notify_all();
        // RequestStop is allowed from a ready callback; Stop joins elsewhere.
        // This also detects a backend that invokes ready while holding its lock.
        if(ready.stopOnReady.load()) ready.queue.load()->RequestStop();
    }

    bool wait(unsigned previous) {
        std::unique_lock<std::mutex> lock(mutex);
        return changed.wait_for(lock, 1s, [&] { return count > previous; });
    }

    unsigned value() {
        std::lock_guard<std::mutex> lock(mutex);
        return count;
    }
};

static std::unique_ptr<LC32GuestTimerQueue> create(Ready &ready) {
    int error = 0;
    auto queue = LC32GuestTimerQueue::Create(Ready::Call, &ready, error);
    check("create", queue != nullptr && error == 0);
    ready.queue.store(queue.get());
    return queue;
}

static guest_kevent_qos_s timer(uint64_t ident, uint64_t udata,
        int64_t data, uint32_t fflags, uint16_t flags = EV_ADD | EV_ONESHOT) {
    guest_kevent_qos_s event{};
    event.ident = ident;
    event.filter = EVFILT_TIMER;
    event.flags = flags;
    event.qos = 0x1500;
    event.udata = udata;
    event.fflags = fflags;
    event.xflags = 0x12345678;
    event.data = data;
    event.ext[2] = UINT64_C(0x1122334455667788);
    event.ext[3] = UINT64_C(0x8877665544332211);
    return event;
}

static bool take(LC32GuestTimerQueue &queue, guest_kevent_qos_s &event,
        std::chrono::milliseconds duration = 1000ms,
        uint32_t excludedQos = 0, uint32_t requiredQos = 0) {
    auto end = Clock::now() + duration;
    do {
        if(queue.Take(event, excludedQos, requiredQos)) return true;
        std::this_thread::sleep_for(1ms);
    } while(Clock::now() < end);
    return false;
}

static bool quiet(LC32GuestTimerQueue &queue, std::chrono::milliseconds duration) {
    guest_kevent_qos_s event{};
    return !take(queue, event, duration);
}

static bool sameMetadata(const guest_kevent_qos_s &actual,
        const guest_kevent_qos_s &expected) {
    return actual.ident == expected.ident && actual.filter == EVFILT_TIMER &&
        actual.udata == expected.udata && actual.qos == expected.qos &&
        actual.xflags == expected.xflags &&
        !std::memcmp(actual.ext + 2, expected.ext + 2, 2 * sizeof(actual.ext[0]));
}

static void clocksAndMetadata(void) {
    Ready ready;
    auto queue = create(ready);
    if(!queue) return;
    auto invalid = timer(1, 2, 30, 0);
    invalid.filter = EVFILT_USER;
    check("reject-nontimer-filter", queue->Apply(invalid) == EINVAL);
    invalid.filter = EVFILT_TIMER;
    invalid.flags = EV_DELETE;
    check("missing-delete-errno", queue->Apply(invalid) == ENOENT);
    struct Unit { const char *name; uint32_t flag; int64_t data; } units[] = {
        {"milliseconds", 0, 30},
        {"microseconds", NOTE_USECONDS, 30000},
        {"nanoseconds", NOTE_NSECONDS, 30000000},
    };
    unsigned index = 0;
    for(const auto &unit : units) {
        auto input = timer(UINT64_C(0x1234567800000000) + ++index,
            UINT64_C(0xfedcba9876543210), unit.data, unit.flag);
        auto start = Clock::now();
        check(std::string(unit.name) + "-apply", queue->Apply(input) == 0);
        guest_kevent_qos_s output{};
        bool received = take(*queue, output);
        check(std::string(unit.name) + "-event", received && output.data >= 1);
        check(std::string(unit.name) + "-not-early", received && Clock::now() - start >= 28ms);
        check(std::string(unit.name) + "-wide-metadata", received && sameMetadata(output, input));
        check(std::string(unit.name) + "-one-shot", quiet(*queue, 35ms));
    }

    struct timeval wall{};
    gettimeofday(&wall, nullptr);
    int64_t wallDeadline = int64_t(wall.tv_sec) * 1000000 + wall.tv_usec + 40000;
    auto wallInput = timer(40, 41, wallDeadline, NOTE_ABSOLUTE | NOTE_USECONDS);
    auto wallStart = Clock::now();
    check("wall-absolute-apply", queue->Apply(wallInput) == 0);
    guest_kevent_qos_s output{};
    bool received = take(*queue, output);
    check("wall-absolute-wide-deadline", received && output.data >= 1 &&
        Clock::now() - wallStart >= 38ms);

    mach_timebase_info_data_t timebase{};
    mach_timebase_info(&timebase);
    uint64_t machDeadline = mach_absolute_time() +
        UINT64_C(40000000) * timebase.denom / timebase.numer;
    auto machInput = timer(50, 51, int64_t(machDeadline), NOTE_ABSOLUTE | NOTE_MACHTIME);
    auto machStart = Clock::now();
    check("mach-absolute-apply", queue->Apply(machInput) == 0);
    received = take(*queue, output);
    check("mach-absolute-wide-deadline", received && output.data >= 1 &&
        Clock::now() - machStart >= 38ms);
}

static void updatesAndIdentity(void) {
    Ready ready;
    auto queue = create(ready);
    if(!queue) return;
    auto input = timer(100, 101, 20, 0);
    unsigned previous = ready.value();
    check("pending-generation-apply", queue->Apply(input) == 0);
    check("pending-generation-ready", ready.wait(previous));
    // Do not Take the old event: a rearm must invalidate that pending generation.
    input.data = 70;
    auto rearmStart = Clock::now();
    check("pending-generation-rearm", queue->Apply(input) == 0);
    guest_kevent_qos_s output{};
    check("pending-generation-old-event-dropped", !queue->Take(output));
    bool received = take(*queue, output);
    check("pending-generation-new-event", received && sameMetadata(output, input) &&
        Clock::now() - rearmStart >= 68ms);

    input = timer(200, 201, 25, 0, EV_ADD | EV_DISABLE | EV_ONESHOT);
    check("disabled-add", queue->Apply(input) == 0);
    check("disabled-quiet", quiet(*queue, 60ms));
    input.flags = EV_ENABLE;
    check("enable", queue->Apply(input) == 0);
    check("enable-delivers", take(*queue, output) && output.ident == input.ident);

    input = timer(250, 251, 15, 0);
    previous = ready.value();
    check("pending-disable-add", queue->Apply(input) == 0);
    check("pending-disable-ready", ready.wait(previous));
    input.flags = EV_DISABLE;
    check("pending-disable", queue->Apply(input) == 0);
    check("pending-disable-holds-event", !queue->Take(output));
    previous = ready.value();
    input.flags = EV_ENABLE;
    check("pending-enable", queue->Apply(input) == 0);
    check("pending-enable-renotifies", ready.wait(previous));
    check("pending-enable-delivers", take(*queue, output) && output.ident == input.ident);

    input = timer(300, 301, 15, 0);
    previous = ready.value();
    check("pending-delete-add", queue->Apply(input) == 0);
    check("pending-delete-ready", ready.wait(previous));
    input.flags = EV_DELETE;
    check("pending-delete", queue->Apply(input) == 0);
    check("pending-delete-drops-event", quiet(*queue, 40ms));

    auto first = timer(400, UINT64_C(0x1111111122222222), 30, 0,
        EV_ADD | EV_ONESHOT | EV_UDATA_SPECIFIC);
    auto second = timer(400, UINT64_C(0x3333333344444444), 50, 0,
        EV_ADD | EV_ONESHOT | EV_UDATA_SPECIFIC);
    check("udata-first-add", queue->Apply(first) == 0);
    check("udata-second-add", queue->Apply(second) == 0);
    first.flags = EV_DELETE | EV_UDATA_SPECIFIC;
    check("udata-delete-first-only", queue->Apply(first) == 0);
    received = take(*queue, output);
    check("udata-second-survives", received && sameMetadata(output, second));
    check("udata-deleted-first-quiet", quiet(*queue, 60ms));

    input = timer(500, 501, 20, 0, EV_ADD | EV_CLEAR);
    check("periodic-add", queue->Apply(input) == 0);
    check("periodic-first", take(*queue, output) && output.data >= 1);
    check("periodic-second", take(*queue, output) && output.data >= 1);
    input.flags = EV_DELETE;
    check("periodic-delete", queue->Apply(input) == 0);
    check("periodic-delete-quiet", quiet(*queue, 60ms));
}

static void shutdown(void) {
    Ready ready;
    auto queue = create(ready);
    if(!queue) return;
    ready.stopOnReady.store(true);
    auto input = timer(600, 601, 15, 0, EV_ADD | EV_CLEAR);
    check("shutdown-add", queue->Apply(input) == 0);
    check("shutdown-callback-request", ready.wait(0));
    queue->RequestStop();
    queue->RequestStop();
    auto start = Clock::now();
    queue->Stop();
    queue->Stop();
    check("shutdown-idempotent-bounded", Clock::now() - start < 1s);
    unsigned atStop = ready.value();
    std::this_thread::sleep_for(40ms);
    check("shutdown-no-later-ready", ready.value() == atStop);
    guest_kevent_qos_s output{};
    check("shutdown-no-pending-take", !queue->Take(output));
    check("shutdown-rejects-apply", queue->Apply(input) == ECANCELED);
}

static void inFlightChanges(void) {
    for(unsigned mode = 0; mode < 3; ++mode) {
        Ready ready;
        auto queue = create(ready);
        if(!queue) continue;
        const char *name = mode == 0 ? "inflight-disable-enable" :
            mode == 1 ? "inflight-rearm" : "inflight-delete";
        auto input = timer(700 + mode, 710 + mode, 15, 0);
        armBarrier();
        check(std::string(name) + "-add", queue->Apply(input) == 0);
        check(std::string(name) + "-kernel-consumed", waitBarrier());
        auto start = Clock::now();
        if(mode == 0) {
            input.flags = EV_DISABLE;
            check("inflight-disable-no-enoent", queue->Apply(input) == 0);
            input.flags = EV_ENABLE;
            check("inflight-enable-no-enoent", queue->Apply(input) == 0);
        } else {
            input.flags = mode == 1 ? EV_ADD | EV_ONESHOT : EV_DELETE;
            input.data = 70;
            check(std::string(name) + "-apply", queue->Apply(input) == 0);
        }
        releaseBarrier();
        guest_kevent_qos_s output{};
        if(mode == 0) {
            check("inflight-disable-enable-preserves-expiry", take(*queue, output) &&
                output.ident == input.ident && output.data >= 1);
        } else if(mode == 1) {
            bool received = take(*queue, output);
            check("inflight-rearm-discards-old-expiry", received &&
                Clock::now() - start >= 68ms && output.ident == input.ident);
        } else {
            check("inflight-delete-suppresses-expiry", quiet(*queue, 50ms));
        }
    }
}

static void qosSelection(void) {
    Ready ready;
    auto queue = create(ready);
    if(!queue) return;
    auto ordinary = timer(800, 801, 15, 0);
    auto manager = timer(810, 811, 15, 0);
    const uint32_t managerFlag = PTHREAD_PRIORITY_EVENT_MANAGER_FLAG;
    manager.qos |= managerFlag;
    guest_kevent_qos_s output{};
    bool registered = queue->Apply(ordinary) == 0 && queue->Apply(manager) == 0;
    check("manager-only-preserves-ordinary", registered &&
        take(*queue, output, 1000ms, 0, managerFlag) && output.ident == manager.ident &&
        take(*queue, output, 1000ms, managerFlag) && output.ident == ordinary.ident);
    registered = queue->Apply(ordinary) == 0 && queue->Apply(manager) == 0;
    check("ordinary-only-preserves-manager", registered &&
        take(*queue, output, 1000ms, managerFlag) && output.ident == ordinary.ident &&
        take(*queue, output, 1000ms, 0, managerFlag) && output.ident == manager.ident);
    check("qos-selection-no-extra-event", !queue->Take(output));
}

int main(void) {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    signal(SIGALRM, watchdog);
    alarm(20);
    clocksAndMetadata();
    updatesAndIdentity();
    inFlightChanges();
    qosSelection();
    shutdown();
    alarm(0);
    std::printf("guest-timer: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
