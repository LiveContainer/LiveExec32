#import <Foundation/Foundation.h>
#include <stdio.h>

// The same public-API fixture runs natively and under ARM32. NSNotFound is
// NSIntegerMax, not NSUIntegerMax, and must follow the caller's word size.
static unsigned checks, failures;

static void check(const char *name, BOOL passed) {
    printf("foundation-not-found-%s: %s\n", name, passed ? "PASS" : "FAIL");
    ++checks;
    failures += !passed;
}

static void indexEquals(const char *name, NSUInteger actual, NSUInteger expected) {
    printf("foundation-not-found-%s: %s (actual=0x%lx expected=0x%lx)\n",
        name, actual == expected ? "PASS" : "FAIL",
        (unsigned long)actual, (unsigned long)expected);
    ++checks;
    failures += actual != expected;
}

static void arrayIndexes(void) {
    NSMutableString *member = [NSMutableString stringWithString:@"equal value"];
    NSMutableString *equalButDistinct = [NSMutableString stringWithString:@"equal value"];
    NSArray *array = @[@"first", member, @"last"];
    check("identity-fixture-is-distinct-but-equal",
        member != equalButDistinct && [member isEqual:equalButDistinct]);
    indexEquals("array-equality-first-hit", [array indexOfObject:@"first"], 0);
    indexEquals("array-equality-hit", [array indexOfObject:equalButDistinct], 1);
    indexEquals("array-equality-miss", [array indexOfObject:@"absent"], NSNotFound);
    indexEquals("array-ranged-hit", [array indexOfObject:@"last" inRange:NSMakeRange(1, 2)], 2);
    indexEquals("array-ranged-absent-miss",
        [array indexOfObject:@"absent" inRange:NSMakeRange(0, 3)], NSNotFound);
    indexEquals("array-ranged-excluded-miss",
        [array indexOfObject:member inRange:NSMakeRange(2, 1)], NSNotFound);
    indexEquals("array-ranged-empty-miss",
        [array indexOfObject:member inRange:NSMakeRange(1, 0)], NSNotFound);
    indexEquals("array-identity-hit", [array indexOfObjectIdenticalTo:member], 1);
    indexEquals("array-identity-equal-value-miss",
        [array indexOfObjectIdenticalTo:equalButDistinct], NSNotFound);
    indexEquals("array-identity-absent-miss",
        [array indexOfObjectIdenticalTo:@"absent"], NSNotFound);
    indexEquals("array-identity-ranged-hit",
        [array indexOfObjectIdenticalTo:member inRange:NSMakeRange(1, 1)], 1);
    indexEquals("array-identity-ranged-equal-value-miss",
        [array indexOfObjectIdenticalTo:equalButDistinct inRange:NSMakeRange(0, 3)], NSNotFound);
    indexEquals("array-identity-ranged-excluded-miss",
        [array indexOfObjectIdenticalTo:member inRange:NSMakeRange(2, 1)], NSNotFound);
    indexEquals("array-identity-ranged-empty-miss",
        [array indexOfObjectIdenticalTo:member inRange:NSMakeRange(3, 0)], NSNotFound);
    NSArray *empty = [NSArray array];
    indexEquals("empty-array-equality", [empty indexOfObject:member], NSNotFound);
    indexEquals("empty-array-ranged-equality",
        [empty indexOfObject:member inRange:NSMakeRange(0, 0)], NSNotFound);
    indexEquals("empty-array-identity", [empty indexOfObjectIdenticalTo:member], NSNotFound);
    indexEquals("empty-array-ranged-identity",
        [empty indexOfObjectIdenticalTo:member inRange:NSMakeRange(0, 0)], NSNotFound);

    NSOrderedSet *ordered = [NSOrderedSet orderedSetWithArray:array];
    indexEquals("ordered-set-first-hit", [ordered indexOfObject:@"first"], 0);
    indexEquals("ordered-set-equality-hit", [ordered indexOfObject:equalButDistinct], 1);
    indexEquals("ordered-set-last-hit", [ordered indexOfObject:@"last"], 2);
    indexEquals("ordered-set-miss", [ordered indexOfObject:@"absent"], NSNotFound);
    indexEquals("empty-ordered-set-miss", [[NSOrderedSet orderedSet] indexOfObject:member], NSNotFound);
    NSMutableOrderedSet *mutable = [NSMutableOrderedSet orderedSetWithArray:array];
    indexEquals("mutable-ordered-set-hit", [mutable indexOfObject:member], 1);
    indexEquals("mutable-ordered-set-miss", [mutable indexOfObject:@"absent"], NSNotFound);
}

static void indexSetQueries(void) {
    NSIndexSet *empty = [NSIndexSet indexSet];
    indexEquals("empty-index-set-first", empty.firstIndex, NSNotFound);
    indexEquals("empty-index-set-last", empty.lastIndex, NSNotFound);
    indexEquals("empty-index-set-greater", [empty indexGreaterThanIndex:5], NSNotFound);
    indexEquals("empty-index-set-less", [empty indexLessThanIndex:5], NSNotFound);
    indexEquals("empty-index-set-greater-equal", [empty indexGreaterThanOrEqualToIndex:5], NSNotFound);
    indexEquals("empty-index-set-less-equal", [empty indexLessThanOrEqualToIndex:5], NSNotFound);

    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    [indexes addIndex:2]; [indexes addIndex:5]; [indexes addIndex:9];
    indexEquals("index-set-first-hit", indexes.firstIndex, 2);
    indexEquals("index-set-last-hit", indexes.lastIndex, 9);
    indexEquals("index-set-greater-hit", [indexes indexGreaterThanIndex:2], 5);
    indexEquals("index-set-less-hit", [indexes indexLessThanIndex:9], 5);
    indexEquals("index-set-greater-equal-hit", [indexes indexGreaterThanOrEqualToIndex:5], 5);
    indexEquals("index-set-less-equal-hit", [indexes indexLessThanOrEqualToIndex:5], 5);
    indexEquals("index-set-greater-gap-hit", [indexes indexGreaterThanOrEqualToIndex:6], 9);
    indexEquals("index-set-less-gap-hit", [indexes indexLessThanOrEqualToIndex:4], 2);
    indexEquals("index-set-greater-miss", [indexes indexGreaterThanIndex:9], NSNotFound);
    indexEquals("index-set-less-miss", [indexes indexLessThanIndex:2], NSNotFound);
    indexEquals("index-set-greater-equal-miss", [indexes indexGreaterThanOrEqualToIndex:10], NSNotFound);
    indexEquals("index-set-less-equal-miss", [indexes indexLessThanOrEqualToIndex:1], NSNotFound);

    // Bound these canonical sentinel loops so a regression cannot hang a run.
    NSUInteger forwardCount = 0, backwardCount = 0, forwardSum = 0, backwardSum = 0;
    NSUInteger forward = indexes.firstIndex, backward = indexes.lastIndex;
    while(forward != NSNotFound && forwardCount < 4) {
        forwardSum += forward;
        ++forwardCount;
        forward = [indexes indexGreaterThanIndex:forward];
    }
    while(backward != NSNotFound && backwardCount < 4) {
        backwardSum += backward;
        ++backwardCount;
        backward = [indexes indexLessThanIndex:backward];
    }
    check("index-set-forward-enumeration-stops", forward == NSNotFound && forwardCount == 3 && forwardSum == 16);
    check("index-set-backward-enumeration-stops", backward == NSNotFound && backwardCount == 3 && backwardSum == 16);
    NSIndexSet *zero = [NSIndexSet indexSetWithIndex:0];
    indexEquals("index-set-zero-first-hit", zero.firstIndex, 0);
    indexEquals("index-set-zero-last-hit", zero.lastIndex, 0);
    indexEquals("index-set-below-zero-miss", [zero indexLessThanIndex:0], NSNotFound);
    indexEquals("index-set-above-zero-miss", [zero indexGreaterThanIndex:0], NSNotFound);
    NSUInteger highest = NSNotFound - 1;
    NSIndexSet *high = [NSIndexSet indexSetWithIndex:highest];
    indexEquals("index-set-high-valid-first-hit", high.firstIndex, highest);
    indexEquals("index-set-high-valid-last-hit", high.lastIndex, highest);
    indexEquals("index-set-after-high-valid-miss", [high indexGreaterThanIndex:highest], NSNotFound);
}

static void guardedMutableRemoval(void) {
    NSMutableArray *array = [NSMutableArray arrayWithArray:@[@"first", @"middle", @"last"]];
    NSUInteger missing = [array indexOfObject:@"absent"];
    BOOL enteredRemoval = NO;
    if(missing != NSNotFound) {
        enteredRemoval = YES;
        // Record the bad branch without triggering a separate native exception
        // unwind failure on unfixed builds. Valid removals below use the API.
        if(missing < array.count) [array removeObjectAtIndex:missing];
    }
    indexEquals("mutable-array-miss-sentinel", missing, NSNotFound);
    check("guarded-miss-does-not-enter-remove", !enteredRemoval && array.count == 3);
    NSUInteger hit = [array indexOfObject:@"middle"];
    indexEquals("mutable-array-hit-index", hit, 1);
    if(hit != NSNotFound && hit < array.count) [array removeObjectAtIndex:hit];
    check("guarded-hit-removes-correct-object", [array isEqual:@[@"first", @"last"]]);
    indexEquals("removed-object-now-misses", [array indexOfObject:@"middle"], NSNotFound);
}

int main(void) {
    @autoreleasepool {
        arrayIndexes();
        indexSetQueries();
        guardedMutableRemoval();
    }
    printf("Foundation NSNotFound summary: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
