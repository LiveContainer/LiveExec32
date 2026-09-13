.arm
.balign 4

// Preserve r0-r3 immediately below the caller's original stack so the C
// helper can walk Apple's packed ARM32 argument words, including r3/stack
// splits. The extra r4/lr pair keeps SP aligned across helper calls.
.global _LC32GuestForwardMessage
_LC32GuestForwardMessage:
    mov r12, #0
    b 1f

.global _LC32GuestForwardMessageStret
_LC32GuestForwardMessageStret:
    mov r12, #1
1:
    push {r0, r1, r2, r3}
    push {r4, lr}
    mov r4, r12
    add r0, sp, #8
    mov r1, r4
    bl _LC32GuestForwardingTarget
    cmp r0, #0
    beq 2f

    // Replace only self (r1 for stret), then tail-call the ordinary guest
    // dispatcher. All original explicit arguments and the caller LR survive.
    add r2, sp, #8
    str r0, [r2, r4, lsl #2]
    mov r12, r4
    pop {r4, lr}
    pop {r0, r1, r2, r3}
    cmp r12, #0
    bne _objc_msgSend_stret
    b _objc_msgSend
2:
    add r0, sp, #8
    mov r1, r4
    bl _LC32GuestForwardInvocation
    pop {r4, lr}
    add sp, sp, #16
    // Scalar, object, and soft-float result bits occupy r0/r1.
    bx lr
