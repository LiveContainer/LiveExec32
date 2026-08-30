#pragma once

#include <limits.h>

/*
 * Sandbox-compatible Darwin file-system syscall adapters.  Include
 * dynarmic_internal.h first for the guest integer aliases and Darwin types.
 */

int LC32CopyGuestCString(u32 guest_string, char output[PATH_MAX]);
int LC32GuestPathToHost(u32 guest_path, char output[PATH_MAX]);

int guest_link(u32 guest_source, u32 guest_destination);
int guest_chflags(u32 guest_path, u_int flags);
int guest_symlink(u32 guest_target, u32 guest_link_path);
int guest_mkfifo(u32 guest_path, mode_t mode);
int guest_rmdir(u32 guest_path);
int guest_utimes(u32 guest_path, u32 guest_times);
int guest_futimes(int fildes, u32 guest_times);
int guest_lchown(u32 guest_path, uid_t owner, gid_t group);
int guest_pathconf(u32 guest_path, int name);
int guest_truncate(u32 guest_path, off_t length);
int guest_shm_unlink(u32 guest_name);

ssize_t guest_getxattr(u32 guest_path, u32 guest_name,
                       u32 guest_value, size_t size,
                       u_int32_t position, int options);
ssize_t guest_fgetxattr(int fildes, u32 guest_name,
                        u32 guest_value, size_t size,
                        u_int32_t position, int options);
int guest_fsetxattr(int fildes, u32 guest_name,
                    u32 guest_value, size_t size,
                    u_int32_t position, int options);
int guest_removexattr(u32 guest_path, u32 guest_name, int options);
int guest_fremovexattr(int fildes, u32 guest_name, int options);
ssize_t guest_listxattr(u32 guest_path, u32 guest_name_buffer,
                        size_t size, int options);
ssize_t guest_flistxattr(int fildes, u32 guest_name_buffer,
                         size_t size, int options);

int guest_getgroups(int count, u32 guest_groups);
int guest_getlogin(u32 guest_name, u32 name_size);
int guest_poll(int syscall_number, u32 guest_descriptors,
               u32 descriptor_count, int timeout);
ssize_t guest_readv(int syscall_number, int fildes,
                    u32 guest_iov, int iov_count);
ssize_t guest_pwrite(int syscall_number, int fildes,
                     u32 guest_buffer, size_t byte_count,
                     off_t offset);
