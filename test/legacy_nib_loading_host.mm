#import "../HostFrameworks/UIKit/LegacyNibLoading.h"
#include <stdio.h>

@interface LC32TestNibBundle : NSBundle
@property(nonatomic, retain) NSException *failure;
@property(nonatomic, retain) NSArray *result;
@end
@implementation LC32TestNibBundle
- (NSArray *)loadNibNamed:(NSString *)name owner:(id)owner
                 options:(NSDictionary *)options {
    if(self.failure) @throw self.failure;
    return self.result;
}
@end

static unsigned failures;
static void check(BOOL passed, const char *name) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    if(!passed) ++failures;
}

int main(void) {
    @autoreleasepool {
        LC32TestNibBundle *bundle = [LC32TestNibBundle new];
        bundle.result = @[@"loaded object"];
        check(LC32LoadGuestNib(bundle, @"Optional", nil, nil) == bundle.result,
              "successful-result-preserved");
        bundle.result = nil;
        check(LC32LoadGuestNib(bundle, @"Optional", nil, nil) == nil,
              "native-nil-preserved");
        NSString *missing = @"Could not load NIB in bundle: 'test' with name 'Optional'";
        bundle.failure = [NSException exceptionWithName:NSInternalInconsistencyException
            reason:missing userInfo:nil];
        check(LC32LoadGuestNib(bundle, @"Optional", nil, nil) == nil,
              "missing-optional-nib-returns-nil");
        NSArray *failuresToPreserve = @[
            [NSException exceptionWithName:NSInvalidUnarchiveOperationException
                reason:missing userInfo:nil],
            [NSException exceptionWithName:NSInternalInconsistencyException
                reason:@"awakeFromNib failed" userInfo:nil],
            [NSException exceptionWithName:NSInternalInconsistencyException
                reason:@"Could not load NIB in bundle: 'test' with name 'Nested'"
                userInfo:nil],
        ];
        for(NSException *expected in failuresToPreserve) {
            bundle.failure = expected;
            BOOL caught = NO;
            @try {
                LC32LoadGuestNib(bundle, @"Optional", nil, nil);
            } @catch(NSException *actual) {
                caught = actual == expected;
            }
            check(caught, "unrelated-exception-preserved");
        }
    }
    return failures ? 1 : 0;
}
