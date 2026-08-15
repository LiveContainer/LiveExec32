#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NSString (LC32PrivateByteConstruction)
+ (instancetype)stringWithBytes:(const void *)bytes
                         length:(NSUInteger)length
                       encoding:(NSStringEncoding)encoding;
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    const unsigned char embeddedNUL[] = {'A', 0, 'B'};
    NSString *utf8 = [[NSString alloc]
        initWithBytes:embeddedNUL
               length:sizeof(embeddedNUL)
             encoding:NSUTF8StringEncoding];
    BOOL utf8Passed = utf8 && utf8.length == 3 &&
        [utf8 characterAtIndex:0] == 'A' &&
        [utf8 characterAtIndex:1] == 0 &&
        [utf8 characterAtIndex:2] == 'B';
    printf("string-bytes-embedded-nul: %s\n",
           utf8Passed ? "PASS" : "FAIL");
    [utf8 release];

    const unsigned char latin1Bytes[] = {0x41, 0xe9};
    NSString *latin1 = [NSString stringWithBytes:latin1Bytes
                                          length:sizeof(latin1Bytes)
                                        encoding:NSISOLatin1StringEncoding];
    BOOL latin1Passed = latin1 && latin1.length == 2 &&
        [latin1 characterAtIndex:0] == 'A' &&
        [latin1 characterAtIndex:1] == 0x00e9;
    printf("string-bytes-latin1: %s\n",
           latin1Passed ? "PASS" : "FAIL");

    unichar characters[2] = {};
    [latin1 getCharacters:characters range:NSMakeRange(0, 2)];
    BOOL charactersPassed = characters[0] == 'A' &&
        characters[1] == 0x00e9;
    printf("string-get-characters-range: %s\n",
           charactersPassed ? "PASS" : "FAIL");

    unichar allCharacters[2] = {};
    [latin1 getCharacters:allCharacters];
    BOOL allCharactersPassed = allCharacters[0] == 'A' &&
        allCharacters[1] == 0x00e9;
    printf("string-get-characters-all: %s\n",
           allCharactersPassed ? "PASS" : "FAIL");

    char *ownedBytes = malloc(6);
    memcpy(ownedBytes, "owned", 6);
    NSString *owned = [[NSString alloc]
        initWithBytesNoCopy:ownedBytes
                     length:5
                   encoding:NSUTF8StringEncoding
               freeWhenDone:YES];
    BOOL noCopyPassed = [owned isEqualToString:@"owned"];
    printf("string-bytes-no-copy-owned: %s\n",
           noCopyPassed ? "PASS" : "FAIL");
    [owned release];

    [pool drain];
    return !(utf8Passed && latin1Passed && charactersPassed &&
             allCharactersPassed && noCopyPassed);
}
