#import "bridge.h"
#include "LC32ObjCBridgeABI.h"

#include <atomic>
#include <memory>
#include <mutex>
#include <new>
#include <stdarg.h>
#include <vector>

// These Objective-C runtime entry points let the ARC-built host transfer an
// existing +1 without introducing another ARC-managed strong local.
extern "C" id objc_autorelease(id object);
extern "C" void objc_release(id object);
extern "C" id objc_retain(id object);

#if __has_feature(objc_arc)
static void LC32ObjCAutoreleaseWithoutARC(id object) {
    (void)objc_autorelease(object);
}
#endif

static void LC32ObjCRetainWithoutARC(id object) {
    (void)objc_retain(object);
}

@interface LC32ObjCMethodResolver : NSObject
+ (void)registerClass:(Class)cls;
@end

static void LC32PinGuestObjectToHost(id hostObject, u32 guestObject,
                                     bool retainGuestObject);
static void LC32DrainDeferredGuestPinReleases();

static int LC32UniqueSelectorArgumentIndexNamed(SEL selector,
                                                 const char *expectedName) {
    const char *component = sel_getName(selector);
    const size_t expectedLength = strlen(expectedName);
    int matchingIndex = -1;
    unsigned int argumentIndex = 0;
    while(component) {
        const char *colon = strchr(component, ':');
        if(!colon) break;
        if((size_t)(colon - component) == expectedLength &&
           memcmp(component, expectedName, expectedLength) == 0) {
            if(matchingIndex >= 0) return -1;
            matchingIndex = (int)argumentIndex;
        }
        component = colon + 1;
        argumentIndex++;
    }
    return matchingIndex;
}

#pragma mark Guest -> Host functions

u32 LC32HostToGuestCopyClassName(u32 guest_output, size_t length, u64 host_object) {
    const char *input = class_getName([(id)host_object class]);
    length = MIN(strlen(input), length);
    // write null terminator aswell
    Dynarmic_mem_1write(guest_output, length+1, (char *)input);
    return length;
}

u32 LC32CopyHostStringUTF8(u64 host_object, u32 guest_output,
                           size_t capacity) {
    const char *bytes = [(NSString *)(id)host_object UTF8String];
    if(!bytes) return 0;

    const size_t byteCount = strlen(bytes) + 1;
    if(byteCount > UINT32_MAX) return 0;
    if(guest_output && capacity) {
        const size_t copyCount = MIN(byteCount, capacity);
        if(Dynarmic_mem_1write(guest_output, copyCount, (char *)bytes) != 0) {
            return 0;
        }
        if(copyCount < byteCount) {
            const char terminator = '\0';
            if(Dynarmic_mem_1write(guest_output + copyCount - 1, 1,
                                   (char *)&terminator) != 0) {
                return 0;
            }
        }
    }
    return (u32)byteCount;
}

u32 LC32CopyHostDataBytes(u64 host_object, u32 guest_output, u32 length,
                          u32 offset) {
    NSData *data = (NSData *)(id)host_object;
    const NSUInteger dataLength = data.length;
    if(offset > dataLength || length > dataLength - offset) {
        return UINT32_MAX;
    }
    if(!length) return 0;

    const void *bytes = data.bytes;
    if(!bytes || !guest_output || Dynarmic_mem_1write(
            guest_output, length,
            (char *)bytes + offset) != 0) {
        return UINT32_MAX;
    }
    return length;
}

u64 LC32Dlsym(u32 guest_name, bool isFunction) {
    DynarmicHostString host_name(guest_name);
    
    u64 r = (u64)dlsym(RTLD_DEFAULT, host_name.hostPtr);
    if(r && !isFunction) r = *(u64*)r;
    printf("LC32: dlsym %s = 0x%llx\n", host_name.hostPtr, r);
    return r;
}

inline id LC32GetHostConstString(u32 guest_self) {
    // Construct a __NSCFConstantString { isa, flags, buffer, length }
    u64 *constStr = (u64 *)malloc(sizeof(u64[4]));
    constStr[0] = (u64)__CFConstantStringClassReference;
    constStr[1] = (u64)Dynarmic_current_user_callbacks()->MemoryRead32(guest_self + sizeof(u32[1]));
    u64 length = (u64)Dynarmic_current_user_callbacks()->MemoryRead32(guest_self + sizeof(u32[3]));
    DynarmicHostString host_str(Dynarmic_current_user_callbacks()->MemoryRead32(guest_self + sizeof(u32[2])), length);
    constStr[2] = (u64)host_str.hostPtrForGuest();
    constStr[3] = length;
    return (id)constStr;
}

u64 LC32GetHostObject(u32 guest_self, u32 guest_className, bool returnClass) {
    DynarmicHostString host_className(guest_className);
    Class cls = objc_getClass(host_className.hostPtr);
    if(returnClass) {
        [(id)cls setGuest_self:guest_self];
        return (u64)cls;
    }

    const bool isGuestClass = [(id)cls isGuestClass];
    const bool isConstantStringClass =
        object_getClass(cls) ==
            object_getClass((Class)__CFConstantStringClassReference);
    id obj;
    if(isConstantStringClass) {
        obj = LC32GetHostConstString(guest_self);
    } else if(isGuestClass) {
        /*
         * The guest has already allocated this object; we only need a native
         * mirror with the same dynamic class.  Sending +alloc here can enter
         * a guest singleton's overridden +allocWithZone:, which asks for the
         * same host mirror again and recurses until the host stack overflows.
         */
        obj = class_createInstance(cls, 0);
    } else {
        obj = [cls alloc];
    }
    [obj setGuest_self:guest_self];
    if(isGuestClass) {
        // Dynamic guest classes have unique native allocations but no native
        // initializer shim where the final mirror can be pinned.
        LC32PinGuestObjectToHost(obj, guest_self, true);
    }
    return (u64)obj;
}

u64 LC32GetHostSelector(u32 guest_selector) {
    DynarmicHostString host_selector(guest_selector);
    return (u64)sel_registerName(host_selector.hostPtr);
}

// guest to host call of objc_msgSend*
u64 LC32InvokeHostSelector(u64 host_self, u64 host_cmd, u64 va_args) {
    // ARMv7 stores parameters in r0-r3 and stack pointer. r0-r3 is already reserved for self and cmd, so we read the rest from stack pointer

    u32 structPtr = 0, structLen;
    if(host_cmd & SEL_RETURN_STRUCT) {
        host_cmd &= ~SEL_RETURN_STRUCT;
        structPtr = Dynarmic_current_user_callbacks()->MemoryRead32(va_args);
        structLen = Dynarmic_current_user_callbacks()->MemoryRead32(va_args += sizeof(u32));
        va_args += sizeof(u32);
    }

    // FIXME: how to read number of args for variadic methods and translate its values?
    u64 args[9] = {
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64)),
        Dynarmic_current_user_callbacks()->MemoryRead64(va_args += sizeof(u64))
    };

    /*
     * A guest pointer cannot be handed to an ARM64 Objective-C method. Shim
     * sources tag pointers to 64-bit guest temporaries; substitute native
     * stack storage for objc_msgSend and copy the result back afterwards.
     * Looking at the method encoding prevents a negative scalar or floating
     * bit pattern from ever being mistaken for an indirect argument.
     */
    u32 indirectGuestStorage[9] = {};
    u64 indirectHostStorage[9] = {};
    std::unique_ptr<u64[]> objectArrayHostStorage[9];
    id receiver = (id)host_self;
    SEL selector = (SEL)host_cmd;
    Class dispatchClass = object_getClass(receiver);
    const bool invokeSuper = [(id)dispatchClass isGuestClass];
    if(invokeSuper) {
        do {
            dispatchClass = class_getSuperclass(dispatchClass);
        } while(dispatchClass && [(id)dispatchClass isGuestClass]);
    }
    Method method = dispatchClass
        ? class_getInstanceMethod(dispatchClass, selector)
        : nullptr;
    if(method) {
        const unsigned int argumentCount =
            MIN(method_getNumberOfArguments(method) - 2, 9u);
        for(unsigned int index = 0; index < argumentCount; index++) {
            char *argumentType =
                method_copyArgumentType(method, index + 2);
            if(!argumentType) continue;
            const char *unqualifiedType = argumentType;
            while(*unqualifiedType &&
                    strchr("rnNoORVA", *unqualifiedType)) {
                unqualifiedType++;
            }
            const u64 argumentTag =
                args[index] & LC32_GUEST_ARGUMENT_TAG_MASK;
            const bool isTaggedPointer =
                *unqualifiedType == '^' &&
                argumentTag == LC32_GUEST_INDIRECT_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            const bool isTaggedObjectArray =
                unqualifiedType[0] == '^' &&
                unqualifiedType[1] == '@' &&
                argumentTag == LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG &&
                (u32)args[index] != 0;
            free(argumentType);
            if(argumentTag == LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG &&
               !isTaggedObjectArray) {
                printf("LC32: refusing object-array argument %u for "
                       "non-object-pointer selector %s\n", index,
                       sel_getName(selector));
                return 0;
            }
            if(isTaggedObjectArray) {
                const u32 guestStorage = (u32)args[index];
                LC32HostObjectArrayDescriptor descriptor = {};
                const int selectorCountArgumentIndex =
                    LC32UniqueSelectorArgumentIndexNamed(selector, "count");
                if(Dynarmic_mem_1read(guestStorage, sizeof(descriptor),
                        reinterpret_cast<char *>(&descriptor)) != 0 ||
                   descriptor.magic != LC32_HOST_OBJECT_ARRAY_MAGIC ||
                   descriptor.reserved != 0 ||
                   descriptor.count > LC32_HOST_OBJECT_ARRAY_MAX_COUNT ||
                   selectorCountArgumentIndex < 0 ||
                   descriptor.countArgumentIndex !=
                       (u32)selectorCountArgumentIndex ||
                   descriptor.countArgumentIndex >= argumentCount ||
                   descriptor.countArgumentIndex == index) {
                    printf("LC32: invalid object-array descriptor for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    return 0;
                }

                char *countType = method_copyArgumentType(
                    method, descriptor.countArgumentIndex + 2);
                const char *unqualifiedCountType = countType;
                while(unqualifiedCountType && *unqualifiedCountType &&
                        strchr("rnNoORVA", *unqualifiedCountType)) {
                    unqualifiedCountType++;
                }
                const bool validCountType = unqualifiedCountType &&
                    strchr("CILQS", *unqualifiedCountType) != nullptr;
                free(countType);
                if(!validCountType ||
                   args[descriptor.countArgumentIndex] != descriptor.count) {
                    printf("LC32: mismatched object-array count for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    return 0;
                }

                const u64 objectBytes =
                    (u64)descriptor.count * sizeof(u64);
                const u64 objectAddress =
                    (u64)guestStorage + sizeof(descriptor);
                if(objectAddress + objectBytes > UINT64_C(0x100000000)) {
                    printf("LC32: overflowing object-array descriptor for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    return 0;
                }

                if(descriptor.count) {
                    objectArrayHostStorage[index].reset(
                        new(std::nothrow) u64[descriptor.count]);
                    if(!objectArrayHostStorage[index]) {
                        printf("LC32: cannot allocate object-array argument "
                               "%u of %s\n", index,
                               sel_getName(selector));
                        return 0;
                    }
                }
                if(objectBytes && Dynarmic_mem_1read(
                        (u32)objectAddress, (size_t)objectBytes,
                        reinterpret_cast<char *>(
                            objectArrayHostStorage[index].get())) != 0) {
                    printf("LC32: unreadable object-array descriptor for "
                           "argument %u of %s\n", index,
                           sel_getName(selector));
                    return 0;
                }
                args[index] = descriptor.count
                    ? (u64)objectArrayHostStorage[index].get()
                    : 0;
                continue;
            }
            if(!isTaggedPointer) continue;

            const u32 guestStorage = (u32)args[index];
            args[index] = 0;
            if(!guestStorage || Dynarmic_mem_1read(
                    guestStorage, sizeof(indirectHostStorage[index]),
                    reinterpret_cast<char *>(
                        &indirectHostStorage[index])) != 0) {
                continue;
            }
            indirectGuestStorage[index] = guestStorage;
            args[index] = (u64)&indirectHostStorage[index];
        }
    } else {
        for(size_t index = 0; index < 9; index++) {
            const u64 argumentTag =
                args[index] & LC32_GUEST_ARGUMENT_TAG_MASK;
            if((argumentTag != LC32_GUEST_INDIRECT_ARGUMENT_TAG &&
                argumentTag != LC32_GUEST_OBJECT_ARRAY_ARGUMENT_TAG) ||
               !(u32)args[index]) {
                continue;
            }
            printf("LC32: cannot marshal pointer argument %zu for "
                   "unresolved selector %s\n", index,
                   sel_getName(selector));
            return 0;
        }
    }

    auto finishIndirectArguments = [&](u64 result) -> u64 {
        for(size_t index = 0; index < 9; index++) {
            if(!indirectGuestStorage[index]) continue;
            (void)Dynarmic_mem_1write(
                indirectGuestStorage[index],
                sizeof(indirectHostStorage[index]),
                reinterpret_cast<char *>(
                    &indirectHostStorage[index]));
        }
        return result;
    };

    /*
     * AAPCS64 allocates scalar floating-point arguments and integer/pointer
     * arguments from independent register banks. The guest shim transports
     * each logical scalar in one 64-bit stack slot, so compact those slots by
     * host type before entering objc_msgSend. In particular, a leading
     * double belongs in d0 and must not also consume x2.
     *
     * Generated float arguments are promoted to double by the variadic guest
     * call. Convert them back to float and place their bits in the low half
     * of the corresponding v register. Keep the old raw-slot behavior for
     * aggregate arguments until their full AAPCS64 layout is described here.
     */
    u64 integerArguments[9] = {};
    u64 floatingArguments[8] = {};
    bool useTypedScalarArguments = method != nullptr;
    if(method) {
        const unsigned int argumentCount =
            method_getNumberOfArguments(method) - 2;
        size_t integerArgumentCount = 0;
        size_t floatingArgumentCount = 0;
        if(argumentCount > 9) useTypedScalarArguments = false;

        for(unsigned int index = 0;
                useTypedScalarArguments && index < argumentCount; index++) {
            char *argumentType =
                method_copyArgumentType(method, index + 2);
            const char *unqualifiedType = argumentType;
            while(unqualifiedType && *unqualifiedType &&
                    strchr("rnNoORVA", *unqualifiedType)) {
                unqualifiedType++;
            }

            switch(unqualifiedType ? *unqualifiedType : '\0') {
                case 'f': {
                    if(floatingArgumentCount >= 8) {
                        useTypedScalarArguments = false;
                        break;
                    }
                    double promotedValue;
                    memcpy(&promotedValue, &args[index],
                           sizeof(promotedValue));
                    const float hostValue = (float)promotedValue;
                    u32 hostBits;
                    memcpy(&hostBits, &hostValue, sizeof(hostBits));
                    floatingArguments[floatingArgumentCount++] = hostBits;
                    break;
                }
                case 'd':
                    if(floatingArgumentCount >= 8) {
                        useTypedScalarArguments = false;
                        break;
                    }
                    floatingArguments[floatingArgumentCount++] = args[index];
                    break;
                case '@':
                case '#':
                case ':':
                case '*':
                case '^':
                case '?':
                case 'B':
                case 'C':
                case 'I':
                case 'L':
                case 'Q':
                case 'S':
                case 'b':
                case 'c':
                case 'i':
                case 'l':
                case 'q':
                case 's':
                    integerArguments[integerArgumentCount++] = args[index];
                    break;
                default:
                    useTypedScalarArguments = false;
                    break;
            }
            free(argumentType);
        }
        if(useTypedScalarArguments) {
            /*
             * Objective-C metadata describes only the fixed portion of a
             * variadic method. Unnamed AAPCS64 arguments use the integer
             * vararg stream, so preserve the shim's remaining raw slots (and
             * its explicit zero terminator) after the typed fixed arguments.
             */
            for(size_t index = argumentCount;
                    index < 9 && integerArgumentCount < 9; index++) {
                integerArguments[integerArgumentCount++] = args[index];
            }
        }
    }
    if(!useTypedScalarArguments) {
        memcpy(integerArguments, args, sizeof(integerArguments));
        memcpy(floatingArguments, args, sizeof(floatingArguments));
    }

    typedef u64(*objc_msgSendFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef float(*objc_msgSendFloatFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef double(*objc_msgSendDoubleFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    struct LC32_TwoDoubles {
        double d0, d1;
    };
    struct LC32_FourDoubles {
        double d0, d1, d2, d3;
    };
    typedef LC32_TwoDoubles(*objc_msgSendTwoDoublesFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef LC32_FourDoubles(*objc_msgSendFourDoublesFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);
    typedef LC32_SixDoubles(*objc_msgSendSixDoublesFunc)(u64 x0, u64 x1, u64 x2, u64 x3, u64 x4, u64 x5, u64 x6, u64 x7, ...);

    enum class HostReturnKind {
        Integer,
        Float,
        Double,
    } returnKind = HostReturnKind::Integer;
    if(method) {
        char *returnType = method_copyReturnType(method);
        if(returnType) {
            const char *unqualifiedType = returnType;
            while(*unqualifiedType &&
                    strchr("rnNoORVA", *unqualifiedType)) {
                unqualifiedType++;
            }
            if(*unqualifiedType == 'f') {
                returnKind = HostReturnKind::Float;
            } else if(*unqualifiedType == 'd') {
                returnKind = HostReturnKind::Double;
            }
            free(returnType);
        }
    }

    auto floatingArgument = [&](size_t index) {
        double value;
        memcpy(&value, &floatingArguments[index], sizeof(value));
        return value;
    };

    auto invokeScalar = [&](void *function, u64 target) -> u64 {
        LC32SetDoubleRegisters(
            floatingArgument(0), floatingArgument(1),
            floatingArgument(2), floatingArgument(3),
            floatingArgument(4), floatingArgument(5),
            floatingArgument(6), floatingArgument(7));
        double floatingResult;
        switch(returnKind) {
            case HostReturnKind::Float:
                floatingResult = ((objc_msgSendFloatFunc)function)(target,
                    host_cmd, integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
                break;
            case HostReturnKind::Double:
                floatingResult = ((objc_msgSendDoubleFunc)function)(target,
                    host_cmd, integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
                break;
            case HostReturnKind::Integer:
                return ((objc_msgSendFunc)function)(target, host_cmd,
                    integerArguments[0], integerArguments[1],
                    integerArguments[2], integerArguments[3],
                    integerArguments[4], integerArguments[5],
                    integerArguments[6], integerArguments[7],
                    integerArguments[8]);
        }
        u64 resultBits;
        memcpy(&resultBits, &floatingResult, sizeof(resultBits));
        return resultBits;
    };

    auto invokeStruct = [&](void *function, u64 target) {
        LC32SetDoubleRegisters(
            floatingArgument(0), floatingArgument(1),
            floatingArgument(2), floatingArgument(3),
            floatingArgument(4), floatingArgument(5),
            floatingArgument(6), floatingArgument(7));
        switch(structLen) {
            case sizeof(LC32_TwoDoubles): {
                const LC32_TwoDoubles result =
                    ((objc_msgSendTwoDoublesFunc)function)(target,
                        host_cmd, integerArguments[0], integerArguments[1],
                        integerArguments[2], integerArguments[3],
                        integerArguments[4], integerArguments[5],
                        integerArguments[6], integerArguments[7],
                        integerArguments[8]);
                (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                    (char *)&result);
                break;
            }
            case sizeof(LC32_FourDoubles): {
                const LC32_FourDoubles result =
                    ((objc_msgSendFourDoublesFunc)function)(target,
                        host_cmd, integerArguments[0], integerArguments[1],
                        integerArguments[2], integerArguments[3],
                        integerArguments[4], integerArguments[5],
                        integerArguments[6], integerArguments[7],
                        integerArguments[8]);
                (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                    (char *)&result);
                break;
            }
            case sizeof(LC32_SixDoubles): {
                const LC32_SixDoubles result =
                    ((objc_msgSendSixDoublesFunc)function)(target,
                        host_cmd, integerArguments[0], integerArguments[1],
                        integerArguments[2], integerArguments[3],
                        integerArguments[4], integerArguments[5],
                        integerArguments[6], integerArguments[7],
                        integerArguments[8]);
                (void)Dynarmic_mem_1write(structPtr, sizeof(result),
                    (char *)&result);
                break;
            }
            default:
                printf("LC32: unsupported host struct return size %u "
                       "for selector %s\n", structLen,
                       sel_getName(selector));
                break;
        }
    };

    // If we're calling from guest within a guest subclass, call super
    if(invokeSuper) {
        struct objc_super superInfo = {
            (id)host_self,
            dispatchClass
        };
        if(structPtr) {
            invokeStruct((void *)objc_msgSendSuper, (u64)&superInfo);
            return finishIndirectArguments(0);
        } else {
            return finishIndirectArguments(
                invokeScalar((void *)objc_msgSendSuper,
                             (u64)&superInfo));
        }
    } else {
        if(structPtr) {
            invokeStruct((void *)objc_msgSend, host_self);
            return finishIndirectArguments(0);
        } else {
            return finishIndirectArguments(
                invokeScalar((void *)objc_msgSend, host_self));
        }
    }
}

void LC32SetInvokeGuestFuncPtr(u32 dlsymFunc, u32 invokeFunc) {
    sharedHandle.guest_dlsym = dlsymFunc;
    sharedHandle.guest_LC32InvokeGuestC = invokeFunc;
}

#pragma mark Host -> Guest functions

static u32 LC32CachedGuestSymbol(std::atomic<u32> &cache,
                                 const char *name) {
    u32 value = cache.load(std::memory_order_acquire);
    if(value) return value;
    const u32 resolved = guest_dlsym(name);
    if(!resolved) return 0;
    if(cache.compare_exchange_strong(value, resolved,
            std::memory_order_release, std::memory_order_acquire))
        return resolved;
    return value;
}

static u32 LC32CachedGuestSelector(std::atomic<u32> &cache,
                                   const char *name) {
    u32 value = cache.load(std::memory_order_acquire);
    if(value) return value;
    const u32 resolved = guest_sel_registerName(name);
    if(!resolved) return 0;
    if(cache.compare_exchange_strong(value, resolved,
            std::memory_order_release, std::memory_order_acquire))
        return resolved;
    return value;
}

u64 LC32InvokeGuestC(u32 pc, bool ret64, int argc, u32 *args) {
    if(threadHandle.jit == nullptr || threadHandle.cb == nullptr) {
        fprintf(stderr,
            "LC32: refusing guest callback on an unregistered host thread "
            "(pc=0x%x)\n", pc);
        return 0;
    }
    std::array<std::uint32_t, 16> &regs = threadHandle.jit->Regs();
    struct context32 ctx;
    Dynarmic_context_1save(&ctx);

    // TODO: optimize this
    // first 4 arguments go to r0-r3
    for(int i = 0; i < MIN(argc, 4); i++) {
        regs[i] = args[i];
    }
    // subsequent arguments go to stack pointer
    for(int i = argc-1; i >= 4; i--) {
        Dynarmic_current_user_callbacks()->MemoryWrite32(regs[Reg::SP] -= sizeof(u32), args[i]);
    }
    regs[12] = pc;
    Dynarmic_emu_1start(sharedHandle.guest_LC32InvokeGuestC);
    u64 result = (u64)regs[0];
    if(ret64) result |= (u64)regs[1] << 32;

    Dynarmic_context_1restore(&ctx);
    return result;
}

u32 LC32HostToGuestArgument(char *type, u64 value) {
    while(*type && strchr("rnNoORVA", *type)) type++;
    switch(*type) {
        case 'B': // bool
        case 'I':
        case 'Q':
        case 'c':
        case 'i':
        case 'q':
            return (u32)value;
        case 'd':
            return (float)(CGFloat)value;
        case '@': // id
        case '#': // Class
            return [(id)value guest_self];
        case '^':
            /*
             * Legacy Cocoa callbacks use void * as an opaque context token.
             * Guest shims pass those tokens to the host zero-extended, so
             * values which still fit in 32 bits can safely make the return
             * trip without exposing or dereferencing host memory. Reject a
             * real ARM64 pointer instead of silently truncating it.
             */
            if(type[1] == 'v' && value == (u64)(u32)value) {
                return (u32)value;
            }
            /*
             * NSZone is an obsolete allocator hint.  A native zone pointer
             * cannot be exposed to the 32-bit address space, and Cocoa
             * treats a null zone as the default zone.  This is used by
             * copyWithZone: while native collections copy guest-backed
             * objects.
             */
            if(!strncmp(type, "^{_NSZone=",
                        sizeof("^{_NSZone=") - 1) ||
               !strncmp(type, "^{NSZone=",
                        sizeof("^{NSZone=") - 1)) {
                return 0;
            }
            [[fallthrough]];
        default:
            printf("LC32HostToGuestArgument: unhandled type %s\n", type);
            abort();
    }
}

static float LC32GuestFloatReturn(u64 value) {
    const u32 bits = (u32)value;
    float result;
    memcpy(&result, &bits, sizeof(result));
    return result;
}

static double LC32GuestDoubleReturn(u64 value) {
    double result;
    memcpy(&result, &value, sizeof(result));
    return result;
}

u64 LC32GuestToHostReturnType(char *type, u64 value) {
    while(*type && strchr("rnNoORVA", *type)) type++;
    switch(*type) {
        case 'B': // bool
        case 'C':
        case 'I':
        case 'L':
        case 'S':
        case 'b':
        case 'c':
        case 'i':
        case 'l':
        case 's':
            return (u64)(u32)value;
        case 'Q':
        case 'q':
            return value;
        case 'v':
            return 0;
        case 'f': {
            const double hostValue = LC32GuestFloatReturn(value);
            u64 result;
            memcpy(&result, &hostValue, sizeof(result));
            return result;
        }
        case 'd': {
            const double hostValue = LC32GuestDoubleReturn(value);
            u64 result;
            memcpy(&result, &hostValue, sizeof(result));
            return result;
        }
        case '@': // id
        case '#': {// Class
            // don't call LC32GetHostObject here! the guest stores host pointer
            static std::atomic<u32> guestPtr{0};
            const u32 selector = LC32CachedGuestSelector(
                guestPtr, "host_self");
            u32 args[] = {(u32)value, selector};
            return guest_objc_msgSend(sizeof(args)/sizeof(*args), args);
        }
        default:
            printf("LC32GuestToHostReturnType: unhandled type %s\n", type);
            abort();
    }
}

static u64 LC32InvokeGuestSelectorWordsRaw(id self, SEL _cmd,
                                           const u32 *argumentWords,
                                           size_t argumentWordCount) {
    assert(argumentWordCount <= 18);

    u32 guest_args[20];
    size_t guest_argc = 0;
    guest_args[guest_argc++] = (u32)(u64)[self guest_self];
    guest_args[guest_argc++] = guest_sel_registerName(sel_getName(_cmd));
    for(size_t index = 0; index < argumentWordCount; index++) {
        guest_args[guest_argc++] = argumentWords[index];
    }

    return guest_objc_msgSend((int)guest_argc, guest_args);
}

static u64 LC32InvokeGuestSelectorWords(id self, SEL _cmd,
                                        const u32 *argumentWords,
                                        size_t argumentWordCount) {
    const u64 guest_result = LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, argumentWords, argumentWordCount);
    Method method = object_isClass(self)
        ? class_getClassMethod(self, _cmd)
        : class_getInstanceMethod((Class)[self class], _cmd);
    char *returnType = method_copyReturnType(method);
    const u64 host_result = LC32GuestToHostReturnType(returnType, guest_result);
    free(returnType);
    return host_result;
}

static u32 LC32GuestFloatWord(CGFloat value) {
    const float guestValue = (float)value;
    u32 word;
    memcpy(&word, &guestValue, sizeof(word));
    return word;
}

static u64 LC32InvokeGuestSelectorCGRectRaw(id self, SEL _cmd, CGRect rect) {
    const u32 words[] = {
        LC32GuestFloatWord(rect.origin.x),
        LC32GuestFloatWord(rect.origin.y),
        LC32GuestFloatWord(rect.size.width),
        LC32GuestFloatWord(rect.size.height),
    };
    return LC32InvokeGuestSelectorWordsRaw(
        self, _cmd, words, sizeof(words) / sizeof(*words));
}

// A CGRect is an HFA of four doubles in the arm64 host ABI, but four floats in
// the ARMv7 guest ABI. A typed IMP is required so the host values are captured
// from d0-d3 before they are narrowed and placed in the guest argument words.
static u64 LC32InvokeGuestSelectorCGRect(id self, SEL _cmd, CGRect rect) {
    const u32 words[] = {
        LC32GuestFloatWord(rect.origin.x),
        LC32GuestFloatWord(rect.origin.y),
        LC32GuestFloatWord(rect.size.width),
        LC32GuestFloatWord(rect.size.height),
    };
    return LC32InvokeGuestSelectorWords(
        self, _cmd, words, sizeof(words) / sizeof(*words));
}

static float LC32InvokeGuestSelectorCGRectGuestFloatHostFloat(
        id self, SEL _cmd, CGRect rect) {
    return LC32GuestFloatReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

static double LC32InvokeGuestSelectorCGRectGuestFloatHostDouble(
        id self, SEL _cmd, CGRect rect) {
    return (double)LC32GuestFloatReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

static float LC32InvokeGuestSelectorCGRectGuestDoubleHostFloat(
        id self, SEL _cmd, CGRect rect) {
    return (float)LC32GuestDoubleReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

static double LC32InvokeGuestSelectorCGRectGuestDoubleHostDouble(
        id self, SEL _cmd, CGRect rect) {
    return LC32GuestDoubleReturn(
        LC32InvokeGuestSelectorCGRectRaw(self, _cmd, rect));
}

// Keep x2-x7 as explicit parameters, then consume any arguments which the
// arm64 caller placed on the stack through va_list.
static u64 LC32InvokeGuestSelectorRaw(id self, SEL _cmd,
                                     u64 arg2, u64 arg3, u64 arg4,
                                     u64 arg5, u64 arg6, u64 arg7,
                                     va_list *hostStackArguments,
                                     Method *resolvedMethod) {
    // FIXME: fast path to get guest selector? cache to hash map?
    u32 guest_cmd = guest_sel_registerName(sel_getName(_cmd));
    Method method = object_isClass(self) ? class_getClassMethod(self, _cmd) : class_getInstanceMethod((Class)[self class], _cmd);

    // Objective-C method metadata describes logical arguments, but an arm64
    // NSRange occupies two general-purpose argument slots. Keep an independent
    // raw-slot cursor so following arguments stay aligned.
    const u64 hostRegisterArguments[] = {
        arg2, arg3, arg4, arg5, arg6, arg7
    };
    constexpr size_t hostRegisterArgumentCount =
        sizeof(hostRegisterArguments) / sizeof(*hostRegisterArguments);
    size_t hostArgumentSlot = 0;
    auto nextHostArgument = [&]() -> u64 {
        if(hostArgumentSlot < hostRegisterArgumentCount) {
            return hostRegisterArguments[hostArgumentSlot++];
        }
        hostArgumentSlot++;
        return va_arg(*hostStackArguments, u64);
    };

    size_t guest_argc = 0;
    u32 guest_args[20];
    guest_args[guest_argc++] = (u32)(u64)[self guest_self];
    guest_args[guest_argc++] = guest_cmd;

    int nargs = method_getNumberOfArguments(method);
    // The generic trampoline has six logical host argument positions. Structs
    // may expand those into extra raw GPR slots (and at most one supported
    // stack argument); broader stack/FP signatures need typed trampolines.
    assert(nargs <= 8);
    for(int i = 2; i < nargs; i++) {
        char *argType = method_copyArgumentType(method, i);
        const char *unqualifiedType = argType;
        while(*unqualifiedType && strchr("rnNoORVA", *unqualifiedType)) {
            unqualifiedType++;
        }

        const bool isNSRange =
            !strncmp(unqualifiedType, "{_NSRange=",
                     sizeof("{_NSRange=") - 1) ||
            !strncmp(unqualifiedType, "{NSRange=",
                     sizeof("{NSRange=") - 1);
        if(isNSRange) {
            /*
             * AAPCS64 never splits an aggregate between registers and the
             * stack. If only x7 remains, it is unused and both NSUInteger
             * fields begin on the stack.
             */
            if(hostArgumentSlot < hostRegisterArgumentCount &&
                    hostRegisterArgumentCount - hostArgumentSlot < 2) {
                hostArgumentSlot = hostRegisterArgumentCount;
            }
            assert(guest_argc + 2 <=
                   sizeof(guest_args) / sizeof(*guest_args));
            guest_args[guest_argc++] = (u32)nextHostArgument();
            guest_args[guest_argc++] = (u32)nextHostArgument();
        } else {
            assert(guest_argc < sizeof(guest_args) / sizeof(*guest_args));
            guest_args[guest_argc++] = LC32HostToGuestArgument(
                argType, nextHostArgument());
        }
        free(argType);
    }
    if(resolvedMethod) *resolvedMethod = method;
    return guest_objc_msgSend((int)guest_argc, guest_args);
}

u64 LC32InvokeGuestSelector(id self, SEL _cmd, u64 arg2, u64 arg3,
                            u64 arg4, u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    Method method = nullptr;
    const u64 guest_result = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, &method);
    va_end(hostStackArguments);

    char *returnType = method_copyReturnType(method);
    u64 host_result = LC32GuestToHostReturnType(returnType, guest_result);
    free(returnType);
    return host_result;
}

static float LC32InvokeGuestSelectorGuestFloatHostFloat(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return LC32GuestFloatReturn(guestResult);
}

static double LC32InvokeGuestSelectorGuestFloatHostDouble(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return (double)LC32GuestFloatReturn(guestResult);
}

static float LC32InvokeGuestSelectorGuestDoubleHostFloat(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return (float)LC32GuestDoubleReturn(guestResult);
}

static double LC32InvokeGuestSelectorGuestDoubleHostDouble(
        id self, SEL _cmd, u64 arg2, u64 arg3, u64 arg4,
        u64 arg5, u64 arg6, u64 arg7, ...) {
    va_list hostStackArguments;
    va_start(hostStackArguments, arg7);
    const u64 guestResult = LC32InvokeGuestSelectorRaw(
        self, _cmd, arg2, arg3, arg4, arg5, arg6, arg7,
        &hostStackArguments, nullptr);
    va_end(hostStackArguments);
    return LC32GuestDoubleReturn(guestResult);
}

void LC32SetGuestScalarIvar(id self, SEL _cmd, u64 value) {
    const char *setterName = sel_getName(_cmd);
    char ivarName[0x50];
    const bool hasLeadingUnderscore =
        !strncmp(setterName, "_set", sizeof("_set") - 1);
    const char *propertyName = setterName +
        (hasLeadingUnderscore ? sizeof("_set") - 1 : sizeof("set") - 1);
    const size_t propertyLength = strlen(propertyName);
    if(propertyLength < 2 || propertyName[propertyLength - 1] != ':') {
        printf("LC32: invalid synthetic ivar setter %s\n", setterName);
        return;
    }
    const int written = snprintf(ivarName, sizeof(ivarName), "%s%c%.*s",
        hasLeadingUnderscore ? "_" : "", tolower(propertyName[0]),
        (int)propertyLength - 2, propertyName + 1);
    if(written <= 0 || (size_t)written >= sizeof(ivarName)) {
        printf("LC32: synthetic ivar setter name too long: %s\n",
               setterName);
        return;
    }
    guest_object_setInstanceVariable([self guest_self], ivarName,
                                     (u32)value);
}

void LC32SetGuestNSObjectIvar(id self, SEL _cmd, id value) {
    LC32SetGuestScalarIvar(self, _cmd, (u64)[value guest_self]);
}

u32 guest_dlsym(const char *host_name) {
    DynarmicGuestStackString guest_name(host_name);
    u32 args[] = {(u32)(u64)RTLD_DEFAULT, guest_name.guestPtr};
    return LC32InvokeGuestC(sharedHandle.guest_dlsym, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_free(u32 guest_ptr) {
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "free");
    u32 args[] = {guest_ptr};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

// These class_copy*List shims are pretty much the same
u32 guest_class_copyIvarList(u32 guest_cls, unsigned int *outCount) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_copyIvarList");
    u32 guest_outCount = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u32);
    u32 args[] = {guest_cls, guest_outCount};
    u32 result = LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
    *outCount = Dynarmic_current_user_callbacks()->MemoryRead32(guest_outCount);
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u32);
    return result;
}
u32 guest_class_copyMethodList(u32 guest_cls, unsigned int *outCount) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_copyMethodList");
    u32 guest_outCount = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u32);
    u32 args[] = {guest_cls, guest_outCount};
    u32 result = LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
    *outCount = Dynarmic_current_user_callbacks()->MemoryRead32(guest_outCount);
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u32);
    return result;
}
u32 guest_class_copyProtocolList(u32 guest_cls, unsigned int *outCount) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_copyProtocolList");
    u32 guest_outCount = threadHandle.jit->Regs()[Reg::SP] -= sizeof(u32);
    u32 args[] = {guest_cls, guest_outCount};
    u32 result = LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
    *outCount = Dynarmic_current_user_callbacks()->MemoryRead32(guest_outCount);
    threadHandle.jit->Regs()[Reg::SP] += sizeof(u32);
    return result;
}

u32 guest_class_createInstance(u32 guest_cls, u32 extraBytes) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_createInstance");
    u32 args[] = {guest_cls, extraBytes};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getClassMethod(u32 guest_cls, u32 guest_sel) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_getClassMethod");
    u32 args[] = {guest_cls, guest_sel};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getInstanceMethod(u32 guest_cls, u32 guest_sel) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_getInstanceMethod");
    u32 args[] = {guest_cls, guest_sel};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getName(u32 guest_cls) {
    if(!threadHandle.jit) return false;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "class_getName");
    u32 args[] = {guest_cls};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_class_getSuperclass(u32 guest_cls) {
    if(!guest_cls) return 0;
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_cls + 4);
}

u32 guest_ivar_getName(u32 guest_ivar) {
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_ivar + sizeof(u32[1]));
}

u32 guest_ivar_getTypeEncoding(u32 guest_ivar) {
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_ivar + sizeof(u32[2]));
}

u32 guest_object_getClass(u32 guest_obj) {
    if(!guest_obj) return 0;
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_obj);
}

u32 guest_object_setInstanceVariable(u32 guest_obj, const char *host_name, u32 newValue) {
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(
        cache, "object_setInstanceVariable");
    DynarmicGuestStackString guest_name(host_name);
    u32 args[] = {guest_obj, guest_name.guestPtr, newValue};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

u32 guest_protocol_getName(u32 guest_protocol) {
    return Dynarmic_current_user_callbacks()->MemoryRead32(guest_protocol + sizeof(u32[1]));
}

u32 guest_sel_registerName(const char *host_name) {
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "sel_registerName");
    DynarmicGuestStackString guest_name(host_name);
    u32 args[] = {guest_name.guestPtr};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

//if(!guestPtr) guestPtr = guest_dlsym("LC32TestHostToGuestCall");
//u32 args[] = {0x40404040, 0x41414141, 0x42424242, 0x43434343, 0x44444444, 0x45454545, 0x46464646, 0x47474747};
u32 guest_objc_getClass(const char *name) {
    if(!threadHandle.jit) return 0;
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "objc_getClass");

    DynarmicGuestStackString guest_name(name);
    u32 args[] = {guest_name.guestPtr};
    return LC32InvokeGuestC(guestPtr, false, sizeof(args)/sizeof(*args), args);
}

Class guest_objc_getClass_retHostClass(const char *name) {
    // Get the guest class pointer
    u32 guest_outClass = guest_objc_getClass(name);
    if(!guest_outClass) return nil;

    // Now that we will be recursively resolving subclass
    Class subclass;
    u32 guest_superclass = guest_class_getSuperclass(guest_outClass);
    DynarmicHostString superclassName(guest_class_getName(guest_superclass));
    subclass = objc_getClass(superclassName.hostPtr);
    if(!subclass) return nil;

    // Now we can construct the class
    Class outClass = objc_allocateClassPair(subclass, name, 0);
    // set class to class
    [(id)outClass setGuest_self:guest_outClass];
    // set metaclass to metaclass
    [(id)object_getClass(outClass) setGuest_self:guest_object_getClass(guest_outClass)];
    // resolve methods and register a dynamic resolver
    [LC32ObjCMethodResolver registerClass:outClass];
    // register to objc
    objc_registerClassPair(outClass);
    [outClass setGuestClass:YES];
    [(id)object_getClass(outClass) setGuestClass:YES];
    return outClass;
}

u64 guest_objc_msgSend(int argc, u32 *args) {
    LC32DrainDeferredGuestPinReleases();
    static std::atomic<u32> cache{0};
    const u32 guestPtr = LC32CachedGuestSymbol(cache, "objc_msgSend");
    return LC32InvokeGuestC(guestPtr, true, argc, args);
}

/*
 * Native collections retain a dynamically mirrored host object without
 * touching the ARM32 object's retain count. Keep one guest-only +1 alive for
 * exactly as long as the host mirror rather than trying to mirror every host
 * retain/release. Ordinary guest ownership operations continue to mirror
 * their corresponding native ownership operations.
 */
enum class LC32GuestReleaseKind : uint8_t {
    LifetimePin,
    LogicalOwnership,
};

static void LC32AdjustGuestReferenceNow(
        u32 guestObject, bool retaining,
        LC32GuestReleaseKind releaseKind =
            LC32GuestReleaseKind::LifetimePin) {
    static std::atomic<u32> retainSelector{0};
    static std::atomic<u32> releaseSelector{0};
    static std::atomic<u32> logicalReleaseSelector{0};
    u32 selector;
    if(retaining) {
        selector = LC32CachedGuestSelector(
            retainSelector, "LC32_retain");
    } else if(releaseKind == LC32GuestReleaseKind::LogicalOwnership) {
        selector = LC32CachedGuestSelector(
            logicalReleaseSelector,
            "LC32_releaseGuestOwnershipOnly");
    } else {
        selector = LC32CachedGuestSelector(
            releaseSelector, "LC32_release");
    }
    u32 args[] = {guestObject, selector};
    guest_objc_msgSend(sizeof(args) / sizeof(*args), args);
}

struct LC32DeferredGuestRelease {
    u32 guestObject;
    LC32GuestReleaseKind kind;
    u64 retainedHostObject;
};

static std::mutex& LC32DeferredGuestPinReleaseMutex() {
    // Associated objects can be torn down during process shutdown. Intentionally
    // keep this synchronization state alive until the process exits.
    static std::mutex *mutex = new std::mutex;
    return *mutex;
}

static std::vector<LC32DeferredGuestRelease>&
LC32DeferredGuestPinReleases() {
    static std::vector<LC32DeferredGuestRelease> *releases =
        new std::vector<LC32DeferredGuestRelease>;
    return *releases;
}

static thread_local bool LC32DrainingGuestPinReleases;

static void LC32ReleaseGuestReference(
        u32 guestObject, LC32GuestReleaseKind kind,
        id hostObjectToKeepAlive = nil) {
    if(threadHandle.jit && threadHandle.cb) {
        LC32AdjustGuestReferenceNow(guestObject, false, kind);
        return;
    }

    u64 retainedHostObject = 0;
    if(hostObjectToKeepAlive) {
        LC32ObjCRetainWithoutARC(hostObjectToKeepAlive);
        retainedHostObject = (u64)hostObjectToKeepAlive;
    }

    // The guest reference remains held until a registered guest thread drains
    // this entry. Logical ownership releases also keep the native mirror alive
    // so they can safely clear its reverse mapping before releasing it.
    std::lock_guard<std::mutex> lock(
        LC32DeferredGuestPinReleaseMutex());
    LC32DeferredGuestPinReleases().push_back({
        guestObject, kind, retainedHostObject,
    });
}

static void LC32ReleaseGuestPin(u32 guestObject) {
    LC32ReleaseGuestReference(
        guestObject, LC32GuestReleaseKind::LifetimePin);
}

static void LC32ReleaseGuestLogicalOwnership(
        u32 guestObject, id hostObject) {
    LC32ReleaseGuestReference(
        guestObject, LC32GuestReleaseKind::LogicalOwnership,
        hostObject);
}

static void LC32DrainDeferredGuestPinReleases() {
    if(LC32DrainingGuestPinReleases ||
            !threadHandle.jit || !threadHandle.cb) {
        return;
    }

    std::vector<LC32DeferredGuestRelease> pending;
    {
        std::lock_guard<std::mutex> lock(
            LC32DeferredGuestPinReleaseMutex());
        pending.swap(LC32DeferredGuestPinReleases());
    }
    if(pending.empty()) return;

    LC32DrainingGuestPinReleases = true;
    for(const LC32DeferredGuestRelease &release : pending) {
        LC32AdjustGuestReferenceNow(
            release.guestObject, false, release.kind);
        if(release.retainedHostObject) {
            objc_release((id)release.retainedHostObject);
        }
    }
    LC32DrainingGuestPinReleases = false;
}

@interface LC32GuestLifetimePin : NSObject {
@public
    u32 guestObject;
}
@end

@implementation LC32GuestLifetimePin
- (void)dealloc {
    LC32ReleaseGuestPin(guestObject);
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}
@end

@interface LC32GuestAutoreleaseToken : NSObject {
@public
    u32 guestObject;
    id hostObject;
}
@end

@implementation LC32GuestAutoreleaseToken
- (void)dealloc {
    // Keep hostObject strongly held while the guest removes its corresponding
    // logical +1 and, if final, clears the host's reverse mapping.
    LC32ReleaseGuestLogicalOwnership(guestObject, hostObject);
#if !__has_feature(objc_arc)
    [hostObject release];
    [super dealloc];
#endif
}
@end

extern "C" u32 LC32ScheduleGuestAutorelease(
        u32 hostLow, u32 hostHigh, u32 guestStackPointer) {
    const u64 hostAddress = hostLow | ((u64)hostHigh << 32);
    id __unsafe_unretained hostObject = (id)hostAddress;
    // SVC 1002 forwards r2/r3 directly and passes the guest SP as its third
    // native argument. The next ARMv7 vararg (the guest object) is at [SP].
    const u32 guestObject =
        Dynarmic_current_user_callbacks()->MemoryRead32(guestStackPointer);
    if(!hostObject || !guestObject) return 0;

    LC32GuestAutoreleaseToken *token =
        [LC32GuestAutoreleaseToken new];
    token->guestObject = guestObject;
#if __has_feature(objc_arc)
    token->hostObject = hostObject;
    // Transfer a dedicated +1 to the host autorelease pool. Clearing the ARC
    // local first leaves exactly that transferred ownership outstanding.
    void *retainedToken = (__bridge_retained void *)token;
    token = nil;
    LC32ObjCAutoreleaseWithoutARC((__bridge id)retainedToken);
#else
    token->hostObject = [hostObject retain];
    [token autorelease];
#endif

    // The token now owns the mirror's existing guest-paired +1. Its eventual
    // destruction releases guest logical ownership first, then this host +1.
    objc_release(hostObject);
    return 0;
}

static const void *LC32GuestLifetimePinKey =
    &LC32GuestLifetimePinKey;

static void LC32PinGuestObjectToHost(id hostObject, u32 guestObject,
                                     bool retainGuestObject) {
    if(!hostObject || !guestObject) return;

    @synchronized(hostObject) {
        LC32GuestLifetimePin *existing = objc_getAssociatedObject(
            hostObject, LC32GuestLifetimePinKey);
        if(existing) {
            assert(existing->guestObject == guestObject);
            return;
        }

        if(retainGuestObject) {
            assert(threadHandle.jit && threadHandle.cb);
            LC32AdjustGuestReferenceNow(guestObject, true);
        }

        LC32GuestLifetimePin *pin = [LC32GuestLifetimePin new];
        pin->guestObject = guestObject;
        objc_setAssociatedObject(hostObject, LC32GuestLifetimePinKey, pin,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if !__has_feature(objc_arc)
        [pin release];
#endif
    }
}

objc_hook_getClass host_getClass;
BOOL host_hook_getClass(const char *name, Class *outClass) {
    if(host_getClass && host_getClass(name, outClass)) {
        return true;
    }

    printf("host_hook_getClass: %s\n", name);
    *outClass = guest_objc_getClass_retHostClass(name);
    return *outClass != nil;
}

@implementation NSObject(LC32)
static const void *kGuestClass = &kGuestClass;
static const void *kGuestSelf = &kGuestSelf;
- (void)setGuestClass:(BOOL)value {
    return objc_setAssociatedObject(self, kGuestClass, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)isGuestClass {
    return ((NSNumber *)objc_getAssociatedObject(self, kGuestClass)).boolValue;
}

// Set the equivalent guest object pointer.
// Called from guest_self if the object has not been known by guest before (eg passing UIApplication object to guest)
// Called from guest's setHost_self if the object is created by guest code (eg creating AppDelegate, UIWindow, etc)
- (void)setGuest_self:(u32)ptr {
    //assert(!self.guest_selfOrNull);
    @synchronized(self) {
        objc_setAssociatedObject(self, kGuestSelf, @(ptr),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (u32)guest_selfOrNull {
    return ((NSNumber *)objc_getAssociatedObject(self, kGuestSelf)).unsignedLongValue;
}

- (u32)LC32_bindGuestSelfIfAbsent:(u32)ptr {
    u32 boundGuestObject;
    @synchronized(self) {
        const u32 existing = self.guest_selfOrNull;
        if(existing) {
            boundGuestObject = existing;
        } else {
            objc_setAssociatedObject(self, kGuestSelf, @(ptr),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            boundGuestObject = ptr;
        }
    }
    /*
     * An initializer may replace its +alloc placeholder (class clusters do
     * this routinely). Move the lifetime guarantee to the returned native
     * object as soon as it acquires the reverse mapping. The placeholder's
     * pin is released independently when that object is destroyed.
     */
    if(boundGuestObject == ptr) {
        /*
         * This is also needed when +alloc and -init return the same object:
         * +alloc installed its reverse mapping but deliberately did not pin
         * native class-cluster placeholders, which may be shared.
         */
        LC32PinGuestObjectToHost(self, ptr, true);
    }
    return boundGuestObject;
}

- (void)LC32_clearGuestSelfIfEqual:(u64)expectedGuestSelf {
    @synchronized(self) {
        NSNumber *mappedGuestSelf =
            objc_getAssociatedObject(self, kGuestSelf);
        if(mappedGuestSelf.unsignedLongLongValue == expectedGuestSelf) {
            objc_setAssociatedObject(self, kGuestSelf, nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

- (u32)guest_self {
    u32 ptr = self.guest_selfOrNull;
    if(ptr) return ptr;

    @synchronized(self) {
    ptr = self.guest_selfOrNull;
    if(ptr) return ptr;

    Class hostClass = self.class;
    const char *className = class_getName(hostClass);
    Class matchedHostClass = hostClass;
    while(matchedHostClass != Nil) {
        ptr = guest_objc_getClass(class_getName(matchedHostClass));
        if(ptr) break;
        matchedHostClass = class_getSuperclass(matchedHostClass);
    }
    if(!ptr) {
        printf("LC32: Error: Host required missing guest class %s\n", className);
        return 0;
    }
    if(matchedHostClass != hostClass) {
        printf("LC32: mapping host class %s through guest superclass %s\n",
            className, class_getName(matchedHostClass));
    }
    if(object_isClass(self)) return self.guest_self = ptr;

    static std::atomic<u32> guestSetHostSelfCache{0};
    const u32 guest_setHost_self = LC32CachedGuestSelector(
        guestSetHostSelfCache, "initWithHostSelf:");
    ptr = guest_class_createInstance(ptr, 0);

    //guest_objc_performSelector(ptr, guest_setHost_self, (u32)(u64)self, (u32)((u64)self >> 32));
    {
        u32 args[] = {ptr, guest_setHost_self, (u32)(u64)self, (u32)((u64)self >> 32)};
        ptr = guest_objc_msgSend(sizeof(args)/sizeof(*args), args);
    }

    self.guest_self = ptr;
    if([(id)hostClass isGuestClass]) {
        // class_createInstance returned the +1 which becomes this host
        // mirror's lifetime pin; do not retain it a second time.
        LC32PinGuestObjectToHost(self, ptr, false);
    }
    return ptr;
    }
}
@end

static const char *LC32UnqualifiedType(const char *type) {
    while(type && *type && strchr("rnNoORVA", *type)) type++;
    return type;
}

static const char *LC32ProtocolMethodTypes(Protocol *protocol, SEL selector,
                                           BOOL instanceMethod,
                                           unsigned int depth) {
    if(!protocol || depth > 16) return nullptr;

    for(BOOL required : {YES, NO}) {
        const struct objc_method_description description =
            protocol_getMethodDescription(protocol, selector, required,
                                          instanceMethod);
        if(description.name && description.types) return description.types;
    }

    unsigned int adoptedCount = 0;
    Protocol *__unsafe_unretained *adoptedProtocols =
        protocol_copyProtocolList(protocol, &adoptedCount);
    for(unsigned int index = 0; index < adoptedCount; index++) {
        const char *types = LC32ProtocolMethodTypes(
            adoptedProtocols[index], selector, instanceMethod, depth + 1);
        if(types) {
            free(adoptedProtocols);
            return types;
        }
    }
    free(adoptedProtocols);
    return nullptr;
}

static const char *LC32ClassProtocolMethodTypes(Class cls, SEL selector,
                                                BOOL instanceMethod) {
    if(!cls) return nullptr;

    unsigned int protocolCount = 0;
    Protocol *__unsafe_unretained *protocols =
        class_copyProtocolList(cls, &protocolCount);
    for(unsigned int index = 0; index < protocolCount; index++) {
        const char *types = LC32ProtocolMethodTypes(
            protocols[index], selector, instanceMethod, 0);
        if(types) {
            free(protocols);
            return types;
        }
    }
    free(protocols);
    return nullptr;
}

static const char *LC32ClassHierarchyProtocolMethodTypes(
        Class cls, SEL selector, BOOL instanceMethod) {
    for(Class current = cls; current;
            current = class_getSuperclass(current)) {
        const char *types = LC32ClassProtocolMethodTypes(
            current, selector, instanceMethod);
        if(types) return types;
    }
    return nullptr;
}

// Protocol adoption belongs to the ordinary class, but class methods are
// installed on its metaclass. Keep the owner available while a newly
// allocated class is still unregistered and cannot yet be found by name.
static const void *LC32ProtocolOwnerClassKey =
    &LC32ProtocolOwnerClassKey;

static Class LC32ProtocolOwnerClass(Class cls) {
    if(!class_isMetaClass(cls)) return cls;

    Class owner = (Class)objc_getAssociatedObject(
        (id)cls, LC32ProtocolOwnerClassKey);
    if(owner) return owner;
    return objc_lookUpClass(class_getName(cls));
}

/*
 * A guest CGFloat is encoded as `f`, while the same public method is `d` in
 * the ARM64 UIKit ABI.  Prefer the native declaration inherited by the mirror
 * class, then a native protocol declaration adopted anywhere in its class
 * hierarchy.
 */
static const char *LC32ExpectedHostMethodTypes(Class cls, SEL selector) {
    Class superclass = class_getSuperclass(cls);
    Method inheritedMethod = superclass
        ? class_getInstanceMethod(superclass, selector)
        : nullptr;
    if(inheritedMethod) return method_getTypeEncoding(inheritedMethod);

    const BOOL instanceMethod = !class_isMetaClass(cls);
    return LC32ClassHierarchyProtocolMethodTypes(
        LC32ProtocolOwnerClass(cls), selector, instanceMethod);
}

@implementation LC32ObjCMethodResolver
+ (void)addMethod:(Method)method toClass:(Class)cls {
    class_addMethod(cls, method_getName(method), method_getImplementation(method), method_getTypeEncoding(method));
}

+ (void)addGuestIvar:(u32)guest_ivar toClass:(Class)cls {
    DynarmicHostString name(guest_ivar_getName(guest_ivar));
    DynarmicHostString typeEncoding(guest_ivar_getTypeEncoding(guest_ivar));

    // According to https://github.com/Quotation/LongestCocoa#longest-objective-c-property-names, the longest public property has 56 characters
    // still, we need to add an assert
    char setterName[0x50];
    char literalIvarSetterName[0x50] = {};
    assert(strlen(name.hostPtr) + 4 < sizeof(setterName));
    if(name.hostPtr[0] == '_') {
        snprintf(setterName, sizeof(setterName)-1, "_set%c%s:", toupper(name.hostPtr[1]), &name.hostPtr[2]);
        // Some older nibs archive the literal ivar name as their KVC key.
        // KVC asks for set_btnGameMode: when the key is _btnGameMode, while
        // _setBtnGameMode: above is the accessor for the logical key
        // btnGameMode. Register both spellings against the same guest ivar.
        snprintf(literalIvarSetterName, sizeof(literalIvarSetterName)-1,
                 "set%s:", name.hostPtr);
    } else {
        snprintf(setterName, sizeof(setterName)-1, "set%c%s:", toupper(name.hostPtr[0]), &name.hostPtr[1]);
    }

    char setterTypeEncoding[10];
    snprintf(setterTypeEncoding, sizeof(setterTypeEncoding)-1, "v@:%c", typeEncoding.hostPtr[0]);

    IMP setterImplementation = nullptr;
    switch(typeEncoding.hostPtr[0]) {
        case '@':
        case '#':
            setterImplementation = (IMP)&LC32SetGuestNSObjectIvar;
            break;
        case 'B':
        case 'C':
        case 'I':
        case 'L':
        case 'Q':
        case 'S':
        case 'b':
        case 'c':
        case 'i':
        case 'l':
        case 'q':
        case 's':
            setterImplementation = (IMP)&LC32SetGuestScalarIvar;
            break;
        default:
            printf("LC32: skipping ivar %s with unhandled type %s\n", name.hostPtr, typeEncoding.hostPtr);
            break;
    }
    if(setterImplementation) {
        class_addMethod(cls, sel_registerName(setterName),
                        setterImplementation, setterTypeEncoding);
        if(literalIvarSetterName[0]) {
            class_addMethod(cls, sel_registerName(literalIvarSetterName),
                            setterImplementation, setterTypeEncoding);
        }
    }

    // We currently don't bind setter, just leaving here for future references
    // for getter booleans, we have to register total 3 variants: name, hasName and isName, since we don't want to run a LLM here to predict which is best ¯\_(ツ)_/¯
}

+ (void)addGuestMethod:(u32)guest_method selector:(SEL)sel toClass:(Class)cls {
    objc_method_32 host_method_32;
    Dynarmic_mem_1read(guest_method, sizeof(host_method_32), (char *)&host_method_32);
    DynarmicHostString host_method_types(host_method_32.method_types);
    if(!sel) {
        DynarmicHostString host_sel(host_method_32.method_name);
        sel = sel_registerName(host_sel.hostPtr);
    }

    // The Objective-C runtime calls these lifecycle hooks as id (*)(id) and
    // void (*)(id), without a selector argument. Installing the generic
    // (id, SEL, ...) trampoline therefore interprets garbage in x1 as _cmd.
    // Guest C++ ivars belong to the guest object and are already managed by
    // the guest runtime, so forwarding would also construct/destruct twice.
    const char *selectorName = sel_getName(sel);
    if(!strcmp(selectorName, ".cxx_construct") ||
            !strcmp(selectorName, ".cxx_destruct") ||
            !strcmp(selectorName, "dealloc")) {
        return;
    }

    const char *guestMethodTypes = host_method_types.hostPtr;
    const char *installedMethodTypes = guestMethodTypes;
    const char guestReturnType = *LC32UnqualifiedType(guestMethodTypes);
    char hostReturnType = guestReturnType;
    IMP floatingImplementation = nullptr;
    if(guestReturnType == 'f' || guestReturnType == 'd') {
        const char *expectedHostTypes =
            LC32ExpectedHostMethodTypes(cls, sel);
        if(expectedHostTypes) {
            const char expectedReturnType =
                *LC32UnqualifiedType(expectedHostTypes);
            if(expectedReturnType == 'f' || expectedReturnType == 'd') {
                installedMethodTypes = expectedHostTypes;
                hostReturnType = expectedReturnType;
            }
        }

        if(guestReturnType == 'f') {
            floatingImplementation = hostReturnType == 'd'
                ? (IMP)&LC32InvokeGuestSelectorGuestFloatHostDouble
                : (IMP)&LC32InvokeGuestSelectorGuestFloatHostFloat;
        } else {
            floatingImplementation = hostReturnType == 'f'
                ? (IMP)&LC32InvokeGuestSelectorGuestDoubleHostFloat
                : (IMP)&LC32InvokeGuestSelectorGuestDoubleHostDouble;
        }
        if(hostReturnType != guestReturnType) {
            fprintf(stderr,
                "LC32: floating return ABI for %s: guest %c -> host %c\n",
                selectorName, guestReturnType, hostReturnType);
        }
    }

    IMP implementation = floatingImplementation
        ? floatingImplementation
        : (IMP)&LC32InvokeGuestSelector;
    if(strstr(installedMethodTypes, "{CGRect=")) {
        NSMethodSignature *signature =
            [NSMethodSignature signatureWithObjCTypes:installedMethodTypes];
        if(signature.numberOfArguments == 3) {
            const char *argumentType = [signature getArgumentTypeAtIndex:2];
            while(*argumentType && strchr("rnNoORVA", *argumentType)) {
                argumentType++;
            }
            if(!strncmp(argumentType, "{CGRect=", sizeof("{CGRect=") - 1)) {
                if(floatingImplementation) {
                    if(guestReturnType == 'f') {
                        implementation = hostReturnType == 'd'
                            ? (IMP)&LC32InvokeGuestSelectorCGRectGuestFloatHostDouble
                            : (IMP)&LC32InvokeGuestSelectorCGRectGuestFloatHostFloat;
                    } else {
                        implementation = hostReturnType == 'f'
                            ? (IMP)&LC32InvokeGuestSelectorCGRectGuestDoubleHostFloat
                            : (IMP)&LC32InvokeGuestSelectorCGRectGuestDoubleHostDouble;
                    }
                } else {
                    implementation = (IMP)&LC32InvokeGuestSelectorCGRect;
                }
            }
        }
    }
    class_addMethod(cls, sel, implementation, installedMethodTypes);
}


+ (void)addGuestProtocol:(u32)guest_protocol toClass:(Class)cls {
    DynarmicHostString host_protocolName(guest_protocol_getName(guest_protocol));
    Protocol *protocol = objc_getProtocol(host_protocolName.hostPtr);
    if(protocol) {
        class_addProtocol(cls, protocol);
    } else {
        printf("LC32: skipping nonexistent protocol %s\n", host_protocolName.hostPtr);
    }
}

+ (void)registerClass:(Class)clsObject {
    u32 count;
    u32 list;

    Class cls = object_getClass(clsObject);
    objc_setAssociatedObject((id)cls, LC32ProtocolOwnerClassKey,
                             (id)clsObject, OBJC_ASSOCIATION_ASSIGN);
    [self addMethod:class_getClassMethod(self, @selector(resolveClassMethod:)) toClass:cls];
    [self addMethod:class_getClassMethod(self, @selector(resolveInstanceMethod:)) toClass:cls];
    [cls resolveInstanceMethod:@selector(init)];
    [cls setGuestClass:YES];

    // FIXME: can't call free on copied lists
    // Register protocols
    list = guest_class_copyProtocolList([clsObject guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestProtocol:Dynarmic_current_user_callbacks()->MemoryRead32(list) toClass:clsObject];
    }
    //if(list) guest_free(list);

    // Register class methods. Pass metaclass (cls) here!
    list = guest_class_copyMethodList([cls guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestMethod:Dynarmic_current_user_callbacks()->MemoryRead32(list) selector:nil toClass:cls];
    }
    //if(list) guest_free(list);

    // Register instance methods
    list = guest_class_copyMethodList([clsObject guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestMethod:Dynarmic_current_user_callbacks()->MemoryRead32(list) selector:nil toClass:clsObject];
    }
    //if(list) guest_free(list);

    // Add synthetic ivar setters only after real guest methods. They are a
    // fallback for nib/KVC assignment when the binary has no setter; adding
    // them first would shadow an app's retaining property implementation.
    list = guest_class_copyIvarList([clsObject guest_self], &count);
    for(int i = 0; i < count; i++, list += sizeof(u32)) {
        [self addGuestIvar:Dynarmic_current_user_callbacks()->MemoryRead32(list) toClass:clsObject];
    }
    //if(list) guest_free(list);
}

// FIXME: currently using class_get*Method which may return superclass's method, but I guess this shouldn't affect anything
+ (BOOL)resolveClassMethod:(SEL)sel {
    printf("resolveClassMethod %s\n", sel_getName(sel));
    u32 guest_sel = guest_sel_registerName(sel_getName(sel));
    u32 guest_method = guest_class_getClassMethod(self.guest_self, guest_sel);
    if(guest_method) {
        [LC32ObjCMethodResolver addGuestMethod:guest_method selector:sel toClass:self.class];
    }
    return [super resolveClassMethod:sel];
}

+ (BOOL)resolveInstanceMethod:(SEL)sel {
    printf("resolveInstanceMethod %s\n", sel_getName(sel));
    u32 guest_sel = guest_sel_registerName(sel_getName(sel));
    u32 guest_method = guest_class_getInstanceMethod(self.guest_self, guest_sel);
    if(guest_method) {
        [LC32ObjCMethodResolver addGuestMethod:guest_method selector:sel toClass:self];
    }
    return [super resolveInstanceMethod:sel];
}
@end

__attribute__((constructor)) void LC32InstallGetClassHook() {
    objc_setHook_getClass(host_hook_getClass, &host_getClass);
}
