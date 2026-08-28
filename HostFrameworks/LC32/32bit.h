#pragma once

#include <mach/task.h>
#include <sys/signal.h>
#include <sys/stat.h>

// dyld
#define DYLD_PROCESS_INFO_NOTIFY_LOAD_ID                        0x1000
#define DYLD_PROCESS_INFO_NOTIFY_UNLOAD_ID                      0x2000
#define DYLD_PROCESS_INFO_NOTIFY_MAIN_ID                        0x3000

struct dyld_all_image_infos_32 {
    uint32_t        version;
    uint32_t        infoArrayCount;
    uint32_t        infoArray;
    uint32_t        notification;
    bool            processDetachedFromSharedRegion;
    bool            libSystemInitialized;
    uint32_t        dyldImageLoadAddress;
    uint32_t        jitInfo;
    uint32_t        dyldVersion;
    uint32_t        errorMessage;
    uint32_t        terminationFlags;
    uint32_t        coreSymbolicationShmPage;
    uint32_t        systemOrderFlag;
    uint32_t        uuidArrayCount;
    uint32_t        uuidArray;
    uint32_t        dyldAllImageInfosAddress;
    uint32_t        initialImageCount;
    uint32_t        errorKind;
    uint32_t        errorClientOfDylibPath;
    uint32_t        errorTargetDylibPath;
    uint32_t        errorSymbol;
    uint32_t        sharedCacheSlide;
    uint8_t         sharedCacheUUID[16];
    uint32_t        sharedCacheBaseAddress;
    uint64_t        infoArrayChangeTimestamp;
    uint32_t        dyldPath;
    uint32_t        notifyMachPorts[2];
    uint32_t        reserved[11];
};

struct dyld_process_info_image_entry {
    uuid_t                                              uuid;
    uint64_t                    loadAddress;
    uint32_t                    pathStringOffset;
    uint32_t                    pathLength;
};

struct dyld_process_info_notify_header {
    mach_msg_header_t                       header;
    uint32_t                    version;
    uint32_t                    imageCount;
    uint32_t                    imagesOffset;
    uint32_t                    stringsOffset;
    uint64_t                    timestamp;
};

// Others
struct objc_method_32 {
    uint32_t method_name;
    uint32_t method_types;
    uint32_t method_imp;
};

struct sigaction_32 {
#if 0
  union {
    void    (*__sa_handler)(int);
    void    (*__sa_sigaction)(int, struct __siginfo *, void *);
  } __sigaction_u;                /* signal handler */
#endif
  uint32_t _sa_handler;
  int     sa_flags;               /* see signal options below */
  sigset_t sa_mask;               /* signal mask to apply */
};

struct timespec_32 {
	int tv_sec;
	int tv_nsec;
};

struct timeval_32 {
	int32_t tv_sec;
	int32_t tv_usec;
};

struct __attribute__((__packed__)) stat_32 {
	dev_t		st_dev;                 /* [XSI] ID of device containing file */
	mode_t		st_mode;                /* [XSI] Mode of file (see below) */
	nlink_t		st_nlink;               /* [XSI] Number of hard links */
	__darwin_ino64_t st_ino;                /* [XSI] File serial number */
	uid_t		st_uid;                 /* [XSI] User ID of the file */
	gid_t		st_gid;                 /* [XSI] Group ID of the file */
	dev_t		st_rdev;                /* [XSI] Device ID */
	struct timespec_32 st_atimespec;           /* time of last access */
	struct timespec_32 st_mtimespec;           /* time of last data modification */
	struct timespec_32 st_ctimespec;           /* time of last status change */
	struct timespec_32 st_birthtimespec;       /* time of file creation(birth) */
	//__DARWIN_STRUCT_STAT64_TIMES
	off_t		st_size;                /* [XSI] file size, in bytes */
	blkcnt_t	st_blocks;              /* [XSI] blocks allocated for file */
	blksize_t	st_blksize;             /* [XSI] optimal blocksize for I/O */
	__uint32_t	st_flags;               /* user defined flags for file */
	__uint32_t	st_gen;                 /* file generation number */
	__int32_t	st_lspare;              /* RESERVED: DO NOT USE! */
	__int64_t	st_qspare[2];           /* RESERVED: DO NOT USE! */
};
