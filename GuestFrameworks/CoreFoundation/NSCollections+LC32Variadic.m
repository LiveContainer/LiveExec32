#import <Foundation/Foundation.h>

#include <stdarg.h>

// Objective-C type encodings omit the ellipsis from variadic methods. Keep
// nil-terminated object lists in the ARMv7 guest, where va_list has the ABI
// expected by the caller, and build the corresponding host collection using
// ordinary fixed-argument shim methods.

static NSMutableArray *LC32ArrayFromObjects(id firstObject,
                                             va_list arguments) {
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:8];
    for(id object = firstObject; object != nil;
            object = va_arg(arguments, id)) {
        [objects addObject:object];
    }
    return objects;
}

static NSMutableSet *LC32SetFromObjects(id firstObject,
                                         va_list arguments) {
    NSMutableSet *objects = [NSMutableSet setWithCapacity:8];
    for(id object = firstObject; object != nil;
            object = va_arg(arguments, id)) {
        [objects addObject:object];
    }
    return objects;
}

static NSMutableOrderedSet *LC32OrderedSetFromObjects(id firstObject,
                                                       va_list arguments) {
    NSMutableOrderedSet *objects =
        [NSMutableOrderedSet orderedSetWithCapacity:8];
    for(id object = firstObject; object != nil;
            object = va_arg(arguments, id)) {
        [objects addObject:object];
    }
    return objects;
}

static NSMutableDictionary *LC32DictionaryFromObjectsAndKeys(
        id firstObject, va_list arguments) {
    NSMutableDictionary *objectsAndKeys =
        [NSMutableDictionary dictionaryWithCapacity:8];
    for(id object = firstObject; object != nil;
            object = va_arg(arguments, id)) {
        id key = va_arg(arguments, id);
        // Deliberately let NSMutableDictionary enforce the native exception
        // behavior for an unterminated object/key pair (a nil key).
        [objectsAndKeys setObject:object forKey:key];
    }
    return objectsAndKeys;
}

@implementation NSArray (LC32Variadic)

+ (instancetype)arrayWithObjects:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableArray *objects = LC32ArrayFromObjects(firstObject, arguments);
    va_end(arguments);
    return [self arrayWithArray:objects];
}

- (instancetype)initWithObjects:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableArray *objects = LC32ArrayFromObjects(firstObject, arguments);
    va_end(arguments);
    return [self initWithArray:objects];
}

@end

@implementation NSSet (LC32Variadic)

+ (instancetype)setWithObjects:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableSet *objects = LC32SetFromObjects(firstObject, arguments);
    va_end(arguments);
    return [self setWithSet:objects];
}

- (instancetype)initWithObjects:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableSet *objects = LC32SetFromObjects(firstObject, arguments);
    va_end(arguments);
    return [self initWithSet:objects];
}

@end

@implementation NSOrderedSet (LC32Variadic)

+ (instancetype)orderedSetWithObjects:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableOrderedSet *objects =
        LC32OrderedSetFromObjects(firstObject, arguments);
    va_end(arguments);
    return [self orderedSetWithOrderedSet:objects];
}

- (instancetype)initWithObjects:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableOrderedSet *objects =
        LC32OrderedSetFromObjects(firstObject, arguments);
    va_end(arguments);
    return [self initWithOrderedSet:objects];
}

@end

@implementation NSDictionary (LC32Variadic)

+ (instancetype)dictionaryWithObjectsAndKeys:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableDictionary *objectsAndKeys =
        LC32DictionaryFromObjectsAndKeys(firstObject, arguments);
    va_end(arguments);
    return [self dictionaryWithDictionary:objectsAndKeys];
}

- (instancetype)initWithObjectsAndKeys:(id)firstObject, ... {
    va_list arguments;
    va_start(arguments, firstObject);
    NSMutableDictionary *objectsAndKeys =
        LC32DictionaryFromObjectsAndKeys(firstObject, arguments);
    va_end(arguments);
    return [self initWithDictionary:objectsAndKeys];
}

@end
