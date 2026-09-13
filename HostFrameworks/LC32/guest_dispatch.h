#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Register after the guest dlsym/callback entry points become available.
 * The source borrows libdispatch's receive right; it never destroys it. */
void LC32InstallGuestMainQueueSource(void);
void LC32RemoveGuestMainQueueSource(void);

#ifdef __cplusplus
}
#endif
