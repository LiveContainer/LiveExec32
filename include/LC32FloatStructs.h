#ifndef LC32_FLOAT_STRUCTS_H
#define LC32_FLOAT_STRUCTS_H

#include <stddef.h>
#include <string.h>

// Only for packed sequences of ARM32 floats that become ARM64 doubles
// (CGFloat-based structs). Fixed-width doubles/floats need no conversion.
// Source and destination must be separate buffers. memcpy also supports
// nested public structs and unaligned NSValue bytes without aliasing casts.
static inline void LC32WidenFloatStruct(const void *guest, void *host,
                                      size_t count) {
    for(size_t i = 0; i < count; ++i) {
        float value;
        memcpy(&value, (const char *)guest + i * sizeof(value), sizeof(value));
        const double widened = value;
        memcpy((char *)host + i * sizeof(widened), &widened, sizeof(widened));
    }
}

static inline void LC32NarrowFloatStruct(const void *host, void *guest,
                                       size_t count) {
    for(size_t i = 0; i < count; ++i) {
        double value;
        memcpy(&value, (const char *)host + i * sizeof(value), sizeof(value));
        const float narrowed = (float)value;
        memcpy((char *)guest + i * sizeof(narrowed), &narrowed, sizeof(narrowed));
    }
}

#define LC32_DEFINE_FLOAT_STRUCT(COUNT) \
    typedef struct { double values[COUNT]; } LC32Floats##COUNT##_64; \
    static inline void LC32Host##COUNT##Floats(const void *guest, void *host) { \
        LC32WidenFloatStruct(guest, host, COUNT); \
    } \
    static inline void LC32Guest##COUNT##Floats(const void *host, void *guest) { \
        LC32NarrowFloatStruct(host, guest, COUNT); \
    }

LC32_DEFINE_FLOAT_STRUCT(2)
LC32_DEFINE_FLOAT_STRUCT(4)
LC32_DEFINE_FLOAT_STRUCT(6)
LC32_DEFINE_FLOAT_STRUCT(16)
#undef LC32_DEFINE_FLOAT_STRUCT

#endif
