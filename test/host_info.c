#include <mach/host_info.h>
#include <mach/mach.h>
#include <mach/machine.h>
#include <mach/vm_statistics.h>

#include <limits.h>
#include <stdio.h>

enum {
    kHostBasicInfoOldCount = 5,
    kHostInfoMaxCount = 68,
};

static const integer_t kCanary = (integer_t)0x5a5a5a5a;

static int report(const char *name, int passed) {
    printf("host-info-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

static void fill_canaries(integer_t *words, size_t count) {
    for (size_t index = 0; index < count; ++index) {
        words[index] = kCanary;
    }
}

static int canaries_unchanged(
        const integer_t *words, size_t begin, size_t end) {
    for (size_t index = begin; index < end; ++index) {
        if (words[index] != kCanary) {
            return 0;
        }
    }
    return 1;
}

static int basic_prefix_is_arm(const integer_t *words) {
    const host_basic_info_t basic = (host_basic_info_t)words;
    return basic->max_cpus >= 1 &&
        basic->avail_cpus >= 1 &&
        basic->avail_cpus <= basic->max_cpus &&
        basic->memory_size != 0 &&
        basic->cpu_type == CPU_TYPE_ARM &&
        basic->cpu_subtype == CPU_SUBTYPE_ARM_V7S;
}

static int test_basic_too_small(mach_port_t host) {
    for (mach_msg_type_number_t requested = 0;
            requested < kHostBasicInfoOldCount; ++requested) {
        integer_t words[kHostInfoMaxCount];
        fill_canaries(words, kHostInfoMaxCount);

        mach_msg_type_number_t count = requested;
        const kern_return_t result = host_info(
            host, HOST_BASIC_INFO, words, &count);
        if (result == KERN_SUCCESS || count != requested ||
                !canaries_unchanged(words, 0, kHostInfoMaxCount)) {
            return 0;
        }
    }
    return 1;
}

static int test_basic_legacy_counts(mach_port_t host) {
    for (mach_msg_type_number_t requested = kHostBasicInfoOldCount;
            requested < HOST_BASIC_INFO_COUNT; ++requested) {
        integer_t words[kHostInfoMaxCount];
        fill_canaries(words, kHostInfoMaxCount);

        mach_msg_type_number_t count = requested;
        const kern_return_t result = host_info(
            host, HOST_BASIC_INFO, words, &count);
        if (result != KERN_SUCCESS ||
                count != kHostBasicInfoOldCount ||
                !basic_prefix_is_arm(words) ||
                !canaries_unchanged(words, count, kHostInfoMaxCount)) {
            return 0;
        }
    }
    return 1;
}

static int test_basic_full_counts(
        mach_port_t host, host_basic_info_data_t *basicOut) {
    static const mach_msg_type_number_t requestedCounts[] = {
        HOST_BASIC_INFO_COUNT,
        HOST_BASIC_INFO_COUNT + 1,
        kHostInfoMaxCount,
    };

    for (size_t testIndex = 0;
            testIndex < sizeof(requestedCounts) /
                sizeof(requestedCounts[0]); ++testIndex) {
        integer_t words[kHostInfoMaxCount];
        fill_canaries(words, kHostInfoMaxCount);

        mach_msg_type_number_t count = requestedCounts[testIndex];
        const kern_return_t result = host_info(
            host, HOST_BASIC_INFO, words, &count);
        if (result != KERN_SUCCESS ||
                count != HOST_BASIC_INFO_COUNT ||
                !basic_prefix_is_arm(words) ||
                !canaries_unchanged(words, count, kHostInfoMaxCount)) {
            return 0;
        }

        const host_basic_info_t basic = (host_basic_info_t)words;
        if (basic->cpu_threadtype != CPU_THREADTYPE_NONE ||
                basic->physical_cpu < 1 ||
                basic->physical_cpu > basic->physical_cpu_max ||
                basic->logical_cpu < 1 ||
                basic->logical_cpu > basic->logical_cpu_max ||
                basic->max_mem < basic->memory_size) {
            return 0;
        }
        if (testIndex == 0) {
            *basicOut = *basic;
        }
    }
    return 1;
}

static int test_statistics_flavor(
        mach_port_t host, host_flavor_t flavor,
        mach_msg_type_number_t expectedCount) {
    integer_t words[kHostInfoMaxCount];
    fill_canaries(words, kHostInfoMaxCount);

    mach_msg_type_number_t count = expectedCount;
    const kern_return_t result = host_statistics(
        host, flavor, words, &count);
    return result == KERN_SUCCESS && count == expectedCount &&
        canaries_unchanged(words, count, kHostInfoMaxCount);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    const mach_port_t host = mach_host_self();
    if (!report("port", MACH_PORT_VALID(host))) {
        return 1;
    }

    const int basicTooSmallPassed = test_basic_too_small(host);
    const int basicLegacyPassed = test_basic_legacy_counts(host);
    host_basic_info_data_t basic = {};
    const int basicFullPassed = test_basic_full_counts(host, &basic);
    const int basicArchitecturePassed = basicFullPassed &&
        basic.cpu_type == CPU_TYPE_ARM &&
        basic.cpu_subtype == CPU_SUBTYPE_ARM_V7S &&
        basic.cpu_threadtype == CPU_THREADTYPE_NONE;
    const int basicResourcesPassed = basicFullPassed &&
        basic.max_cpus >= 1 && basic.avail_cpus >= 1 &&
        basic.physical_cpu >= 1 && basic.physical_cpu_max >= 1 &&
        basic.logical_cpu >= 1 && basic.logical_cpu_max >= 1 &&
        basic.memory_size != 0 && basic.max_mem >= basic.memory_size;

    integer_t vmWords[kHostInfoMaxCount];
    fill_canaries(vmWords, kHostInfoMaxCount);
    mach_msg_type_number_t vmCount = HOST_VM_INFO_COUNT;
    kern_return_t result = host_statistics(
        host, HOST_VM_INFO, vmWords, &vmCount);
    const vm_statistics_t vm = (vm_statistics_t)vmWords;
    const int vmStatisticsPassed = result == KERN_SUCCESS &&
        vmCount == HOST_VM_INFO_COUNT && vm->wire_count != 0 &&
        canaries_unchanged(vmWords, vmCount, kHostInfoMaxCount);
    const int loadStatisticsPassed = test_statistics_flavor(
        host, HOST_LOAD_INFO, HOST_LOAD_INFO_COUNT);
    const int cpuStatisticsPassed = test_statistics_flavor(
        host, HOST_CPU_LOAD_INFO, HOST_CPU_LOAD_INFO_COUNT);

    integer_t unknownStatistics[kHostInfoMaxCount];
    fill_canaries(unknownStatistics, kHostInfoMaxCount);
    mach_msg_type_number_t unknownStatisticsCount = kHostInfoMaxCount;
    result = host_statistics(
        host, INT_MAX, unknownStatistics, &unknownStatisticsCount);
    const int unknownStatisticsPassed = result != KERN_SUCCESS &&
        unknownStatisticsCount == kHostInfoMaxCount &&
        canaries_unchanged(
            unknownStatistics, 0, kHostInfoMaxCount);

    host_priority_info_data_t priority = {};
    mach_msg_type_number_t priorityCount = HOST_PRIORITY_INFO_COUNT;
    result = host_info(
        host, HOST_PRIORITY_INFO, (host_info_t)&priority,
        &priorityCount);
    const int priorityPassed =
        result == KERN_SUCCESS &&
        priorityCount == HOST_PRIORITY_INFO_COUNT &&
        priority.minimum_priority <= priority.user_priority &&
        priority.user_priority <= priority.maximum_priority;

    integer_t unknown[68] = {};
    mach_msg_type_number_t unknownCount =
        sizeof(unknown) / sizeof(unknown[0]);
    result = host_info(
        host, INT_MAX, unknown, &unknownCount);
    const int unknownPassed = result != KERN_SUCCESS;

    const int deallocatePassed = mach_port_deallocate(
        mach_task_self(), host) == KERN_SUCCESS;
    const int passed =
        report("basic-too-small", basicTooSmallPassed) &&
        report("basic-legacy-count", basicLegacyPassed) &&
        report("basic-full-count", basicFullPassed) &&
        report("basic-architecture", basicArchitecturePassed) &&
        report("basic-resources", basicResourcesPassed) &&
        report("statistics-vm", vmStatisticsPassed) &&
        report("statistics-load", loadStatisticsPassed) &&
        report("statistics-cpu", cpuStatisticsPassed) &&
        report("statistics-unknown-flavor", unknownStatisticsPassed) &&
        report("priority", priorityPassed) &&
        report("unknown-flavor", unknownPassed) &&
        report("deallocate", deallocatePassed);
    printf("host-info-regression: %s\n",
        passed ? "PASS" : "FAIL");
    return !passed;
}
