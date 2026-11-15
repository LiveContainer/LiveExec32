#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned failures;
static unsigned checks;

static void Check(const char *name, BOOL passed) {
    ++checks;
    failures += !passed;
    printf("%s: %s\n", name, passed ? "PASS" : "FAIL");
}

static BOOL HasCharacters(NSString *string, const unichar *characters,
                          NSUInteger length) {
    if(!string || string.length != length) return NO;
    for(NSUInteger i = 0; i < length; ++i) {
        if([string characterAtIndex:i] != characters[i]) return NO;
    }
    return YES;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        const unichar name[] = {'k', 'c', 'i', 'n', 'i'};
        NSString *string = [[NSString alloc] initWithCharacters:name length:5];
        Check("characters-extension-name", [string isEqualToString:@"kcini"]);
        [string release];
        // Safely reproduce the old scalar-pointer adapter without exercising
        // its no-copy variant, which could hand native free() guest storage.
        if(argc > 1 && !strcmp(argv[1], "--probe")) return failures != 0;

        // Counted UTF-16: no terminator, embedded NUL, supplementary character,
        // and unmatched surrogates. Do not decode through a byte encoding.
        const unichar units[] = {'A', 0, 0x03b1, 0xd83d, 0xde00, 0xd800,
                                 'B', 0xdc00, 0xfeff};
        const NSUInteger count = sizeof(units) / sizeof(*units);
        for(unsigned mutable = 0; mutable != 2; ++mutable) {
            Class cls = mutable ? NSMutableString.class : NSString.class;
            string = [[cls alloc] initWithCharacters:units length:count];
            Check(mutable ? "characters-mutable-init" : "characters-init",
                HasCharacters(string, units, count));
            if(mutable) {
                [(NSMutableString *)string appendString:@"!"];
                Check("characters-mutable-append", string.length == count + 1 &&
                    [string characterAtIndex:count] == '!');
            }
            [string release];

            string = [cls stringWithCharacters:units length:count];
            Check(mutable ? "characters-mutable-factory" : "characters-factory",
                HasCharacters(string, units, count));
            if(mutable) {
                [(NSMutableString *)string appendString:@"!"];
                Check("characters-mutable-factory-append",
                    string.length == count + 1);
            }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
            string = [[cls alloc] initWithCharacters:NULL length:0];
#pragma clang diagnostic pop
            Check("characters-empty-null", string && string.length == 0);
            [string release];
            string = [cls stringWithCharacters:units length:0];
            Check("characters-empty-buffer", string && string.length == 0);

            for(unsigned transfer = 0; transfer != 2; ++transfer) {
                unichar *owned = malloc(sizeof(units));
                if(!owned) return 2;
                memcpy(owned, units, sizeof(units));
                string = [[cls alloc] initWithCharactersNoCopy:owned
                    length:count freeWhenDone:transfer];
                Check(transfer ? "characters-no-copy-owned" :
                                 "characters-no-copy-borrowed",
                    HasCharacters(string, units, count));
                [string release];
                if(!transfer) {
                    Check("characters-borrowed-buffer-retained",
                        !memcmp(owned, units, sizeof(units)));
                    free(owned);
                }
            }
        }

        const NSUInteger largeCount = 10000;
        unichar *large = malloc(largeCount * sizeof(*large));
        if(!large) return 2;
        for(NSUInteger i = 0; i < largeCount; ++i) large[i] = 'A' + i % 26;
        string = [[NSString alloc] initWithCharacters:large length:largeCount];
        Check("characters-multipage", HasCharacters(string, large, largeCount));
        large[0] = '!';
        free(large);
        Check("characters-input-copied", string.length == largeCount &&
            [string characterAtIndex:0] == 'A' &&
            [string characterAtIndex:largeCount - 1] == 'A' + (largeCount - 1) % 26);
        [string release];
        printf("characters: %u checks, %u failures\n", checks, failures);
        return failures != 0;
    }
}
