#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    const char constructorSource[] = "constructor";
    NSData *constructed = [NSData dataWithBytes:constructorSource
                                         length:sizeof(constructorSource) - 1];
    BOOL constructorPassed = constructed.length == 11 &&
        !memcmp(constructed.bytes, constructorSource, 11);
    printf("data-with-bytes: %s\n",
        constructorPassed ? "PASS" : "FAIL");

    NSData *data = [@"guest-data" dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = data.bytes;
    BOOL bytesPassed = data.length == 10 && bytes &&
        !memcmp(bytes, "guest-data", 10);
    printf("data-bytes: %s\n", bytesPassed ? "PASS" : "FAIL");

    char whole[10] = {0};
    [data getBytes:whole];
    BOOL wholePassed = !memcmp(whole, "guest-data", sizeof(whole));
    printf("data-get-bytes: %s\n", wholePassed ? "PASS" : "FAIL");

    char range[4] = {0};
    [data getBytes:range range:NSMakeRange(6, sizeof(range))];
    BOOL rangePassed = !memcmp(range, "data", sizeof(range));
    printf("data-get-range: %s\n", rangePassed ? "PASS" : "FAIL");

    const char mutableSource[] = "mutable-data";
    NSMutableData *mutable = [NSMutableData dataWithCapacity:16];
    [mutable appendBytes:mutableSource length:sizeof(mutableSource) - 1];
    NSData *subdata = [mutable subdataWithRange:NSMakeRange(2, 4)];
    BOOL subdataPassed = subdata.length == 4 && subdata.bytes &&
        !memcmp(subdata.bytes, "tabl", 4);
    printf("mutable-subdata-range: %s\n",
        subdataPassed ? "PASS" : "FAIL");

    [pool drain];
    return !(constructorPassed && bytesPassed && wholePassed && rangePassed &&
             subdataPassed);
}
