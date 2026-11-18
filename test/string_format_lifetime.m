#import <Foundation/Foundation.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>

static NSString *newFormattedString(unsigned variant, NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *result = variant == 2
        ? [[NSString alloc] initWithFormat:format arguments:arguments]
        : [[NSString alloc] initWithFormat:format locale:nil arguments:arguments];
    va_end(arguments);
    return result;
}

static unsigned testInitializerMappings(void) {
    unsigned failures = 0;
    for(unsigned variant = 0; variant < 4; ++variant) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        NSString *string = variant == 0
            ? [[NSString alloc] initWithFormat:@"mapping-%u", variant]
            : variant == 1
            ? [[NSString alloc] initWithFormat:@"mapping-%u" locale:nil, variant]
            : newFormattedString(variant, @"mapping-%u", variant);
        NSArray *owner = [[NSArray alloc] initWithObjects:string, nil];
        BOOL canonical = string && [owner objectAtIndex:0] == string;
        printf("format-init-%u-canonical-mapping: %s\n", variant,
            canonical ? "PASS" : "FAIL");
        failures += !canonical;
        [string release];
        [pool drain];
        pool = [NSAutoreleasePool new];
        NSString *expected = [NSString stringWithFormat:@"mapping-%u", variant];
        BOOL alive = [[owner objectAtIndex:0] isEqualToString:expected];
        printf("format-init-%u-container-lifetime: %s\n", variant,
            alive ? "PASS" : "FAIL");
        failures += !alive;
        [owner release];
        [pool drain];
    }
    return failures;
}

// Exercise SpongeBob's date -> formatted string -> dictionary path inside
// native notification callbacks. This is stress coverage, not a reproducer
// for the original intermittent startup exception. The later custom-node
// dictionary conversion is covered by context_data_lifetime.m.
enum { Iterations = 2000, WorkerCount = 4 };

static void *formatDates(void *context) {
    unsigned failures = 0;
    for(unsigned i = 0; i < Iterations; ++i) {
        @autoreleasepool {
            // An ARM32 @autoreleasepool alone does not drain native +0
            // Foundation results. Exercise both pool implementations.
            NSAutoreleasePool *nativePool = [NSAutoreleasePool new];
            NSDate *start = [NSDate dateWithTimeIntervalSinceReferenceDate:1000];
            NSDate *end = [NSDate dateWithTimeIntervalSinceReferenceDate:
                1000 + (i % 3) * 86400.0];
            NSString *days = [NSString stringWithFormat:@"%1.0f",
                floor([end timeIntervalSinceDate:start] / 86400.0)];
            if(!days || days.length != 1 || days.intValue != i % 3) {
                ++failures;
                printf("format-date failure worker=%lu iteration=%u result=%s\n",
                    (unsigned long)(uintptr_t)context, i,
                    days.UTF8String ?: "<nil>");
                [nativePool drain];
                break;
            }
            NSMutableDictionary *data = [NSMutableDictionary dictionary];
            [data setObject:days forKey:@"a.DaysSinceLastUse"];
            [nativePool drain];
        }
    }
    return (void *)(uintptr_t)failures;
}

@interface LC32FormatNotificationObserver : NSObject {
@public
    unsigned failures;
    unsigned workerIndex;
}
- (void)formatNotification:(NSNotification *)notification;
@end
@implementation LC32FormatNotificationObserver
- (void)formatNotification:(NSNotification *)notification {
    (void)notification;
    failures += (unsigned)(uintptr_t)formatDates((void *)(uintptr_t)workerIndex);
}
@end

static void *formatNotification(void *context) {
    @autoreleasepool {
        NSNotificationCenter *center = [NSNotificationCenter new];
        LC32FormatNotificationObserver *observer = [LC32FormatNotificationObserver new];
        observer->workerIndex = (unsigned)(uintptr_t)context;
        [center addObserver:observer selector:@selector(formatNotification:)
                       name:@"format" object:nil];
        [center postNotificationName:@"format" object:nil];
        unsigned failures = observer->failures;
        [center removeObserver:observer];
        [observer release];
        [center release];
        return (void *)(uintptr_t)failures;
    }
}

int main(void) {
    pthread_t workers[WorkerCount];
    setvbuf(stdout, NULL, _IONBF, 0);
    unsigned started = 0, failures = testInitializerMappings();
    for(; started < WorkerCount; ++started) {
        if(pthread_create(&workers[started], NULL, formatNotification,
                (void *)(uintptr_t)started)) { ++failures; break; }
    }
    failures += (unsigned)(uintptr_t)formatNotification((void *)(uintptr_t)WorkerCount);
    for(unsigned i = 0; i < started; ++i) {
        void *result = NULL;
        if(pthread_join(workers[i], &result)) ++failures;
        failures += (unsigned)(uintptr_t)result;
    }
    printf("format-date lifetime: %u failures\n", failures);
    return failures != 0;
}
