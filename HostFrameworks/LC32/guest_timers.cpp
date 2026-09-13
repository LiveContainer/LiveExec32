#include "dynarmic_internal.h"
#include "guest_timer_queue.h"
#include "guest_timers.h"

namespace {
std::mutex timerQueueMutex;
std::shared_ptr<LC32GuestTimerQueue> timerQueue;

bool Stopping() {
    return nativeShutdownRequested.load(std::memory_order_acquire) ||
        guestProcessExitRequested.load(std::memory_order_acquire);
}

void TimerReady(void *) {
    if(Stopping()) return;
    const GuestWorkqueuePumpResult result = PumpGuestWorkqueue();
    if(result == GuestWorkqueuePumpResult::CooperativeTransition) {
        // The cooperative pump only stages an upcall; the actual main
        // runner must install it at its own safe context boundary.
        ScheduleMainGuestWorkqueueTransition();
    }
}
} // namespace

int ApplyGuestWorkqueueTimerChange(const guest_kevent_qos_s &change) {
    // Initialize from the real guest caller, never from the native waiter
    // which may subsequently create a guest workqueue worker.
    EnsureGuestThreadRegistry();
    std::shared_ptr<LC32GuestTimerQueue> queue;
    {
        std::lock_guard<std::mutex> lock(timerQueueMutex);
        if(Stopping()) return ECANCELED;
        if(!timerQueue) {
            if(!(change.flags & EV_ADD) || (change.flags & EV_DELETE)) return 0;
            int error = 0;
            auto created = LC32GuestTimerQueue::Create(TimerReady, nullptr, error);
            if(!created) return error;
            timerQueue = std::move(created);
        }
        queue = timerQueue;
    }
    const int error = queue->Apply(change);
    // Existing direct-workqueue registrations permit deleting an already
    // consumed one-shot. Do not turn libdispatch's idempotent cleanup into a
    // whole-syscall failure (per-change error receipts are not yet modeled).
    return error == ENOENT && (change.flags & EV_DELETE) ? 0 : error;
}

bool NextGuestWorkqueueTimerEvent(GuestWorkqueueDelivery &delivery,
        bool allowEventManager, bool allowOrdinary) {
    if(!allowEventManager && !allowOrdinary) return false;
    std::shared_ptr<LC32GuestTimerQueue> queue;
    {
        std::lock_guard<std::mutex> lock(timerQueueMutex);
        queue = timerQueue;
    }
    if(!queue || Stopping()) return false;
    guest_kevent_qos_s event = {};
    if(!queue->Take(event,
            allowEventManager ? 0 : PTHREAD_PRIORITY_EVENT_MANAGER_FLAG,
            allowOrdinary ? 0 : PTHREAD_PRIORITY_EVENT_MANAGER_FLAG))
        return false;
    delivery = {};
    delivery.event = event;
    delivery.eventManager = (event.qos & PTHREAD_PRIORITY_EVENT_MANAGER_FLAG) != 0;
    return true;
}

void RequestGuestWorkqueueTimersStop() {
    std::shared_ptr<LC32GuestTimerQueue> queue;
    {
        std::lock_guard<std::mutex> lock(timerQueueMutex);
        queue = timerQueue;
    }
    if(queue) queue->RequestStop();
}

void StopGuestWorkqueueTimers() {
    std::shared_ptr<LC32GuestTimerQueue> queue;
    {
        std::lock_guard<std::mutex> lock(timerQueueMutex);
        queue = std::move(timerQueue);
    }
    // Called only by main teardown, never while holding guest registration,
    // native pump, or lifecycle locks: the waiter may be inside the pump.
    if(queue) queue->Stop();
}
