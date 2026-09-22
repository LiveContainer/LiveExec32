#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static NSString *LC32ManagedAccessorKey(id object, SEL selector) {
    for(Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        NSString *key = objc_getAssociatedObject(cls, selector);
        if(key) return key;
    }
    return nil;
}

static id LC32ManagedObjectGetter(NSManagedObject *object, SEL selector) {
    NSString *key = LC32ManagedAccessorKey(object, selector);
    [object willAccessValueForKey:key];
    id value = [object primitiveValueForKey:key];
    [object didAccessValueForKey:key];
    return value;
}

static void LC32ManagedObjectSetter(NSManagedObject *object, SEL selector, id value) {
    NSString *key = LC32ManagedAccessorKey(object, selector);
    [object willChangeValueForKey:key];
    [object setPrimitiveValue:value forKey:key];
    [object didChangeValueForKey:key];
}

@implementation NSManagedObject (LC32Accessors)

+ (BOOL)resolveInstanceMethod:(SEL)selector {
    /* Native Core Data synthesizes native IMPs, not ARM32 methods. Supply the
     * guest half of object-valued @dynamic accessors using Core Data's custom
     * accessor protocol, preserving faulting and change notifications. Never
     * treat a native IMP (or an arbitrary scalar property) as a guest method. */
    for(Class cls = self; cls && cls != [NSManagedObject class];
            cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        for(unsigned i = 0; i < count; ++i) {
            objc_property_t property = properties[i];
            char *dynamic = property_copyAttributeValue(property, "D");
            char *type = property_copyAttributeValue(property, "T");
            BOOL supported = dynamic && type && type[0] == '@' && type[1] != '?';
            free(dynamic);
            free(type);
            if(!supported) continue;

            const char *name = property_getName(property);
            char *getter = property_copyAttributeValue(property, "G");
            BOOL isGetter = !strcmp(sel_getName(selector), getter ?: name);
            free(getter);
            char *readonly = property_copyAttributeValue(property, "R");
            char *setter = property_copyAttributeValue(property, "S");
            if(!setter) {
                size_t length = strlen(name);
                setter = malloc(length + 5);
                if(setter) {
                    memcpy(setter, "set", 3);
                    memcpy(setter + 3, name, length);
                    setter[3] = toupper((unsigned char)setter[3]);
                    setter[length + 3] = ':';
                    setter[length + 4] = 0;
                }
            }
            BOOL isSetter = !readonly && setter && !strcmp(sel_getName(selector), setter);
            free(readonly);
            free(setter);
            if(!isGetter && !isSetter) continue;

            /* Bind the exact property name before publishing the IMP. Do not
             * infer it from setURL:, custom accessors, or an inherited method. */
            objc_setAssociatedObject(self, selector,
                [NSString stringWithUTF8String:name], OBJC_ASSOCIATION_RETAIN);
            BOOL added = class_addMethod(self, selector, isGetter
                ? (IMP)LC32ManagedObjectGetter : (IMP)LC32ManagedObjectSetter,
                isGetter ? "@8@0:4" : "v12@0:4@8");
            free(properties);
            return added;
        }
        free(properties);
    }
    return [super resolveInstanceMethod:selector];
}

@end
