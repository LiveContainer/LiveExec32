#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

static unsigned failures;
static void check(const char *name, BOOL passed) {
    printf("attributed-initializer-%s: %s\n", name, passed ? "PASS" : "FAIL");
    failures += !passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        for(Class cls in @[[NSAttributedString class], [NSMutableAttributedString class]]) {
            NSAttributedString *plain = [[cls alloc] initWithString:@"video"];
            check("plain", [plain.string isEqual:@"video"] && plain.length == 5);
            NSAttributedString *empty = [[cls alloc] initWithString:@"" attributes:nil];
            check("empty-nil-attributes", empty != nil && empty.length == 0);
            NSAttributedString *styled = [[cls alloc] initWithString:@"title"
                attributes:@{@"probe": @42}];
            CFRange range = CFRangeMake(-1, -1);
            id attribute = (id)CFAttributedStringGetAttribute(
                (CFAttributedStringRef)styled, 0, CFSTR("probe"), &range);
            check("attributes", [styled.string isEqual:@"title"] &&
                [attribute isEqual:@42] && range.location == 0 && range.length == 5);
            NSAttributedString *copy = [[cls alloc] initWithAttributedString:styled];
            [styled release];
            check("copy-survives-original", [copy.string isEqual:@"title"] &&
                [(id)CFAttributedStringGetAttribute((CFAttributedStringRef)copy,
                    0, CFSTR("probe"), NULL) isEqual:@42]);
            if(cls == NSMutableAttributedString.class) {
                [(NSMutableAttributedString *)plain replaceCharactersInRange:NSMakeRange(0, 5)
                    withString:@"playing"];
                check("inherited-initializer-stays-mutable", [plain.string isEqual:@"playing"]);
            }
            [copy release];
            [empty release];
            [plain release];
        }
    }
    printf("attributed initializer regression: %s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
