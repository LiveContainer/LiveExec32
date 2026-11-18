#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Model ADMS's dotted-key serialization: the dictionary holds guest-defined
// nodes, not the strings supplied by the caller. Autorelease precedes the
// first native-container insertion (and therefore lazy mirror publication).
@interface LC32ContextNode : NSObject {
    NSString *_value;
    NSMutableDictionary *_subValues;
}
@property(nonatomic, retain) NSString *value;
@property(nonatomic, retain) NSMutableDictionary *subValues;
@end

static unsigned created, destroyed;
static pthread_mutex_t countsLock = PTHREAD_MUTEX_INITIALIZER;
@implementation LC32ContextNode
@synthesize value = _value, subValues = _subValues;
- (id)init {
    if((self = [super init])) {
        pthread_mutex_lock(&countsLock);
        ++created;
        pthread_mutex_unlock(&countsLock);
        self.value = [NSString string];
        self.subValues = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)dealloc {
    pthread_mutex_lock(&countsLock);
    ++destroyed;
    pthread_mutex_unlock(&countsLock);
    [_value release];
    [_subValues release];
    [super dealloc];
}
@end

static void addValue(NSString *value, NSMutableDictionary *dictionary,
                     NSArray *keys, NSUInteger index) {
    NSString *key = [keys objectAtIndex:index];
    LC32ContextNode *node = [dictionary objectForKey:key];
    if(!node) node = [[[LC32ContextNode alloc] init] autorelease];
    if(index + 1 == keys.count) node.value = value;
    [dictionary setObject:node forKey:key];
    if(index + 1 < keys.count) addValue(value, node.subValues, keys, index + 1);
}

@interface LC32ContextObserver : NSObject {
@public
    unsigned failures;
}
- (void)convert:(NSNotification *)notification;
@end
@implementation LC32ContextObserver
- (void)convert:(NSNotification *)notification {
    (void)notification;
    for(unsigned iteration = 0; iteration < 500; ++iteration) {
        @autoreleasepool {
            NSAutoreleasePool *pool = [NSAutoreleasePool new];
            NSMutableDictionary *tree = [NSMutableDictionary new];
            for(unsigned i = 0; i < 9; ++i) {
                NSString *key = i ? [NSString stringWithFormat:@"a.key%u", i]
                                  : @"a.DaysSinceLastUse";
                addValue([NSString stringWithFormat:@"%u", iteration], tree,
                    [key componentsSeparatedByString:@"."], 0);
            }
            LC32ContextNode *root = [tree objectForKey:@"a"];
            LC32ContextNode *leaf = [root.subValues objectForKey:@"DaysSinceLastUse"];
            if(!root || !leaf) {
                fprintf(stderr, "missing context iteration=%u tree=%p root=%p leaf=%p count=%lu sub=%p\n",
                    iteration, tree, root, leaf, (unsigned long)tree.count, root.subValues);
                abort();
            }
            NSArray *owner = [[NSArray alloc] initWithObjects:leaf, nil];
            failures += [owner objectAtIndex:0] != leaf;
            // Only native containers retain the nodes after this drain.
            [pool drain];
            pool = [NSAutoreleasePool new];
            failures += [tree objectForKey:@"a"] != root;
            failures += [root.subValues objectForKey:@"DaysSinceLastUse"] != leaf;
            failures += (unsigned)leaf.value.intValue != iteration;
            [tree release];
            LC32ContextNode *survivor = [owner objectAtIndex:0];
            failures += survivor != leaf || (unsigned)survivor.value.intValue != iteration;
            [owner release];
            [pool drain];
        }
    }
}
@end

static void *run(void *unused) {
    (void)unused;
    @autoreleasepool {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        NSNotificationCenter *center = [NSNotificationCenter new];
        LC32ContextObserver *observer = [LC32ContextObserver new];
        [center addObserver:observer selector:@selector(convert:) name:@"context" object:nil];
        [center postNotificationName:@"context" object:nil];
        unsigned failures = observer->failures;
        [center removeObserver:observer];
        [observer release];
        [center release];
        [pool drain];
        return (void *)(uintptr_t)failures;
    }
}

int main(int argc, char **argv) {
    (void)argv;
    setvbuf(stdout, NULL, _IONBF, 0);
    pthread_t workers[4];
    unsigned started = 0, failures = 0;
    unsigned workerCount = argc > 1 ? 0 : 4;
    printf("context lifetime workers=%u\n", workerCount + 1);
    for(; started < workerCount; ++started) {
        if(pthread_create(&workers[started], NULL, run, NULL)) { ++failures; break; }
    }
    failures += (unsigned)(uintptr_t)run(NULL);
    for(unsigned i = 0; i < started; ++i) {
        void *result = NULL;
        if(pthread_join(workers[i], &result)) ++failures;
        failures += (unsigned)(uintptr_t)result;
    }
    printf("context lifetime: %u failures; created=%u destroyed=%u\n",
        failures, created, destroyed);
    return failures != 0 || created != destroyed;
}
