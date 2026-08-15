#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSString *source = @"A\u00e9B";
    unsigned char bytes[16] = {};
    NSUInteger usedLength = NSUIntegerMax;
    NSRange remainingRange = NSMakeRange(NSNotFound, NSNotFound);

    BOOL converted = [source
        getBytes:bytes
        maxLength:sizeof(bytes)
        usedLength:&usedLength
        encoding:NSUTF8StringEncoding
        options:0
        range:NSMakeRange(0, source.length)
        remainingRange:&remainingRange];
    const unsigned char expected[] = {'A', 0xc3, 0xa9, 'B'};
    BOOL passed = converted && usedLength == sizeof(expected) &&
        memcmp(bytes, expected, sizeof(expected)) == 0 &&
        NSEqualRanges(remainingRange, NSMakeRange(source.length, 0));
    printf("string-get-bytes: %s\n", passed ? "PASS" : "FAIL");

    [pool drain];
    return !passed;
}
