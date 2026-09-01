#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#define DYN_PAGE_BITS 12
#include "guest_memory_hash.h"

KHASH_INIT(guest_page, khint64_t, uintptr_t, 1,
    LC32GuestPageAddressHash, kh_int64_hash_equal)
KHASH_INIT(aligned_address, khint64_t, uintptr_t, 1,
    kh_int64_hash_func, kh_int64_hash_equal)

namespace {

constexpr khint64_t PageSize =
    UINT64_C(1) << DYN_PAGE_BITS;
constexpr khint64_t FirstPage = UINT64_C(0x30000000);
constexpr khint_t PageCount = 4096;
constexpr khint_t BucketCount = 8192;

template <typename Table, typename Hash>
size_t ProbeCount(
        const Table *table, khint64_t key, Hash hash) {
    const khint_t mask = table->n_buckets - 1;
    khint_t iterator = hash(key) & mask;
    const khint_t first = iterator;
    khint_t step = 0;
    size_t probes = 1;
    while (!__ac_isempty(table->flags, iterator) &&
            (__ac_isdel(table->flags, iterator) ||
                !kh_int64_hash_equal(
                    table->keys[iterator], key))) {
        iterator = (iterator + (++step)) & mask;
        ++probes;
        if (iterator == first) {
            break;
        }
    }
    return probes;
}

template <typename Lookup>
double BenchmarkLookups(Lookup lookup, size_t iterations) {
    volatile uintptr_t checksum = 0;
    const auto start = std::chrono::steady_clock::now();
    for (size_t iteration = 0; iteration < iterations; ++iteration) {
        for (khint_t index = 0; index < PageCount; ++index) {
            checksum = checksum ^ lookup(
                FirstPage +
                    static_cast<khint64_t>(index) * PageSize);
        }
    }
    const auto elapsed = std::chrono::steady_clock::now() - start;
    if (checksum == UINTPTR_MAX) {
        std::abort();
    }
    return std::chrono::duration<double, std::nano>(elapsed).count() /
        static_cast<double>(iterations * PageCount);
}

}  // namespace

int main() {
    kh_guest_page_t *pages = kh_init(guest_page);
    kh_aligned_address_t *oldPages = kh_init(aligned_address);
    if (pages == nullptr || oldPages == nullptr ||
            kh_resize(guest_page, pages, BucketCount) != 0 ||
            kh_resize(aligned_address, oldPages, BucketCount) != 0) {
        return 1;
    }

    for (khint_t index = 0; index < PageCount; ++index) {
        const khint64_t key =
            FirstPage + static_cast<khint64_t>(index) * PageSize;
        int newResult = 0;
        int oldResult = 0;
        const khint_t newIterator =
            kh_put(guest_page, pages, key, &newResult);
        const khint_t oldIterator =
            kh_put(aligned_address, oldPages, key, &oldResult);
        if (newResult <= 0 || oldResult <= 0 ||
                newIterator == kh_end(pages) ||
                oldIterator == kh_end(oldPages)) {
            return 1;
        }
        kh_value(pages, newIterator) =
            static_cast<uintptr_t>(index) + 1;
        kh_value(oldPages, oldIterator) =
            static_cast<uintptr_t>(index) + 1;
    }

    size_t newProbeTotal = 0;
    size_t oldProbeTotal = 0;
    size_t newMaximumProbes = 0;
    for (khint_t index = 0; index < PageCount; ++index) {
        const khint64_t key =
            FirstPage + static_cast<khint64_t>(index) * PageSize;
        const khint_t iterator =
            kh_get(guest_page, pages, key);
        if (iterator == kh_end(pages) ||
                kh_value(pages, iterator) !=
                    static_cast<uintptr_t>(index) + 1 ||
                kh_get(guest_page, pages, key + 1) !=
                    kh_end(pages)) {
            return 1;
        }
        const size_t newProbes = ProbeCount(
            pages, key, LC32GuestPageAddressHash);
        newProbeTotal += newProbes;
        oldProbeTotal += ProbeCount(
            oldPages, key,
            [](khint64_t address) {
                return kh_int64_hash_func(address);
            });
        newMaximumProbes =
            std::max(newMaximumProbes, newProbes);
    }

    if (newMaximumProbes > 16 ||
            newProbeTotal * 32 >= oldProbeTotal) {
        std::fprintf(stderr,
            "unexpected probe counts: old=%zu new=%zu max=%zu\n",
            oldProbeTotal, newProbeTotal,
            newMaximumProbes);
        return 1;
    }

    const double newNanoseconds = BenchmarkLookups(
        [pages](khint64_t key) {
            const khint_t iterator =
                kh_get(guest_page, pages, key);
            return kh_value(pages, iterator);
        }, 64);
    const double oldNanoseconds = BenchmarkLookups(
        [oldPages](khint64_t key) {
            const khint_t iterator =
                kh_get(aligned_address, oldPages, key);
            return kh_value(oldPages, iterator);
        }, 1);

    std::printf(
        "guest memory hash: PASS; probes %.2f -> %.2f, "
        "lookup %.1f ns -> %.1f ns\n",
        static_cast<double>(oldProbeTotal) / PageCount,
        static_cast<double>(newProbeTotal) / PageCount,
        oldNanoseconds, newNanoseconds);
    kh_destroy(guest_page, pages);
    kh_destroy(aligned_address, oldPages);
    return 0;
}
