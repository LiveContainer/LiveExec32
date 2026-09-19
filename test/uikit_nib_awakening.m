#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdio.h>

static unsigned objectAwakeCount;
static unsigned buttonAwakeCount;

@interface LC32NibObject : NSObject
@end

@implementation LC32NibObject
- (void)awakeFromNib {
    objectAwakeCount++;
    [super awakeFromNib];
}
@end

@interface LC32NibButton : UIButton
@end

@implementation LC32NibButton
- (void)awakeFromNib {
    buttonAwakeCount++;
    [super awakeFromNib];
}
@end

static BOOL report(const char *name, BOOL passed) {
    printf("uikit-nib-awakening-%s: %s\n", name,
        passed ? "PASS" : "FAIL");
    return passed;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSObject *object = [NSObject new];
        UIButton *button = [[UIButton alloc] initWithFrame:CGRectZero];
        LC32NibObject *customObject = [LC32NibObject new];
        LC32NibButton *customButton = [[LC32NibButton alloc]
            initWithFrame:CGRectZero];

        /* UIKit's NSObject category must be inherited by both Foundation
         * objects and controls whose captured class lists omit the method. */
        BOOL passed = report("inherited-method",
            [object respondsToSelector:@selector(awakeFromNib)] &&
            [button respondsToSelector:@selector(awakeFromNib)]);
        [object awakeFromNib];
        [button awakeFromNib];
        [customObject awakeFromNib];
        [customButton awakeFromNib];
        passed &= report("guest-override-super",
            objectAwakeCount == 1 && buttonAwakeCount == 1);
        passed &= report("missing-optional-nib",
            [[NSBundle mainBundle] loadNibNamed:@"LC32MissingOptionalNib"
                owner:nil options:nil] == nil);

#if !__has_feature(objc_arc)
        [customButton release];
        [customObject release];
        [button release];
        [object release];
#endif
        printf("uikit-nib-awakening-regression: %s\n",
            passed ? "PASS" : "FAIL");
        return !passed;
    }
}
