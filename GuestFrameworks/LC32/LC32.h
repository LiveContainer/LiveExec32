@import ObjectiveC;
#import <Foundation/Foundation.h>

#define CRSetCrashLogMessage(msg) __assert_rtn(NULL, __FILE__, __LINE__, msg)
#define HALT __builtin_trap()

@interface NSObject(LC32)
- (instancetype)initWithHostSelf:(uint64_t)host_self;
- (void)bindHostSelf:(uint64_t)ptr;
- (uint64_t)host_self;
- (void)setHost_self:(uint64_t)ptr;
@end

uint64_t LC32Dlsym(const char *name, BOOL isFunction);

uint32_t LC32InvokeHostCRet32(uint64_t hostPtr, ...);

// Used to make guest call from host. r12 is guest function pointer. It then issues svc 1009 to halt itself to return execution back to the host
uint64_t LC32InvokeGuestC();

// Returns an address pointing to either direct memory mapped to the guest, or copied in case its boundary exceeds a guest page
// TODO: For now, this should be read-only. There is currently no mechanism to flush the copied buffer back
uint64_t LC32GuestToHostCString(const char *string, size_t length);

// Free the C string if it was copied
void LC32GuestToHostCStringFree(uint64_t string);

// Copy class name from host to guest
uint32_t LC32HostToGuestCopyClassName(char *output, size_t length, uint64_t host_input);

// Converts host class to guest class
Class LC32HostToGuestClass(uint64_t address);

// Get the guest object pointer from host
id LC32HostToGuestObject(uint64_t host_object);

// Returns host SEL address
uint64_t LC32GetHostSelector(SEL selector);

// Invoke host objc_msgSend. All arguments must be 64-bit aligned with an exception below:
// If the most significant bit of selector is set, 2 additional uint32_t arguments are reserved for return struct pointer and size
uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...);

// Get the host class pointer. If returnClass is false, it returns [clsss alloc]
uint64_t LC32GetHostObject(id self, const char *name, bool returnClass);
