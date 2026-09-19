#pragma once

#include <mach/message.h>

/* The caller owns a buffer of MAX(sendSize, receiveSize, sizeof(header))
 * bytes and completes reply-port/message-ID bookkeeping after this call. */
bool HandleGuestSimpleMachMessage(
    mach_msg_header_t *message, mach_msg_size_t sendSize,
    mach_msg_size_t receiveSize, mach_msg_bits_t requestBits,
    mach_msg_return_t *result);

/* Guest exception delivery is not implemented. Reject optional crash-handler
 * registration with a MIG error, without altering the native task's ports. */
bool HandleGuestExceptionPortMessage(
    mach_msg_header_t *message, mach_msg_size_t sendSize,
    mach_msg_size_t receiveSize, mach_msg_bits_t requestBits,
    mach_msg_return_t *result);
