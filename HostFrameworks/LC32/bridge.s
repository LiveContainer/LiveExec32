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

// Dummy function to set double registers
// When declaring it as C function, it generates unnecessary stack push-pops
.global _LC32GetDoubleRegisters
.global _LC32SetDoubleRegisters
_LC32GetDoubleRegisters:
_LC32SetDoubleRegisters:
    ret
