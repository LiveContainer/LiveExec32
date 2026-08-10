#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

int main(void) {
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
    return !(bytesPassed && wholePassed && rangePassed);
}
