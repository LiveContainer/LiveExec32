#import <Foundation/Foundation.h>
#import <GameKit/GameKit.h>
#import <LC32/LC32.h>

#include <stdio.h>
#include <string.h>

/* No Game Center authentication or reporting is needed: these are local
 * achievement properties. Compare guest accessors against direct native
 * calls so compiler-synthesized, guest-only ivars cannot pass the test. */
static unsigned failures;
static unsigned checks;

static void check(BOOL condition, const char *description) {
    checks++;
    if(!condition) failures++;
    printf("%s %s\n", condition ? "PASS" : "FAIL", description);
}

static id nativeObject(id receiver, SEL selector) {
    return LC32InvokeHostObjectSelector(
        [receiver host_self], LC32GetHostSelector(selector), (uint64_t)0);
}

static double nativePercentComplete(GKAchievement *achievement) {
    uint64_t bits = LC32InvokeHostSelector([achievement host_self],
        LC32GetHostSelector(@selector(percentComplete)), (uint64_t)0);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static double nativeBoxedPercentComplete(GKAchievement *achievement) {
    NSNumber *value = LC32InvokeHostObjectSelector([achievement host_self],
        LC32GetHostSelector(@selector(valueForKey:)),
        [@"percentComplete" host_self], (uint64_t)0);
    return [value doubleValue];
}

static void setNativePercentComplete(GKAchievement *achievement, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    LC32InvokeHostSelector([achievement host_self],
        LC32GetHostSelector(@selector(setPercentComplete:)), bits,
        (uint64_t)0);
}

int main(void) {
    @autoreleasepool {
        NSString *identifier = @"org.liveexec32.test.local-achievement";
        GKAchievement *achievement = [[GKAchievement alloc]
            initWithIdentifier:identifier];
        check(achievement != nil, "achievement initializes locally");
        check([nativeObject(achievement, @selector(identifier))
                  isEqualToString:identifier],
              "native initializer preserves identifier");
        check([[achievement identifier] isEqualToString:identifier],
              "guest identifier reads native initializer state");

        /* This is the cache insertion used by older Game Center clients.
         * Avoid an uncaught nil-key exception so other failures are reported. */
        NSMutableDictionary *cache = [NSMutableDictionary dictionary];
        NSString *key = [achievement identifier];
        if(key) [cache setObject:achievement forKey:key];
        check([cache objectForKey:identifier] == achievement,
              "initialized identifier is a usable achievement-cache key");

        NSString *replacement = @"org.liveexec32.test.changed-achievement";
        [achievement setIdentifier:replacement];
        check([nativeObject(achievement, @selector(identifier))
                  isEqualToString:replacement],
              "guest identifier setter updates native state");
        check([[achievement identifier] isEqualToString:replacement],
              "guest identifier setter and getter agree");

        LC32InvokeHostSelector([achievement host_self],
            LC32GetHostSelector(@selector(setIdentifier:)),
            [identifier host_self], (uint64_t)0);
        check([[achievement identifier] isEqualToString:identifier],
              "guest identifier observes later native mutations");

        [achievement setPercentComplete:42.125];
        printf("Guest-set percentage: native=%.17g guest=%.17g (%s)\n",
               nativePercentComplete(achievement), [achievement percentComplete],
               [[achievement description] UTF8String]);
        check(nativeBoxedPercentComplete(achievement) == 42.125,
              "native KVC independently confirms guest percentage setter");
        check(nativePercentComplete(achievement) == 42.125,
              "guest double setter updates native percent complete");
        check([achievement percentComplete] == 42.125,
              "guest double getter preserves percent-complete precision");
        setNativePercentComplete(achievement, 84.375);
        printf("Native-set percentage: native=%.17g guest=%.17g (%s)\n",
               nativePercentComplete(achievement), [achievement percentComplete],
               [[achievement description] UTF8String]);
        check(nativeBoxedPercentComplete(achievement) == 84.375,
              "native KVC independently confirms direct percentage setter");
        check([achievement percentComplete] == 84.375,
              "guest percent complete observes native mutations");

        NSDate *nativeDate = nativeObject(achievement,
                                          @selector(lastReportedDate));
        check([[achievement lastReportedDate] host_self] ==
                  [nativeDate host_self],
              "guest last-reported date matches native property");

        [achievement release];
    }
    printf("%u/%u achievement-property checks passed\n",
           checks - failures, checks);
    return failures ? 1 : 0;
}
