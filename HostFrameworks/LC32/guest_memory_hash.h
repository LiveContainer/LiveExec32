#pragma once

#include "khash.h"

#ifndef DYN_PAGE_BITS
#error "DYN_PAGE_BITS must be defined before guest_memory_hash.h"
#endif

/*
 * Memory-map keys remain guest byte addresses for exact equality, but their
 * low page-offset bits are always zero. Hash the page number with Wang's
 * mixer so both contiguous pages and sparse guest mappings use all buckets.
 */
static kh_inline khint_t LC32GuestPageAddressHash(
        khint64_t address) {
    return kh_int_hash_func2(
        static_cast<khint32_t>(
            address >> DYN_PAGE_BITS));
}
