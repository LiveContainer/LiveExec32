#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface UIViewController : NSObject
@end
@interface UIScreenMode : NSObject
@property(nonatomic) CGSize pixels;
@property(nonatomic) CGSize applicationPixels;
@property(nonatomic) NSInteger lastLevel;
- (CGSize)size;
@end
@interface UIScreen : NSObject
@property(nonatomic) CGFloat testScale;
@property(nonatomic, strong) UIScreenMode *currentMode;
- (CGFloat)scale;
@end
