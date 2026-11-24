#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface LC32LegacyNibClasses : NSObject
@end

@implementation LC32LegacyNibClasses
+ (void)load {
    // Older nibs name this removed UIButton subclass directly. UINibDecoder
    // resolves classes through the runtime, not NSKeyedUnarchiver's class map.
    // UIButton decodes the archived UIButtonType and stateful content itself;
    // only the old runtime name is missing. Preserve UIKit's class if present.
    if(objc_lookUpClass("UIRoundedRectButton")) return;
    Class button = objc_allocateClassPair(UIButton.class, "UIRoundedRectButton", 0);
    if(button) objc_registerClassPair(button);
}
@end
