#import <Foundation/Foundation.h>

#include <objc/runtime.h>
#include <pwd.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

NSUInteger NSPageSize(void) {
    const long pageSize = sysconf(_SC_PAGESIZE);
    return pageSize > 0 ? (NSUInteger)pageSize : 4096;
}

NSUInteger NSLogPageSize(void) {
    NSUInteger pageSize = NSPageSize();
    NSUInteger logarithm = 0;
    while(pageSize > 1) {
        pageSize >>= 1;
        logarithm++;
    }
    return logarithm;
}

NSUInteger NSRoundUpToMultipleOfPageSize(NSUInteger bytes) {
    const NSUInteger pageSize = NSPageSize();
    const NSUInteger mask = pageSize - 1;
    return (bytes + mask) & ~mask;
}

NSUInteger NSRoundDownToMultipleOfPageSize(NSUInteger bytes) {
    const NSUInteger pageSize = NSPageSize();
    return bytes & ~(pageSize - 1);
}

void *NSAllocateMemoryPages(NSUInteger bytes) {
    if(!bytes) bytes = 1;

    const NSUInteger roundedBytes =
        NSRoundUpToMultipleOfPageSize(bytes);
    if(roundedBytes < bytes) abort();

    void *memory = mmap(NULL, roundedBytes, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON, -1, 0);
    if(memory == MAP_FAILED) abort();
    return memory;
}

void NSDeallocateMemoryPages(void *pointer, NSUInteger bytes) {
    if(!pointer || !bytes) return;
    const NSUInteger roundedBytes =
        NSRoundUpToMultipleOfPageSize(bytes);
    if(roundedBytes >= bytes) munmap(pointer, roundedBytes);
}

void NSCopyMemoryPages(const void *source, void *destination,
                       NSUInteger bytes) {
    if(bytes) memmove(destination, source, bytes);
}

NSUInteger NSRealMemoryAvailable(void) {
    const uint64_t physicalMemory = NSProcessInfo.processInfo.physicalMemory;
    return physicalMemory > NSUIntegerMax
        ? NSUIntegerMax
        : (NSUInteger)physicalMemory;
}

void NSDeallocateObject(id object) {
    if(object) object_dispose(object);
}

BOOL NSShouldRetainWithZone(id object, NSZone *requestedZone) {
    (void)object;
    return !requestedZone || requestedZone == NSDefaultMallocZone();
}

NSRange NSUnionRange(NSRange range1, NSRange range2) {
    const NSUInteger start = MIN(range1.location, range2.location);
    const NSUInteger end = MAX(NSMaxRange(range1), NSMaxRange(range2));
    return NSMakeRange(start, end - start);
}

NSString *NSStringFromRange(NSRange range) {
    return [NSString stringWithFormat:@"{%lu, %lu}",
        (unsigned long)range.location, (unsigned long)range.length];
}

static NSString *LC32StringFromUserDatabaseField(const char *field) {
    return field && field[0] ? [NSString stringWithUTF8String:field] : nil;
}

NSString *NSUserName(void) {
    struct passwd *entry = getpwuid(getuid());
    NSString *name = entry ? LC32StringFromUserDatabaseField(entry->pw_name)
                           : nil;
    return name ?: @"mobile";
}

NSString *NSFullUserName(void) {
    struct passwd *entry = getpwuid(getuid());
    if(!entry || !entry->pw_gecos || !entry->pw_gecos[0]) {
        return NSUserName();
    }

    const char *separator = strchr(entry->pw_gecos, ',');
    if(!separator) return LC32StringFromUserDatabaseField(entry->pw_gecos);

    return [[[NSString alloc] initWithBytes:entry->pw_gecos
        length:(NSUInteger)(separator - entry->pw_gecos)
        encoding:NSUTF8StringEncoding] autorelease];
}

NSString *NSHomeDirectoryForUser(NSString *userName) {
    if(!userName) return nil;
    const char *name = userName.UTF8String;
    if(!name) return nil;
    struct passwd *entry = getpwnam(name);
    return entry ? LC32StringFromUserDatabaseField(entry->pw_dir) : nil;
}

NSString *NSOpenStepRootDirectory(void) {
    return @"/";
}
