#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <iostream>

#include <assert.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

#include <mach-o/getsect.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/reloc.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>

#include <dirent.h>
#include <dlfcn.h>
#include <signal.h>
#include <sys/attr.h>
#include <sys/errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/xattr.h>
#include <libgen.h>
#include "mach_private.h"
#include "codesign.h"
#include "dynarmic.h"
#include "32bit.h"


#define IGNORE_BAD_MEM_ACCESS 1
#define TRACE_RW 0
#define TRACE_BRANCH 0
#define TRACE_SVC 0
//#define TRACE_ALLOC 0
//#define fprintf(...)
//#define printf(...)

#define CS_OPS_STATUS 0
#define CS_ENFORCEMENT 0x00001000

#define msgh_request_port	msgh_remote_port
#define msgh_reply_port		msgh_local_port

struct symbolicated_call {
    u32 address;
    u32 symbolOffset;
    const char *symbolName;
    const char *imageName;
};

extern "C"
int return_with_carry(int result, bool carry) {
    threadHandle.cpsr->setCarry(carry);
    return carry ? errno : result;
}

extern "C"
int return_with_carry_direct(int result, bool carry) {
    threadHandle.cpsr->setCarry(carry);
    return result;
}

extern "C"
int syscallRetCarry(long syscall, ...);
__asm__(" \
_syscallRetCarry: \n \
    mov x16, x0 \n \
    ldp x0, x1, [sp] \n \
    ldp x2, x3, [sp, #0x10] \n \
    ldp x4, x5, [sp, #0x20] \n \
    ldr x6, [sp, #0x30] \n \
    svc #0x80 \n \
    mov x1, #0 \n \
    b.lo LcarryClear\n \
    mov x1, #1 \n \
LcarryClear: \n \
    b _return_with_carry_direct \n \
");

// guest syscalls
int guest_csops(pid_t pid, unsigned int ops, u32 guest_useraddr, size_t usersize) {
    char *host_useraddr = (char *)malloc(usersize);
    int result = syscallRetCarry(SYS_csops, pid, ops, host_useraddr, usersize, 0,0,0);
    if(ops == CS_OPS_STATUS) {
        // remove code signature enforcement
        *(uint32_t *)host_useraddr &= ~CS_ENFORCEMENT;
    }
    Dynarmic_mem_1write(guest_useraddr, usersize, host_useraddr);
    free(host_useraddr);
    return result;
}

int guest_getrlimit(int resource, u32 guest_rlp) {
    struct rlimit host_rlp;
    int result = syscallRetCarry(SYS_getrlimit, resource, &host_rlp, 0,0,0,0,0);
    Dynarmic_mem_1write(guest_rlp, sizeof(host_rlp), (char *)&host_rlp);
    return result;
}


u32 guest_mmap(u32 guest_addr, size_t len, int prot, int flags, int fildes, off_t offset) {
    len = ALIGN_DYN_SIZE(len);
    u32 result = Dynarmic_mmap(guest_addr, len, prot, flags, fildes, offset);
    if(result == -1) {
        threadHandle.cpsr->setCarry(true);
        return errno;
    }
    return result;
}

int guest___sysctl(u32 guest_name, u_int namelen, u32 guest_oldp, u32 guest_oldlenp, u32 guest_newp, size_t newlen) {
    // TODO: fake stuff like CPU architecture and KERN_USRSTACK32
    int host_name[0x10];
    assert(namelen < sizeof(host_name));
    Dynarmic_mem_1read(guest_name, sizeof(int) * namelen, (char *)host_name);

    // Guess nothing is larger than 1kb
    size_t host_oldlenp;
    char host_oldp[0x400];
    char host_newp[0x400];
    assert(newlen <= sizeof(host_newp));
    if(guest_newp) {
        Dynarmic_mem_1read(guest_newp, newlen, host_newp);
    }

    int result = syscallRetCarry(SYS_sysctl,
        host_name, namelen,
        guest_oldp ? &host_oldp : NULL,
        guest_oldlenp ? &host_oldlenp : 0,
        guest_newp ? (int *)host_newp : NULL, newlen,
        0
    );

    if(guest_oldp) {
        Dynarmic_mem_1write(guest_oldp, host_oldlenp, host_oldp);
        sharedHandle.ucb->MemoryWrite32(guest_oldlenp, host_oldlenp);
    }
    return result;
}

int guest___sysctlbyname(u32 guest_name, u_int namelen, u32 guest_oldp, u32 guest_oldlenp, u32 guest_newp, size_t newlen) {
    // TODO: fake stuff like CPU architecture and KERN_USRSTACK32
    DynarmicHostString host_name(guest_name);

    // Guess nothing is larger than 1kb
    size_t host_oldlenp;
    char host_oldp[0x400];
    char host_newp[0x400];
    assert(newlen <= sizeof(host_newp));
    if(guest_newp) {
        Dynarmic_mem_1read(guest_newp, newlen, host_newp);
    }

    int result = syscallRetCarry(SYS_sysctlbyname,
        host_name.hostPtr, namelen,
        guest_oldp ? &host_oldp : NULL,
        guest_oldlenp ? &host_oldlenp : 0,
        guest_newp ? (int *)host_newp : NULL, newlen,
        0
    );

    if(guest_oldp) {
        Dynarmic_mem_1write(guest_oldp, host_oldlenp, host_oldp);
        sharedHandle.ucb->MemoryWrite32(guest_oldlenp, host_oldlenp);
    }
    return result;
}

int guest_getattrlist(u32 guest_path, u32 guest_attrList, u32 guest_attrBuf, size_t attrBufSize, unsigned long options) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    struct attrlist host_attrList;
    Dynarmic_mem_1read(guest_attrList, sizeof(struct attrlist), (char *)&host_attrList);
    char *host_attrBuf = (char *)malloc(attrBufSize);
    int result = syscallRetCarry(SYS_getattrlist, host_path, &host_attrList, host_attrBuf, attrBufSize, options, 0,0);
    Dynarmic_mem_1write(guest_attrBuf, attrBufSize, host_attrBuf);
    free(host_attrBuf);
    return result;
}

int guest_shm_open(u32 guest_name, int oflag, int mode) {
    DynarmicHostString host_name(guest_name);
    printf("LC32: shm_open %s\n", host_name.hostPtr);
    return syscallRetCarry(SYS_shm_open, host_name.hostPtr, oflag, mode);
}

int	 guest_pthread_getugid_np(u32 uid, u32 gid) {
    uid_t host_uid, host_gid;
    int result = pthread_getugid_np(&host_uid, &host_gid);
    sharedHandle.ucb->MemoryWrite32(uid, host_uid);
    sharedHandle.ucb->MemoryWrite32(gid, host_gid);
    return result;
}

#define MACH_MSG_UNION(function, name) \
union MachMessage_##function { \
    __Request__##function##_t In; \
    __Reply__##function##_t Out; \
} *name = (MachMessage_##function *)host_header

// FIXME: cannot call mach_msg(2)_trap directly
mach_msg_return_t
guest_mach_msg_trap(u32 guest_msg,
		 mach_msg_option_t option,
		 mach_msg_size_t send_size,
		 mach_msg_size_t rcv_size,
		 mach_port_t rcv_name,
		 mach_msg_timeout_t timeout,
		 mach_port_t notify) {
    mach_msg_return_t result = MACH_MSG_SUCCESS;

    char *host_msg = (char *)malloc(MAX(send_size, rcv_size));
    Dynarmic_mem_1read(guest_msg, send_size, host_msg);

    mach_msg_header_t *host_header = (mach_msg_header_t *)host_msg;
    printf("LC32: mach_msg_trap id %d\n", host_header->msgh_id);

    // pre-process reply header
    host_header->msgh_bits &= 0xff;
    switch(host_header->msgh_id) {
        case 0: {
            result = MACH_SEND_INVALID_HEADER; // TODO
            break;
        }
        case 200: {
            MACH_MSG_UNION(host_info, Mess);
            if(Mess->In.flavor == HOST_PRIORITY_INFO) {
                result = host_info(Mess->In.Head.msgh_request_port, Mess->In.flavor, (host_info_t)Mess->Out.host_info_out, &Mess->Out.host_info_outCnt);
                host_header->msgh_size = sizeof(Mess->Out) - sizeof(Mess->Out.host_info_out) + sizeof(Mess->Out.host_info_out[0])*Mess->Out.host_info_outCnt;
                Mess->Out.RetCode = result;
            } else {
                printf("LC32: Unhandled flavor %d\n", Mess->In.flavor);
                sharedHandle.ucb->ExceptionRaised(0xDEADDEAD, Dynarmic::A32::Exception::Yield);
            }
            break;
        }
        case 206: {
            MACH_MSG_UNION(host_get_clock_service, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = host_get_clock_service(Mess->In.Head.msgh_request_port, Mess->In.clock_id, &Mess->Out.clock_serv.name);
            Mess->Out.clock_serv.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.clock_serv.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 412: {
            MACH_MSG_UNION(host_get_special_port, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = host_get_special_port(Mess->In.Head.msgh_request_port, Mess->In.node, Mess->In.which, &Mess->Out.port.name);
            Mess->Out.port.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.port.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case DYLD_PROCESS_INFO_NOTIFY_LOAD_ID: {
            const dyld_process_info_notify_header *Mess = (dyld_process_info_notify_header *)host_header;
            const dyld_process_info_image_entry* entries = (dyld_process_info_image_entry*)((uintptr_t)Mess + Mess->imagesOffset);
            uintptr_t stringPool = (uintptr_t)Mess + Mess->stringsOffset;
            for(unsigned i=0; i < Mess->imageCount; ++i) {
                u32 imageAddress = entries[i].loadAddress;
                char *imagePath = (char *)(stringPool + entries[i].pathStringOffset);
                // Find __TEXT size
                struct segment_command *seg = (struct segment_command *)((uintptr_t)get_memory(imageAddress) + sizeof(struct mach_header));
                while(seg->cmd != LC_SEGMENT || strcmp(seg->segname, SEG_TEXT) != 0){
                    seg = (struct segment_command *)((uintptr_t)seg + seg->cmdsize);
                }
                guestMappings[guestMappingLen].name = strdup(basename(imagePath));
                guestMappings[guestMappingLen].start = imageAddress;
                guestMappings[guestMappingLen].end = imageAddress + seg->vmsize;
                guestMappings[guestMappingLen].hostAddr = (uintptr_t)get_memory(imageAddress);
                printf("LC32: added image %s (0x%08x-0x%08x)\n", guestMappings[guestMappingLen].name, guestMappings[guestMappingLen].start, guestMappings[guestMappingLen].end);
                guestMappingLen++;
            }
            __attribute__((fallthrough));
        }
        case DYLD_PROCESS_INFO_NOTIFY_UNLOAD_ID:
        case DYLD_PROCESS_INFO_NOTIFY_MAIN_ID: {
            host_header->msgh_bits        = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND);
            host_header->msgh_id          = 0;
            host_header->msgh_local_port  = MACH_PORT_NULL;
            host_header->msgh_reserved    = 0;
            host_header->msgh_size        = sizeof(*host_header);
            break;
        }
        case 3409: {
            MACH_MSG_UNION(task_get_special_port, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = task_get_special_port(Mess->In.Head.msgh_request_port, Mess->In.which_port, &Mess->Out.special_port.name);
            Mess->Out.special_port.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.special_port.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 3410: {
            MACH_MSG_UNION(task_set_special_port, Mess);
            Mess->Out.RetCode = task_set_special_port(Mess->In.Head.msgh_request_port, Mess->In.which_port, Mess->In.special_port.name);
            break;
        }
        case 3418: {
            MACH_MSG_UNION(semaphore_create, Mess);
            host_header->msgh_bits |= MACH_MSGH_BITS_COMPLEX;
            host_header->msgh_size = sizeof(Mess->Out);
            result = semaphore_create(Mess->In.Head.msgh_request_port, &Mess->Out.semaphore.name, Mess->In.policy, Mess->In.value);
            Mess->Out.semaphore.type = MACH_MSG_PORT_DESCRIPTOR;
            Mess->Out.semaphore.disposition = 17;
            Mess->Out.msgh_body.msgh_descriptor_count = 1;
            break;
        }
        case 3444: {
            MACH_MSG_UNION(task_register_dyld_image_infos, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.RetCode = KERN_SUCCESS;
            break;
        }
        case 3447: {
            MACH_MSG_UNION(task_register_dyld_shared_cache_image_info, Mess);
            host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.RetCode = KERN_SUCCESS;
            break;
        }
        case 78945670: {
            MACH_MSG_UNION(_notify_server_register_check, Mess);
            // this Mach trap is missing on arm64
	         host_header->msgh_size = sizeof(Mess->Out);
            Mess->Out.size = 0;
            Mess->Out.slot = 0;
            Mess->Out.token = 0;
            Mess->Out.status = 0;
            Mess->Out.RetCode = 0;
            break;
        }
        case 0x10000000: {
            // _xpc_send_serializer: we can pass directly
            result = mach_msg_send(host_header);
            // this function does not modify the message buffer, return directly
            free(host_msg);
            return result;
        }
        default:
            printf("LC32: Unhandled msgh_id\n");
            sharedHandle.ucb->ExceptionRaised(0xDEADDEAD, Dynarmic::A32::Exception::Yield);
            break;
    }

    host_header->msgh_reply_port = rcv_name;
    host_header->msgh_request_port = 0;
    host_header->msgh_id += 100; // reply Id always equals reqId+100

    Dynarmic_mem_1write(guest_msg, rcv_size, host_msg);
    free(host_msg);
    return result;
}

int guest_getdirentries64(int fd, u32 guest_buf, int nbytes, u32 guest_basep) {
    char *host_buf = (char *)malloc(nbytes);
    __darwin_off_t host_basep = (__darwin_off_t)sharedHandle.ucb->MemoryRead32(guest_basep); // is reading needed?
    // FIXME: is this correct?
    int result = syscallRetCarry(SYS_getdirentries64, fd, host_buf, nbytes, &host_basep, 0,0,0);
    Dynarmic_mem_1write(guest_buf, nbytes, host_buf);
    sharedHandle.ucb->MemoryWrite64(guest_basep, host_basep);
    free(host_buf);
    return result;
}

void guest_stat_copy(struct stat *host_buf, struct stat_32 *host_buf_32) {
    host_buf_32->st_dev = host_buf->st_dev;
    host_buf_32->st_mode = host_buf->st_mode;
    host_buf_32->st_nlink = host_buf->st_nlink;
    host_buf_32->st_ino = host_buf->st_ino;
    host_buf_32->st_uid = host_buf->st_uid;
    host_buf_32->st_gid = host_buf->st_gid;
    host_buf_32->st_rdev = host_buf->st_rdev;

    // Y2038???
    host_buf_32->st_atimespec.tv_sec = host_buf->st_atimespec.tv_sec;
    host_buf_32->st_atimespec.tv_nsec = host_buf->st_atimespec.tv_nsec;
    host_buf_32->st_mtimespec.tv_sec = host_buf->st_mtimespec.tv_sec;
    host_buf_32->st_mtimespec.tv_nsec = host_buf->st_mtimespec.tv_nsec;
    host_buf_32->st_ctimespec.tv_sec = host_buf->st_ctimespec.tv_sec;
    host_buf_32->st_ctimespec.tv_nsec = host_buf->st_ctimespec.tv_nsec;
    host_buf_32->st_birthtimespec.tv_sec = host_buf->st_birthtimespec.tv_sec;
    host_buf_32->st_birthtimespec.tv_nsec = host_buf->st_birthtimespec.tv_nsec;

    host_buf_32->st_size = host_buf->st_size;
    host_buf_32->st_blocks = host_buf->st_blocks;
    host_buf_32->st_blksize = host_buf->st_blksize;
    host_buf_32->st_flags = host_buf->st_flags;
    host_buf_32->st_gen = host_buf->st_gen;
    host_buf_32->st_lspare = host_buf->st_lspare;
    host_buf_32->st_qspare[0] = host_buf->st_qspare[0];
    host_buf_32->st_qspare[1] = host_buf->st_qspare[1];
}

int guest_stat64(u32 guest_path, u32 guest_buf) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    struct stat host_buf;
    struct stat_32 host_buf_32;
    int result = stat(host_path, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_fstat(int fildes, u32 guest_buf) {
    struct stat host_buf;
    struct stat_32 host_buf_32;
    int result = fstat(fildes, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_lstat(u32 guest_path, u32 guest_buf) {
    struct stat host_buf;
    struct stat_32 host_buf_32;
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    int result = lstat(host_path, &host_buf);
    if(result == 0) {
        guest_stat_copy(&host_buf, &host_buf_32);
        Dynarmic_mem_1write(guest_buf, sizeof(struct stat_32), (char *)&host_buf_32);
    }
    return return_with_carry(result, result != 0);
}

int guest_statfs64(u32 guest_path, u32 guest_buf) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    struct statfs host_buf;
    int result = syscallRetCarry(SYS_statfs, host_path, &host_buf, 0,0,0,0,0);
    if(result == 0) {
        Dynarmic_mem_1write(guest_buf, sizeof(struct statfs), (char *)&host_buf);
    }
    return result;
}

int guest_fstatfs64(int fildes, u32 guest_buf) {
    struct statfs host_buf;
    int result = syscallRetCarry(SYS_fstatfs, fildes, &host_buf, 0,0,0,0,0);
    if(result == 0) {
        Dynarmic_mem_1write(guest_buf, sizeof(struct statfs), (char *)&host_buf);
    }
    return result;
}

u32 guest_bsdthread_thread_start;
int guest_bsdthread_pthread_size;
int guest_bsdthread_register(u32 guest_func_thread_start, u32 guest_func_start_wqthread, int pthread_size, u32 data, int32_t datasize, off_t offset) {
    guest_bsdthread_thread_start = guest_func_thread_start;
    guest_bsdthread_pthread_size = pthread_size;
    return return_with_carry(PTHREAD_FEATURE_FINEPRIO | PTHREAD_FEATURE_BSDTHREADCTL | PTHREAD_FEATURE_SETSELF | PTHREAD_FEATURE_QOS_MAINTENANCE | PTHREAD_FEATURE_QOS_DEFAULT, false);
}

int guest_sandbox_ms(u32 guest_policyname, int call, u32 guest_arg) {
    // TODO: ???
    char host_policyname[0x20];
    Dynarmic_mem_1read(guest_policyname, sizeof(host_policyname), host_policyname);
    printf("sandbox(%s, %d)\n", host_policyname, call);
    return 0;
}

int guest_getentropy(u32 guest_buffer, u32 length) {
    char *host_buffer = (char *)malloc(length);
    int result = syscallRetCarry(SYS_getentropy, (void *)host_buffer, length, 0,0,0,0,0);
    Dynarmic_mem_1write(guest_buffer, length, host_buffer);
    free(host_buffer);
    return result;
}

int guest_connect(int socket, u32 guest_address, socklen_t address_len) {
    // See https://developer.apple.com/forums/thread/756756?answerId=790507022#790507022
    // sockaddr_un.sun_path has an artificial limit is 104 bytes, however it allows up to 253 bytes
    if(address_len > SOCK_MAXADDRLEN) {
        return return_with_carry_direct(EINVAL, true);
    }
    char host_address[SOCK_MAXADDRLEN];
    Dynarmic_mem_1read(guest_address, address_len, host_address);

    int type;
    socklen_t length = sizeof(int);
    getsockopt(socket, SOL_SOCKET, SO_TYPE, &type, &length);
    if(type == SOCK_DGRAM) {
        char host_path[PATH_MAX];
        sockaddr_un *sock = (sockaddr_un *)host_address;
        sharedHandle.fs->pathGuestToHost(sock->sun_path, host_path);
        if(strlen(host_path) > SOCK_MAXADDRLEN - offsetof(sockaddr_un, sun_path)) {
            return return_with_carry_direct(EINVAL, true);
        }
        strcpy(sock->sun_path, host_path);
        address_len = SUN_LEN(sock);
    }

    return syscallRetCarry(SYS_connect, socket, (const sockaddr *)host_address, address_len, 0,0,0,0);
}

int guest_gettimeofday(u32 guest_tp, u32 guest_tzp) {
    // tzp is always null since it's no longer used
    //assert(!guest_tzp);
    struct timeval host_tp;
    int result = syscallRetCarry(SYS_gettimeofday, &host_tp, NULL, 0,0,0,0,0);
    Dynarmic_mem_1write(guest_tp, sizeof(host_tp), (char *)&host_tp);
    return result;
}

int guest_rename(u32 guest_old, u32 guest_new) {
    char host_old[PATH_MAX], host_new[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_old, host_old);
    sharedHandle.fs->pathGuestToHost(guest_new, host_new);
    return syscallRetCarry(SYS_rename, host_old, host_new, 0,0,0,0,0);
}

ssize_t guest_sendto(int socket, const u32 guest_buffer, size_t length, int flags, u32 guest_dest_addr, socklen_t dest_len) {
    char *host_buffer = (char *)malloc(length);
    char *host_dest_addr = (char *)malloc(dest_len);
    Dynarmic_mem_1read(guest_buffer, length, host_buffer);
    Dynarmic_mem_1read(guest_dest_addr, dest_len, host_dest_addr);
    int result = syscallRetCarry(SYS_sendto, socket, host_buffer, length, flags, (const sockaddr *)host_dest_addr, dest_len, 0);
    free(host_buffer);
    free(host_dest_addr);
    return result;
}

ssize_t guest_pread(int NR, int fildes, u32 guest_buf, size_t nbyte, off_t offset) {
    char *host_buf = (char *)malloc(nbyte);
    ssize_t result = syscallRetCarry(NR, fildes, host_buf, nbyte, offset, 0,0,0);
    Dynarmic_mem_1write(guest_buf, nbyte, host_buf);
    free(host_buf);
    return result;
}

ssize_t guest_read(int NR, int fildes, u32 guest_buf, size_t nbyte) {
    char *host_buf = (char *)malloc(nbyte);
    ssize_t result = syscallRetCarry(NR, fildes, host_buf, nbyte, 0,0,0,0);
    Dynarmic_mem_1write(guest_buf, nbyte, host_buf);
    free(host_buf);
    return result;
}

ssize_t guest_write(int NR, int fildes, u32 guest_buf, size_t nbyte) {
    char *host_buf = (char *)malloc(nbyte);
    Dynarmic_mem_1read(guest_buf, nbyte, host_buf);
    ssize_t result = syscallRetCarry(NR, fildes, host_buf, nbyte, 0,0,0,0);
    free(host_buf);
    return result;
}

ssize_t guest_writev(int NR, int fildes, u32 guest_iov, int iovcnt) {
    size_t iovsize = sizeof(iovec_32) * iovcnt;
    iovec_32 *host_iov = (iovec_32 *)malloc(iovsize);
    Dynarmic_mem_1read(guest_iov, iovsize, (char *)host_iov);
    ssize_t result = 0;
    for (int i = 0; i < iovcnt; i++) {
        result += guest_write(NR == SYS_writev ? SYS_write : SYS_write_nocancel, fildes, host_iov[i].guest_iov_base, host_iov[i].iov_len);
    }
    free(host_iov);
    return result;
}

int guest_open(int NR, u32 guest_path, int oflag, int mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    int result = syscallRetCarry(NR, host_path, oflag, mode, 0,0,0,0);
    return result;
}

int guest_unlink(u32 guest_path) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_unlink, host_path, 0,0,0,0,0,0);
}

int guest_chmod(u32 guest_path, mode_t mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_chmod, host_path, mode, 0,0,0,0,0);
}

int guest_chown(u32 guest_path, uid_t owner, gid_t group) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_chown, host_path, owner, group, 0,0,0,0);
}

int guest_access(u32 guest_path, int mode) {
    char host_path[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_path, host_path);
    return syscallRetCarry(SYS_access, host_path, mode, 0,0,0,0,0);
}

int guest_sigaction(int sig, u32 guest_act, u32 guest_oact) {
    static sigaction_32 host_actions[SIGUSR2 + 1];
    if (guest_oact) {
        Dynarmic_mem_1write(guest_oact, sizeof(sigaction_32), (char *)&host_actions[sig]);
    }
    if (guest_act) {
        printf("LC32: sigaction: 0x%08x -> ", host_actions[sig]._sa_handler);
        Dynarmic_mem_1read(guest_act, sizeof(sigaction_32), (char *)&host_actions[sig]);
        printf("LC32: 0x%08x\n", host_actions[sig]._sa_handler);
    }
    return 0;
}

int guest_sigprocmask(int how, u32 guest_set, u32 guest_oldset) {
    sigset_t host_set = guest_set ? sharedHandle.ucb->MemoryRead32(guest_set) : 0;
    sigset_t host_oldset = 0;
    int result = syscallRetCarry(SYS_sigprocmask, how, guest_set ? &host_set : NULL, &host_oldset, 0,0,0,0);
    if (guest_oldset) {
        sharedHandle.ucb->MemoryWrite32(guest_oldset, host_oldset);
    }
    return result;
}

int guest_ioctl(int fildes, u32 request, u32 guest_r2) {
    switch(request) {
        case TIOCSCTTY:
        case TIOCEXCL:
        case TIOCSBRK:
        case TIOCCBRK:
        case TIOCPTYGRANT:
        case TIOCPTYUNLK:
            //case DTRACEHIOC_REMOVE:
            //case BIOCFLUSH:
            //case BIOCPROMISC:
            return syscallRetCarry(SYS_ioctl, fildes, request, guest_r2, 0,0,0,0);
        case FIODTYPE: {
            int host_r2;
            int result = syscallRetCarry(SYS_ioctl, fildes, request, &host_r2, 0,0,0,0);
            sharedHandle.ucb->MemoryWrite32(guest_r2, host_r2);
            return result;
        }
        case DTRACEHIOC_ADD:
        case DTRACEHIOC_ADDDOF:
        case DTRACEHIOC_REMOVE:
        case 0x80046804: // FIXME?
            return -1;
    }
    printf("Unhandled ioctl request: %d (0x%x)\n", request, request);
    sharedHandle.ucb->ExceptionRaised(0xDEADDEAD, Dynarmic::A32::Exception::Yield);
    return -1;
}

int guest_pthread_sigmask(int how, u32 guest_set, u32 guest_oldset) {
    sigset_t host_set = guest_set ? sharedHandle.ucb->MemoryRead32(guest_set) : 0;
    sigset_t host_oldset = 0;
    int result = pthread_sigmask(how, guest_set ? &host_set : NULL, &host_oldset);
    if (guest_oldset) {
        sharedHandle.ucb->MemoryWrite32(guest_oldset, host_oldset);
    }
    // FIXME: does it need carry bit upon error?
    return result;
}

ssize_t guest_readlink(u32 guest_pathname, u32 guest_buf, size_t bufsiz) {
    char host_pathname[PATH_MAX];
    sharedHandle.fs->pathGuestToHost(guest_pathname, host_pathname);
    char *host_buf = (char *)malloc(bufsiz);
    int result = syscallRetCarry(SYS_readlink, host_pathname, host_buf, bufsiz, 0,0,0,0);
    sharedHandle.fs->pathHostToGuest(host_buf, guest_buf);
    Dynarmic_mem_1write(guest_buf, bufsiz, host_buf);
    free(host_buf);
    return result;
}

int guest_munmap(u32 guest_addr, size_t len) {
    int result = Dynarmic_munmap(guest_addr, len);
    if(result == -1) {
        threadHandle.cpsr->setCarry(true);
        return errno;
    }
    return result;
}

int guest_mprotect(u32 guest_addr, size_t len, int prot) {
    int result = Dynarmic_mprotect(guest_addr, len, prot);
    if(result == -1) {
        threadHandle.cpsr->setCarry(true);
        return errno;
    }
    return result;
}

int guest_fcntl(int fildes, int cmd, u32 guest_r2) {
    switch (cmd) {
        // r2 is null or is a literal
        case F_DUPFD:
        case F_GETFD:
        case F_SETFD:
        case F_GETFL:
        case F_SETFL:
        case F_GETOWN:
        case F_SETOWN:
        case F_RDAHEAD:
        case F_NOCACHE:
        case F_FULLFSYNC:
            return syscallRetCarry(SYS_fcntl, fildes, cmd, guest_r2, 0,0,0,0);
        case F_ADDFILESIGS_RETURN:
            // fsig->fs_file_start = 0xFFFFFFFF;
            sharedHandle.ucb->MemoryWrite32(guest_r2, 0xFFFFFFFF);
            return 0;
        case F_CHECK_LV:
            return 0;
        // r2 is a pointer
        case F_GETPATH: {
            char host_r2[PATH_MAX];
            int result = syscallRetCarry(SYS_fcntl, fildes, cmd, host_r2, 0,0,0,0);
            sharedHandle.fs->pathHostToGuest(host_r2, guest_r2);
            return result;
        }
        case F_PREALLOCATE: {
            fstore_t host_r2;
            Dynarmic_mem_1read(guest_r2, sizeof(fstore_t), (char *)&host_r2);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2, 0,0,0,0);
        }
        case F_SETSIZE: {
            off_t host_r2 = sharedHandle.ucb->MemoryRead64(guest_r2);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2);
        }
        case F_RDADVISE: {
            struct radvisory host_r2;
            Dynarmic_mem_1read(guest_r2, sizeof(struct radvisory), (char *)&host_r2);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2, 0,0,0,0);
        }
        //case F_READBOOTSTRAP:
        //case F_WRITEBOOTSTRAP:

        case F_LOG2PHYS: {
            struct log2phys host_r2;
            Dynarmic_mem_1read(guest_r2, sizeof(struct log2phys), (char *)&host_r2);
            int result = syscallRetCarry(SYS_fcntl, fildes, cmd, &host_r2, 0,0,0,0);
            Dynarmic_mem_1write(guest_r2, sizeof(struct log2phys), (char *)&host_r2);
            return result;
        }
        default:
            printf("Unhandled fcntl command: %d\n", cmd);
            sharedHandle.ucb->ExceptionRaised(0xDEADDEAD, Dynarmic::A32::Exception::Yield);
            return syscallRetCarry(SYS_fcntl, fildes, cmd, guest_r2, 0,0,0,0);
    }
}

int guest_proc_info(int callnum, int pid, int flavor, uint64_t arg, u32 guest_buffer, int buffersize) {
    // FIXME: check buffer size
    char *host_buffer = (char *)malloc(buffersize);
    int result = syscallRetCarry(SYS_proc_info, callnum, pid, flavor, arg, host_buffer, buffersize, 0);
    if(callnum == 2 && flavor == PROC_PIDT_SHORTBSDINFO) {
        proc_bsdshortinfo *info = (proc_bsdshortinfo *)host_buffer;
        info->pbsi_flags |= 2; // set PROC_FLAG_TRACED. FIXME: without this, it will crash
        info->pbsi_flags &= ~0x10; // unset PROC_FLAG_LP64
    }
    Dynarmic_mem_1write(guest_buffer, buffersize, host_buffer);
    free(host_buffer);
    return result;
}

int guest_mach_timebase_info(u32 guest_info) {
    struct mach_timebase_info host_info;
    int result = mach_timebase_info(&host_info);
    Dynarmic_mem_1write(guest_info, sizeof(host_info), (char *)&host_info);
    return result;
}

kern_return_t guest_host_create_mach_voucher_trap(mach_port_name_t host, u32 guest_recipes, int recipes_size, u32 guest_voucher) {
    // array of bytes
    mach_voucher_attr_raw_recipe_array_t host_recipes = (mach_voucher_attr_raw_recipe_array_t)malloc(recipes_size);
    Dynarmic_mem_1read(guest_recipes, recipes_size, (char *)host_recipes);
    mach_port_name_t host_voucher;
    kern_return_t result = host_create_mach_voucher_trap(host, host_recipes, recipes_size, &host_voucher);
    sharedHandle.ucb->MemoryWrite32(guest_voucher, host_voucher);
    return result;
}

kern_return_t guest__kernelrpc_mach_vm_allocate_trap(u32 target, u32 guest_address, mach_vm_size_t size, int flags) {
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }

    // FIXME: change the behavior of this to ensure re-mmapping works
    //int tag = flags >> 24;
    bool anywhere = (flags & VM_FLAGS_ANYWHERE) != 0;
    if (anywhere) {
        // Sometimes the address pointer will contain garbage value, change it to 0
        sharedHandle.ucb->MemoryWrite32(guest_address, 0);
    }
    u32 result = Dynarmic_mmap(sharedHandle.ucb->MemoryRead32(guest_address), size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | (anywhere ? 0 : MAP_FIXED), -1, 0);
    if (result == -1) {
/*
        if (!anywhere && tag != VM_MEMORY_REALLOC) {
            printf("IllegalStateException\n");
            abort();
        }
*/
        return KERN_NO_SPACE;
    }
    sharedHandle.ucb->MemoryWrite32(guest_address, result);
    return KERN_SUCCESS;
}

kern_return_t guest__kernelrpc_mach_port_construct_trap(mach_port_name_t target, u32 guest_options, u64 context, u32 guest_name) {
    mach_port_options_t host_options;
    mach_port_name_t host_name;
    Dynarmic_mem_1read(guest_options, sizeof(host_options), (char *)&host_options);
    kern_return_t result = _kernelrpc_mach_port_construct_trap(target, &host_options, context, &host_name);
    sharedHandle.ucb->MemoryWrite32(guest_name, host_name);
    return result;
}

kern_return_t guest__kernelrpc_mach_port_allocate_trap(mach_port_name_t target, mach_port_right_t right, u32 guest_name) {
    mach_port_name_t host_name;
    kern_return_t result = _kernelrpc_mach_port_allocate_trap(target, right, &host_name);
    sharedHandle.ucb->MemoryWrite32(guest_name, host_name);
    return result;
}

kern_return_t guest__kernelrpc_mach_vm_map_trap(mach_port_name_t target, u32 guest_address, mach_vm_size_t size, mach_vm_offset_t mask, int flags, vm_prot_t cur_protection) {
    // TODO: verify and round mask accordingly
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }
    bool anywhere = (flags & VM_FLAGS_ANYWHERE) != 0;
    if (!anywhere) {
        printf("LC32: BackendException: _kernelrpc_mach_vm_map_trap fixed\n");
        return KERN_FAILURE;
    }
    u32 result = Dynarmic_mmap(sharedHandle.ucb->MemoryRead32(guest_address), size, cur_protection, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0, mask ?: DYN_PAGE_MASK);
    if (result == -1) {
        return KERN_NO_SPACE;
    }
    sharedHandle.ucb->MemoryWrite32(guest_address, result);
    return KERN_SUCCESS;
}

kern_return_t guest__kernelrpc_mach_vm_deallocate_trap(u32 target, vm_address_t address, mach_vm_size_t size) {
    if (target != mach_task_self()) {
        return KERN_FAILURE;
    }
    return Dynarmic_munmap(address, size) == 0 ? KERN_SUCCESS : KERN_FAILURE;
}

int guest_abort_with_payload(u32 reason_namespace, u64 reason_code, u32 guest_payload, u32 payload_size, u32 guest_reason_string, u64 reason_flags) {
    DynarmicHostString host_reason_string(guest_reason_string);
    printf("abort_with_payload called with namespace=0x%x, code=0x%llx, reason=%s\n", reason_namespace, reason_code, host_reason_string.hostPtr);
    return 0;
}

////////
int guestMappingLen = 0;
guest_file_mapping guestMappings[1000];

static void load_symbols_for_image(guest_file_mapping *mapping, void(^iterator)(u32 address, const char *name)) {
  u32 slide = mapping->start; // FIXME: properly calculate this slide
  const struct mach_header *header = (const struct mach_header *)mapping->hostAddr;

  u32 crashInfoSize;
  u64 crash_info = (u32)(u64)getsectdatafromheader(header, SEG_DATA, "__crash_info", &crashInfoSize);
  if (crash_info) {
    crash_info += slide;
    crashreporter_annotations_t host_gCRAnnotations;
    Dynarmic_mem_1read(crash_info, sizeof(crashreporter_annotations_t), (char *)&host_gCRAnnotations);
    if (host_gCRAnnotations.message) {
      char message[0x1000];
      Dynarmic_mem_1read(host_gCRAnnotations.message, sizeof(message), message);
      printf("Crash message from %s: %s\n", mapping->name, message);
    } else if (host_gCRAnnotations.message2) {
      printf("gCRAnnotations has message2 but unhandled. Crashing to raise attention\n");
    }
  }

  segment_command *cur_seg_cmd;
  struct symtab_command* symtab_cmd = NULL;
  uintptr_t cur = (uintptr_t)header + sizeof(mach_header);
  for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
    cur_seg_cmd = (segment_command *)cur;
    if (cur_seg_cmd->cmd == LC_SYMTAB) {
      symtab_cmd = (struct symtab_command*)cur_seg_cmd;
    }
  }

  if (!symtab_cmd) {
    return;
  }

  // Find base symbol/string table addresses
  // FIXME: symbol resolution for dyld shared cache
#if 1
  struct nlist *host_symtab = (struct nlist *)((uintptr_t)header + symtab_cmd->symoff);
  u64 host_strtab = (u32)((uintptr_t)header + symtab_cmd->stroff);

  struct nlist *symtab = (struct nlist *)((u64)mapping->start + symtab_cmd->symoff);
  u32 strtab = (u32)(mapping->start + symtab_cmd->stroff);
  iterator(mapping->start, "(unknown symbol)");
  if(!get_memory(strtab)) {
    return;
  }

  for(int i=0; i < symtab_cmd->nsyms; i++) {
    u32 addr = strtab + sharedHandle.ucb->MemoryRead32((u32)(u64)&symtab[i].n_un.n_strx);
    //u32 host_addr = host_strtab +
    if(!get_memory(addr)) continue;
    u64 symbolAddr = sharedHandle.ucb->MemoryRead32((u32)(u64)&symtab[i].n_value) + slide;
    u64 hostSymbolAddr = host_symtab[i].n_value + slide;
    DynarmicHostString host_sym(addr);
    if(*host_sym.hostPtr) {
      iterator(symbolAddr, (const char *)host_sym.hostPtr);
    } else {
      iterator(symbolAddr, (const char *)symbolAddr);
    }
  }
#else
  struct nlist *symtab = (struct nlist *)((uintptr_t)header + symtab_cmd->symoff);
  char *strtab = (char *)((uintptr_t)header + symtab_cmd->stroff);
  for(int i=0; i < symtab_cmd->nsyms; i++) {
    iterator(symtab[i].n_value + slide, (const char *)(strtab + symtab[i].n_un.n_strx));
  }
#endif
}

void symbolicate_call_stack(symbolicated_call *callStack, int callStackLen) {
  for (int n = 0; n < guestMappingLen; n++) {
    load_symbols_for_image(&guestMappings[n], ^(u32 address, const char *name){
      //printf("[0x%08x-0x%08x] %s`%s\n", address, guestMappings[n].name, name);
      for (int i = 0; i < callStackLen; i++) {
        if (callStack[i].address >= address && (!callStack[i].symbolName || callStack[i].address - address < callStack[i].symbolOffset)) {
          //printf("0x%08x [0x%08x-0x%08x]\n", callStack[i].address, start, end);
          callStack[i].imageName = guestMappings[n].name;
          callStack[i].symbolName = name;
          callStack[i].symbolOffset = callStack[i].address - address;
        }
      }
    });
  }
}

char *get_memory_page(u64 vaddr) {
    size_t num_page_table_entries = sharedHandle.num_page_table_entries;
    void **page_table = sharedHandle.page_table;
    khash_t(memory) *memory = sharedHandle.memory;
    u64 idx = vaddr >> DYN_PAGE_BITS;
    if(page_table && idx < num_page_table_entries) {
      return (char *)page_table[idx];
    }
    u64 base = vaddr & ~DYN_PAGE_MASK;
    khiter_t k = kh_get(memory, memory, base);
    if(k == kh_end(memory)) {
      return NULL;
    }
    t_memory_page page = kh_value(memory, k);
    return (char *)page->addr;
}

inline void *get_memory(u64 vaddr) {
    char *page = get_memory_page(vaddr);
    return page ? &page[vaddr & DYN_PAGE_MASK] : NULL;
}

class DynarmicCallbacks32 final : public Dynarmic::A32::UserCallbacks {
private:
    ~DynarmicCallbacks32() = default;

public:
    void destroy() {
        this->cp15 = nullptr;
        delete this;
    }

    DynarmicCallbacks32(khash_t(memory) *memory)
        : memory{memory}, cp15(std::make_shared<DynarmicCP15>()) {}

    bool IsReadOnlyMemory(u32 vaddr) override {
//        u32 idx;
//        return mem_map && (idx = vaddr >> DYN_PAGE_BITS) < num_page_table_entries && mem_map[idx] & PAGE_EXISTS_BIT && (mem_map[idx] & UC_PROT_WRITE) == 0;
        return false;
    }

    std::optional<uint32_t> MemoryReadCode(u32 vaddr) override {
#if TRACE_BRANCH
        static u32 lastRead;
        if (vaddr - lastRead != 4 && vaddr == cpu->Regs()[15]) {
            lastRead = vaddr;
            DumpBacktrace(false);
        }
#endif
        return MemoryRead32(vaddr, false);
    }
    u16 MemoryReadThumbCode(u32 vaddr) {
        u16 code = MemoryRead16(vaddr, false);
//        printf("MemoryReadThumbCode[%s->%s:%d]: vaddr=0x%x, code=0x%04x\n", __FILE__, __func__, __LINE__, vaddr, code);
        return code;
    }

// FIXME: sometimes it will try to access 0x4, 0x8 and 0xc, I disassembled and found nothing, is there something to do with cpsr? For now let it do stuff in an empty page...
    void HandleBadMemoryAccess() {
#if !IGNORE_BAD_MEM_ACCESS
        DumpCrashReport();
#endif
    }

    u8 MemoryRead8(u32 vaddr) override {
        u8 *dest = (u8 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: read08(0x%04x) = 0x%01x\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
            return 0;
        }
    }
    u16 MemoryRead16(u32 vaddr, bool trace) {
        if(vaddr & 1) {
            const u8 a{MemoryRead8(vaddr)};
            const u8 b{MemoryRead8(vaddr + sizeof(u8))};
            return (static_cast<u16>(b) << 8) | a;
        }
        u16 *dest = (u16 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            if (trace)
            printf("Trace: read16(0x%04x) = 0x%02x\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            // trace = tolerance bad mềm access, else crash
            if(trace) {
                HandleBadMemoryAccess();
            } else {
                DumpCrashReport();
            }
            return 0;
        }
    }
    u16 MemoryRead16(u32 vaddr) override {
        return MemoryRead16(vaddr, true);
    }
    u32 MemoryRead32(u32 vaddr, bool trace) {
        if(vaddr & 3) {
            const u16 a{MemoryRead16(vaddr)};
            const u16 b{MemoryRead16(vaddr + sizeof(u16))};
            return (static_cast<u32>(b) << 16) | a;
        }
        u32 *dest = (u32 *) get_memory(vaddr);
        if(dest) {
            //printf("MemoryRead32[%s->%s:%d]: vaddr=0x%x, value=0x%x\n", __FILE__, __func__, __LINE__, vaddr, dest[0]);
#if TRACE_RW
            if (trace)
            printf("Trace: read32(0x%04x) = 0x%04x\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            // trace = tolerance bad mềm access, else crash
            if(trace) {
                HandleBadMemoryAccess();
            } else {
                DumpCrashReport();
            }
            return 0;
        }
    }
    u32 MemoryRead32(u32 vaddr) override {
        return MemoryRead32(vaddr, true);
    }
    u64 MemoryRead64(u32 vaddr) override {
        if(vaddr & 7) {
            const u32 a{MemoryRead32(vaddr)};
            const u32 b{MemoryRead32(vaddr + sizeof(u32))};
            return (static_cast<u64>(b) << 32) | a;
        }
        u64 *dest = (u64 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: read64(0x%04x) = 0x%08llx\n", vaddr, dest[0]);
#endif
            return dest[0];
        } else {
            fprintf(stderr, "MemoryRead64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
            return 0;
        }
    }

    void MemoryWrite8(u32 vaddr, u8 value) override {
        u8 *dest = (u8 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write08(0x%04x) = 0x%01x\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite8[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }
    void MemoryWrite16(u32 vaddr, u16 value) override {
        if(vaddr & 1) {
            MemoryWrite8(vaddr, static_cast<u8>(value));
            MemoryWrite8(vaddr + sizeof(u8), static_cast<u8>(value >> 8));
            return;
        }
        u16 *dest = (u16 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write16(0x%04x) = 0x%02x\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite16[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }
    void MemoryWrite32(u32 vaddr, u32 value) override {
        if(vaddr & 3) {
            MemoryWrite16(vaddr, static_cast<u16>(value));
            MemoryWrite16(vaddr + sizeof(u16), static_cast<u16>(value >> 16));
            return;
        }
        u32 *dest = (u32 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write32(0x%04x) = 0x%04x\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite32[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }
    void MemoryWrite64(u32 vaddr, u64 value) override {
        if(vaddr & 7) {
            MemoryWrite32(vaddr, static_cast<u32>(value));
            MemoryWrite32(vaddr + sizeof(u32), static_cast<u32>(value >> 32));
            return;
        }
        u64 *dest = (u64 *) get_memory(vaddr);
        if(dest) {
#if TRACE_RW
            printf("Trace: write64(0x%04x) = 0x%08llx\n", vaddr, value);
#endif
            dest[0] = value;
        } else {
            fprintf(stderr, "MemoryWrite64[%s->%s:%d]: vaddr=0x%x\n", __FILE__, __func__, __LINE__, vaddr);
            HandleBadMemoryAccess();
        }
    }

    bool MemoryWriteExclusive8(u32 vaddr, u8 value, u8 expected) override {
        bool write = MemoryRead8(vaddr) == expected;
        if(write) {
            MemoryWrite8(vaddr, value);
        }
        return write;
    }
    bool MemoryWriteExclusive16(u32 vaddr, u16 value, u16 expected) override {
        bool write = MemoryRead16(vaddr) == expected;
        if(write) {
            MemoryWrite16(vaddr, value);
        }
        return write;
    }
    bool MemoryWriteExclusive32(u32 vaddr, u32 value, u32 expected) override {
        bool write = MemoryRead32(vaddr) == expected;
        if(write) {
            MemoryWrite32(vaddr, value);
        }
        return write;
    }
    bool MemoryWriteExclusive64(u32 vaddr, u64 value, u64 expected) override {
        bool write = MemoryRead64(vaddr) == expected;
        if(write) {
            MemoryWrite64(vaddr, value);
        }
        return write;
    }

    void InterpreterFallback(u32 pc, std::size_t num_instructions) override {
        cpu->HaltExecution();
        std::optional<std::uint32_t> code = MemoryReadCode(pc);
        if(code) {
            fprintf(stderr, "Unicorn fallback @ 0x%x for %lu instructions (instr = 0x%08X)", pc, num_instructions, *(cpsr->isThumb() ? MemoryReadThumbCode(pc) : MemoryReadCode(pc)));
        }
        DumpCrashReport();
    }

    void ExceptionRaised(u32 pc, Dynarmic::A32::Exception exception) override {
        bool isBkpt = exception == Dynarmic::A32::Exception::Breakpoint;
        u32 code = *(cpsr->isThumb() ? MemoryReadThumbCode(pc) : MemoryReadCode(pc));
        if(isBkpt) {
            printf("Breakpoint!\n");
            DumpCrashReport();
        } else if ((code & 0xFFFF) == 0xDEFE) {
            printf("ExceptionRaised[%s->%s:%d]: pc=0x%x, exception=%d, code=TRAP\n", __FILE__, __func__, __LINE__, pc, exception);
            DumpCrashReport();
        } else {
            printf("ExceptionRaised[%s->%s:%d]: pc=0x%x, exception=%d, code=0x%08X\n", __FILE__, __func__, __LINE__, pc, exception, code);
            DumpCrashReport();
        }
    }

    void DumpCrashReport() {
        DumpBacktrace(true);
    }
    
    void DumpBacktrace(bool crash) {
        static bool crashing = false;
        if (crashing) {
            printf("Caught error while dumping call stack\n");
            return;
        }
        crashing = true;

        printf("# %s\n", crash ? "CRASHED" : "Branch");
        printf("Registers: \n");
        printf(" r0 0x%08x  r1 0x%08x  r2 0x%08x  r3 0x%08x\n", cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
        printf(" r4 0x%08x  r5 0x%08x  r6 0x%08x  r7 0x%08x\n", cpu->Regs()[4], cpu->Regs()[5], cpu->Regs()[6], cpu->Regs()[7]);
        printf(" r8 0x%08x  r9 0x%08x r10 0x%08x r11 0x%08x\n", cpu->Regs()[8], cpu->Regs()[9], cpu->Regs()[10], cpu->Regs()[11]);
        printf("r12 0x%08x  sp 0x%08x  lr 0x%08x  pc 0x%08x\n", cpu->Regs()[12], cpu->Regs()[13], cpu->Regs()[14], cpu->Regs()[15]);
        printf("CPSR: 0x%08x thumb(%d) N(%d) Z(%d) C(%d) V(%d)\n", cpu->Cpsr(), threadHandle.cpsr->isThumb(), threadHandle.cpsr->isNegative(), threadHandle.cpsr->isZero(), threadHandle.cpsr->hasCarry(), threadHandle.cpsr->isOverflow());

        u32 pc = cpu->Regs()[15];
        u32 lr = cpu->Regs()[14];
        u32 fp = cpu->Regs()[7];

        struct symbolicated_call callStack[0x100] = {{0}};
        int callStackLen = 0;
        callStack[callStackLen++].address = pc - 2;
        callStack[callStackLen++].address = lr - 2;
        for (; callStackLen < 0x100; callStackLen++) {
            pc = MemoryRead32(fp + 4, false) & ~1;
            callStack[callStackLen].address = pc - 2;
            fp = MemoryRead32(fp, false);
            if(!fp) break;
        }
        symbolicate_call_stack(callStack, callStackLen);

        printf("Call stack: \n");
        for (int i = 0; i < 0x100; i++) {
            if (!callStack[i].address) break;
            printf("%3d: 0x%08x", i, callStack[i].address);
            const char *symbolName = callStack[i].symbolName;
            if (symbolName) {
                printf(" %s`%s + 0x%x\n", callStack[i].imageName, &symbolName[symbolName[0] == '_'], callStack[i].symbolOffset);
            } else {
                printf("\n");
            }
        }

        printf("Binary images: \n");
        for (int i = 0; i < guestMappingLen; i++) {
            printf("%3d: 0x%08x-0x%08x %s\n", i, guestMappings[i].start, guestMappings[i].end, guestMappings[i].name);
        }

        crashing = crash;
        if (crash) abort();
    }

    void CallSVC(u32 swi) override {
        int NR = cpu->Regs()[12];
        if (swi == 0 && cpu->Regs()[5] == POST_CALLBACK_SYSCALL_NUMBER && cpu->Regs()[7] == 0) { // postCallback
            int number = cpu->Regs()[4];
/*
            Svc svc = svcMemory.getSvc(number);
            if (svc != null) {
                svc.handlePostCallback(emulator);
                    return;
            }
            backend.emu_stop();
*/
            printf("svc number: %d\n", number);
            DumpCrashReport();
        }
        if (swi == 0 && cpu->Regs()[5] == PRE_CALLBACK_SYSCALL_NUMBER && cpu->Regs()[7] == 0) { // preCallback
            int number = cpu->Regs()[4];
/*
            Svc svc = svcMemory.getSvc(number);
            if (svc != null) {
                svc.handlePreCallback(emulator);
                return;
             }
            backend.emu_stop();
*/
            printf("Unhandled svc number: %d\n", number);
            DumpCrashReport();
        }
        if (swi != DARWIN_SWI_SYSCALL) {
            if (swi == (cpsr->isThumb() ? 0xff : 0xffffff)) {
                printf("LC32: throw: PopContextException\n");
                DumpCrashReport();
            }
            if (swi == (cpsr->isThumb() ? 0xff : 0xffffff) - 1) {
                printf("LC32: throw: ThreadContextSwitchException\n");
                DumpCrashReport();
            }
            printf("Unhandled svc number: %d\n", swi);
            DumpCrashReport();
/*
            Svc svc = svcMemory.getSvc(swi);
            if (svc != null) {
                backend.reg_write(ArmConst.UC_ARM_REG_R0, (int) svc.handle(emulator));
                return;
            }
            backend.emu_stop();
            throw new IllegalStateException("svc number: " + swi + ", NR=" + NR);
*/
        }

#if TRACE_SVC
        printf("CallSVC(NR=%d)\n", NR);
#endif

        cpsr->setCarry(false);
/*
BE CAREFUL WHEN MOVING SYSCALL. Checklist:
- Declared max args of the category
- Arg contains 64bit value? (must not)
- Exclude pointer-involved (guest_*)
*/
        switch (NR) {
            // direct calls with 0-4 arguments, returns 32bit value
            case -91: // mk_timer_create
            case -29: // host_self_trap
            case -28: // task_self_trap
            case -27: // thread_self_trap
            case -26: // mach_reply_port
            case -21: // _kernelrpc_mach_port_insert_right_trap
            case -19: // _kernelrpc_mach_port_mod_refs_trap
            case SYS_close: // 6
            case SYS_getpid: // 20
            case SYS_setuid: // 23
            case SYS_getuid: // 24
            case SYS_geteuid: // 25
            case SYS_getppid: // 39
            case SYS_getegid: // 43
            case SYS_getgid: // 47
            case SYS_fsync: // 95
            case SYS_socket: // 97
            case SYS_issetugid: // 327
            case SYS_close_nocancel: // 399
                cpu->Regs()[0] = syscallRetCarry(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                cpsr->setCarry(false); // FIXME: mach_reply_port sets carry to true, idk why
                break;
            // direct calls with 0-2 arguments, returns 64bit value
            case -18: // _kernelrpc_mach_port_deallocate_trap
            case -3: // mach_absolute_time
            case 372: { // thread_selfid
                u64 result = syscallRetCarry((long)NR, cpu->Regs()[0], cpu->Regs()[1]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
            } break;
            // direct call with custom args
            case 423: // semwait_signal_nocancel
                cpu->Regs()[0] = syscallRetCarry(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4] | ((u64)cpu->Regs()[5] << 32), cpu->Regs()[6]);
                break;
            // the rest are indirect calls
            case -89:
                cpu->Regs()[0] = guest_mach_timebase_info(cpu->Regs()[0]);
                break;
            case -70:
                cpu->Regs()[0] = guest_host_create_mach_voucher_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                break;
            case -31:
                cpu->Regs()[0] = guest_mach_msg_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5], cpu->Regs()[6]);
                break;
            case -24:
                cpu->Regs()[0] = guest__kernelrpc_mach_port_construct_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32), cpu->Regs()[4]);
                break;
            case -16: // _kernelrpc_mach_port_allocate_trap
                cpu->Regs()[0] = guest__kernelrpc_mach_port_allocate_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case -15:
                // NOTE: skip r7 since it's frame pointer
                cpu->Regs()[0] = guest__kernelrpc_mach_vm_map_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32), cpu->Regs()[4] | ((u64)cpu->Regs()[5] << 32), cpu->Regs()[6], cpu->Regs()[8]);
                break;
            case -12:
                cpu->Regs()[0] = guest__kernelrpc_mach_vm_deallocate_trap(cpu->Regs()[0], cpu->Regs()[1] | ((u64)cpu->Regs()[2] << 32), cpu->Regs()[3] | ((u64)cpu->Regs()[4] << 32));
                break;
            case -10:
                cpu->Regs()[0] = guest__kernelrpc_mach_vm_allocate_trap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32), cpu->Regs()[4]);
                break;
            case SYS_syscall: {
                printf("Warning: CallSVC(SYS_syscall, NR=%d) called. Be sure to check arguments\n", cpu->Regs()[0]);
                cpu->Regs()[12] = cpu->Regs()[0];
                CallSVC(0x80);
                break;
            }
            case SYS_exit: // 1
                printf("Guest exited with code %d\n", cpu->Regs()[0]);
                exit(cpu->Regs()[0]);
                break;
            case SYS_fork: // 2
                printf("fork() not supported\n");
                cpu->Regs()[0] = ENOSYS;
                break;
            case SYS_read: // 3
            case SYS_read_nocancel: // 396
                // Note: we don't use the cancel version cause unidbg also doesn't and it hangs
                cpu->Regs()[0] = guest_read(SYS_read_nocancel, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_write: // 4
            case SYS_write_nocancel:
                cpu->Regs()[0] = guest_write(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_open: // 5
            case SYS_open_nocancel:
                // Note: we don't use the cancel version cause unidbg also doesn't and it hangs
                cpu->Regs()[0] = guest_open(SYS_open_nocancel, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case SYS_unlink: // 10
                cpu->Regs()[0] = guest_unlink(cpu->Regs()[0]);
                break;
            case SYS_chmod: // 15
                cpu->Regs()[0] = guest_chmod(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case SYS_chown: // 16
                cpu->Regs()[0] = guest_chown(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 33:
                cpu->Regs()[0] = guest_access(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 46:
                cpu->Regs()[0] = guest_sigaction(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 48:
                cpu->Regs()[0] = guest_sigprocmask(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 54:
                cpu->Regs()[0] = guest_ioctl(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 58:
                cpu->Regs()[0] = guest_readlink(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 73:
                cpu->Regs()[0] = guest_munmap(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 74:
                cpu->Regs()[0] = guest_mprotect(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 75: // posix_madvise
                cpu->Regs()[0] = 0;
                break;
            case 92:
            case SYS_fcntl_nocancel:
                cpu->Regs()[0] = guest_fcntl(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 98:
                cpu->Regs()[0] = guest_connect(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 116:
                cpu->Regs()[0] = guest_gettimeofday(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 121:
            case SYS_writev_nocancel:
                cpu->Regs()[0] = guest_writev(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 128:
                cpu->Regs()[0] = guest_rename(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 133:
                cpu->Regs()[0] = guest_sendto(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case 153:
            case SYS_pread_nocancel:
                cpu->Regs()[0] = guest_pread(NR, cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3] | ((u64)cpu->Regs()[4] << 32));
                break;
            case 169:
                cpu->Regs()[0] = guest_csops(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                break;
            case 194:
                cpu->Regs()[0] = guest_getrlimit(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 197:
                cpu->Regs()[0] = guest_mmap(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5] | ((u64)cpu->Regs()[6] << 32));
                break;
            case 202:
                cpu->Regs()[0] = guest___sysctl(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case 220:
                cpu->Regs()[0] = guest_getattrlist(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4]);
                break;
            case 266:
                cpu->Regs()[0] = guest_shm_open(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 274:
                cpu->Regs()[0] = guest___sysctlbyname(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5]);
                break;
            case 286:
                cpu->Regs()[0] = guest_pthread_getugid_np(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 294: // __shared_region_check_np
                cpu->Regs()[0] = return_with_carry_direct(EINVAL, true);
                break;
#if 0
            case 301:
                backend.reg_write(ArmConst.UC_ARM_REG_R0, psynch_mutexwait(emulator));
                break;
            case 302:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, psynch_mutexdrop(emulator));
                    break;
                case 303:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, psynch_cvbroad(emulator));
                    break;
                case 305:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, psynch_cvwait(emulator));
                    break;
#endif
            case 328:
                printf("pthread_kill called\n");
                DumpCrashReport();
                break;
            case 329:
                cpu->Regs()[0] = guest_pthread_sigmask(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
#if 0
                case 330:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, sigwait(emulator));
                    break;
                case 331:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, disable_threadsignal(emulator));
                    break;
                case 334:
                    backend.reg_write(ArmConst.UC_ARM_REG_R0, semwait_signal(emulator));
                    break;
#endif
            case 336:
                cpu->Regs()[0] = guest_proc_info(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3] | ((u64)cpu->Regs()[4] << 32), cpu->Regs()[5], cpu->Regs()[6]);
                break;
            case 338:
                cpu->Regs()[0] = guest_stat64(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 339:
                cpu->Regs()[0] = guest_fstat(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 340:
                cpu->Regs()[0] = guest_lstat(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 344:
                cpu->Regs()[0] = guest_getdirentries64(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3]);
                break;
            case 345:
                cpu->Regs()[0] = guest_statfs64(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 346:
                cpu->Regs()[0] = guest_fstatfs64(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case 366:
                cpu->Regs()[0] = guest_bsdthread_register(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5] | ((u64)cpu->Regs()[6] << 32));
                break;
            case 381:
                cpu->Regs()[0] = guest_sandbox_ms(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                break;
            case 489: //mremap_encrypted
                printf("LC32: attempted to load encrypted binaries?\n");
                cpu->Regs()[0] = 0; //return_with_carry_direct(EPERM, true);
                break;
            case 500:
                cpu->Regs()[0] = guest_getentropy(cpu->Regs()[0], cpu->Regs()[1]);
                break;
            case SYS_abort_with_payload:
                cpu->Regs()[0] = guest_abort_with_payload(cpu->Regs()[0], cpu->Regs()[1] | ((u64)cpu->Regs()[2] << 32), cpu->Regs()[3], cpu->Regs()[4], cpu->Regs()[5], cpu->Regs()[6] | ((u64)cpu->Regs()[8] << 32));
                DumpCrashReport();
                break;
            case (int)0x80000000:
                NR = cpu->Regs()[3];
                if(handleMachineDependentSyscall(NR)) {
                    break;
                }
            case 1001: { // LC32Dlsym
                u64 result = LC32Dlsym(cpu->Regs()[0], cpu->Regs()[1]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1002: { // LC32InvokeHostCRet32
                if(cpu->IsExecuting()) {
                    // Get out of the callback first, since host may call other guest functions
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                typedef u32(*HostCall)(u32, u32, u32);
                HostCall hostCall = (HostCall)((u64)cpu->Regs()[0] | ((u64)cpu->Regs()[1] << 32));
                cpu->Regs()[0] = hostCall(cpu->Regs()[2], cpu->Regs()[3], cpu->Regs()[Reg::SP]);
                break;
            }
            case 1003: { // LC32GuestToHostCString
                DynarmicHostString host_pointer(cpu->Regs()[0], cpu->Regs()[1]);
                u64 result = (u64)host_pointer.hostPtrForGuest();
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1004: { // LC32GuestToHostCStringFree
                u64 pointer = cpu->Regs()[0] | ((u64)cpu->Regs()[1] << 32);
                // TODO: maybe move the check to guest
                if(pointer & DynarmicHostString_NEED_FREE) {
                    free((void *)((u64)pointer & ~DynarmicHostString_NEED_FREE));
                }
                break;
            }
            case 1005: { // LC32GetHostSelector
                u64 result = LC32GetHostSelector(cpu->Regs()[0]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1006: { // LC32InvokeHostSelector
                if(cpu->IsExecuting()) {
                    // Get out of the callback first, since host may call other guest functions
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                u64 host_self = (u64)cpu->Regs()[0] | ((u64)cpu->Regs()[1] << 32);
                u64 host_cmd = (u64)cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32);
                u64 result = LC32InvokeHostSelector(host_self, host_cmd, cpu->Regs()[Reg::SP]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1007: { // LC32GetHostObject
                if(cpu->IsExecuting()) {
                    // Get out of the callback first, since host may call other guest functions
                    cpu->HaltExecution(LC32HaltReasonSVC);
                    return;
                }
                u64 result = LC32GetHostObject(cpu->Regs()[0], cpu->Regs()[1], cpu->Regs()[2]);
                cpu->Regs()[0] = (u32)result;
                cpu->Regs()[1] = (u32)(result >> 32);
                break;
            }
            case 1008: { // LC32HostToGuestCopyString
                u64 host_object = (u64)cpu->Regs()[2] | ((u64)cpu->Regs()[3] << 32);
                cpu->Regs()[0] = LC32HostToGuestCopyClassName(cpu->Regs()[0], cpu->Regs()[1], host_object);
                break;
            }
            case 1009:
                assert(cpu->IsExecuting());
                // We're returning from guest call
                cpu->HaltExecution(LC32HaltReasonRetFromGuest);
                return;
            default:
                printf("Unhandled svc number: %d\n", NR);
                DumpCrashReport();
                break;
        }
#if TRACE_SVC
        printf("CallSVC returned 0x%08x, carry %d\n", cpu->Regs()[0], cpsr->hasCarry());
#endif
    }

    bool handleMachineDependentSyscall(int NR) {
        printf("handleMachineDependentSyscall(%d)\n", NR);
        switch (NR) {
            case 0:
                //backend.reg_write(ArmConst.UC_ARM_REG_R0, sys_icache_invalidate(emulator));
                return true;
            case 1:
                //backend.reg_write(ArmConst.UC_ARM_REG_R0, sys_dcache_flush(emulator));
                return true;
            case 2:
                printf("TSB set to 0x%08x\n", cpu->Regs()[0]);
                cp15.get()->uro = cpu->Regs()[0];
                cpu->Regs()[0] = 0;
                return true;
            case 3:
                cpu->Regs()[0] = cp15.get()->uro;
                return true;
        }
        return false;
    }

    void AddTicks(u64 ticks) override {
    }

    u64 GetTicksRemaining() override {
        return 0x10000000000ULL;
    }

    khash_t(memory) *memory = NULL;
    size_t num_page_table_entries;
    void **page_table = NULL;
    Dynarmic::A32::Jit *cpu;
    DynarmicCpsr *cpsr;
    std::shared_ptr<DynarmicCP15> cp15;
};

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    nativeInitialize
 * Signature: (Z)J
 */
bool Dynarmic_nativeInitialize() {
  sharedHandle.memory = kh_init(memory);
  if(sharedHandle.memory == NULL) {
    fprintf(stderr, "kh_init memory failed\n");
    abort();
    return 0;
  }
  int ret = kh_resize(memory, sharedHandle.memory, 0x1000);
  if(ret == -1) {
    fprintf(stderr, "kh_resize memory failed\n");
    abort();
    return 0;
  }
  sharedHandle.monitor = new Dynarmic::ExclusiveMonitor(1);
  {
    DynarmicCallbacks32 *callbacks = new DynarmicCallbacks32(sharedHandle.memory);

    Dynarmic::A32::UserConfig config;
    config.callbacks = callbacks;
    config.coprocessors[15] = callbacks->cp15;
    config.processor_id = 0;
    config.global_monitor = sharedHandle.monitor;
    config.always_little_endian = false;
    config.wall_clock_cntpct = true;
//    config.page_table_pointer_mask_bits = DYN_PAGE_BITS;

//    config.unsafe_optimizations = true;
//    config.optimizations |= Dynarmic::OptimizationFlag::Unsafe_UnfuseFMA;
//    config.optimizations |= Dynarmic::OptimizationFlag::Unsafe_ReducedErrorFP;

    sharedHandle.num_page_table_entries = Dynarmic::A32::UserConfig::NUM_PAGE_TABLE_ENTRIES;
    size_t size = sharedHandle.num_page_table_entries * sizeof(void*);
    sharedHandle.page_table = (void **)mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
    if(sharedHandle.page_table == MAP_FAILED) {
      fprintf(stderr, "nativeInitialize mmap failed[%s->%s:%d] size=0x%zx, errno=%d, msg=%s\n", __FILE__, __func__, __LINE__, size, errno, strerror(errno));
      sharedHandle.page_table = NULL;
    } else {
      callbacks->num_page_table_entries = sharedHandle.num_page_table_entries;
      callbacks->page_table = sharedHandle.page_table;

      // Unpredictable instructions
      config.define_unpredictable_behaviour = true;

      // Memory
      config.page_table = reinterpret_cast<std::array<std::uint8_t*, Dynarmic::A32::UserConfig::NUM_PAGE_TABLE_ENTRIES>*>(sharedHandle.page_table);
      config.absolute_offset_page_table = false;
      config.detect_misaligned_access_via_page_table = 16 | 32 | 64 | 128;
      config.only_detect_misalignment_via_page_table_on_page_boundary = true;
    }

    sharedHandle.cb = callbacks;
    threadHandle.jit = new Dynarmic::A32::Jit(config);
    threadHandle.cpsr = new DynarmicCpsr(threadHandle.jit);
    sharedHandle.fs = new LC32Filesystem();
    callbacks->cpu = threadHandle.jit;
    callbacks->cpsr = threadHandle.cpsr;
  }
  return true;
}

void Dynarmic_nativeDestroy() {
  khash_t(memory) *memory = sharedHandle.memory;
  for (khiter_t k = kh_begin(memory); k < kh_end(memory); k++) {
    if(kh_exist(memory, k)) {
      t_memory_page page = kh_value(memory, k);
      int ret = munmap(page->addr, DYN_PAGE_SIZE);
      if(ret != 0) {
        fprintf(stderr, "munmap failed[%s->%s:%d]: addr=%p, ret=%d\n", __FILE__, __func__, __LINE__, page->addr, ret);
      }
      free(page);
    }
  }
  kh_destroy(memory, memory);
  Dynarmic::A32::Jit *jit = threadHandle.jit;
  if(jit) {
    jit->ClearCache();
    jit->Reset();
    delete jit;
  }
  DynarmicCallbacks32 *cb = sharedHandle.cb;
  if(cb) {
    cb->destroy();
  }
  if(sharedHandle.page_table) {
    int ret = munmap(sharedHandle.page_table, sharedHandle.num_page_table_entries * sizeof(void*));
    if(ret != 0) {
      fprintf(stderr, "munmap failed[%s->%s:%d]: page_table=%p, ret=%d\n", __FILE__, __func__, __LINE__, sharedHandle.page_table, ret);
    }
  }
  delete sharedHandle.monitor;
}

// FIXME: unmapping 1/4 of 16k page will unmap other 3/4 pages
int Dynarmic_munmap(u64 address, u64 size) {
  if(address & DYN_PAGE_MASK) {
    errno = EINVAL;
    return -1;
  }
  if(size == 0 || (size & DYN_PAGE_MASK)) {
    errno = EINVAL;
    return -1;
  }
  khash_t(memory) *memory = sharedHandle.memory;
  for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
    u64 idx = vaddr >> DYN_PAGE_BITS;
    khiter_t k = kh_get(memory, memory, vaddr);
    if(k == kh_end(memory)) {
      fprintf(stderr, "mem_unmap failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
      errno = ENOMEM;
      return -1;
    }
    if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
      sharedHandle.page_table[idx] = NULL;
    }
    t_memory_page page = kh_value(memory, k);
    int ret = munmap(page->addr, DYN_PAGE_SIZE);
    if(ret != 0) {
      fprintf(stderr, "munmap failed[%s->%s:%d]: addr=%p, ret=%d\n", __FILE__, __func__, __LINE__, page->addr, ret);
    }
    free(page);
    kh_del(memory, memory, k);
  }
  return 0;
}

u64 Dynarmic_mem_reserve(u64 address, u64 size, bool fixed, u64 mask) {
  static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
  pthread_mutex_lock(&mutex);

  // Don't allocate anything below 16MB region to better catch bad accesses
  if (address < 0x10000000) { // DYN_PAGE_SIZE
    if (fixed) {
      pthread_mutex_unlock(&mutex);
      printf("Dynarmic_mem_reserve: refusing to reserve below 16MB range\n");
      return -1;
    } else {
      address += 0x10000000;
    }
  }

  address = (address + mask) &~ mask;
  khash_t(memory) *memory = sharedHandle.memory;
  int ret;
  for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
    khiter_t k;
    if((k = kh_get(memory, memory, vaddr)) != kh_end(memory)) {
      if (fixed) {
#if 0
        pthread_mutex_unlock(&mutex);
        printf("Dynarmic_mem_reserve: cannot reserve fixed address 0x%llx. It is bound to 0x%llx\n", address, kh_value(memory, k)->addr);
        return -1;
#else
        //printf("Dynarmic_mem_reserve: force-remapping at address 0x%llx\n", address);
        // FIXME: what should I really do here? Unmap will cause subsequent 3 pages (remember we're running 4k binaries on 16k) to be unmapped aswell
        //Dynarmic_munmap(vaddr, DYN_PAGE_SIZE);
#endif
      } else {
        address = vaddr + mask + 1;
      }
    }
  }

  for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
    khiter_t k = kh_put(memory, memory, vaddr, &ret);
    t_memory_page page = (t_memory_page) calloc(1, sizeof(struct memory_page));
    kh_value(memory, k) = page;
  }

  pthread_mutex_unlock(&mutex);
  printf("Dynarmic_mem_reserve: 0x%llx-0x%llx\n", address, address + size);
  return address;
}

u32 Dynarmic_direct_mmap(u32 address, u32 size, int protection, int flags, void *src, u64 off) {
  if(address & DYN_PAGE_MASK) {
    errno = EINVAL;
    return -1;
  }
  if(size == 0 || (size & DYN_PAGE_MASK)) {
    errno = EINVAL;
    return -1;
  }

  khash_t(memory) *memory = sharedHandle.memory;
  address = Dynarmic_mem_reserve(address, size, flags & MAP_FIXED, DYN_PAGE_MASK);
  if(address == -1) {
    fprintf(stderr, "reserve failed[%s->%s:%d]: addr=0x%x\n", __FILE__, __func__, __LINE__, address);
    return -1;
  }

  for(u32 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
    u64 idx = vaddr >> DYN_PAGE_BITS;

    void *addr = (void *)((u64)src + off + vaddr - address);
    if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
      sharedHandle.page_table[idx] = addr;
    } else {
      // 0xffffff80001f0000ULL: 0x10000
    }
    t_memory_page page = kh_value(memory, kh_get(memory, memory, vaddr));
    page->addr = addr;
    page->perms = protection;
  }
  return address;
}

u32 Dynarmic_mmap(u32 address, u32 size, int protection, int flags, int fildes, u64 off, u64 mask) {
  if(address & DYN_PAGE_MASK) {
    errno = EINVAL;
    return -1;
  }
  if(size == 0 || (size & mask)) {
    errno = EINVAL;
    return -1;
  }
  khash_t(memory) *memory = sharedHandle.memory;
  address = Dynarmic_mem_reserve(address, size, flags & MAP_FIXED, mask);
  if(address == -1) {
    fprintf(stderr, "reserve failed[%s->%s:%d]: addr=0x%x\n", __FILE__, __func__, __LINE__, address);
    return -1;
  }

  if ((protection & PROT_EXEC) != 0 && fildes != -1 && size > 0x1000 && off == 0) {
    // write for Debug
    protection |= PROT_WRITE;
    flags |= MAP_PRIVATE;
    flags &= ~MAP_SHARED;
  }

  off_t aligned_off = off & ~(PAGE_SIZE-1);
  u64 addr = (u64)mmap(NULL, size + (off - aligned_off), protection & ~PROT_EXEC, flags & ~MAP_FIXED, fildes, aligned_off);
  if(addr == (u64)MAP_FAILED) {
    fprintf(stderr, "mmap failed[%s->%s:%d]: addr=%p\n", __FILE__, __func__, __LINE__, (void*)addr);
    return -1;
  }
  addr += off - aligned_off;

  printf("DBG: mmaping host 0x%llx to 0x%x\n", addr, address);

  for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
    u64 idx = vaddr >> DYN_PAGE_BITS;

    if(sharedHandle.page_table && idx < sharedHandle.num_page_table_entries) {
      sharedHandle.page_table[idx] = (void *)addr;
    } else {
      // 0xffffff80001f0000ULL: 0x10000
    }
    t_memory_page page = kh_value(memory, kh_get(memory, memory, vaddr));
    page->addr = (void *)addr;
    page->perms = protection;

    addr += DYN_PAGE_SIZE;
  }
  return address;
}

int Dynarmic_mprotect(u64 address, u64 size, int perms) {
  if(address & DYN_PAGE_MASK) {
    errno = EINVAL;
    return -1;
  }
  if(size == 0 || (size & DYN_PAGE_MASK)) {
    errno = EINVAL;
    return -1;
  }
  khash_t(memory) *memory = sharedHandle.memory;
  for(u64 vaddr = address; vaddr < address + size; vaddr += DYN_PAGE_SIZE) {
    khiter_t k = kh_get(memory, memory, vaddr);
    if(k == kh_end(memory)) {
      fprintf(stderr, "mem_protect failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
      errno = ENOMEM;
      return -1;
    }
    t_memory_page page = kh_value(memory, k);
    page->perms = perms;
  }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    mem_write
 * Signature: (JJ[B)I
 */
int Dynarmic_mem_1write(u64 address, u64 size, char* src) {
  u64 vaddr_end = address + size;
  for(u64 vaddr = address & ~DYN_PAGE_MASK; vaddr < vaddr_end; vaddr += DYN_PAGE_SIZE) {
    u64 start = vaddr < address ? address - vaddr : 0;
    u64 end = vaddr + DYN_PAGE_SIZE <= vaddr_end ? DYN_PAGE_SIZE : (vaddr_end - vaddr);
    u64 len = end - start;
    char *addr = get_memory_page(vaddr);
    if(addr == NULL) {
      fprintf(stderr, "mem_write failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
      return 1;
    }
    char *dest = &addr[start];
//    printf("mem_write address=%p, vaddr=%p, start=%ld, len=%ld, addr=%p, dest=%p\n", (void*)address, (void*)vaddr, start, len, addr, dest);
    memcpy(dest, src, len);
    src += len;
  }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    mem_read
 * Signature: (JJI)[B
 */
int Dynarmic_mem_1read(u64 address, u64 size, char* dest) {
  u64 vaddr_end = address + size;
  for(u64 vaddr = address & ~DYN_PAGE_MASK; vaddr < vaddr_end; vaddr += DYN_PAGE_SIZE) {
    u64 start = vaddr < address ? address - vaddr : 0;
    u64 end = vaddr + DYN_PAGE_SIZE <= vaddr_end ? DYN_PAGE_SIZE : (vaddr_end - vaddr);
    u64 len = end - start;
    char *addr = get_memory_page(vaddr);
    if(addr == NULL) {
      fprintf(stderr, "mem_read failed[%s->%s:%d]: vaddr=%p\n", __FILE__, __func__, __LINE__, (void*)vaddr);
      return 1;
    }
    char *src = (char *)&addr[start];
    memcpy(dest, src, len);
    dest += len;
  }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_write
 * Signature: (JIJ)I
 */
int Dynarmic_reg_1write(int index, u32 value) {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      jit->Regs()[index] = value;
    } else {
      return 1;
    }
  }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_read
 * Signature: (JI)J
 */
u32 Dynarmic_reg_1read(int index) {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      return jit->Regs()[index];
    } else {
      abort();
      return -1;
    }
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_read_cpsr
 * Signature: (J)I
 */
int Dynarmic_reg_1read_1cpsr() {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      return jit->Cpsr();
    } else {
      abort();
      return -1;
    }
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_write_cpsr
 * Signature: (JI)I
 */
int Dynarmic_reg_1write_1cpsr(int value) {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      jit->SetCpsr(value);
      return 0;
    } else {
      abort();
      return -1;
    }
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    reg_write_c13_c0_3
 * Signature: (JI)I
 */
int Dynarmic_reg_1write_1c13_1c0_13(int value) {
  {
    DynarmicCallbacks32 *cb = sharedHandle.cb;
    if(cb) {
      cb->cp15.get()->uro = value;
      return 0;
    } else {
      abort();
      return -1;
    }
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    emu_start
 * Signature: (JJ)I
 */
int Dynarmic_emu_1start(u32 pc) {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      Dynarmic::A32::Jit *cpu = jit;
      if(pc & 1) {
        cpu->SetCpsr(0x00000030); // Thumb user mode
      } else {
        cpu->SetCpsr(0x000001d0); // Arm user mode
      }
      cpu->Regs()[15] = (u32) (pc & ~1);
      while(cpu->Run() == LC32HaltReasonSVC) {
        sharedHandle.ucb->CallSVC(0x80);
      }
    } else {
      return 1;
    }
  }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    emu_stop
 * Signature: (J)I
 */
int Dynarmic_emu_1stop() {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    if(jit) {
      Dynarmic::A32::Jit *cpu = jit;
      cpu->HaltExecution();
    } else {
      return 1;
    }
  }
  return 0;
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_alloc
 * Signature: (J)J
 */
void* Dynarmic_context_1alloc() {
  {
    void *ctx = malloc(sizeof(struct context32));
    return ctx;
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_restore
 * Signature: (JJ)V
 */
void Dynarmic_context_1restore(t_context32 ctx) {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    jit->Regs() = ctx->regs;
    jit->ExtRegs() = ctx->extRegs;
    jit->SetCpsr(ctx->cpsr);
    jit->SetFpscr(ctx->fpscr);

    DynarmicCallbacks32 *cb = sharedHandle.cb;
    cb->cp15.get()->uro = ctx->uro;
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    context_save
 * Signature: (JJ)V
 */
void Dynarmic_context_1save(t_context32 ctx) {
  {
    Dynarmic::A32::Jit *jit = threadHandle.jit;
    ctx->regs = jit->Regs();
    ctx->extRegs = jit->ExtRegs();
    ctx->cpsr = jit->Cpsr();
    ctx->fpscr = jit->Fpscr();

    DynarmicCallbacks32 *cb = sharedHandle.cb;
    ctx->uro = cb->cp15.get()->uro;
  }
}

/*
 * Class:     com_github_unidbg_arm_backend_dynarmic_Dynarmic
 * Method:    free
 * Signature: (J)V
 */
void Dynarmic_free(void *ctx) {
  free(ctx);
}

#ifdef __cplusplus
}
#endif
