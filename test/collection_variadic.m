#import <Foundation/Foundation.h>

#include <stdio.h>

static int check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return !passed;
}

int main(void) {
    int failed = 0;

    NSArray *array = [NSArray arrayWithObjects:@"zero", @"one", @"two", nil];
    failed += check("array-class", array.count == 3 &&
                    [[array objectAtIndex:2] isEqual:@"two"]);
    NSArray *initializedArray =
        [[NSArray alloc] initWithObjects:@"first", @"second", nil];
    failed += check("array-init", initializedArray.count == 2 &&
                    [[initializedArray objectAtIndex:1] isEqual:@"second"]);

    NSSet *set = [NSSet setWithObjects:@"duplicate", @"duplicate",
                                         @"unique", nil];
    failed += check("set-class", set.count == 2 &&
                    [set containsObject:@"unique"]);
    NSSet *initializedSet =
        [[NSSet alloc] initWithObjects:@"left", @"right", nil];
    failed += check("set-init", initializedSet.count == 2 &&
                    [initializedSet containsObject:@"right"]);

    NSOrderedSet *orderedSet = [NSOrderedSet
        orderedSetWithObjects:@"first", @"second", @"first", nil];
    failed += check("ordered-set-class", orderedSet.count == 2 &&
                    [[orderedSet objectAtIndex:1] isEqual:@"second"]);
    NSOrderedSet *initializedOrderedSet = [[NSOrderedSet alloc]
        initWithObjects:@"alpha", @"beta", nil];
    failed += check("ordered-set-init", initializedOrderedSet.count == 2 &&
                    [[initializedOrderedSet objectAtIndex:0] isEqual:@"alpha"]);

    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
        @"value-0", @"key-0", @7, @"key-1", @"value-2", @"key-2",
        @"value-3", @"key-3", @"value-4", @"key-4", @"value-5", @"key-5",
        @"value-6", @"key-6", @"value-7", @"key-7", nil];
    failed += check("dictionary-class", dictionary.count == 8 &&
                    [[dictionary objectForKey:@"key-0"] isEqual:@"value-0"] &&
                    [[dictionary objectForKey:@"key-1"] isEqual:@7] &&
                    [[dictionary objectForKey:@"key-7"] isEqual:@"value-7"]);
    NSDictionary *initializedDictionary = [[NSDictionary alloc]
        initWithObjectsAndKeys:@"left", @"a", @"right", @"b", nil];
    failed += check("dictionary-init", initializedDictionary.count == 2 &&
                    [[initializedDictionary objectForKey:@"b"]
                        isEqual:@"right"]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    failed += check("empty-array", [NSArray arrayWithObjects:nil].count == 0);
    failed += check("empty-set", [NSSet setWithObjects:nil].count == 0);
    failed += check("empty-ordered-set",
                    [NSOrderedSet orderedSetWithObjects:nil].count == 0);
    failed += check("empty-dictionary",
                    [NSDictionary dictionaryWithObjectsAndKeys:nil].count == 0);
#pragma clang diagnostic pop
    return failed;
}
