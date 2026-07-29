#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/mach_traps.h>

__BEGIN_DECLS

#define DTRACEHIOC              (('d' << 24) | ('t' << 16) | ('h' << 8))
#define DTRACEHIOC_ADD          (DTRACEHIOC | 1)        /* add helper */
#define DTRACEHIOC_REMOVE       (DTRACEHIOC | 2)        /* remove helper */
#define DTRACEHIOC_ADDDOF       (DTRACEHIOC | 3)        /* add helper DOF */

#define PTHREAD_FEATURE_DISPATCHFUNC	0x01		/* same as WQOPS_QUEUE_NEWSPISUPP, checks for dispatch function support */
#define PTHREAD_FEATURE_FINEPRIO		0x02		/* are fine grained prioirities available */
#define PTHREAD_FEATURE_BSDTHREADCTL	0x04		/* is the bsdthread_ctl syscall available */
#define PTHREAD_FEATURE_SETSELF			0x08		/* is the BSDTHREAD_CTL_SET_SELF command of bsdthread_ctl available */
#define PTHREAD_FEATURE_QOS_MAINTENANCE	0x10		/* is QOS_CLASS_MAINTENANCE available */
#define PTHREAD_FEATURE_RESERVED		0x20		/* burnt, shipped in OSX 10.11 & iOS 9 with partial kevent delivery support */
#define PTHREAD_FEATURE_KEVENT          0x40		/* supports direct kevent delivery */
#define PTHREAD_FEATURE_WORKLOOP          0x80		/* supports workloops */
#define PTHREAD_FEATURE_QOS_DEFAULT		0x40000000	/* the kernel supports QOS_CLASS_DEFAULT */

/* iOS 10.3 libpthread workq_kernreturn operations. */
#define WQOPS_THREAD_RETURN                 0x04
#define WQOPS_QUEUE_NEWSPISUPP              0x10
#define WQOPS_QUEUE_REQTHREADS              0x20
#define WQOPS_QUEUE_REQTHREADS2             0x30
#define WQOPS_THREAD_KEVENT_RETURN          0x40
#define WQOPS_SET_EVENT_MANAGER_PRIORITY    0x80

#define KEVENT_FLAG_IMMEDIATE                0x001
#define KEVENT_FLAG_ERROR_EVENTS             0x002
#define KEVENT_FLAG_WORKQ                    0x020

// Others

#define PROC_PIDT_SHORTBSDINFO		13
#define PROC_PIDT_SHORTBSDINFO_SIZE	(sizeof(struct proc_bsdshortinfo))

struct proc_bsdshortinfo {
	uint32_t                pbsi_pid;		/* process id */
	uint32_t                pbsi_ppid;		/* process parent id */
	uint32_t                pbsi_pgid;		/* process perp id */
	uint32_t                pbsi_status;		/* p_stat value, SZOMB, SRUN, etc */
	char                    pbsi_comm[MAXCOMLEN];	/* upto 16 characters of process name */
	uint32_t                pbsi_flags;              /* 64bit; emulated etc */
	uid_t                   pbsi_uid;		/* current uid on process */
	gid_t                   pbsi_gid;		/* current gid on process */
	uid_t                   pbsi_ruid;		/* current ruid on process */
	gid_t                   pbsi_rgid;		/* current tgid on process */
	uid_t                   pbsi_svuid;		/* current svuid on process */
	gid_t                   pbsi_svgid;		/* current svgid on process */
	uint32_t                pbsi_rfu;		/* reserved for future use*/
};

struct iovec_32 {
    uint32_t guest_iov_base;  /* Base address. */
    size_t iov_len;    /* Length. */
};

struct crashreporter_annotations_t {
	uint64_t version;		// unsigned long
	uint64_t message;		// char *
	uint64_t signature_string;	// char *
	uint64_t backtrace;		// char *
	uint64_t message2;		// char *
	uint64_t thread;		// uint64_t
	uint64_t dialog_mode;		// unsigned int
	uint64_t abort_cause;		// uint64_t
};

// Mach private

#ifdef  __MigPackStructs
#pragma pack(push, 4)
#endif
typedef struct {
	mach_msg_header_t Head;
	char payload[];
} __Request___xpc_send_serializer_t __attribute__((unused));

typedef struct {
	mach_msg_header_t Head;
	NDR_record_t NDR;
	kern_return_t RetCode;
} __Reply___xpc_send_serializer_t __attribute__((unused));

typedef struct {
	mach_msg_header_t Head;
	mach_msg_body_t msgh_body;
	mach_msg_ool_descriptor_t name;
	NDR_record_t NDR;
	mach_msg_type_number_t nameCnt;
} __Request___notify_server_register_check_t __attribute__((unused));

typedef struct {
	mach_msg_header_t Head;
	NDR_record_t NDR;
	kern_return_t RetCode;
	int size;
	int slot;
	int token;
	int status;
} __Reply___notify_server_register_check_t __attribute__((unused));

typedef struct {
	mach_msg_header_t Head;
	NDR_record_t NDR;
	int token;
} __Request___notify_server_check_t __attribute__((unused));

typedef struct {
	mach_msg_header_t Head;
	NDR_record_t NDR;
	kern_return_t RetCode;
	int check;
	int status;
} __Reply___notify_server_check_t __attribute__((unused));
#ifdef  __MigPackStructs
#pragma pack(pop)
#endif

typedef struct {
	/* a mach_msg_header_t* or mach_msg_aux_header_t* */
	mach_vm_address_t               msgv_data;
	/* if msgv_rcv_addr is non-zero, use it as rcv address instead */
	mach_vm_address_t               msgv_rcv_addr;
	mach_msg_size_t                 msgv_send_size;
	mach_msg_size_t                 msgv_rcv_size;
} mach_msg_vector_t;

__options_decl(mach_msg_option64_t, uint64_t, {
	MACH64_MSG_OPTION_NONE                 = 0x0ull,
	/* share lower 32 bits with mach_msg_option_t */
	MACH64_SEND_MSG                        = MACH_SEND_MSG,
	MACH64_RCV_MSG                         = MACH_RCV_MSG,

	MACH64_RCV_LARGE                       = MACH_RCV_LARGE,
	MACH64_RCV_LARGE_IDENTITY              = MACH_RCV_LARGE_IDENTITY,

	MACH64_SEND_TIMEOUT                    = MACH_SEND_TIMEOUT,
	MACH64_SEND_OVERRIDE                   = MACH_SEND_OVERRIDE,
	MACH64_SEND_INTERRUPT                  = MACH_SEND_INTERRUPT,
	MACH64_SEND_NOTIFY                     = MACH_SEND_NOTIFY,
#if KERNEL
	MACH64_SEND_ALWAYS                     = MACH_SEND_ALWAYS,
	MACH64_SEND_IMPORTANCE                 = MACH_SEND_IMPORTANCE,
	MACH64_SEND_KERNEL                     = MACH_SEND_KERNEL,
#endif
	MACH64_SEND_FILTER_NONFATAL            = MACH_SEND_FILTER_NONFATAL,
	MACH64_SEND_TRAILER                    = MACH_SEND_TRAILER,
	MACH64_SEND_NOIMPORTANCE               = MACH_SEND_NOIMPORTANCE,
	MACH64_SEND_NODENAP                    = MACH_SEND_NODENAP,
	MACH64_SEND_SYNC_OVERRIDE              = MACH_SEND_SYNC_OVERRIDE,
	MACH64_SEND_PROPAGATE_QOS              = MACH_SEND_PROPAGATE_QOS,

	MACH64_SEND_SYNC_BOOTSTRAP_CHECKIN     = MACH_SEND_SYNC_BOOTSTRAP_CHECKIN,

	MACH64_RCV_TIMEOUT                     = MACH_RCV_TIMEOUT,

	MACH64_RCV_INTERRUPT                   = MACH_RCV_INTERRUPT,
	MACH64_RCV_VOUCHER                     = MACH_RCV_VOUCHER,

	MACH64_RCV_GUARDED_DESC                = MACH_RCV_GUARDED_DESC,
	MACH64_RCV_SYNC_WAIT                   = MACH_RCV_SYNC_WAIT,
	MACH64_RCV_SYNC_PEEK                   = MACH_RCV_SYNC_PEEK,

	MACH64_MSG_STRICT_REPLY                = MACH_MSG_STRICT_REPLY,
	/* following options are 64 only */

	/* Send and receive message as vectors */
	MACH64_MSG_VECTOR                      = 0x0000000100000000ull,
	/* The message is a kobject call */
	MACH64_SEND_KOBJECT_CALL               = 0x0000000200000000ull,
	/* The message is sent to a message queue */
	MACH64_SEND_MQ_CALL                    = 0x0000000400000000ull,
	/* This message destination is unknown. Used by old simulators only. */
	MACH64_SEND_ANY                        = 0x0000000800000000ull,
	/* This message is a DriverKit call */
	MACH64_SEND_DK_CALL                    = 0x0000001000000000ull,

#ifdef XNU_KERNEL_PRIVATE
	/*
	 * Policy for the mach_msg2_trap() call
	 */
	MACH64_POLICY_KERNEL_EXTENSION         = 0x0002000000000000ull,
	MACH64_POLICY_FILTER_NON_FATAL         = 0x0004000000000000ull,
	MACH64_POLICY_FILTER_MSG               = 0x0008000000000000ull,
	MACH64_POLICY_DEFAULT                  = 0x0010000000000000ull,
#if XNU_TARGET_OS_OSX
	MACH64_POLICY_SIMULATED                = 0x0020000000000000ull,
#else
	MACH64_POLICY_SIMULATED                = 0x0000000000000000ull,
#endif
#if CONFIG_ROSETTA
	MACH64_POLICY_TRANSLATED               = 0x0040000000000000ull,
#else
	MACH64_POLICY_TRANSLATED               = 0x0000000000000000ull,
#endif
	MACH64_POLICY_HARDENED                 = 0x0080000000000000ull,
	MACH64_POLICY_RIGID                    = 0x0100000000000000ull,
	MACH64_POLICY_PLATFORM                 = 0x0200000000000000ull,
	MACH64_POLICY_KERNEL                   = MACH64_SEND_KERNEL,

	/* one of these bits must be set to have a valid policy */
	MACH64_POLICY_NEEDED_MASK              = (
		MACH64_POLICY_SIMULATED |
		MACH64_POLICY_TRANSLATED |
		MACH64_POLICY_DEFAULT |
		MACH64_POLICY_HARDENED |
		MACH64_POLICY_RIGID |
		MACH64_POLICY_PLATFORM |
		MACH64_POLICY_KERNEL),

	/* extra policy modifiers */
	MACH64_POLICY_MASK                     = (
		MACH64_POLICY_KERNEL_EXTENSION |
		MACH64_POLICY_FILTER_NON_FATAL |
		MACH64_POLICY_FILTER_MSG |
		MACH64_POLICY_NEEDED_MASK),

	/*
	 * If kmsg has auxiliary data, append it immediate after the message
	 * and trailer.
	 *
	 * Must be used in conjunction with MACH64_MSG_VECTOR,
	 * only used by kevent() from the kernel.
	 */
	MACH64_RCV_LINEAR_VECTOR               = 0x1000000000000000ull,
	/* Receive into highest addr of buffer */
	MACH64_RCV_STACK                       = 0x2000000000000000ull,
#if MACH_FLIPC
	/*
	 * This internal-only flag is intended for use by a single thread per-port/set!
	 * If more than one thread attempts to MACH64_PEEK_MSG on a port or set, one of
	 * the threads may miss messages (in fact, it may never wake up).
	 */
	MACH64_PEEK_MSG                        = 0x4000000000000000ull,
#endif /* MACH_FLIPC */
	/*
	 * This is a mach_msg2() send/receive operation.
	 */
	MACH64_MACH_MSG2                       = 0x8000000000000000ull
#endif
});

// https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/message.h#L1481-L1528
extern mach_msg_return_t mach_msg2_internal(
	void *data,
	mach_msg_option64_t option64,
	uint64_t msgh_bits_and_send_size,
	uint64_t msgh_remote_and_local_port,
	uint64_t msgh_voucher_and_id,
	uint64_t desc_count_and_rcv_name,
	uint64_t rcv_size_and_priority,
	uint64_t timeout);
static inline mach_msg_return_t
mach_msg2(
	void *data,
	mach_msg_option64_t option64,
	mach_msg_header_t header,
	mach_msg_size_t send_size,
	mach_msg_size_t rcv_size,
	mach_port_t rcv_name,
	uint64_t timeout,
	uint32_t priority)
{
	mach_msg_base_t *base;
	mach_msg_size_t descriptors;

	if (option64 & MACH64_MSG_VECTOR) {
		base = (mach_msg_base_t *)((mach_msg_vector_t *)data)->msgv_data;
	} else {
		base = (mach_msg_base_t *)data;
	}

	if ((option64 & MACH64_SEND_MSG) &&
	    (base->header.msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
		descriptors = base->body.msgh_descriptor_count;
	} else {
		descriptors = 0;
	}

#define MACH_MSG2_SHIFT_ARGS(lo, hi) ((uint64_t)hi << 32 | (uint32_t)lo)
	return mach_msg2_internal(data, option64,
	           MACH_MSG2_SHIFT_ARGS(header.msgh_bits, send_size),
	           MACH_MSG2_SHIFT_ARGS(header.msgh_remote_port, header.msgh_local_port),
	           MACH_MSG2_SHIFT_ARGS(header.msgh_voucher_port, header.msgh_id),
	           MACH_MSG2_SHIFT_ARGS(descriptors, rcv_name),
	           MACH_MSG2_SHIFT_ARGS(rcv_size, priority), timeout);
#undef MACH_MSG2_SHIFT_ARGS
}

int __proc_info(int callnum, int pid, int flavor, uint64_t arg, void * buffer, int buffersize);

// Mach private

extern mach_port_name_t mach_reply_port(void);

extern mach_port_name_t thread_self_trap(void);

extern mach_port_name_t host_self_trap(void);

extern mach_msg_return_t mach_msg_trap(
	mach_msg_header_t *msg,
	mach_msg_option_t option,
	mach_msg_size_t send_size,
	mach_msg_size_t rcv_size,
	mach_port_name_t rcv_name,
	mach_msg_timeout_t timeout,
	mach_port_name_t notify);

extern mach_msg_return_t mach_msg_overwrite_trap(
	mach_msg_header_t *msg,
	mach_msg_option_t option,
	mach_msg_size_t send_size,
	mach_msg_size_t rcv_size,
	mach_port_name_t rcv_name,
	mach_msg_timeout_t timeout,
	mach_msg_priority_t priority,
	mach_msg_header_t *rcv_msg,
	mach_msg_size_t rcv_limit);

extern kern_return_t semaphore_signal_trap(
	mach_port_name_t signal_name);

extern kern_return_t semaphore_signal_all_trap(
	mach_port_name_t signal_name);

extern kern_return_t semaphore_signal_thread_trap(
	mach_port_name_t signal_name,
	mach_port_name_t thread_name);

extern kern_return_t semaphore_wait_trap(
	mach_port_name_t wait_name);

extern kern_return_t semaphore_wait_signal_trap(
	mach_port_name_t wait_name,
	mach_port_name_t signal_name);

extern kern_return_t semaphore_timedwait_trap(
	mach_port_name_t wait_name,
	unsigned int sec,
	clock_res_t nsec);

extern kern_return_t semaphore_timedwait_signal_trap(
	mach_port_name_t wait_name,
	mach_port_name_t signal_name,
	unsigned int sec,
	clock_res_t nsec);

// XPC private
extern kern_return_t _xpc_send_serializer(mach_port_t port, const char *payload);

// FIXME: uint64_t
extern uint32_t __thread_selfid(void);
extern void _pthread_set_self(pthread_t);

extern int __semwait_signal_nocancel(int, int, int, int, int64_t, int32_t);

extern int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
extern int __sysctlbyname(const char *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

size_t __getdirentries64(int fd, void *buf, size_t bufsize, __darwin_off_t *basep);

int getentropy(void *buffer, size_t length);

__END_DECLS
