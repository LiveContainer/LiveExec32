#include "guest_timer_queue.h"

#include <sys/param.h>
#include <sys/event.h>
#include "mach_private.h"
#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <limits>
#include <mutex>
#include <new>
#include <pthread.h>
#include <unordered_map>
#include <unistd.h>

struct LC32GuestTimerQueue::Impl {
    struct Timer {
        guest_kevent_qos_s guest = {};
        uint64_t generation = 0;
        struct kevent64_s readyEvent = {};
        bool pending = false;
        bool enabled = true;
        bool oneShot = false;
    };
    int descriptor = -1;
    int error = 0;
    std::mutex mutex;
    std::mutex joinMutex;
    bool stopping = false;
    bool started = false;
    pthread_t thread = {};
    uint64_t nextIdent = 1; // zero belongs to our EVFILT_USER shutdown wakeup.
    std::unordered_map<uint64_t, Timer> timers;
    ReadyCallback ready = nullptr;
    void *context = nullptr;

    ~Impl() { if(descriptor >= 0) close(descriptor); }

    static void *Run(void *context) {
        auto *self = static_cast<Impl *>(context);
        for(;;) {
            struct kevent64_s events[16] = {};
            const int count = kevent64(self->descriptor, nullptr, 0,
                events, 16, 0, nullptr);
            const int waitError = count < 0 ? errno : 0;
            if(waitError == EINTR) continue;
            bool notify = false;
            {
                std::lock_guard<std::mutex> lock(self->mutex);
                if(self->stopping) return nullptr;
                if(count < 0) {
                    self->error = waitError;
                    fprintf(stderr, "LC32: native timer kqueue wait failed: %d\n", self->error);
                    return nullptr;
                }
                for(int index = 0; index < count; ++index) {
                    const auto &event = events[index];
                    if(event.filter != EVFILT_TIMER) continue;
                    auto found = self->timers.find(event.ident);
                    if(found == self->timers.end()) continue;
                    Timer &timer = found->second;
                    // Rearming changes the token without changing the private
                    // ident. A result already removed by kevent64 may be stale.
                    if(event.udata != timer.generation) continue;
                    if(timer.pending && !(event.flags & EV_ERROR)) {
                        const int64_t previous = timer.readyEvent.data;
                        timer.readyEvent = event;
                        timer.readyEvent.data = previous > 0 && event.data > 0 &&
                            previous > INT64_MAX - event.data
                            ? INT64_MAX : previous + event.data;
                    } else {
                        timer.readyEvent = event;
                    }
                    timer.pending = true;
                    notify |= timer.enabled;
                }
                // EV_ENABLE can make a previously collected expiration
                // deliverable. Its EVFILT_USER poke carries no timer payload.
                if(!notify) {
                    notify = std::any_of(self->timers.begin(), self->timers.end(),
                        [](const auto &entry) {
                            return entry.second.pending && entry.second.enabled;
                        });
                }
            }
            // Pumping may create guest workers. Never hold the timer mutex
            // while acquiring the guest registry, VM, or lifecycle locks.
            if(notify && self->ready) self->ready(self->context);
        }
    }
};

LC32GuestTimerQueue::LC32GuestTimerQueue(std::unique_ptr<Impl> impl)
    : impl(std::move(impl)) {}

std::unique_ptr<LC32GuestTimerQueue> LC32GuestTimerQueue::Create(
        ReadyCallback ready, void *context, int &error) {
    error = 0;
    std::unique_ptr<Impl> impl(new(std::nothrow) Impl);
    if(!impl) { error = ENOMEM; return nullptr; }
    impl->descriptor = kqueue();
    if(impl->descriptor < 0) { error = errno; return nullptr; }
    struct kevent64_s wake = {};
    wake.filter = EVFILT_USER;
    wake.flags = EV_ADD | EV_CLEAR;
    if(kevent64(impl->descriptor, &wake, 1, nullptr, 0, 0, nullptr) < 0) {
        error = errno;
        return nullptr;
    }
    impl->ready = ready;
    impl->context = context;
    std::unique_ptr<LC32GuestTimerQueue> result(
        new(std::nothrow) LC32GuestTimerQueue(std::move(impl)));
    if(!result) { error = ENOMEM; return nullptr; }
    error = pthread_create(&result->impl->thread, nullptr, Impl::Run, result->impl.get());
    if(error) return nullptr;
    result->impl->started = true;
    return result;
}

LC32GuestTimerQueue::~LC32GuestTimerQueue() { Stop(); }

int LC32GuestTimerQueue::Apply(const guest_kevent_qos_s &change) {
    if(change.filter != EVFILT_TIMER) return EINVAL;
    std::lock_guard<std::mutex> lock(impl->mutex);
    if(impl->stopping) return ECANCELED;
    if(impl->error) return impl->error;
    auto found = std::find_if(impl->timers.begin(), impl->timers.end(),
        [&](const auto &entry) {
            const auto &old = entry.second.guest;
            return old.ident == change.ident &&
                (!((old.flags | change.flags) & EV_UDATA_SPECIFIC) ||
                 old.udata == change.udata);
        });
    bool inserted = false;
    if(found == impl->timers.end()) {
        if(!(change.flags & EV_ADD) || (change.flags & EV_DELETE)) return ENOENT;
        if(impl->timers.size() >= 4096) return ENOSPC;
        if(impl->nextIdent == 0) return EOVERFLOW;
        try {
            found = impl->timers.emplace(impl->nextIdent++, Impl::Timer{}).first;
        } catch(const std::bad_alloc &) { return ENOMEM; }
        inserted = true;
    }
    Impl::Timer &timer = found->second;
    if((change.flags & EV_ADD) && timer.generation == UINT64_MAX) {
        if(inserted) impl->timers.erase(found);
        return EOVERFLOW;
    }
    // ENABLE/DISABLE must retain the token: a valid expiration may already
    // be in the waiter's local array, but not yet published as pending.
    const uint64_t generation = timer.generation + ((change.flags & EV_ADD) != 0);
    struct kevent64_s native = {};
    native.ident = found->first;
    native.filter = EVFILT_TIMER;
    // Every guest key has its own native ident, so generation tokens must not
    // themselves become part of the native EV_UDATA_SPECIFIC lookup key.
    native.flags = (change.flags & ~EV_UDATA_SPECIFIC) | EV_RECEIPT;
    native.fflags = change.fflags;
    native.data = change.data;
    native.udata = generation;
    native.ext[0] = change.ext[0];
    native.ext[1] = change.ext[1];
    struct kevent64_s receipt = {};
    const struct timespec immediate = {};
    const int result = kevent64(impl->descriptor, &native, 1,
        &receipt, 1, 0, &immediate);
    int error = result < 0 ? errno :
        result != 1 || !(receipt.flags & EV_ERROR) ? EIO : (int)receipt.data;
    // A one-shot already received by our waiter is still pending for guest
    // delivery. Delete/disable/enable operate on that held event, not on a
    // kernel registration which has already retired.
    if(error == ENOENT && !inserted && timer.oneShot &&
       !(change.flags & EV_ADD)) error = 0;
    if(error) {
        if(inserted) impl->timers.erase(found);
        return error;
    }
    if(change.flags & EV_DELETE) {
        impl->timers.erase(found);
        return 0;
    }
    if(change.flags & EV_ADD) {
        timer.guest = change;
        timer.pending = false;
        timer.enabled = !(change.flags & EV_DISABLE);
        timer.oneShot = (change.flags & EV_ONESHOT) ||
            (change.fflags & NOTE_ABSOLUTE);
    } else {
        // ENABLE/DISABLE do not replace a timer's interval or clear an
        // expiration which was collected while it was disabled.
        if(change.flags & EV_DISABLE) timer.enabled = false;
        else if(change.flags & EV_ENABLE) timer.enabled = true;
    }
    timer.generation = generation;
    if(timer.pending && timer.enabled) {
        // Wake the waiter rather than invoking an arbitrary callback while
        // the caller may still own the guest workqueue registration lock.
        struct kevent64_s wake = {};
        wake.filter = EVFILT_USER;
        wake.fflags = NOTE_TRIGGER;
        (void)kevent64(impl->descriptor, &wake, 1, nullptr, 0, 0, nullptr);
    }
    return 0;
}

bool LC32GuestTimerQueue::Take(guest_kevent_qos_s &event, uint32_t excludedQosFlags,
        uint32_t requiredQosFlags) {
    std::lock_guard<std::mutex> lock(impl->mutex);
    if(impl->stopping) return false;
    for(auto found = impl->timers.begin(); found != impl->timers.end(); ++found) {
        Impl::Timer &timer = found->second;
        if(!timer.pending || !timer.enabled ||
           (static_cast<uint32_t>(timer.guest.qos) & excludedQosFlags) ||
           (static_cast<uint32_t>(timer.guest.qos) & requiredQosFlags) != requiredQosFlags)
            continue;
        event = timer.guest;
        event.flags = (timer.readyEvent.flags & ~EV_RECEIPT) |
            (timer.guest.flags & EV_UDATA_SPECIFIC);
        event.fflags = timer.readyEvent.fflags;
        event.data = timer.readyEvent.data;
        event.ext[0] = timer.readyEvent.ext[0];
        event.ext[1] = timer.readyEvent.ext[1];
        timer.pending = false;
        if(timer.oneShot) impl->timers.erase(found);
        return true;
    }
    return false;
}

void LC32GuestTimerQueue::RequestStop() {
    std::lock_guard<std::mutex> lock(impl->mutex);
    if(impl->stopping) return;
    impl->stopping = true;
    impl->timers.clear();
    struct kevent64_s wake = {};
    wake.filter = EVFILT_USER;
    wake.fflags = NOTE_TRIGGER;
    (void)kevent64(impl->descriptor, &wake, 1, nullptr, 0, 0, nullptr);
}

void LC32GuestTimerQueue::Stop() {
    std::lock_guard<std::mutex> joinLock(impl->joinMutex);
    RequestStop();
    if(impl->started) {
        const int error = pthread_join(impl->thread, nullptr);
        if(error) {
            fprintf(stderr, "LC32: could not join native timer waiter: %d\n", error);
            std::terminate();
        }
        impl->started = false;
    }
}
