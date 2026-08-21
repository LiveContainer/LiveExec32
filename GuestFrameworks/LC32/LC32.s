.arm
.balign 4

// Invoke a guest block from a serialized callback descriptor. All currently
// supported block values use the AAPCS32 core-register class. The C bridge has
// already serialized them in Apple's ARM32 ABI word order. words[0] is the
// guest block literal, followed by its explicit argument words.
.global _LC32InvokeGuestBlockWords
_LC32InvokeGuestBlockWords:
    push {r4, r5, r6, r7, r8, lr}
    mov r4, r0
    mov r5, r1
    mov r6, r2
    mov r8, sp

    cmp r6, #1
    blo 3f
    cmp r6, #16
    bhi 3f

    cmp r6, #4
    ble 2f
    sub r7, r6, #4
    // Keep SP eight-byte aligned at the indirect call boundary.
    add r3, r7, #1
    bic r3, r3, #1
    sub sp, sp, r3, lsl #2
    add r2, r5, #16
    mov r1, sp
1:
    ldr r0, [r2], #4
    str r0, [r1], #4
    subs r7, r7, #1
    bne 1b

2:
    mov r0, #0
    mov r1, #0
    mov r2, #0
    mov r3, #0
    cmp r6, #1
    ldrge r0, [r5]
    cmp r6, #2
    ldrge r1, [r5, #4]
    cmp r6, #3
    ldrge r2, [r5, #8]
    cmp r6, #4
    ldrge r3, [r5, #12]
    blx r4
    mov sp, r8
    pop {r4, r5, r6, r7, r8, pc}

3:
    mov r0, #0
    mov r1, #0
    mov sp, r8
    pop {r4, r5, r6, r7, r8, pc}

.global _LC32Dlsym
_LC32Dlsym:
    movw r12, #1001
    svc #0x80
    bx lr

.global _LC32InvokeHostCRet32
_LC32InvokeHostCRet32:
    movw r12, #1002
    svc #0x80
    bx lr

.global _LC32GuestToHostCString
_LC32GuestToHostCString:
    movw r12, #1003
    svc #0x80
    bx lr

.global _LC32GuestToHostCStringFree
_LC32GuestToHostCStringFree:
    movw r12, #1004
    svc #0x80
    bx lr

.global _LC32GetHostSelector
_LC32GetHostSelector:
    movw r12, #1005
    svc #0x80
    bx lr

.global _LC32InvokeHostSelector
_LC32InvokeHostSelector:
    movw r12, #1006
    svc #0x80
    bx lr

// Typed +0 object-return alias for SVC 1006.  A uint64_t selector occupies
// r2-r3; bit 30 of its high word is bit 62 of the full selector value.
.global _LC32InvokeHostObjectSelector
_LC32InvokeHostObjectSelector:
    orr r3, r3, #0x40000000
    movw r12, #1006
    svc #0x80
    bx lr

.global _LC32CopyHostCString
_LC32CopyHostCString:
    movw r12, #1020
    svc #0x80
    bx lr

.global _LC32GetHostObject
_LC32GetHostObject:
    movw r12, #1007
    svc #0x80
    bx lr

.global _LC32HostToGuestCopyClassName
_LC32HostToGuestCopyClassName:
    movw r12, #1008
    svc #0x80
    bx lr

.global _LC32InvokeGuestC
_LC32InvokeGuestC:
    blx r12
    movw r12, #1009
    svc #0x80
    bkpt

.global _LC32InvokeHostNSStringFormat
_LC32InvokeHostNSStringFormat:
    movw r12, #1010
    svc #0x80
    bx lr

.global _LC32CopyHostStringUTF8
_LC32CopyHostStringUTF8:
    movw r12, #1011
    svc #0x80
    bx lr

.global _LC32CopyHostDataBytes
_LC32CopyHostDataBytes:
    movw r12, #1012
    svc #0x80
    bx lr

.global _LC32CopyHostStringBytes
_LC32CopyHostStringBytes:
    movw r12, #1013
    svc #0x80
    bx lr

.global _LC32HostStringRangeOfString
_LC32HostStringRangeOfString:
    movw r12, #1014
    svc #0x80
    bx lr

.global _LC32CreateHostBlock
_LC32CreateHostBlock:
    movw r12, #1015
    svc #0x80
    bx lr

.global _LC32GuestObjectForOwnedHostObjectAddress
_LC32GuestObjectForOwnedHostObjectAddress:
    movw r12, #1016
    svc #0x80
    bx lr

.global _LC32GuestCallbackExecutorWait
_LC32GuestCallbackExecutorWait:
    movw r12, #1017
    svc #0x80
    bx lr

.global _LC32GuestCallbackExecutorComplete
_LC32GuestCallbackExecutorComplete:
    movw r12, #1018
    svc #0x80
    bx lr

.global _LC32TryRetainHostWeakReference
_LC32TryRetainHostWeakReference:
    movw r12, #1019
    svc #0x80
    bx lr

.global _LC32FinishHostWeakRetain
_LC32FinishHostWeakRetain:
    movw r12, #1021
    svc #0x80
    bx lr
