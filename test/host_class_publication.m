#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <mach/mach_traps.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

@interface NSObject (LC32HostClassPublicationTests)
- (uint64_t)host_self;
@end
extern uint64_t LC32GetHostSelector(SEL selector);
extern uint64_t LC32InvokeHostSelector(uint64_t object, uint64_t selector, ...);

enum { Workers = 8, Rounds = 16 };
static Class classes[Rounds];
static uint32_t ready[Rounds], start[Rounds], done[Rounds];
static uint64_t mirrors[Rounds][Workers];
static uint64_t hostClasses[Rounds][Workers];

static void waitFor(uint32_t *value, uint32_t expected) {
    while(__atomic_load_n(value, __ATOMIC_ACQUIRE) != expected) swtch();
}

static void *publish(void *opaque) {
    const unsigned worker = (unsigned)(uintptr_t)opaque;
    for(unsigned round = 0; round < Rounds; ++round) {
        @autoreleasepool {
            id object = class_createInstance(classes[round], 0);
            __atomic_add_fetch(&ready[round], 1, __ATOMIC_RELEASE);
            waitFor(&start[round], 1);
            const uint64_t host = [object host_self];
            mirrors[round][worker] = host;
            hostClasses[round][worker] = host ? LC32InvokeHostSelector(host,
                LC32GetHostSelector(@selector(class)), (uint64_t)0) : 0;
            __atomic_add_fetch(&done[round], 1, __ATOMIC_RELEASE);
            waitFor(&start[round], 2);
            [object release];
        }
    }
    return NULL;
}

int main(void) {
    @autoreleasepool {
        for(unsigned round = 0; round < Rounds; ++round) {
            char name[80];
            snprintf(name, sizeof(name), "LC32ConcurrentParent%u", round);
            Class parent = objc_allocateClassPair(NSObject.class, name, 0);
            if(!parent) return 2;
            objc_registerClassPair(parent);
            snprintf(name, sizeof(name), "LC32ConcurrentChild%u", round);
            classes[round] = objc_allocateClassPair(parent, name, 0);
            if(!classes[round]) return 2;
            objc_registerClassPair(classes[round]);
        }
        pthread_t workers[Workers];
        for(unsigned index = 0; index < Workers; ++index) {
            if(pthread_create(&workers[index], NULL, publish,
                    (void *)(uintptr_t)index)) return 2;
        }
        unsigned failures = 0;
        for(unsigned round = 0; round < Rounds; ++round) {
            waitFor(&ready[round], Workers);
            __atomic_store_n(&start[round], 1, __ATOMIC_RELEASE);
            waitFor(&done[round], Workers);
            for(unsigned worker = 0; worker < Workers; ++worker) {
                if(!mirrors[round][worker] || !hostClasses[round][worker] ||
                    hostClasses[round][worker] != hostClasses[round][0]) failures++;
                for(unsigned prior = 0; prior < worker; ++prior)
                    if(mirrors[round][worker] == mirrors[round][prior]) failures++;
            }
            __atomic_store_n(&start[round], 2, __ATOMIC_RELEASE);
        }
        for(unsigned index = 0; index < Workers; ++index)
            pthread_join(workers[index], NULL);
        printf("host-class-concurrent-publication: %s (%u failures, %u rounds, %u workers)\n",
            failures ? "FAIL" : "PASS", failures, Rounds, Workers);
        return failures != 0;
    }
}
