#import <Foundation/Foundation.h>

#import <Block.h>
#import <objc/runtime.h>

#include <stdbool.h>
#include <stdint.h>

/*
 * libsystem_blocks supplies these as 128-byte zero-filled regions.  The first
 * 64 bytes hold a class and the second 64 bytes hold its metaclass.  Apple's
 * CoreFoundation turns the regions into Objective-C classes during its own
 * initialization; without that step a block has a non-null isa which points
 * at an otherwise empty class object.
 */
extern void *_NSConcreteMallocBlock[32];
extern void *_NSConcreteAutoBlock[32];
extern void *_NSConcreteFinalizingBlock[32];
extern void *_NSConcreteWeakBlockVariable[32];

extern Class objc_initializeClassPair(Class superclass, const char *name,
                                      Class cls, Class metacls);

extern id objc_retain(id object);
extern void objc_release(id object);

extern bool _Block_tryRetain(const void *block);
extern bool _Block_isDeallocating(const void *block);

struct LC32BlockRRCallbacks {
    uintptr_t size;
    void (*retain)(const void *object);
    void (*release)(const void *object);
    void (*destructInstance)(const void *object);
};

extern void _Block_use_RR2(const struct LC32BlockRRCallbacks *callbacks);

struct LC32BlockDescriptorWithCopyDispose {
    uintptr_t reserved;
    uintptr_t size;
    void (*copy)(void *destination, const void *source);
    void (*dispose)(const void *source);
};

struct LC32BlockLiteral {
    Class isa;
    uint32_t flags;
    uint32_t reserved;
    void (*invoke)(void *block);
    struct LC32BlockDescriptorWithCopyDispose *descriptor;
};

enum {
    LC32BlockHasCopyDispose = 1U << 25,
};

@interface NSBlock : NSObject
@end

@interface __NSStackBlock : NSBlock
@end

@interface __NSMallocBlock : NSBlock
@end

@interface __NSAutoBlock : NSBlock
@end

@interface __NSFinalizingBlock : __NSAutoBlock
@end

@interface __NSGlobalBlock : NSBlock
@end

@interface __NSBlockVariable : NSObject
@end

@implementation NSBlock

+ (id)alloc {
    return nil;
}

+ (id)allocWithZone:(NSZone *)zone {
    (void)zone;
    return nil;
}

- (id)copy {
    return _Block_copy(self);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return _Block_copy(self);
}

- (void)invoke {
    struct LC32BlockLiteral *block = (struct LC32BlockLiteral *)self;
    block->invoke(block);
}

@end

@implementation __NSStackBlock

- (id)retain {
    return self;
}

- (oneway void)release {
}

- (NSUInteger)retainCount {
    return 1;
}

- (id)autorelease {
    return self;
}

@end

@implementation __NSMallocBlock

- (id)retain {
    (void)_Block_copy(self);
    return self;
}

- (oneway void)release {
    _Block_release(self);
}

- (NSUInteger)retainCount {
    return 1;
}

- (BOOL)_tryRetain {
    return _Block_tryRetain(self);
}

- (BOOL)_isDeallocating {
    return _Block_isDeallocating(self);
}

@end

@implementation __NSAutoBlock

- (id)copy {
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

@end

@implementation __NSFinalizingBlock

- (void)finalize {
    struct LC32BlockLiteral *block = (struct LC32BlockLiteral *)self;
    if(block->flags & LC32BlockHasCopyDispose) {
        block->descriptor->dispose(block);
    }
}

@end

@implementation __NSGlobalBlock

- (id)retain {
    return self;
}

- (oneway void)release {
}

- (id)copy {
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

- (NSUInteger)retainCount {
    return 1;
}

- (BOOL)_tryRetain {
    return YES;
}

- (BOOL)_isDeallocating {
    return NO;
}

@end

@implementation __NSBlockVariable
@end

static void LC32BlockRetain(const void *object) {
    (void)objc_retain((id)object);
}

static void LC32BlockRelease(const void *object) {
    objc_release((id)object);
}

static void LC32BlockDestructInstance(const void *object) {
    (void)objc_destructInstance((id)object);
}

struct LC32ConcreteBlockClass {
    const char *superclassName;
    const char *className;
    void **storage;
};

__attribute__((constructor))
static void LC32InitializeNSBlockClasses(void) {
    const struct LC32ConcreteBlockClass descriptions[] = {
        { "__NSStackBlock", "__NSStackBlock__", _NSConcreteStackBlock },
        { "__NSMallocBlock", "__NSMallocBlock__", _NSConcreteMallocBlock },
        { "__NSAutoBlock", "__NSAutoBlock__", _NSConcreteAutoBlock },
        { "__NSFinalizingBlock", "__NSFinalizingBlock__",
          _NSConcreteFinalizingBlock },
        { "__NSGlobalBlock", "__NSGlobalBlock__", _NSConcreteGlobalBlock },
        { "__NSBlockVariable", "__NSBlockVariable__",
          _NSConcreteWeakBlockVariable },
    };
    Class classes[sizeof(descriptions) / sizeof(descriptions[0])];

    for(NSUInteger index = 0;
        index < sizeof(descriptions) / sizeof(descriptions[0]); index++) {
        const struct LC32ConcreteBlockClass *description =
            &descriptions[index];
        Class blockClass = (Class)description->storage;
        Class blockMetaclass = (Class)((uint8_t *)description->storage + 0x40);

        objc_initializeClassPair(objc_lookUpClass(description->superclassName),
                                 description->className,
                                 blockClass, blockMetaclass);
        classes[index] = blockClass;
    }

    for(NSUInteger index = 0;
        index < sizeof(classes) / sizeof(classes[0]); index++) {
        objc_registerClassPair(classes[index]);
    }

    const struct LC32BlockRRCallbacks callbacks = {
        .size = sizeof(callbacks),
        .retain = LC32BlockRetain,
        .release = LC32BlockRelease,
        .destructInstance = LC32BlockDestructInstance,
    };
    _Block_use_RR2(&callbacks);
}
