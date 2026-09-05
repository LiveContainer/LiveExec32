#pragma once

/*
 * Private guest-system-call entry points used by DynarmicCallbacks32::CallSVC.
 * Include dynarmic_internal.h before this header so the guest integer aliases
 * and Darwin ABI types below are available.
 */

int guest_csops(pid_t pid, unsigned int ops, u32 guest_useraddr,
                size_t usersize);
int guest_csops_audittoken(pid_t pid, unsigned int ops,
                           u32 guest_useraddr, size_t usersize,
                           u32 guest_audit_token);
int guest_getrlimit(int resource, u32 guest_rlp);
u32 guest_mmap(u32 guest_addr, size_t len, int prot, int flags,
               int fildes, off_t offset);
int guest___sysctl(u32 guest_name, u_int namelen, u32 guest_oldp,
                   u32 guest_oldlenp, u32 guest_newp, size_t newlen);
int guest___sysctlbyname(u32 guest_name, u_int namelen, u32 guest_oldp,
                         u32 guest_oldlenp, u32 guest_newp, size_t newlen);
int guest_getattrlist(u32 guest_path, u32 guest_attr_list,
                      u32 guest_attr_buffer, size_t attr_buffer_size,
                      unsigned long options);
int guest_shm_open(u32 guest_name, int oflag, int mode);
int guest_pthread_getugid_np(u32 uid, u32 gid);

mach_msg_return_t guest_mach_msg_trap(
    u32 guest_msg, mach_msg_option_t option, mach_msg_size_t send_size,
    mach_msg_size_t receive_size, mach_port_t receive_name,
    mach_msg_timeout_t timeout, mach_port_t notify);

int guest_getdirentries64(int fd, u32 guest_buffer, u32 nbytes,
                          u32 guest_basep);
int guest_stat64(u32 guest_path, u32 guest_buffer);
int guest_fstat(int fildes, u32 guest_buffer);
int guest_lstat(u32 guest_path, u32 guest_buffer);
int guest_statfs64(u32 guest_path, u32 guest_buffer);
int guest_fstatfs64(int fildes, u32 guest_buffer);

int guest_bsdthread_register(u32 guest_thread_start,
                             u32 guest_workqueue_thread_start,
                             int pthread_size, u32 data,
                             int32_t data_size, off_t offset);
int guest_workq_open();
int guest_bsdthread_ctl(u32 command, u32 arg1, u32 arg2, u32 arg3);
int guest_workq_kernreturn(int options, u32 item, int arg2, int arg3);
LC32_DYNARMIC_HIDDEN int guest_kevent(
    int kqueue_descriptor, u32 guest_changes,
    int change_count, u32 guest_events, int event_count,
    u32 guest_timeout);
int guest_kevent_qos(int kqueue_descriptor, u32 guest_changes,
                     int change_count, u32 guest_events, int event_count,
                     u32 guest_data_out, u32 data_available,
                     unsigned int flags);

int guest_sandbox_ms(u32 guest_policy_name, int call, u32 guest_arg);
int guest_getentropy(u32 guest_buffer, u32 length);
int guest_bind(int socket, u32 guest_address, socklen_t address_length);
int guest_setsockopt(int socket, int level, int option, u32 guest_value,
                     socklen_t value_length);
int guest_getsockopt(int socket, int level, int option, u32 guest_value,
                     u32 guest_value_length);
int guest_getsockname(int socket, u32 guest_address,
                      u32 guest_address_length);
int guest_getpeername(int socket, u32 guest_address,
                      u32 guest_address_length);
int guest_accept(int syscall_number, int socket, u32 guest_address,
                 u32 guest_address_length);
ssize_t guest_recvfrom(int syscall_number, int socket, u32 guest_buffer,
                       size_t length, int flags, u32 guest_from,
                       u32 guest_from_length);
int guest_connect(int syscall_number, int socket, u32 guest_address,
                  socklen_t address_length);
LC32_DYNARMIC_HIDDEN int guest_socketpair(
    int domain, int type, int protocol, u32 guest_sockets);
int guest_gettimeofday(u32 guest_timeval, u32 guest_timezone);
int guest_rename(u32 guest_old_path, u32 guest_new_path);
ssize_t guest_sendto(int syscall_number, int socket, u32 guest_buffer,
                     size_t length, int flags, u32 guest_destination_address,
                     socklen_t destination_length);
LC32_DYNARMIC_HIDDEN ssize_t guest_sendmsg(
    int syscall_number, int socket,
    u32 guest_message_address, int flags);
int guest_select(int syscall_number, int descriptor_count,
                 u32 guest_read_set, u32 guest_write_set,
                 u32 guest_exception_set, u32 guest_timeout);

ssize_t guest_pread(int syscall_number, int fildes, u32 guest_buffer,
                    size_t byte_count, off_t offset);
ssize_t guest_read(int syscall_number, int fildes, u32 guest_buffer,
                   size_t byte_count);
ssize_t guest_write(int syscall_number, int fildes, u32 guest_buffer,
                    size_t byte_count);
ssize_t guest_writev(int syscall_number, int fildes, u32 guest_iov,
                     int iov_count);
LC32_DYNARMIC_HIDDEN int guest_close(
    int syscall_number, int fildes);
LC32_DYNARMIC_HIDDEN int guest_dup(int fildes);
LC32_DYNARMIC_HIDDEN int guest_dup2(
    int source, int destination);
int guest_open(int syscall_number, u32 guest_path, int oflag, int mode);
int guest_chdir(u32 guest_path);
int guest_fchdir(int fildes);
int guest_pthread_chdir(u32 guest_path);
int guest_pthread_fchdir(int fildes);
int guest_unlink(u32 guest_path);
int guest_chmod(u32 guest_path, mode_t mode);
int guest_chown(u32 guest_path, uid_t owner, gid_t group);
int guest_access(u32 guest_path, int mode);
int guest_mkdir(u32 guest_path, mode_t mode);
int guest_setxattr(u32 guest_path, u32 guest_name, u32 guest_value,
                   size_t size, u_int32_t position, int options);
int guest_sigaction(int signal, u32 guest_action, u32 guest_old_action);
int guest_sigprocmask(int how, u32 guest_set, u32 guest_old_set);
int guest_ioctl(int fildes, u32 request, u32 guest_arg);
int guest_pthread_sigmask(int how, u32 guest_set, u32 guest_old_set);
ssize_t guest_readlink(u32 guest_path, u32 guest_buffer, size_t buffer_size);
int guest_munmap(u32 guest_address, size_t length);
int guest_mprotect(u32 guest_address, size_t length, int protection);
int guest_fcntl(int fildes, int command, u32 guest_arg);
int guest_proc_info(int call_number, int pid, int flavor, uint64_t arg,
                    u32 guest_buffer, int buffer_size);

int guest_mach_timebase_info(u32 guest_info);
kern_return_t guest_host_create_mach_voucher_trap(
    mach_port_name_t host, u32 guest_recipes, int recipes_size,
    u32 guest_voucher);
kern_return_t guest_mach_voucher_extract_attr_recipe_trap(
    mach_port_name_t voucher, mach_voucher_attr_key_t key,
    u32 guest_recipe, u32 guest_recipe_size);
kern_return_t guest_mach_generate_activity_id(
    mach_port_name_t target, int count, u32 guest_activity_ids);
kern_return_t guest_mk_timer_cancel(mach_port_name_t timer,
                                    u32 guest_result_time);
kern_return_t guest__kernelrpc_mach_vm_allocate_trap(
    u32 target, u32 guest_address, mach_vm_size_t size, int flags);
kern_return_t guest__kernelrpc_mach_vm_purgable_control_trap(
    mach_port_name_t target, mach_vm_offset_t guest_address,
    vm_purgable_t control, u32 guest_state);
kern_return_t guest__kernelrpc_mach_port_construct_trap(
    mach_port_name_t target, u32 guest_options, u64 context, u32 guest_name);
kern_return_t guest__kernelrpc_mach_port_allocate_trap(
    mach_port_name_t target, mach_port_right_t right, u32 guest_name);
kern_return_t guest__kernelrpc_mach_vm_map_trap(
    mach_port_name_t target, u32 guest_address, mach_vm_size_t size,
    mach_vm_offset_t mask, int flags, vm_prot_t current_protection);
kern_return_t guest__kernelrpc_mach_vm_deallocate_trap(
    u32 target, vm_address_t address, mach_vm_size_t size);
int guest_abort_with_payload(u32 reason_namespace, u64 reason_code,
                             u32 guest_payload, u32 payload_size,
                             u32 guest_reason_string, u64 reason_flags);
int guest_mremap_encrypted(u32 start, u32 length, u32 cryptid,
                           u32 cpu_type, u32 cpu_subtype);
