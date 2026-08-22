.syntax unified
.thumb
.text

.globl _test_connect_nocancel
.thumb_func
_test_connect_nocancel:
    movw r12, #409
    svc #0x80
    bcc 1f
    push {r4, lr}
    mov r4, r0
    bl ___error
    str r4, [r0]
    movs r0, #0
    mvns r0, r0
    pop {r4, pc}
1:
    bx lr

.globl _test_select_nocancel
.thumb_func
_test_select_nocancel:
    mov r12, sp
    push {r4, lr}
    ldr r4, [r12]
    movw r12, #407
    svc #0x80
    bcc 2f
    mov r4, r0
    bl ___error
    str r4, [r0]
    movs r0, #0
    mvns r0, r0
2:
    pop {r4, pc}

.globl _test_sendto_nocancel
.thumb_func
_test_sendto_nocancel:
    mov r12, sp
    push {r4, r5, r6, lr}
    ldm r12, {r4, r5}
    movw r12, #413
    svc #0x80
    bcc 3f
    mov r6, r0
    bl ___error
    str r6, [r0]
    movs r0, #0
    mvns r0, r0
3:
    pop {r4, r5, r6, pc}
