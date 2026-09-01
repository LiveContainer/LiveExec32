// Objective-C doesn't provide objc_msgSend(Super)_stret since arm64 has a builtin x8 register dedicated for returning struct
// However, we need to set x8 to an address located in guest heap
// We will be using x0 to store a pointer to struct containing indirect return address and the original x0
.text
.align 4

.global _LC32_objc_msgSend_stret
_LC32_objc_msgSend_stret:
    ldp x8, x0, [x0]
    b _objc_msgSend

.global _LC32_objc_msgSendSuper_stret
_LC32_objc_msgSendSuper_stret:
    ldp x8, x0, [x0]
    b _objc_msgSendSuper

// Invoke objc_msgSend or objc_msgSendSuper with independently marshalled
// integer and floating-point argument banks. The C bridge cannot safely seed
// d0-d7 with a dummy call: any bookkeeping between that call and objc_msgSend
// may legally clobber those caller-saved registers. This trampoline loads the
// integer registers and stack arguments first, restores d0-d7 last, and then
// makes the native call.
//
// LC32HostMessageInvocation layout:
//   0   invokeSuper
//   8   target
//   16  selector
//   24  integerArguments[9]
//   96  floatingArguments[8]
.global _LC32InvokeHostMessageInteger
.global _LC32InvokeHostMessageFloat
.global _LC32InvokeHostMessageDouble
.global _LC32InvokeHostMessageTwoDoubles
.global _LC32InvokeHostMessageTwoU64
.global _LC32InvokeHostMessageFourDoubles
.global _LC32InvokeHostMessageSixDoubles
_LC32InvokeHostMessageInteger:
_LC32InvokeHostMessageFloat:
_LC32InvokeHostMessageDouble:
_LC32InvokeHostMessageTwoDoubles:
_LC32InvokeHostMessageTwoU64:
_LC32InvokeHostMessageFourDoubles:
_LC32InvokeHostMessageSixDoubles:
    .cfi_startproc
    stp x29, x30, [sp, #-16]!
    .cfi_def_cfa_offset 16
    .cfi_offset x29, -16
    .cfi_offset x30, -8
    mov x29, sp
    .cfi_def_cfa_register x29
    sub sp, sp, #32

    mov x10, x0
    ldr w14, [x10]
    ldr x0, [x10, #8]
    ldr x1, [x10, #16]
    ldp x2, x3, [x10, #24]
    ldp x4, x5, [x10, #40]
    ldp x6, x7, [x10, #56]
    ldp x11, x12, [x10, #72]
    ldr x13, [x10, #88]
    stp x11, x12, [sp]
    str x13, [sp, #16]

    ldp d0, d1, [x10, #96]
    ldp d2, d3, [x10, #112]
    ldp d4, d5, [x10, #128]
    ldp d6, d7, [x10, #144]
    cbnz w14, 1f
    bl _objc_msgSend
    b 2f
1:
    bl _objc_msgSendSuper
2:

    add sp, sp, #32
    ldp x29, x30, [sp], #16
    .cfi_def_cfa sp, 0
    ret
    .cfi_endproc
