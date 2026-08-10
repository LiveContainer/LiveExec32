#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LC32TraitTextField : UITextField
@end

@implementation LC32TraitTextField
@end

int main(void) {
    @autoreleasepool {
        UITextField *field =
            [[LC32TraitTextField alloc] initWithFrame:(CGRect){}];
        if(!field ||
           ![field respondsToSelector:@selector(setReturnKeyType:)]) {
            fprintf(stderr, "text-input-traits: missing setter\n");
            return 1;
        }

        field.returnKeyType = UIReturnKeyDone;
        field.keyboardType = UIKeyboardTypeEmailAddress;
        field.enablesReturnKeyAutomatically = YES;
        field.secureTextEntry = YES;

        if(field.returnKeyType != UIReturnKeyDone ||
           field.keyboardType != UIKeyboardTypeEmailAddress ||
           !field.enablesReturnKeyAutomatically ||
           !field.secureTextEntry) {
            fprintf(stderr, "text-input-traits: round trip failed\n");
            return 2;
        }

        printf("text-input-traits: PASS\n");
    }
    return 0;
}
