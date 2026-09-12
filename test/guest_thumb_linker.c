#include <stdint.h>
#include <stdio.h>

static volatile uint32_t constructor_value;

__attribute__((constructor, noinline))
static void lc32_thumb_constructor(void) {
    constructor_value = UINT32_C(0x13579bdf);
}

__attribute__((noinline))
uint32_t lc32_thumb_callback(uint32_t value) {
    return value ^ UINT32_C(0xa5a55a5a);
}

/* Keep an actual data relocation and indirect call, even in optimized builds.
 * The audit checks this slot as well as the constructor's __mod_init_func slot. */
uint32_t (* volatile lc32_thumb_callback_pointer)(uint32_t) =
    lc32_thumb_callback;

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    const int constructor_ok = constructor_value == UINT32_C(0x13579bdf);
    printf("guest-thumb-constructor: %s\n", constructor_ok ? "PASS" : "FAIL");
    const uintptr_t pointer = (uintptr_t)lc32_thumb_callback_pointer;
    const int thumb_ok = (pointer & 1) != 0;
    printf("guest-thumb-data-pointer: %s (0x%lx)\n",
        thumb_ok ? "PASS" : "FAIL", (unsigned long)pointer);
    /* A lost Thumb bit would branch into Thumb code in ARM state. Report the
     * broken relocation safely instead of deliberately crashing this test. */
    const int callback_ok = thumb_ok &&
        lc32_thumb_callback_pointer(UINT32_C(0x12345678)) ==
            (UINT32_C(0x12345678) ^ UINT32_C(0xa5a55a5a));
    printf("guest-thumb-indirect-call: %s\n", callback_ok ? "PASS" : "FAIL");
    return !(constructor_ok && thumb_ok && callback_ok);
}
