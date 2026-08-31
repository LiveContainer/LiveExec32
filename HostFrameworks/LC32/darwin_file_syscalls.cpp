#include "dynarmic_internal.h"
#include "dynarmic_syscalls.h"
#include "darwin_file_syscalls.h"

#include <limits.h>
#include <poll.h>
#include <sys/uio.h>

namespace {

constexpr size_t LC32MaximumStagedIOBytes = 64 * 1024 * 1024;

int GuestPathToHost(u32 guest_path, char host_path[PATH_MAX]) {
    return LC32GuestPathToHost(guest_path, host_path);
}

int GuestName(u32 guest_name, char name[PATH_MAX]) {
    return LC32CopyGuestCString(guest_name, name);
}

bool HostPathIsWithin(const char *path, const std::string &root) {
    if (root == "/") {
        return path[0] == '/';
    }
    const size_t root_length = root.size();
    return strncmp(path, root.c_str(), root_length) == 0 &&
        (path[root_length] == '\0' || path[root_length] == '/');
}

bool RelativeSymlinkTargetStaysInMount(
        const char *target, const char *host_link_path) {
    const std::string *mount_root = nullptr;
    for (const std::string &candidate : sharedHandle.fs->hostmpVec) {
        if (HostPathIsWithin(host_link_path, candidate) &&
                (mount_root == nullptr ||
                 candidate.size() > mount_root->size())) {
            mount_root = &candidate;
        }
    }
    if (mount_root == nullptr) {
        return false;
    }

    const char *last_slash = strrchr(host_link_path, '/');
    if (last_slash == nullptr) {
        return false;
    }
    const size_t parent_length = last_slash == host_link_path
        ? 1
        : static_cast<size_t>(last_slash - host_link_path);
    std::string parent(host_link_path, parent_length);
    if (!HostPathIsWithin(parent.c_str(), *mount_root)) {
        return false;
    }

    size_t depth = 0;
    const char *suffix = parent.c_str() + mount_root->size();
    while (*suffix != '\0') {
        while (*suffix == '/') {
            ++suffix;
        }
        if (*suffix == '\0') {
            break;
        }
        ++depth;
        while (*suffix != '\0' && *suffix != '/') {
            ++suffix;
        }
    }

    const char *component = target;
    bool saw_named_component = false;
    while (*component != '\0') {
        while (*component == '/') {
            ++component;
        }
        const char *end = component;
        while (*end != '\0' && *end != '/') {
            ++end;
        }
        const size_t length = static_cast<size_t>(end - component);
        if (length == 2 && component[0] == '.' && component[1] == '.') {
            /* After following a named component, the kernel may have crossed
             * a symlink and `..` would no longer be lexical. Only permit the
             * common leading ../ run that can be bounded against the mount. */
            if (saw_named_component || depth == 0) {
                return false;
            }
            --depth;
        } else if (length != 0 &&
                !(length == 1 && component[0] == '.')) {
            saw_named_component = true;
            ++depth;
        }
        component = end;
    }
    return true;
}

int PrepareGuestTimevals(u32 guest_times, struct timeval host_times[2],
                         const struct timeval **host_times_pointer) {
    if (guest_times == 0) {
        *host_times_pointer = nullptr;
        return 0;
    }

    timeval_32 guest_values[2] = {};
    if (!read_guest_memory_with_permissions(
            guest_times, guest_values, sizeof(guest_values), PROT_READ)) {
        return EFAULT;
    }
    for (size_t index = 0; index < 2; ++index) {
        host_times[index].tv_sec = guest_values[index].tv_sec;
        host_times[index].tv_usec = guest_values[index].tv_usec;
    }
    *host_times_pointer = host_times;
    return 0;
}

template <typename Invoke>
ssize_t GuestXattrRead(u32 guest_value, size_t size, Invoke invoke) {
    const bool has_guest_buffer = guest_value != 0;
    if (has_guest_buffer && size > LC32MaximumStagedIOBytes) {
        return return_with_carry_direct(ENOMEM, true);
    }

    std::vector<char> value;
    try {
        if (has_guest_buffer && size != 0) {
            value.resize(size);
        }
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }

    /* A null pointer is Darwin's size-query form even when size is nonzero.
     * Conversely, preserve a non-null pointer for a zero-sized output so the
     * kernel does not mistake it for that query form. */
    char zero_size_buffer = 0;
    void *host_value = !has_guest_buffer
        ? nullptr
        : (value.empty() ? &zero_size_buffer : value.data());
    const ssize_t result = static_cast<ssize_t>(invoke(host_value, size));
    if (threadHandle.cpsr->hasCarry() || result <= 0) {
        return result;
    }
    if (!has_guest_buffer || size == 0) {
        return result;
    }
    if (static_cast<size_t>(result) > value.size() ||
            !write_guest_memory_with_permissions(
                guest_value, value.data(), static_cast<size_t>(result),
                PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
}

template <typename Invoke>
int GuestXattrWrite(u32 guest_value, size_t size, Invoke invoke) {
    if (guest_value == 0 && size != 0) {
        return return_with_carry_direct(EINVAL, true);
    }
    if (size > LC32MaximumStagedIOBytes) {
        return return_with_carry_direct(ENOMEM, true);
    }

    std::vector<char> value;
    try {
        if (size != 0) {
            value.resize(size);
        }
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }
    if (size != 0 && !read_guest_memory_with_permissions(
            guest_value, value.data(), size, PROT_READ)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return invoke(value.empty() ? nullptr : value.data(), size);
}

} // namespace

int LC32CopyGuestCString(u32 guest_string, char output[PATH_MAX]) {
    if (guest_string == 0 || output == nullptr) {
        return EFAULT;
    }

    size_t copied = 0;
    while (copied < PATH_MAX) {
        const u64 address = static_cast<u64>(guest_string) + copied;
        if (address > UINT32_MAX) {
            return EFAULT;
        }
        const size_t page_remaining =
            DYN_PAGE_SIZE - (address & DYN_PAGE_MASK);
        const size_t chunk_length = std::min(
            static_cast<size_t>(PATH_MAX) - copied, page_remaining);
        std::array<char, DYN_PAGE_SIZE> chunk = {};
        if (!read_guest_memory_with_permissions(
                address, chunk.data(), chunk_length, PROT_READ)) {
            return EFAULT;
        }
        const void *terminator = memchr(
            chunk.data(), '\0', chunk_length);
        const size_t content_length = terminator != nullptr
            ? static_cast<const char *>(terminator) - chunk.data()
            : chunk_length;
        memcpy(output + copied, chunk.data(), content_length);
        copied += content_length;
        if (terminator != nullptr) {
            output[copied] = '\0';
            return 0;
        }
    }
    return ENAMETOOLONG;
}

int LC32GuestPathToHost(u32 guest_path, char output[PATH_MAX]) {
    char copied_path[PATH_MAX];
    const int copy_error = LC32CopyGuestCString(
        guest_path, copied_path);
    if (copy_error != 0) {
        return copy_error;
    }
    if (copied_path[0] == '\0') {
        return ENOENT;
    }
    errno = 0;
    if (!sharedHandle.fs->pathGuestToHost(copied_path, output)) {
        return errno != 0 ? errno : EINVAL;
    }
    return 0;
}

int guest_link(u32 guest_source, u32 guest_destination) {
    char host_source[PATH_MAX];
    char host_destination[PATH_MAX];
    int error = GuestPathToHost(guest_source, host_source);
    if (error == 0) {
        error = GuestPathToHost(guest_destination, host_destination);
    }
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_link, host_source, host_destination, 0, 0, 0, 0, 0);
}

int guest_chflags(u32 guest_path, u32 flags) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_chflags, host_path, flags, 0, 0, 0, 0, 0);
}

int guest_symlink(u32 guest_target, u32 guest_link_path) {
    char copied_target[PATH_MAX];
    const int target_error = LC32CopyGuestCString(
        guest_target, copied_target);
    if (target_error != 0) {
        return return_with_carry_direct(target_error, true);
    }

    char host_link_path[PATH_MAX];
    const int link_error = GuestPathToHost(
        guest_link_path, host_link_path);
    if (link_error != 0) {
        return return_with_carry_direct(link_error, true);
    }

    char translated_target[PATH_MAX];
    const char *host_target = copied_target;
    if (copied_target[0] == '/') {
        errno = 0;
        if (!sharedHandle.fs->pathGuestToHost(
                copied_target, translated_target)) {
            return return_with_carry_direct(
                errno != 0 ? errno : EINVAL, true);
        }
        host_target = translated_target;
    } else if (!RelativeSymlinkTargetStaysInMount(
            copied_target, host_link_path)) {
        /* The host kernel resolves a relative link after LC32's path mapping.
         * Permit parent components while they stay within the selected mount,
         * but never let the raw host-relative target cross that boundary. */
        return return_with_carry_direct(EPERM, true);
    }
    return syscallRetCarry(
        SYS_symlink, host_target, host_link_path, 0, 0, 0, 0, 0);
}

int guest_mkfifo(u32 guest_path, mode_t mode) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_mkfifo, host_path, mode, 0, 0, 0, 0, 0);
}

int guest_rmdir(u32 guest_path) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_rmdir, host_path, 0, 0, 0, 0, 0, 0);
}

int guest_utimes(u32 guest_path, u32 guest_times) {
    char host_path[PATH_MAX];
    int error = GuestPathToHost(guest_path, host_path);
    struct timeval host_times[2] = {};
    const struct timeval *host_times_pointer = nullptr;
    if (error == 0) {
        error = PrepareGuestTimevals(
            guest_times, host_times, &host_times_pointer);
    }
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_utimes, host_path, host_times_pointer, 0, 0, 0, 0, 0);
}

int guest_futimes(int fildes, u32 guest_times) {
    struct timeval host_times[2] = {};
    const struct timeval *host_times_pointer = nullptr;
    const int error = PrepareGuestTimevals(
        guest_times, host_times, &host_times_pointer);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_futimes, fildes, host_times_pointer, 0, 0, 0, 0, 0);
}

int guest_lchown(u32 guest_path, uid_t owner, gid_t group) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_lchown, host_path, owner, group, 0, 0, 0, 0);
}

int guest_pathconf(u32 guest_path, int name) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_pathconf, host_path, name, 0, 0, 0, 0, 0);
}

int guest_truncate(u32 guest_path, off_t length) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_truncate, host_path, length, 0, 0, 0, 0, 0);
}

int guest_shm_unlink(u32 guest_name) {
    char name[PATH_MAX];
    const int error = GuestName(guest_name, name);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_shm_unlink, name, 0, 0, 0, 0, 0, 0);
}

ssize_t guest_getxattr(u32 guest_path, u32 guest_name,
        u32 guest_value, size_t size, u_int32_t position, int options) {
    char host_path[PATH_MAX];
    int error = GuestPathToHost(guest_path, host_path);
    char name[PATH_MAX];
    if (error == 0) {
        error = GuestName(guest_name, name);
    }
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    /* The armv7 iOS 10 ABI treats 0xffffffff as a legacy path-xattr
     * size query even when the caller supplied a non-null value pointer. */
    if (size == UINT32_MAX) {
        return GuestXattrRead(0, 0, [&](void *value, size_t length) {
            return syscallRetCarry(
                SYS_getxattr, host_path, name, value, length,
                position, options, 0);
        });
    }
    return GuestXattrRead(guest_value, size, [&](void *value, size_t length) {
        return syscallRetCarry(
            SYS_getxattr, host_path, name, value, length,
            position, options, 0);
    });
}

ssize_t guest_fgetxattr(int fildes, u32 guest_name,
        u32 guest_value, size_t size, u_int32_t position, int options) {
    char name[PATH_MAX];
    const int error = GuestName(guest_name, name);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return GuestXattrRead(guest_value, size, [&](void *value, size_t length) {
        return syscallRetCarry(
            SYS_fgetxattr, fildes, name, value, length,
            position, options, 0);
    });
}

int guest_fsetxattr(int fildes, u32 guest_name,
        u32 guest_value, size_t size, u_int32_t position, int options) {
    char name[PATH_MAX];
    const int error = GuestName(guest_name, name);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return GuestXattrWrite(guest_value, size,
        [&](const void *value, size_t length) {
            return syscallRetCarry(
                SYS_fsetxattr, fildes, name, value, length,
                position, options, 0);
        });
}

int guest_removexattr(u32 guest_path, u32 guest_name, int options) {
    char host_path[PATH_MAX];
    int error = GuestPathToHost(guest_path, host_path);
    char name[PATH_MAX];
    if (error == 0) {
        error = GuestName(guest_name, name);
    }
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_removexattr, host_path, name, options,
        0, 0, 0, 0);
}

int guest_fremovexattr(int fildes, u32 guest_name, int options) {
    char name[PATH_MAX];
    const int error = GuestName(guest_name, name);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return syscallRetCarry(
        SYS_fremovexattr, fildes, name, options,
        0, 0, 0, 0);
}

ssize_t guest_listxattr(u32 guest_path, u32 guest_name_buffer,
        size_t size, int options) {
    char host_path[PATH_MAX];
    const int error = GuestPathToHost(guest_path, host_path);
    if (error != 0) {
        return return_with_carry_direct(error, true);
    }
    return GuestXattrRead(
        guest_name_buffer, size, [&](void *value, size_t length) {
            return syscallRetCarry(
                SYS_listxattr, host_path, value, length, options,
                0, 0, 0);
        });
}

ssize_t guest_flistxattr(int fildes, u32 guest_name_buffer,
        size_t size, int options) {
    return GuestXattrRead(
        guest_name_buffer, size, [&](void *value, size_t length) {
            return syscallRetCarry(
                SYS_flistxattr, fildes, value, length, options,
                0, 0, 0);
        });
}

int guest_getgroups(int count, u32 guest_groups) {
    if (count < 0) {
        return return_with_carry_direct(EINVAL, true);
    }
    const int actual_count = syscallRetCarry(
        SYS_getgroups, 0, nullptr, 0, 0, 0, 0, 0);
    if (threadHandle.cpsr->hasCarry() || count == 0) {
        return actual_count;
    }
    if (count < actual_count) {
        return return_with_carry_direct(EINVAL, true);
    }
    if (actual_count == 0) {
        return return_with_carry_direct(0, false);
    }
    if (guest_groups == 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    std::vector<gid_t> groups;
    try {
        groups.resize(static_cast<size_t>(actual_count));
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }
    const int result = syscallRetCarry(
        SYS_getgroups, actual_count,
        groups.empty() ? nullptr : groups.data(), 0, 0, 0, 0, 0);
    if (threadHandle.cpsr->hasCarry() || result <= 0) {
        return result;
    }
    if (result > actual_count || !write_guest_memory_with_permissions(
            guest_groups, groups.data(),
            static_cast<size_t>(result) * sizeof(gid_t), PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
}

int guest_getlogin(u32 guest_name, u32 name_size) {
    const size_t capacity = std::min<size_t>(name_size, MAXLOGNAME);
    if (guest_name == 0 && capacity != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    std::array<char, MAXLOGNAME> name = {};
    const int result = syscallRetCarry(
        SYS_getlogin, name.data(), capacity, 0, 0, 0, 0, 0);
    if (threadHandle.cpsr->hasCarry()) {
        return result;
    }
    if (capacity != 0 && !write_guest_memory_with_permissions(
            guest_name, name.data(), capacity, PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
}

int guest_poll(int syscall_number, u32 guest_descriptors,
        u32 descriptor_count, int timeout) {
    if (descriptor_count > static_cast<u32>(OPEN_MAX)) {
        return return_with_carry_direct(EINVAL, true);
    }
    if (descriptor_count != 0 && guest_descriptors == 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    std::vector<pollfd> descriptors;
    try {
        descriptors.resize(descriptor_count);
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }
    const size_t byte_count = descriptors.size() * sizeof(pollfd);
    if (byte_count != 0 &&
            (!read_guest_memory_with_permissions(
                guest_descriptors, descriptors.data(), byte_count,
                PROT_READ) ||
             !guest_memory_range_has_permissions(
                guest_descriptors, byte_count, PROT_WRITE))) {
        return return_with_carry_direct(EFAULT, true);
    }

    const bool workqueue_may_block = timeout != 0 &&
        NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const int result = debugger_aware_host_wait(
        [&] {
            return syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_poll : syscall_number,
                descriptors.data(), descriptor_count, timeout,
                0, 0, 0, 0);
        },
        return_with_carry_direct(EINTR, true));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    if (!threadHandle.cpsr->hasCarry() && byte_count != 0 &&
            !write_guest_memory_with_permissions(
                guest_descriptors, descriptors.data(), byte_count,
                PROT_WRITE)) {
        return return_with_carry_direct(EFAULT, true);
    }
    return result;
}

ssize_t guest_readv(int syscall_number, int fildes,
        u32 guest_iov, int iov_count) {
    if (iov_count < 0 || iov_count > IOV_MAX) {
        return return_with_carry_direct(EINVAL, true);
    }
    if (iov_count != 0 && guest_iov == 0) {
        return return_with_carry_direct(EFAULT, true);
    }

    std::vector<iovec_32> guest_vectors;
    std::vector<std::vector<char>> buffers;
    std::vector<iovec> host_vectors;
    try {
        guest_vectors.resize(static_cast<size_t>(iov_count));
        buffers.resize(static_cast<size_t>(iov_count));
        host_vectors.resize(static_cast<size_t>(iov_count));
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }
    if (iov_count != 0 && !read_guest_memory_with_permissions(
            guest_iov, guest_vectors.data(),
            guest_vectors.size() * sizeof(iovec_32), PROT_READ)) {
        return return_with_carry_direct(EFAULT, true);
    }

    size_t total_length = 0;
    try {
        for (size_t index = 0; index < guest_vectors.size(); ++index) {
            const size_t length = guest_vectors[index].iov_len;
            if ((length != 0 &&
                    guest_vectors[index].guest_iov_base == 0) ||
                    length > static_cast<size_t>(INT32_MAX) - total_length) {
                return return_with_carry_direct(
                    length != 0 &&
                        guest_vectors[index].guest_iov_base == 0
                        ? EFAULT : EINVAL,
                    true);
            }
            total_length += length;
            if (total_length > LC32MaximumStagedIOBytes) {
                return return_with_carry_direct(ENOMEM, true);
            }
            if (length != 0 && !guest_memory_range_has_permissions(
                    guest_vectors[index].guest_iov_base,
                    length, PROT_WRITE)) {
                return return_with_carry_direct(EFAULT, true);
            }
            buffers[index].resize(length);
            host_vectors[index] = {
                .iov_base = buffers[index].empty()
                    ? nullptr : buffers[index].data(),
                .iov_len = length,
            };
        }
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }

    const bool workqueue_may_block = NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_readv : syscall_number,
                fildes, host_vectors.data(), iov_count,
                0, 0, 0, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    if (threadHandle.cpsr->hasCarry() || result <= 0) {
        return result;
    }

    size_t remaining = static_cast<size_t>(result);
    for (size_t index = 0;
            index < guest_vectors.size() && remaining != 0; ++index) {
        const size_t copied = std::min(
            remaining, buffers[index].size());
        if (copied != 0 && !write_guest_memory_with_permissions(
                guest_vectors[index].guest_iov_base,
                buffers[index].data(), copied, PROT_WRITE)) {
            return return_with_carry_direct(EFAULT, true);
        }
        remaining -= copied;
    }
    return result;
}

ssize_t guest_pwrite(int syscall_number, int fildes,
        u32 guest_buffer, size_t byte_count, off_t offset) {
    if (guest_buffer == 0 && byte_count != 0) {
        return return_with_carry_direct(EFAULT, true);
    }
    if (byte_count > static_cast<size_t>(INT32_MAX)) {
        return return_with_carry_direct(EINVAL, true);
    }
    if (byte_count > LC32MaximumStagedIOBytes) {
        return return_with_carry_direct(ENOMEM, true);
    }
    std::vector<char> buffer;
    try {
        buffer.resize(byte_count);
    } catch (const std::bad_alloc &) {
        return return_with_carry_direct(ENOMEM, true);
    }
    if (byte_count != 0 && !read_guest_memory_with_permissions(
            guest_buffer, buffer.data(), byte_count, PROT_READ)) {
        return return_with_carry_direct(EFAULT, true);
    }
    const bool workqueue_may_block = NativeGuestWorkqueueIsCurrent();
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockEnter();
    }
    const ssize_t result = debugger_aware_host_wait(
        [&] {
            return static_cast<ssize_t>(syscallRetCarry(
                NativeGuestThreadsEnabled()
                    ? SYS_pwrite : syscall_number,
                fildes, buffer.empty() ? nullptr : buffer.data(),
                byte_count, offset, 0, 0, 0));
        },
        static_cast<ssize_t>(
            return_with_carry_direct(EINTR, true)));
    if (workqueue_may_block) {
        NativeGuestWorkqueueHostBlockExit();
    }
    return result;
}
