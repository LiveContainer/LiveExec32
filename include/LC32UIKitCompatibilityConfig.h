#pragma once

// Build both halves with 0 for native UIKit policy plus retained fixes.
// Keep font/layout/alert fixes, legacy identifier/AdMob shims,
// ABI/resource forwarding and debugger support independent of this flag.
#ifndef LC32_UIKIT_COMPATIBILITY
#define LC32_UIKIT_COMPATIBILITY 1
#endif

#if LC32_UIKIT_COMPATIBILITY != 0 && LC32_UIKIT_COMPATIBILITY != 1
#error LC32_UIKIT_COMPATIBILITY must be 0 or 1
#endif
