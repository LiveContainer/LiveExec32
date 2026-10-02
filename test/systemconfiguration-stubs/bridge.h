#pragma once
#include <cstdint>
#include <dlfcn.h>
#include <CoreFoundation/CoreFoundation.h>
using u32 = uint32_t;
int Dynarmic_mem_1read(u32 address, u32 size, char *output);
int Dynarmic_mem_1write(u32 address, u32 size, const char *input);
u32 LC32GuestObjectForOwnedHostObject(CFTypeRef object);
