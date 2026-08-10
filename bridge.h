#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>
#include "32bit.h"
#include "dynarmic.h"

#define SEL_RETURN_STRUCT ((u64)1 << 63)

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

// dummy function to get and set double registers. CGAffineTransform takes up to 6 doubles
LC32_SixDoubles LC32GetDoubleRegisters();
void LC32SetDoubleRegisters(double d0, double d1, double d2, double d3, double d4, double d5);

u32 LC32HostToGuestCopyClassName(u32 guest_output, size_t length, u64 host_object);
u32 LC32CopyHostStringUTF8(u64 host_object, u32 guest_output, size_t capacity);
u32 LC32CopyHostDataBytes(u64 host_object, u32 guest_output, u32 length,
                          u32 offset);
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
u32 guest_protocol_getName(u32 guest_ivar);
u32 guest_sel_registerName(const char *host_name);
u32 guest_objc_getClass(const char *name);
Class guest_objc_getClass_retHostClass(const char *name);
u64 guest_objc_msgSend(int argc, u32 *args);
BOOL host_hook_getClass(const char *name, Class *outClass);

__END_DECLS
