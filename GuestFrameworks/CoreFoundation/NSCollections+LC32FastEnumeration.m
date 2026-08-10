#import <Foundation/Foundation.h>

#include <stdint.h>

// NSFastEnumerationState contains NSUInteger values and pointers, so its host
// and guest layouts cannot be shared. Keep the state in ARM32 guest memory and
// drive an ordinary bridged NSEnumerator one object at a time instead.
static NSUInteger LC32CountByEnumerating(
        NSEnumerator *enumerator,
        NSFastEnumerationState *state,
        id __unsafe_unretained objects[],
        NSUInteger count) {
    if(!state || !objects || !count) return 0;

    if(state->state == 0) {
        state->state = 1;
        state->extra[0] =
            (NSUInteger)(uintptr_t)[enumerator retain];
        // The host collection's mutation counter is not guest-addressable.
        // Use a stable guest sentinel while the host enumerator performs its
        // own mutation checks at each nextObject fetch.
        state->extra[4] = 1;
    } else {
        enumerator = (NSEnumerator *)(uintptr_t)state->extra[0];
    }

    state->itemsPtr = objects;
    state->mutationsPtr = &state->extra[4];

    // A guest mutation sentinel cannot mirror the host collection's internal
    // counter. Returning one object per batch forces the next host-enumerator
    // fetch between guest loop iterations, preserving its mutation checks.
    count = MIN(count, (NSUInteger)1);
    NSUInteger produced = 0;
    BOOL exhausted = NO;
    while(produced < count) {
        id object = [enumerator nextObject];
        if(!object) {
            exhausted = YES;
            break;
        }
        objects[produced++] = object;
    }
    state->state += produced;
    if(exhausted) {
        [enumerator release];
        state->extra[0] = 0;
    }
    return produced;
}

@implementation NSArray (LC32FastEnumeration)
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])objects
                                    count:(NSUInteger)count {
    NSEnumerator *enumerator = state && state->state
        ? (NSEnumerator *)(uintptr_t)state->extra[0]
        : [self objectEnumerator];
    return LC32CountByEnumerating(enumerator, state, objects, count);
}
@end

@implementation NSDictionary (LC32FastEnumeration)
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])objects
                                    count:(NSUInteger)count {
    // NSDictionary fast enumeration yields keys.
    NSEnumerator *enumerator = state && state->state
        ? (NSEnumerator *)(uintptr_t)state->extra[0]
        : [self keyEnumerator];
    return LC32CountByEnumerating(enumerator, state, objects, count);
}
@end

@implementation NSSet (LC32FastEnumeration)
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])objects
                                    count:(NSUInteger)count {
    NSEnumerator *enumerator = state && state->state
        ? (NSEnumerator *)(uintptr_t)state->extra[0]
        : [self objectEnumerator];
    return LC32CountByEnumerating(enumerator, state, objects, count);
}
@end

@implementation NSOrderedSet (LC32FastEnumeration)
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])objects
                                    count:(NSUInteger)count {
    NSEnumerator *enumerator = state && state->state
        ? (NSEnumerator *)(uintptr_t)state->extra[0]
        : [self objectEnumerator];
    return LC32CountByEnumerating(enumerator, state, objects, count);
}
@end

@implementation NSEnumerator (LC32FastEnumeration)
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained [])objects
                                    count:(NSUInteger)count {
    return LC32CountByEnumerating(self, state, objects, count);
}
@end
