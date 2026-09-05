#import <Foundation/Foundation.h>

#include <inttypes.h>
#include <stdio.h>

static int check_file_manager(NSFileManager *manager, NSString *path,
                              const char *label) {
    NSError *error = nil;
    NSDictionary *attributes = [manager
        attributesOfFileSystemForPath:path error:&error];
    NSNumber *freeSize = [attributes objectForKey:NSFileSystemFreeSize];
    unsigned long long freeBytes = [freeSize unsignedLongLongValue];

    printf("%s path=%s free=%" PRIu64 "\n",
        label, [path UTF8String], (uint64_t)freeBytes);
    fflush(stdout);
    if(manager == nil || attributes == nil || error != nil ||
            freeSize == nil || freeBytes <= 50000000ULL) {
        fprintf(stderr,
            "%s filesystem attributes failed: manager=%p "
            "attributes=%p error=%s freeSize=%p\n",
            label, manager, attributes,
            [[error description] UTF8String], freeSize);
        return 1;
    }
    return 0;
}

int main(void) {
    @autoreleasepool {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES);
        if([paths count] == 0) {
            fprintf(stderr, "Documents directory lookup returned no paths\n");
            return 1;
        }

        NSString *path = [paths objectAtIndex:0];
        NSFileManager *newManager = [NSFileManager new];
        if(check_file_manager(newManager, path, "new") != 0) {
            [newManager release];
            return 1;
        }
        [newManager release];

        NSFileManager *initializedManager =
            [[NSFileManager alloc] init];
        if(check_file_manager(
                initializedManager, path, "alloc/init") != 0) {
            [initializedManager release];
            return 1;
        }
        [initializedManager release];

        return check_file_manager(
            [NSFileManager defaultManager], path, "defaultManager");
    }
}
