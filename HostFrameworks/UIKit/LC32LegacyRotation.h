#pragma once

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Restore pre-iOS-8 guest rotation queries/callbacks and the native legacy
 * backing-layer setup, independently of modern-host canvas compensation. */
bool LC32NativeLegacyRotationEnabled(void);
void LC32PrepareNativeLegacyRotationClass(Class cls);
void LC32FinishNativeLegacyRotationStartup(void);

/* Supplied by the emulator: native layout callbacks can arrive before the
 * guest renderer is initialized or on a thread without a guest CPU context. */
BOOL LC32NativeLegacyRotationCanCallGuest(void);

#ifdef __cplusplus
}
#endif
