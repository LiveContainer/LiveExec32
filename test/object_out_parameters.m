#import <Foundation/Foundation.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if __has_feature(objc_arc)
#error This regression requires explicit MRC ownership transitions.
#endif

typedef struct {
    uint32_t before;
    id value;
    uint32_t after;
} ObjectSlot;

_Static_assert(sizeof(id) == sizeof(uint32_t),
    "This regression must exercise the ARM32 object-pointer ABI");
_Static_assert(offsetof(ObjectSlot, after) ==
    offsetof(ObjectSlot, value) + sizeof(uint32_t),
    "The trailing canary must immediately follow the guest object slot");

static unsigned failures;

static void check(const char *name, BOOL passed) {
    printf("object-out-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

static ObjectSlot objectSlot(void) {
    const ObjectSlot slot = {0x12345678, nil, 0x87654321};
    return slot;
}

static BOOL intact(ObjectSlot slot) {
    return slot.before == 0x12345678 && slot.after == 0x87654321;
}

static void checkFormatter(void) {
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    [formatter setLocale:locale];
    [locale release];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setLenient:NO];

    /* Both arguments have the captured o^@ encoding. Keep their guarded
     * four-byte cells adjacent to catch native-width writes or aliasing. */
    struct {
        ObjectSlot result;
        ObjectSlot error;
    } outputs = {objectSlot(), objectSlot()};
    BOOL parsed = [formatter getObjectValue:&outputs.result.value
        forString:@"1234.5"
        errorDescription:(NSString **)&outputs.error.value];
    check("formatter-success", parsed &&
        [outputs.result.value isKindOfClass:[NSNumber class]] &&
        [outputs.result.value doubleValue] == 1234.5);
    check("formatter-success-width",
        intact(outputs.result) && intact(outputs.error));
    /* A successful call need not write its error argument. */

    outputs.result = objectSlot();
    outputs.error = objectSlot();
    parsed = [formatter getObjectValue:&outputs.result.value
        forString:@"not-a-number"
        errorDescription:(NSString **)&outputs.error.value];
    check("formatter-error", !parsed &&
        [outputs.error.value isKindOfClass:[NSString class]] &&
        [outputs.error.value length] > 0);
    check("formatter-error-width",
        intact(outputs.result) && intact(outputs.error));

    outputs.result = objectSlot();
    parsed = [formatter getObjectValue:&outputs.result.value
        forString:@"2468.5" errorDescription:NULL];
    check("formatter-null-error-success", parsed &&
        [outputs.result.value doubleValue] == 2468.5 &&
        intact(outputs.result));
    outputs.result = objectSlot();
    parsed = [formatter getObjectValue:&outputs.result.value
        forString:@"not-a-number" errorDescription:NULL];
    check("formatter-null-error-failure", !parsed && intact(outputs.result));

    /* NSFormatter explicitly permits either or both output pointers to be
     * NULL. NSURL, below, requires a non-NULL resource-value pointer. */
    outputs.error = objectSlot();
    parsed = [formatter getObjectValue:NULL forString:@"1234.5"
        errorDescription:(NSString **)&outputs.error.value];
    check("formatter-null-result-success", parsed && intact(outputs.error));
    outputs.error = objectSlot();
    parsed = [formatter getObjectValue:NULL forString:@"not-a-number"
        errorDescription:(NSString **)&outputs.error.value];
    check("formatter-null-result-failure", !parsed &&
        [outputs.error.value isKindOfClass:[NSString class]] &&
        [outputs.error.value length] > 0 && intact(outputs.error));
    check("formatter-null-outputs-success", [formatter getObjectValue:NULL
        forString:@"1234.5" errorDescription:NULL]);
    check("formatter-null-outputs-failure", ![formatter getObjectValue:NULL
        forString:@"not-a-number" errorDescription:NULL]);

    NSAutoreleasePool *resultPool = [NSAutoreleasePool new];
    outputs.result = objectSlot();
    parsed = [formatter getObjectValue:&outputs.result.value
        forString:@"1234.5" errorDescription:NULL];
    id retainedResult = [outputs.result.value retain];
    [resultPool drain];
    check("formatter-retained-result", parsed && intact(outputs.result) &&
        [retainedResult isKindOfClass:[NSNumber class]] &&
        [retainedResult doubleValue] == 1234.5);
    [retainedResult release];
    [formatter release];
}

static void checkURL(void) {
    NSString *pathTemplate = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"lc32-object-out-XXXXXX"];
    char *path = strdup([pathTemplate UTF8String]);
    int descriptor = path ? mkstemp(path) : -1;
    check("url-temp-file", descriptor >= 0);
    if(descriptor < 0) {
        free(path);
        return;
    }

    const char contents[] = "object-output-test";
    const ssize_t written = write(descriptor, contents, sizeof(contents) - 1);
    const int closed = close(descriptor);
    check("url-temp-file-write",
        written == sizeof(contents) - 1 && closed == 0);
    NSString *filePath = [NSString stringWithUTF8String:path];
    NSURL *url = [NSURL fileURLWithPath:filePath];
    NSString *fileSizeKey = NSURLFileSizeKey;

    ObjectSlot value = objectSlot();
    ObjectSlot error = objectSlot();
    BOOL found = [url getResourceValue:&value.value forKey:fileSizeKey
        error:(NSError **)&error.value];
    check("url-success", found &&
        [value.value isKindOfClass:[NSNumber class]] &&
        [value.value unsignedIntegerValue] == sizeof(contents) - 1);
    check("url-success-width", intact(value) && intact(error));
    /* As with NSError ** APIs generally, do not inspect error on success. */

    value = objectSlot();
    found = [url getResourceValue:&value.value forKey:fileSizeKey
        error:NULL];
    check("url-null-error-success", found && intact(value) &&
        [value.value unsignedIntegerValue] == sizeof(contents) - 1);

    /* A child of our regular file cannot exist. This gives a deterministic
     * lookup failure without depending on an unrelated filesystem path. */
    NSString *missingPath = [filePath stringByAppendingPathComponent:@"missing"];
    NSAutoreleasePool *errorPool = [NSAutoreleasePool new];
    NSURL *missingURL = [NSURL fileURLWithPath:missingPath];
    value = objectSlot();
    error = objectSlot();
    found = [missingURL getResourceValue:&value.value forKey:fileSizeKey
        error:(NSError **)&error.value];
    check("url-error", !found &&
        [error.value isKindOfClass:[NSError class]] &&
        [[error.value localizedDescription] length] > 0);
    check("url-error-width", intact(value) && intact(error));
    NSError *retainedError = [error.value retain];

    value = objectSlot();
    found = [missingURL getResourceValue:&value.value forKey:fileSizeKey
        error:NULL];
    check("url-null-error-failure", !found && intact(value));
    [errorPool drain];
    check("url-retained-error", [retainedError isKindOfClass:[NSError class]] &&
        [[retainedError localizedDescription] length] > 0);
    [retainedError release];

    check("url-temp-file-cleanup", unlink(path) == 0);
    free(path);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    checkFormatter();
    checkURL();
    [pool drain];
    printf("object-out-parameters: %s (%u failures)\n",
        failures ? "FAIL" : "PASS", failures);
    return failures != 0;
}
