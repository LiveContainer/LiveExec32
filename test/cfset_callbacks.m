#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int deallocations;

@interface LC32SetProbe : NSObject
@end

@implementation LC32SetProbe
- (void)dealloc {
    ++deallocations;
    [super dealloc];
}
@end

static int report(const char *name, int passed) {
    printf("cfset-callbacks-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);

    @autoreleasepool {
        int passed = 1;
        CFMutableSetRef nonretaining = CFSetCreateMutable(
            kCFAllocatorDefault, 0, NULL);
        LC32SetProbe *weakProbe = [LC32SetProbe new];
        [(NSMutableSet *)nonretaining addObject:weakProbe];

        NSUInteger enumerationCount = 0;
        id enumeratedObject = nil;
        for(id object in (NSSet *)nonretaining) {
            ++enumerationCount;
            enumeratedObject = object;
        }
        passed &= report("null-identity-and-enumeration",
            nonretaining && CFSetGetCount(nonretaining) == 1 &&
            CFSetContainsValue(nonretaining, weakProbe) &&
            CFSetGetValue(nonretaining, weakProbe) == weakProbe &&
            enumerationCount == 1 && enumeratedObject == weakProbe);

        [weakProbe release];
        passed &= report("null-does-not-retain", deallocations == 1);
        CFRelease(nonretaining);

        NSMutableString *first =
            [[NSMutableString alloc] initWithString:@"same"];
        NSMutableString *second =
            [[NSMutableString alloc] initWithString:@"same"];
        NSMutableString *third =
            [[NSMutableString alloc] initWithString:@"same"];
        const CFSetCallBacks zeroCallbacks = {};
        CFMutableSetRef identity = CFSetCreateMutable(
            kCFAllocatorDefault, 0, &zeroCallbacks);
        CFSetAddValue(identity, first);
        [(NSMutableSet *)identity addObject:second];
        passed &= report("null-pointer-identity",
            CFSetGetCount(identity) == 2 &&
            CFSetContainsValue(identity, first) &&
            CFSetContainsValue(identity, second) &&
            !CFSetContainsValue(identity, third));

        CFSetRef identityCopy = CFSetCreateCopy(
            kCFAllocatorDefault, identity);
        CFMutableSetRef mutableIdentityCopy = CFSetCreateMutableCopy(
            kCFAllocatorDefault, 0, identity);
        CFSetAddValue(mutableIdentityCopy, third);
        passed &= report("null-copy-callbacks",
            CFSetGetCount(identityCopy) == 2 &&
            !CFSetContainsValue(identityCopy, third) &&
            CFSetGetCount(mutableIdentityCopy) == 3);
        const void *identityValues[] = {first, second};
        CFSetRef immutableIdentity = CFSetCreate(
            kCFAllocatorDefault, identityValues, 2, NULL);
        passed &= report("null-immutable-create",
            CFSetGetCount(immutableIdentity) == 2 &&
            !CFSetContainsValue(immutableIdentity, third));
        CFRelease(immutableIdentity);
        CFRelease(mutableIdentityCopy);
        CFRelease(identityCopy);
        CFRelease(identity);
        [third release];
        [second release];
        [first release];

        CFMutableSetRef retaining = CFSetCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
        LC32SetProbe *strongProbe = [LC32SetProbe new];
        CFSetAddValue(retaining, strongProbe);
        [strongProbe release];
        passed &= report("cftype-retains", deallocations == 1 &&
            CFSetGetCount(retaining) == 1);
        CFRelease(retaining);
        passed &= report("cftype-releases", deallocations == 2);

        printf("cfset-callbacks-regression: %s\n",
            passed ? "PASS" : "FAIL");
        return !passed;
    }
}
