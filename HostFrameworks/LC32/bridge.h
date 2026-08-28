#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
#include "LC32FoundationBridgeABI.h"
#include "LC32ObjCBridgeABI.h"
#include "32bit.h"
#include "dynarmic.h"

#define SEL_RETURN_STRUCT LC32_HOST_SELECTOR_RETURN_STRUCT
#define SEL_RETURN_GUEST_OBJECT LC32_HOST_SELECTOR_RETURN_GUEST_OBJECT

__BEGIN_DECLS

typedef struct LC32_stret {
    char *stretAddr;
    u64 self; // or objc_super
} LC32_stret;

typedef struct LC32_SixDoubles {
    double value[6];
} TEMP_SixDoubles;

void LC32_objc_msgSend_stret(/* LC32_stret stret, SEL sel, ... */);
void LC32_objc_msgSendSuper_stret(/* LC32_stret stret, SEL sel, ... */);

extern int __CFConstantStringClassReference[];

@interface NSObject(LC32)
- (void)setGuestClass:(BOOL)value;
- (BOOL)isGuestClass;
- (void)setGuest_self:(u32)ptr;
- (u32)guest_selfOrNull;
- (u32)LC32_bindGuestSelfIfAbsent:(u32)ptr;
- (u32)guest_self;
@end

// Dummy calls used to read or seed the AAPCS64 floating-point registers.
LC32_SixDoubles LC32GetDoubleRegisters();
void LC32SetDoubleRegisters(double d0, double d1, double d2, double d3,
                            double d4, double d5, double d6, double d7);

u32 LC32HostToGuestCopyClassName(u32 guest_output, size_t length, u64 host_object);
// Copies a raw host C string into guest memory, returning the required byte
// count including the terminating NUL.
u32 LC32CopyHostCString(u64 host_cstring, u32 guest_output, size_t capacity);
u32 LC32CopyHostStringUTF8(u64 host_object, u32 guest_output, size_t capacity);
u32 LC32CopyHostStringBytes(u64 host_object, u32 encoding,
                            u32 guest_output, u32 capacity);
u64 LC32HostStringRangeOfString(
    const LC32FoundationStringRangeRequest *request);
u32 LC32CopyHostDataBytes(u64 host_object, u32 guest_output, u32 length,
                          u32 offset);
// Converts a native +1 result (Create/Copy/alloc rule) to its guest proxy.
// If the native object already has a proxy, this also creates the matching
// guest-only +1; the native +1 is released later by the guest's public release.
u32 LC32GuestObjectForOwnedHostObject(CFTypeRef object);
// Objective-C equivalent of LC32GuestObjectForOwnedHostObject. The caller
// transfers a +1 result from an alloc/new/copy/mutableCopy method family.
u32 LC32GuestObjectForOwnedHostObjectAddress(u64 object);
// SVC 1019 host half. A non-sentinel result is an opaque pending-retain token.
LC32HostWeakRetainResult LC32TryRetainHostWeakReference(u32 guest_object);
// SVC 1021 commits or rolls back the token's exact native +1.
u32 LC32FinishHostWeakRetain(u32 token, u32 guest_object, u32 commit);
// Native authoritative guest-to-host mapping used instead of guest libobjc's
// associated-object table. Lookup returns a borrowed raw host address.
u64 LC32LookupHostMapping(u32 guest_object);
u32 LC32UpdateHostMapping(u32 guest_object,
                          LC32HostMappingOperation operation,
                          u64 host_object);
//u64 LC32Dlsym(u32 guest_name);
u64 LC32GetHostObject(u32 guest_self, u32 guest_class, bool returnClass);
u64 LC32GetHostSelector(u32 guest_selector);
u64 LC32InvokeHostSelector(u64 host_self, u64 host_cmd, u64 va_args);
u64 LC32InvokeHostNSStringFormat(u64 host_self,
                                 u64 host_selector,
                                 u64 host_format,
                                 u64 host_locale,
                                 u32 guest_arguments,
                                 u32 options);
void LC32SetInvokeGuestFuncPtr(u32 dlsymFunc, u32 invokeFunc);
u64 LC32InvokeGuestC(u32 pc, bool ret64, int argc, u32 *args);
// Guest blocks use the Blocks runtime rather than NSObject retain/release.
// Copying turns a stack block into stable guest storage; release is deferred
// when a native block dies on a thread which is not registered with the JIT.
u32 LC32CopyGuestBlock(u32 guest_block);
void LC32ReleaseGuestBlock(u32 guest_block);
u64 LC32CreateHostBlock(u32 guest_block);
u32 LC32HostToGuestArgument(char *type, u64 value);
u64 LC32GuestToHostReturnType(char *type, u64 value);
u64 LC32InvokeGuestSelector(id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4, u64 arg5, u64 arg6, u64 arg7, ...);
u32 guest_dlsym(const char *host_name);
u32 guest_free(u32 guest_ptr);
u32 guest_class_copyIvarList(u32 guest_cls, unsigned int *outCount);
u32 guest_class_copyMethodList(u32 guest_cls, unsigned int *outCount);
u32 guest_class_copyProtocolList(u32 guest_cls, unsigned int *outCount);
u32 guest_class_createInstance(u32 guest_cls, u32 extraBytes);
u32 guest_class_getClassMethod(u32 guest_cls, u32 guest_sel);
u32 guest_class_getInstanceMethod(u32 guest_cls, u32 guest_sel);
u32 guest_class_getName(u32 guest_cls);
u32 guest_class_getSuperclass(u32 guest_cls);
u32 guest_ivar_getName(u32 guest_ivar);
u32 guest_ivar_getTypeEncoding(u32 guest_ivar);
u32 guest_object_getClass(u32 guest_obj);
u32 guest_object_setInstanceVariable(u32 guest_obj, const char *host_name, u32 newValue);
u32 guest_object_getInstanceVariable(u32 guest_obj, const char *host_name, u32 *outValue);
u32 guest_protocol_getName(u32 guest_ivar);
u32 guest_sel_registerName(const char *host_name);
u32 guest_objc_getClass(const char *name);
Class guest_objc_getClass_retHostClass(const char *name);
u64 guest_objc_msgSend(int argc, u32 *args);
BOOL host_hook_getClass(const char *name, Class *outClass);
// Lets framework bridges add native compatibility entry points after all
// guest methods have been mirrored but before the class is registered.
void LC32UIKitPrepareGuestClass(Class cls);

__END_DECLS
