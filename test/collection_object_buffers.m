#import <Foundation/Foundation.h>

#include <stdio.h>

@interface NSMutableArray (LC32ObjectBufferTests)
- (void)addObjects:(const id [])objects count:(NSUInteger)count;
- (void)insertObjects:(const id [])objects
                count:(NSUInteger)count
              atIndex:(NSUInteger)index;
@end

@interface NSMutableSet (LC32ObjectBufferTests)
- (void)addObjects:(const id [])objects count:(NSUInteger)count;
@end

@interface NSMutableOrderedSet (LC32ObjectBufferTests)
- (void)addObjects:(const id [])objects count:(NSUInteger)count;
- (void)insertObjects:(const id [])objects
                count:(NSUInteger)count
              atIndex:(NSUInteger)index;
@end

@interface NSMutableDictionary (LC32ObjectBufferTests)
- (void)addObjects:(const id [])objects
            forKeys:(const id<NSCopying> [])keys
              count:(NSUInteger)count;
- (void)setObjects:(const id [])objects
           forKeys:(const id<NSCopying> [])keys
             count:(NSUInteger)count;
@end

@interface NSSet (LC32ObjectBufferOwnershipTests)
+ (instancetype)newSetWithObjects:(const id [])objects
                            count:(NSUInteger)count;
@end

static int check(const char *name, BOOL passed) {
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
    return !passed;
}

int main(void) {
    int failed = 0;

    id objects[] = {@"zero", @"one", @"two"};
    NSArray *array = [NSArray arrayWithObjects:objects count:3];
    failed += check("counted-array", array.count == 3 &&
                    [[array objectAtIndex:2] isEqual:@"two"]);

    NSArray *literal = @[@"literal-zero", @"literal-one"];
    failed += check("array-literal", literal.count == 2 &&
                    [[literal objectAtIndex:1] isEqual:@"literal-one"]);

    NSArray *initializedArray =
        [[NSArray alloc] initWithObjects:objects count:3];
    failed += check("counted-array-init", initializedArray.count == 3 &&
                    [[initializedArray objectAtIndex:0] isEqual:@"zero"]);

    NSSet *set = [NSSet setWithObjects:objects count:3];
    failed += check("counted-set", set.count == 3 &&
                    [set containsObject:@"one"]);

    NSSet *initializedSet = [[NSSet alloc] initWithObjects:objects count:3];
    failed += check("counted-set-init", initializedSet.count == 3 &&
                    [initializedSet containsObject:@"two"]);

    NSSet *newSet = [NSSet newSetWithObjects:objects count:3];
    failed += check("counted-set-new-family", newSet.count == 3 &&
                    [newSet containsObject:@"zero"]);
    [newSet release];

    id orderedObjects[] = {@"first", @"second", @"first"};
    NSOrderedSet *orderedSet = [NSOrderedSet
        orderedSetWithObjects:orderedObjects count:3];
    failed += check("counted-ordered-set", orderedSet.count == 2 &&
                    [[orderedSet objectAtIndex:1] isEqual:@"second"]);

    NSOrderedSet *initializedOrderedSet = [[NSOrderedSet alloc]
        initWithObjects:orderedObjects count:3];
    failed += check("counted-ordered-set-init",
                    initializedOrderedSet.count == 2 &&
                    [[initializedOrderedSet objectAtIndex:0]
                        isEqual:@"first"]);

    id values[] = {@"value-zero", @"value-one"};
    id<NSCopying> keys[] = {@"key-zero", @"key-one"};
    NSDictionary *dictionary = [NSDictionary dictionaryWithObjects:values
                                                            forKeys:keys
                                                              count:2];
    failed += check("counted-dictionary", dictionary.count == 2 &&
                    [[dictionary objectForKey:@"key-one"]
                        isEqual:@"value-one"]);

    NSDictionary *initializedDictionary = [[NSDictionary alloc]
        initWithObjects:values forKeys:keys count:2];
    failed += check("counted-dictionary-init",
                    initializedDictionary.count == 2 &&
                    [[initializedDictionary objectForKey:@"key-zero"]
                        isEqual:@"value-zero"]);

    NSDictionary *dictionaryLiteral = @{
        @"literal-key": @"literal-value"
    };
    failed += check("dictionary-literal", dictionaryLiteral.count == 1 &&
                    [[dictionaryLiteral objectForKey:@"literal-key"]
                        isEqual:@"literal-value"]);

    NSMutableArray *mutableArray = [NSMutableArray array];
    [mutableArray addObjects:objects count:2];
    id inserted[] = {@"inserted-zero", @"inserted-one"};
    [mutableArray insertObjects:inserted count:2 atIndex:1];
    failed += check("mutable-array-bulk", mutableArray.count == 4 &&
                    [[mutableArray objectAtIndex:1]
                        isEqual:@"inserted-zero"] &&
                    [[mutableArray objectAtIndex:3] isEqual:@"one"]);

    NSMutableSet *mutableSet = [NSMutableSet set];
    [mutableSet addObjects:orderedObjects count:3];
    failed += check("mutable-set-bulk", mutableSet.count == 2);

    NSMutableOrderedSet *mutableOrderedSet = [NSMutableOrderedSet
        orderedSet];
    [mutableOrderedSet addObjects:objects count:2];
    [mutableOrderedSet insertObjects:inserted count:2 atIndex:1];
    failed += check("mutable-ordered-set-bulk",
                    mutableOrderedSet.count == 4 &&
                    [[mutableOrderedSet objectAtIndex:2]
                        isEqual:@"inserted-one"]);

    NSMutableDictionary *mutableDictionary = [[NSMutableDictionary alloc]
        initWithObjects:values forKeys:keys count:2];
    failed += check("mutable-dictionary-init",
                    mutableDictionary.count == 2 &&
                    [[mutableDictionary objectForKey:@"key-one"]
                        isEqual:@"value-one"]);

    id addedValues[] = {@"added-value"};
    id<NSCopying> addedKeys[] = {@"added-key"};
    [mutableDictionary addObjects:addedValues forKeys:addedKeys count:1];
    [mutableDictionary setObjects:values forKeys:keys count:2];
    failed += check("mutable-dictionary-bulk",
                    mutableDictionary.count == 3 &&
                    [[mutableDictionary objectForKey:@"key-zero"]
                        isEqual:@"value-zero"] &&
                    [[mutableDictionary objectForKey:@"added-key"]
                        isEqual:@"added-value"]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    failed += check("empty-counted-array",
                    [NSArray arrayWithObjects:NULL count:0].count == 0);
    failed += check("empty-counted-dictionary",
                    [NSDictionary dictionaryWithObjects:NULL
                                                 forKeys:NULL
                                                   count:0].count == 0);
#pragma clang diagnostic pop

    return failed;
}
