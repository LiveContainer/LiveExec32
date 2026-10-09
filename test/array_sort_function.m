#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;
static unsigned deallocations;

static void check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

@interface SortItem : NSObject {
@public
    NSInteger value;
}
@end
@implementation SortItem
- (void)dealloc {
    ++deallocations;
    [super dealloc];
}
@end

typedef struct {
    NSInteger direction;
    unsigned calls;
    void *expected;
    BOOL objects;
    BOOL nested;
} SortContext;

static NSInteger compareNumbers(id first, id second, void *opaque) {
    SortContext *context = opaque;
    if(context) {
        check("array-sort-context-identity", context->expected == context);
        ++context->calls;
    }
    NSInteger a = context && context->objects
        ? ((SortItem *)first)->value : [first integerValue];
    NSInteger b = context && context->objects
        ? ((SortItem *)second)->value : [second integerValue];
    if(context && context->nested) {
        context->nested = NO;
        NSMutableArray *inner = [NSMutableArray arrayWithObjects:@2, @1, nil];
        [inner sortUsingFunction:compareNumbers context:NULL];
        check("array-sort-reentrant-comparator", [inner isEqual:@[@1, @2]]);
    }
    return (a < b ? -1 : a > b ? 1 : 0) * (context ? context->direction : 1);
}

int main(void) {
    @autoreleasepool {
        SortContext context = { .direction = 1 };
        context.expected = &context;
        NSMutableArray *values = [NSMutableArray arrayWithObjects:@3, @1, @2, @1, nil];
        id original = values;
        [values sortUsingFunction:compareNumbers context:&context];
        check("array-sort-ascending-duplicates", [values isEqual:@[@1, @1, @2, @3]]);
        check("array-sort-mutates-existing-array", values == original && context.calls > 0);
        context.direction = -1;
        [values sortUsingFunction:compareNumbers context:&context];
        check("array-sort-descending-signed-result", [values isEqual:@[@3, @2, @1, @1]]);
        [values sortUsingFunction:compareNumbers context:NULL];
        check("array-sort-null-context", [values isEqual:@[@1, @1, @2, @3]]);
        context.direction = 1;
        context.nested = YES;
        [values sortUsingFunction:compareNumbers context:&context];
        check("array-sort-nested-completed", !context.nested);

        NSMutableArray *empty = [NSMutableArray array];
        [empty sortUsingFunction:compareNumbers context:NULL];
        check("array-sort-empty", empty.count == 0);
        [empty addObject:@42];
        [empty sortUsingFunction:compareNumbers context:NULL];
        check("array-sort-singleton", [empty isEqual:@[@42]]);

        @autoreleasepool {
            NSMutableArray *items = [[NSMutableArray alloc] init];
            for(NSInteger i = 3; i > 0; --i) {
                SortItem *item = [SortItem new];
                item->value = i;
                [items addObject:item];
                [item release];
            }
            context.objects = YES;
            [items sortUsingFunction:compareNumbers context:&context];
            check("array-sort-guest-object-identity", ((SortItem *)items[0])->value == 1 &&
                  ((SortItem *)items[1])->value == 2 && ((SortItem *)items[2])->value == 3);
            [items release];
        }
        check("array-sort-object-lifetime", deallocations == 3);
    }
    return failures;
}
