#include "LC32FloatStructs.h"
#include <math.h>
#include <stdint.h>
#include <stdio.h>

static unsigned failures;
#define CHECK(condition) do { if(!(condition)) { \
    fprintf(stderr, "float structs: line %d: %s\n", __LINE__, #condition); \
    ++failures; \
} } while(0)

static int sameFloat(float a, float b) {
    uint32_t ab, bb;
    memcpy(&ab, &a, sizeof(ab));
    memcpy(&bb, &b, sizeof(bb));
    return ab == bb || (isnan(a) && isnan(b));
}

int main(void) {
    const struct {
        size_t count, hostSize;
        void (*widen)(const void *, void *);
        void (*narrow)(const void *, void *);
    } layouts[] = {
        {2, sizeof(LC32Floats2_64), LC32Host2Floats, LC32Guest2Floats},
        {4, sizeof(LC32Floats4_64), LC32Host4Floats, LC32Guest4Floats},
        {6, sizeof(LC32Floats6_64), LC32Host6Floats, LC32Guest6Floats},
        {16, sizeof(LC32Floats16_64), LC32Host16Floats, LC32Guest16Floats},
    };
    const float samples[] = {0.0f, -0.0f, 1.25f, -9.5f, 0x1p-149f,
        0x1.fffffep127f, INFINITY, -INFINITY, NAN};
    for(size_t layout = 0; layout < sizeof(layouts) / sizeof(layouts[0]); ++layout) {
        const size_t count = layouts[layout].count;
        CHECK(layouts[layout].hostSize == count * sizeof(double));
        for(size_t sample = 0; sample < sizeof(samples) / sizeof(samples[0]); ++sample) {
            // Deliberately unaligned input/output, with guard bytes on both ends.
            unsigned char guest[16 * sizeof(float) + 8];
            unsigned char host[16 * sizeof(double) + 8];
            unsigned char output[sizeof(guest)], original[sizeof(guest)];
            memset(guest, 0xa5, sizeof(guest));
            memset(host, 0xa5, sizeof(host));
            memset(output, 0xa5, sizeof(output));
            for(size_t i = 0; i < count; ++i)
                memcpy(guest + 1 + i * sizeof(float), &samples[sample], sizeof(float));
            memcpy(original, guest, sizeof(guest));
            layouts[layout].widen(guest + 1, host + 3);
            CHECK(!memcmp(original, guest, sizeof(guest)));
            for(size_t i = 0; i < count; ++i) {
                double value;
                memcpy(&value, host + 3 + i * sizeof(value), sizeof(value));
                CHECK((isnan(value) && isnan(samples[sample])) ||
                    (value == (double)samples[sample] &&
                     !!signbit(value) == !!signbit(samples[sample])));
                // Also check narrowing values not exactly representable as floats.
                if(isfinite(value) && value != 0.0) value += 0.123456789;
                memcpy(host + 3 + i * sizeof(value), &value, sizeof(value));
            }
            layouts[layout].narrow(host + 3, output + 1);
            for(size_t i = 0; i < count; ++i) {
                double h;
                float g;
                memcpy(&h, host + 3 + i * sizeof(h), sizeof(h));
                memcpy(&g, output + 1 + i * sizeof(g), sizeof(g));
                CHECK(sameFloat(g, (float)h));
            }
            for(size_t i = 0; i < sizeof(host); ++i)
                if(i < 3 || i >= 3 + count * sizeof(double)) CHECK(host[i] == 0xa5);
            for(size_t i = 0; i < sizeof(output); ++i)
                if(i < 1 || i >= 1 + count * sizeof(float)) CHECK(output[i] == 0xa5);
        }
    }
    printf("float struct conversions: %s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
