#import "Foundation+LC32.h"

@interface __SwiftNativeNSStringBase : NSString
@end
@implementation __SwiftNativeNSStringBase
@end

__attribute__((objc_runtime_name("Swift._NSCopying")))
@protocol LC32SwiftNSCopying
@end

__attribute__((objc_runtime_name("Swift.__SwiftNativeNSString")))
@interface LC32SwiftNativeNSString : __SwiftNativeNSStringBase
@end

@implementation LC32SwiftNativeNSString
@end

__attribute__((objc_runtime_name("Swift.__StringStorage")))
@interface LC32SwiftStringStorage : LC32SwiftNativeNSString <LC32SwiftNSCopying>
@end

@implementation LC32SwiftStringStorage
@end
