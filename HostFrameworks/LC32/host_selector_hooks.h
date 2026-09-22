#pragma once

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdint.h>

// Framework adapters are scoped to calls crossing the guest bridge. Native
// calls, including calls made inside an adapter, keep their ordinary methods.
struct LC32HostSelectorHook {
    SEL replacement = nullptr;
    void (*didInvoke)(id receiver, const uint64_t *arguments) = nullptr;
};

void LC32RegisterHostSelectorHook(Class cls, SEL selector,
    LC32HostSelectorHook hook);
LC32HostSelectorHook LC32FindHostSelectorHook(Class cls, SEL selector);

// Adapters must bypass mirrored guest overrides just as the ordinary bridge
// does. The original selector is passed to this IMP, preserving native _cmd.
IMP LC32NativeHostMethod(id receiver, SEL selector);
