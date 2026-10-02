#pragma once
#import <Foundation/Foundation.h>
#include <cstdint>
using u32 = uint32_t;
int Dynarmic_mem_1read(u32, u32, char *);
int Dynarmic_mem_1write(u32, u32, const char *);
u32 LC32GuestObjectForOwnedHostObject(CFTypeRef);
u32 guest_dlsym(const char *);
uint64_t LC32InvokeGuestC(u32, bool, int, u32 *);
@interface NSObject (CoreMediaFixture)
- (u32)guest_self;
@end
