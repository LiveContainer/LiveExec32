#include <SystemConfiguration/SystemConfiguration.h>
#include "systemconfiguration-stubs/bridge.h"
#include "../GuestFrameworks/SystemConfiguration/LC32SystemConfigurationBridge.h"
#include <cstdio>
#include <cstring>
#include <initializer_list>

static LC32SCCopyCall memory;
static bool rejectWrite, returnNull;
static unsigned checks, failures, transfers, calls;
static CFTypeRef transferred, inputObject;
static void check(const char *name, bool pass) {
    printf("sc-copy-%s: %s\n", name, pass ? "PASS" : "FAIL");
    ++checks; failures += !pass;
}
int Dynarmic_mem_1read(u32 address, u32 size, char *output) {
    if(address != 0x1000 || size != sizeof(memory)) return -1;
    memcpy(output, &memory, size); return 0;
}
int Dynarmic_mem_1write(u32 address, u32 size, const char *input) {
    if(rejectWrite || address != 0x1000 || size != sizeof(memory)) return -1;
    memcpy(&memory, input, size); return 0;
}
u32 LC32GuestObjectForOwnedHostObject(CFTypeRef object) {
    if(!object) return 0;
    ++transfers; transferred = object;
    return 0x2000;
}
static CFTypeRef copyValue(CFTypeRef input) {
    ++calls; inputObject = input;
    return returnNull ? nullptr : CFStringCreateCopy(nullptr, CFSTR("fixture"));
}
static CFStringRef copyComputerName(CFTypeRef input, CFStringEncoding *encoding) {
    *encoding = kCFStringEncodingUTF8;
    return (CFStringRef)copyValue(input);
}
static CFTypeRef copyInterfaces() { return copyValue(nullptr); }
static int lastError() { return kSCStatusAccessError; }
static void *testOpen(const char *, int) { return (void *)1; }
static void *testSymbol(void *, const char *name) {
    if(!strcmp(name, "SCError")) return (void *)lastError;
    if(!strcmp(name, "SCDynamicStoreCopyComputerName")) return (void *)copyComputerName;
    if(!strcmp(name, "SCDynamicStoreCopyLocation")) return nullptr; // absent SPI
    if(!strcmp(name, "CNCopySupportedInterfaces")) return (void *)copyInterfaces;
    return (void *)copyValue;
}
#define dlopen testOpen
#define dlsym testSymbol
#include "../HostFrameworks/SystemConfiguration/SystemConfiguration.mm"
#undef dlopen
#undef dlsym

static void reset() {
    if(transferred) CFRelease(transferred);
    transferred = nullptr; transfers = calls = 0;
    rejectWrite = returnNull = false;
    memory = {}; memory.version = 1;
    memory.object = UINT64_C(0x1234567887654321);
    memory.reserved = 0xa5a5a5a5;
}
int main() {
    reset();
    check("null-address", !LC32_SystemConfiguration_Copy(1, 0));
    check("overflow-address", !LC32_SystemConfiguration_Copy(1, 0xfffffff0));
    check("unmapped-address", !LC32_SystemConfiguration_Copy(1, 0x1234));
    memory.version = 2;
    check("unknown-version", !LC32_SystemConfiguration_Copy(1, 0x1000) && !calls);
    reset();
    check("unknown-opcode", !LC32_SystemConfiguration_Copy(99, 0x1000) &&
          memory.status == kSCStatusFailed && !calls);
    check("missing-native-export", !LC32_SystemConfiguration_Copy(LC32SCOpCopyLocation, 0x1000) &&
          memory.status == kSCStatusFailed && !calls);
    for(u32 op : {1u, 2u, 4u, 5u, 6u}) {
        reset();
        check("owned-result", LC32_SystemConfiguration_Copy(op, 0x1000) == 0x2000 &&
              calls == 1 && transfers == 1 && transferred);
        check("status-and-layout", memory.status == kSCStatusOK && memory.reserved == 0xa5a5a5a5);
        check("input-pointer-width", uintptr_t(inputObject) == (op == 5 ? 0 : memory.object));
        if(op == 1) check("encoding-width", memory.encoding == kCFStringEncodingUTF8);
        reset(); returnNull = true;
        check("native-failure", !LC32_SystemConfiguration_Copy(op, 0x1000) &&
              memory.status == kSCStatusAccessError && !transfers);
    }
    reset(); rejectWrite = true;
    check("failed-write-no-transfer", !LC32_SystemConfiguration_Copy(1, 0x1000) && !transfers);
    reset();
    printf("systemconfiguration-copy: %u checks, %u failures\n", checks, failures);
    return failures != 0;
}
