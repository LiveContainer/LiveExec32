#pragma once

#include <memory>
#include <cstdint>

struct guest_kevent_qos_s;

/* Native-only, independently testable timer storage. It never executes guest
 * code. The readiness callback runs outside its locks on a native waiter. */
class LC32GuestTimerQueue {
public:
    using ReadyCallback = void (*)(void *);
    static std::unique_ptr<LC32GuestTimerQueue> Create(
        ReadyCallback ready, void *context, int &error);
    ~LC32GuestTimerQueue();
    int Apply(const guest_kevent_qos_s &change);
    bool Take(guest_kevent_qos_s &event, uint32_t excludedQosFlags = 0,
        uint32_t requiredQosFlags = 0);
    void RequestStop();
    // The owner joins; never call Stop from the readiness callback.
    void Stop();

private:
    struct Impl;
    explicit LC32GuestTimerQueue(std::unique_ptr<Impl> impl);
    std::unique_ptr<Impl> impl;
};
