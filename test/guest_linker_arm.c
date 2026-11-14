#include <stdint.h>

__attribute__((noinline))
uint32_t lc32_arm_callback(uint32_t value) { return value + 13; }

uint32_t (*volatile lc32_arm_callback_pointer)(uint32_t) = lc32_arm_callback;

// Called from Thumb code, then makes the reverse ARM-to-Thumb call.
__attribute__((noinline))
uint32_t lc32_arm_call(uint32_t (*callback)(uint32_t), uint32_t value) {
    return callback(value) + 17;
}
