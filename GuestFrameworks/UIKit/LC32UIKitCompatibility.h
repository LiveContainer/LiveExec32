#ifndef LC32_UIKIT_COMPATIBILITY_H
#define LC32_UIKIT_COMPATIBILITY_H
#include "../../include/LC32UIKitCompatibilityConfig.h"

#import <Foundation/Foundation.h>

/* Process-wide host policy, cached once for all guest UIKit adaptations. */
__attribute__((visibility("hidden")))
BOOL LC32GuestUIKitLegacyCompatibilityEnabled(void);

#endif
