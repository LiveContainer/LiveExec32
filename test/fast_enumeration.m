#import <Foundation/Foundation.h>

#include <stdio.h>

static int checkCount(const char *name, NSUInteger actual,
                      NSUInteger expected) {
    BOOL passed = actual == expected;
    printf("%s: %s (%u)\n", name, passed ? "PASS" : "FAIL",
           (unsigned)actual);
    return !passed;
}

int main(void) {
    int failed = 0;
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:40];
    NSMutableDictionary *dictionary =
        [NSMutableDictionary dictionaryWithCapacity:40];
    for(NSUInteger index = 0; index < 40; index++) {
        NSString *key = [NSString stringWithFormat:@"key-%u",
                                                   (unsigned)index];
        [array addObject:key];
        [dictionary setObject:key forKey:key];
    }

    NSUInteger arrayCount = 0;
    for(id object in array) if(object) arrayCount++;
    failed += checkCount("array-fast-enumeration", arrayCount, 40);

    NSUInteger dictionaryCount = 0;
    NSUInteger dictionaryValues = 0;
    for(id key in dictionary) {
        dictionaryCount++;
        if([dictionary objectForKey:key]) dictionaryValues++;
    }
    failed += checkCount("dictionary-fast-enumeration",
                         dictionaryCount, 40);
    failed += checkCount("dictionary-yields-keys", dictionaryValues, 40);

    NSSet *set = [NSSet setWithArray:array];
    NSUInteger setCount = 0;
    for(id object in set) if(object) setCount++;
    failed += checkCount("set-fast-enumeration", setCount, 40);

    NSOrderedSet *orderedSet = [NSOrderedSet orderedSetWithArray:array];
    NSUInteger orderedCount = 0;
    for(id object in orderedSet) if(object) orderedCount++;
    failed += checkCount("ordered-set-fast-enumeration", orderedCount, 40);

    NSUInteger enumeratorCount = 0;
    for(id object in [array objectEnumerator]) if(object) enumeratorCount++;
    failed += checkCount("enumerator-fast-enumeration", enumeratorCount, 40);
    return failed != 0;
}
