#pragma once

struct guest_kevent_qos_s;
struct GuestWorkqueueDelivery;
int ApplyGuestWorkqueueTimerChange(const guest_kevent_qos_s &change);
bool NextGuestWorkqueueTimerEvent(GuestWorkqueueDelivery &delivery,
    bool allowEventManager = true, bool allowOrdinary = true);
void RequestGuestWorkqueueTimersStop();
void StopGuestWorkqueueTimers();
