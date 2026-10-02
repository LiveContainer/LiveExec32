#pragma once
#include <stdint.h>

typedef enum : uint32_t {
    LC32SCOpCopyComputerName = 1,
    LC32SCOpCopyLocalHostName,
    LC32SCOpCopyLocation,
    LC32SCOpCopyProxies,
    LC32SCOpCopySupportedInterfaces,
    LC32SCOpCopyCurrentNetworkInfo,
} LC32SCOpcode;

typedef struct {
    uint32_t version;
    uint32_t encoding;
    int32_t status;
    uint32_t reserved;
    uint64_t object;
} LC32SCCopyCall;

void LC32SCSetError(int status);
