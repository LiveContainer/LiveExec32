#import <Foundation/Foundation.h>

@implementation NSMutableArray (LC32Sorting)

- (void)sortUsingFunction:(NSInteger (NS_NOESCAPE *)(id, id, void *))compare
                  context:(void *)context {
    /* Keep the function and opaque context in the guest. The existing block
     * bridge converts the native array elements and signed comparison result. */
    [self sortUsingComparator:^NSComparisonResult(id first, id second) {
        return compare(first, second, context);
    }];
}

@end
